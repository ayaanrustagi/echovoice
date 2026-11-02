import Foundation

@main
struct AACVocabularySmoke {
    static func main() {
        let ids = Set(AACVocabulary.categories.map(\.id))
        precondition(ids.count == AACVocabulary.categories.count)
        precondition(ids.isSuperset(of: ["core", "social-repair", "people-family", "health", "appointments"]))
        precondition(AACVocabulary.categories.first?.words.contains("I") == true)
        precondition(AACVocabulary.categories.first?.words.contains("want") == true)
        precondition(Set(AACVocabulary.coreWords).isSuperset(of: Set(AACVocabulary.universalCoreWords)))
        precondition(AACVocabulary.categories.first(where: { $0.id == "social-repair" })?.words.contains("I don't understand") == true)
        precondition(AACVocabulary.allBuilderWords.count >= 91)
        precondition(AACVocabulary.appending("want", to: "I") == "I want")
        precondition(AACVocabulary.appending("?", to: "what time") == "what time?")
        precondition(AACVocabulary.appending(",", to: "yes") == "yes,")
        precondition(!AACVocabulary.speaksImmediately(categoryID: "core"))
        precondition(!AACVocabulary.speaksImmediately(categoryID: "all-words"))
        precondition(!AACVocabulary.speaksImmediately(categoryID: "health"))
        precondition(!AACVocabulary.speaksImmediately(categoryID: "food-drinks"))
        precondition(AACVocabulary.speaksImmediately(categoryID: "social-repair"))
        precondition(AACVocabulary.speaksImmediately(categoryID: "personal"))

        let personal = AACVocabulary.personalMessages(
            name: "Diane",
            dateOfBirth: "",
            address: "Austin, Texas",
            phone: "555-0100",
            email: "",
            medicalConditions: "ALS",
            medications: "Medication A",
            allergies: "penicillin",
            emergencyContact: "Sam, 555-0100"
        )
        precondition(personal.count == 7)
        precondition(personal[0] == "My name is Diane.")
        precondition(personal.contains("My address is Austin, Texas."))
        precondition(personal.contains("My medical conditions are ALS."))
        precondition(personal.contains("My allergies are penicillin."))
        print("AAC vocabulary and personal-message smoke tests passed")
    }
}
