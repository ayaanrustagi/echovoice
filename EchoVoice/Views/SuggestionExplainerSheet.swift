import SwiftUI

/// Explains why the board suggested the phrases it did.
///
/// The suggestion row is the visible face of an on-device Naive Bayes model. A
/// suggestion someone cannot interrogate is just the app being mysterious about
/// their own words, so this shows the whole calculation: the three log terms the
/// model summed, and the raw counts each one came from.
///
/// Everything here is read back from the same `rank` call the board sorted with,
/// so the panel cannot describe a ranking other than the one on screen.
struct SuggestionExplainerSheet: View {
    let entries: [(phrase: Phrase, explanation: AdaptivePhraseRanker.Explanation)]
    /// Resolves the previously spoken phrase's id to a readable label.
    let labelForID: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var showsArithmetic = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    ForEach(entries, id: \.phrase.id) { entry in
                        card(for: entry)
                    }
                    privacyNote
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "Why these?"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                        .font(EchoFont.body(17, weight: .bold))
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "EchoVoice learns which phrases you reach for, when you reach for them, and what you tend to say next."))
                .font(EchoFont.body(16))
                .foregroundStyle(Palette.ink)
            Text(String(localized: "It only ever learns from your own selections. There is no shared model and nothing is sent anywhere."))
                .font(EchoFont.body(14))
                .foregroundStyle(Palette.muted)

            Toggle(isOn: $showsArithmetic) {
                Text(String(localized: "Show the math"))
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.forest)
            }
            .tint(Palette.forest)
            .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(for entry: (phrase: Phrase, explanation: AdaptivePhraseRanker.Explanation)) -> some View {
        let explanation = entry.explanation
        return VStack(alignment: .leading, spacing: 10) {
            Text(entry.phrase.label)
                .font(EchoFont.display(20, weight: .extraBold))
                .foregroundStyle(Palette.forest)

            reason(
                String(localized: "Chosen %@ %@ out of %@", defaultValue: "Chosen \(String(describing: explanation.timesSelected)) \(String(describing: explanation.timesSelected == 1 ? String(localized: "time") : String(localized: "times"))) out of \(String(describing: explanation.totalSelections))"),
                detail: String(localized: "how often you use it at all")
            )
            reason(
                String(localized: "%@ of those in the %@", defaultValue: "\(String(describing: explanation.timesInThisTimeOfDay)) of those in the \(String(describing: explanation.timeBucket))"),
                detail: String(localized: "time of day")
            )
            if let afterCount = explanation.timesAfterPreviousPhrase {
                let previousLabel = explanation.previousPhraseID.flatMap(labelForID) ?? String(localized: "the last phrase")
                reason(
                    String(localized: "%@ %@ right after “%@”", defaultValue: "\(String(describing: afterCount)) \(String(describing: afterCount == 1 ? String(localized: "time") : String(localized: "times"))) right after \u{201C}\(String(describing: previousLabel))\u{201D}"),
                    detail: String(localized: "what usually follows")
                )
            } else {
                reason(String(localized: "Nothing spoken recently"), detail: String(localized: "no conversation context to use"))
            }

            if showsArithmetic {
                arithmetic(explanation)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2)
        }
    }

    private func reason(_ headline: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Palette.lime)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(EchoFont.body(13))
                    .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The literal sum the ranker sorts on. Laplace-smoothed log probabilities
    /// are negative, and less negative means more likely — said plainly here
    /// rather than left for the reader to work out.
    private func arithmetic(_ explanation: AdaptivePhraseRanker.Explanation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 2)
            Text(String(localized: "LOG PROBABILITIES"))
                .font(EchoFont.body(11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.faint)

            term("prior", explanation.prior)
            term(String(localized: "time of day"), explanation.timeLikelihood)
            term(String(localized: "previous phrase"), explanation.transitionLikelihood)

            Divider().padding(.vertical, 2)
            term("score", explanation.score, emphasized: true)

            Text(String(localized: "Closer to zero is more likely. The three terms are added, not multiplied, because they are logs — that is what keeps the numbers from underflowing."))
                .font(EchoFont.body(12))
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func term(_ name: String, _ value: Double, emphasized: Bool = false) -> some View {
        HStack {
            Text(name)
                .font(EchoFont.body(13, weight: emphasized ? .bold : .regular))
                .foregroundStyle(emphasized ? Palette.ink : Palette.muted)
            Spacer()
            Text(String(format: "%.3f", value))
                .font(EchoFont.body(13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(emphasized ? Palette.forest : Palette.ink)
        }
    }

    private var privacyNote: some View {
        Text(String(localized: "Only phrase identifiers and counts are stored. Phrase text and recordings are never part of the model, and you can erase what it has learned in Settings."))
            .font(EchoFont.body(13))
            .foregroundStyle(Palette.faint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
