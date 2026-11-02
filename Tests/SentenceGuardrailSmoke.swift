import Foundation

/// Tests the guardrail that stops the sentence expander putting words in
/// someone's mouth.
///
/// This is the highest-stakes logic added to EchoVoice. A language model
/// suggesting a sentence for a person who cannot speak is only acceptable while
/// it is provably unable to introduce meaning they did not select — so the rule
/// lives in `filtered(_:from:)` where it can be tested, not in the prompt where
/// it can only be hoped for.
///
/// The model is not exercised here; these are the deterministic checks around
/// it, run against candidate strings a model plausibly returns.
@main
struct SentenceGuardrailSmoke {
    static func main() {
        checkAcceptsGrammaticalScaffolding()
        checkRejectsInventedContent()
        checkAllowsInflections()
        checkRejectsOverlongOptions()
        checkDeduplicates()
        checkOptionCap()
        checkCanExpandGate()
        checkRejectsAddedNegationAndAnswers()
        checkRejectsAddedHelp()
        checkRejectsDroppedWords()
        checkKeepsSelectedNegation()
        checkSpanishGuardrails()
        print("Sentence guardrail smoke tests passed")
    }

    private static func checkSpanishGuardrails() {
        let options = SentenceExpander.filtered(
            ["Quisiera agua fría, por favor.", "Quisiera agua.", "No quiero agua fría.",
             "Sí, quiero agua fría.", "Necesito ayuda con agua fría.", "Quisiera agua fría y café."],
            from: "agua fría", language: "es"
        )
        precondition(options == ["Quisiera agua fría, por favor."])
        precondition(SentenceExpander.filtered(["No quiero agua."], from: "no agua", language: "es") == ["No quiero agua."])
        precondition(SentenceExpander.filtered(["Quiero agua."], from: "no agua", language: "es").isEmpty)
        precondition(SentenceExpander.filtered(["Sí, quiero agua."], from: "silla agua", language: "es").isEmpty)
        precondition(SentenceExpander.filtered(["No quiero agua."], from: "nosotros agua", language: "es").isEmpty)
        precondition(SentenceExpander.filtered(["Necesito ayuda."], from: "necesito ayuda", language: "es") == ["Necesito ayuda."])
    }

    /// Function words, auxiliaries, and politeness are what the expansion is
    /// *for*; rejecting them would leave nothing to accept.
    private static func checkAcceptsGrammaticalScaffolding() {
        let kept = SentenceExpander.filtered(
            ["Could I have some cold water, please?"],
            from: "water cold"
        )
        precondition(kept.count == 1, "rejected an option that only added function words")
    }

    /// The failure that matters: a plausible, helpful-sounding sentence carrying
    /// a request the person never made.
    private static func checkRejectsInventedContent() {
        let cases: [(candidate: String, draft: String, invented: String)] = [
            ("Could I have some cold water and a blanket?", "water cold", "blanket"),
            ("Please call my daughter about the water.", "water cold", "daughter"),
            ("I am in pain and need water.", "water cold", "pain"),
            ("Can I have water at three o'clock?", "water cold", "clock"),
            ("I am frightened, please bring water.", "water cold", "frightened")
        ]
        for testCase in cases {
            let kept = SentenceExpander.filtered([testCase.candidate], from: testCase.draft)
            precondition(
                kept.isEmpty,
                "let through an option inventing \"\(testCase.invented)\": \(testCase.candidate)"
            )
        }
    }

    /// Inflecting a selected word is rearrangement, not invention, and must
    /// survive — otherwise almost every natural sentence is rejected.
    private static func checkAllowsInflections() {
        let kept = SentenceExpander.filtered(
            ["I would like something to drink.", "I am drinking now."],
            from: "drink now"
        )
        precondition(kept.count == 2, "an inflection of a selected word was treated as new content")
    }

    /// Long options defeat the purpose: the person has to read and verify each
    /// one before speaking it.
    private static func checkRejectsOverlongOptions() {
        let long = Array(repeating: "water", count: 20).joined(separator: " ")
        precondition(
            SentenceExpander.filtered([long], from: "water cold").isEmpty,
            "accepted an option longer than the fifteen-word cap"
        )
    }

    private static func checkDeduplicates() {
        let kept = SentenceExpander.filtered(
            ["I would like water.", "i would like water.", "I would like some water."],
            from: "water like"
        )
        precondition(kept.count == 2, "case-different duplicates were both kept")
    }

    private static func checkOptionCap() {
        let candidates = [
            "I would like water.",
            "I want water.",
            "Could I have water?",
            "May I have water?",
            "Water, please."
        ]
        let kept = SentenceExpander.filtered(candidates, from: "water like want")
        precondition(
            kept.count <= SentenceExpander.optionCount,
            "returned more options than the interface shows"
        )
    }

    /// "not", "no", and "yes" are tiny words that reverse a message. The person
    /// must have chosen them; the model may not.
    private static func checkRejectsAddedNegationAndAnswers() {
        let cases: [(candidate: String, draft: String)] = [
            ("I do not want water.", "want water"),
            ("No, I want water.", "want water"),
            ("Yes, I want cold water.", "water cold")
        ]
        for testCase in cases {
            precondition(
                SentenceExpander.filtered([testCase.candidate], from: testCase.draft).isEmpty,
                "let through an option that adds a reversal: \(testCase.candidate)"
            )
        }
    }

    /// "Help" turns an ordinary message into an apparent emergency. Seen in the
    /// simulator: "I want need" came back as "I need help."
    private static func checkRejectsAddedHelp() {
        for (candidate, draft) in [("I need help.", "I want need"), ("I need help with the water.", "water cold")] {
            precondition(
                SentenceExpander.filtered([candidate], from: draft).isEmpty,
                "let through an option that adds a call for help: \(candidate)"
            )
        }
    }

    /// Dropping a chosen word changes the message as surely as adding one:
    /// "cold water" is not "water".
    private static func checkRejectsDroppedWords() {
        precondition(
            SentenceExpander.filtered(["Could I have some water, please?"], from: "water cold").isEmpty,
            "let through an option that dropped a selected word"
        )
    }

    /// A negation the person selected is theirs and must survive.
    private static func checkKeepsSelectedNegation() {
        let kept = SentenceExpander.filtered(["I don't want any water."], from: "don't want water")
        precondition(kept.count == 1, "rejected an option keeping the person's own negation")
    }

    /// The offer should not appear for input that is already a sentence, or too
    /// short to be telegraphic, or long enough that rephrasing becomes editing.
    private static func checkCanExpandGate() {
        precondition(SentenceExpander.canExpand("water cold now"), "refused a clear core-word draft")
        precondition(!SentenceExpander.canExpand(""), "offered to expand nothing")
        precondition(!SentenceExpander.canExpand("water"), "offered to expand a single word")
        precondition(
            !SentenceExpander.canExpand("I would like some water, please."),
            "offered to rewrite a finished sentence"
        )
        let tooLong = Array(repeating: "word", count: SentenceExpander.maximumInputWords + 1)
            .joined(separator: " ")
        precondition(!SentenceExpander.canExpand(tooLong), "offered to rewrite past the word cap")
    }
}
