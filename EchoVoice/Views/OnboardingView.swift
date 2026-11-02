import AVFoundation
import Speech
import SwiftUI

/// Mandatory First-Launch Interactive Onboarding & Permissions Wizard.
/// Ensures the user grants Camera, Microphone, and Personal Voice permissions,
/// selects their hands-free navigation preference (Head movement or Touch),
/// and tests dwell selection before accessing the app.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentStep: Int = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-EchoVoiceOnboardingStep"),
           arguments.indices.contains(flag + 1),
           let step = Int(arguments[flag + 1]), (0...4).contains(step) {
            return step
        }
        #endif
        return 0
    }()
    @State private var cameraPermissionGranted = false
    @State private var micPermissionGranted = false
    @State private var didRequestAllPermissions = false
    @State private var showGazeCalibration = false
    @State private var showPersonalInfo = false
    @State private var welcomeBreathing = false

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top Progress Bar
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Palette.controlAccent : Palette.controlAccent.opacity(0.20))
                        .frame(height: 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            ScrollView {
                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: personalInfoStep
                    case 2: trackingPermissionsStep
                    case 3: voicePermissionsStep
                    case 4: setupPreferencesStep
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            // A long step scrolls; its last lines fade out above the buttons
            // instead of being sliced off by them.
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                }
            }
            .scrollIndicatorsFlash(onAppear: true)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            // Bottom Navigation Buttons. Stacked at accessibility sizes, where a
            // 100-point Back button broke its own word in two.
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 16))) {
                if currentStep > 0 {
                    Button {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy) { currentStep -= 1 }
                    } label: {
                        Text(String(localized: "Back"))
                            .font(EchoFont.body(16, weight: .bold))
                            .foregroundStyle(Palette.controlAccent)
                            .lineLimit(1)
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 100, minHeight: 54)
                            .background(Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 16))
                    }
                }

                Button {
                    // Leaving Personal Info asks for every permission up front, one
                    // prompt after another, so nothing is left for later screens
                    // to discover. Each step's buttons still work as a retry.
                    if currentStep == 1 && !didRequestAllPermissions {
                        didRequestAllPermissions = true
                        Task { await requestAllPermissions() }
                    }
                    if currentStep < 4 {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy) { currentStep += 1 }
                    } else {
                        onComplete()
                    }
                } label: {
                    Text(currentStep == 4 ? String(localized: "Start Using EchoVoice") : String(localized: "Continue"))
                        .font(EchoFont.body(17, weight: .bold))
                        .foregroundStyle(Palette.onControlAccent)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Palette.controlAccent, in: .rect(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        // Without a cap the cards run the full 13" of an iPad, which leaves a
        // line of body text nearly a foot wide and unreadable. Under 620pt this
        // is inert, so iPhone is unaffected.
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .background(Palette.background)
        .onAppear {
            checkExistingPermissions()
        }
        .sheet(isPresented: $showPersonalInfo) {
            PersonalInfoEditorSheet()
        }
        .fullScreenCover(isPresented: $showGazeCalibration) {
            GazeCalibrationView()
        }
    }

    // MARK: Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Palette.orange.opacity(0.2))
                    .frame(width: 150, height: 150)
                    .scaleEffect(welcomeBreathing && !reduceMotion ? 1.08 : 1)
                BearMascotView(mood: .wave)
                    .frame(width: 190, height: 190)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    welcomeBreathing = true
                }
            }
            .onDisappear { welcomeBreathing = false }

            VStack(spacing: 8) {
                Text(String(localized: "Welcome to EchoVoice"))
                    .font(EchoFont.display(30, weight: .extraBold))
                    .foregroundStyle(Palette.controlAccent)
                    .multilineTextAlignment(.center)

                Text(String(localized: "Tap a phrase. Let EchoVoice speak for you."))
                    .font(EchoFont.body(15))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            VStack(alignment: .leading, spacing: 14) {
                featureBullet(icon: "speaker.wave.2.fill", title: String(localized: "Speak"), desc: String(localized: "Tap a phrase or type your own."))
                featureBullet(icon: "mic.fill", title: String(localized: "Use your voice"), desc: String(localized: "Record phrases you use often."))
                featureBullet(icon: "eye", title: String(localized: "Hands-free"), desc: String(localized: "Control it with small head movements."))
            }
            .padding(20)
            .background(Palette.surface, in: .rect(cornerRadius: 24))
            .shadow(color: Palette.forest.opacity(0.06), radius: 10, y: 4)
            .padding(.horizontal, 24)

            Text(String(localized: "EchoVoice is an AAC and personal voice-journal tool, not a medical device. It does not diagnose, screen, or monitor any condition."))
                .font(EchoFont.body(12))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    // MARK: Step 1: Personal Info

    /// Just the three details someone most needs to say fast. Everything else
    /// lives in Settings > Personal Info.
    private var personalInfoStep: some View {
        let profile = Bindable(store)
        return VStack(spacing: 14) {
            BearMascotView(mood: .listening)
                .frame(width: 90, height: 90)

            VStack(spacing: 6) {
                Text(String(localized: "About you"))
                    .font(EchoFont.display(26, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                Text(String(localized: "These become one-tap phrases. Skip any you like."))
                    .font(EchoFont.body(15))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 14) {
                onboardingField(String(localized: "Your name"), text: profile.profileName, prompt: String(localized: "Avery Johnson"))
                onboardingField(String(localized: "Emergency contact"), text: profile.profileEmergencyContact, prompt: String(localized: "Name and phone number"))
                onboardingField(String(localized: "Allergies"), text: profile.profileAllergies, prompt: String(localized: "Allergies or none"))
            }
            .padding(.horizontal, 24)

            Label(String(localized: "Saved only on this phone"), systemImage: "lock.fill")
                .font(EchoFont.body(13, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private func onboardingField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(EchoFont.body(16, weight: .bold))
                .foregroundStyle(Palette.ink)
            TextField(prompt, text: text)
                .font(EchoFont.body(17, weight: .medium))
                .padding(14)
                .background(Palette.surface, in: .rect(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2)
                }
        }
    }

    // MARK: Step 2: Head & Eye Tracking Permissions

    private var trackingPermissionsStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(String(localized: "How will you choose?"))
                    .font(EchoFont.display(24, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text(String(localized: "Pick one. You can change it later in Settings."))
                    .font(EchoFont.body(14))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Mode Selector Options
            VStack(alignment: .leading, spacing: 10) {
                ForEach(EyeGazeManager.TrackingMode.allCases) { mode in
                    modeOptionButton(mode: mode)
                }
            }
            .padding(12)
            .background(Palette.surface, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 24)

            if eyeGaze.trackingMode != .touch && eyeGaze.isEyeTrackingSupported() {
                // Camera Permission Button
                Button {
                    requestCameraPermission()
                } label: {
                    HStack {
                        Image(systemName: cameraPermissionGranted ? "checkmark.circle.fill" : "camera.fill")
                            .font(.system(size: 18))
                        Text(cameraPermissionGranted ? String(localized: "Camera Access Granted") : String(localized: "Allow Camera for Face Tracking"))
                            .font(EchoFont.body(15, weight: .bold))
                        Spacer()
                    }
                    .padding(14)
                    .background(cameraPermissionGranted ? Palette.lime : Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 18))
                    .foregroundStyle(cameraPermissionGranted ? Palette.forest : Palette.controlAccent)
                }
                .padding(.horizontal, 24)
            } else if !eyeGaze.isEyeTrackingSupported() {
                Label(String(localized: "Head control needs an iPhone or iPad with Face ID. On this device, use Touch."), systemImage: "info.circle.fill")
                    .font(EchoFont.body(13, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 24)
            }

            if eyeGaze.trackingMode != .touch {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "How it works"))
                        .font(EchoFont.body(16, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                    howItWorksLine("scope", String(localized: "Rest the cursor on a button until its ring fills."))
                    howItWorksLine("book.pages", String(localized: "Turn pages with the arrows, or close your eyes and hold."))
                    howItWorksLine("exclamationmark.triangle", String(localized: "For HELP: blink five times quickly, then close your eyes and hold."))
                }
                .padding(16)
                .background(Palette.lime.opacity(0.22), in: .rect(cornerRadius: 18))
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: Step 3: Voice & Mic Permissions

    private var voicePermissionsStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(String(localized: "Your voice"))
                    .font(EchoFont.display(24, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text(String(localized: "Make EchoVoice sound like you."))
                    .font(EchoFont.body(14))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 14) {
                PersonalVoiceSetupCard()

                // Mic Button
                Button {
                    requestMicPermission()
                } label: {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: micPermissionGranted ? "checkmark.circle.fill" : "mic.fill")
                            .font(.system(size: 22))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "Microphone"))
                                .font(EchoFont.body(16, weight: .bold))
                                .foregroundStyle(micPermissionGranted ? Palette.forest : Palette.controlAccent)
                                .multilineTextAlignment(.leading)
                            Text(String(localized: "For recording phrases."))
                                .font(EchoFont.body(12))
                                .foregroundStyle(micPermissionGranted ? Palette.forest.opacity(0.78) : Palette.secondaryText)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(micPermissionGranted ? Palette.lime : Palette.forest.opacity(0.1), in: .rect(cornerRadius: 18))
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: Step 4: Dwell & Text Size Preferences

    private var setupPreferencesStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(String(localized: "Customize Preferences"))
                    .font(EchoFont.display(24, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text(String(localized: "Make EchoVoice easy to see and use. You can change these later in Settings."))
                    .font(EchoFont.body(14))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 16) {
                if eyeGaze.trackingMode != .touch {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(localized: "Dwell time"))
                                .font(EchoFont.body(15, weight: .bold))
                            Spacer()
                            Text(String(format: "%.1fs", eyeGaze.dwellDuration))
                                .font(EchoFont.body(14))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Slider(value: Binding(
                            get: { eyeGaze.dwellDuration },
                            set: { eyeGaze.dwellDuration = $0 }
                        ), in: 0.8...3.0, step: 0.1)
                        .tint(Palette.forest)
                    }

                    Button {
                        showGazeCalibration = true
                    } label: {
                        Label(
                            eyeGaze.calibrationInUse == nil
                                ? String(localized: "Set up head control (1 minute)")
                                : String(localized: "Setup done — check or redo"),
                            systemImage: eyeGaze.calibrationInUse == nil ? "scope" : "checkmark.circle.fill"
                        )
                        .font(EchoFont.body(15, weight: .bold))
                        .foregroundStyle(eyeGaze.calibrationInUse == nil ? Palette.onControlAccent : Palette.controlAccent)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(eyeGaze.calibrationInUse == nil ? Palette.controlAccent : Palette.controlAccent.opacity(0.12),
                                    in: .rect(cornerRadius: 14))
                    }
                    .disabled(!cameraPermissionGranted)
                    .opacity(cameraPermissionGranted ? 1 : 0.45)

                    if !cameraPermissionGranted {
                        Text(String(localized: "Allow camera access on the previous step to set up hands-free control."))
                            .font(EchoFont.body(12))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                // Personal info: name, contacts, and medical details for Build > Personal.
                Button {
                    showPersonalInfo = true
                } label: {
                    Label(String(localized: "More personal info"), systemImage: "person.text.rectangle")
                        .font(EchoFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.controlAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                // Text Size Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Text Size"))
                        .font(EchoFont.body(15, weight: .bold))
                    if dynamicTypeSize.isAccessibilitySize {
                        textSizePicker.pickerStyle(.menu)
                    } else {
                        textSizePicker.pickerStyle(.segmented)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Board Density"))
                        .font(EchoFont.body(15, weight: .bold))
                    if dynamicTypeSize.isAccessibilitySize {
                        boardDensityPicker.pickerStyle(.menu)
                    } else {
                        boardDensityPicker.pickerStyle(.segmented)
                    }
                }

                Toggle(isOn: Binding(
                    get: { store.highContrastEnabled },
                    set: { store.highContrastEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "High Contrast"))
                            .font(EchoFont.body(15, weight: .bold))
                        Text(String(localized: "Dark green-black background with bright text and controls."))
                            .font(EchoFont.body(12))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .tint(Palette.controlAccent)

                Toggle(String(localized: "Show symbols on Quick phrases"), isOn: Binding(
                    get: { store.showSymbols },
                    set: { store.showSymbols = $0 }
                ))
                .font(EchoFont.body(15, weight: .bold))
                .tint(Palette.controlAccent)

                // Offered here because a caregiver setting up the phone is the
                // person who knows whether the board needs locking.
                Toggle(isOn: Binding(
                    get: { store.lockedToBoard },
                    set: { store.lockedToBoard = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Stay on Speak screen"))
                            .font(EchoFont.body(15, weight: .bold))
                        Text(String(localized: "Hides the other tabs so the board can't be left by accident. Hold the lock for 1.5 seconds to unlock."))
                            .font(EchoFont.body(12))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .tint(Palette.controlAccent)

                if eyeGaze.trackingMode != .touch {
                    Text(String(localized: "HELP always has a button at the bottom of the board. Under hands-free control it needs a longer look, so it isn't chosen by accident."))
                        .font(EchoFont.body(13, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .background(Palette.surface, in: .rect(cornerRadius: 24))
            .shadow(color: Palette.forest.opacity(0.06), radius: 10, y: 4)
            .padding(.horizontal, 24)
        }
    }

    // MARK: Helpers

    private var textSizePicker: some View {
        Picker(String(localized: "Text Size"), selection: Binding(
            get: { store.textSize },
            set: { store.textSize = $0 }
        )) {
            Text(String(localized: "Standard")).tag("standard")
            Text(String(localized: "Large")).tag("large")
            Text(String(localized: "Extra Large")).tag("xl")
        }
    }

    private var boardDensityPicker: some View {
        Picker(String(localized: "Board Density"), selection: Binding(
            get: { store.boardDensity },
            set: { store.boardDensity = $0 }
        )) {
            Text(String(localized: "Comfortable")).tag("comfortable")
            Text(String(localized: "Compact")).tag("compact")
        }
    }

    private func modeOptionButton(mode: EyeGazeManager.TrackingMode) -> some View {
        let isSelected = eyeGaze.trackingMode == mode
        // Head and eye control need a TrueDepth camera. Offering them on a
        // device without one leaves the person on a mode that cannot work.
        let isAvailable = mode == .touch || eyeGaze.isEyeTrackingSupported()
        return Button {
            eyeGaze.trackingMode = mode
            eyeGaze.isEnabled = mode != .touch && cameraPermissionGranted
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.controlAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(EchoFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                    Text(mode.description)
                        .font(EchoFont.body(12))
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Palette.forest.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isSelected ? Palette.forest : Palette.forest.opacity(0.1), lineWidth: isSelected ? 2 : 1))
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.45)
    }

    private func howItWorksLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.controlAccent)
                .frame(width: 20)
            Text(text)
                .font(EchoFont.body(14))
                .foregroundStyle(Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureBullet(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Palette.controlAccent)
                .frame(width: 38, height: 38)
                .background(Palette.controlAccent.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
                Text(desc)
                    .font(EchoFont.body(13))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private func checkExistingPermissions() {
        #if os(iOS)
        if !eyeGaze.isEyeTrackingSupported() {
            eyeGaze.trackingMode = .touch
            eyeGaze.isEnabled = false
        }
        cameraPermissionGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if #available(iOS 17.0, *) {
            micPermissionGranted = AVAudioApplication.shared.recordPermission == .granted
        } else {
            micPermissionGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        }
        #endif
    }

    /// Camera, microphone, speech recognition, then Personal Voice. Awaited in
    /// turn because iOS shows one system prompt at a time.
    private func requestAllPermissions() async {
        #if os(iOS)
        cameraPermissionGranted = await AVCaptureDevice.requestAccess(for: .video)
        if #available(iOS 17.0, *) {
            micPermissionGranted = await AVAudioApplication.requestRecordPermission()
        }
        _ = await withCheckedContinuation { (done: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
        speaker.requestPersonalVoice()
        #endif
    }

    private func requestCameraPermission() {
        #if os(iOS)
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.cameraPermissionGranted = granted
                if granted {
                    self.eyeGaze.isEnabled = true
                }
            }
        }
        #endif
    }

    private func requestMicPermission() {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    self.micPermissionGranted = granted
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    self.micPermissionGranted = granted
                }
            }
        }
        #endif
    }
}
