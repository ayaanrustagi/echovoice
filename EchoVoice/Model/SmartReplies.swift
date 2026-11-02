import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Extra Listen-mode replies from Apple's on-device language model.
///
/// The rule-based `PartnerReplySuggester` answers instantly and always; this
/// only adds up to three replies after it, reading the last few turns so it can
/// follow the conversation ("What did the doctor say?" → replies about that).
/// Like the sentence expander it runs entirely on the device, never speaks on
/// its own, and is checked in code by `PartnerReplySuggester.filteredSmartReplies`.
/// On a device without Apple Intelligence it returns nothing and Listen works
/// exactly as before.
enum SmartReplies {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return false }
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    fileprivate static var instructions: String {
        baseInstructions + (AppLanguage.isSpanish
            ? "\nWrite all replies in natural Latin American Spanish. Use tú. Never mention ayuda, auxilio, emergencias, llamar, or calling anyone."
            : "\nWrite all replies in English.")
    }

    private static let baseInstructions = """
        You suggest short replies for an adult who cannot speak. They tap one \
        reply and a speech app says it aloud to the person talking to them.

        Rules:
        - Write each reply in the first person, as the speaker, in under ten words.
        - Offer replies that answer differently from each other, for example \
        agreeing, declining, and asking for something else.
        - Never invent facts about the speaker: no names, places, times, \
        diagnoses, or plans that are not in the conversation.
        - Never repeat a reply that was already offered.
        - Never mention help, emergencies, or calling anyone.
        - Sound like an adult talking to an adult: plain and warm, not childish.
        """

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    fileprivate struct Suggestions {
        @Guide(description: "Short first-person replies the speaker could say next.", .count(3))
        var replies: [String]
    }
    #endif
}

/// Writes the model replies for one partner turn at a time, handing each one
/// over the moment it is complete instead of waiting for all three.
///
/// The next turn's session is created and prewarmed ahead of time, so the
/// model is already loaded when the partner stops talking. A fresh session per
/// turn keeps every prompt small; the conversation goes in the prompt instead.
@MainActor
final class SmartReplyDrafter {
    #if canImport(FoundationModels)
    /// A prewarmed `LanguageModelSession` (typed loosely to stay iOS 18 safe).
    private var ready: AnyObject?
    #endif

    func prepare() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), SmartReplies.isAvailable, ready == nil else { return }
        let session = LanguageModelSession(instructions: SmartReplies.instructions)
        session.prewarm()
        ready = session
        #endif
    }

    /// `conversation` is oldest first, each line already labelled ("They: …", "Me: …").
    /// Calls `onReply` once per reply that passes `filteredSmartReplies`.
    func draft(
        to heard: String,
        conversation: [String],
        existing: [String],
        onReply: @MainActor (String) -> Void
    ) async {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), SmartReplies.isAvailable else { return }
        let session = (ready as? LanguageModelSession) ?? LanguageModelSession(instructions: SmartReplies.instructions)
        ready = nil
        defer { prepare() }

        let context = conversation.suffix(6).joined(separator: "\n")
        let prompt = "Conversation so far:\n\(context)\n\nThey just said: \(heard)\n\nReplies already offered: \(existing.joined(separator: "; "))"
        var offered = existing
        var handed = 0
        func hand(_ raw: String) {
            guard let reply = PartnerReplySuggester.filteredSmartReplies([raw], existing: offered).first else { return }
            offered.append(reply)
            onReply(reply)
        }

        var latest: [String] = []
        do {
            let stream = session.streamResponse(
                to: prompt,
                generating: SmartReplies.Suggestions.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 160)
            )
            for try await snapshot in stream {
                latest = snapshot.content.replies ?? []
                // A reply is finished once the model has moved on to the next one.
                while handed < latest.count - 1 {
                    hand(latest[handed])
                    handed += 1
                }
            }
        } catch {
            // Guardrail, context, or cancellation: whatever finished already
            // stands, and the rule-based replies on screen stand on their own.
            return
        }
        while handed < latest.count {
            hand(latest[handed])
            handed += 1
        }
        #endif
    }
}
