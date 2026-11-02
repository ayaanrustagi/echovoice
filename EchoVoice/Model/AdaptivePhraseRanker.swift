import Foundation

/// A tiny online Bayesian model for one-tap phrase suggestions.
///
/// The model learns from this person's selections instead of a population
/// dataset. It combines three signals: overall phrase frequency, time of day,
/// and the previously spoken phrase. Only aggregate phrase IDs and counts are
/// persisted; phrase text and audio never leave the device.
struct AdaptivePhraseRanker: Codable, Equatable, Sendable {
    private(set) var totalSelections = 0
    private var phraseCounts: [String: Int] = [:]
    private var timeCounts: [String: Int] = [:]
    private var transitionCounts: [String: Int] = [:]
    private var lastPhraseID: String?
    private var lastSelectionTime: TimeInterval?

    private static let minimumSelections = 3
    private static let contextWindow: TimeInterval = 10 * 60
    private static let timeBucketCount = 4

    mutating func record(phraseID: String, at date: Date = .now, calendar: Calendar = .current) {
        guard !phraseID.isEmpty else { return }

        phraseCounts[phraseID, default: 0] += 1
        timeCounts[timeKey(phraseID, bucket: Self.timeBucket(for: date, calendar: calendar)), default: 0] += 1

        if let previous = recentPreviousPhrase(at: date) {
            transitionCounts[transitionKey(previous, phraseID), default: 0] += 1
        }

        totalSelections += 1
        lastPhraseID = phraseID
        lastSelectionTime = date.timeIntervalSince1970
    }

    func suggestions(
        candidateIDs: [String],
        at date: Date = .now,
        limit: Int,
        calendar: Calendar = .current
    ) -> [String] {
        rank(candidateIDs: candidateIDs, at: date, limit: limit, calendar: calendar).map(\.phraseID)
    }

    /// The same ranking, with the arithmetic kept rather than discarded.
    ///
    /// `suggestions` is defined in terms of this so the explanation shown to a
    /// person can never disagree with the order they actually see. Every field
    /// is a log-probability the model genuinely summed — there is no separate
    /// "explanation" heuristic reconstructing a plausible story afterwards.
    func rank(
        candidateIDs: [String],
        at date: Date = .now,
        limit: Int,
        calendar: Calendar = .current
    ) -> [Explanation] {
        guard totalSelections >= Self.minimumSelections, limit > 0 else { return [] }

        let candidates = Array(NSOrderedSet(array: candidateIDs).compactMap { $0 as? String })
        guard !candidates.isEmpty else { return [] }

        let bucket = Self.timeBucket(for: date, calendar: calendar)
        let previous = recentPreviousPhrase(at: date)
        let classCount = Double(candidates.count)

        let ranked = candidates.enumerated().compactMap { index, phraseID -> (Explanation, Int)? in
            guard let phraseCount = phraseCounts[phraseID], phraseCount > 0 else { return nil }

            // Laplace-smoothed Naive Bayes probabilities. Log space avoids
            // underflow and turns the product into an easy-to-audit sum.
            let prior = log((Double(phraseCount) + 1) / (Double(totalSelections) + classCount))
            let timesInBucket = timeCounts[timeKey(phraseID, bucket: bucket), default: 0]
            let timeLikelihood = log(
                (Double(timesInBucket) + 1) / (Double(phraseCount) + Double(Self.timeBucketCount))
            )

            var transitionLikelihood = 0.0
            var timesAfterPrevious = 0
            if let previous {
                timesAfterPrevious = transitionCounts[transitionKey(previous, phraseID), default: 0]
                let outgoing = candidates.reduce(0) {
                    $0 + transitionCounts[transitionKey(previous, $1), default: 0]
                }
                transitionLikelihood = log(
                    (Double(timesAfterPrevious) + 1) / (Double(outgoing) + classCount)
                )
            }

            let explanation = Explanation(
                phraseID: phraseID,
                prior: prior,
                timeLikelihood: timeLikelihood,
                transitionLikelihood: transitionLikelihood,
                timesSelected: phraseCount,
                timesInThisTimeOfDay: timesInBucket,
                timesAfterPreviousPhrase: previous == nil ? nil : timesAfterPrevious,
                previousPhraseID: previous,
                timeBucket: Self.bucketName(bucket),
                totalSelections: totalSelections
            )
            return (explanation, index)
        }

        return ranked
            .sorted { lhs, rhs in
                lhs.0.score == rhs.0.score ? lhs.1 < rhs.1 : lhs.0.score > rhs.0.score
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Why one phrase was suggested. All three log terms plus the raw counts
    /// they came from, so the panel can show both the arithmetic and the
    /// plain-language version of it.
    struct Explanation: Equatable, Sendable, Identifiable {
        let phraseID: String
        let prior: Double
        let timeLikelihood: Double
        let transitionLikelihood: Double

        let timesSelected: Int
        let timesInThisTimeOfDay: Int
        /// Nil when nothing was spoken recently enough to condition on.
        let timesAfterPreviousPhrase: Int?
        let previousPhraseID: String?
        let timeBucket: String
        let totalSelections: Int

        var id: String { phraseID }

        /// The summed log-probability the ranking actually sorts on.
        var score: Double { prior + timeLikelihood + transitionLikelihood }

        /// Whether the previous-phrase term contributed at all this time.
        var usedContext: Bool { previousPhraseID != nil }
    }

    /// Human-readable label for a time bucket, for the explanation panel.
    static func bucketName(_ bucket: Int) -> String {
        switch bucket {
        case 0: return String(localized: "morning")
        case 1: return String(localized: "afternoon")
        case 2: return String(localized: "evening")
        default: return String(localized: "night")
        }
    }

    /// The time bucket a date falls in, exposed so the UI can label the row
    /// with the same bucket the model conditioned on.
    static func bucketName(for date: Date, calendar: Calendar = .current) -> String {
        bucketName(timeBucket(for: date, calendar: calendar))
    }

    private func recentPreviousPhrase(at date: Date) -> String? {
        guard let lastPhraseID, let lastSelectionTime,
              date.timeIntervalSince1970 - lastSelectionTime <= Self.contextWindow,
              date.timeIntervalSince1970 >= lastSelectionTime
        else { return nil }
        return lastPhraseID
    }

    private static func timeBucket(for date: Date, calendar: Calendar) -> Int {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return 0       // morning
        case 11..<17: return 1      // afternoon
        case 17..<22: return 2      // evening
        default: return 3           // night
        }
    }

    private func timeKey(_ phraseID: String, bucket: Int) -> String {
        "\(phraseID)|\(bucket)"
    }

    private func transitionKey(_ previous: String, _ next: String) -> String {
        "\(previous)|\(next)"
    }
}
