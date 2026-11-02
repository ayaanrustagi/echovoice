import Foundation

struct AACWordCategory: Identifiable, Equatable {
    let id: String
    let title: String
    let words: [String]
}

enum AACVocabulary {
    private static let builderCategoryIDs: Set<String> = ["all-words", "core", "actions", "position", "describe"]

    /// Project Core's 36-location Universal Core vocabulary. EchoVoice keeps its
    /// original high-frequency positions first, then appends any missing words;
    /// an update therefore expands language without destroying learned motor
    /// patterns. Reference: https://project-core.com/communication-systems/
    /// Universal Core is available under CC BY-SA 4.0.
    static let universalCoreWords: [String] = [
        String(localized: "all"), String(localized: "can"), String(localized: "different"), String(localized: "do"), String(localized: "finished"), String(localized: "get"), String(localized: "go"), String(localized: "good"),
        String(localized: "he"), String(localized: "help"), String(localized: "here"), String(localized: "I"), String(localized: "in"), String(localized: "it"), String(localized: "like"), String(localized: "look"), String(localized: "make"),
        String(localized: "more"), String(localized: "not"), String(localized: "on"), String(localized: "open"), String(localized: "put"), String(localized: "same"), String(localized: "she"), String(localized: "some"), String(localized: "stop"),
        String(localized: "that"), String(localized: "turn"), String(localized: "up"), String(localized: "want"), String(localized: "what"), String(localized: "when"), String(localized: "where"), String(localized: "who"), String(localized: "why"), String(localized: "you")
    ]

    /// Sentence-building words from the PRC "100 Frequently Used Core Words"
    /// list that the board was missing (reviewed with the district AAC lead,
    /// Oct 2026). Appended after Universal Core so no learned position moves.
    static let topCoreAdditions: [String] = [
        String(localized: "and"), String(localized: "but"), String(localized: "they"), String(localized: "how"), String(localized: "for"), String(localized: "will"), String(localized: "be"), String(localized: "was"), String(localized: "were"), String(localized: "did"), String(localized: "mine"),
        String(localized: "all done")
    ]

    /// Existing positions are intentionally preserved. Stable placement is an
    /// accessibility feature for people who locate words through motor memory.
    static let coreWords: [String] = {
        var words = [
            String(localized: "I"), String(localized: "you"), String(localized: "we"), String(localized: "it"), String(localized: "this"), String(localized: "that"), String(localized: "want"), String(localized: "need"),
            String(localized: "like"), String(localized: "don't"), String(localized: "more"), String(localized: "stop"), String(localized: "go"), String(localized: "come"), String(localized: "help"),
            String(localized: "yes"), String(localized: "no"), String(localized: "please"), String(localized: "thank you"), String(localized: "not"), String(localized: "can"), String(localized: "do"),
            String(localized: "have"), String(localized: "feel"), ".", ",", "?", "!"
        ]
        for word in universalCoreWords + topCoreAdditions where !words.contains(word) {
            words.append(word)
        }
        return words
    }()

    static let categories: [AACWordCategory] = [
        .init(
            id: "core",
            title: String(localized: "Core"),
            words: coreWords
        ),
        .init(
            id: "actions",
            title: String(localized: "Actions"),
            words: [
                String(localized: "am"), String(localized: "are"), String(localized: "get"), String(localized: "make"), String(localized: "put"), String(localized: "turn"), String(localized: "tell"), String(localized: "call"),
                String(localized: "move"), String(localized: "wait"), String(localized: "know"), String(localized: "think"), String(localized: "say"), String(localized: "look"), String(localized: "listen"),
                String(localized: "read"), String(localized: "write"), String(localized: "open"), String(localized: "close"), String(localized: "start"), String(localized: "finish"), String(localized: "change"),
                String(localized: "see"), String(localized: "find"), String(localized: "drink"), String(localized: "eat"), String(localized: "take")
            ]
        ),
        .init(
            id: "position",
            title: String(localized: "Position"),
            words: [
                String(localized: "in"), String(localized: "out"), String(localized: "up"), String(localized: "down"), String(localized: "on"), String(localized: "off"), String(localized: "here"), String(localized: "there"),
                String(localized: "with"), String(localized: "without"), String(localized: "before"), String(localized: "after"), String(localized: "left"), String(localized: "right"),
                String(localized: "closer"), String(localized: "farther"), String(localized: "again"), String(localized: "slowly"), String(localized: "away"), String(localized: "under")
            ]
        ),
        .init(
            id: "describe",
            title: String(localized: "Describe"),
            words: [
                String(localized: "big"), String(localized: "little"), String(localized: "new"), String(localized: "old"), String(localized: "one"), String(localized: "fast"), String(localized: "slow"),
                String(localized: "pretty"), String(localized: "red"), String(localized: "blue"), String(localized: "yellow"), String(localized: "green"), String(localized: "purple"), String(localized: "cool")
            ]
        ),
        .init(
            id: "social-repair",
            title: String(localized: "Social & Repair"),
            words: [
                String(localized: "hello"), String(localized: "goodbye"), String(localized: "how are you?"), String(localized: "what's new?"), String(localized: "thank you"),
                String(localized: "you're welcome"), String(localized: "excuse me"), String(localized: "I'm sorry"), String(localized: "I don't know"),
                String(localized: "I understand"), String(localized: "I don't understand"), String(localized: "please wait"),
                String(localized: "give me more time"), String(localized: "please say that again"),
                String(localized: "please say it another way"), String(localized: "that is not what I meant"),
                String(localized: "yes, but..."), String(localized: "no, but..."), String(localized: "it's something else")
            ]
        ),
        .init(
            id: "people-family",
            title: String(localized: "People & Family"),
            words: [
                String(localized: "family"), String(localized: "spouse"), String(localized: "partner"), String(localized: "child"), String(localized: "grandchild"), String(localized: "parent"),
                String(localized: "sibling"), String(localized: "friend"), String(localized: "caregiver"), String(localized: "nurse"), String(localized: "doctor"), String(localized: "therapist"),
                String(localized: "I love you"), String(localized: "stay with me"), String(localized: "visit me"), String(localized: "call my family"),
                String(localized: "tell them"), String(localized: "I'm thinking of you"), String(localized: "how was your day?")
            ]
        ),
        .init(
            id: "food-drinks",
            title: String(localized: "Food & Drinks"),
            words: [
                String(localized: "water"), String(localized: "coffee"), String(localized: "tea"), String(localized: "juice"), String(localized: "breakfast"), String(localized: "lunch"), String(localized: "dinner"),
                String(localized: "snack"), String(localized: "hungry"), String(localized: "thirsty"), String(localized: "more"), String(localized: "less"), String(localized: "finished"),
                String(localized: "too hot"), String(localized: "too cold"), String(localized: "I like this"), String(localized: "I don't like this"), String(localized: "yum")
            ]
        ),
        .init(
            id: "feelings",
            title: String(localized: "Feelings"),
            words: [
                String(localized: "good"), String(localized: "bad"), String(localized: "happy"), String(localized: "sad"), String(localized: "angry"), String(localized: "worried"), String(localized: "afraid"),
                String(localized: "calm"), String(localized: "frustrated"), String(localized: "lonely"), String(localized: "confused"), String(localized: "comfortable"),
                String(localized: "uncomfortable"), String(localized: "tired"), String(localized: "I need a break"), String(localized: "hurt"), String(localized: "sick"), String(localized: "mad"), String(localized: "ready")
            ]
        ),
        .init(
            id: "entertainment",
            title: String(localized: "Entertainment"),
            words: [
                String(localized: "TV"), String(localized: "music"), String(localized: "book"), String(localized: "movie"), String(localized: "news"), String(localized: "sports"), String(localized: "play"),
                String(localized: "pause"), String(localized: "channel"), String(localized: "volume up"), String(localized: "volume down"), String(localized: "something else"),
                String(localized: "I like this"), String(localized: "I don't like this")
            ]
        ),
        .init(
            id: "health",
            title: String(localized: "Body & Health"),
            words: [
                String(localized: "I need help breathing"), String(localized: "please reposition me"), String(localized: "suction"),
                String(localized: "medication"), String(localized: "pain"), String(localized: "tired"), String(localized: "bathroom"), String(localized: "water"), String(localized: "hungry"),
                String(localized: "too hot"), String(localized: "too cold"), String(localized: "nurse"), String(localized: "doctor"), String(localized: "emergency"),
                String(localized: "I need a break"), String(localized: "please wait")
            ]
        ),
        .init(
            id: "home",
            title: String(localized: "Home"),
            words: [
                String(localized: "bed"), String(localized: "chair"), String(localized: "door"), String(localized: "window"), String(localized: "light"), String(localized: "fan"), String(localized: "blanket"),
                String(localized: "pillow"), String(localized: "remote"), String(localized: "television"), String(localized: "kitchen"), String(localized: "bedroom"), String(localized: "bathroom"),
                String(localized: "turn it on"), String(localized: "turn it off"), String(localized: "open it"), String(localized: "close it")
            ]
        ),
        .init(
            id: "sports-hobbies",
            title: String(localized: "Sports & Hobbies"),
            words: [
                String(localized: "sports"), String(localized: "football"), String(localized: "basketball"), String(localized: "baseball"), String(localized: "soccer"), String(localized: "golf"),
                String(localized: "reading"), String(localized: "gardening"), String(localized: "games"), String(localized: "art"), String(localized: "photography"), String(localized: "outdoors"),
                String(localized: "my favorite"), String(localized: "I want to watch"), String(localized: "I want to play")
            ]
        ),
        .init(
            id: "places-travel",
            title: String(localized: "Places & Travel"),
            words: [
                String(localized: "home"), String(localized: "hospital"), String(localized: "clinic"), String(localized: "school"), String(localized: "work"), String(localized: "restaurant"),
                String(localized: "store"), String(localized: "outside"), String(localized: "car"), String(localized: "bus"), String(localized: "airport"), String(localized: "here"), String(localized: "there"),
                String(localized: "where are we?"), String(localized: "I want to go home")
            ]
        ),
        .init(
            id: "time-weather",
            title: String(localized: "Time & Weather"),
            words: [
                String(localized: "now"), String(localized: "later"), String(localized: "today"), String(localized: "tomorrow"), String(localized: "yesterday"), String(localized: "morning"),
                String(localized: "afternoon"), String(localized: "evening"), String(localized: "what time?"), String(localized: "when?"), String(localized: "sunny"), String(localized: "cloudy"),
                String(localized: "raining"), String(localized: "hot"), String(localized: "cold")
            ]
        ),
        .init(
            id: "phone-technology",
            title: String(localized: "Phone & Technology"),
            words: [
                String(localized: "phone"), String(localized: "tablet"), String(localized: "computer"), String(localized: "call"), String(localized: "text"), String(localized: "answer"),
                String(localized: "video call"), String(localized: "charger"), String(localized: "internet"), String(localized: "volume up"), String(localized: "volume down"),
                String(localized: "who is calling?"), String(localized: "call them"), String(localized: "send a message")
            ]
        ),
        .init(
            id: "appointments",
            title: String(localized: "Appointments"),
            words: [
                String(localized: "appointment"), String(localized: "calendar"), String(localized: "doctor"), String(localized: "nurse"), String(localized: "therapy"), String(localized: "pharmacy"),
                String(localized: "today"), String(localized: "tomorrow"), String(localized: "what time?"), String(localized: "cancel"), String(localized: "reschedule"),
                String(localized: "please explain"), String(localized: "I have a question"), String(localized: "call my caregiver")
            ]
        ),
        .init(
            id: "money-shopping",
            title: String(localized: "Money & Shopping"),
            words: [
                String(localized: "money"), String(localized: "cash"), String(localized: "card"), String(localized: "buy"), String(localized: "pay"), String(localized: "price"), String(localized: "receipt"), String(localized: "store"),
                String(localized: "shopping"), String(localized: "too expensive"), String(localized: "I want this"), String(localized: "I don't want this"),
                String(localized: "how much?"), String(localized: "something else")
            ]
        )
    ]

    static let allBuilderWords = categories
        .filter { builderCategoryIDs.contains($0.id) }
        .flatMap(\.words)

    static func appending(_ token: String, to message: String) -> String {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return cleanMessage }
        guard !cleanMessage.isEmpty else { return cleanToken }
        if [".", ",", "?", "!"].contains(cleanToken) {
            return cleanMessage + cleanToken
        }
        return cleanMessage + " " + cleanToken
    }

    /// Categories whose tiles are already whole messages ("please say that
    /// again", "My name is …"), so a tap speaks them. Every other word, topic
    /// words like "water" included, goes into the sentence being built.
    private static let wholeMessageCategoryIDs: Set<String> = ["social-repair", "personal"]

    static func speaksImmediately(categoryID: String) -> Bool {
        wholeMessageCategoryIDs.contains(categoryID)
    }

    static func personalMessages(
        name: String,
        dateOfBirth: String,
        address: String,
        phone: String,
        email: String,
        medicalConditions: String,
        medications: String,
        allergies: String,
        emergencyContact: String
    ) -> [String] {
        [
            sentence(prefix: String(localized: "My name is"), value: name),
            sentence(prefix: String(localized: "My date of birth is"), value: dateOfBirth),
            sentence(prefix: String(localized: "My address is"), value: address),
            sentence(prefix: String(localized: "My phone number is"), value: phone),
            sentence(prefix: String(localized: "My email address is"), value: email),
            sentence(prefix: String(localized: "My medical conditions are"), value: medicalConditions),
            sentence(prefix: String(localized: "My medications are"), value: medications),
            sentence(prefix: String(localized: "My allergies are"), value: allergies),
            sentence(prefix: String(localized: "My emergency contact is"), value: emergencyContact)
        ].compactMap { $0 }
    }

    private static func sentence(prefix: String, value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return "\(prefix) \(clean)."
    }
}
