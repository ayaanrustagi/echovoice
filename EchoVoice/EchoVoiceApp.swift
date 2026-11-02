import SwiftData
import SwiftUI

@main
struct EchoVoiceApp: App {
    @State private var store = AppStore()
    @State private var speaker = Speaker()
    @State private var eyeGaze = EyeGazeManager()

    init() {
        EchoFont.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(speaker)
                .environment(eyeGaze)
                .tint(Palette.controlAccent)
                .preferredColorScheme(store.highContrastEnabled ? .dark : .light)
        }
        .modelContainer(for: [Phrase.self, CheckIn.self, Recording.self, StatusEvent.self])
    }
}
