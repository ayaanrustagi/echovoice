import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns telegraphic core-word output into full sentences the person can choose
/// from, using Apple's on-device system language model.
///
/// ## Why this exists
///
/// Building a sentence from a core-word board is slow, so people build the
/// shortest thing that carries the meaning: "water cold now". That is efficient
/// and completely understandable — and it is also why adults using AAC are
/// routinely spoken to as though they were children. The words are right; the
/// grammar the listener expects is missing, and listeners read the gap as the
/// speaker's.
///
/// Expanding those words into "Could I have some cold water, please?" costs no
/// extra selections and changes how the message lands.
///
/// ## The rules this operates under
///
/// A tool that writes sentences for someone who cannot speak is dangerous if it
/// is careless. Three constraints, all enforced here rather than left to the
/// prompt:
///
/// 1. **It never speaks on its own.** Every option is offered; the person picks
///    one or dismisses all of them. Nothing is auto-selected, and the original
///    wording always remains available as the first choice.
/// 2. **It may not change meaning.** The instructions forbid new topics, requests,
///    names, times, or feelings — the model rearranges and inflects the words
///    given to it, and `filtered(_:)` drops any option that smuggles in content
///    words the person did not select, adds a negation or a call for help, or
///    leaves out a word they did select.
/// 3. **It stays on the device.** `SystemLanguageModel` runs locally. No draft
///    ever leaves the phone, which is the only reason a communication aid can
///    responsibly touch a language model at all.
///
/// ## Availability
///
/// Requires iOS 26 and an Apple Intelligence-eligible device with the model
/// downloaded. Every other case degrades to `unavailable` with a specific
/// reason, and the caller simply never shows the control. Nothing in the core
/// communication path depends on this.
@MainActor
@Observable
final class SentenceExpander {
    enum Availability: Equatable {
        case available
        case unsupportedOS
        case deviceNotEligible
        case appleIntelligenceOff
        case modelNotReady

        var isAvailable: Bool { self == .available }

        /// Shown only in Settings, never on the board. Someone mid-conversation
        /// does not need to read about model eligibility.
        var explanation: String? {
            switch self {
            case .available: return nil
            case .unsupportedOS: return String(localized: "Requires iOS 26 or later.")
            case .deviceNotEligible: return String(localized: "This device doesn't support Apple Intelligence.")
            case .appleIntelligenceOff: return String(localized: "Turn on Apple Intelligence in Settings to use this.")
            case .modelNotReady: return String(localized: "The on-device model is still downloading.")
            }
        }
    }

    enum ExpansionState: Equatable {
        case idle
        case working
        case ready([String])
        case failed
    }

    private(set) var state: ExpansionState = .idle

    /// Longest input worth expanding. Past this the person has already written a
    /// sentence, and rephrasing it would be editing their words rather than
    /// helping them finish.
    nonisolated static let maximumInputWords = 12
    nonisolated static let optionCount = 3

    var availability: Availability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .unsupportedOS }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceOff
        case .unavailable(.modelNotReady):
            return .modelNotReady
        @unknown default:
            return .modelNotReady
        }
        #else
        return .unsupportedOS
        #endif
    }

    /// Whether this draft is worth offering to expand.
    ///
    /// Two or more words, under the cap, and no sentence-ending punctuation —
    /// punctuation means the person already finished a thought deliberately.
    nonisolated static func canExpand(_ draft: String) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { ".!?".contains($0) }) else { return false }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        return words.count >= 2 && words.count <= maximumInputWords
    }

    func reset() { state = .idle }

    func expand(_ draft: String) async {
        guard Self.canExpand(draft), availability.isAvailable else {
            state = .failed
            return
        }
        state = .working

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            state = .failed
            return
        }
        do {
            let session = LanguageModelSession(instructions: Self.instructions + (AppLanguage.isSpanish
                ? "\nWrite every option in natural Latin American Spanish, using tú when addressing someone. Never introduce no, sí, si, nunca, tampoco, ni, ayuda, ayúdame, emergencia, or their inflections unless selected."
                : "\nWrite every option in English."))
            let response = try await session.respond(
                to: "Words selected: \(draft)",
                generating: Phrasings.self,
                options: GenerationOptions(
                    // Greedy decoding: the same words should produce the same
                    // options every time. A communication aid that rephrases
                    // differently on each attempt is one a person cannot learn.
                    samplingMode: .greedy,
                    maximumResponseTokens: 220
                )
            )
            let options = Self.filtered(response.content.sentences, from: draft)
            state = options.isEmpty ? .failed : .ready(options)
        } catch {
            // Includes guardrail rejections and context-limit errors. There is
            // nothing useful to say to someone mid-sentence: the control simply
            // stops offering, and their own words are untouched.
            state = .failed
        }
        #else
        state = .failed
        #endif
    }

    // MARK: Guardrails

    private static let instructions = """
        You help an adult who cannot speak turn selected words into full sentences \
        for a speech app to say aloud.

        Rules:
        - Use ONLY the meaning of the words given. Never add a topic, request, \
        person, place, time, number, or feeling that is not already there.
        - Keep every word given. Never add "not", "no", "yes", or "help".
        - Add only grammatical words: articles, prepositions, auxiliaries, \
        pronouns, and polite forms such as "please".
        - Write in the first person, as the speaker.
        - Keep every option under fifteen words.
        - Write as an adult speaking to another adult. Never sound childlike, \
        cute, apologetic, or clinical.
        - Give distinct options, not restatements of one another.
        """

    /// Words the model is allowed to introduce.
    ///
    /// Everything here is grammatical scaffolding — function words plus the
    /// politeness forms the instructions ask for. A candidate containing any
    /// word outside this set that the person did not select is rejected, which
    /// makes rule 2 a property of the code rather than a hope about the prompt.
    nonisolated private static let permittedAddedWords: Set<String> = [
        "a", "an", "the", "i", "im", "me", "my", "mine", "myself",
        "you", "your", "we", "us", "it", "its", "this", "that", "these", "those",
        "am", "is", "are", "was", "were", "be", "been", "being",
        "do", "does", "did", "have", "has", "had",
        "can", "could", "will", "would", "should", "may", "might", "must",
        "to", "of", "in", "on", "at", "for", "with", "from", "by", "up", "down",
        "out", "off", "over", "about", "into", "some", "any", "and", "or", "but",
        // Deliberately absent: "not", "no", "yes", "help", "take". Each one
        // can reverse a message or turn it into an emergency, so the person
        // has to have chosen it.
        "so", "if", "then", "there", "here", "now",
        // Indefinite placeholders. "something to drink" adds a slot, not a
        // topic — refusing them rejects most natural expansions of a single
        // verb while blocking nothing a person did not mean.
        "something", "anything", "someone", "somebody", "one",
        "please", "thank", "thanks", "sorry", "would", "like", "want", "need",
        "get", "got", "give", "go", "going", "come"
    ]

    nonisolated private static let spanishAddedWords: Set<String> = [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "de", "del", "al",
        "a", "en", "con", "por", "para", "y", "o", "pero", "que", "yo", "me", "mi",
        "mis", "tú", "tu", "tus", "te", "se", "lo", "le", "nos", "nosotros",
        "es", "son", "soy", "estoy", "está", "están", "estar", "ser", "tengo", "tener",
        "puedo", "puedes", "podría", "podrías", "quisiera", "quiero", "necesito",
        "algo", "favor", "gracias"
    ]

    nonisolated private static let sensitiveWords: Set<String> = [
        "not", "no", "yes", "help", "sí", "si", "nunca", "jamás", "tampoco", "ni",
        "ayuda", "ayúdame", "ayudar", "ayudes", "auxilio", "emergencia"
    ]

    /// Keep only candidates that introduce no new content.
    ///
    /// Comparison is on normalized word stems, so "cold" matching "colder" does
    /// not count as invention while a genuinely new noun does. Deliberately
    /// strict: dropping a good option costs a person one tap, and letting
    /// through a bad one puts words in their mouth.
    nonisolated static func filtered(_ candidates: [String], from draft: String, language: String = AppLanguage.code) -> [String] {
        let source = Set(normalizedWords(draft))
        // Words the person chose that are not scaffolding: every option has to
        // keep them, because dropping "cold" from "water cold" changes the
        // message as much as adding a word would.
        let permitted = language == "es" ? spanishAddedWords : permittedAddedWords
        let required = source.subtracting(permitted)
        var seen = Set<String>()
        var kept: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.split(whereSeparator: \.isWhitespace).count <= 15 else { continue }

            let candidateWords = Set(normalizedWords(trimmed))
            guard sensitiveWords.intersection(candidateWords) == sensitiveWords.intersection(source) else { continue }
            let introduced = normalizedWords(trimmed).filter { word in
                if permitted.contains(word) { return false }
                // Accept a shared stem in either direction, so both inflections
                // ("drink" → "drinking") and reductions are allowed.
                return !source.contains(where: { $0.hasPrefix(word) || word.hasPrefix($0) })
            }
            guard introduced.isEmpty else { continue }

            let words = normalizedWords(trimmed)
            let keepsSelection = required.allSatisfy { chosen in
                words.contains(where: { $0.hasPrefix(chosen) || chosen.hasPrefix($0) })
            }
            guard keepsSelection else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            kept.append(trimmed)
        }
        return Array(kept.prefix(optionCount))
    }

    nonisolated private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension SentenceExpander {
    /// Guided-generation shape. Constraining the output to a fixed-size list of
    /// strings means there is no free-form text to parse and no way for the
    /// model to answer with prose instead of options.
    @Generable
    struct Phrasings {
        @Guide(
            description: "Complete, natural sentences saying exactly what the selected words mean.",
            .count(SentenceExpander.optionCount)
        )
        var sentences: [String]
    }
}
#endif
