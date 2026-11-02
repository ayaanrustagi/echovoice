import Foundation

/// Speech-trend journal analyzer.
///
/// Ported verbatim from the web build's `speechTrend.ts`. Not a black box and
/// deliberately NOT framed as a diagnostic: it's a rolling personal baseline +
/// z-score check that surfaces changes in the patient's OWN voice over time, so
/// they can raise them with a clinician. ALS/MND speech changes in
/// well-documented, measurable ways (slower rate, more/longer pauses, reduced
/// pitch control); each person is only ever compared against their own history,
/// never a population norm.
struct CheckinMetrics: Equatable, Sendable {
    var wpm: Double
    var pauseRatio: Double
    var pitchStability: Double
}

struct TrendResult: Equatable, Sendable {
    var flagged: Bool
    var reasons: [String]
    var baseline: CheckinMetrics?
}

enum SpeechTrend {
    /// Below this many prior check-ins there isn't enough history for a baseline —
    /// flagging early would just react to normal week-to-week noise.
    static let minBaselineSamples = 3
    /// ~1.5 std devs from personal baseline. Deliberately loose: false alarms
    /// erode trust faster than a missed week costs.
    static let zThreshold = 1.5

    private static func stats(_ values: [Double]) -> (mean: Double, std: Double) {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, variance.squareRoot())
    }

    /// How many std devs `latest` sits below `baseline.mean`.
    private static func declineZ(_ base: (mean: Double, std: Double), _ latest: Double) -> Double {
        // Three near-identical baseline readings can produce a zero or tiny
        // standard deviation. Use a conservative personal noise floor so one
        // WPM of jitter does not look enormous, while a real shift can still be
        // surfaced instead of becoming mathematically impossible to flag.
        return (base.mean - latest) / max(base.std, noiseFloor(for: base.mean))
    }

    /// How many std devs `latest` sits above `baseline.mean`.
    private static func riseZ(_ base: (mean: Double, std: Double), _ latest: Double) -> Double {
        return (latest - base.mean) / max(base.std, noiseFloor(for: base.mean))
    }

    static func analyze(history: [CheckinMetrics], latest: CheckinMetrics) -> TrendResult {
        guard history.count >= minBaselineSamples else {
            return TrendResult(flagged: false, reasons: [], baseline: nil)
        }

        let wpmBase = stats(history.map(\.wpm))
        let pauseBase = stats(history.map(\.pauseRatio))
        let stabilityBase = stats(history.map(\.pitchStability))

        var reasons: [String] = []

        if declineZ(wpmBase, latest.wpm) > zThreshold {
            reasons.append(String(localized: "Speaking rate is %@ words/min (usual pace: %@ words/min)", defaultValue: "Speaking rate is \(String(describing: Int(latest.wpm.rounded()))) words/min (usual pace: \(String(describing: Int(wpmBase.mean.rounded()))) words/min)"))
        }
        if latest.pauseRatio > pauseBase.mean * 1.4 && latest.pauseRatio > 0.25 {
            reasons.append(String(localized: "Pausing is %@%% of speech (usual amount: %@%%)", defaultValue: "Pausing is \(String(describing: Int((latest.pauseRatio * 100).rounded())))% of speech (usual amount: \(String(describing: Int((pauseBase.mean * 100).rounded())))%)"))
        }
        if declineZ(stabilityBase, latest.pitchStability) > zThreshold {
            reasons.append(String(localized: "Voice steadiness has changed since your recent readings"))
        }

        return TrendResult(
            flagged: !reasons.isEmpty,
            reasons: reasons,
            baseline: CheckinMetrics(wpm: wpmBase.mean, pauseRatio: pauseBase.mean, pitchStability: stabilityBase.mean)
        )
    }

    /// Percentage-point drop in word accuracy that counts as a real change rather
    /// than recognizer noise. Set high deliberately: ASR output varies run to run
    /// even for identical speech, and a false alarm here is far more alarming to a
    /// family than a missed week.
    static let intelligibilityDropThreshold = 0.12

    /// Compare this week's word accuracy against the person's own prior readings.
    /// Returns a plain-language reason when it has dropped meaningfully, else nil.
    static func intelligibilityReason(history: [Double], latest: Double) -> String? {
        guard history.count >= minBaselineSamples else { return nil }
        let baseline = stats(history)
        guard baseline.mean - latest >= intelligibilityDropThreshold else { return nil }
        return String(localized: "Speech recognition caught %@%% of the sentence (usually %@%%)", defaultValue: "Speech recognition caught \(String(describing: Int((latest * 100).rounded())))% of the sentence (usually \(String(describing: Int((baseline.mean * 100).rounded())))%)")
    }
}

// MARK: - Explainability

/// The full working for one comparison: what the personal baseline was, what
/// this reading measured, and how many standard deviations apart they are.
///
/// This exists so the app can show its arithmetic instead of only its verdict.
/// A number a person is asked to act on — "mention this to your clinician" —
/// should be inspectable, and every field here traces back to a specific
/// measurement rather than to a model weight.
struct MetricComparison: Equatable, Sendable, Identifiable {
    /// Display name, e.g. "Speaking rate".
    let name: String
    let latest: Double
    let baselineMean: Double
    let baselineStd: Double
    /// The floor substituted for `baselineStd` when the readings were nearly
    /// identical. See `SpeechTrend.declineZ`.
    let noiseFloor: Double
    /// Standard deviations away from the personal baseline, signed so that
    /// positive always means "moved in the direction that would be flagged".
    let z: Double
    /// Formatter-friendly unit suffix, e.g. String(localized: "wpm") or "%".
    let unit: String
    /// Whether this particular metric crossed its threshold on this reading.
    let crossedThreshold: Bool

    var id: String { name }

    /// Whether the standard deviation was so small that the noise floor took
    /// over. Worth surfacing: it is the difference between "unusually steady
    /// history" and "genuinely large change".
    var usedNoiseFloor: Bool { baselineStd < noiseFloor }
}

struct TrendDetail: Equatable, Sendable {
    let comparisons: [MetricComparison]
    let baselineSampleCount: Int
    /// Nil until there is enough history; the UI says so rather than showing
    /// zeroes that look like real measurements.
    var hasBaseline: Bool { baselineSampleCount >= SpeechTrend.minBaselineSamples }
}

extension SpeechTrend {
    /// Recompute the comparison behind a single reading, for display.
    ///
    /// Deliberately a separate entry point from `analyze`: the flagging path
    /// stays untouched, and this can be called for any historical check-in
    /// without re-running or mutating anything.
    static func detail(history: [CheckinMetrics], latest: CheckinMetrics) -> TrendDetail {
        guard history.count >= minBaselineSamples else {
            return TrendDetail(comparisons: [], baselineSampleCount: history.count)
        }

        let wpmBase = stats(history.map(\.wpm))
        let pauseBase = stats(history.map(\.pauseRatio))
        let stabilityBase = stats(history.map(\.pitchStability))

        let wpmZ = declineZ(wpmBase, latest.wpm)
        let pauseZ = riseZ(pauseBase, latest.pauseRatio)
        let stabilityZ = declineZ(stabilityBase, latest.pitchStability)

        return TrendDetail(
            comparisons: [
                MetricComparison(
                    name: String(localized: "Speaking rate"),
                    latest: latest.wpm,
                    baselineMean: wpmBase.mean,
                    baselineStd: wpmBase.std,
                    noiseFloor: noiseFloor(for: wpmBase.mean),
                    z: wpmZ,
                    unit: String(localized: "wpm"),
                    crossedThreshold: wpmZ > zThreshold
                ),
                MetricComparison(
                    name: String(localized: "Pausing"),
                    latest: latest.pauseRatio * 100,
                    baselineMean: pauseBase.mean * 100,
                    baselineStd: pauseBase.std * 100,
                    noiseFloor: noiseFloor(for: pauseBase.mean) * 100,
                    z: pauseZ,
                    unit: "%",
                    // Pausing uses its own rule in `analyze` — a 40% relative
                    // rise with an absolute floor — rather than the z threshold,
                    // because a pause ratio near zero makes z misleadingly large.
                    crossedThreshold: latest.pauseRatio > pauseBase.mean * 1.4 && latest.pauseRatio > 0.25
                ),
                MetricComparison(
                    name: String(localized: "Voice steadiness"),
                    latest: latest.pitchStability,
                    baselineMean: stabilityBase.mean,
                    baselineStd: stabilityBase.std,
                    noiseFloor: noiseFloor(for: stabilityBase.mean),
                    z: stabilityZ,
                    unit: "",
                    crossedThreshold: stabilityZ > zThreshold
                )
            ],
            baselineSampleCount: history.count
        )
    }

    /// Single source of truth for the personal noise floor, so `declineZ`,
    /// `riseZ`, and the explanation panel can never drift apart.
    static func noiseFloor(for mean: Double) -> Double {
        max(abs(mean) * 0.10, 0.01)
    }
}
