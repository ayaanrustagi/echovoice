import SwiftUI

/// Explains and surfaces Apple Personal Voice status. The app can't create a
/// Personal Voice for the user (that's a system flow in Settings), but it can
/// detect and use one — and clearly tell them how to set it up.
struct VoiceSetupView: View {
    @Environment(Speaker.self) private var speaker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BearMascotView(mood: .speaking)
                    .frame(width: 96, height: 96)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Text(String(localized: "Your Own Voice"))
                    .font(EchoFont.display(28, weight: .extraBold))
                    .foregroundStyle(Palette.forest)

                statusCard

                Text(String(localized: "How it works"))
                    .font(EchoFont.body(19, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(String(localized: "Apple Personal Voice lets you record your voice while you still can, and recreate it on-device. EchoVoice speaks your phrases in that voice — so it always sounds like you. Everything is generated on this device and never uploaded."))
                    .font(EchoFont.body(16))
                    .foregroundStyle(Palette.muted)

                Text(String(localized: "To create your Personal Voice, open Settings › Accessibility › Personal Voice. Then return here and allow EchoVoice to use it."))
                    .font(EchoFont.body(16))
                    .foregroundStyle(Palette.muted)

                Button {
                    speaker.requestPersonalVoice()
                } label: {
                    Text(String(localized: "Check for my Personal Voice"))
                        .font(EchoFont.display(18, weight: .bold))
                        .foregroundStyle(Palette.cream)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .background(Palette.forest, in: .rect(cornerRadius: 22))
                .shadow(color: Palette.forest.opacity(0.25), radius: 10, y: 5)
            }
            .padding(20)
            .readableContentWidth()
        }
        .background(Palette.cream)
    }

    private var statusCard: some View {
        let (text, glyph, color): (String, AnyView, Color) = {
            switch speaker.personalVoiceState {
            case .authorized where speaker.isUsingPersonalVoice:
                return (String(localized: "Personal Voice is active — phrases speak in your voice."),
                        AnyView(VectorIconShape(rawPath: EchoIcon.check()).stroke(Palette.forest, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))),
                        Palette.forest)
            case .authorized, .unavailable:
                return (String(localized: "No Personal Voice found yet. Create one in Settings to hear phrases in your voice."),
                        AnyView(Circle().stroke(Palette.orange, lineWidth: 3)), Palette.orange)
            case .notAuthorized:
                return (String(localized: "EchoVoice needs permission to use your Personal Voice."),
                        AnyView(Circle().stroke(Palette.orange, lineWidth: 3)), Palette.orange)
            }
        }()

        return HStack(spacing: 14) {
            glyph.frame(width: 28, height: 28).foregroundStyle(color)
            Text(text)
                .font(EchoFont.body(16, weight: .medium))
                .foregroundStyle(Palette.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}
