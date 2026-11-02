import Foundation

/// Generates a demonstrable journal history.
///
/// The journal is only legible once there are enough readings to have a personal
/// baseline, which in normal use takes weeks. That makes the most technically
/// substantial screen in the app the one a new person — or anyone being shown
/// the app — is guaranteed to see empty.
///
/// These readings are:
///
/// - **Labelled.** Every generated `CheckIn` carries `isSample = true`, the
///   journal shows a banner while any exist, and clinician exports exclude them.
/// - **Deterministic.** A fixed seed means the same curve every time, so a
///   demonstration is reproducible and a screenshot can be retaken.
/// - **Run through the real analyzer.** Nothing here writes a `flagged` value or
///   a reason string directly; `AppStore` feeds each reading through
///   `SpeechTrend.analyze` in date order exactly as a live check-in would. The
///   flags that appear are ones the shipping logic actually produced.
enum SampleJournalHistory {
    /// One generated reading, before the trend analyzer has seen it.
    struct Reading {
        let date: Date
        let metrics: SpeechMetrics
        let intelligibility: Double
    }

    static let readingCount = 14
    static let daysBetweenReadings = 7

    /// A small deterministic PRNG. `SystemRandomNumberGenerator` would make the
    /// demonstration different on every run, which defeats the point.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }
        mutating func next() -> UInt64 {
            // xorshift64*
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2_685_821_657_736_338_717
        }
    }

    /// Readings ending at `endingAt`, oldest first.
    ///
    /// The shape is a long steady stretch followed by a gradual decline in the
    /// final readings — the pattern the trend analyzer exists to notice, and the
    /// one worth being able to show. Week-to-week jitter is deliberately larger
    /// than the drift so the baseline has a real standard deviation and the
    /// z-score check is doing actual work rather than reacting to a clean ramp.
    static func readings(endingAt endDate: Date = .now, seed: UInt64 = 20_261_026) -> [Reading] {
        var generator = SeededGenerator(seed: seed)
        let calendar = Calendar.current

        let baselineWPM = 148.0
        let baselinePause = 0.16
        let baselineStability = 0.62
        let baselineIntelligibility = 0.94

        return (0..<readingCount).map { index in
            let readingsFromEnd = readingCount - 1 - index
            let date = calendar.date(
                byAdding: .day,
                value: -readingsFromEnd * daysBetweenReadings,
                to: endDate
            ) ?? endDate

            // Decline begins only in the last third, so the first readings form
            // a genuine steady baseline rather than a slope from the start.
            let declineOnset = 9
            let declineSteps = Double(max(0, index - declineOnset))

            let jitter = { (spread: Double) in Double.random(in: -spread...spread, using: &generator) }

            let wpm = baselineWPM - declineSteps * 6.5 + jitter(4.0)
            let pauseRatio = min(0.55, baselinePause + declineSteps * 0.035 + jitter(0.015))
            let stability = max(0.05, baselineStability - declineSteps * 0.03 + jitter(0.02))
            let intelligibility = min(1, max(0, baselineIntelligibility - declineSteps * 0.03 + jitter(0.015)))

            // Articulation rate is speaking rate with pauses removed — derived
            // here the same way `SpeechAnalysis` derives it, rather than invented
            // independently, so the detail panel stays internally consistent.
            let articulationRate = pauseRatio < 1 ? wpm / (1 - pauseRatio) : wpm

            return Reading(
                date: date,
                metrics: SpeechMetrics(
                    wpm: wpm,
                    pauseRatio: pauseRatio,
                    // A plausible adult speaking F0. Not used by the trend logic,
                    // which reads pitch *stability*, but stored for the detail view.
                    pitchMean: 118 + jitter(6),
                    pitchStability: stability,
                    articulationRate: articulationRate,
                    durationSec: 6.4 + jitter(0.5)
                ),
                intelligibility: intelligibility
            )
        }
    }
}
