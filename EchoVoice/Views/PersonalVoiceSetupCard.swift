import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Walks someone through making an Apple Personal Voice without leaving them
/// to find it on their own. iOS only lets a Personal Voice be recorded inside
/// Settings, so this opens that page, then checks again automatically the
/// moment they come back to EchoVoice.
struct PersonalVoiceSetupCard: View {
    @Environment(Speaker.self) private var speaker
    @Environment(\.scenePhase) private var scenePhase
    @State private var sentToSettings = false

    var body: some View {
        Group {
            if speaker.isUsingPersonalVoice {
                readyCard
            } else {
                setupCard
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings: pick up the voice they just made.
            if phase == .active && sentToSettings && !speaker.isUsingPersonalVoice {
                speaker.requestPersonalVoice()
            }
        }
    }

    private var readyCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Your Personal Voice is ready"))
                    .font(EchoFont.body(16, weight: .bold))
                Text(String(localized: "EchoVoice will speak in your own voice."))
                    .font(EchoFont.body(13))
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.forest)
        .padding(16)
        .background(Palette.lime, in: .rect(cornerRadius: 18))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 22))
                Text(String(localized: "Your own voice"))
                    .font(EchoFont.body(17, weight: .bold))
            }
            .foregroundStyle(Palette.controlAccent)

            step(1, String(localized: "Open Settings"))
            step(2, String(localized: "Create a Personal Voice"))
            step(3, String(localized: "Come back. Done."))

            Button {
                openPersonalVoiceSettings()
            } label: {
                Text(String(localized: "Open Personal Voice"))
                    .font(EchoFont.body(16, weight: .bold))
                    .foregroundStyle(Palette.onControlAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Palette.controlAccent, in: .rect(cornerRadius: 14))
            }

            Button {
                speaker.requestPersonalVoice()
            } label: {
                Text(speaker.isChecking ? String(localized: "Checking\u{2026}") : String(localized: "I already made one"))
                    .font(EchoFont.body(14, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }

            if sentToSettings, !speaker.isChecking, let status = speaker.statusExplanation {
                Text(status)
                    .font(EchoFont.body(12))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(16)
        .background(Palette.forest.opacity(0.08), in: .rect(cornerRadius: 18))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.onControlAccent)
                .frame(width: 22, height: 22)
                .background(Palette.controlAccent, in: .circle)
            Text(text)
                .font(EchoFont.body(14))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Apple publishes no link to the Personal Voice page. These Settings
    /// paths are undocumented (fine for a personal build, a risk in App Store
    /// review), so each one falls back to the next, ending on EchoVoice's own
    /// page in Settings, which always opens.
    private func openPersonalVoiceSettings() {
        #if os(iOS)
        sentToSettings = true
        var candidates = ["App-prefs:ACCESSIBILITY&path=PERSONAL_VOICE", "App-prefs:ACCESSIBILITY"]
            .compactMap(URL.init(string:))
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            candidates.append(appSettings)
        }
        open(candidates)
        #endif
    }

    #if os(iOS)
    private func open(_ urls: [URL]) {
        guard let first = urls.first else { return }
        UIApplication.shared.open(first) { opened in
            if !opened { open(Array(urls.dropFirst())) }
        }
    }
    #endif
}
