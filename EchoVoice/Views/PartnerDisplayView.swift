import SwiftUI

/// A second screen for the person being spoken to.
///
/// ## The problem
///
/// Building a sentence on a board takes time, and during that time the listener
/// has nothing to look at. So they do one of three things: lean over the device,
/// which takes the conversation away from its owner; fill the silence with
/// guesses, which is worse; or drift off. Every mature AAC product that centres
/// literate adults ships some form of partner-facing view for exactly this
/// reason.
///
/// ## What this does
///
/// Shows the message as it is being built, in type large enough to read across a
/// table or a hospital bed. The listener can follow the thought forming instead
/// of waiting through silence, which means fewer interruptions and less
/// finishing of other people's sentences.
///
/// `flipped` rotates the whole display 180° so an iPad lying flat between two
/// people reads correctly from the other side — the common arrangement at a
/// bedside or a clinic table.
///
/// The display is deliberately passive: it has no controls that affect the
/// message, and closing it is the only thing a partner can do. The sentence
/// belongs to the person building it.
struct PartnerDisplayView: View {
    let draft: String
    let lastSpoken: String?
    /// True while text-to-speech is actually playing.
    let isSpeaking: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flipped = false

    /// Shown before anything is typed, so the screen explains itself to a
    /// listener who has never seen the app.
    private let placeholder = String(localized: "Writing a message\u{2026}")

    var body: some View {
        // The controls get their own row. Floated over the content, they sat on
        // top of the status line on narrower screens.
        VStack(spacing: 0) {
            controls
            VStack(spacing: 28) {
                statusLine
                messageText
                if let lastSpoken, !lastSpoken.isEmpty, lastSpoken != draft {
                    previousLine(lastSpoken)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .readableContentWidth(1100)
            .rotationEffect(.degrees(flipped ? 180 : 0))
            .animation(reduceMotion ? nil : .snappy, value: flipped)
        }
        .background(Palette.forest.ignoresSafeArea())
        // The listener's screen should not sleep mid-sentence while someone is
        // slowly building one.
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            BearMascotView(mood: isSpeaking ? .speaking : .idle, style: .onDark)
                .frame(width: 56, height: 56)

            Circle()
                .fill(isSpeaking ? Palette.lime : Palette.orange)
                .frame(width: 12, height: 12)
            Text(isSpeaking ? String(localized: "Speaking") : String(localized: "Still writing \u{2014} please wait"))
                .font(EchoFont.body(20, weight: .bold))
                .foregroundStyle(Palette.cream.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Scales down only as far as legibility across a table allows. Below that
    /// it wraps and scrolls instead, because unreadable text on the partner
    /// screen defeats the entire purpose of having one.
    private var messageText: some View {
        ScrollView {
            Text(draft.isEmpty ? placeholder : draft)
                .font(EchoFont.display(draft.isEmpty ? 40 : 64, weight: .extraBold))
                .foregroundStyle(draft.isEmpty ? Palette.cream.opacity(0.45) : Palette.cream)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityLabel(draft.isEmpty ? String(localized: "No message yet") : draft)
    }

    private func previousLine(_ text: String) -> some View {
        VStack(spacing: 6) {
            Text(String(localized: "JUST SAID"))
                .font(EchoFont.body(13, weight: .bold))
                .tracking(1)
                .foregroundStyle(Palette.cream.opacity(0.45))
            Text(text)
                .font(EchoFont.body(22))
                .foregroundStyle(Palette.cream.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Just said: %@", defaultValue: "Just said: \(String(describing: text))"))
    }

    /// Kept in the corners and visually quiet: they belong to whoever set the
    /// device down, and they must never compete with the message.
    private var controls: some View {
        HStack {
            cornerButton(String(localized: "Close"), systemImage: "xmark") { dismiss() }
            Spacer()
            cornerButton(
                flipped ? String(localized: "Face me") : String(localized: "Face them"),
                systemImage: "arrow.up.arrow.down"
            ) {
                flipped.toggle()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func cornerButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(EchoFont.body(15, weight: .bold))
                .foregroundStyle(Palette.cream.opacity(0.9))
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Palette.cream.opacity(0.14), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
