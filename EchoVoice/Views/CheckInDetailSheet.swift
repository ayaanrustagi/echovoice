import SwiftUI

/// The full working behind one journal reading.
///
/// The journal's job is to give someone something concrete to bring to a
/// clinician. A single verdict — "worth mentioning" — is not that. This shows
/// what was measured, what this person's own baseline was at the time, how far
/// apart they are in standard deviations, and where the threshold sat.
///
/// It is also the honest place to say when the personal noise floor did the
/// work: three near-identical readings produce a standard deviation close to
/// zero, and without a floor a single word-per-minute of jitter would look
/// enormous. Hiding that would make a soft signal look like a hard one.
struct CheckInDetailSheet: View {
    let checkin: CheckIn
    let detail: TrendDetail

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if checkin.isSample { sampleBanner }
                    summary
                    if detail.hasBaseline {
                        ForEach(detail.comparisons) { comparison in
                            comparisonCard(comparison)
                        }
                        thresholdNote
                    } else {
                        baselineNotReady
                    }
                    rawMeasurements
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Palette.cream)
            .navigationTitle(checkin.date.formatted(date: .abbreviated, time: .shortened))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                        .font(EchoFont.body(17, weight: .bold))
                }
            }
        }
    }

    private var sampleBanner: some View {
        Label(String(localized: "Sample reading — not recorded by you"), systemImage: "info.circle.fill")
            .font(EchoFont.body(14, weight: .bold))
            .foregroundStyle(Palette.forest)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.orange.opacity(0.28), in: .rect(cornerRadius: 14))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(checkin.flagged ? String(localized: "Worth mentioning to your clinician") : String(localized: "Steady compared with your usual readings"))
                .font(EchoFont.body(18, weight: .bold))
                .foregroundStyle(Palette.ink)
            ForEach(checkin.reasons, id: \.self) { reason in
                Text("• \(reason)")
                    .font(EchoFont.body(15))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonCard(_ comparison: MetricComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(comparison.name)
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.forest)
                Spacer()
                if comparison.crossedThreshold {
                    Text(String(localized: "FLAGGED"))
                        .font(EchoFont.body(11, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.orange, in: .capsule)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(format(comparison.latest, unit: comparison.unit))
                    .font(EchoFont.display(28, weight: .extraBold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Text(String(localized: "this reading"))
                    .font(EchoFont.body(13))
                    .foregroundStyle(Palette.faint)
            }

            row(String(localized: "Your usual"), format(comparison.baselineMean, unit: comparison.unit))
            row(String(localized: "Normal spread"), "± \(format(comparison.baselineStd, unit: comparison.unit))")
            row(String(localized: "Distance from usual"), String(format: "%.2f σ", comparison.z))

            if comparison.usedNoiseFloor {
                Text(String(localized: "Your past readings were unusually close together, so EchoVoice used a minimum spread of %@ instead. Without it, ordinary week-to-week variation would look like a large change.", defaultValue: "Your past readings were unusually close together, so EchoVoice used a minimum spread of \(String(describing: format(comparison.noiseFloor, unit: comparison.unit))) instead. Without it, ordinary week-to-week variation would look like a large change."))
                    .font(EchoFont.body(12))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(
                    comparison.crossedThreshold ? Palette.orange.opacity(0.55) : Palette.forest.opacity(0.08),
                    lineWidth: 2
                )
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
                .font(EchoFont.body(14))
                .foregroundStyle(Palette.muted)
            Spacer()
            Text(value)
                .font(EchoFont.body(14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
    }

    private var thresholdNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "How the threshold works"))
                .font(EchoFont.body(15, weight: .bold))
                .foregroundStyle(Palette.forest)
            Text(String(localized: "A reading is flagged once it sits more than %@ standard deviations from your own baseline, built from your %@ earlier readings. You are never compared with anyone else. Pausing uses its own rule instead, because a pause ratio near zero makes standard deviations misleading.", defaultValue: "A reading is flagged once it sits more than \(String(describing: String(format: "%.1f", SpeechTrend.zThreshold))) standard deviations from your own baseline, built from your \(String(describing: detail.baselineSampleCount)) earlier readings. You are never compared with anyone else. Pausing uses its own rule instead, because a pause ratio near zero makes standard deviations misleading."))
                .font(EchoFont.body(13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvas.opacity(0.6), in: .rect(cornerRadius: 18))
    }

    private var baselineNotReady: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "No personal baseline yet"))
                .font(EchoFont.body(15, weight: .bold))
                .foregroundStyle(Palette.forest)
            Text(String(localized: "This reading came before you had %@ earlier ones to compare against, so it was saved without being judged. Comparing against fewer readings would mostly react to ordinary variation.", defaultValue: "This reading came before you had \(String(describing: SpeechTrend.minBaselineSamples)) earlier ones to compare against, so it was saved without being judged. Comparing against fewer readings would mostly react to ordinary variation."))
                .font(EchoFont.body(13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvas.opacity(0.6), in: .rect(cornerRadius: 18))
    }

    /// The stored numbers as measured, including the ones the trend logic does
    /// not act on. Articulation rate in particular is worth showing next to
    /// speaking rate: the gap between them is pausing.
    private var rawMeasurements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "MEASURED ON THIS DEVICE"))
                .font(EchoFont.body(11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.faint)
            row(String(localized: "Speaking rate"), String(format: String(localized: "%.0f wpm"), checkin.wpm))
            row(String(localized: "Articulation rate"), String(format: String(localized: "%.0f wpm"), checkin.articulationRate))
            row(String(localized: "Pausing"), String(format: "%.0f%%", checkin.pauseRatio * 100))
            row(String(localized: "Pitch stability"), String(format: "%.2f", checkin.pitch))
            if checkin.hasIntelligibility {
                row(String(localized: "Words understood"), String(format: "%.0f%%", checkin.intelligibility * 100))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2)
        }
    }

    private func format(_ value: Double, unit: String) -> String {
        let digits = abs(value) < 10 ? 2 : 0
        let number = String(format: "%.\(digits)f", value)
        return unit.isEmpty ? number : (unit == "%" ? "\(number)%" : "\(number) \(unit)")
    }
}
