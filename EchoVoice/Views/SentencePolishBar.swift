import SwiftUI

/// Offers full-sentence phrasings of a core-word draft.
///
/// Placed directly under the composer, so the person sees their own words and
/// the alternatives together and picks between them. The design constraints all
/// come from the same place — this must never take the sentence away from the
/// person who is building it:
///
/// - It is offered only when there is something worth expanding. Until then it
///   stays in place, dimmed: when it appeared after the second word it pushed
///   the word grid down under the person's next tap.
/// - Nothing runs until the person taps. No draft is sent to the model as they
///   type.
/// - Choosing an option replaces the draft but does not speak it; the person
///   still presses Speak. A wrong suggestion costs an edit, never an utterance.
/// - Dismissing leaves the original words exactly as they were.
struct SentencePolishBar: View {
    @Binding var draft: String
    let expander: SentenceExpander
    /// Called when the person accepts a phrasing, so the board can clear any
    /// stale suggestion state.
    var onAccept: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch expander.state {
            case .idle:
                if expander.availability.isAvailable {
                    offerButton(isEnabled: SentenceExpander.canExpand(draft))
                }
            case .working:
                workingRow
            case .ready(let options):
                optionList(options)
            case .failed:
                failureRow
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: expander.state)
        .onChange(of: draft) { _, _ in
            // The person changed their words, so any pending options describe a
            // sentence that no longer exists.
            if case .idle = expander.state { return }
            expander.reset()
        }
    }

    private func offerButton(isEnabled: Bool) -> some View {
        Button {
            Task { await expander.expand(draft) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.quote")
                Text(String(localized: "Make it a full sentence"))
                Spacer(minLength: 0)
            }
            .font(EchoFont.body(15, weight: .bold))
            .foregroundStyle(Palette.forest)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 14)
            .background(Palette.forest.opacity(0.08), in: .rect(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .gazeSelectable(id: "polish-offer", isEnabled: isEnabled) {
            Task { await expander.expand(draft) }
        }
        .accessibilityLabel(String(localized: "Make it a full sentence"))
        .accessibilityHint(isEnabled
            ? String(localized: "Suggests complete sentences using only the words you chose. You pick one.")
            : String(localized: "Choose at least two words first."))
    }

    private var workingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Palette.forest)
            Text(String(localized: "Writing options on this device\u{2026}"))
                .font(EchoFont.body(15))
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 14)
        .background(Palette.surface, in: .rect(cornerRadius: 15))
        .accessibilityLabel(String(localized: "Writing sentence options on this device"))
    }

    private func optionList(_ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "PICK A PHRASING"))
                    .font(EchoFont.body(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.faint)
                Spacer()
                Button(String(localized: "Keep mine")) { expander.reset() }
                    .font(EchoFont.body(13, weight: .bold))
                    .foregroundStyle(Palette.forest)
                    .frame(minHeight: 44)
                    .gazeSelectable(id: "polish-dismiss") { expander.reset() }
            }

            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    accept(option)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.forest.opacity(0.5))
                            .padding(.top, 3)
                        Text(option)
                            .font(EchoFont.body(17, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Palette.surface, in: .rect(cornerRadius: 15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(Palette.forest.opacity(0.14), lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .gazeSelectable(id: "polish-option-\(index)") { accept(option) }
                .accessibilityLabel(option)
                .accessibilityHint(String(localized: "Replaces your message with this wording. It is not spoken until you press Speak."))
            }

            Text(String(localized: "Written on this device from your words only. Nothing is sent anywhere."))
                .font(EchoFont.body(11))
                .foregroundStyle(Palette.faint)
        }
    }

    private var failureRow: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Couldn't write options for that. Your words are unchanged."))
                .font(EchoFont.body(13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(String(localized: "OK")) { expander.reset() }
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.forest)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: .rect(cornerRadius: 15))
    }

    private func accept(_ option: String) {
        Haptics.tap()
        draft = option
        expander.reset()
        onAccept(option)
    }
}
