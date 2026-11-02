import Foundation

/// Turns what a conversation partner just said into replies the person can
/// speak with one selection.
///
/// The slowest part of AAC is answering. A partner asks "Do you want water?",
/// and the person has to find Yes, or find Water, while the partner waits. This
/// reads the partner's words (transcribed on the device by `PartnerListener`)
/// and puts the likely answers first.
///
/// Deterministic rules, not a model, so every suggestion can be explained:
/// - a yes/no question ("Do you…", "Are you…", "…or not?") offers Yes and No;
/// - an either/or question ("tea or coffee?") offers each option by name;
/// - any content word that matches a phrase on the person's own board offers
///   that phrase, so it plays in their banked voice if they recorded one.
///
/// It only ever offers. Nothing is spoken until the person selects a reply.
enum PartnerReplySuggester {
    struct Candidate: Sendable {
        let id: UUID
        let label: String
        let text: String
    }

    enum Reply: Hashable, Sendable {
        /// A phrase from the board (plays the banked recording when one exists).
        case phrase(UUID)
        /// A reply with no matching board phrase, spoken with text-to-speech.
        case text(String)
    }

    enum Kind: Equatable, Sendable {
        case yesNo
        case choice([String])
        case question
        case statement
        case nothing
    }

    struct Result: Equatable, Sendable {
        var kind: Kind
        var replies: [Reply]
        /// Board-phrase matches and the heard word that matched each, for the
        /// "why" line under the replies.
        var matchedWords: [String]
    }

    static let auxiliaries: Set<String> = [
        "do", "does", "did", "are", "is", "was", "were", "am", "can", "could", "will",
        "would", "should", "shall", "have", "has", "had", "may", "might", "want", "need",
        "you", "ready", "okay", "ok", "any",
        "quieres", "necesitas", "puedes", "estás", "estas", "tienes", "te", "hay", "vas", "eres",
    ]
    static let questionWords: Set<String> = ["what", "how", "where", "when", "who", "which", "why", "qué", "que", "cómo", "como", "dónde", "donde", "cuándo", "cuando", "quién", "quien", "cuál", "cual"]
    /// Words that carry no topic, so they never match a board phrase.
    static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "to", "of", "in", "on", "at", "for", "with",
        "you", "your", "yours", "i", "me", "my", "we", "us", "our", "it", "its", "this", "that",
        "these", "those", "some", "any", "do", "does", "did", "are", "is", "was", "were", "am",
        "be", "been", "can", "could", "will", "would", "should", "shall", "have", "has", "had",
        "may", "might", "want", "need", "like", "get", "go", "just", "now", "right", "not",
        "yes", "no", "please", "what", "how", "where", "when", "who", "which", "why", "there",
        "here", "then", "too", "very", "more", "little", "bit", "lot", "one", "okay", "ok",
        "hey", "hi", "well", "um", "uh", "oh", "yeah", "know", "think", "feel", "feeling",
        "el", "la", "los", "las", "un", "una", "unos", "unas", "de", "del", "al", "y", "o",
        "pero", "que", "qué", "cómo", "como", "dónde", "donde", "cuándo", "cuando", "quién",
        "yo", "tú", "tu", "te", "me", "mi", "mis", "su", "sus", "se", "lo", "le",
        "es", "está", "estás", "estas", "son", "soy", "en", "con", "por", "para",
        "quieres", "quiero", "necesitas", "necesito", "puedes", "puedo", "tienes", "tengo",
        "sí", "si", "favor", "gracias", "bien", "sientes", "siento",
    ]

    /// Longest model-written reply worth offering; past this it is a speech, not a reply.
    static let maximumSmartReplyWords = 10
    static let maximumSmartReplies = 3
    /// HELP has its own button and its own confirmation. A suggested reply must
    /// never be a second, unconfirmed way to raise an emergency.
    static let blockedSmartReplyWords: Set<String> = ["help", "emergency", "911", "ambulance", "police", "ayuda", "ayúdame", "ayudar", "ayudes", "ayuden", "auxilio", "socorro", "emergencia", "emergencias", "ambulancia", "policía", "policia", "112"]

    /// The guardrail for on-device model replies, in code rather than the prompt:
    /// trimmed, short, not an emergency, and not a repeat of a reply already
    /// shown (compared case- and punctuation-insensitively).
    static func filteredSmartReplies(_ raw: [String], existing: [String]) -> [String] {
        var seen = Set(existing.map { tokens($0).joined(separator: " ") })
        var kept: [String] = []
        for reply in raw {
            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
            let words = tokens(text)
            guard !words.isEmpty, words.count <= maximumSmartReplyWords,
                  blockedSmartReplyWords.isDisjoint(with: words),
                  !words.contains(where: { word in
                      let plain = word.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es-MX"))
                      return ["ayud", "auxili", "socorr", "emergenc", "ambulanc", "polici"].contains { plain.hasPrefix($0) }
                  }) else { continue }
            let key = words.joined(separator: " ")
            guard seen.insert(key).inserted else { continue }
            kept.append(text)
            if kept.count == maximumSmartReplies { break }
        }
        return kept
    }

    static func suggest(heard: String, candidates: [Candidate], limit: Int = 6) -> Result {
        let words = tokens(heard)
        guard !words.isEmpty else { return Result(kind: .nothing, replies: [], matchedWords: []) }

        let kind = classify(words, endsWithQuestionMark: heard.trimmingCharacters(in: .whitespaces).hasSuffix("?"))
        let matches = boardMatches(words, candidates: candidates)

        var literal: [String] = []
        var trailing: [String] = []
        switch kind {
        case .yesNo:
            literal = [String(localized: "Yes"), String(localized: "No")]
            trailing = [String(localized: "I'm not sure.")]
        case .choice(let options):
            literal = options
            trailing = [String(localized: "Neither.")]
        case .question:
            if words.starts(with: ["how", "are", "you"]) || words.contains("feeling") || words.contains("feel") || words.contains("sientes") || words.starts(with: ["cómo", "estás"]) {
                literal = [String(localized: "I'm okay."), String(localized: "I'm tired."), String(localized: "I'm in pain.")]
            }
            trailing = [String(localized: "Please repeat that.")]
        case .statement:
            trailing = [String(localized: "Okay."), String(localized: "Thank you.")]
        case .nothing:
            break
        }

        var replies: [Reply] = []
        func add(_ reply: Reply) {
            if !replies.contains(reply) { replies.append(reply) }
        }
        literal.forEach { add(resolve($0, candidates)) }
        matches.forEach { add(.phrase($0.id)) }
        trailing.forEach { add(resolve($0, candidates)) }

        return Result(kind: kind, replies: Array(replies.prefix(limit)), matchedWords: matches.map(\.word))
    }

    // MARK: - Classification

    static func classify(_ words: [String], endsWithQuestionMark: Bool) -> Kind {
        // "…or not?" asks for yes or no, not a choice between two things.
        if let orIndex = words.firstIndex(where: { $0 == "or" || $0 == "o" }), words.indices.contains(orIndex + 1),
           !["not", "no"].contains(words[orIndex + 1]), let options = choiceOptions(words, orIndex: orIndex) {
            return .choice(options)
        }
        let first = words.first(where: { !["so", "and", "well", "hey", "um", "uh", "oh", "okay"].contains($0) }) ?? ""
        if questionWords.contains(first) || words.starts(with: ["por", "qué"]) { return .question }
        if auxiliaries.contains(first) || words.suffix(2) == ["or", "not"] || words.suffix(2) == ["o", "no"] { return .yesNo }
        return endsWithQuestionMark ? .yesNo : .statement
    }

    /// "do you want tea or coffee" → ["Tea", "Coffee"]. The left option is the
    /// last word before "or"; the right one is up to three words after it, so
    /// "the red one" survives as "Red one".
    private static func choiceOptions(_ words: [String], orIndex: Int) -> [String]? {
        guard orIndex > 0 else { return nil }
        let left = words[orIndex - 1]
        let right = words[(orIndex + 1)...].prefix(3).drop(while: { ["a", "an", "the", "some", "el", "la", "los", "las", "un", "una"].contains($0) })
        guard !stopWords.contains(left), let firstRight = right.first, !stopWords.contains(firstRight) else { return nil }
        return [left, right.joined(separator: " ")].map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    // MARK: - Board matching

    private struct Match { let id: UUID; let word: String; let score: Int; let labelLength: Int }

    private static func boardMatches(_ words: [String], candidates: [Candidate]) -> [(id: UUID, word: String)] {
        let content = words.filter { !stopWords.contains($0) && $0.count >= 3 }
        guard !content.isEmpty else { return [] }

        var matches: [Match] = []
        for candidate in candidates {
            let phraseWords = Set(tokens(candidate.label + " " + candidate.text).filter { !stopWords.contains($0) })
            let hits = content.filter { word in phraseWords.contains { sameStem($0, word) } }
            if let firstHit = hits.first {
                matches.append(Match(id: candidate.id, word: firstHit, score: hits.count, labelLength: candidate.label.count))
            }
        }
        // More shared words first; then the shorter, more specific label.
        return matches
            .sorted { ($0.score, -$0.labelLength) > ($1.score, -$1.labelLength) }
            .map { ($0.id, $0.word) }
    }

    static let inflections = ["s", "es", "ed", "d", "ing", "er", "ers", "y"]

    /// "drink" matches "drinking", "water" matches "waters", but "pain" must
    /// not match "paint": the extra letters have to be a real English ending,
    /// not just any prefix overlap. A doubled final consonant counts too
    /// ("stop" → "stopping").
    static func sameStem(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard short.count >= 3, long.hasPrefix(short) else { return false }
        var ending = String(long.dropFirst(short.count))
        if let last = short.last, ending.first == last, ending.count > 1 { ending.removeFirst() }
        return inflections.contains(ending)
    }

    /// A literal reply uses the board's own phrase when one says the same thing,
    /// so "Yes" plays the person's recording of "Yes" instead of a synthetic one.
    private static func resolve(_ text: String, _ candidates: [Candidate]) -> Reply {
        let key = tokens(text).joined(separator: " ")
        if let match = candidates.first(where: {
            tokens($0.text).joined(separator: " ") == key || tokens($0.label).joined(separator: " ") == key
        }) {
            return .phrase(match.id)
        }
        return .text(text)
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }
}
