import Foundation

@main
enum PartnerReplySmoke {
    static func main() {
        let yes = PartnerReplySuggester.Candidate(id: UUID(), label: "Yes", text: "Yes")
        let no = PartnerReplySuggester.Candidate(id: UUID(), label: "No", text: "No")
        let water = PartnerReplySuggester.Candidate(id: UUID(), label: "Water", text: "Can I have some water, please?")
        let bathroom = PartnerReplySuggester.Candidate(id: UUID(), label: "Bathroom", text: "I need to use the bathroom.")
        let pain = PartnerReplySuggester.Candidate(id: UUID(), label: "Pain", text: "I'm in pain.")
        let tired = PartnerReplySuggester.Candidate(id: UUID(), label: "Tired", text: "I'm tired.")
        let board = [yes, no, water, bathroom, pain, tired]

        // On-device model replies: trimmed, short, no emergency words, no repeats.
        let smart = PartnerReplySuggester.filteredSmartReplies(
            ["  \"Not right now, thanks.\" ", "Yes", "Please call for help", "Maybe after lunch",
             "maybe after lunch!", "I would really like to talk about this a lot more later today", "Juice, please", "Extra"],
            existing: ["Yes", "No"]
        )
        precondition(smart == ["Not right now, thanks.", "Maybe after lunch", "Juice, please"], "\(smart)")

        func suggest(_ heard: String) -> PartnerReplySuggester.Result {
            PartnerReplySuggester.suggest(heard: heard, candidates: board)
        }

        // Yes/no question: Yes and No first, using the board's own phrases so
        // banked recordings play, then the topic match.
        let drink = suggest("Do you want some water?")
        precondition(drink.kind == .yesNo, "\(drink.kind)")
        precondition(Array(drink.replies.prefix(3)) == [.phrase(yes.id), .phrase(no.id), .phrase(water.id)], "\(drink.replies)")
        precondition(drink.matchedWords == ["water"])

        // Recognizers don't always add punctuation; the opening word still counts.
        precondition(suggest("are you comfortable").kind == .yesNo)
        precondition(suggest("you need the bathroom?").replies.contains(.phrase(bathroom.id)))

        // Either/or: each option by name, then Neither.
        let choice = suggest("Would you like tea or coffee?")
        precondition(choice.kind == .choice(["Tea", "Coffee"]), "\(choice.kind)")
        precondition(choice.replies.prefix(2) == [.text("Tea"), .text("Coffee")])
        precondition(choice.replies.contains(.text("Neither.")))
        let shirt = suggest("the blue shirt or the red one")
        precondition(shirt.kind == .choice(["Shirt", "Red one"]), "\(shirt.kind)")

        // "…or not" is a yes/no question, not a choice.
        precondition(suggest("Do you want to go outside or not").kind == .yesNo)

        // Open question about feelings offers feeling replies, preferring the
        // board's versions.
        let howAreYou = suggest("How are you feeling today?")
        precondition(howAreYou.kind == .question)
        precondition(howAreYou.replies.contains(.phrase(tired.id)) && howAreYou.replies.contains(.phrase(pain.id)), "\(howAreYou.replies)")

        // Statements get acknowledgements, plus anything on topic.
        let statement = suggest("The doctor will check your pain medicine soon.")
        precondition(statement.kind == .statement)
        precondition(statement.replies.first == .phrase(pain.id), "\(statement.replies)")
        precondition(statement.replies.contains(.text("Okay.")))

        // Stems: "drinking water" still finds Water; "paint" must not find Pain.
        precondition(suggest("is he drinking waters").replies.contains(.phrase(water.id)))
        precondition(!suggest("Did you like the paint color?").replies.contains(.phrase(pain.id)))
        precondition(PartnerReplySuggester.sameStem("drink", "drinking"))
        precondition(!PartnerReplySuggester.sameStem("pain", "painting"))

        let spanishChoice = PartnerReplySuggester.suggest(heard: "¿Quieres té o café?", candidates: [])
        precondition(spanishChoice.kind == .choice(["Té", "Café"]))
        precondition(PartnerReplySuggester.suggest(heard: "quieres agua", candidates: []).kind == .yesNo)
        precondition(PartnerReplySuggester.suggest(heard: "¿Cómo estás?", candidates: []).kind == .question)
        precondition(PartnerReplySuggester.suggest(heard: "¿Por qué?", candidates: []).kind == .question)
        precondition(PartnerReplySuggester.filteredSmartReplies(
            ["Necesito ayuda", "Ayúdame", "Pide una ambulancia", "Es una emergencia", "Ayúdenme", "Llama a la policía"],
            existing: []).isEmpty)

        // Nothing heard: nothing offered. Never more than the limit.
        precondition(suggest("   ").kind == .nothing && suggest("").replies.isEmpty)
        let many = PartnerReplySuggester.suggest(heard: "do you want water bathroom pain tired", candidates: board, limit: 4)
        precondition(many.replies.count == 4)
        precondition(Set(many.replies).count == many.replies.count, "replies must not repeat")

        print("partner-reply: all checks passed")
    }
}
