import SwiftUI

/// Guided hands-free setup.
///
/// 1. **Get ready** — live checks that the camera can see the person.
/// 2. **Follow the dot** — five points. Every signal source is recorded at
///    once; each axis's direction and gain is *measured*, and for eye gaze
///    the steadiest source is chosen (`GazeCalibrationBuilder`).
/// 3. **Check directions** — the live cursor must actually go left, right,
///    up and down when the person does. This is the check that would have
///    caught a reversed cursor.
/// 4. **Try selecting** (optional) — the real dwell selector on board-sized
///    tiles: time to select, wrong selections, jitter, tracking losses.
///
/// Every sample and result stays in UserDefaults on this device.
struct GazeCalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum DirectionStep: CaseIterable {
        case center, left, right, up, down

        /// Deliberately not the calibration points: the check tests the live
        /// cursor where calibration was not fitted.
        var target: CGPoint {
            switch self {
            case .center: return CGPoint(x: 0.5, y: 0.5)
            case .left: return CGPoint(x: 0.22, y: 0.46)
            case .right: return CGPoint(x: 0.78, y: 0.54)
            case .up: return CGPoint(x: 0.46, y: 0.24)
            case .down: return CGPoint(x: 0.54, y: 0.76)
            }
        }

        var name: String {
            switch self {
            case .center: return String(localized: "the middle")
            case .left: return String(localized: "the left")
            case .right: return String(localized: "the right")
            case .up: return String(localized: "the top")
            case .down: return String(localized: "the bottom")
            }
        }
    }

    private enum Phase: Equatable {
        case overview
        case capturing(CalibrationPoint, index: Int)
        case failed(String)
        case checking(DirectionStep)
        case accuracy
        case recentering
    }

    @State private var phase: Phase = .overview
    @State private var progress = 0.0
    @State private var job: Task<Void, Never>?
    @State private var message: String?
    @State private var stageSize: CGSize?

    private var isHead: Bool { eyeGaze.trackingMode == .headMotion }
    private var isBusy: Bool {
        switch phase {
        case .overview, .failed: return false
        default: return true
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            ZStack {
                Palette.background.ignoresSafeArea()

                switch phase {
                case .overview:
                    overview
                case .failed(let reason):
                    failure(reason)
                case .capturing(let point, let index):
                    targetStage(
                        at: local(point.normalizedTarget, origin),
                        size: geometry.size,
                        title: isHead ? String(localized: "Point your nose at the dot") : String(localized: "Look at the dot"),
                        detail: String(localized: "Hold still until the ring fills. %@ of %@", defaultValue: "Hold still until the ring fills. \(String(describing: index + 1)) of \(String(describing: CalibrationPoint.allCases.count))")
                    )
                case .checking(let step):
                    targetStage(
                        at: local(step.target, origin),
                        size: geometry.size,
                        title: isHead ? String(localized: "Point at the dot on %@", defaultValue: "Point at the dot on \(String(describing: step.name))") : String(localized: "Look at the dot on %@", defaultValue: "Look at the dot on \(String(describing: step.name))"),
                        detail: String(localized: "Checking that the cursor follows you.")
                    )
                    GazeCursorOverlay().ignoresSafeArea()
                case .recentering:
                    targetStage(
                        at: local(CGPoint(x: 0.5, y: 0.5), origin),
                        size: geometry.size,
                        title: isHead ? String(localized: "Point your nose at the dot") : String(localized: "Look at the dot"),
                        detail: String(localized: "Re-centering. Keep still for a moment.")
                    )
                case .accuracy:
                    GazeAccuracyCheck { result in
                        eyeGaze.saveAccuracyResult(result)
                        message = String(localized: "Selection check saved on this device.")
                        phase = .overview
                    } onCancel: {
                        phase = .overview
                    }
                    GazeCursorOverlay().ignoresSafeArea()
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                if let stageSize, stageSize != size { cancelForGeometryChange() }
                stageSize = size
            }
        }
        .onChange(of: eyeGaze.orientation) { cancelForGeometryChange() }
        .interactiveDismissDisabled(isBusy)
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-EchoVoiceAutoStartSetup"), phase == .overview {
                start(runCalibration)
            }
        }
        #endif
        .onDisappear {
            job?.cancel()
            eyeGaze.debugAimPoint = nil
        }
    }

    private func local(_ normalized: CGPoint, _ origin: CGPoint) -> CGPoint {
        let window = GazeScreenMapping.windowPoint(forNormalized: normalized, in: eyeGaze.gazeArea)
        return CGPoint(x: window.x - origin.x, y: window.y - origin.y)
    }

    private func cancelForGeometryChange() {
        guard isBusy else { return }
        job?.cancel()
        eyeGaze.debugAimPoint = nil
        eyeGaze.resetDwell()
        message = "The screen changed. Run setup again with the device in this position."
        phase = .overview
    }

    // MARK: Overview

    private var overview: some View {
        ScrollView {
            VStack(spacing: 18) {
                BearMascotView(mood: .idle)
                    .frame(width: 120, height: 120)
                    .padding(.top, 8)

                Text(isHead ? String(localized: "Head control setup") : String(localized: "Eye control setup"))
                    .font(EchoFont.display(28, weight: .extraBold))
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.center)

                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(EchoFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.controlAccent)
                        .multilineTextAlignment(.center)
                }

                readinessCard

                if eyeGaze.calibrationInUse != nil {
                    GazeSetupSummaryCard()
                } else {
                    stepsCard
                }

                actions
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(1, String(localized: "Put the device where it will stay, at eye level if you can."))
            step(2, String(localized: "Sit the way you usually sit."))
            step(3, isHead ? String(localized: "Point your nose at five dots, one at a time.") : String(localized: "Look at five dots, one at a time. Keep your head still."))
            step(4, String(localized: "Then EchoVoice checks that the cursor goes where you look."))
            Text(String(localized: "About one minute. Nothing leaves this device."))
                .font(EchoFont.body(14))
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 20))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(EchoFont.body(16, weight: .bold))
                .foregroundStyle(Palette.onControlAccent)
                .frame(width: 30, height: 30)
                .background(Palette.controlAccent, in: .circle)
            Text(text)
                .font(EchoFont.body(17, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readinessCard: some View {
        let quality = eyeGaze.trackingQuality
        let (icon, color, text): (String, Color, String) = {
            switch quality {
            case .off: return ("camera", Palette.faint, String(localized: "Turn on hands-free control in Settings first."))
            case .searching: return ("face.dashed", Palette.red, String(localized: "Looking for your face. Face the screen in good light."))
            case .poor:
                if eyeGaze.faceDistance > 0.85 { return ("arrow.down.right.and.arrow.up.left", Palette.orange, String(localized: "Move a little closer to the phone.")) }
                if eyeGaze.faceDistance > 0 && eyeGaze.faceDistance < 0.18 { return ("arrow.up.left.and.arrow.down.right", Palette.orange, String(localized: "Move a little further from the phone.")) }
                return ("light.max", Palette.orange, String(localized: "Tracking is weak. More light usually helps."))
            case .good: return ("face.smiling", Palette.controlAccent, String(localized: "EchoVoice can see you clearly."))
            }
        }()
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32)
            Text(text)
                .font(EchoFont.body(16, weight: .bold))
                .foregroundStyle(Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(0.5), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        let calibrated = eyeGaze.calibrationInUse != nil
        VStack(spacing: 10) {
            // Once setup has worked, the obvious next step is to leave. "Set up
            // again" as the big green button invited people to redo a setup
            // that had just passed, with Done below the fold.
            if calibrated {
                primaryButton(String(localized: "Done"), systemImage: "checkmark") { dismiss() }
                secondaryButton(String(localized: "Set up again"), systemImage: "scope") {
                    start(runCalibration)
                }
                .disabled(!eyeGaze.isHandsFreeActive)
            } else {
                primaryButton(String(localized: "Start setup"), systemImage: "scope") {
                    start(runCalibration)
                }
                .disabled(!eyeGaze.isHandsFreeActive)
            }

            if calibrated {
                secondaryButton(String(localized: "Check directions"), systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                    start(runDirectionCheck)
                }
                secondaryButton(String(localized: "Try selecting"), systemImage: "hand.point.up.left") {
                    message = nil
                    phase = .accuracy
                }
            }
            if eyeGaze.isHandsFreeActive {
                secondaryButton(String(localized: "Re-center"), systemImage: "dot.viewfinder") {
                    start(runRecenter)
                }
            }
            if !calibrated {
                Button(String(localized: "Not now")) { dismiss() }
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(EchoFont.body(18, weight: .bold))
                .foregroundStyle(Palette.onControlAccent)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Palette.controlAccent, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func failure(_ reason: String) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Palette.orange)
            Text(String(localized: "Setup didn't finish"))
                .font(EchoFont.display(26, weight: .extraBold))
                .foregroundStyle(Palette.primaryText)
            Text(reason)
                .font(EchoFont.body(18, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Your previous setup, if any, is unchanged."))
                .font(EchoFont.body(15))
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 0)
            primaryButton(String(localized: "Try again"), systemImage: "arrow.clockwise") { start(runCalibration) }
            secondaryButton(String(localized: "Back"), systemImage: "chevron.left") { phase = .overview }
        }
        .padding(24)
        .frame(maxWidth: 560)
    }

    // MARK: Target stage

    private func targetStage(at point: CGPoint, size: CGSize, title: String, detail: String) -> some View {
        // The instructions must never sit on the dot: when the dot is near the
        // top they move to the bottom, instead of fading to unreadable.
        let dotNearTop = point.y < size.height * 0.35
        return ZStack {
            VStack(spacing: 6) {
                if dotNearTop { Spacer() }
                Text(title)
                    .font(EchoFont.display(24, weight: .extraBold))
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(EchoFont.body(16, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                if !dotNearTop { Spacer() }
                Button(String(localized: "Stop")) {
                    job?.cancel()
                    eyeGaze.debugAimPoint = nil
                    phase = .overview
                }
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .frame(minWidth: 88, minHeight: 50)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .readableContentWidth()

            ZStack {
                Circle()
                    .stroke(Palette.forest.opacity(0.18), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Palette.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(Palette.forest)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 84, height: 84)
            .position(point)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: point)
            .accessibilityLabel(String(localized: "Target"))
        }
    }

    // MARK: Jobs

    private func start(_ work: @escaping @MainActor () async -> Void) {
        job?.cancel()
        message = nil
        job = Task { @MainActor in await work() }
    }

    private static let samplesPerPoint = 60

    private func runCalibration() async {
        var samples: [CalibrationPoint: [GazeSignalSet]] = [:]
        for (index, point) in CalibrationPoint.allCases.enumerated() {
            phase = .capturing(point, index: index)
            progress = 0
            eyeGaze.debugAimPoint = point.normalizedTarget
            // Eyes need a moment to land on a new dot, heads longer.
            guard await pause(milliseconds: isHead ? 900 : 650) else { return }
            var collected: [GazeSignalSet] = []
            var last: TimeInterval?
            let started = ProcessInfo.processInfo.systemUptime
            while collected.count < Self.samplesPerPoint,
                  ProcessInfo.processInfo.systemUptime - started < 4 {
                if let fresh = eyeGaze.freshSignals(after: last) {
                    collected.append(fresh.signals)
                    last = fresh.time
                }
                progress = Double(collected.count) / Double(Self.samplesPerPoint)
                guard await pause(milliseconds: 12) else { return }
            }
            samples[point] = collected
        }
        eyeGaze.debugAimPoint = nil

        let sources = GazeSignalSource.candidates(forHeadMode: isHead)
        let outcome = GazeCalibrationBuilder.evaluate(samples: samples, sources: sources, orientation: eyeGaze.orientation)
        #if DEBUG
        for evaluation in outcome.evaluations {
            let c = evaluation.candidate
            print("ECHOVOICE_GAZE calibration source=\(evaluation.source.rawValue) usable=\(evaluation.isUsable) swapped=\(c?.swapsAxes ?? false) xReversed=\(c?.x.isReversed ?? false) yReversed=\(c?.y.isReversed ?? false) xSNR=\(String(format: "%.1f", c?.x.signalToNoise ?? 0)) ySNR=\(String(format: "%.1f", c?.y.signalToNoise ?? 0)) problems=\(String(describing: evaluation.xProblem)),\(String(describing: evaluation.yProblem)) x=\(c.map { String(format: "%.4f/%.4f/%.4f j%.4f", $0.x.low, $0.x.center, $0.x.high, $0.x.jitter) } ?? "-") y=\(c.map { String(format: "%.4f/%.4f/%.4f j%.4f", $0.y.low, $0.y.center, $0.y.high, $0.y.jitter) } ?? "-") enough=\(evaluation.hasEnoughSamples)")
        }
        print("ECHOVOICE_GAZE calibration chosen=\(outcome.best?.source.rawValue ?? "none")")
        #endif
        guard let best = outcome.best else {
            phase = .failed(Self.explain(outcome.evaluations, isHead: isHead))
            return
        }
        eyeGaze.saveCalibration(best)
        eyeGaze.clearChecks()
        await runDirectionCheck()
    }

    private func runDirectionCheck() async {
        var medians: [DirectionStep: CGPoint] = [:]
        for step in DirectionStep.allCases {
            phase = .checking(step)
            progress = 0
            eyeGaze.debugAimPoint = step.target
            guard await pause(milliseconds: 900) else { return }
            var points: [CGPoint] = []
            var last: TimeInterval?
            let started = ProcessInfo.processInfo.systemUptime
            while points.count < 40, ProcessInfo.processInfo.systemUptime - started < 3 {
                if let fresh = eyeGaze.freshCursor(after: last) {
                    points.append(fresh.point)
                    last = fresh.time
                }
                progress = Double(points.count) / 40
                guard await pause(milliseconds: 12) else { return }
            }
            // No samples means no evidence the cursor moved: it fails.
            medians[step] = points.isEmpty ? CGPoint(x: 0.5, y: 0.5) : PointStats(points).median
        }
        eyeGaze.debugAimPoint = nil
        let result = DirectionalCheckResult(
            center: medians[.center] ?? CGPoint(x: 0.5, y: 0.5),
            left: medians[.left] ?? CGPoint(x: 0.5, y: 0.5),
            right: medians[.right] ?? CGPoint(x: 0.5, y: 0.5),
            up: medians[.up] ?? CGPoint(x: 0.5, y: 0.5),
            down: medians[.down] ?? CGPoint(x: 0.5, y: 0.5)
        )
        eyeGaze.saveDirectionalCheck(result)
        #if DEBUG
        print("ECHOVOICE_GAZE directionCheck left=\(result.left) right=\(result.right) up=\(result.up) down=\(result.down) medians=\(medians.map { "\($0.key):\(String(format: "%.2f,%.2f", $0.value.x, $0.value.y))" }.sorted())")
        #endif
        message = result.allPassed
            ? String(localized: "Setup saved. The cursor follows you in every direction.")
            : String(localized: "Setup saved, but some directions did not follow. Try setting up again.")
        phase = .overview
    }

    private func runRecenter() async {
        phase = .recentering
        progress = 0
        eyeGaze.debugAimPoint = CGPoint(x: 0.5, y: 0.5)
        guard await pause(milliseconds: 700) else { return }
        eyeGaze.recenter()
        let started = ProcessInfo.processInfo.systemUptime
        while eyeGaze.isRecentering, ProcessInfo.processInfo.systemUptime - started < 4 {
            progress = min((ProcessInfo.processInfo.systemUptime - started) / 0.6, 1)
            guard await pause(milliseconds: 30) else { return }
        }
        eyeGaze.debugAimPoint = nil
        message = eyeGaze.isRecentering ? String(localized: "Couldn't see you steadily. Try again.") : String(localized: "Re-centered.")
        phase = .overview
    }

    /// Sleep, reporting false if the job was cancelled.
    private func pause(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return true
        } catch {
            return false
        }
    }

    /// A plain-language reason, from the most informative source's problem.
    static func explain(_ evaluations: [GazeCalibrationEvaluation], isHead: Bool) -> String {
        guard evaluations.contains(where: \.hasEnoughSamples) else {
            return String(localized: "EchoVoice lost sight of your face. Keep your face in view of the front camera, in good light, and try again.")
        }
        let problems = evaluations.flatMap { [$0.xProblem, $0.yProblem] }.compactMap { $0 }
        if problems.contains(.crossedOver) {
            return isHead
                ? String(localized: "The dots didn't line up in order. Point your nose at each dot and hold until its ring fills.")
                : String(localized: "The dots didn't line up in order. Keep your head still and look right at each dot until its ring fills.")
        }
        if problems.contains(.noResponse) {
            return isHead
                ? String(localized: "EchoVoice couldn't see enough head movement. Turn a little further toward each dot.")
                : String(localized: "EchoVoice couldn't see your eyes move enough. Look right at each dot, all the way to the edge.")
        }
        return String(localized: "Tracking was too shaky. Steady the phone — a stand or mount helps — and check the lighting.")
    }
}

/// What the current setup is and whether it has been shown to work.
struct GazeSetupSummaryCard: View {
    @Environment(EyeGazeManager.self) private var eyeGaze

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Your setup"), systemImage: "checkmark.seal.fill")
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.controlAccent)

            if let calibration = eyeGaze.calibrationInUse {
                row(String(localized: "Method"), eyeGaze.trackingMode == .headMotion ? String(localized: "Head movement") : String(localized: "Eyes (%@)", defaultValue: "Eyes (\(String(describing: calibration.source.label.lowercased())))"))
                row(String(localized: "Set up"), calibration.createdAt.formatted(date: .abbreviated, time: .shortened))
                if calibration.x.isReversed || calibration.y.isReversed || calibration.swapsAxes {
                    Text(String(localized: "EchoVoice measured and corrected this phone's direction during setup."))
                        .font(EchoFont.body(13))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let check = eyeGaze.directionalCheck {
                HStack(spacing: 8) {
                    direction(String(localized: "Left"), check.left)
                    direction(String(localized: "Right"), check.right)
                    direction(String(localized: "Up"), check.up)
                    direction(String(localized: "Down"), check.down)
                }
            } else {
                row(String(localized: "Directions"), String(localized: "Not checked yet"))
            }

            if let result = eyeGaze.accuracyResult {
                row(String(localized: "Selection check"), String(format: String(localized: "%d of %d · %.1fs · %d wrong"), result.successfulTargets, result.targetCount, result.meanAcquisitionTime, result.falseSelections))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 20))
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(EchoFont.body(15))
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(EchoFont.body(15, weight: .bold))
                .foregroundStyle(Palette.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func direction(_ name: String, _ passed: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(passed ? Palette.controlAccent : Palette.red)
            Text(name)
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "%@: %@", defaultValue: "\(String(describing: name)): \(String(describing: passed ? String(localized: "works") : String(localized: "did not follow")))"))
    }
}
