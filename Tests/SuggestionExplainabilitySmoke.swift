import Foundation

/// Tests that the "Why these?" panel describes the ranking people actually see.
///
/// The panel is only worth anything if it cannot drift from the ranking. That is
/// structural — `suggestions` is defined in terms of `rank` — but structure is
/// easy to refactor away, so it is pinned here: same order, and a score that is
/// genuinely the sum of the three terms displayed.
@main
struct SuggestionExplainabilitySmoke {
    private static let calendar = Calendar(identifier: .gregorian)

    private static func at(hour: Int, day: Int = 1) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    static func main() {
        checkRankMatchesSuggestions()
        checkScoreIsSumOfShownTerms()
        checkCountsMatchWhatWasRecorded()
        checkTimeBucketsAreLabelled()
        checkSilentBeforeMinimumSelections()
        print("Suggestion explainability smoke tests passed")
    }

    private static func trainedRanker() -> AdaptivePhraseRanker {
        var ranker = AdaptivePhraseRanker()
        // A morning routine: coffee then paper, repeatedly.
        for day in 1...4 {
            ranker.record(phraseID: "coffee", at: at(hour: 8, day: day), calendar: calendar)
            ranker.record(phraseID: "paper", at: at(hour: 8, day: day), calendar: calendar)
        }
        // A distinct evening phrase, so time of day separates the candidates.
        for day in 1...3 {
            ranker.record(phraseID: "blanket", at: at(hour: 21, day: day), calendar: calendar)
        }
        return ranker
    }

    private static let candidates = ["coffee", "paper", "blanket"]

    private static func checkRankMatchesSuggestions() {
        let ranker = trainedRanker()
        let when = at(hour: 8, day: 5)
        let ordered = ranker.suggestions(candidateIDs: candidates, at: when, limit: 3, calendar: calendar)
        let explained = ranker.rank(candidateIDs: candidates, at: when, limit: 3, calendar: calendar)
            .map(\.phraseID)
        precondition(ordered == explained, "the explanation panel would list a different order than the board")
    }

    private static func checkScoreIsSumOfShownTerms() {
        let explanations = trainedRanker().rank(
            candidateIDs: candidates,
            at: at(hour: 8, day: 5),
            limit: 3,
            calendar: calendar
        )
        precondition(!explanations.isEmpty, "a trained ranker returned nothing to explain")
        for explanation in explanations {
            let sum = explanation.prior + explanation.timeLikelihood + explanation.transitionLikelihood
            precondition(
                abs(explanation.score - sum) < 1e-9,
                "the score shown is not the sum of the three terms shown beside it"
            )
            // Laplace-smoothed log probabilities are always negative.
            precondition(explanation.prior < 0, "prior was not a log probability")
        }
    }

    /// The plain-language lines are built from these counts, so a wrong count is
    /// a sentence that misstates the person's own history back to them.
    private static func checkCountsMatchWhatWasRecorded() {
        let explanations = trainedRanker().rank(
            candidateIDs: candidates,
            at: at(hour: 8, day: 5),
            limit: 3,
            calendar: calendar
        )
        guard let coffee = explanations.first(where: { $0.phraseID == "coffee" }) else {
            preconditionFailure("coffee was not ranked at all")
        }
        precondition(coffee.timesSelected == 4, "reported the wrong number of selections")
        precondition(coffee.timesInThisTimeOfDay == 4, "reported the wrong time-of-day count")
        precondition(coffee.totalSelections == 11, "reported the wrong total")

        guard let blanket = explanations.first(where: { $0.phraseID == "blanket" }) else {
            preconditionFailure("blanket was not ranked at all")
        }
        precondition(
            blanket.timesInThisTimeOfDay == 0,
            "an evening phrase was credited with morning selections"
        )
    }

    private static func checkTimeBucketsAreLabelled() {
        precondition(AdaptivePhraseRanker.bucketName(for: at(hour: 8), calendar: calendar) == "morning")
        precondition(AdaptivePhraseRanker.bucketName(for: at(hour: 14), calendar: calendar) == "afternoon")
        precondition(AdaptivePhraseRanker.bucketName(for: at(hour: 19), calendar: calendar) == "evening")
        precondition(AdaptivePhraseRanker.bucketName(for: at(hour: 2), calendar: calendar) == "night")
    }

    /// Two selections is not a habit. Suggesting from that noise would teach
    /// people the row is unreliable before it has a chance to be useful.
    private static func checkSilentBeforeMinimumSelections() {
        var ranker = AdaptivePhraseRanker()
        ranker.record(phraseID: "coffee", at: at(hour: 8), calendar: calendar)
        ranker.record(phraseID: "coffee", at: at(hour: 8), calendar: calendar)
        precondition(
            ranker.rank(candidateIDs: candidates, at: at(hour: 8), limit: 3, calendar: calendar).isEmpty,
            "suggested phrases before there was enough history to justify one"
        )
    }
}
