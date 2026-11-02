import SwiftUI

/// Program physical NFC tags to speak a phrase, and test them by scanning.
///
/// The pitch to a family: put a tag on the bed rail for "I need help," one by the
/// door for "Come in," one on the wheelchair tray for "I'm thirsty." Tapping a
/// tag takes far less precision than finding a tile on a screen, and a visitor
/// can use it without being shown the app first.
struct TagsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @State private var nfc = NFCTagManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if nfc.isAvailable {
                        statusCard
                        scanCard
                        phraseList
                    } else {
                        unsupportedCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .readableContentWidth()
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "NFC Tags"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                // A scanned tag speaks immediately — that's the whole point of the tag.
                nfc.onPhraseScanned = { id in
                    guard let phrase = store.phrases.first(where: { $0.id == id }) else { return }
                    speaker.speak(phrase, rate: store.speechRate, volume: store.speechVolume)
                }
            }
        }
    }

    private var unsupportedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.orange)
                Text(String(localized: "NFC isn't available here"))
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            Text(nfc.unavailableReason)
                .font(EchoFont.body(14))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.orange.opacity(0.4), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusCard: some View {
        switch nfc.outcome {
        case .idle, .scanning:
            EmptyView()
        case .success(let message):
            resultBanner(message, icon: "checkmark.circle.fill", tint: Palette.forest)
        case .failure(let message):
            resultBanner(message, icon: "exclamationmark.triangle.fill", tint: Palette.orange)
        }
    }

    private func resultBanner(_ message: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            Text(message)
                .font(EchoFont.body(14, weight: .bold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Test a tag"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.forest)
            Text(String(localized: "Scan a tag you've already set up to hear it speak."))
                .font(EchoFont.body(14))
                .foregroundStyle(Palette.muted)

            Button {
                nfc.beginScanning()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.right")
                    Text(String(localized: "Scan a tag"))
                }
                .font(EchoFont.body(15, weight: .bold))
                .foregroundStyle(Palette.cream)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Palette.forest, in: .rect(cornerRadius: 16))
            }
            .accessibilityLabel(String(localized: "Scan an NFC tag"))
            .accessibilityHint(String(localized: "Hold your iPhone near a tag to hear its phrase"))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    private var phraseList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Write a phrase to a tag"))
                .font(EchoFont.body(19, weight: .bold))
                .foregroundStyle(Palette.forest)

            ForEach(store.phrases) { phrase in
                Button {
                    nfc.beginWriting(phrase: phrase)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(phrase.tint == Phrase.TintKind.forest ? Palette.forest : Palette.lime.opacity(0.3))
                                    .frame(width: 44, height: 44)
                                PhraseGlyph(
                                    symbol: phrase.symbol,
                                    color: phrase.tint == Phrase.TintKind.forest ? Palette.cream : Palette.forest
                                )
                                .frame(width: 22, height: 22)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(phrase.label)
                                    .font(EchoFont.body(17, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                Text("\u{201C}\(phrase.text)\u{201D}")
                                    .font(EchoFont.body(14))
                                    .foregroundStyle(Palette.muted)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Label(String(localized: "Write to tag"), systemImage: "wave.3.right")
                            .font(EchoFont.body(14, weight: .bold))
                            .foregroundStyle(Palette.cream)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Palette.forest, in: .rect(cornerRadius: 14))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(14)
                    .background(Palette.surface, in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 1.5))
                }
                .buttonStyle(Pressable())
                .accessibilityLabel(String(localized: "Write %@ to a tag", defaultValue: "Write \(String(describing: phrase.label)) to a tag"))
                .accessibilityHint(String(localized: "Hold your iPhone near a blank tag to save this phrase to it"))
            }
        }
    }
}
