import Foundation

@main
enum AdaptivePhraseRankerSmoke {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func date(hour: Int, minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: hour, minute: minute))!
        }

        let candidates = ["yes", "water", "bathroom"]
        var model = AdaptivePhraseRanker()
        precondition(model.suggestions(candidateIDs: candidates, at: date(hour: 8), limit: 3, calendar: calendar).isEmpty)

        model.record(phraseID: "water", at: date(hour: 8), calendar: calendar)
        model.record(phraseID: "water", at: date(hour: 8, minute: 1), calendar: calendar)
        model.record(phraseID: "yes", at: date(hour: 8, minute: 2), calendar: calendar)

        let morning = model.suggestions(candidateIDs: candidates, at: date(hour: 8, minute: 3), limit: 3, calendar: calendar)
        precondition(morning.first == "water", "morning use should teach a morning suggestion")
        precondition(!morning.contains("bathroom"), "unused phrases should not be invented")

        model.record(phraseID: "bathroom", at: date(hour: 20), calendar: calendar)
        model.record(phraseID: "bathroom", at: date(hour: 20, minute: 1), calendar: calendar)
        model.record(phraseID: "bathroom", at: date(hour: 20, minute: 2), calendar: calendar)

        let evening = model.suggestions(candidateIDs: candidates, at: date(hour: 20, minute: 3), limit: 1, calendar: calendar)
        precondition(evening == ["bathroom"], "time context should change the ranking")

        let encoded = try! JSONEncoder().encode(model)
        let restored = try! JSONDecoder().decode(AdaptivePhraseRanker.self, from: encoded)
        precondition(restored == model, "learned state must survive relaunch")

        print("Adaptive phrase ranker smoke tests passed")
    }
}
