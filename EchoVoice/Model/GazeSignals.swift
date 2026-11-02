import CoreGraphics
import Foundation
import simd

// MARK: - Coordinate conventions
//
// Every signal below is reported in *screen axes as the person sees the
// screen*: +x toward the right edge, +y toward the bottom edge. That is the
// UIKit direction, so a larger x or y means the cursor should move right or
// down. Converting into these axes happens exactly once, here, so no caller
// ever has to guess which way an ARKit axis points.
//
// The ARKit frames involved (from Apple's documentation):
//
// * Face space (`ARFaceAnchor`): origin behind the face, +x toward the face's
//   own left (the viewer's right), +y up relative to the face, +z out of the
//   face toward the viewer — here, toward the device. `lookAtPoint` is in this
//   space and "has a positive x-axis component" when the person looks to
//   their left.
// * Camera space (`ARCamera.transform`): fixed to the device, independent of
//   interface orientation. +x runs along the long axis from the front camera
//   toward the Home button (down the screen in portrait), +y is up in
//   landscape-left device orientation (toward the screen's right edge in
//   portrait), and +z points out of the screen toward the person.
//
// Face transforms are converted into camera space before use (see
// `EyeGazeManager`), so a device that moves or tilts on its mount changes the
// signal only as much as the head-to-screen relationship changes.
//
// These conventions are documented, not measured. Calibration therefore
// detects each axis's direction and gain from what the person actually does,
// and the Signal Check tool reports whether a device agrees with them.

/// Interface orientation, mirrored as a plain value so mapping stays testable
/// without UIKit.
enum GazeScreenOrientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

/// The ways one ARKit face frame can become a pointing signal.
enum GazeSignalSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Where the head points: yaw and pitch toward the screen, in radians.
    case headPose
    /// Both eyes' pupil rays (`leftEyeTransform`/`rightEyeTransform`),
    /// intersected with the device plane, in meters. Head plus eye movement.
    case eyeTransform
    /// The ray toward `lookAtPoint`, intersected with the device plane, in
    /// meters. Head plus eye movement, as ARKit estimates it.
    case lookAtPoint
    /// Eyelid blend shapes (`eyeLookIn/Out/Up/Down`). Eye-in-head only, so a
    /// head movement does not move it. Unitless coefficients.
    case blendShape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .headPose: return String(localized: "Head pose")
        case .eyeTransform: return String(localized: "Eye transforms")
        case .lookAtPoint: return String(localized: "Look-at point")
        case .blendShape: return String(localized: "Eye blend shapes")
        }
    }

    /// The sources an access mode may calibrate against.
    static func candidates(forHeadMode isHead: Bool) -> [GazeSignalSource] {
        isHead ? [.headPose] : [.eyeTransform, .lookAtPoint, .blendShape]
    }
}

/// The raw inputs taken from one `ARFaceAnchor`, as plain values.
///
/// Built from the anchor on ARKit's callback thread and handed to the main
/// actor, so no `ARFrame` or `ARAnchor` is retained past its callback.
struct FaceSample: Sendable {
    /// The face anchor's transform in camera space.
    var faceInCamera: simd_float4x4
    /// Eye transforms relative to the face anchor.
    var leftEye: simd_float4x4
    var rightEye: simd_float4x4
    /// ARKit's gaze focus estimate, in face space.
    var lookAtPoint: SIMD3<Float>

    var eyeLookInLeft: Float = 0
    var eyeLookOutLeft: Float = 0
    var eyeLookUpLeft: Float = 0
    var eyeLookDownLeft: Float = 0
    var eyeLookInRight: Float = 0
    var eyeLookOutRight: Float = 0
    var eyeLookUpRight: Float = 0
    var eyeLookDownRight: Float = 0
    var eyeBlinkLeft: Float = 0
    var eyeBlinkRight: Float = 0

    /// ARKit keeps delivering an anchor for a face it has lost, marked
    /// untracked, with a stale pose. Such a sample must not move anything.
    var isTracked: Bool = true
    var timestamp: TimeInterval

    /// Distance from the device to the face, in meters. The length of the
    /// translation, so it is positive whichever way the camera's z axis points
    /// (ARKit's camera looks down -z, which made the raw z negative on device).
    var faceDistance: Float {
        let t = faceInCamera.columns.3
        return simd_length(SIMD3(t.x, t.y, t.z))
    }
}

/// One frame's worth of every signal, all in screen axes.
struct GazeSignalSet: Equatable, Sendable {
    var headPose: CGPoint?
    var eyeTransform: CGPoint?
    var lookAtPoint: CGPoint?
    var blendShape: CGPoint?

    subscript(source: GazeSignalSource) -> CGPoint? {
        switch source {
        case .headPose: return headPose
        case .eyeTransform: return eyeTransform
        case .lookAtPoint: return lookAtPoint
        case .blendShape: return blendShape
        }
    }
}

enum GazeGeometry {
    /// Re-express a camera-space vector in screen axes (+x right, +y down,
    /// +z toward the person) for the given interface orientation.
    static func screenVector(fromCamera v: SIMD3<Float>, orientation: GazeScreenOrientation) -> SIMD3<Float> {
        switch orientation {
        case .portrait:
            // Camera +y is the screen's right edge, camera +x its bottom.
            return SIMD3(v.y, v.x, v.z)
        case .portraitUpsideDown:
            return SIMD3(-v.y, -v.x, v.z)
        case .landscapeRight:
            // Home button (camera +x) on the right; camera +y is the top.
            return SIMD3(v.x, -v.y, v.z)
        case .landscapeLeft:
            // Home button on the left; camera +y is the bottom.
            return SIMD3(-v.x, v.y, v.z)
        }
    }

    /// Put the face in front of the camera at +z, the convention every signal
    /// below assumes (+z toward the person).
    ///
    /// On a real iPhone ARKit's front camera looks down its −z axis, so the
    /// face arrives at negative z. Left alone, every ray then "started behind
    /// the screen" and every head pose "faced away", so all signals were nil
    /// and readiness never got past weak tracking. Only z is flipped: if that
    /// leaves x or y reversed relative to the screen, calibration measures each
    /// axis's direction and absorbs it. A face already at +z is returned as is.
    static func facingViewer(_ faceInCamera: simd_float4x4) -> simd_float4x4 {
        guard faceInCamera.columns.3.z < 0 else { return faceInCamera }
        let flipZ = simd_float4x4(diagonal: SIMD4<Float>(1, 1, -1, 1))
        return flipZ * faceInCamera
    }

    /// The inverse of `screenVector(fromCamera:orientation:)`.
    static func cameraVector(fromScreen s: SIMD3<Float>, orientation: GazeScreenOrientation) -> SIMD3<Float> {
        switch orientation {
        case .portrait: return SIMD3(s.y, s.x, s.z)
        case .portraitUpsideDown: return SIMD3(-s.y, -s.x, s.z)
        case .landscapeRight: return SIMD3(s.x, -s.y, s.z)
        case .landscapeLeft: return SIMD3(-s.x, s.y, s.z)
        }
    }

    /// Where a ray from the face meets the device plane (camera-space z = 0).
    ///
    /// Returns nil unless the ray starts in front of the screen and heads
    /// toward it — a ray pointing away never meets the screen, and one nearly
    /// parallel to it would put the point wildly off to the side.
    static func intersectDevicePlane(origin: SIMD3<Float>, direction: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(direction)
        guard origin.z > 0.05, length > 0, direction.z / length < -0.3 else { return nil }
        let t = -origin.z / direction.z
        return origin + t * direction
    }

    static func transformPoint(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = m * SIMD4<Float>(p, 1)
        return SIMD3(r.x, r.y, r.z)
    }

    static func transformDirection(_ m: simd_float4x4, _ d: SIMD3<Float>) -> SIMD3<Float> {
        let r = m * SIMD4<Float>(d, 0)
        return SIMD3(r.x, r.y, r.z)
    }
}

enum GazeSignalExtractor {
    static func signals(from sample: FaceSample, orientation: GazeScreenOrientation) -> GazeSignalSet {
        GazeSignalSet(
            headPose: headPose(sample, orientation: orientation),
            eyeTransform: eyeTransformPoint(sample, orientation: orientation),
            lookAtPoint: lookAtPlanePoint(sample, orientation: orientation),
            blendShape: blendShape(sample)
        )
    }

    /// Yaw and pitch of the face's forward axis toward the screen.
    ///
    /// Face +z points from the face toward the device, which is camera −z
    /// when someone faces the screen squarely, so "straight at the screen" is
    /// (0, 0). Turning toward the right edge gives +x; tipping the chin down
    /// gives +y.
    static func headPose(_ sample: FaceSample, orientation: GazeScreenOrientation) -> CGPoint? {
        let forward = SIMD3<Float>(
            sample.faceInCamera.columns.2.x,
            sample.faceInCamera.columns.2.y,
            sample.faceInCamera.columns.2.z
        )
        let s = GazeGeometry.screenVector(fromCamera: simd_normalize(forward), orientation: orientation)
        let towardScreen = -s.z
        guard towardScreen > 0.2 else { return nil }
        return CGPoint(x: CGFloat(atan2(s.x, towardScreen)), y: CGFloat(atan2(s.y, towardScreen)))
    }

    /// The average of both pupil rays, where they meet the device plane.
    static func eyeTransformPoint(_ sample: FaceSample, orientation: GazeScreenOrientation) -> CGPoint? {
        let face = sample.faceInCamera
        func origin(_ eye: simd_float4x4) -> SIMD3<Float> {
            GazeGeometry.transformPoint(face, SIMD3(eye.columns.3.x, eye.columns.3.y, eye.columns.3.z))
        }
        func direction(_ eye: simd_float4x4) -> SIMD3<Float> {
            // The eye's +z axis points from the eyeball's center through the pupil.
            simd_normalize(GazeGeometry.transformDirection(face, SIMD3(eye.columns.2.x, eye.columns.2.y, eye.columns.2.z)))
        }
        let rayOrigin = (origin(sample.leftEye) + origin(sample.rightEye)) / 2
        let rayDirection = direction(sample.leftEye) + direction(sample.rightEye)
        guard let hit = GazeGeometry.intersectDevicePlane(origin: rayOrigin, direction: rayDirection) else { return nil }
        let s = GazeGeometry.screenVector(fromCamera: hit, orientation: orientation)
        return CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
    }

    /// The ray from between the eyes toward `lookAtPoint`, where it meets the
    /// device plane.
    static func lookAtPlanePoint(_ sample: FaceSample, orientation: GazeScreenOrientation) -> CGPoint? {
        let face = sample.faceInCamera
        let leftOrigin = SIMD3(sample.leftEye.columns.3.x, sample.leftEye.columns.3.y, sample.leftEye.columns.3.z)
        let rightOrigin = SIMD3(sample.rightEye.columns.3.x, sample.rightEye.columns.3.y, sample.rightEye.columns.3.z)
        let eyesMid = (leftOrigin + rightOrigin) / 2
        let originCamera = GazeGeometry.transformPoint(face, eyesMid)
        let targetCamera = GazeGeometry.transformPoint(face, sample.lookAtPoint)
        guard let hit = GazeGeometry.intersectDevicePlane(origin: originCamera, direction: targetCamera - originCamera) else { return nil }
        let s = GazeGeometry.screenVector(fromCamera: hit, orientation: orientation)
        return CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
    }

    /// Eye-in-head direction from the eyelid blend shapes.
    ///
    /// Apple documents `eyeLookInLeft` and `eyeLookOutRight` as "consistent
    /// with a rightward gaze", and the Out-Left/In-Right pair as leftward. The
    /// blend shapes describe the face, so they do not depend on interface
    /// orientation.
    static func blendShape(_ sample: FaceSample) -> CGPoint {
        let rightward = (sample.eyeLookInLeft + sample.eyeLookOutRight) - (sample.eyeLookOutLeft + sample.eyeLookInRight)
        let downward = (sample.eyeLookDownLeft + sample.eyeLookDownRight) - (sample.eyeLookUpLeft + sample.eyeLookUpRight)
        return CGPoint(x: CGFloat(rightward / 2), y: CGFloat(downward / 2))
    }
}

/// Mapping used before a person has calibrated.
///
/// Each source's half-range is the raw distance from the neutral pose that
/// should carry the cursor to the edge of the calibration area at the default
/// sensitivity. They are deliberately modest starting points, not a claim of
/// accuracy: uncalibrated eye gaze is too person-specific to select with, and
/// the app does not let it.
enum DefaultGazeMapping {
    static let edgeOffset: CGFloat = 0.36   // 0.5 ± 0.36 = the 0.14 / 0.86 calibration targets

    static func halfRange(for source: GazeSignalSource) -> CGSize {
        switch source {
        case .headPose: return CGSize(width: 0.26, height: 0.17)       // ≈ 15° and 10°
        case .eyeTransform, .lookAtPoint: return CGSize(width: 0.035, height: 0.06)
        case .blendShape: return CGSize(width: 0.30, height: 0.25)
        }
    }

    static func normalizedPoint(raw: CGPoint, neutral: CGPoint, source: GazeSignalSource, sensitivity: Double) -> CGPoint {
        let range = halfRange(for: source)
        let gain = CGFloat(max(0.2, sensitivity) / 6.0)
        func axis(_ value: CGFloat, _ center: CGFloat, _ half: CGFloat) -> CGFloat {
            min(max(0.5 + edgeOffset * gain * (value - center) / half, 0), 1)
        }
        return CGPoint(x: axis(raw.x, neutral.x, range.width), y: axis(raw.y, neutral.y, range.height))
    }
}

/// The 0...1 area gaze is mapped into, and back, in window points.
///
/// Calibration, the accuracy check, and the live cursor all go through this
/// one function, so a target drawn at a normalized point and the cursor
/// produced by looking at it can never disagree about where that point is.
enum GazeScreenMapping {
    static func windowPoint(forNormalized p: CGPoint, in area: CGRect) -> CGPoint {
        CGPoint(x: area.minX + p.x * area.width, y: area.minY + p.y * area.height)
    }

    static func normalizedPoint(forWindow p: CGPoint, in area: CGRect) -> CGPoint {
        guard area.width > 0, area.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: (p.x - area.minX) / area.width, y: (p.y - area.minY) / area.height)
    }

    /// Keep the cursor inside the area, a small margin from its edges.
    static func clamp(_ p: CGPoint, to area: CGRect, margin: CGFloat = 12) -> CGPoint {
        let inset = area.insetBy(dx: min(margin, area.width / 2), dy: min(margin, area.height / 2))
        return CGPoint(x: min(max(p.x, inset.minX), inset.maxX), y: min(max(p.y, inset.minY), inset.maxY))
    }
}
