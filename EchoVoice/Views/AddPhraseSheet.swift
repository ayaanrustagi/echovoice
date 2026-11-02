import SwiftUI

/// Caregiver flow for adding a phrase to the board. Deliberately explicit —
/// every word the app can ever speak is typed by a human here; the app never
/// authors speech on its own.
struct AddPhraseSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var text = ""
    @State private var symbol: Phrase.Symbol = .custom
    @State private var tint: Phrase.TintKind = .lime
    @State private var shortcut = ""
    @State private var showSaveError = false

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty &&
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field(String(localized: "BUTTON LABEL"), prompt: String(localized: "e.g. Music"), value: $label)
                    field(String(localized: "SPOKEN SENTENCE"), prompt: String(localized: "e.g. Can you play some music?"), value: $text)
                    field(String(localized: "PERSONAL SHORTCUT (OPTIONAL)"), prompt: String(localized: "e.g. mus"), value: $shortcut)

                    Text(String(localized: "Type this short cue in the Conversation workspace to retrieve the exact sentence. It stays on this device."))
                        .font(EchoFont.body(13))
                        .foregroundStyle(Palette.muted)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionCaption(String(localized: "ICON"))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                            ForEach(Phrase.Symbol.allCases, id: \.self) { s in
                                Button { symbol = s } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(symbol == s ? Palette.lime : Palette.surface)
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Palette.forest.opacity(symbol == s ? 0 : 0.12), lineWidth: 2)
                                        PhraseGlyph(symbol: s, color: Palette.forest)
                                            .scaleEffect(0.8)
                                    }
                                    .frame(width: 44, height: 44)
                                }
                                .buttonStyle(Pressable())
                                .accessibilityLabel(String(localized: "Icon %@", defaultValue: "Icon \(String(describing: s.localizedName))"))
                                .accessibilityAddTraits(symbol == s ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionCaption(String(localized: "COLOR"))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                            ForEach(Phrase.TintKind.allCases, id: \.self) { t in
                                Button { tint = t } label: {
                                    ZStack {
                                        Circle().fill(t.background)
                                        Circle().strokeBorder(
                                            tint == t ? Palette.orange : Palette.forest.opacity(0.15),
                                            lineWidth: tint == t ? 3 : 2
                                        )
                                    }
                                    .frame(width: 44, height: 44)
                                }
                                .buttonStyle(Pressable())
                                .accessibilityLabel(String(localized: "Color %@", defaultValue: "Color \(String(describing: t.localizedName))"))
                                .accessibilityAddTraits(tint == t ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }

                    // Live preview tile, same rendering as the board
                    VStack(alignment: .leading, spacing: 10) {
                        sectionCaption(String(localized: "PREVIEW"))
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(tint == Phrase.TintKind.forest ? Color.white.opacity(0.18)
                                          : tint == Phrase.TintKind.plain ? Palette.forest.opacity(0.08)
                                          : Color.white.opacity(0.5))
                                    .frame(width: 56, height: 56)
                                PhraseGlyph(symbol: symbol, color: tint.foreground)
                            }
                            Text(label.isEmpty ? String(localized: "Label") : label)
                               .font(EchoFont.display(22, weight: .bold))
                                .foregroundStyle(tint.foreground)
                        }
                        .frame(maxWidth: .infinity, minHeight: 148)
                        .background(tint.background, in: .rect(cornerRadius: 28))
                        .overlay {
                            if tint == Phrase.TintKind.plain {
                                RoundedRectangle(cornerRadius: 28)
                                    .strokeBorder(Palette.forest.opacity(0.12), lineWidth: 3)
                            }
                        }
                    }
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "New Phrase"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add")) {
                        let saved = store.addPhrase(Phrase(
                            text: text.trimmingCharacters(in: .whitespaces),
                            label: label.trimmingCharacters(in: .whitespaces),
                            symbol: symbol,
                            tint: tint,
                            shortcut: shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        if saved {
                            dismiss()
                        } else {
                            showSaveError = true
                        }
                    }
                    .disabled(!canSave)
                    .fontWeight(.bold)
                }
            }
            .alert(String(localized: "Couldn't Add Phrase"), isPresented: $showSaveError) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(localized: "Your phrase wasn't saved. Please try again."))
            }
        }
    }

    private func sectionCaption(_ s: String) -> some View {
        Text(s)
            .font(EchoFont.body(13, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Palette.faint)
    }

    private func field(_ caption: String, prompt: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionCaption(caption)
            TextField(prompt, text: value)
                .font(EchoFont.body(17))
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Palette.surface, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2))
        }
    }
}
