import Foundation

/// Connects the voice journal to the message bank.
///
/// Every AAC product does message banking OR speech tracking. Keeping them
/// separate is the gap: families bank phrases when they happen to think of it,
/// which is usually later than they wish they had. This reads the journal's own
/// trend and turns it into a concrete prompt — *which* phrases are still
/// unbanked, and why now is a good time to record them.
///
/// Deliberately NOT diagnostic, and the distinction is load-bearing:
/// this never predicts disease progression, never estimates time remaining, and
/// never names a condition. It only observes that a person's own readings have
/// changed and points out that a recording made today preserves today's voice.
/// That claim is true regardless of why the voice changed.
enum BankingUrgency {
    /// Fewer readings than this and there's no trend to speak of — prompting off
    /// two data points would just be noise dressed up as insight.
    static let minReadingsForTrend = 4

    /// Words-per-minute drop across the tracked window that counts as a real
    /// shift rather than normal week-to-week variation.
    static let meaningfulWPMDrop = 6.0

    /// A decline only means something if the readings are spread across real time.
    /// Four readings in one afternoon are four readings of a tiring task, not a
    /// trend — and reading the same sentence repeatedly slopes downward on fatigue
    /// alone, which is exactly the false alarm that would make a family stop
    /// trusting this prompt.
    static let minTrendSpanDays = 14.0

    enum Level {
        /// Not enough readings yet to say anything about direction.
        case needsMoreReadings
        /// Readings are holding steady.
        case steady
        /// Readings have shifted downward across the tracked window.
        case voiceChanging
    }

    struct Recommendation {
        var level: Level
        var unbankedPhrases: [Phrase]
        var bankedCount: Int
        var totalCount: Int
        /// Estimated WPM change per reading (negative = slowing). Nil without a trend.
        var wpmSlopePerReading: Double?

        var hasUnbanked: Bool { !unbankedPhrases.isEmpty }

        /// Headline shown on the banking card.
        var title: String {
            guard totalCount > 0 else { return String(localized: "Add your first phrase") }
            guard hasUnbanked else { return String(localized: "Every phrase is banked") }
            switch level {
            case .needsMoreReadings:
                return String(localized: "%@ phrases still in a synthetic voice", defaultValue: "\(String(describing: unbankedPhrases.count)) phrases still in a synthetic voice")
            case .steady:
                return String(localized: "Your voice is steady — a good time to record")
            case .voiceChanging:
                return String(localized: "Record these while they still sound like you")
            }
        }

        /// Supporting line. Never states a cause, never predicts a future.
        var detail: String {
            guard totalCount > 0 else { return String(localized: "Add a phrase on the Speak tab, then record it here in your own voice.") }
            guard hasUnbanked else {
                return String(localized: "All %@ phrases play back in your own recorded voice.", defaultValue: "All \(String(describing: totalCount)) phrases play back in your own recorded voice.")
            }
            switch level {
            case .needsMoreReadings:
                return String(localized: "Recording them means they'll play back in your real voice instead of a synthetic one.")
            case .steady:
                return String(localized: "Your recent readings are holding steady. A phrase recorded today preserves how your voice sounds today.")
            case .voiceChanging:
                return String(localized: "Your readings have shifted over your last few check-ins. A phrase recorded today preserves how you sound today — that recording doesn't change later.")
            }
        }

        /// Whether to draw the card in the attention-getting treatment.
        var isEmphasized: Bool {
            level == .voiceChanging && hasUnbanked
        }
    }

    /// Least-squares slope of WPM against reading index. Index rather than raw
    /// date keeps irregular check-in spacing from distorting the direction. Same-sitting
    /// clustering is handled by the span guard in evaluate, not by the x-axis
    /// choice — so a future reader does not reintroduce that leverage problem.
    private static func slope(of values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let n = Double(values.count)
        let xs = (0..<values.count).map(Double.init)
        let meanX = xs.reduce(0, +) / n
        let meanY = values.reduce(0, +) / n

        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, values) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator != 0 else { return nil }
        return numerator / denominator
    }

    /// Calendar days between the first and last reading. checkins is expected in
    /// chronological order, but this does not assume it — it takes the true range,
    /// so an out-of-order array cannot produce a falsely short span.
    private static func spanInDays(_ checkins: [CheckIn]) -> Double {
        guard let earliest = checkins.map(\.date).min(),
              let latest = checkins.map(\.date).max()
        else { return 0 }
        return latest.timeIntervalSince(earliest) / 86_400
    }

    /// Whether the series drifts down by more than `meaningfulWPMDrop` overall.
    private static func declines(_ values: [Double]) -> Bool {
        guard let slope = slope(of: values) else { return false }
        return slope * Double(values.count - 1) <= -meaningfulWPMDrop
    }

    /// A decline only counts if no single reading is carrying it.
    ///
    /// Without this, one tired morning or one bad recording is enough to tell a
    /// family their voice is changing — the exact false alarm that would make
    /// them stop trusting the prompt. Re-checking with each reading removed in
    /// turn means a flag requires a pattern, not a bad day.
    private static func declinesRobustly(_ values: [Double]) -> Bool {
        guard declines(values) else { return false }
        for index in values.indices {
            var withoutOne = values
            withoutOne.remove(at: index)
            guard declines(withoutOne) else { return false }
        }
        return true
    }

    /// Build the recommendation from the journal history and the current board.
    /// `checkins` is expected in chronological order (oldest first).
    static func evaluate(checkins: [CheckIn], phrases: [Phrase]) -> Recommendation {
        let unbanked = phrases
            .filter { !$0.hasRecording }
            .sorted { $0.orderIndex < $1.orderIndex }
        let bankedCount = phrases.count - unbanked.count

        guard checkins.count >= minReadingsForTrend else {
            return Recommendation(
                level: .needsMoreReadings,
                unbankedPhrases: unbanked,
                bankedCount: bankedCount,
                totalCount: phrases.count,
                wpmSlopePerReading: nil
            )
        }

        guard spanInDays(checkins) >= minTrendSpanDays else {
            return Recommendation(
                level: .needsMoreReadings,
                unbankedPhrases: unbanked,
                bankedCount: bankedCount,
                totalCount: phrases.count,
                wpmSlopePerReading: nil
            )
        }

        let wpmSeries = checkins.map(\.wpm)

        // Intelligibility — how much of the sentence the recognizer caught — is a
        // more direct signal than speaking rate, so a robust decline in it counts
        // on its own. Scaled to the same units as WPM so one threshold governs both.
        let intelligibilitySeries = checkins
            .filter(\.hasIntelligibility)
            .map { $0.intelligibility * 100 }

        let declining = declinesRobustly(wpmSeries)
            || (intelligibilitySeries.count >= minReadingsForTrend && declinesRobustly(intelligibilitySeries))

        let level: Level = declining ? .voiceChanging : .steady

        return Recommendation(
            level: level,
            unbankedPhrases: unbanked,
            bankedCount: bankedCount,
            totalCount: phrases.count,
            wpmSlopePerReading: slope(of: wpmSeries)
        )
    }
}
