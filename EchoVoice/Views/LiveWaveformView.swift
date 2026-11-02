import SwiftUI

/// Live view of the speech analysis while someone is reading.
///
/// Three layers, drawn in one `Canvas` so a 100 Hz frame stream never creates
/// 400 SwiftUI views:
///
/// 1. **Energy bars** — short-time RMS per 25ms frame. Frames above the adaptive
///    silence threshold are drawn in lime; frames below it are drawn in a muted
///    grey. That split is not cosmetic: it *is* the voiced/unvoiced decision the
///    pause ratio is computed from, so someone watching can see the measurement
///    being made.
/// 2. **Silence threshold** — a dashed rule at `peak × silenceThresholdRatio`,
///    so the boundary the shading depends on is visible rather than implied.
/// 3. **Pitch track** — estimated F0 per voiced frame, plotted on a fixed
///    60–400 Hz scale so the line's height means the same thing every reading.
///
/// The empty state deliberately shows the axis and the threshold rule rather
/// than a blank box: the instrument should look like an instrument before the
/// first word, not like a component that failed to load.
struct LiveWaveformView: View {
    let trace: LiveSpeechTrace
    var isRecording: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 96
    private let pitchFloor = SpeechAnalysis.minF0Hz
    private let pitchCeiling = SpeechAnalysis.maxF0Hz

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Canvas(rendersAsynchronously: true) { context, size in
                drawGrid(in: &context, size: size)
                drawEnergy(in: &context, size: size)
                drawPitch(in: &context, size: size)
            }
            .frame(height: height)
            .background(Palette.canvas.opacity(0.55), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Palette.forest.opacity(0.10), lineWidth: 2)
            }
            .animation(nil, value: trace.frames.count)

        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Live speech analysis"))
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isRecording ? String(localized: "Live voice") : String(localized: "Voice recording"))
                .font(EchoFont.body(14, weight: .bold))
                .foregroundStyle(Palette.forest)
            if trace.hasSignal {
                HStack(spacing: 14) {
                    if let f0 = trace.currentF0, isRecording {
                        readout("\(Int(f0.rounded())) Hz", label: String(localized: "pitch"))
                    }
                    readout("\(Int((trace.windowPauseRatio * 100).rounded()))%", label: String(localized: "pause"))
                }
            }
        }
    }

    private func readout(_ value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(EchoFont.body(14, weight: .bold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text(label)
                .font(EchoFont.body(12))
                .foregroundStyle(Palette.faint)
        }
    }

    // MARK: Drawing

    /// Baseline plus the dashed adaptive silence threshold.
    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: size.height - 1))
        baseline.addLine(to: CGPoint(x: size.width, y: size.height - 1))
        context.stroke(baseline, with: .color(Palette.forest.opacity(0.16)), lineWidth: 1)

        guard trace.hasSignal else { return }
        let ratio = SpeechAnalysis.silenceThresholdRatio
        let y = size.height - (size.height * ratio * normalizedScale)
        guard y.isFinite, y > 0, y < size.height else { return }

        var rule = Path()
        rule.move(to: CGPoint(x: 0, y: y))
        rule.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
            rule,
            with: .color(Palette.forest.opacity(0.35)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
    }

    /// Bars are drawn against the running peak, so the waveform fills the box
    /// regardless of how loudly the person speaks or how far the phone is.
    private var normalizedScale: CGFloat { 0.86 }

    private func drawEnergy(in context: inout GraphicsContext, size: CGSize) {
        let frames = trace.frames
        guard !frames.isEmpty, trace.peakEnergy > 0 else { return }

        let slotWidth = size.width / CGFloat(LiveSpeechTrace.displayFrameCapacity)
        let barWidth = max(1, slotWidth * 0.72)
        // Newest frame sits at the right edge; a partially filled buffer grows
        // from the left rather than stretching, so bars never change width
        // mid-reading.
        for (offset, frame) in frames.enumerated() {
            let normalized = CGFloat(frame.energy / trace.peakEnergy)
            let barHeight = max(1.5, normalized * size.height * normalizedScale)
            let x = CGFloat(offset) * slotWidth
            let rect = CGRect(
                x: x + (slotWidth - barWidth) / 2,
                y: size.height - barHeight,
                width: barWidth,
                height: barHeight
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(frame.voiced ? Palette.lime : Palette.faintest.opacity(0.55))
            )
        }
    }

    private func drawPitch(in context: inout GraphicsContext, size: CGSize) {
        let frames = trace.frames
        guard frames.count > 1 else { return }

        let slotWidth = size.width / CGFloat(LiveSpeechTrace.displayFrameCapacity)
        let span = pitchCeiling - pitchFloor

        // An unvoiced gap is a break in the line, not a straight segment across
        // it — drawing through silence would invent pitch that was never there.
        var path = Path()
        var penDown = false
        for (offset, frame) in frames.enumerated() {
            guard frame.voiced, let f0 = frame.f0 else {
                penDown = false
                continue
            }
            let clamped = min(max(f0, pitchFloor), pitchCeiling)
            let normalized = CGFloat((clamped - pitchFloor) / span)
            let point = CGPoint(
                x: CGFloat(offset) * slotWidth + slotWidth / 2,
                y: size.height - (normalized * size.height * normalizedScale)
            )
            if penDown {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                penDown = true
            }
        }
        context.stroke(
            path,
            with: .color(Palette.orange),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }

    private var accessibilitySummary: String {
        guard trace.hasSignal else {
            return isRecording ? String(localized: "Listening. No speech detected yet.") : String(localized: "No reading in progress.")
        }
        let pause = Int((trace.windowPauseRatio * 100).rounded())
        if let f0 = trace.currentF0 {
            return String(localized: "Pitch %@ hertz, pausing %@ percent.", defaultValue: "Pitch \(String(describing: Int(f0.rounded()))) hertz, pausing \(String(describing: pause)) percent.")
        }
        return String(localized: "Pausing %@ percent.", defaultValue: "Pausing \(String(describing: pause)) percent.")
    }
}
