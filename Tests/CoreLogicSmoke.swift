import Foundation

final class Phrase {
    let orderIndex: Int
    let hasRecording: Bool

    init(orderIndex: Int, hasRecording: Bool) {
        self.orderIndex = orderIndex
        self.hasRecording = hasRecording
    }
}

final class CheckIn {
    let date: Date
    let wpm: Double
    let intelligibility: Double

    var hasIntelligibility: Bool { intelligibility >= 0 }

    init(date: Date, wpm: Double, intelligibility: Double = -1) {
        self.date = date
        self.wpm = wpm
        self.intelligibility = intelligibility
    }
}

@main
enum CoreLogicSmoke {
    static func main() {
        let steady = CheckinMetrics(wpm: 120, pauseRatio: 0.10, pitchStability: 0.90)
        let noBaseline = SpeechTrend.analyze(history: [steady, steady], latest: steady)
        precondition(noBaseline.baseline == nil && !noBaseline.flagged)

        let smallJitter = SpeechTrend.analyze(
            history: [steady, steady, steady],
            latest: CheckinMetrics(wpm: 114, pauseRatio: 0.10, pitchStability: 0.86)
        )
        precondition(!smallJitter.flagged, "Normal jitter should not trigger a warning")

        let realShift = SpeechTrend.analyze(
            history: [steady, steady, steady],
            latest: CheckinMetrics(wpm: 90, pauseRatio: 0.32, pitchStability: 0.60)
        )
        precondition(realShift.flagged, "A large shift from an identical baseline must remain detectable")
        precondition(realShift.reasons.count == 3)

        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let phrases = [Phrase(orderIndex: 1, hasRecording: false), Phrase(orderIndex: 0, hasRecording: true)]

        let clustered = [120.0, 115, 110, 105].enumerated().map {
            CheckIn(date: start.addingTimeInterval(Double($0.offset) * 60), wpm: $0.element)
        }
        let clusteredResult = BankingUrgency.evaluate(checkins: clustered, phrases: phrases)
        precondition(clusteredResult.level == .needsMoreReadings, "Same-sitting fatigue is not a longitudinal trend")

        let robustDecline = [120.0, 115, 110, 105].enumerated().map {
            CheckIn(date: start.addingTimeInterval(Double($0.offset) * 7 * day), wpm: $0.element)
        }
        let declineResult = BankingUrgency.evaluate(checkins: robustDecline, phrases: phrases)
        precondition(declineResult.level == .voiceChanging)
        precondition(declineResult.unbankedPhrases.map(\.orderIndex) == [1])

        let oneBadDay = [120.0, 120, 60, 120].enumerated().map {
            CheckIn(date: start.addingTimeInterval(Double($0.offset) * 7 * day), wpm: $0.element)
        }
        precondition(BankingUrgency.evaluate(checkins: oneBadDay, phrases: phrases).level == .steady)

        let emptyBank = BankingUrgency.evaluate(checkins: [], phrases: [])
        precondition(emptyBank.title == "Add your first phrase")
        precondition(!emptyBank.detail.contains("All 0"))

        print("Core trend and banking-urgency smoke tests passed")
    }
}
