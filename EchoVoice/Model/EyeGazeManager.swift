#if os(iOS)
import ARKit
import Foundation
import SwiftUI
import UIKit
import simd

/// On-device hands-free cursor and dwell selection.
///
/// Pipeline, once per camera frame:
/// 1. `FaceSample` — plain values copied out of the `ARFaceAnchor`, with the
///    face expressed relative to the camera, so a device that shifts on its
///    mount is handled.
/// 2. `GazeSignalExtractor` — every candidate signal (head pose, eye
///    transforms, look-at point, blend shapes) in screen axes.
/// 3. Calibration (or, before one exists, a neutral-centered default) maps
///    the active signal to the screen; a One Euro filter steadies it.
/// 4. `BlinkGestureDetector` handles HELP and page turns; `DwellSelector`
///    chooses and fires targets registered by `.gazeSelectable`.
///
/// "Direct Select" is the standard AAC term for touching a target directly,
/// so an SLP reading the screen recognises it immediately.
@MainActor
@Observable
final class EyeGazeManager: NSObject, ARSessionDelegate {
    struct AccessProfile: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var modeRaw: String
        var dwellDuration: Double
        var sensitivity: Double
        /// The calibration measured for this mount. Restored with the profile,
        /// so moving between a bed and a wheelchair does not mean starting over.
        var calibration: GazeCalibration?

        init(id: UUID = UUID(), name: String, mode: TrackingMode, dwellDuration: Double,
             sensitivity: Double, calibration: GazeCalibration? = nil) {
            self.id = id
            self.name = name
            self.modeRaw = mode.rawValue
            self.dwellDuration = dwellDuration
            self.sensitivity = sensitivity
            self.calibration = calibration
        }

        var mode: TrackingMode { (TrackingMode(rawValue: modeRaw) ?? .touch).replacingRetiredEye }
    }

    enum TrackingMode: String, CaseIterable, Identifiable {
        case headMotion = "head"
        /// Retired: on a phone screen the eye signals moved too little to
        /// calibrate reliably. Kept only so an old saved "eye" value decodes;
        /// it is never offered and is replaced with head movement on load.
        case eyeGaze = "eye"
        case touch = "touch"

        /// The modes a person can pick.
        static let allCases: [TrackingMode] = [.headMotion, .touch]

        var replacingRetiredEye: TrackingMode { self == .eyeGaze ? .headMotion : self }

        var id: String { rawValue }
        var label: String {
            switch self {
            case .headMotion: return String(localized: "Head movement")
            case .eyeGaze: return String(localized: "Eye gaze")
            case .touch: return String(localized: "Touch")
            }
        }

        var description: String {
            switch self {
            case .headMotion: return String(localized: "Point with small head movements. The steadiest choice for most people.")
            case .eyeGaze: return String(localized: "Look at what you want. Needs a short setup and a steady phone position.")
            case .touch: return String(localized: "Tap what you want. The camera stays off.")
            }
        }
    }

    enum TrackingQuality: Equatable {
        case off, searching, poor, good
    }

    // MARK: Settings

    var isEnabled: Bool = false {
        didSet {
            if isEnabled && trackingMode != .touch && !isEyeTrackingSupported() {
                isEnabled = false
                return
            }
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if isEnabled && trackingMode != .touch {
                startSession()
            } else {
                stopSession()
            }
        }
    }

    var trackingMode: TrackingMode = .headMotion {
        didSet {
            guard trackingMode != oldValue else { return }
            UserDefaults.standard.set(trackingMode.rawValue, forKey: Keys.mode)
            loadPerModeState()
            configureFilters()
            if trackingMode == .touch {
                stopSession()
            } else if isEnabled {
                if isEyeTrackingSupported() {
                    startSession()
                } else {
                    isEnabled = false
                }
            }
        }
    }

    var dwellDuration: Double = 1.5 {
        didSet { UserDefaults.standard.set(dwellDuration, forKey: Keys.dwell) }
    }

    /// Gain before calibration. Calibration replaces it with measured gain.
    var sensitivity: Double = 6.0 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: Keys.sensitivity) }
    }

    /// A held eye closure turns the page. Off for people whose lids droop.
    var blinkPageTurnEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(blinkPageTurnEnabled, forKey: Keys.blinkPageTurn)
            blink.pageTurnEnabled = blinkPageTurnEnabled
        }
    }

    /// Whether to draw the tracking readout. Off by default: it is for setup
    /// and demonstration, not for daily communication.
    var showsTrackingDiagnostics: Bool = UserDefaults.standard.bool(forKey: Keys.diagnostics) {
        didSet { UserDefaults.standard.set(showsTrackingDiagnostics, forKey: Keys.diagnostics) }
    }

    private(set) var accessProfiles: [AccessProfile] = []

    // MARK: Live state

    var cursorPosition: CGPoint = CGPoint(x: 200, y: 300)
    /// The cursor as a fraction of the gaze area; nil while not tracking.
    private(set) var normalizedCursor: CGPoint?
    private(set) var calibration: GazeCalibration?
    private(set) var accuracyResult: GazeAccuracyResult?
    private(set) var directionalCheck: DirectionalCheckResult?
    private(set) var hoveredTargetID: String?
    private(set) var dwellProgress: Double = 0

    // Tracking diagnostics. Hands-free access fails silently by nature: when
    // the face leaves the frame or the light drops the cursor just stops, and
    // nobody can tell whether the app broke, they moved, or they are aiming
    // wrong. These say which.
    private(set) var isFaceTracked = false
    private(set) var trackingHz: Double = 0
    /// Eye closure, 0...1, the larger of the two eyes.
    private(set) var blinkLevel: Double = 0
    private(set) var leftBlink: Double = 0
    private(set) var rightBlink: Double = 0
    /// Face distance from the screen, in meters.
    private(set) var faceDistance: Double = 0
    private(set) var blinksInEmergencyWindow = 0
    private(set) var isEmergencyBlinkArmed = false
    /// Progress of the confirming HELP hold, 0...1.
    private(set) var helpHoldProgress: Double = 0
    private(set) var latestSignals: GazeSignalSet?
    private(set) var latestSignalsAt: TimeInterval?
    private(set) var selectionState: GazeTrackingState = .lost
    private(set) var orientation: GazeScreenOrientation = .portrait
    private(set) var isRecentering = false

    /// For the simulator harness: the point the scripted person looks at.
    var debugAimPoint: CGPoint?

    var onEmergencyBlinkTrigger: (() -> Void)?
    var onBlinkNavigationTrigger: (() -> Void)?
    /// A confirmed blink-HELP not yet raised on screen. The board raises HELP
    /// and consumes this; the tab container watches it to bring the board
    /// forward from any other tab — including before the board has ever been
    /// opened, when nothing else is listening.
    private(set) var hasPendingHelpRequest = false
    @ObservationIgnored private var pendingHelpAt: TimeInterval = 0

    /// Take the pending HELP request, if there is a recent one. A request is
    /// only honoured for 30 seconds: HELP must never go off long after the
    /// gesture that asked for it.
    func consumeHelpRequest() -> Bool {
        guard hasPendingHelpRequest else { return false }
        hasPendingHelpRequest = false
        return ProcessInfo.processInfo.systemUptime - pendingHelpAt < 30
    }

    // MARK: Derived state

    /// The calibration, if it applies to the current screen orientation.
    var calibrationInUse: GazeCalibration? {
        guard let calibration, calibration.isValid, calibration.orientation == orientation else { return nil }
        return calibration
    }

    var calibrationOrientationMismatch: Bool {
        guard let calibration, calibration.isValid else { return false }
        return calibration.orientation != orientation
    }

    /// Eye gaze is too person-specific to select with uncalibrated: the
    /// cursor would land on the wrong phrase. Head movement has a usable
    /// default once its neutral pose is captured.
    var needsCalibration: Bool { trackingMode == .eyeGaze && calibrationInUse == nil }

    var isHandsFreeActive: Bool { isEnabled && trackingMode != .touch }

    var isSelectionReady: Bool { isHandsFreeActive && !needsCalibration }

    /// The signal driving the cursor right now.
    var activeSource: GazeSignalSource {
        if let calibrationInUse { return calibrationInUse.source }
        // Apple documents lookAtPoint's sign explicitly, so it is the least
        // surprising uncalibrated preview for eye gaze.
        return trackingMode == .headMotion ? .headPose : .lookAtPoint
    }

    var trackingQuality: TrackingQuality {
        guard isHandsFreeActive else { return .off }
        guard isFaceTracked else { return .searching }
        if trackingHz < 24 || faceDistance < 0.18 || faceDistance > 0.85 { return .poor }
        return .good
    }

    // MARK: Private state

    private enum Keys {
        static let enabled = "echovoice.eyegaze"
        static let mode = "echovoice.trackingmode"
        static let dwell = "echovoice.dwelltime"
        static let sensitivity = "echovoice.gazesensitivity"
        static let diagnostics = "echovoice.gazeDiagnostics"
        static let blinkPageTurn = "echovoice.blinkPageTurn"
        static let profiles = "echovoice.accessProfiles"
        // v2: the raw signals changed meaning, so older calibrations are void.
        static func calibration(_ mode: TrackingMode) -> String { "echovoice.gazecalibration.v2.\(mode.rawValue)" }
        static func accuracy(_ mode: TrackingMode) -> String { "echovoice.gazeaccuracy.v2.\(mode.rawValue)" }
        static func direction(_ mode: TrackingMode) -> String { "echovoice.gazedirection.v2.\(mode.rawValue)" }
    }

    struct RegisteredTarget {
        let token: UUID
        var frame: CGRect
        var kind: DwellTarget.Kind
        var action: () -> Void
    }

    @ObservationIgnored private var targets: [String: RegisteredTarget] = [:]
    @ObservationIgnored private var dwell = DwellSelector()
    @ObservationIgnored private var blink = BlinkGestureDetector()
    @ObservationIgnored private var horizontalFilter = AdaptiveGazeFilter()
    @ObservationIgnored private var verticalFilter = AdaptiveGazeFilter()
    @ObservationIgnored private var arSession: ARSession?
    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var lastAnchorAt: TimeInterval?
    /// Samples just after the lids reopen are skewed; ignore them briefly.
    @ObservationIgnored private var settleUntil: TimeInterval = 0
    @ObservationIgnored private var wasClosed = false
    /// Uncalibrated neutral pose per source, captured automatically.
    @ObservationIgnored private var neutral: [GazeSignalSource: CGPoint] = [:]
    @ObservationIgnored private var neutralSamples: [CGPoint] = []
    @ObservationIgnored private var neutralAttempts = 0
    @ObservationIgnored private var sessionRetries = 0

    /// ARKit could not run (camera in use elsewhere, permission, hardware).
    private(set) var sessionFailed = false

    /// True while "straight ahead" is still being measured. Nothing is
    /// selectable then: the cursor is pinned to the center until the neutral
    /// pose exists, and dwelling there would select whatever sits there.
    private var isCapturingNeutral: Bool {
        isRecentering || (calibrationInUse == nil && neutral[activeSource] == nil)
    }
    @ObservationIgnored private weak var window: UIWindow?
    @ObservationIgnored private var lastGazeArea: CGRect?
    #if DEBUG
    @ObservationIgnored private var simulator: SimulatedFaceDriver?
    @ObservationIgnored private let logsGaze = ProcessInfo.processInfo.arguments.contains("-EchoVoiceLogGaze")
    @ObservationIgnored private var lastLogAt: TimeInterval = 0
    #endif

    private let hoverHaptic = UIImpactFeedbackGenerator(style: .light)
    private let selectHaptic = UINotificationFeedbackGenerator()

    override init() {
        super.init()
        let defaults = UserDefaults.standard
        let savedMode = (TrackingMode(rawValue: defaults.string(forKey: Keys.mode) ?? "head") ?? .headMotion).replacingRetiredEye
        trackingMode = savedMode
        let savedDwell = defaults.double(forKey: Keys.dwell)
        dwellDuration = savedDwell > 0 ? savedDwell : 1.5
        let savedSensitivity = defaults.double(forKey: Keys.sensitivity)
        sensitivity = savedSensitivity > 0 ? savedSensitivity : 6.0
        blinkPageTurnEnabled = defaults.object(forKey: Keys.blinkPageTurn) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.profiles),
           let profiles = try? JSONDecoder().decode([AccessProfile].self, from: data) {
            accessProfiles = profiles
        }
        #if DEBUG
        simulator = SimulatedFaceDriver.fromLaunchArguments()
        if simulator != nil, ProcessInfo.processInfo.arguments.contains("-EchoVoiceSimulateEnable") {
            defaults.set(true, forKey: Keys.enabled)
        }
        #endif
        loadPerModeState()
        configureFilters()
        blink.pageTurnEnabled = blinkPageTurnEnabled

        // Whether property observers run for assignments inside `init` is not
        // something to depend on, so the session is started explicitly.
        let wantsEnabled = defaults.bool(forKey: Keys.enabled)
        isEnabled = wantsEnabled && (trackingMode == .touch || isEyeTrackingSupported())
        if isEnabled && trackingMode != .touch {
            startSession()
        }
    }

    func isEyeTrackingSupported() -> Bool {
        #if DEBUG
        if simulator != nil { return true }
        #endif
        return ARFaceTrackingConfiguration.isSupported
    }

    // MARK: Session

    private func startSession() {
        guard isEyeTrackingSupported() else { return }
        resetTrackingState()
        startWatchdog()
        #if DEBUG
        if let simulator {
            simulator.start { [weak self] in
                guard let self else { return nil }
                return (self.debugAimPoint, self.trackingMode == .headMotion, self.orientation)
            } deliver: { [weak self] sample in
                self?.process(sample)
            }
            return
        }
        #endif
        if arSession == nil {
            let session = ARSession()
            session.delegate = self
            // Delivered on the main queue so each frame is processed in place,
            // without an extra hop and a frame of latency.
            session.delegateQueue = .main
            arSession = session
        }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        arSession?.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    private func stopSession() {
        #if DEBUG
        simulator?.stop()
        #endif
        arSession?.pause()
        watchdog?.invalidate()
        watchdog = nil
        resetTrackingState()
    }

    private func resetTrackingState() {
        lastAnchorAt = nil
        isFaceTracked = false
        trackingHz = 0
        blinkLevel = 0
        leftBlink = 0
        rightBlink = 0
        latestSignals = nil
        latestSignalsAt = nil
        normalizedCursor = nil
        selectionState = .lost
        neutralSamples.removeAll()
        blink.faceLost()
        syncBlinkState()
        resetMotionFilter()
        resetDwell()
    }

    /// ARKit does not announce that a face has left the frame; it stops
    /// delivering tracked anchors. Treat a gap as a lost face.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let last = self.lastAnchorAt else { return }
                if ProcessInfo.processInfo.systemUptime - last > 0.6, self.isFaceTracked {
                    self.markFaceLost()
                }
            }
        }
    }

    private func markFaceLost() {
        isFaceTracked = false
        trackingHz = 0
        blinkLevel = 0
        latestSignals = nil
        latestSignalsAt = nil
        normalizedCursor = nil
        selectionState = .lost
        blink.faceLost()
        syncBlinkState()
        resetMotionFilter()
        dwell.trackingLost()
        publishDwell()
    }

    // MARK: ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let anchor = frame.anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let sample = FaceSample(anchor: anchor, camera: frame.camera, timestamp: frame.timestamp)
        MainActor.assumeIsolated {
            self.process(sample)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.sessionDidFail() }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated { self.markFaceLost() }
    }

    /// Another app had the camera, or the app was backgrounded: run again
    /// rather than sit on "Looking for your face" forever.
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated {
            if self.isHandsFreeActive { self.startSession() }
        }
    }

    /// Retry a few times, a couple of seconds apart, then say so plainly.
    private func sessionDidFail() {
        markFaceLost()
        guard isHandsFreeActive, sessionRetries < 3 else {
            sessionFailed = isHandsFreeActive
            return
        }
        sessionRetries += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.isHandsFreeActive else { return }
            self.startSession()
        }
    }

    // MARK: Per-frame processing

    private func process(_ sample: FaceSample) {
        guard isHandsFreeActive else { return }
        // Gesture and dwell timing use when the camera captured the frame, not
        // when the main thread got round to it: a busy moment on the main
        // thread would otherwise stretch or shrink a blink and misread it.
        // ARFrame timestamps share the system-uptime clock; anything
        // implausible falls back to it.
        let uptime = ProcessInfo.processInfo.systemUptime
        let now = (sample.timestamp > 0 && abs(uptime - sample.timestamp) < 1) ? sample.timestamp : uptime
        // An untracked anchor is skipped, not treated as a lost face: ARKit can
        // flag a single frame during an otherwise steady hold, and treating
        // it as a loss would disarm HELP mid-confirmation. A real loss stops
        // tracked frames altogether, and the watchdog catches that in 0.6 s.
        guard sample.isTracked else { return }
        noteAnchor(at: now)
        refreshOrientation()

        leftBlink = Double(sample.eyeBlinkLeft)
        rightBlink = Double(sample.eyeBlinkRight)
        blinkLevel = max(leftBlink, rightBlink)
        faceDistance = Double(sample.faceDistance)

        handle(blink.update(left: leftBlink, right: rightBlink, time: now))
        syncBlinkState(at: now)

        #if DEBUG
        if logsGaze {
            let t = sample.faceInCamera.columns.3, l = sample.lookAtPoint
            rawPose = String(format: "t=%.2f,%.2f,%.2f look=%.2f,%.2f,%.2f", t.x, t.y, t.z, l.x, l.y, l.z)
        }
        #endif
        let signals = GazeSignalExtractor.signals(from: sample, orientation: orientation)
        latestSignals = signals
        latestSignalsAt = now

        // Eyelid-based estimates are unreliable while the lids move, and a
        // closed-eye gesture must not drag the cursor, in either mode.
        // Both eyes, not either: one heavy lid while looking at the bottom
        // row froze eye-gaze selection of exactly the controls down there.
        let closing = blink.isClosed || (trackingMode == .eyeGaze && min(leftBlink, rightBlink) > 0.55)
        if wasClosed && !closing { settleUntil = now + 0.12 }
        wasClosed = closing

        if closing || now < settleUntil {
            selectionState = .eyesClosed
        } else if let raw = signals[activeSource] {
            selectionState = .tracking
            moveCursor(raw: raw, at: now)
        } else {
            // Head turned right away from the screen: nothing to point with.
            selectionState = .lost
            normalizedCursor = nil
        }

        runDwell(at: now)
        #if DEBUG
        logFrame(at: now)
        #endif
    }

    #if DEBUG
    /// Last frame's face position in camera space and lookAtPoint, for the log.
    @ObservationIgnored private var rawPose = "-"

    /// One line four times a second: what the simulated person aims at, where
    /// the cursor went, and what dwell is doing. Read from the console to get
    /// numbers out of a simulator run.
    private func logFrame(at now: TimeInterval) {
        guard logsGaze, now - lastLogAt >= 0.25 else { return }
        lastLogAt = now
        let aim = (simulator?.lastAim ?? debugAimPoint).map { String(format: "%.2f,%.2f", $0.x, $0.y) } ?? "-"
        let cursor = normalizedCursor.map { String(format: "%.2f,%.2f", $0.x, $0.y) } ?? "-"
        print("ECHOVOICE_GAZE mode=\(trackingMode.rawValue) source=\(activeSource.rawValue) calibrated=\(calibrationInUse != nil) state=\(selectionState) aim=\(aim) cursor=\(cursor) hovered=\(hoveredTargetID ?? "-") progress=\(String(format: "%.2f", dwellProgress)) armed=\(isEmergencyBlinkArmed) blinks=\(blinksInEmergencyWindow) quality=\(trackingQuality) hz=\(String(format: "%.1f", trackingHz)) dist=\(String(format: "%.2f", faceDistance)) tracked=\(isFaceTracked) signals=\(latestSignals.map { set in [("head", set.headPose), ("eyeT", set.eyeTransform), ("look", set.lookAtPoint), ("blend", set.blendShape)].filter { $0.1 != nil }.map(\.0).joined(separator: "+") } ?? "none") raw=\(rawPose)")
    }
    #endif

    private func noteAnchor(at now: TimeInterval) {
        if let last = lastAnchorAt, now > last {
            let instantaneous = 1 / (now - last)
            trackingHz = trackingHz == 0 ? instantaneous : (trackingHz * 0.9 + instantaneous * 0.1)
        }
        lastAnchorAt = now
        sessionRetries = 0
        sessionFailed = false
        if !isFaceTracked {
            isFaceTracked = true
            neutralSamples.removeAll()
        }
    }

    private func moveCursor(raw: CGPoint, at now: TimeInterval) {
        captureNeutralIfNeeded(raw)
        let normalized: CGPoint
        if let calibrationInUse {
            normalized = calibrationInUse.normalizedPoint(for: raw)
        } else {
            normalized = DefaultGazeMapping.normalizedPoint(
                raw: raw,
                neutral: neutral[activeSource] ?? raw,
                source: activeSource,
                sensitivity: sensitivity
            )
        }
        let area = gazeArea
        let target = GazeScreenMapping.clamp(GazeScreenMapping.windowPoint(forNormalized: normalized, in: area), to: area)
        cursorPosition = CGPoint(
            x: horizontalFilter.filter(target.x, at: now),
            y: verticalFilter.filter(target.y, at: now)
        )
        normalizedCursor = GazeScreenMapping.normalizedPoint(forWindow: cursorPosition, in: area)
    }

    /// Before calibration, the first half-second of *steady* tracking defines
    /// "straight ahead"; `recenter()` redefines it on request. Samples taken
    /// while the head is still moving are not a resting pose — capturing one
    /// left the uncalibrated cursor pulled toward wherever the person was
    /// turning — so the window slides until it holds still.
    private func captureNeutralIfNeeded(_ raw: CGPoint) {
        let wantsCapture = isRecentering || (calibrationInUse == nil && neutral[activeSource] == nil)
        guard wantsCapture else { return }
        neutralSamples.append(raw)
        neutralAttempts += 1
        if neutralSamples.count > 30 { neutralSamples.removeFirst(neutralSamples.count - 30) }
        guard neutralSamples.count == 30 else { return }
        let stats = PointStats(neutralSamples)
        let range = DefaultGazeMapping.halfRange(for: activeSource)
        // Steady: spread under a tenth of the default half-range on both
        // axes. After three seconds without that — a tremor, say — the
        // latest half-second is used anyway, so the cursor is never stuck.
        let steady = stats.spread.x < range.width * 0.1 && stats.spread.y < range.height * 0.1
        guard steady || neutralAttempts >= 180 else { return }
        let center = stats.median
        neutralSamples.removeAll()
        neutralAttempts = 0
        if isRecentering, let calibrationInUse {
            saveCalibration(calibrationInUse.recentered(on: center))
        } else {
            neutral[activeSource] = center
        }
        isRecentering = false
        resetMotionFilter()
    }

    /// Treat the current pose as center. Keeps any calibrated range and
    /// direction; only the center moves.
    func recenter() {
        neutralSamples.removeAll()
        isRecentering = true
        if calibrationInUse == nil { neutral[activeSource] = nil }
    }

    private func handle(_ events: [BlinkGestureDetector.Event]) {
        for event in events {
            switch event {
            case .quickBlink:
                break
            case .helpArmed:
                selectHaptic.notificationOccurred(.warning)
            case .helpConfirmed:
                #if DEBUG
                if logsGaze { print("ECHOVOICE_GAZE event=helpConfirmed") }
                #endif
                selectHaptic.notificationOccurred(.error)
                resetDwell()
                pendingHelpAt = ProcessInfo.processInfo.systemUptime
                hasPendingHelpRequest = true
                onEmergencyBlinkTrigger?()
            case .helpCancelled, .helpHoldTooShort:
                break
            case .pageTurn:
                #if DEBUG
                if logsGaze { print("ECHOVOICE_GAZE event=pageTurn") }
                #endif
                hoverHaptic.impactOccurred()
                resetDwell()
                onBlinkNavigationTrigger?()
            }
        }
    }

    private func syncBlinkState(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if blinksInEmergencyWindow != blink.quickBlinkCount { blinksInEmergencyWindow = blink.quickBlinkCount }
        if isEmergencyBlinkArmed != blink.isArmed { isEmergencyBlinkArmed = blink.isArmed }
        let hold = blink.helpHoldProgress(at: now)
        if abs(helpHoldProgress - hold) > 0.01 || (hold == 0 && helpHoldProgress != 0) { helpHoldProgress = hold }
    }

    // MARK: Screen geometry

    /// The area gaze maps into: the window's safe area, in window points —
    /// the same space SwiftUI's `.global` frames use.
    var gazeArea: CGRect {
        guard let window = currentWindow() else { return CGRect(x: 0, y: 0, width: 390, height: 844) }
        return window.bounds.inset(by: window.safeAreaInsets)
    }

    private func currentWindow() -> UIWindow? {
        if let window { return window }
        let found = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        window = found
        return found
    }

    private func refreshOrientation() {
        let interface = currentWindow()?.windowScene?.interfaceOrientation ?? .portrait
        let mapped: GazeScreenOrientation
        switch interface {
        case .portraitUpsideDown: mapped = .portraitUpsideDown
        case .landscapeLeft: mapped = .landscapeLeft
        case .landscapeRight: mapped = .landscapeRight
        default: mapped = .portrait
        }
        let orientationChanged = mapped != orientation
        let area = gazeArea
        if orientationChanged || lastGazeArea != area {
            orientation = mapped
            lastGazeArea = area
            if orientationChanged {
                neutral.removeAll()
                neutralSamples.removeAll()
                neutralAttempts = 0
            }
            normalizedCursor = nil
            resetMotionFilter()
            resetDwell()
        }
    }

    // MARK: Targets and dwell

    /// Called by `.gazeSelectable` whenever a control appears or moves.
    func registerTarget(id: String, token: UUID, frame: CGRect, kind: DwellTarget.Kind, action: @escaping () -> Void) {
        targets[id] = RegisteredTarget(token: token, frame: frame, kind: kind, action: action)
    }

    /// Only the registration that owns `token` may remove the target, so a
    /// view disappearing after its replacement appeared cannot unregister it.
    func unregisterTarget(id: String, token: UUID) {
        guard targets[id]?.token == token else { return }
        targets[id] = nil
    }

    private func runDwell(at now: TimeInterval) {
        guard isSelectionReady else {
            if hoveredTargetID != nil || dwellProgress != 0 { resetDwell() }
            return
        }
        let current = targets.map { DwellTarget(id: $0.key, frame: $0.value.frame, kind: $0.value.kind) }
        let cursor: CGPoint? = selectionState == .lost ? nil : cursorPosition
        let state: GazeTrackingState = (selectionState == .tracking && isCapturingNeutral) ? .eyesClosed : selectionState
        let fired = dwell.update(cursor: cursor, state: state, targets: current, time: now, dwellDuration: dwellDuration)
        publishDwell()
        if let fired, let target = targets[fired] {
            #if DEBUG
            if logsGaze { print("ECHOVOICE_GAZE event=selected id=\(fired)") }
            #endif
            selectHaptic.notificationOccurred(.success)
            target.action()
        }
    }

    private func publishDwell() {
        if hoveredTargetID != dwell.hoveredID {
            if dwell.hoveredID != nil { hoverHaptic.impactOccurred() }
            hoveredTargetID = dwell.hoveredID
        }
        if abs(dwellProgress - dwell.progress) > 0.005 || (dwell.progress == 0 && dwellProgress != 0) {
            dwellProgress = dwell.progress
        }
    }

    /// Forget hover, progress, and the one-selection latch. Call when the
    /// screen changes wholesale: a new page, tab, mode, or sheet.
    func resetDwell() {
        dwell.reset(time: ProcessInfo.processInfo.systemUptime)
        hoveredTargetID = nil
        dwellProgress = 0
    }

    // MARK: Samples for calibration and checks

    /// The latest signals, if fresh, open-eyed, and newer than `previousTime`.
    /// Calibration only uses distinct recent frames; reusing one frozen frame
    /// can produce a plausible but unusable mapping.
    func freshSignals(after previousTime: TimeInterval?) -> (signals: GazeSignalSet, time: TimeInterval)? {
        guard isHandsFreeActive, isFaceTracked, selectionState == .tracking,
              let signals = latestSignals, let time = latestSignalsAt,
              ProcessInfo.processInfo.systemUptime - time < 0.2,
              time > (previousTime ?? -.infinity) else { return nil }
        return (signals, time)
    }

    /// The filtered cursor as a fraction of the gaze area, if fresh.
    func freshCursor(after previousTime: TimeInterval?) -> (point: CGPoint, time: TimeInterval)? {
        guard let fresh = freshSignals(after: previousTime), let normalizedCursor else { return nil }
        return (normalizedCursor, fresh.time)
    }

    // MARK: Calibration storage

    func saveCalibration(_ newCalibration: GazeCalibration) {
        guard newCalibration.isValid else { return }
        calibration = newCalibration
        if let data = try? JSONEncoder().encode(newCalibration) {
            UserDefaults.standard.set(data, forKey: Keys.calibration(trackingMode))
        }
        resetMotionFilter()
    }

    /// A new calibration makes older accuracy and direction results stale.
    func clearChecks() {
        accuracyResult = nil
        directionalCheck = nil
        UserDefaults.standard.removeObject(forKey: Keys.accuracy(trackingMode))
        UserDefaults.standard.removeObject(forKey: Keys.direction(trackingMode))
    }

    func saveAccuracyResult(_ result: GazeAccuracyResult) {
        accuracyResult = result
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Keys.accuracy(trackingMode))
        }
    }

    func saveDirectionalCheck(_ result: DirectionalCheckResult) {
        directionalCheck = result
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Keys.direction(trackingMode))
        }
    }

    func clearCalibration() {
        calibration = nil
        UserDefaults.standard.removeObject(forKey: Keys.calibration(trackingMode))
        clearChecks()
        neutral.removeAll()
        resetMotionFilter()
    }

    private func loadPerModeState() {
        let defaults = UserDefaults.standard
        calibration = defaults.data(forKey: Keys.calibration(trackingMode))
            .flatMap { try? JSONDecoder().decode(GazeCalibration.self, from: $0) }
        accuracyResult = defaults.data(forKey: Keys.accuracy(trackingMode))
            .flatMap { try? JSONDecoder().decode(GazeAccuracyResult.self, from: $0) }
        directionalCheck = defaults.data(forKey: Keys.direction(trackingMode))
            .flatMap { try? JSONDecoder().decode(DirectionalCheckResult.self, from: $0) }
        neutral.removeAll()
        resetMotionFilter()
        resetDwell()
    }

    private func configureFilters() {
        // Eye signals are noisier than head pose, so they rest on a lower
        // cutoff; both open up quickly for a deliberate movement.
        let (cutoff, speed): (CGFloat, CGFloat) = trackingMode == .eyeGaze ? (0.8, 0.02) : (1.2, 0.03)
        horizontalFilter = AdaptiveGazeFilter(minimumCutoff: cutoff, speedCoefficient: speed)
        verticalFilter = AdaptiveGazeFilter(minimumCutoff: cutoff, speedCoefficient: speed)
    }

    private func resetMotionFilter() {
        horizontalFilter.reset()
        verticalFilter.reset()
    }

    // MARK: Access profiles

    func saveAccessProfile(name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let profile = AccessProfile(name: cleaned, mode: trackingMode, dwellDuration: dwellDuration,
                                    sensitivity: sensitivity, calibration: calibration)
        accessProfiles.removeAll { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }
        accessProfiles.append(profile)
        persistAccessProfiles()
    }

    func applyAccessProfile(_ profile: AccessProfile) {
        trackingMode = profile.mode
        dwellDuration = profile.dwellDuration
        sensitivity = profile.sensitivity
        if let saved = profile.calibration, saved.isValid {
            saveCalibration(saved)
            clearChecks()
        }
    }

    func deleteAccessProfile(_ profile: AccessProfile) {
        accessProfiles.removeAll { $0.id == profile.id }
        persistAccessProfiles()
    }

    private func persistAccessProfiles() {
        guard let data = try? JSONEncoder().encode(accessProfiles) else { return }
        UserDefaults.standard.set(data, forKey: Keys.profiles)
    }
}

extension FaceSample {
    /// Copy what the pipeline needs out of an anchor, relative to the camera.
    init(anchor: ARFaceAnchor, camera: ARCamera, timestamp: TimeInterval) {
        let shapes = anchor.blendShapes
        func value(_ key: ARFaceAnchor.BlendShapeLocation) -> Float { shapes[key]?.floatValue ?? 0 }
        self.init(
            faceInCamera: GazeGeometry.facingViewer(simd_mul(simd_inverse(camera.transform), anchor.transform)),
            leftEye: anchor.leftEyeTransform,
            rightEye: anchor.rightEyeTransform,
            lookAtPoint: anchor.lookAtPoint,
            eyeLookInLeft: value(.eyeLookInLeft),
            eyeLookOutLeft: value(.eyeLookOutLeft),
            eyeLookUpLeft: value(.eyeLookUpLeft),
            eyeLookDownLeft: value(.eyeLookDownLeft),
            eyeLookInRight: value(.eyeLookInRight),
            eyeLookOutRight: value(.eyeLookOutRight),
            eyeLookUpRight: value(.eyeLookUpRight),
            eyeLookDownRight: value(.eyeLookDownRight),
            eyeBlinkLeft: value(.eyeBlinkLeft),
            eyeBlinkRight: value(.eyeBlinkRight),
            isTracked: anchor.isTracked,
            timestamp: timestamp
        )
    }
}
#else
import Foundation
import SwiftUI

/// Non-iOS stand-in so shared views compile. Hands-free access needs ARKit.
@MainActor
@Observable
final class EyeGazeManager {
    enum TrackingMode: String, CaseIterable, Identifiable {
        case headMotion = "head"
        case eyeGaze = "eye"
        case touch = "touch"
        static let allCases: [TrackingMode] = [.headMotion, .touch]
        var id: String { rawValue }
        var label: String { rawValue }
        var description: String { "" }
    }

    var isEnabled = false
    var trackingMode: TrackingMode = .touch
    var dwellDuration: Double = 1.5
    var cursorPosition: CGPoint = .zero
    var hoveredTargetID: String?
    var dwellProgress: Double = 0
    var isFaceTracked = false
    var isEmergencyBlinkArmed = false
    var isHandsFreeActive: Bool { false }
    func isEyeTrackingSupported() -> Bool { false }
    func registerTarget(id: String, token: UUID, frame: CGRect, kind: DwellTarget.Kind, action: @escaping () -> Void) {}
    func unregisterTarget(id: String, token: UUID) {}
    func resetDwell() {}
}
#endif
