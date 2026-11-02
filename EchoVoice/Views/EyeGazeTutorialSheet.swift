import SwiftUI

/// Interactive Eye Tracking & Dwell Selection Tutorial Sheet for AAC users and caregivers.
struct EyeGazeTutorialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(Speaker.self) private var speaker

    @State private var practiceComplete = false
    @State private var practiceProgress: Double = 0.0
    @State private var practiceTimer: Timer?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    tutorialStepCard(
                        number: "1",
                        title: String(localized: "Turn it on"),
                        description: String(localized: "In Settings, turn on Hands-free control and choose Head movement. Allow the camera when asked.")
                    )

                    tutorialStepCard(
                        number: "2",
                        title: String(localized: "Set it up"),
                        description: String(localized: "Tap Set up hands-free. Follow five dots, then EchoVoice checks that the cursor goes where you point.")
                    )

                    tutorialStepCard(
                        number: "3",
                        title: String(localized: "Choose a button"),
                        description: String(format: String(localized: "Rest the cursor on a button. A ring fills in %.1f seconds, then it is chosen. Look away before it fills to cancel."), eyeGaze.dwellDuration)
                    )

                    tutorialStepCard(
                        number: "4",
                        title: String(localized: "Turn the page"),
                        description: eyeGaze.blinkPageTurnEnabled
                            ? String(localized: "Use the arrow buttons, or close your eyes and hold for a second.")
                            : String(localized: "Use the arrow buttons at the bottom of the board.")
                    )

                    tutorialStepCard(
                        number: "?",
                        title: String(localized: "If pointing isn't reliable"),
                        description: String(localized: "Touch always works, and the HELP button is always on screen. For scanning instead of pointing, turn on iOS Switch Control (Settings › Accessibility › Switch Control): it steps through EchoVoice's buttons and selects with a switch, a tap anywhere, or a head turn.")
                    )

                    DisclosureGroup(String(localized: "Calling for HELP")) {
                        Text(String(localized: "Blink five times quickly, then close your eyes and hold for 2 seconds. Or rest on the red HELP button: it needs a longer look than other buttons, so it is not chosen by accident."))
                            .font(EchoFont.body(15))
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    .font(EchoFont.body(16, weight: .bold))
                    .tint(Palette.controlAccent)
                    .padding(16)
                    .background(Palette.surface, in: .rect(cornerRadius: 18))

                    // Step 4: Interactive Practice Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("5")
                                .font(EchoFont.display(18, weight: .bold))
                                .foregroundStyle(Palette.cream)
                                .frame(width: 32, height: 32)
                                .background(Palette.forest, in: .circle)
                            Text(String(localized: "Try it"))
                                .font(EchoFont.body(18, weight: .bold))
                                .foregroundStyle(Palette.primaryText)
                        }

                        Button {
                            triggerPracticeSuccess()
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(practiceComplete ? Palette.lime : Palette.orange.opacity(0.2))
                                        .frame(width: 60, height: 60)

                                    if practiceComplete {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 26, weight: .bold))
                                            .foregroundStyle(Palette.forest)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 24))
                                            .foregroundStyle(Palette.forest)
                                    }
                                }

                                Text(practiceComplete ? String(localized: "It worked") : (eyeGaze.isSelectionReady ? String(localized: "Rest the cursor here") : String(localized: "Tap here to practice")))
                                    .font(EchoFont.display(18, weight: .bold))
                                    .foregroundStyle(Palette.primaryText)

                                if practiceProgress > 0 && !practiceComplete {
                                    ProgressView(value: practiceProgress, total: 1.0)
                                        .tint(Palette.forest)
                                        .padding(.horizontal, 20)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 130)
                            .background(practiceComplete ? Palette.lime.opacity(0.25) : Palette.background, in: .rect(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.forest.opacity(0.15), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .gazeSelectable(id: "tutorial-practice", showsHighlight: true) { triggerPracticeSuccess() }
                    }
                    .padding(18)
                    .background(Palette.surface, in: .rect(cornerRadius: 24))
                    .shadow(color: Palette.forest.opacity(0.06), radius: 10, y: 4)

                    // Got It Button
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "Done"))
                            .font(EchoFont.body(17, weight: .bold))
                            .foregroundStyle(Palette.cream)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Palette.forest, in: .rect(cornerRadius: 18))
                    }
                    .padding(.top, 10)
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Palette.background)
            .navigationTitle(String(localized: "Hands-free guide"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func tutorialStepCard(number: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(EchoFont.display(18, weight: .bold))
                .foregroundStyle(Palette.cream)
                .frame(width: 32, height: 32)
                .background(Palette.forest, in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
                Text(description)
                    .font(EchoFont.body(15))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .shadow(color: Palette.forest.opacity(0.06), radius: 8, y: 4)
    }

    private func triggerPracticeSuccess() {
        withAnimation(.snappy) {
            practiceComplete = true
            practiceProgress = 1.0
        }
        let phrase = Phrase(text: String(localized: "Eye tracking tutorial complete!"), label: String(localized: "Tutorial"), symbol: .love, tint: .forest)
        speaker.speak(phrase)
    }
}
