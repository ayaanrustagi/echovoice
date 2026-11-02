import CoreGraphics
import Foundation
import simd

/// Coordinate-mapping tests for the hands-free signals.
///
/// Each test builds an ARKit-shaped face transform from a *physical*
/// description — "the head turns toward the screen's right edge" — using the
/// axis conventions Apple documents, and checks the signal moves the cursor
/// the way a person would expect. This verifies the whole chain of axis
/// conversions, orientations, and signs. It cannot verify that a particular
/// iPhone honours Apple's documentation; that needs the on-device Signal Check.
@main
enum GazeSignalsSmoke {
    static let orientations = GazeScreenOrientation.allCases

    static func main() {
        roundTripsEveryOrientation()
        neutralFaceIsAProperRotation()
        headTurnsMoveTheCursorTheSameWay()
        eyeTransformRaysFollowTheEyes()
        lookAtPointSignMatchesAppleDocumentation()
        blendShapesFollowDocumentedMeaning()
        raysThatMissTheScreenAreRejected()
        defaultMappingCentersOnNeutral()
        screenMappingRoundTrips()
        deviceFaceBehindNegativeZIsNormalized()
        print("Gaze signal mapping smoke tests passed")
    }

    // MARK: Physical model

    /// Screen frame used by the tests: +x right, +y down, +z toward the person.
    /// A face squarely facing the screen has its own axes pointing: +x (its
    /// left) toward the screen's left, +y (up) toward the screen's top, and +z
    /// (out of the face) toward the device.
    static func faceInCamera(
        position: SIMD3<Float> = SIMD3(0, 0.06, 0.35),
        turnRight yaw: Float = 0,
        chinDown pitch: Float = 0,
        orientation: GazeScreenOrientation
    ) -> simd_float4x4 {
        var faceX = SIMD3<Float>(-1, 0, 0)
        var faceY = SIMD3<Float>(0, -1, 0)
        var faceZ = SIMD3<Float>(0, 0, -1)
        // Chin down: the nose tips toward the bottom edge, the top of the head
        // toward the device.
        func pitchRotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(v.x, v.y * cos(pitch) - v.z * sin(pitch), v.y * sin(pitch) + v.z * cos(pitch))
        }
        // Turn right: the nose swings toward the right edge.
        func yawRotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(v.x * cos(yaw) - v.z * sin(yaw), v.y, v.x * sin(yaw) + v.z * cos(yaw))
        }
        faceX = yawRotate(pitchRotate(faceX))
        faceY = yawRotate(pitchRotate(faceY))
        faceZ = yawRotate(pitchRotate(faceZ))
        precondition(abs(faceZ.x - sin(yaw) * cos(pitch)) < 1e-5, "yaw model sanity")

        func camera(_ v: SIMD3<Float>) -> SIMD4<Float> {
            SIMD4(GazeGeometry.cameraVector(fromScreen: v, orientation: orientation), 0)
        }
        var position4 = camera(position)
        position4.w = 1
        return simd_float4x4(columns: (camera(faceX), camera(faceY), camera(faceZ), position4))
    }

    /// An eye transform in face space, rotated so the pupil turns toward the
    /// face's own right (screen right) by `right` and down by `down`.
    static func eye(at origin: SIMD3<Float>, right: Float = 0, down: Float = 0) -> simd_float4x4 {
        // Face space: +x is the face's left, so "toward screen right" is −x;
        // +y is up, so "down" is −y. The pupil looks along +z when neutral.
        let direction = simd_normalize(SIMD3<Float>(-tan(right), -tan(down), 1))
        let up = SIMD3<Float>(0, 1, 0)
        let xAxis = simd_normalize(simd_cross(up, direction))
        let yAxis = simd_cross(direction, xAxis)
        return simd_float4x4(columns: (
            SIMD4(xAxis, 0), SIMD4(yAxis, 0), SIMD4(direction, 0), SIMD4(origin, 1)
        ))
    }

    static func sample(
        face: simd_float4x4,
        eyesRight: Float = 0,
        eyesDown: Float = 0,
        lookAt: SIMD3<Float> = SIMD3(0, 0.02, 0.4)
    ) -> FaceSample {
        FaceSample(
            faceInCamera: face,
            leftEye: eye(at: SIMD3(0.03, 0.02, 0.02), right: eyesRight, down: eyesDown),
            rightEye: eye(at: SIMD3(-0.03, 0.02, 0.02), right: eyesRight, down: eyesDown),
            lookAtPoint: lookAt,
            timestamp: 0
        )
    }

    // MARK: Tests

    /// The real front camera reports the face at negative z. After
    /// `facingViewer`, it must produce the same signals as the +z model, and a
    /// face already at +z must pass through untouched.
    static func deviceFaceBehindNegativeZIsNormalized() {
        let flipZ = simd_float4x4(diagonal: SIMD4<Float>(1, 1, -1, 1))
        for orientation in orientations {
            let model = faceInCamera(turnRight: 0.15, chinDown: 0.1, orientation: orientation)
            precondition(GazeGeometry.facingViewer(model) == model, "a +z face must not change")

            let device = flipZ * model
            precondition(device.columns.3.z < 0, "test setup: device face should be at -z")
            let fixed = GazeGeometry.facingViewer(device)
            let expected = GazeSignalExtractor.signals(from: sample(face: model, eyesRight: 0.1), orientation: orientation)
            let actual = GazeSignalExtractor.signals(from: sample(face: fixed, eyesRight: 0.1), orientation: orientation)
            precondition(actual.headPose != nil && actual.eyeTransform != nil && actual.lookAtPoint != nil,
                         "normalized device face must produce head, eye, and lookAt signals (\(orientation))")
            precondition(actual == expected, "normalized device face must match the model (\(orientation))")

            let broken = GazeSignalExtractor.signals(from: sample(face: device, eyesRight: 0.1), orientation: orientation)
            precondition(broken.headPose == nil && broken.lookAtPoint == nil,
                         "test setup: an un-normalized -z face should yield no signals, as seen on device")
        }
    }

    static func roundTripsEveryOrientation() {
        let v = SIMD3<Float>(0.1, -0.2, 0.3)
        for orientation in orientations {
            let back = GazeGeometry.screenVector(
                fromCamera: GazeGeometry.cameraVector(fromScreen: v, orientation: orientation),
                orientation: orientation
            )
            precondition(simd_length(back - v) < 1e-6, "round trip failed for \(orientation)")
        }
    }

    /// The documented face axes plus the documented camera axes must form a
    /// proper rotation (determinant +1). A mirrored screen/camera mapping would
    /// give −1 — the kind of silent sign error that reverses a cursor.
    static func neutralFaceIsAProperRotation() {
        for orientation in orientations {
            let m = faceInCamera(orientation: orientation)
            let rotation = simd_float3x3(
                SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
            )
            precondition(abs(simd_determinant(rotation) - 1) < 1e-5, "face frame is mirrored in \(orientation)")
        }
    }

    static func headTurnsMoveTheCursorTheSameWay() {
        let turn: Float = 0.2
        for orientation in orientations {
            func head(_ yaw: Float, _ pitch: Float) -> CGPoint {
                let s = sample(face: faceInCamera(turnRight: yaw, chinDown: pitch, orientation: orientation))
                guard let p = GazeSignalExtractor.headPose(s, orientation: orientation) else {
                    preconditionFailure("no head pose for \(orientation)")
                }
                return p
            }
            let center = head(0, 0)
            precondition(abs(center.x) < 1e-5 && abs(center.y) < 1e-5, "facing the screen should read (0, 0) in \(orientation)")
            precondition(head(turn, 0).x > 0.15, "turning right should move right in \(orientation)")
            precondition(head(-turn, 0).x < -0.15, "turning left should move left in \(orientation)")
            precondition(head(0, turn).y > 0.15, "chin down should move down in \(orientation)")
            precondition(head(0, -turn).y < -0.15, "chin up should move up in \(orientation)")
            // A pure turn should not leak into the other axis.
            precondition(abs(head(turn, 0).y) < 1e-4 && abs(head(0, turn).x) < 1e-4, "axis leak in \(orientation)")
            precondition(abs(head(turn, 0).x - CGFloat(turn)) < 1e-4, "yaw should read in radians")
        }
    }

    static func eyeTransformRaysFollowTheEyes() {
        for orientation in orientations {
            let face = faceInCamera(orientation: orientation)
            func point(_ right: Float, _ down: Float) -> CGPoint {
                guard let p = GazeSignalExtractor.eyeTransformPoint(sample(face: face, eyesRight: right, eyesDown: down), orientation: orientation) else {
                    preconditionFailure("eye ray missed the screen in \(orientation)")
                }
                return p
            }
            let center = point(0, 0)
            precondition(point(0.15, 0).x > center.x + 0.02, "eyes right should move right in \(orientation)")
            precondition(point(-0.15, 0).x < center.x - 0.02, "eyes left should move left in \(orientation)")
            precondition(point(0, 0.15).y > center.y + 0.02, "eyes down should move down in \(orientation)")
            precondition(point(0, -0.15).y < center.y - 0.02, "eyes up should move up in \(orientation)")
        }
        // Head and eyes add: turning the head right with the eyes still in
        // their sockets moves the gaze point right too.
        let turned = faceInCamera(turnRight: 0.15, orientation: .portrait)
        let still = faceInCamera(orientation: .portrait)
        let a = GazeSignalExtractor.eyeTransformPoint(sample(face: turned), orientation: .portrait)!
        let b = GazeSignalExtractor.eyeTransformPoint(sample(face: still), orientation: .portrait)!
        precondition(a.x > b.x + 0.02, "eye-transform gaze should include head rotation")
    }

    /// Apple: "If the user is looking to the left, the vector has a positive
    /// x-axis component." Looking to one's own left is looking at the screen's
    /// left edge, so +x in face space must move the cursor left.
    static func lookAtPointSignMatchesAppleDocumentation() {
        for orientation in orientations {
            let face = faceInCamera(orientation: orientation)
            let ahead = GazeSignalExtractor.lookAtPlanePoint(sample(face: face, lookAt: SIMD3(0, 0.02, 0.4)), orientation: orientation)!
            let lookingLeft = GazeSignalExtractor.lookAtPlanePoint(sample(face: face, lookAt: SIMD3(0.12, 0.02, 0.4)), orientation: orientation)!
            let lookingUp = GazeSignalExtractor.lookAtPlanePoint(sample(face: face, lookAt: SIMD3(0, 0.14, 0.4)), orientation: orientation)!
            precondition(lookingLeft.x < ahead.x - 0.01, "positive lookAtPoint.x must move the cursor left in \(orientation)")
            precondition(abs(lookingLeft.y - ahead.y) < 1e-4, "horizontal look should not move vertically in \(orientation)")
            precondition(lookingUp.y < ahead.y - 0.01, "positive lookAtPoint.y must move the cursor up in \(orientation)")
        }
    }

    /// Apple: eyeLookInLeft and eyeLookOutRight are "consistent with a
    /// rightward gaze"; eyeLookUp is upward.
    static func blendShapesFollowDocumentedMeaning() {
        var s = sample(face: faceInCamera(orientation: .portrait))
        s.eyeLookInLeft = 0.6
        s.eyeLookOutRight = 0.6
        precondition(GazeSignalExtractor.blendShape(s).x > 0.5, "rightward blend shapes should move right")
        s = sample(face: faceInCamera(orientation: .portrait))
        s.eyeLookOutLeft = 0.6
        s.eyeLookInRight = 0.6
        precondition(GazeSignalExtractor.blendShape(s).x < -0.5, "leftward blend shapes should move left")
        s = sample(face: faceInCamera(orientation: .portrait))
        s.eyeLookUpLeft = 0.4
        s.eyeLookUpRight = 0.4
        precondition(GazeSignalExtractor.blendShape(s).y < -0.3, "upward blend shapes should move up")
    }

    static func raysThatMissTheScreenAreRejected() {
        // Heading away from the device.
        precondition(GazeGeometry.intersectDevicePlane(origin: SIMD3(0, 0, 0.3), direction: SIMD3(0, 0, 1)) == nil)
        // Nearly parallel to the screen.
        precondition(GazeGeometry.intersectDevicePlane(origin: SIMD3(0, 0, 0.3), direction: SIMD3(1, 0, -0.1)) == nil)
        // Straight at it lands at the origin.
        let hit = GazeGeometry.intersectDevicePlane(origin: SIMD3(0.01, 0.02, 0.3), direction: SIMD3(0, 0, -1))!
        precondition(simd_length(hit - SIMD3(0.01, 0.02, 0)) < 1e-6)
        // Head turned fully away yields no head pose.
        let away = faceInCamera(turnRight: .pi * 0.49, orientation: .portrait)
        precondition(GazeSignalExtractor.headPose(sample(face: away), orientation: .portrait) == nil)
    }

    static func defaultMappingCentersOnNeutral() {
        let neutral = CGPoint(x: 0.05, y: -0.03)
        let center = DefaultGazeMapping.normalizedPoint(raw: neutral, neutral: neutral, source: .headPose, sensitivity: 6)
        precondition(center == CGPoint(x: 0.5, y: 0.5))
        let range = DefaultGazeMapping.halfRange(for: .headPose)
        let edge = DefaultGazeMapping.normalizedPoint(
            raw: CGPoint(x: neutral.x + range.width, y: neutral.y - range.height),
            neutral: neutral, source: .headPose, sensitivity: 6
        )
        precondition(abs(edge.x - 0.86) < 1e-6 && abs(edge.y - 0.14) < 1e-6, "half-range should reach the calibration edge")
        let far = DefaultGazeMapping.normalizedPoint(raw: CGPoint(x: 9, y: -9), neutral: neutral, source: .headPose, sensitivity: 6)
        precondition(far == CGPoint(x: 1, y: 0), "default mapping must clamp")
    }

    static func screenMappingRoundTrips() {
        let areas = [
            CGRect(x: 0, y: 47, width: 390, height: 763),
            CGRect(x: 0, y: 24, width: 834, height: 1150),
            CGRect(x: 0, y: 24, width: 1194, height: 790),
            CGRect(x: 0, y: 24, width: 1024, height: 1322),
            CGRect(x: 0, y: 24, width: 1366, height: 980),
            CGRect(x: 0, y: 24, width: 320, height: 980),
            CGRect(x: 0, y: 24, width: 507, height: 980),
            CGRect(x: 32, y: 24, width: 678, height: 790)
        ]
        for area in areas {
            for p in [CGPoint(x: 0.14, y: 0.84), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.86, y: 0.16)] {
                let window = GazeScreenMapping.windowPoint(forNormalized: p, in: area)
                let back = GazeScreenMapping.normalizedPoint(forWindow: window, in: area)
                precondition(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
                precondition(area.contains(window), "Calibration and cursor must stay inside the live window")
            }
            let clamped = GazeScreenMapping.clamp(CGPoint(x: -50, y: 2000), to: area)
            precondition(clamped == CGPoint(x: area.minX + 12, y: area.maxY - 12))
        }
    }
}
