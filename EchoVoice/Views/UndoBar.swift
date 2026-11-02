import SwiftUI

/// Shown for `AppStore.undoWindow` after a phrase or recording is deleted.
/// The Undo target is large on purpose: the person most likely to need it is the
/// one whose hand slipped in the first place.
///
/// Fixed colors rather than palette tokens, so it reads the same in the light
/// look and in high contrast.
struct UndoBar: View {
    @Environment(AppStore.self) private var store

    private static let barColor = Color(red: 0.118, green: 0.302, blue: 0.169)   // #1E4D2B
    private static let buttonColor = Color(red: 0.659, green: 0.831, blue: 0.216) // #A8D437

    var body: some View {
        if let pending = store.pendingDelete {
            HStack(spacing: 12) {
                Text(pending.message)
                    .font(EchoFont.body(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Haptics.tap()
                    store.undoDelete()
                } label: {
                    Text(String(localized: "Undo"))
                        .font(EchoFont.body(17, weight: .bold))
                        .foregroundStyle(Self.barColor)
                        .frame(minWidth: 88, minHeight: 52)
                        .background(Self.buttonColor, in: .rect(cornerRadius: 16))
                }
                .accessibilityHint(String(localized: "Brings back what you just deleted"))
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .background(Self.barColor, in: .rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .readableContentWidth()
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(pending.id)
        }
    }
}
