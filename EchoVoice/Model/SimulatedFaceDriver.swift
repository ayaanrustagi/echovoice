#if DEBUG && os(iOS)
import CoreGraphics
import Foundation
import simd

/// A scripted "person" for the simulator, which has no TrueDepth camera.
///
/// It builds `FaceSample`s from a physical description — head turned this
/// far, eyes rotated that far — using the same documented ARKit conventions
/// as the tests, and feeds them through the real pipeline: signal
/// extraction, calibration, filtering, dwell, and blink gestures. That makes
/// every screen of hands-free setup exercisable and screenshot-able in the
/// simulator. It proves the app is internally consistent; it cannot prove a
/// real iPhone agrees with Apple's documentation. Debug builds only.
///
/// Launch with `-EchoVoiceSimulateFace <script>` (and `-EchoVoiceSimulateEnable`
/// to switch hands-free on). The script joins parts with `+`:
///   follow        look wherever `debugAimPoint` asks (calibration targets)
///   tour          center, left, right, up, down, repeating
///   point=X,Y     hold one normalized screen point
///   blinkNatural  ordinary blinking, about every three seconds
///   blinkHelp     five quick blinks, then a held closure
///   reversedX     a person/device whose horizontal signal runs backwards
///   lose=T        the face leaves the camera at T seconds for two seconds
///   remote        steer the person live from `Documents/simface.txt`, one
///                 line "ID X Y [help]": look at normalized point X,Y, and
///                 when ID changes with "help", do the blink-HELP gesture.
///                 For recording demos.
@MainActor
final class SimulatedFaceDriver {
    typealias Context = () -> (aim: CGPoint?, isHead: Bool, orientation: GazeScreenOrientation)?

    private var parts: Set<String> = []
    private var fixedPoint: CGPoint?
    private var loseAt: TimeInterval?
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    /// Current head and eye angles (radians), which chase the aim point.
    private var head = CGPoint.zero
    private var eyes = CGPoint.zero
    /// Where the person was aiming on the last frame, for logs.
    private(set) var lastAim: CGPoint?
    private var remoteAim: CGPoint?
    private var remoteCommandID = ""
    private var remoteHelpStartedAt: TimeInterval?
    private var lastRemoteRead: TimeInterval = -.infinity

    static func fromLaunchArguments() -> SimulatedFaceDriver? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-EchoVoiceSimulateFace") else { return nil }
        let script = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "follow"
        let driver = SimulatedFaceDriver()
        for part in script.split(separator: "+").map(String.init) {
            if part.hasPrefix("point=") {
                let numbers = part.dropFirst(6).split(separator: ",").compactMap { Double($0) }
                if numbers.count == 2 { driver.fixedPoint = CGPoint(x: numbers[0], y: numbers[1]) }
            } else if part.hasPrefix("lose=") {
                driver.loseAt = Double(part.dropFirst(5))
            } else {
                driver.parts.insert(part)
            }
        }
        return driver
    }

    func start(context: @escaping Context, deliver: @escaping (FaceSample) -> Void) {
        stop()
        startedAt = ProcessInfo.processInfo.systemUptime
        lastTick = startedAt
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let context = context() else { return }
                deliver(self.tick(context))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: The simulated person

    private func tick(_ context: (aim: CGPoint?, isHead: Bool, orientation: GazeScreenOrientation)) -> FaceSample {
        let now = ProcessInfo.processInfo.systemUptime
        let t = now - startedAt
        let dt = min(max(now - lastTick, 0), 0.05)
        lastTick = now

        if parts.contains("remote") { readRemote(at: t) }
        let aim = context.aim ?? remoteAim ?? fixedPoint ?? scriptedAim(at: t)
        lastAim = aim
        let flip: CGFloat = parts.contains("reversedX") ? -1 : 1
        let offset = CGPoint(x: (aim.x - 0.5) / 0.36, y: (aim.y - 0.5) / 0.36)

        // A person's comfortable range and resting pose are never the app's
        // defaults; calibration has to discover these.
        let wantHead: CGPoint
        let wantEyes: CGPoint
        if context.isHead {
            wantHead = CGPoint(x: 0.04 + flip * offset.x * 0.20, y: -0.03 + offset.y * 0.13)
            wantEyes = .zero
        } else {
            wantHead = CGPoint(x: 0.03, y: -0.02)
            wantEyes = CGPoint(x: flip * offset.x * 0.22, y: offset.y * 0.30)
        }
        head = approach(head, wantHead, dt: dt, tau: 0.15)
        eyes = approach(eyes, wantEyes, dt: dt, tau: 0.06)

        let tremor = CGPoint(x: 0.004 * sin(t * 7.1) + 0.002 * sin(t * 17.3),
                             y: 0.003 * sin(t * 5.3 + 1) + 0.002 * sin(t * 13.7))
        let blink = blinkLevel(at: t)
        let tracked = loseAt.map { !(t >= $0 && t < $0 + 2) } ?? true

        return makeSample(
            yaw: Float(head.x + tremor.x),
            pitch: Float(head.y + tremor.y),
            eyesRight: Float(eyes.x + tremor.x * 0.5),
            eyesDown: Float(eyes.y + tremor.y * 0.5),
            blink: Float(blink),
            tracked: tracked,
            orientation: context.orientation,
            timestamp: now
        )
    }

    private func scriptedAim(at t: TimeInterval) -> CGPoint {
        guard parts.contains("tour") else { return CGPoint(x: 0.5, y: 0.5) }
        let stops = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.14, y: 0.5), CGPoint(x: 0.86, y: 0.5),
                     CGPoint(x: 0.5, y: 0.16), CGPoint(x: 0.5, y: 0.84)]
        return stops[Int(t / 2.5) % stops.count]
    }

    private func readRemote(at t: TimeInterval) {
        guard t - lastRemoteRead >= 0.1 else { return }
        lastRemoteRead = t
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let line = try? String(contentsOf: documents.appendingPathComponent("simface.txt"), encoding: .utf8)
        else { return }
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 3, let x = Double(fields[1]), let y = Double(fields[2]) else { return }
        remoteAim = CGPoint(x: x, y: y)
        if fields[0] != remoteCommandID {
            remoteCommandID = fields[0]
            if fields.contains("help") { remoteHelpStartedAt = t }
        }
    }

    private func blinkLevel(at t: TimeInterval) -> Double {
        if let started = remoteHelpStartedAt {
            let s = t - started
            if s >= 0 && s < 2.0 {
                return s.truncatingRemainder(dividingBy: 0.4) < 0.15 ? 0.95 : 0.05
            }
            if s >= 2.5 && s < 4.8 { return 0.95 }
        }
        if parts.contains("blinkHelp") {
            let s = t - 3
            if s >= 0 && s < 2.0 {
                return s.truncatingRemainder(dividingBy: 0.4) < 0.15 ? 0.95 : 0.05
            }
            if s >= 2.5 && s < 4.8 { return 0.95 }
        }
        if parts.contains("blinkNatural"), t.truncatingRemainder(dividingBy: 3.1) < 0.14 {
            return 0.95
        }
        return 0.05
    }

    private func approach(_ current: CGPoint, _ target: CGPoint, dt: TimeInterval, tau: TimeInterval) -> CGPoint {
        let k = CGFloat(1 - exp(-dt / tau))
        return CGPoint(x: current.x + (target.x - current.x) * k, y: current.y + (target.y - current.y) * k)
    }

    // MARK: Physical model → ARKit-shaped sample

    private func makeSample(
        yaw: Float, pitch: Float, eyesRight: Float, eyesDown: Float, blink: Float,
        tracked: Bool, orientation: GazeScreenOrientation, timestamp: TimeInterval
    ) -> FaceSample {
        // Screen frame: +x right, +y down, +z toward the person. A face
        // squarely facing the screen: its left (+x) toward the screen's left,
        // its up (+y) toward the top, its forward (+z) toward the device.
        func rotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let p = SIMD3(v.x, v.y * cos(pitch) - v.z * sin(pitch), v.y * sin(pitch) + v.z * cos(pitch))
            return SIMD3(p.x * cos(yaw) - p.z * sin(yaw), p.y, p.x * sin(yaw) + p.z * cos(yaw))
        }
        func camera(_ v: SIMD3<Float>, w: Float) -> SIMD4<Float> {
            SIMD4(GazeGeometry.cameraVector(fromScreen: v, orientation: orientation), w)
        }
        let face = simd_float4x4(columns: (
            camera(rotate(SIMD3(-1, 0, 0)), w: 0),
            camera(rotate(SIMD3(0, -1, 0)), w: 0),
            camera(rotate(SIMD3(0, 0, -1)), w: 0),
            camera(SIMD3(0, 0.07, 0.36), w: 1)
        ))

        // Face space: screen-right is −x, down is −y, the pupil looks along +z.
        let direction = simd_normalize(SIMD3<Float>(-tan(eyesRight), -tan(eyesDown), 1))
        let xAxis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), direction))
        let yAxis = simd_cross(direction, xAxis)
        func eye(_ origin: SIMD3<Float>) -> simd_float4x4 {
            simd_float4x4(columns: (SIMD4(xAxis, 0), SIMD4(yAxis, 0), SIMD4(direction, 0), SIMD4(origin, 1)))
        }
        let leftOrigin = SIMD3<Float>(0.031, 0.025, 0.02)
        let rightOrigin = SIMD3<Float>(-0.031, 0.025, 0.02)
        let lookAt = (leftOrigin + rightOrigin) / 2 + direction * 0.4

        let rightward = min(max(eyesRight * 1.6, -1), 1)
        let downward = min(max(eyesDown * 1.4, -1), 1)
        return FaceSample(
            faceInCamera: face,
            leftEye: eye(leftOrigin),
            rightEye: eye(rightOrigin),
            lookAtPoint: lookAt,
            eyeLookInLeft: max(0, rightward),
            eyeLookOutLeft: max(0, -rightward),
            eyeLookUpLeft: max(0, -downward),
            eyeLookDownLeft: max(0, downward),
            eyeLookInRight: max(0, -rightward),
            eyeLookOutRight: max(0, rightward),
            eyeLookUpRight: max(0, -downward),
            eyeLookDownRight: max(0, downward),
            eyeBlinkLeft: blink,
            eyeBlinkRight: blink,
            isTracked: tracked,
            timestamp: timestamp
        )
    }
}
#endif
