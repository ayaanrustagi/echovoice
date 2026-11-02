import SwiftUI
import UIKit

/// Signal Check: the hands-free diagnostic tool.
///
/// Shows every raw signal beside the live cursor, then runs a guided
/// center/left/right/up/down test and reports, per signal and per axis,
/// whether it moved the way Apple's documentation says it should, how
/// strongly, and whether the *cursor* followed. The whole run can be exported
/// as JSON, so a physical-device test produces evidence rather than an
/// impression. For setup help and development; not needed day to day.
struct GazeSignalCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EyeGazeManager.self) private var eyeGaze

    private enum Step: String, CaseIterable, Codable {
        case center, left, right, up, down

        var calibrationPoint: CalibrationPoint {
            switch self {
            case .center: return .center
            case .left: return .left
            case .right: return .right
            case .up: return .top
            case .down: return .bottom
            }
        }
    }

    struct FrameRecord: Codable {
        let t: Double
        let step: String
        let head: [Double]?
        let eyeTransform: [Double]?
        let lookAt: [Double]?
        let blendShape: [Double]?
        let cursor: [Double]?
        let blinkLeft: Double
        let blinkRight: Double
    }

    struct AxisReport: Codable {
        let low: Double, center: Double, high: Double
        let signalToNoise: Double
        let matchesDocumentation: Bool
        let problem: String?
    }

    struct SourceReport: Codable {
        let source: String
        let enoughSamples: Bool
        let horizontal: AxisReport?
        let vertical: AxisReport?
        let usableForCalibration: Bool
    }

    struct Report: Codable {
        let createdAt: Date
        let device: String
        let system: String
        let app: String
        let mode: String
        let orientation: String
        let calibratedSource: String?
        let cursorFollowed: DirectionalCheckResult
        let sources: [SourceReport]
        let frames: [FrameRecord]
    }

    @State private var activeStep: Step?
    @State private var progress = 0.0
    @State private var report: Report?
    @State private var exportURL: URL?
    @State private var job: Task<Void, Never>?
    /// The previews are drawn relative to the pose when the check opened (or
    /// when "Re-center previews" was pressed), so an uncalibrated signal's
    /// offset from the camera does not pin its dot to an edge.
    @State private var previewNeutral: GazeSignalSet?

    private var isHead: Bool { eyeGaze.trackingMode == .headMotion }

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            ZStack {
                Palette.background.ignoresSafeArea()
                if let step = activeStep {
                    stepStage(step, origin: origin)
                } else {
                    content
                }
                GazeCursorOverlay().ignoresSafeArea()
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
                cancelForGeometryChange()
            }
        }
        .onChange(of: eyeGaze.orientation) { cancelForGeometryChange() }
        .onDisappear {
            job?.cancel()
            eyeGaze.debugAimPoint = nil
        }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-EchoVoiceAutoRunSignalCheck") else { return }
            try? await Task.sleep(for: .seconds(2))
            await runTest()
            if let report {
                print("ECHOVOICE_GAZE signalCheck cursor left=\(report.cursorFollowed.left) right=\(report.cursorFollowed.right) up=\(report.cursorFollowed.up) down=\(report.cursorFollowed.down) export=\(exportURL?.lastPathComponent ?? "none") frames=\(report.frames.count)")
                for source in report.sources {
                    print("ECHOVOICE_GAZE signalCheck source=\(source.source) usable=\(source.usableForCalibration) h=\(source.horizontal.map { $0.matchesDocumentation ? "documented" : "REVERSED" } ?? "none") v=\(source.vertical.map { $0.matchesDocumentation ? "documented" : "REVERSED" } ?? "none")")
                }
            }
        }
        #endif
    }

    // MARK: Live view

    private func cancelForGeometryChange() {
        guard activeStep != nil else { return }
        job?.cancel()
        activeStep = nil
        eyeGaze.debugAimPoint = nil
        eyeGaze.resetDwell()
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    liveStatus
                    ForEach(GazeSignalSource.allCases) { source in
                        signalRow(source)
                    }
                    Button(String(localized: "Re-center previews")) { previewNeutral = eyeGaze.latestSignals }
                        .font(EchoFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.controlAccent)
                        .frame(minHeight: 44)
                    Button {
                        job?.cancel()
                        job = Task { @MainActor in await runTest() }
                    } label: {
                        Label(String(localized: "Run direction test"), systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(EchoFont.body(17, weight: .bold))
                            .foregroundStyle(Palette.onControlAccent)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Palette.controlAccent, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(!eyeGaze.isFaceTracked)

                    Text(isHead
                         ? String(localized: "Keep your eyes on the dot and turn your head toward it.")
                         : String(localized: "Keep your head still and move only your eyes to the dot."))
                        .font(EchoFont.body(13))
                        .foregroundStyle(Palette.secondaryText)

                    if let report { reportView(report) }
                }
                .padding(16)
                .readableContentWidth()
            }
            .background(Palette.background)
            .onChange(of: eyeGaze.latestSignalsAt) {
                if previewNeutral == nil { previewNeutral = eyeGaze.latestSignals }
            }
            .navigationTitle(String(localized: "Signal check"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } }
                if let exportURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: exportURL) { Label(String(localized: "Export"), systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
    }

    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyeGaze.isFaceTracked ? String(localized: "Face tracked") : String(localized: "Face not tracked"))
                .font(EchoFont.body(16, weight: .bold))
                .foregroundStyle(eyeGaze.isFaceTracked ? Palette.controlAccent : Palette.red)
            Text(String(format: String(localized: "%@ · %.0f Hz · %.0f cm · %@ · blink L %.2f R %.2f"),
                        eyeGaze.trackingMode.label, eyeGaze.trackingHz, eyeGaze.faceDistance * 100,
                        eyeGaze.orientation.rawValue, eyeGaze.leftBlink, eyeGaze.rightBlink))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Palette.primaryText)
            Text(String(localized: "Cursor uses: %@ · %@", defaultValue: "Cursor uses: \(String(describing: eyeGaze.activeSource.label)) · \(String(describing: eyeGaze.calibrationInUse == nil ? String(localized: "default mapping") : String(localized: "calibrated")))"))
                .font(EchoFont.body(13))
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 16))
    }

    private func signalRow(_ source: GazeSignalSource) -> some View {
        let raw = eyeGaze.latestSignals?[source]
        let neutral = previewNeutral?[source]
        let preview = raw.map {
            DefaultGazeMapping.normalizedPoint(raw: $0, neutral: neutral ?? $0, source: source, sensitivity: 6)
        }
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Palette.background)
                Path { p in
                    p.move(to: CGPoint(x: 28, y: 0)); p.addLine(to: CGPoint(x: 28, y: 56))
                    p.move(to: CGPoint(x: 0, y: 28)); p.addLine(to: CGPoint(x: 56, y: 28))
                }
                .stroke(Palette.faint.opacity(0.5), lineWidth: 1)
                if let preview {
                    Circle().fill(source == eyeGaze.activeSource ? Palette.orange : Palette.controlAccent)
                        .frame(width: 10, height: 10)
                        .position(x: preview.x * 56, y: preview.y * 56)
                }
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.label + (source == eyeGaze.activeSource ? String(localized: " (cursor)") : ""))
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
                Text(raw.map { String(format: "x %+.4f   y %+.4f", $0.x, $0.y) } ?? String(localized: "no reading"))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.surface, in: .rect(cornerRadius: 14))
    }

    private func reportView(_ report: Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Cursor followed"))
                .font(EchoFont.body(16, weight: .bold))
            Text(String(format: String(localized: "Left %@   Right %@   Up %@   Down %@"),
                        mark(report.cursorFollowed.left), mark(report.cursorFollowed.right),
                        mark(report.cursorFollowed.up), mark(report.cursorFollowed.down)))
                .font(.system(.body, design: .monospaced))
            ForEach(report.sources, id: \.source) { source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.source + (source.usableForCalibration ? String(localized: " — usable") : String(localized: " — not usable")))
                        .font(EchoFont.body(14, weight: .bold))
                    Text(axisLine(String(localized: "Left–right"), source.horizontal))
                    Text(axisLine(String(localized: "Up–down"), source.vertical))
                }
                .font(.system(.footnote, design: .monospaced))
            }
        }
        .foregroundStyle(Palette.primaryText)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 16))
    }

    private func mark(_ passed: Bool) -> String { passed ? "✓" : "✗" }

    private func axisLine(_ name: String, _ axis: AxisReport?) -> String {
        guard let axis else { return String(localized: "%@: no data", defaultValue: "\(String(describing: name)): no data") }
        let direction = axis.matchesDocumentation ? String(localized: "as documented") : String(localized: "REVERSED vs docs")
        return String(format: String(localized: "%@: %@, S/N %.1f%@"), name, direction, axis.signalToNoise,
                      axis.problem.map { ", \($0)" } ?? "")
    }

    // MARK: Test

    private func stepStage(_ step: Step, origin: CGPoint) -> some View {
        let window = GazeScreenMapping.windowPoint(forNormalized: step.calibrationPoint.normalizedTarget, in: eyeGaze.gazeArea)
        return ZStack {
            VStack {
                Text(isHead ? String(localized: "Turn your head toward the dot") : String(localized: "Look at the dot"))
                    .font(EchoFont.display(22, weight: .extraBold))
                    .foregroundStyle(Palette.primaryText)
                Text(step.rawValue.capitalized)
                    .font(EchoFont.body(16, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                Button(String(localized: "Stop")) {
                    job?.cancel()
                    activeStep = nil
                    eyeGaze.debugAimPoint = nil
                }
                .font(EchoFont.body(17, weight: .bold))
                .frame(minHeight: 50)
            }
            .padding(24)
            ZStack {
                Circle().stroke(Palette.forest.opacity(0.18), lineWidth: 8)
                Circle().trim(from: 0, to: progress)
                    .stroke(Palette.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(Palette.forest).frame(width: 20, height: 20)
            }
            .frame(width: 78, height: 78)
            .position(x: window.x - origin.x, y: window.y - origin.y)
        }
    }

    @MainActor
    private func runTest() async {
        var signals: [CalibrationPoint: [GazeSignalSet]] = [:]
        var cursors: [Step: [CGPoint]] = [:]
        var frames: [FrameRecord] = []
        let testStart = ProcessInfo.processInfo.systemUptime
        exportURL = nil

        for step in Step.allCases {
            activeStep = step
            progress = 0
            eyeGaze.debugAimPoint = step.calibrationPoint.normalizedTarget
            let started = ProcessInfo.processInfo.systemUptime
            var last: TimeInterval?
            var collected: [GazeSignalSet] = []
            while ProcessInfo.processInfo.systemUptime - started < 2.6 {
                if let fresh = eyeGaze.freshSignals(after: last) {
                    last = fresh.time
                    let settled = fresh.time - started > 0.9
                    if settled {
                        collected.append(fresh.signals)
                        if let cursor = eyeGaze.normalizedCursor { cursors[step, default: []].append(cursor) }
                    }
                    frames.append(record(fresh.signals, at: fresh.time - testStart, step: step))
                }
                progress = min((ProcessInfo.processInfo.systemUptime - started) / 2.6, 1)
                do { try await Task.sleep(for: .milliseconds(12)) } catch { return }
            }
            signals[step.calibrationPoint] = collected
        }
        activeStep = nil
        eyeGaze.debugAimPoint = nil

        // The builder expects some unsettled samples at the start of each
        // point; these were already settled, so it keeps a little less.
        let outcome = GazeCalibrationBuilder.evaluate(samples: signals, sources: GazeSignalSource.allCases,
                                                      orientation: eyeGaze.orientation)
        func median(_ step: Step) -> CGPoint {
            guard let points = cursors[step], !points.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
            return PointStats(points).median
        }
        let followed = DirectionalCheckResult(center: median(.center), left: median(.left), right: median(.right),
                                              up: median(.up), down: median(.down))
        let newReport = Report(
            createdAt: .now,
            device: Self.deviceModel,
            system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            app: Self.appVersion,
            mode: eyeGaze.trackingMode.rawValue,
            orientation: eyeGaze.orientation.rawValue,
            calibratedSource: eyeGaze.calibrationInUse?.source.rawValue,
            cursorFollowed: followed,
            sources: outcome.evaluations.map(Self.sourceReport),
            frames: frames
        )
        report = newReport
        exportURL = Self.write(newReport)
    }

    private func record(_ s: GazeSignalSet, at t: TimeInterval, step: Step) -> FrameRecord {
        func pair(_ p: CGPoint?) -> [Double]? { p.map { [Double($0.x), Double($0.y)] } }
        return FrameRecord(t: t, step: step.rawValue, head: pair(s.headPose), eyeTransform: pair(s.eyeTransform),
                           lookAt: pair(s.lookAtPoint), blendShape: pair(s.blendShape), cursor: pair(eyeGaze.normalizedCursor),
                           blinkLeft: eyeGaze.leftBlink, blinkRight: eyeGaze.rightBlink)
    }

    private static func sourceReport(_ evaluation: GazeCalibrationEvaluation) -> SourceReport {
        func axis(_ a: AxisCalibration?, _ problem: AxisCalibration.Problem?) -> AxisReport? {
            guard let a else { return nil }
            return AxisReport(low: Double(a.low), center: Double(a.center), high: Double(a.high),
                              signalToNoise: min(Double(a.signalToNoise), 999),
                              matchesDocumentation: !a.isReversed, problem: problem?.rawValue)
        }
        return SourceReport(
            source: evaluation.source.label,
            enoughSamples: evaluation.hasEnoughSamples,
            horizontal: axis(evaluation.candidate?.x, evaluation.xProblem),
            vertical: axis(evaluation.candidate?.y, evaluation.yProblem),
            usableForCalibration: evaluation.isUsable
        )
    }

    private static func write(_ report: Report) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return nil }
        let stamp = Int(report.createdAt.timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EchoVoice-signal-check-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
