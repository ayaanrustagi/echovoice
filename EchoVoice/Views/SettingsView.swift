import AVFoundation
import SwiftUI

struct SettingsView: View {
    /// Words, not AVSpeech's raw rate: "0.5x" read as half speed when it is
    /// the voice's normal pace.
    static func speechSpeedLabel(_ rate: Float) -> String {
        switch rate {
        case ..<0.42: return String(localized: "Slow")
        case ..<0.475: return String(localized: "A little slow")
        case ...0.525: return String(localized: "Normal")
        case ...0.58: return String(localized: "A little fast")
        default: return String(localized: "Fast")
        }
    }

    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reflects the app's own text-size override applied at the root, so the
    /// controls can re-flow at the size the user actually picked.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var previewUtterance: String = String(localized: "Hello! This is a preview of your speaking voice in EchoVoice.")
    @State private var showAddPhraseSheet = false
    @State private var roomCheck = RoomCheck()
    @State private var showGazeTutorial = false
    @State private var showGazeCalibration = false
    @State private var showOnboardingSheet = false
    @State private var showPersonalInfoSheet = false
    @State private var shortcutPhrase: Phrase?
    @State private var accessProfileName = ""
    @State private var showMoreSettings = false
    @State private var showTrackingOptions = false
    @State private var showSignalCheck = false

    /// Scroll anchor for the text-size card, so changing size can keep it in view.
    private static let textSizeAnchor = "echovoice.settings.textSize"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        boardLockCard
                        eyeGazeCard
                        speechControlsCard
                        appearanceCard
                        comfortCard
                        languageCard
                        textSizeCard.id(Self.textSizeAnchor)
                        DisclosureGroup(isExpanded: $showMoreSettings) {
                            VStack(spacing: 18) {
                                boardLayoutCard
                                personalInfoCard
                                personalVoiceCard
                                phraseManagerCard
                                onboardingWizardCard
                                disclaimerBanner
                            }
                            .padding(.top, 14)
                        } label: {
                            Text(String(localized: "More settings"))
                                .font(EchoFont.body(17, weight: .bold))
                                .foregroundStyle(Palette.primaryText)
                        }
                        .tint(Palette.controlAccent)
                        .padding(18)
                        .background(Palette.surface, in: .rect(cornerRadius: 22))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .readableContentWidth()
                }
                // Resizing every label changes the scroll content height, which
                // would otherwise fling the user to an unrelated part of the page —
                // often leaving the size buttons off-screen right after they tapped
                // them. Re-anchor so the control stays under their finger and they
                // can see the result and adjust again.
                .onChange(of: store.textSize) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.textSizeAnchor, anchor: .center)
                    }
                }
            }
            .background(Palette.background)
            .navigationTitle(String(localized: "Settings"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showAddPhraseSheet) {
                AddPhraseSheet()
            }
            .sheet(isPresented: $showGazeTutorial) {
                EyeGazeTutorialSheet()
            }
            .fullScreenCover(isPresented: $showGazeCalibration) {
                GazeCalibrationView()
            }
            .fullScreenCover(isPresented: $showSignalCheck) {
                GazeSignalCheckView()
            }
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-EchoVoiceOpenSignalCheck") { showSignalCheck = true }
            }
            #endif
            .sheet(isPresented: $showOnboardingSheet) {
                OnboardingView(onComplete: { showOnboardingSheet = false })
            }
            .sheet(isPresented: $showPersonalInfoSheet) {
                PersonalInfoEditorSheet()
            }
            .sheet(item: $shortcutPhrase) { phrase in
                ShortcutEditorSheet(phrase: phrase)
            }
        }
    }

    private var disclaimerBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Palette.forest)
            Text(String(localized: "Not a medical device. It does not diagnose or monitor any condition."))
                .font(EchoFont.body(13))
                .foregroundStyle(Palette.forest)
        }
        .padding(14)
        .background(Palette.lime.opacity(0.3), in: .rect(cornerRadius: 16))
    }

    // MARK: Board Lock

    private var boardLockCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Stay on Speak screen"))
                        .font(EchoFont.body(17, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                }
                Spacer()
                Toggle(String(localized: "Stay on Speak screen"), isOn: Binding(
                    get: { store.lockedToBoard },
                    set: { store.lockedToBoard = $0 }
                ))
                .labelsHidden()
                .tint(Palette.controlAccent)
            }
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    // MARK: Eye Tracking & Dwell Selection

    private var eyeGazeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "face.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.controlAccent)
                Text(String(localized: "Hands-free control"))
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
                Spacer()
                // On means head control is actually running. With Touch
                // chosen, or on a device without face tracking, it reads off:
                // it showed on (and dimmed) there, which looked stuck.
                Toggle(String(localized: "Hands-free control"), isOn: Binding(
                    get: { eyeGaze.isEnabled && eyeGaze.trackingMode != .touch && eyeGaze.isEyeTrackingSupported() },
                    set: { on in
                        if on && eyeGaze.trackingMode == .touch { eyeGaze.trackingMode = .headMotion }
                        eyeGaze.isEnabled = on
                    }
                ))
                .labelsHidden()
                .tint(Palette.controlAccent)
                .disabled(!eyeGaze.isEyeTrackingSupported())
            }

            if !eyeGaze.isEyeTrackingSupported() {
                Label(String(localized: "Needs a Face ID camera. Touch still works."), systemImage: "info.circle.fill")
                    .font(EchoFont.body(13, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
            }

            if eyeGaze.isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Point with"))
                            .font(EchoFont.body(14, weight: .bold))
                            .foregroundStyle(Palette.primaryText)
                        VStack(spacing: 8) {
                            ForEach(EyeGazeManager.TrackingMode.allCases) { mode in
                                modeRow(mode)
                            }
                        }
                    }

                    if eyeGaze.trackingMode != .touch {
                        setupStatusRow

                        Button {
                            showGazeCalibration = true
                        } label: {
                            Label(eyeGaze.calibrationInUse == nil ? String(localized: "Set up hands-free") : String(localized: "Setup and checks"), systemImage: "scope")
                                .font(EchoFont.body(15, weight: .bold))
                                .foregroundStyle(eyeGaze.calibrationInUse == nil ? Palette.onControlAccent : Palette.controlAccent)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(eyeGaze.calibrationInUse == nil ? Palette.controlAccent : Palette.controlAccent.opacity(0.12),
                                            in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showGazeTutorial = true
                    } label: {
                        Label(String(localized: "How hands-free works"), systemImage: "questionmark.circle")
                            .font(EchoFont.body(14, weight: .bold))
                            .foregroundStyle(Palette.controlAccent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    DisclosureGroup(isExpanded: $showTrackingOptions) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(String(localized: "Dwell time"))
                                    .font(EchoFont.body(14, weight: .bold))
                                Spacer()
                                Text(String(format: String(localized: "%.1f seconds"), eyeGaze.dwellDuration))
                                    .font(EchoFont.body(13))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            Slider(value: Binding(
                                get: { eyeGaze.dwellDuration },
                                set: { eyeGaze.dwellDuration = $0 }
                            ), in: 0.8...3.0, step: 0.1)
                            .tint(Palette.controlAccent)
                            .accessibilityLabel(String(localized: "Dwell time"))
                            .accessibilityValue(String(format: String(localized: "%.1f seconds"), eyeGaze.dwellDuration))

                            Toggle(isOn: Binding(
                                get: { eyeGaze.blinkPageTurnEnabled },
                                set: { eyeGaze.blinkPageTurnEnabled = $0 }
                            )) {
                                Text(String(localized: "Close eyes to turn the page"))
                                    .font(EchoFont.body(15, weight: .bold))
                            }
                            .tint(Palette.controlAccent)

                            accessProfilesSection

                            Toggle(isOn: Binding(
                                get: { eyeGaze.showsTrackingDiagnostics },
                                set: { eyeGaze.showsTrackingDiagnostics = $0 }
                            )) {
                                Text(String(localized: "Show tracking readout on the board"))
                                    .font(EchoFont.body(15, weight: .bold))
                            }
                            .tint(Palette.controlAccent)

                            Button {
                                showSignalCheck = true
                            } label: {
                                Label(String(localized: "Signal check"), systemImage: "waveform.path.ecg")
                                    .font(EchoFont.body(14, weight: .bold))
                                    .foregroundStyle(Palette.controlAccent)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .disabled(eyeGaze.trackingMode == .touch)
                        }
                        .padding(.top, 12)
                    } label: {
                        Text(String(localized: "More hands-free options"))
                            .font(EchoFont.body(15, weight: .bold))
                    }
                    .tint(Palette.controlAccent)
                }
            }
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    private func modeRow(_ mode: EyeGazeManager.TrackingMode) -> some View {
        let selected = eyeGaze.trackingMode == mode
        return Button {
            eyeGaze.trackingMode = mode
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(mode.label)
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.controlAccent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Palette.controlAccent.opacity(0.14) : Palette.background,
                        in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Whether setup is done and has been shown to work, in words.
    private var setupStatusRow: some View {
        let (icon, color, text): (String, Color, String) = {
            if eyeGaze.calibrationOrientationMismatch {
                return ("rotate.right", Palette.orange, String(localized: "Set up again for this position."))
            }
            guard eyeGaze.calibrationInUse != nil else {
                return ("info.circle.fill", Palette.orange, String(localized: "Works now. Setup makes it more accurate."))
            }
            if let check = eyeGaze.directionalCheck {
                return check.allPassed
                    ? ("checkmark.circle.fill", Palette.controlAccent, String(localized: "Set up and checked."))
                    : ("xmark.octagon.fill", Palette.red, String(localized: "Some directions failed. Set up again."))
            }
            return ("checkmark.circle", Palette.controlAccent, String(localized: "Set up."))
        }()
        return Label {
            Text(text)
                .font(EchoFont.body(14, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
    }

    private var accessProfilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Phone positions"))
                .font(EchoFont.body(14, weight: .bold))
                .foregroundStyle(Palette.primaryText)
            VStack(spacing: 8) {
                TextField(String(localized: "Position name"), text: $accessProfileName)
                    .textInputAutocapitalization(.words)
                    .font(EchoFont.body(15))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Palette.background, in: .rect(cornerRadius: 12))
                Button(String(localized: "Save this position")) {
                    eyeGaze.saveAccessProfile(name: accessProfileName)
                    accessProfileName = ""
                }
                .font(EchoFont.body(13, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(accessProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(eyeGaze.accessProfiles) { profile in
                HStack(spacing: 10) {
                    Button {
                        eyeGaze.applyAccessProfile(profile)
                    } label: {
                        HStack {
                            Image(systemName: profile.mode == .touch ? "hand.tap.fill" : "face.dashed")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(EchoFont.body(14, weight: .bold))
                                Text(String(localized: "%@ · %@s dwell%@", defaultValue: "\(String(describing: profile.mode.label)) · \(String(format: "%.1f", profile.dwellDuration))s dwell\(String(describing: profile.calibration == nil ? "" : String(localized: " · calibrated")))"))
                                    .font(EchoFont.body(12))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                        }
                        .foregroundStyle(Palette.controlAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) { eyeGaze.deleteAccessProfile(profile) } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(String(localized: "Delete %@ profile", defaultValue: "Delete \(String(describing: profile.name)) profile"))
                }
                .padding(10)
                .background(Palette.background.opacity(0.55), in: .rect(cornerRadius: 12))
            }
        }
        .padding(.top, 4)
    }

    // MARK: Text Size Selector

    // MARK: Language

    private var languageCard: some View {
        let missing = store.missingStarters(for: store.boardLanguage)
        return VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Board Language"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.primaryText)

            Picker(String(localized: "Board language"), selection: Binding(get: { store.boardLanguage }, set: { store.boardLanguage = $0 })) {
                Text(String(localized: "English")).tag("en")
                Text(String(localized: "Español")).tag("es")
            }
            .pickerStyle(.segmented)

            if missing > 0 {
                Button {
                    Haptics.tap()
                    store.addStarters(for: store.boardLanguage)
                } label: {
                    Label(
                        store.boardLanguage == "es"
                            ? String(localized: "Añadir %@ frases en español", defaultValue: "Añadir \(String(missing)) frases en español")
                            : String(localized: "Add %@ English starter phrases", defaultValue: "Add \(String(describing: missing)) English starter phrases"),
                        systemImage: "plus.circle.fill"
                    )
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Palette.controlAccent.opacity(0.1), in: .rect(cornerRadius: 14))
                }
                .accessibilityHint(String(localized: "Adds them to the end of the board. Your own phrases are not changed."))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.controlAccent.opacity(0.12), lineWidth: 2))
    }

    // MARK: Comfort

    private var comfortCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Comfort"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.primaryText)

            comfortToggle(
                String(localized: "Keep screen awake"),
                isOn: Binding(get: { store.keepScreenAwake }, set: { store.keepScreenAwake = $0 })
            )
            Divider()
            comfortToggle(
                String(localized: "Ignore quick repeat taps"),
                isOn: Binding(get: { store.ignoreRepeatTaps }, set: { store.ignoreRepeatTaps = $0 })
            )
            Divider()
            comfortToggle(
                String(localized: "Hold to speak"),
                isOn: Binding(get: { store.holdToSpeak }, set: { store.holdToSpeak = $0 })
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.controlAccent.opacity(0.12), lineWidth: 2))
    }

    private func comfortToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(EchoFont.body(15, weight: .bold))
        }
        .tint(Palette.controlAccent)
    }

    private var appearanceCard: some View {
        Toggle(isOn: Binding(
            get: { store.highContrastEnabled },
            set: { store.highContrastEnabled = $0 }
        )) {
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Palette.controlAccent)
                    .frame(width: 38, height: 38)
                    .background(Palette.controlAccent.opacity(0.12), in: .circle)

                Text(String(localized: "High Contrast"))
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
            }
        }
        .tint(Palette.controlAccent)
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.controlAccent.opacity(0.12), lineWidth: 2))
    }

    // MARK: Text Size Selector

    private var textSizeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Text Size"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.primaryText)

            // Three side-by-side pills leave too little width for "Extra Large"
            // at accessibility sizes, where it wraps mid-word. Stack them instead
            // so every option keeps one full line — and so the tap targets grow
            // rather than shrink exactly when someone needs them largest.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))

            layout {
                sizeOptionBtn(String(localized: "Standard"), key: "standard")
                sizeOptionBtn(String(localized: "Large"), key: "large")
                sizeOptionBtn(String(localized: "Extra Large"), key: "xl")
            }
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    private func sizeOptionBtn(_ label: String, key: String) -> some View {
        let isSelected = store.textSize == key
        return Button {
            store.textSize = key
        } label: {
            Text(label)
                .font(EchoFont.body(14, weight: .bold))
                .foregroundStyle(isSelected ? Palette.onControlAccent : Palette.controlAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(isSelected ? Palette.controlAccent : Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Board layout

    private var boardLayoutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Communication Board"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.primaryText)

            Picker(String(localized: "Board density"), selection: Binding(
                get: { store.boardDensity },
                set: { store.boardDensity = $0 }
            )) {
                Text(String(localized: "Comfortable")).tag("comfortable")
                Text(String(localized: "Compact")).tag("compact")
            }
            .pickerStyle(.segmented)

            Toggle(isOn: Binding(
                get: { store.showSymbols },
                set: { store.showSymbols = $0 }
            )) {
                Text(String(localized: "Show symbols"))
                    .font(EchoFont.body(15, weight: .bold))
            }
            .tint(Palette.controlAccent)

            Divider()

            Toggle(isOn: Binding(
                get: { store.smartSuggestionsEnabled },
                set: { store.smartSuggestionsEnabled = $0 }
            )) {
                Text(String(localized: "Smart Suggestions"))
                    .font(EchoFont.body(15, weight: .bold))
            }
            .tint(Palette.controlAccent)

            if store.hasLearnedSuggestions {
                Button(String(localized: "Reset learned suggestions"), role: .destructive) {
                    store.resetSmartSuggestions()
                }
                .font(EchoFont.body(15, weight: .bold))
                .frame(minHeight: 44)
            }

            Divider()

            sampleHistoryControls
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    /// The Voice Journal needs several weeks of readings before its chart,
    /// baseline, or trend logic show anything. That makes the most substantial
    /// screen in the app the one a new person is guaranteed to see empty, and it
    /// makes the journal impossible to explain to a family deciding whether to
    /// use it.
    ///
    /// Sample readings fill that gap. They are labelled wherever they appear,
    /// excluded from clinician exports, and removable in one action — so they
    /// demonstrate the journal without ever being mistaken for someone's own
    /// voice history.
    private var sampleHistoryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Voice Journal sample data"))
                .font(EchoFont.body(15, weight: .bold))
                .foregroundStyle(Palette.primaryText)
            if store.hasSampleHistory {
                Text(String(localized: "Labelled, and left out of exports."))
                    .font(EchoFont.body(13))
                    .foregroundStyle(Palette.secondaryText)
            }

            if store.hasSampleHistory {
                Button(String(localized: "Remove sample readings"), role: .destructive) {
                    store.removeSampleHistory()
                }
                .font(EchoFont.body(15, weight: .bold))
                .frame(minHeight: 44)
            } else {
                Button(String(localized: "Add sample readings")) {
                    store.loadSampleHistory()
                }
                .font(EchoFont.body(15, weight: .bold))
                .frame(minHeight: 44)
                .foregroundStyle(Palette.controlAccent)
            }
        }
    }

    private var personalInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Personal Information Phrases"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.primaryText)

            Button {
                showPersonalInfoSheet = true
            } label: {
                Label(String(localized: "Edit Personal Info"), systemImage: "person.text.rectangle")
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.onControlAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.controlAccent, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    // MARK: Speech Controls

    private var speechControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Speech Rate & Volume"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Speech Speed"))
                        .font(EchoFont.body(15, weight: .bold))
                    Spacer()
                    Text(Self.speechSpeedLabel(store.speechRate))
                        .font(EchoFont.body(14))
                        .foregroundStyle(Palette.secondaryText)
                }
                Slider(value: Binding(
                    get: { Double(store.speechRate) },
                    set: { store.speechRate = Float($0) }
                ), in: Double(AppStore.speechRateRange.lowerBound)...Double(AppStore.speechRateRange.upperBound), step: 0.05)
                .tint(Palette.controlAccent)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Volume"))
                        .font(EchoFont.body(15, weight: .bold))
                    Spacer()
                    Text("\(Int(store.speechVolume * 100))%")
                        .font(EchoFont.body(14))
                        .foregroundStyle(Palette.secondaryText)
                }
                Slider(value: Binding(
                    get: { Double(store.speechVolume) },
                    set: { store.speechVolume = Float($0) }
                ), in: 0.1...1.0, step: 0.05)
                .tint(Palette.controlAccent)
            }

            adaptiveVolumeControls

            Button {
                let tempPhrase = Phrase(label: String(localized: "Preview"), text: previewUtterance)
                speaker.speak(tempPhrase, rate: store.speechRate, volume: store.speechVolume)
            } label: {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                    Text(String(localized: "Preview Voice"))
                }
                .font(EchoFont.body(15, weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 14))
            }
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    /// Louder in a noisy room, never quieter than the slider. See `AdaptiveVolume`.
    private var adaptiveVolumeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { speaker.adaptsToRoom }, set: { speaker.adaptsToRoom = $0 })) {
                Text(String(localized: "Louder in noisy rooms"))
                    .font(EchoFont.body(15, weight: .bold))
            }
            .tint(Palette.controlAccent)

            if speaker.adaptsToRoom {
                if store.speechVolume >= 1 {
                    Text(String(localized: "Volume is at 100%, so it can't go louder."))
                        .font(EchoFont.body(13, weight: .semibold))
                        .foregroundStyle(Palette.orange)
                }
                HStack(spacing: 10) {
                    Text(roomReadingText)
                        .font(EchoFont.body(13, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                    Spacer()
                    Button {
                        Task {
                            if let reading = await roomCheck.measure() { speaker.roomReading = reading }
                        }
                    } label: {
                        Text(roomCheck.isMeasuring ? String(localized: "Listening…") : String(localized: "Check room"))
                            .font(EchoFont.body(14, weight: .bold))
                            .foregroundStyle(Palette.controlAccent)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .background(Palette.controlAccent.opacity(0.12), in: .rect(cornerRadius: 12))
                    }
                    .disabled(roomCheck.isMeasuring)
                }
                if let error = roomCheck.errorMessage {
                    Text(error)
                        .font(EchoFont.body(13, weight: .semibold))
                        .foregroundStyle(Palette.red)
                }
            }
        }
    }

    private var roomReadingText: String {
        let fresh = speaker.roomReading.flatMap { reading in
            Date.now.timeIntervalSince(reading.takenAt) <= AdaptiveVolume.maxReadingAge ? reading : nil
        }
        guard let reading = fresh else {
            return String(localized: "No room reading yet.")
        }
        let volume = speaker.effectiveVolume(store.speechVolume)
        return String(format: String(localized: "%@ room (%.0f dBFS) · speaking at %d%%"),
                      AdaptiveVolume.describe(reading.noiseDB), reading.noiseDB, Int((volume * 100).rounded()))
    }

    // MARK: Personal Voice Status

    private var personalVoiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Apple Personal Voice"))
                        .font(EchoFont.body(17, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                    Text(speaker.isUsingPersonalVoice ? String(localized: "Connected") : String(localized: "Not connected"))
                        .font(EchoFont.body(14))
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                Button {
                    speaker.requestPersonalVoice()
                } label: {
                    Text(speaker.isUsingPersonalVoice ? String(localized: "Active") : String(localized: "Check"))
                        .font(EchoFont.body(13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(speaker.isUsingPersonalVoice ? Palette.lime : Palette.forest.opacity(0.1), in: .rect(cornerRadius: 12))
                        .foregroundStyle(speaker.isUsingPersonalVoice ? Palette.forest : Palette.controlAccent)
                }
            }
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    // MARK: Phrase Manager

    private func reorderMenu(for phrase: Phrase) -> some View {
        let index = store.phrases.firstIndex(where: { $0.id == phrase.id }) ?? 0
        let last = store.phrases.count - 1
        return Menu {
            Button(String(localized: "Move to Top"), systemImage: "arrow.up.to.line") { store.movePhrase(phrase, to: 0) }
                .disabled(index == 0)
            Button(String(localized: "Move Up"), systemImage: "arrow.up") { store.movePhrase(phrase, to: index - 1) }
                .disabled(index == 0)
            Button(String(localized: "Move Down"), systemImage: "arrow.down") { store.movePhrase(phrase, to: index + 1) }
                .disabled(index == last)
            Button(String(localized: "Move to Bottom"), systemImage: "arrow.down.to.line") { store.movePhrase(phrase, to: last) }
                .disabled(index == last)
        } label: {
            Label(String(localized: "Move"), systemImage: "arrow.up.arrow.down")
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .accessibilityLabel(String(localized: "Move %@", defaultValue: "Move \(String(describing: phrase.label))"))
    }

    private var phraseManagerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "Manage Phrase Cards (%@)", defaultValue: "Manage Phrase Cards (\(String(describing: store.phrases.count)))"))
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
                Spacer()
                Button {
                    showAddPhraseSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(String(localized: "Add"))
                    }
                    .font(EchoFont.body(14, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                }
            }

            ForEach(store.phrases) { phrase in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(phrase.tint == Phrase.TintKind.forest ? Palette.forest : Palette.lime.opacity(0.3))
                                .frame(width: 36, height: 36)
                            PhraseGlyph(symbol: phrase.symbol, color: phrase.tint == Phrase.TintKind.forest ? Palette.cream : Palette.forest)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(phrase.label)
                                .font(EchoFont.body(15, weight: .bold))
                                .foregroundStyle(Palette.primaryText)
                            Text(phrase.text)
                                .font(EchoFont.body(13))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        reorderMenu(for: phrase)
                        Spacer(minLength: 0)
                        Button {
                            shortcutPhrase = phrase
                        } label: {
                            Label(phrase.shortcut.isEmpty ? String(localized: "Shortcut") : phrase.shortcut, systemImage: "command")
                                .font(EchoFont.body(13, weight: .bold))
                                .foregroundStyle(Palette.controlAccent)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(phrase.shortcut.isEmpty ? String(localized: "Add shortcut for %@", defaultValue: "Add shortcut for \(String(describing: phrase.label))") : String(localized: "Edit shortcut for %@", defaultValue: "Edit shortcut for \(String(describing: phrase.label))"))

                        Button {
                            store.deletePhrase(phrase)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.red)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(String(localized: "Delete %@", defaultValue: "Delete \(String(describing: phrase.label))"))
                    }
                }
                .padding(12)
                .background(Palette.background.opacity(0.55), in: .rect(cornerRadius: 14))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    private var onboardingWizardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.controlAccent)
                Text(String(localized: "Setup"))
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
                Spacer()
            }

            Button {
                showOnboardingSheet = true
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text(String(localized: "Run setup again"))
                        .font(EchoFont.body(15, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(14)
                .background(Palette.controlAccent, in: .rect(cornerRadius: 14))
                .foregroundStyle(Palette.onControlAccent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }
}

private struct ShortcutEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let phrase: Phrase
    @State private var value: String
    @State private var error: String?

    init(phrase: Phrase) {
        self.phrase = phrase
        _value = State(initialValue: phrase.shortcut)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A short code to find this phrase fast.")
                        .font(EchoFont.body(16))
                        .foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(phrase.text)
                            .font(EchoFont.body(18, weight: .bold))
                            .foregroundStyle(Palette.forest)
                        TextField("e.g. app", text: $value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(EchoFont.body(18))
                            .padding(14)
                            .background(Palette.surface, in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2))
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(EchoFont.body(14, weight: .bold))
                            .foregroundStyle(Palette.red)
                    }
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "Personal Shortcut"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        if store.setShortcut(value, for: phrase) { dismiss() }
                        else { error = String(localized: "That shortcut is already in use or too long.") }
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}
