import Foundation

/// Run twice in a resource bundle so this exercises Foundation's real language
/// selection and interpolation, rather than a test-only translation lookup.
@main
struct SpanishLocalizationSmoke {
    static func main() {
        let spanish = CommandLine.arguments.contains("--spanish")
        precondition(AppLanguage.isSpanish == spanish)
        precondition(String(localized: "Speak") == (spanish ? "Hablar" : "Speak"))
        precondition(String(localized: "EchoVoice") == "EchoVoice")
        precondition(String(localized: "Call %@", defaultValue: "Call \(String("Ana"))") == (spanish ? "Llamar a Ana" : "Call Ana"))
        precondition(AACVocabulary.coreWords.contains(spanish ? "yo" : "I"))
        precondition(AACVocabulary.coreWords.contains(spanish ? "sí" : "yes"))
        let food = AACVocabulary.categories.first { $0.id == "food-drinks" }!
        precondition(food.words.contains(spanish ? "tengo sed" : "thirsty"))
        let social = AACVocabulary.categories.first { $0.id == "social-repair" }!
        precondition(social.words.contains(spanish ? "no entiendo" : "I don't understand"))
        let personal = AACVocabulary.personalMessages(
            name: "Ana", dateOfBirth: "", address: "", phone: "", email: "",
            medicalConditions: "", medications: "", allergies: "", emergencyContact: ""
        )
        precondition(personal == [spanish ? "Me llamo Ana." : "My name is Ana."])
        let yes = PartnerReplySuggester.Candidate(id: UUID(), label: spanish ? "Sí" : "Yes", text: spanish ? "Sí" : "Yes")
        let result = PartnerReplySuggester.suggest(heard: spanish ? "¿Quieres agua?" : "Do you want water?", candidates: [yes])
        precondition(result.kind == .yesNo)
        precondition(result.replies.first == .phrase(yes.id))
        precondition(result.replies.contains(.text(spanish ? "No sé bien." : "I'm not sure.")))
        let key = "Speaking rate is %@ words/min (usual pace: %@ words/min)"
        let rate = String(localized: String.LocalizationValue(key))
        precondition(String(format: rate, "60", "90") == (spanish
            ? "La velocidad es de 60 palabras/min (tu ritmo habitual: 90 palabras/min)"
            : "Speaking rate is 60 words/min (usual pace: 90 words/min)"))
        print("\(spanish ? "Spanish" : "English") bundled localization smoke tests passed")
    }
}
