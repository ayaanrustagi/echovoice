import Charts
import SwiftUI

/// A simple read-and-record flow with optional on-device analysis below it.
struct SpeechJournalView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var recorder = Recorder()
    @State private var lastResult: TrendResult?
    @State private var justRecorded = false

    @State private var recognitionExplanation: String?
    @State private var lastIntelligibility: IntelligibilityAnalyzer.Result?
    @State private var selectedCheckin: CheckIn?

    /// Three prior readings are required before the next reading can be compared
    /// with a personal baseline. The fourth check-in is therefore the first
    /// meaningful milestone; an arbitrary twelve-reading goal implied otherwise.
    private let baselineGoal = SpeechTrend.minBaselineSamples + 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if store.hasSampleHistory { sampleBanner }
                    promptCard
                    recordControl
                    if recorder.state == .recording || recorder.trace.hasSignal {
                        LiveWaveformView(trace: recorder.trace, isRecording: recorder.state == .recording)
                    }
                    if let result = lastResult, justRecorded {
                        resultCard(result)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                    progressSummary
                    if !store.checkins.isEmpty {
                        trendChart
                        // Exports carry only this person's own readings, so the
                        // card would produce an empty file when the journal
                        // holds nothing but sample data.
                        if !store.realCheckins.isEmpty { clinicianReportCard }
                    }
                    disclaimer
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .readableContentWidth()
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "Voice Journal"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(item: $selectedCheckin) { checkin in
                CheckInDetailSheet(checkin: checkin, detail: store.trendDetail(for: checkin))
            }
        }
    }

    // MARK: Fixed reference-sentence prompt

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(String(localized: "Read aloud"))
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.forest)
                Spacer(minLength: 0)
                BearMascotView(mood: .listening)
                    .frame(width: 60, height: 60)
                    .padding(.vertical, -8)
            }
            Text(Reference.sentence)
                .font(EchoFont.body(19, weight: .semibold))
                .foregroundStyle(Palette.forest)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Palette.orange, Palette.orange.opacity(0.78)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20)
        )
        .shadow(color: Palette.orange.opacity(0.16), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }

    // MARK: Record control

    private var recordControl: some View {
        let recording = recorder.state == .recording
        return VStack(spacing: 8) {
            Button {
                Task { await toggleRecording() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: recording ? "waveform" : "mic.fill")
                        .symbolEffect(.variableColor.iterative, options: .repeating,
                                      isActive: recording && !reduceMotion)
                    Text(recording ? String(localized: "Stop recording") : String(localized: "Start recording"))
                }
                    .font(EchoFont.body(18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(recording ? Palette.red : Color(red: 0.09, green: 0.27, blue: 0.15),
                                in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)

            if let recognitionExplanation {
                Text(recognitionExplanation)
                    .font(EchoFont.body(14))
                    .foregroundStyle(Palette.secondaryText)
            }

            if let error = recorder.errorMessage {
                Text(error).font(EchoFont.body(14)).foregroundStyle(Palette.red)
            }
        }
    }

    private func toggleRecording() async {
        if recorder.state == .recording {
            if let outcome = await recorder.finishWithIntelligibility() {
                guard outcome.metrics.durationSec >= 3, outcome.metrics.wpm > 0 else {
                    recorder.errorMessage = String(localized: "That recording was too short. Read the full sentence, then tap stop.")
                    return
                }
                lastIntelligibility = outcome.intelligibility
                if outcome.intelligibility == nil, recognitionExplanation == nil {
                    recognitionExplanation = String(localized: "journal.recognitionFailed")
                }
                if let result = store.addCheckin(outcome.metrics, intelligibility: outcome.intelligibility) {
                    lastResult = result
                    withAnimation(reduceMotion ? nil : .snappy) { justRecorded = true }
                } else {
                    recorder.errorMessage = String(localized: "That check-in couldn't be saved. Please try again.")
                }
            }
            return
        }
        guard await recorder.requestPermission() else {
            recorder.errorMessage = String(localized: "Microphone access is needed to record your voice.")
            return
        }
        // Best-effort: a declined prompt just means no intelligibility score,
        // never a blocked check-in.
        _ = await IntelligibilityAnalyzer.requestAuthorization()
        switch IntelligibilityAnalyzer.availability {
        case .ready: recognitionExplanation = nil
        case .notAuthorized: recognitionExplanation = String(localized: "journal.recognitionDenied")
        case .unavailableOnDevice: recognitionExplanation = String(localized: "journal.recognitionUnavailable")
        }
        do {
            justRecorded = false
            lastIntelligibility = nil
            try recorder.start()
        } catch {
            recorder.errorMessage = String(localized: "Couldn't start recording.")
        }
    }

    // MARK: Result Card

    private func resultCard(_ result: TrendResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill((result.flagged ? Palette.orange : Palette.lime).opacity(0.3)).frame(width: 26, height: 26)
                    if result.flagged {
                        Text("!").font(EchoFont.display(14, weight: .extraBold)).foregroundStyle(Palette.forest)
                    } else {
                        VectorIconShape(rawPath: EchoIcon.check()).stroke(Palette.forest, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)).frame(width: 13, height: 13)
                    }
                }
                .padding(.top, 1)
                Text(result.flagged
                     ? String(localized: "Worth mentioning to your clinician")
                     : (result.baseline == nil ? String(localized: "Saved: building your personal baseline") : String(localized: "Saved: your reading looks steady")))
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            ForEach(result.reasons, id: \.self) { reason in
                Text("• \(reason)").font(EchoFont.body(15)).foregroundStyle(Palette.faint)
            }

            if let intelligibility = lastIntelligibility {
                intelligibilityRow(intelligibility)
            }

            if let ms = recorder.lastAnalysisMS {
                analysisCostRow(ms)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    /// Shows what the on-device recognizer actually heard. Seeing the transcript
    /// matters as much as the number — it's concrete evidence rather than a score
    /// the person has to take on faith.
    private func intelligibilityRow(_ result: IntelligibilityAnalyzer.Result) -> some View {
        let percent = Int((result.score * 100).rounded())
        return VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 2)

            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Palette.forest.opacity(0.08)).frame(width: 40, height: 40)
                    Text("\(percent)%")
                        .font(EchoFont.body(13, weight: .bold))
                        .foregroundStyle(Palette.forest)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Words understood"))
                        .font(EchoFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(String(localized: "%@ of %@ words, checked on this device", defaultValue: "\(String(describing: result.wordsMatched)) of \(String(describing: result.wordsExpected)) words, checked on this device"))
                        .font(EchoFont.body(13))
                        .foregroundStyle(Palette.faint)
                }
            }

            Text(String(localized: "Heard: “%@”", defaultValue: "Heard: \u{201C}\(String(describing: result.transcript))\u{201D}"))
                .font(EchoFont.body(13))
                .foregroundStyle(Palette.faint)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "%@ percent of words understood. Heard: %@", defaultValue: "\(String(describing: percent)) percent of words understood. Heard: \(String(describing: result.transcript))"))
    }

    /// Measured cost of the signal processing that just ran.
    ///
    /// A privacy claim is easy to make and hard to show. A wall-clock figure in
    /// milliseconds, taken around the analysis call itself, is the shortest
    /// honest evidence that the work happened on this device: a round trip to a
    /// server could not return in this time.
    private func analysisCostRow(_ milliseconds: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.forest)
            Text(String(localized: "Analyzed in %@ ms on this device", defaultValue: "Analyzed in \(String(describing: String(format: "%.0f", milliseconds))) ms on this device"))
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Analyzed in %@ milliseconds on this device", defaultValue: "Analyzed in \(String(describing: Int(milliseconds.rounded()))) milliseconds on this device"))
    }

    // MARK: Progress

    private var progressSummary: some View {
        let total = store.checkins.count
        let count = min(total, baselineGoal)
        let baselineReady = total >= baselineGoal
        return VStack(alignment: .leading, spacing: 8) {
            Text(baselineReady ? String(localized: "%@ recordings saved", defaultValue: "\(String(describing: total)) recordings saved") : String(localized: "%@ of %@ recordings for your baseline", defaultValue: "\(String(describing: count)) of \(String(describing: baselineGoal)) recordings for your baseline"))
                .font(EchoFont.body(15, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            if !baselineReady {
                ProgressView(value: Double(count), total: Double(baselineGoal))
                    .tint(Palette.controlAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(baselineReady
            ? String(localized: "%@ check-ins in your personal history", defaultValue: "\(String(describing: total)) check-ins in your personal history")
            : String(localized: "%@ of %@ check-ins to start your personal baseline", defaultValue: "\(String(describing: total)) of \(String(describing: baselineGoal)) check-ins to start your personal baseline"))
    }

    // MARK: Chart

    /// Speaking rate against this person's own baseline.
    ///
    /// The shaded band is the baseline mean ± the flagging threshold, computed
    /// from every reading before the most recent one. Drawing it is the point:
    /// a bare line invites comparison with some imagined normal, while a band
    /// makes it obvious that "unusual" here only ever means unusual *for you*.
    /// Flagged readings are drawn in amber so the eye lands on the readings the
    /// analyzer actually acted on.
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Speaking rate over time"))
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(String(localized: "tap a point"))
                    .font(EchoFont.body(12))
                    .foregroundStyle(Palette.faint)
            }

            Chart {
                if let band = baselineBand {
                    RectangleMark(
                        yStart: .value(String(localized: "Lower"), band.lower),
                        yEnd: .value(String(localized: "Upper"), band.upper)
                    )
                    .foregroundStyle(Palette.lime.opacity(0.20))

                    RuleMark(y: .value(String(localized: "Your usual"), band.mean))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(Palette.forest.opacity(0.45))
                }

                ForEach(store.checkins) { checkin in
                    LineMark(x: .value(String(localized: "Date"), checkin.date), y: .value(String(localized: "Words per minute"), checkin.wpm))
                        .foregroundStyle(Palette.forest)
                        .interpolationMethod(.catmullRom)
                }

                ForEach(store.checkins) { checkin in
                    PointMark(x: .value(String(localized: "Date"), checkin.date), y: .value(String(localized: "Words per minute"), checkin.wpm))
                        .foregroundStyle(checkin.flagged ? Palette.orange : Palette.forest)
                        .symbolSize(checkin.flagged ? 120 : 60)
                }
            }
            .frame(height: 210)
            .chartYAxisLabel("words/min")
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            selectNearestCheckin(at: location, proxy: proxy, geometry: geometry)
                        }
                }
            }
            .accessibilityLabel(String(localized: "Speaking rate over time"))
            .accessibilityValue(chartSummary)

            chartLegend
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    private var chartLegend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.lime.opacity(0.45))
                    .frame(width: 14, height: 8)
                Text(String(localized: "your usual range"))
                    .font(EchoFont.body(11))
                    .foregroundStyle(Palette.faint)
            }
            HStack(spacing: 5) {
                Circle().fill(Palette.orange).frame(width: 8, height: 8)
                Text(String(localized: "flagged"))
                    .font(EchoFont.body(11))
                    .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 0)
        }
    }

    /// Baseline mean and the ± threshold band, from every reading before the
    /// last one — the same history `SpeechTrend` compares the last one against.
    private var baselineBand: (mean: Double, lower: Double, upper: Double)? {
        let history = store.checkins.dropLast().map(\.wpm)
        guard history.count >= SpeechTrend.minBaselineSamples else { return nil }
        let mean = history.reduce(0, +) / Double(history.count)
        let variance = history.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(history.count)
        let spread = max(variance.squareRoot(), SpeechTrend.noiseFloor(for: mean)) * SpeechTrend.zThreshold
        return (mean, mean - spread, mean + spread)
    }

    /// Maps a tap to the nearest reading by date. Nearest-by-x rather than an
    /// exact hit test: the points are small, and a person with limited motor
    /// control should not have to land on one precisely.
    private func selectNearestCheckin(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let xInPlot = location.x - geometry[plotFrame].origin.x
        guard let tappedDate: Date = proxy.value(atX: xInPlot) else { return }
        selectedCheckin = store.checkins.min(by: {
            abs($0.date.timeIntervalSince(tappedDate)) < abs($1.date.timeIntervalSince(tappedDate))
        })
    }

    /// Sample readings are labelled everywhere they appear and can be removed in
    /// one action, so the journal never quietly mixes generated numbers into
    /// someone's own history.
    private var sampleBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Palette.forest)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Showing sample readings"))
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(String(localized: "These were generated to demonstrate the journal. They are excluded from clinician exports."))
                    .font(EchoFont.body(13))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Remove")) { store.removeSampleHistory() }
                .font(EchoFont.body(14, weight: .bold))
                .foregroundStyle(Palette.forest)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.orange.opacity(0.28), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var chartSummary: String {
        guard let first = store.checkins.first?.wpm, let last = store.checkins.last?.wpm else { return String(localized: "No readings yet") }
        return String(localized: "%@ readings, from %@ to %@ words per minute", defaultValue: "\(String(describing: store.checkins.count)) readings, from \(String(describing: Int(first.rounded()))) to \(String(describing: Int(last.rounded()))) words per minute")
    }

    // MARK: Clinician Summary Report

    private var clinicianReportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Bring to your SLP / Clinician"))
                        .font(EchoFont.body(17, weight: .bold))
                        .foregroundStyle(Palette.forest)
                    Text(store.hasSampleHistory
                         ? String(localized: "Export a PDF report or raw CSV data to review at your next appointment. Sample readings are left out.")
                         : String(localized: "Export a PDF report or raw CSV data to review at your next speech therapy appointment."))
                        .font(EchoFont.body(14))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    if let pdf = ClinicianReportGenerator.generatePDF(checkins: store.realCheckins) {
                        SharePresenter.present([pdf])
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.richtext.fill")
                        Text(String(localized: "Export PDF"))
                    }
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.cream)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.forest, in: .rect(cornerRadius: 16))
                }

                Button {
                    if let csv = ClinicianReportGenerator.generateCSV(checkins: store.realCheckins) {
                        SharePresenter.present([csv])
                    }
                } label: {
                    HStack {
                        Image(systemName: "tablecells.fill")
                        Text(String(localized: "Export CSV"))
                    }
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.forest)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.forest.opacity(0.1), in: .rect(cornerRadius: 16))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    // MARK: Disclaimer

    private var disclaimer: some View {
        Text(String(localized: "For personal tracking only. EchoVoice does not diagnose or monitor a medical condition."))
            .font(EchoFont.body(13))
            .foregroundStyle(Palette.secondaryText)
            .multilineTextAlignment(.center)
    }
}
