import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @AppStorage("echovoice.didOnboardV2") private var didOnboard = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if didOnboard || ProcessInfo.processInfo.arguments.contains("-EchoVoiceSkipOnboarding") {
                MainTabs()
            } else {
                OnboardingView(onComplete: { didOnboard = true })
            }
        }
        // Drives every EchoFont size, since they're declared relative to a text
        // style. One environment value, so the whole UI resizes together.
        .dynamicTypeSize(store.dynamicTypeRange)
        .environment(\.colorScheme, store.highContrastEnabled ? .dark : .light)
        // Unlike an environment override alone, this also updates UIKit-owned
        // chrome such as the status-bar clock, Wi-Fi, and battery glyphs.
        .preferredColorScheme(store.highContrastEnabled ? .dark : .light)
        .safeAreaInset(edge: .top) {
            if let error = store.persistenceError {
                Text(error).font(EchoFont.body(14)).padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Palette.orange)
            }
        }
        .onChange(of: store.boardLanguage, initial: true) { _, language in
            speaker.boardLanguage = language
        }
        .onAppear {
            store.attachModelContext(modelContext)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-EchoVoiceVerifyResources") {
                print("ECHOVOICE_VERIFY phrases=\(store.phrases.count) persistence_error=\(store.persistenceError != nil) reduce_motion=\(reduceMotion)")
            }
            #endif
        }
    }
}

private struct MainTabs: View {
    @Environment(AppStore.self) private var store
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: Int = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-EchoVoiceUITab"),
           arguments.indices.contains(flag + 1),
           let tab = Int(arguments[flag + 1]), (0...4).contains(tab) {
            return tab
        }
        #endif
        return 0
    }()

    /// Tab tags in tab-bar order; Tags only where NFC works.
    private var visibleTabs: [Int] {
        NFCTagManager.isSupported ? [0, 1, 2, 3, 4] : [0, 1, 2, 4]
    }

    var body: some View {
        Group {
            if store.lockedToBoard {
                SpeakBoardView()
            } else {
                TabView(selection: $selectedTab) {
                    SpeakBoardView()
                        .environment(\.horizontalSizeClass, horizontalSizeClass)
                        .tabItem { Label(String(localized: "Speak"), systemImage: "speaker.wave.2.fill") }
                        .tag(0)

                    VoiceBankView()
                        .environment(\.horizontalSizeClass, horizontalSizeClass)
                        .tabItem { Label(String(localized: "Voice"), systemImage: "mic.fill") }
                        .tag(1)

                    SpeechJournalView()
                        .environment(\.horizontalSizeClass, horizontalSizeClass)
                        .tabItem { Label(String(localized: "Journal"), systemImage: "waveform") }
                        .tag(2)

                    if NFCTagManager.isSupported {
                        TagsView()
                            .environment(\.horizontalSizeClass, horizontalSizeClass)
                            .tabItem { Label(String(localized: "Tags"), systemImage: "wave.3.right") }
                            .tag(3)
                    }

                    SettingsView()
                        .environment(\.horizontalSizeClass, horizontalSizeClass)
                        .tabItem { Label(String(localized: "Settings"), systemImage: "gearshape.fill") }
                        .tag(4)
                }
                // The bottom tab bar on iPad too. iPadOS's floating top bar
                // fitted only four of these five on an iPad mini, hiding
                // Settings behind an arrow even while Settings was open. Each
                // tab gets the real size class back, so its layout stays iPad.
                .environment(\.horizontalSizeClass, .compact)
            }
        }
        .tint(Palette.controlAccent)
        // At the top, on every tab, so a delete can be undone wherever it happened.
        // Not the bottom: on the Speak board that is where HELP lives, and nothing
        // may cover HELP, even for ten seconds.
        .overlay(alignment: .top) {
            UndoBar()
                .padding(.top, 52)
                .animation(.snappy, value: store.pendingDelete?.id)
        }
        // The system tab bar can't carry dwell targets, so matching invisible
        // targets sit on top of it. Without them, hands-free use could never
        // leave the board, or get back to it from another tab.
        .overlay(alignment: .bottom) {
            if eyeGaze.isHandsFreeActive && !store.lockedToBoard {
                TabBarGazeTargets(tabs: visibleTabs, selection: $selectedTab)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
        // Drawn over the tab bar too, so the cursor never vanishes beneath it.
        // Shown on every tab, since the tab bar above is reachable from all of
        // them. Sheets and covers present above this, and draw their own.
        .overlay {
            if eyeGaze.isHandsFreeActive {
                GazeCursorOverlay().ignoresSafeArea()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != 0 { eyeGaze.resetDwell() }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-EchoVoiceLogGaze") { print("ECHOVOICE_GAZE event=tab tab=\(newTab)") }
            #endif
        }
        // A blink-HELP from another tab brings the board forward; the board
        // raises the alert once it is on screen.
        .onChange(of: eyeGaze.hasPendingHelpRequest) { _, pending in
            if pending { selectedTab = 0 }
        }
    }
}
