import SwiftUI

private struct QuickTileHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The core AAC board — a pixel-faithful port of the web design's Patient Home
/// screen: 2-column grid of large phrase tiles, HELP / I'm Okay bar, and a
/// "Speaking: …" toast. Designed for failing vision and motor control — big
/// targets, huge type, high contrast, full VoiceOver support.
struct SpeakBoardView: View {
    @Environment(\.openURL) private var openURL
    private enum BoardMode: String, CaseIterable, Identifiable {
        case quick = "Quick"
        case core = "Build"
        case type = "Type"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .quick: return String(localized: "Quick")
            case .core: return String(localized: "Build")
            case .type: return String(localized: "Type")
            }
        }
        var icon: String {
            switch self {
            case .quick: return "square.grid.2x2.fill"
            case .core: return "text.word.spacing"
            case .type: return "keyboard.fill"
            }
        }
    }

    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @ScaledMetric(relativeTo: .title) private var tileMinHeight = 120
    /// Single-column tiles are already full width, so they need far less height —
    /// using the square-tile minimum there wastes most of the screen and drops the
    /// number of visible phrases to two.
    @ScaledMetric(relativeTo: .title) private var rowMinHeight = 64
    @ScaledMetric(relativeTo: .body) private var phraseMinWidth = 180
    @ScaledMetric(relativeTo: .body) private var compactMinWidth = 120
    @ScaledMetric(relativeTo: .body) private var handsFreeMinWidth = 240
    @ScaledMetric(relativeTo: .body) private var wordMinWidth = 120
    @ScaledMetric(relativeTo: .body) private var wordMinHeight = 62
    @ScaledMetric(relativeTo: .body) private var categoryMinWidth = 150
    @ScaledMetric(relativeTo: .body) private var categoryTileHeight = 108
    @State private var boardWidth: CGFloat = 0
    /// Presented as a modal cover rather than an overlay so it sits above the tab
    /// bar: during an emergency the board must not be navigable away from, and an
    /// in-stack overlay leaves the tabs tappable underneath.
    private enum ActiveAlert: Identifiable {
        case help
        var id: Self { self }
    }
    @State private var activeAlert: ActiveAlert?
    @State private var showOkayConfirmation = false
    @State private var showAddPhrase = false
    @State private var showPersonalInfo = false
    @State private var boardMode: BoardMode = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-EchoVoiceCoreMode") { return .core }
        if arguments.contains("-EchoVoiceTypeMode") { return .type }
        return .quick
    }()
    @State private var selectedCategoryID = "core"
    @State private var browsingCategories = ProcessInfo.processInfo.arguments.contains("-EchoVoiceCategoriesMode")
    @State private var composedMessage = ""
    @State private var showConversationWorkspace = false
    @State private var showHandsFreeConversation = false
    @State private var helpAfterConversation = false
    @State private var quickPage = 0
    @State private var quickGridViewportHeight: CGFloat = 0
    @State private var quickBoardHeight: CGFloat = 0
    @State private var suggestionBlockHeight: CGFloat = 96
    @State private var quickTallestTileHeight: CGFloat = 0
    @State private var coreGridViewportHeight: CGFloat = 0
    @State private var categoryGridHeight: CGFloat = 0
    @State private var categoryPage = 0
    @State private var corePage = 0
    @State private var suggestedPhraseIDs: [UUID] = []
    @State private var showSuggestionExplainer = false
    @State private var showAllSuggestions = false
    @State private var sentenceExpander = SentenceExpander()
    @State private var showPartnerDisplay = false
    @State private var showPartnerListen = false
    @State private var helpAfterListen = false
    @State private var showGazeSetup = false
    @State private var isOnScreen = false
    @FocusState private var typeFieldFocused: Bool
    @State private var helpSpeakTask: Task<Void, Never>?
    @State private var helpDismissTask: Task<Void, Never>?
    /// The Messages sheet is open over the HELP screen. While it is, nothing
    /// closes HELP automatically, or the half-written text would vanish with it.
    @State private var isTextingContact = false

    /// Spoken aloud when calling for help. Phrased as a direct request so a
    /// bystander who hears it knows what is being asked of them.
    private var helpPhrase: String { store.helpPhrase }
    private let helpRepetitions = 5

    private var callContactTitle: String {
        let name = store.emergencyContactName
        return name.isEmpty ? String(localized: "Call") : String(localized: "Call %@", defaultValue: "Call \(String(describing: name))")
    }

    @State private var lastTileTouch: Date = .distantPast

    @State private var unlockProgress: Double = 0.0
    @State private var isHoldingUnlock = false
    @State private var unlockTimer: Timer?

    /// Whether this is a wide screen (iPad, or iPhone in landscape).
    private var isWide: Bool { horizontalSizeClass == .regular }

    /// Column count adapts to both screen width and text size.
    ///
    /// On iPad — the common setup for a wheelchair- or bed-mounted board — two
    /// columns leaves nearly half the screen empty and stretches each tile into a
    /// wide, short slab. More columns means more phrases visible at once, which
    /// directly means fewer taps to reach a word.
    ///
    /// At accessibility text sizes the count drops, because a narrow tile can't
    /// fit a word like "Bathroom" on one line once scaled up and breaks it
    /// mid-word into "Bathroo / m" — unreadable on a board someone scans.
    /// Whether the board is being driven by head or eye tracking right now.
    ///
    /// This is not the same question as "is hands-free enabled" — Direct Select
    /// leaves the manager enabled while the person still taps, and a tapping
    /// person does not want a four-tile board.
    /// Hands-free layout (fewer, larger tiles) once gaze can actually select.
    /// Eye gaze before its setup cannot, so the board stays at its normal
    /// density for whoever is tapping — instead of two phrases a page.
    private var isHandsFreeActive: Bool {
        eyeGaze.isSelectionReady
    }

    /// Anything drawn over the board. While one is up, the board's controls
    /// leave dwell selection: a cursor resting where a tile used to be must not
    /// speak it from behind a sheet.
    private var isBoardCovered: Bool {
        showHandsFreeConversation || showAddPhrase || showAllSuggestions || showConversationWorkspace
            || showPersonalInfo || showPartnerDisplay || showPartnerListen || showSuggestionExplainer || showGazeSetup
            || activeAlert != nil
    }

    private var columnCount: Int {
        if isWide {
            return BoardLayout.columnCount(width: gridWidth, minimum: quickMinimumWidth, spacing: gridSpacing)
        }
        if dynamicTypeSize.isAccessibilitySize {
            return 1
        }
        // Dwell selection has to hit a target the cursor can be *held* inside,
        // not merely touched. Cursor jitter is a few dozen points even after
        // filtering, so a tile sized for a fingertip produces mis-selections and
        // the fatigue of chasing a target — the two failures that make people
        // abandon hands-free access. Fewer, larger tiles cost a page turn and
        // buy a selection that works the first time.
        if isHandsFreeActive {
            return 2
        }
        if store.boardDensity == "compact" {
            return 3
        }
        return 2
    }

    private var columns: [GridItem] {
        if isWide {
            return [GridItem(.adaptive(minimum: min(gridWidth, quickMinimumWidth)), spacing: gridSpacing)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnCount)
    }

    private var gridWidth: CGFloat { max(1, boardWidth - 32) }

    private var quickMinimumWidth: CGFloat {
        if isHandsFreeActive { return handsFreeMinWidth }
        return store.boardDensity == "compact" ? compactMinWidth : phraseMinWidth
    }

    /// Wider gutters under hands-free control. Adjacent targets separated only
    /// by a hairline are the main source of wrong-neighbour selections when the
    /// cursor drifts between two tiles.
    private var gridSpacing: CGFloat {
        if isHandsFreeActive { return 20 }
        return store.boardDensity == "compact" ? 8 : 14
    }

    private var quickTileHeight: CGFloat {
        let estimatedHeight: CGFloat
        if columnCount == 1 {
            estimatedHeight = max(rowMinHeight + 24, 130)
        } else if isHandsFreeActive {
            estimatedHeight = max(tileMinHeight, 140) + 44
        } else if store.boardDensity == "compact" {
            estimatedHeight = isWide ? 70 : 88
        } else {
            estimatedHeight = isWide ? tileMinHeight + 36 : 88
        }
        return max(quickTallestTileHeight, estimatedHeight)
    }

    private func quickRows(fitting height: CGFloat) -> Int {
        let availableHeight = max(0, height - 8)
        return max(1, Int((availableHeight + gridSpacing) / (quickTileHeight + gridSpacing)))
    }

    /// Suggestions are a shortcut, not the board. On a short phone they are
    /// shown only when they do not cost the board a row: an iPhone SE was
    /// left with two phrases per page and a blank half-screen.
    ///
    /// Decided from the whole Quick area's height, which does not change
    /// when the row comes and goes, so the decision cannot feed back on itself.
    private var showsSuggestionRow: Bool {
        guard !smartSuggestionPhrases.isEmpty else { return false }
        // Under hands-free control on a phone the chips would be the smallest
        // targets on screen, which is exactly what dwell selection misses.
        if isHandsFreeActive && !isWide { return false }
        guard !isWide, quickBoardHeight > 0 else { return true }
        // Assume page controls are shown: whether they are depends on the
        // page size, which depends on this decision.
        let pageControls: CGFloat = 68
        let without = quickRows(fitting: quickBoardHeight - pageControls)
        let with = quickRows(fitting: quickBoardHeight - pageControls - suggestionBlockHeight - 8)
        return with >= min(without, 2)
    }

    private var quickPageSize: Int {
        let rows = quickRows(fitting: quickGridViewportHeight)
        // Touch users get every row that fits, up to five on a phone — a
        // three-row cap left a blank band a row or two high on taller iPhones.
        // Hands-free targets stay on two rows so gaze drift never turns a
        // phrase into a small target.
        return columnCount * min(rows, isWide ? 6 : (isHandsFreeActive ? 2 : 5))
    }

    private var quickPageCount: Int {
        max(1, Int(ceil(Double(store.phrases.count) / Double(quickPageSize))))
    }

    private var quickPhrases: ArraySlice<Phrase> {
        let safePage = min(quickPage, quickPageCount - 1)
        let start = safePage * quickPageSize
        return store.phrases[start..<min(start + quickPageSize, store.phrases.count)]
    }

    /// The suggestions chosen at the last refresh (appearing, or switching
    /// to Quick). They deliberately do not change as phrases are spoken or
    /// pages turn: when the row followed the page — dropping suggestions
    /// already visible — it appeared and vanished between pages, which resized
    /// the grid, which moved every phrase under the next tap.
    private var smartSuggestionPhrases: [Phrase] {
        suggestedPhraseIDs.compactMap { id in store.phrases.first(where: { $0.id == id }) }
    }

    private var categories: [AACWordCategory] {
        let personal = AACWordCategory(
            id: "personal",
            title: String(localized: "Personal"),
            words: AACVocabulary.personalMessages(
                name: store.profileName,
                dateOfBirth: store.profileDateOfBirth,
                address: store.profileAddress,
                phone: store.profilePhone,
                email: store.profileEmail,
                medicalConditions: store.profileMedicalConditions,
                medications: store.profileMedications,
                allergies: store.profileAllergies,
                emergencyContact: store.profileEmergencyContact
            )
        )
        let allWords = AACWordCategory(id: "all-words", title: String(localized: "All Words"), words: AACVocabulary.allBuilderWords)
        return [personal, allWords] + AACVocabulary.categories
    }

    private var selectedCategory: AACWordCategory {
        categories.first(where: { $0.id == selectedCategoryID }) ?? categories[1]
    }

    private var coreMinimumWidth: CGFloat {
        selectedCategoryID == "personal" ? max(320, phraseMinWidth) :
            (isHandsFreeActive ? handsFreeMinWidth : (store.boardDensity == "compact" ? compactMinWidth : wordMinWidth))
    }

    private var coreSpacing: CGFloat { isWide && isHandsFreeActive ? 20 : 8 }

    private var coreTileHeight: CGFloat {
        if isHandsFreeActive { return max(96, wordMinHeight) }
        return store.boardDensity == "compact" ? wordMinHeight * 48 / 62 : wordMinHeight
    }

    private var coreColumnCount: Int {
        if isWide {
            return BoardLayout.columnCount(width: gridWidth, minimum: coreMinimumWidth, spacing: coreSpacing)
        }
        let count: Int
        if selectedCategoryID == "personal" {
            count = 1
        } else if dynamicTypeSize.isAccessibilitySize {
            count = 2
        } else {
            count = 3
        }
        return count
    }

    private var coreColumns: [GridItem] {
        if isWide {
            return [GridItem(.adaptive(minimum: min(gridWidth, coreMinimumWidth)), spacing: coreSpacing)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: coreColumnCount)
    }

    private var categoryColumnCount: Int {
        isWide ? BoardLayout.columnCount(width: gridWidth, minimum: categoryMinimumWidth, spacing: coreSpacing) :
            (dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }

    private var categoryMinimumWidth: CGFloat {
        isHandsFreeActive ? handsFreeMinWidth : categoryMinWidth
    }

    private var categoryColumns: [GridItem] {
        if isWide {
            return [GridItem(.adaptive(minimum: min(gridWidth, categoryMinimumWidth)), spacing: coreSpacing)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: categoryColumnCount)
    }

    private var categoryPageSize: Int {
        if isWide {
            let rows = max(1, Int((categoryGridHeight + coreSpacing) / (categoryTileHeight + coreSpacing)))
            return categoryColumnCount * min(rows, 6)
        }
        if dynamicTypeSize.isAccessibilitySize { return 4 }
        // Every row that fits on a touch phone: a fixed nine left a taller
        // iPhone with half a screen of blank space and a second page.
        // Hands-free keeps three rows so the targets stay well apart.
        guard !isHandsFreeActive, categoryGridHeight > 0 else { return 9 }
        let rowHeight: CGFloat = 62 + 8
        let rows = max(3, Int((categoryGridHeight + 8) / rowHeight))
        let perPage = categoryColumnCount * rows
        // When the page controls are showing, the space they take could hold
        // the last row: show every category on one page instead.
        let pageControls: CGFloat = 68
        let rowsWithoutControls = Int((categoryGridHeight + pageControls + 8) / rowHeight)
        if categoryPageCount(perPage: perPage) > 1,
           categories.count <= categoryColumnCount * rowsWithoutControls {
            return categories.count
        }
        return perPage
    }

    private var categoryPageCount: Int {
        categoryPageCount(perPage: categoryPageSize)
    }

    private func categoryPageCount(perPage: Int) -> Int {
        max(1, Int(ceil(Double(categories.count) / Double(max(1, perPage)))))
    }

    private var visibleCategories: ArraySlice<AACWordCategory> {
        let safePage = min(categoryPage, categoryPageCount - 1)
        let start = safePage * categoryPageSize
        return categories[start..<min(start + categoryPageSize, categories.count)]
    }

    private var corePageSize: Int {
        if selectedCategoryID == "personal" && !isWide { return 1 }
        // The word button's own minimum height; the grid sits in a scroll view
        // (2 pt padding top and bottom), so a word that wraps scrolls rather
        // than clips.
        let estimatedRowHeight: CGFloat = isWide ? coreTileHeight : (dynamicTypeSize.isAccessibilitySize ? 86 : 62)
        let rows = max(1, Int((coreGridViewportHeight - 4 + coreSpacing) / (estimatedRowHeight + coreSpacing)))
        return coreColumnCount * min(rows, isWide ? 8 : 5)
    }
    private var corePageCount: Int {
        max(1, Int(ceil(Double(selectedCategory.words.count) / Double(corePageSize))))
    }

    private var coreWords: ArraySlice<String> {
        let safePage = min(corePage, corePageCount - 1)
        let start = safePage * corePageSize
        return selectedCategory.words[start..<min(start + corePageSize, selectedCategory.words.count)]
    }

    private var spokenMessage: String {
        composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                communicationContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        boardWidth = width
                        quickTallestTileHeight = 0
                        clampPages()
                        eyeGaze.resetDwell()
                    }

                if eyeGaze.isHandsFreeActive && eyeGaze.showsTrackingDiagnostics {
                    GazeDiagnosticsOverlay(manager: eyeGaze)
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                }
            }
            .background(Palette.background)
            // Reserve space for fixed controls. A wrapping VStack let the
            // scrollable board draw beneath these controls on short iPhones.
            //
            // Status messages (speaking, HELP ready, I'm Okay saved) draw *over*
            // the mode selector instead of being inserted above the board. An
            // inserted banner pushed every tile down while a phrase spoke and
            // back up when it ended — so the next tap, or a dwelling cursor,
            // landed on a different phrase than the one aimed at.
            .safeAreaInset(edge: .top, spacing: 8) {
                VStack(spacing: 8) {
                    handsFreeSetupBanner
                    topStatusSlot
                }
                .padding(.horizontal, 16)
                .readableContentWidth(900)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Even padding, with the corner radius matched to the 18pt
                // buttons inside (18 + 10), and a clear gap above the tab bar
                // so the dock and the tab bar read as two separate things.
                helpRow
                    .padding(10)
                    .background(
                        Palette.dockSurface,
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .readableContentWidth(900)
            }
            .navigationTitle("EchoVoice")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if eyeGaze.isHandsFreeActive {
                    ToolbarItem(placement: .principal) {
                        HandsFreeStatusPill()
                    }
                }
                if !store.lockedToBoard {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            eyeGaze.resetDwell()
                            showHandsFreeConversation = true
                        } label: {
                            Label(String(localized: "Hands-free conversation"), systemImage: "eye.circle")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .gazeSelectable(id: "open-handsfree-conversation") {
                            eyeGaze.resetDwell()
                            showHandsFreeConversation = true
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showConversationWorkspace = true
                    } label: {
                        Label(String(localized: "Conversation workspace"), systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .accessibilityHint(String(localized: "Keep a draft, use quick interjections, and retrieve personal shortcuts"))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        eyeGaze.resetDwell()
                        showPartnerListen = true
                    } label: {
                        Label(String(localized: "Listen"), systemImage: "ear")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .gazeSelectable(id: "open-listen") {
                        eyeGaze.resetDwell()
                        showPartnerListen = true
                    }
                    .accessibilityHint(String(localized: "Hear what someone says and get replies to it"))
                }
                if boardMode == .quick && !store.lockedToBoard {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAddPhrase = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(String(localized: "Add a new phrase"))
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if store.lockedToBoard {
                    lockButton
                        .padding(.trailing, 18)
                        .padding(.top, 10)
                }
            }
            // Everything above is the board. Presentations below inherit the
            // environment from here, so they are attached after it.
            .environment(\.gazeSelectionEnabled, !isBoardCovered)
            .fullScreenCover(item: $activeAlert) { kind in
                switch kind {
                case .help:
                    alertScreen(
                        iconName: "exclamationmark.triangle.fill",
                        title: String(localized: "Calling for Help"),
                        subtitle: String(localized: "Speaking out loud so someone nearby can hear."),
                        tint: Color(red: 0.70, green: 0.16, blue: 0.17),
                        onStop: { stopHelp() }
                    )
                }
            }
            .animation(reduceMotion ? nil : Motion.pop, value: topStatus)
            .onAppear {
                Haptics.prepare()
                refreshSmartSuggestions()
                performPendingIntent()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-EchoVoiceOpenGazeSetup") { showGazeSetup = true }
                if ProcessInfo.processInfo.arguments.contains("-EchoVoiceOpenConversation") { showHandsFreeConversation = true }
                if ProcessInfo.processInfo.arguments.contains("-EchoVoiceOpenPartner") { showPartnerDisplay = true }
                if ProcessInfo.processInfo.arguments.contains("-EchoVoiceOpenListen") { showPartnerListen = true }
                if ProcessInfo.processInfo.arguments.contains("-EchoVoiceFocusType") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        typeFieldFocused = true
                    }
                }
                #endif
            }
            // An intent can arrive while the app is already running, so a launch-
            // time check alone would drop it.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { performPendingIntent() }
            }
            .sheet(isPresented: $showAddPhrase) { AddPhraseSheet() }
            .sheet(isPresented: $showAllSuggestions) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(smartSuggestionPhrases) { phrase in
                                suggestionButton(phrase)
                            }
                        }
                        .padding(20)
                    }
                    .background(Palette.background)
                    .navigationTitle(String(localized: "Suggested phrases"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) { showAllSuggestions = false }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showHandsFreeConversation, onDismiss: {
                eyeGaze.resetDwell()
                if helpAfterConversation {
                    helpAfterConversation = false
                    triggerHelp()
                }
            }) {
                HandsFreeConversationView(message: $composedMessage) {
                    helpAfterConversation = true
                    showHandsFreeConversation = false
                }
            }
            .fullScreenCover(isPresented: $showPartnerListen, onDismiss: {
                eyeGaze.resetDwell()
                if helpAfterListen {
                    helpAfterListen = false
                    triggerHelp()
                }
            }) {
                PartnerListenView {
                    helpAfterListen = true
                    showPartnerListen = false
                }
            }
            .fullScreenCover(isPresented: $showGazeSetup, onDismiss: { eyeGaze.resetDwell() }) {
                GazeCalibrationView()
            }
            .sheet(isPresented: $showConversationWorkspace) {
                ConversationWorkspaceSheet(message: $composedMessage)
            }
            .sheet(isPresented: $showPersonalInfo) { PersonalInfoEditorSheet() }
            .fullScreenCover(isPresented: $showPartnerDisplay) {
                PartnerDisplayView(
                    draft: composedMessage,
                    lastSpoken: store.conversationHistory.last,
                    isSpeaking: speaker.speakingPhraseID != nil || speaker.isSpeaking
                )
            }
            .sheet(isPresented: $showSuggestionExplainer) {
                SuggestionExplainerSheet(
                    entries: store.suggestionExplanations(limit: isWide ? 4 : 3),
                    labelForID: { store.phraseLabel(forID: $0) }
                )
            }
            .onAppear {
                composedMessage = store.draftMessage
                // Same path as the HELP button: for a user who can't move, the
                // blink trigger is the only way to call for help, so it must not
                // be a weaker version of it.
                eyeGaze.onEmergencyBlinkTrigger = {
                    // From another tab the alert cannot present here yet; the
                    // tab container switches to the board and the request is
                    // raised on appear instead.
                    guard isOnScreen, eyeGaze.consumeHelpRequest() else { return }
                    handleBlinkHelp()
                }
                eyeGaze.onBlinkNavigationTrigger = {
                    guard isOnScreen, !isBoardCovered else { return }
                    advanceCurrentPage(wrapping: true)
                }
                isOnScreen = true
                applyIdleTimer(boardVisible: true)
                // The board just arrived under wherever the person was already
                // looking (after onboarding, setup, or another tab). That was
                // not a choice.
                eyeGaze.resetDwell()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-EchoVoiceLogGaze") { print("ECHOVOICE_GAZE event=boardAppear") }
                #endif
                if eyeGaze.consumeHelpRequest() { handleBlinkHelp() }
            }
            .onDisappear {
                isOnScreen = false
                applyIdleTimer(boardVisible: false)
            }
            .onChange(of: store.keepScreenAwake) { applyIdleTimer(boardVisible: isOnScreen) }
            .onChange(of: store.phrases.count) {
                clampPages()
                if boardMode == .quick { refreshSmartSuggestions() }
            }
            .onChange(of: composedMessage) { _, newValue in
                store.draftMessage = newValue
            }
            .onChange(of: store.boardDensity) {
                quickTallestTileHeight = 0
                clampPages()
            }
            .onChange(of: isHandsFreeActive) {
                quickTallestTileHeight = 0
                clampPages()
            }
            .onChange(of: dynamicTypeSize) {
                quickTallestTileHeight = 0
                clampPages()
                eyeGaze.resetDwell()
            }
            .onChange(of: columnCount) {
                clampPages()
                eyeGaze.resetDwell()
            }
            .onChange(of: selectedCategoryID) {
                corePage = 0
                eyeGaze.resetDwell()
            }
            .onChange(of: isBoardCovered) { eyeGaze.resetDwell() }
            .onChange(of: quickPage) { eyeGaze.resetDwell() }
            .onChange(of: corePage) { eyeGaze.resetDwell() }
            .onChange(of: categoryPage) { eyeGaze.resetDwell() }
        }
    }

    // MARK: Status slot

    private enum TopStatus: Equatable {
        case helpArmed
        case speaking(String)
        case okaySaved
    }

    /// What the slot over the mode selector shows, most urgent first.
    private var topStatus: TopStatus? {
        if eyeGaze.isEmergencyBlinkArmed { return .helpArmed }
        if let phrase = store.phrases.first(where: { $0.id == speaker.speakingPhraseID }) {
            return .speaking(phrase.label)
        }
        if speaker.isSpeaking, let text = speaker.speakingText { return .speaking(text) }
        if showOkayConfirmation { return .okaySaved }
        return nil
    }

    /// The mode selector, with any status drawn over it at exactly its size.
    private var topStatusSlot: some View {
        modeSelector
            .opacity(topStatus == nil ? 1 : 0)
            .environment(\.gazeSelectionEnabled, !isBoardCovered && topStatus == nil)
            .accessibilityHidden(topStatus != nil)
            .overlay {
                if let status = topStatus {
                    statusCard(status)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                }
            }
    }

    @ViewBuilder
    private func statusCard(_ status: TopStatus) -> some View {
        switch status {
        case .helpArmed:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "HELP ready. Close your eyes and hold."))
                        .font(EchoFont.body(15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    ProgressView(value: eyeGaze.helpHoldProgress)
                        .tint(Palette.ink)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.orange, in: .rect(cornerRadius: 15))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        case .speaking(let label):
            speakingToast(label)
        case .okaySaved:
            Label(String(localized: "I'm Okay saved on this device"), systemImage: "checkmark.circle.fill")
                .font(EchoFont.body(15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.09, green: 0.27, blue: 0.15), in: .rect(cornerRadius: 15))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// Shown when hands-free is on but cannot select yet. Persistent for as
    /// long as that is true, so it never makes the board jump.
    @ViewBuilder
    private var handsFreeSetupBanner: some View {
        if eyeGaze.isHandsFreeActive && (eyeGaze.needsCalibration || eyeGaze.calibrationOrientationMismatch) {
            HStack(spacing: 12) {
                BearMascotView(mood: .idle, animated: false)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyeGaze.calibrationOrientationMismatch ? String(localized: "Set up again for this position") : String(localized: "Head control needs a short setup"))
                        .font(EchoFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                    Text(String(localized: "Until then, looking will not select anything."))
                        .font(EchoFont.body(13))
                        .foregroundStyle(Palette.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(String(localized: "Set up")) { showGazeSetup = true }
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.onControlAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Palette.controlAccent, in: .capsule)
            }
            .padding(12)
            .background(Palette.lime.opacity(0.28), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Communication modes

    private var modeSelector: some View {
        HStack(spacing: 8) {
            ForEach(BoardMode.allCases) { mode in
                let selected = boardMode == mode
                Button {
                    selectBoardMode(mode)
                } label: {
                    // At accessibility sizes the icon is dropped and the text
                    // capped, so the three names stay whole instead of "Q…".
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            Text(mode.title)
                        } else {
                            Label(mode.title, systemImage: mode.icon)
                        }
                    }
                        .font(EchoFont.body(16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(selected ? Palette.onControlAccent : Palette.controlAccent)
                        .background(selected ? Palette.controlAccent : Palette.surface, in: .rect(cornerRadius: 15))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .strokeBorder(Palette.forest.opacity(selected ? 0 : 0.14), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .gazeSelectable(id: "mode-\(mode.id)") {
                    selectBoardMode(mode)
                }
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func selectBoardMode(_ mode: BoardMode) {
        if mode != .type { dismissKeyboard() }
        withAnimation(reduceMotion ? nil : Motion.snap) {
            boardMode = mode
            if mode == .core { browsingCategories = true }
        }
        if mode == .quick { refreshSmartSuggestions() }
        eyeGaze.resetDwell()
    }

    @ViewBuilder
    private var communicationContent: some View {
        VStack(spacing: 8) {
            if isWide && dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    conversationBar
                    partnerDisplayButton
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
            } else {
                HStack(spacing: 8) {
                    // The navigation bar opens the workspace on iPhone. Its card
                    // would repeat that action and crowd Build and Type.
                    if isWide || (boardMode == .quick && !composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        conversationBar
                            .transition(.opacity)
                    }
                    // Offered only on a screen large enough to be read from across a
                    // table. On a phone the partner display would be no easier to
                    // read than the board itself.
                    if isWide { partnerDisplayButton }
                }
                .padding(.horizontal, 16)
            }
            if boardMode == .core,
               !browsingCategories,
               !AACVocabulary.speaksImmediately(categoryID: selectedCategory.id) {
                composedMessageBar
                // Core-word building is exactly where telegraphic output comes
                // from, so the phrasing offer belongs against that composer and
                // not only in Type.
                SentencePolishBar(draft: $composedMessage, expander: sentenceExpander) { _ in }
                    .padding(.horizontal, 16)
            }

            switch boardMode {
            case .quick:
                quickBoard
            case .core:
                coreBoard
            case .type:
                typeBoard
            }
        }
    }

    private var partnerDisplayButton: some View {
        Button {
            showPartnerDisplay = true
        } label: {
            Label(String(localized: "Partner view"), systemImage: "person.2.fill")
                .font(EchoFont.body(14, weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Palette.surface, in: .rect(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .gazeSelectable(id: "partner-display") { showPartnerDisplay = true }
        .accessibilityLabel(String(localized: "Open partner view"))
        .accessibilityHint(String(localized: "Shows your message in large type for the person you are talking to"))
    }

    private var conversationBar: some View {
        Button {
            showConversationWorkspace = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Conversation workspace") : String(localized: "Draft ready to continue"))
                        .font(EchoFont.body(14, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                    Text(composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? String(localized: "Keep a thought safe through interruptions")
                         : composedMessage.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(EchoFont.body(12))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(composedMessage.isEmpty ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.controlAccent)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Palette.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(composedMessage.isEmpty ? String(localized: "Open conversation workspace") : String(localized: "Open conversation workspace, draft in progress"))
    }

    private var quickBoard: some View {
        VStack(spacing: 8) {
            // The suggestion row is the visible face of the on-device ranker, so
            // it belongs on the page people actually look at. It stays visible
            // while a phrase speaks: hiding it then slid every tile up under the
            // finger, and back down when speech ended.
            if showsSuggestionRow {
                VStack(spacing: 8) {
                    smartSuggestionHeader
                    smartSuggestionRow
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { suggestionBlockHeight = $0 }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(Array(quickPhrases)) { phrase in
                        tile(for: phrase)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .onPreferenceChange(QuickTileHeightPreferenceKey.self) { height in
                    if height > quickTallestTileHeight {
                        quickTallestTileHeight = height
                        clampPages()
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: quickPage)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { quickGridViewportHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, height in
                            quickGridViewportHeight = height
                            clampPages()
                        }
                }
            }

            if quickPageCount > 1 {
                pageControls(
                    id: "quick",
                    current: quickPage,
                    total: quickPageCount,
                    previous: { quickPage = max(0, quickPage - 1) },
                    next: { quickPage = min(quickPageCount - 1, quickPage + 1) }
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { quickBoardHeight = $0 }
    }

    /// Names the context the ranker just conditioned on.
    ///
    /// Without this the row is three unexplained buttons. With it, the model's
    /// two conditioning signals — time of day, and what was said last — are
    /// stated in the person's own words before they choose anything.
    private var smartSuggestionHeader: some View {
        HStack(spacing: 8) {
            Text(dynamicTypeSize.isAccessibilitySize ? String(localized: "Suggested") : suggestionContextLabel)
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Button(String(localized: "All")) { showAllSuggestions = true }
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.forest)
                .frame(minWidth: 44, minHeight: 44)
                .gazeSelectable(id: "suggestion-all") { showAllSuggestions = true }
                .accessibilityLabel(String(localized: "Show all suggested phrases"))

            Button {
                showSuggestionExplainer = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text(String(localized: "Why?"))
                }
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.forest)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .gazeSelectable(id: "suggestion-why") { showSuggestionExplainer = true }
            .accessibilityLabel(String(localized: "Why these suggestions?"))
            .accessibilityHint(String(localized: "Explains how EchoVoice ranked these phrases"))
        }
        .padding(.horizontal, 16)
    }

    /// e.g. "Suggested \u{00B7} morning \u{00B7} after \u{201C}Water\u{201D}".
    private var suggestionContextLabel: String {
        var parts = [String(localized: "Suggested"), AdaptivePhraseRanker.bucketName(for: .now)]
        if let previous = store.conversationHistory.last {
            let trimmed = previous.count > 22 ? String(previous.prefix(22)) + "\u{2026}" : previous
            parts.append(String(localized: "after “%@”", defaultValue: "after \u{201C}\(String(describing: trimmed))\u{201D}"))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var smartSuggestionRow: some View {
        if isWide || !dynamicTypeSize.isAccessibilitySize {
            let columns = isWide
                ? [GridItem(.adaptive(minimum: min(gridWidth, phraseMinWidth)), spacing: 8)]
                : Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(smartSuggestionPhrases) { phrase in
                    suggestionButton(phrase)
                }
            }
            .padding(.horizontal, 16)
        } else {
            // At accessibility text sizes, wide cards stay in one row so the
            // scaled labels remain legible. All choices are also in the sheet.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(smartSuggestionPhrases) { phrase in
                        suggestionButton(phrase)
                            .frame(width: dynamicTypeSize.isAccessibilitySize ? 220 : 150)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.visible)
        }
    }

    private func suggestionButton(_ phrase: Phrase) -> some View {
        let speaking = speaker.speakingPhraseID == phrase.id
        return Button {
            // In hold-to-speak mode the hold gesture below speaks instead.
            guard !store.holdToSpeak else { return }
            speakFromTouch(phrase)
        } label: {
            Text(phrase.label)
                .font(EchoFont.body(15, weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .background(
                    speaking
                        ? (store.highContrastEnabled ? Palette.contrastSage : Palette.lime)
                        : Palette.surface,
                    in: .rect(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Palette.forest.opacity(0.14), lineWidth: 2)
                }
        }
        .buttonStyle(Pressable())
        .holdToSpeak(enabled: store.holdToSpeak) { speakFromTouch(phrase) }
        .gazeSelectable(id: "smart-\(phrase.id)") { speakAndLearn(phrase) }
        .accessibilityLabel(String(localized: "Suggested: %@", defaultValue: "Suggested: \(String(describing: phrase.text))"))
        .accessibilityAction(.default) { Haptics.tap(); speakAndLearn(phrase) }
        .accessibilityHint(String(localized: "Speaks this phrase aloud"))
    }

    private func refreshSmartSuggestions() {
        guard store.smartSuggestionsEnabled, store.hasLearnedSuggestions else {
            suggestedPhraseIDs = []
            return
        }
        let limit = isWide ? 4 : 3
        suggestedPhraseIDs = store.suggestedPhrases(limit: limit).map(\.id)
    }

    /// Touch path. Drops a tap that lands too soon after the last one: with a
    /// tremor that is almost always a bounce or a slide onto the next tile, and
    /// acting on it would cut off the phrase the person actually chose.
    private func speakFromTouch(_ phrase: Phrase) {
        let now = Date()
        if store.ignoreRepeatTaps, now.timeIntervalSince(lastTileTouch) < AppStore.repeatTapWindow {
            return
        }
        lastTileTouch = now
        Haptics.tap()
        speakAndLearn(phrase)
    }

    private func applyIdleTimer(boardVisible: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = boardVisible && store.keepScreenAwake
        #endif
    }

    private func speakAndLearn(_ phrase: Phrase) {
        guard speaker.speakingPhraseID != phrase.id else { return }
        store.recordPhraseUse(phrase)
        store.rememberSpokenMessage(phrase.text)
        speaker.speak(phrase, rate: store.speechRate, volume: store.speechVolume)
    }

    private var coreBoard: some View {
        VStack(spacing: 8) {
            coreCategoryHeader

            if browsingCategories {
                categoryBrowser
            } else if selectedCategory.id == "personal" && selectedCategory.words.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Palette.controlAccent)
                    Text(String(localized: "Add contact, medical, and emergency details for fast one-tap introductions."))
                        .font(EchoFont.body(16, weight: .medium))
                        .foregroundStyle(Palette.primaryText)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "Set Up Personal Info")) { showPersonalInfo = true }
                        .font(EchoFont.body(16, weight: .bold))
                        .foregroundStyle(Palette.onControlAccent)
                        .frame(minHeight: 48)
                        .padding(.horizontal, 18)
                        .background(Palette.controlAccent, in: .rect(cornerRadius: 15))
                        .gazeSelectable(id: "personal-setup") { showPersonalInfo = true }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surface, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 16)
            } else {
                ScrollView {
                    LazyVGrid(columns: coreColumns, spacing: coreSpacing) {
                        ForEach(Array(coreWords.enumerated()), id: \.offset) { index, word in
                            coreWordButton(word, index: index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { coreGridViewportHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { _, height in
                                coreGridViewportHeight = height
                                clampPages()
                            }
                    }
                }
            }

            if !browsingCategories {
                pageControls(
                    id: "core-\(selectedCategory.id)",
                    current: corePage,
                    total: corePageCount,
                    previous: { corePage = max(0, corePage - 1) },
                    next: { corePage = min(corePageCount - 1, corePage + 1) }
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var coreCategoryHeader: some View {
        Button {
            browsingCategories = true
            eyeGaze.resetDwell()
        } label: {
            HStack(spacing: 8) {
                Label(
                    browsingCategories ? String(localized: "Choose a Category") : selectedCategory.title,
                    systemImage: browsingCategories ? "rectangle.grid.3x2.fill" : "chevron.left"
                )
                .font(EchoFont.body(17, weight: .bold))

                Spacer()

                if !browsingCategories && AACVocabulary.speaksImmediately(categoryID: selectedCategory.id) {
                    Label(String(localized: "Tap to Speak"), systemImage: "speaker.wave.2.fill")
                        .font(EchoFont.body(13, weight: .bold))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .foregroundStyle(Palette.controlAccent)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Palette.surface, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .gazeSelectable(id: "show-categories") {
            browsingCategories = true
            eyeGaze.resetDwell()
        }
        .accessibilityLabel(browsingCategories ? String(localized: "Choose a category") : String(localized: "Back to categories"))
    }

    private var categoryBrowser: some View {
        VStack(spacing: 8) {
            ScrollView {
                LazyVGrid(columns: categoryColumns, spacing: coreSpacing) {
                    ForEach(Array(visibleCategories)) { category in
                        categoryButton(category)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                categoryGridHeight = height
                clampPages()
            }

            pageControls(
                id: "categories",
                current: categoryPage,
                total: categoryPageCount,
                previous: { categoryPage = max(0, categoryPage - 1) },
                next: { categoryPage = min(categoryPageCount - 1, categoryPage + 1) }
            )
        }
        .padding(.horizontal, 16)
    }

    private var typeBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if composedMessage.isEmpty {
                    Text(String(localized: "Type a message"))
                        .font(EchoFont.body(22, weight: .medium))
                        .foregroundStyle(Palette.secondaryText.opacity(0.75))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $composedMessage)
                    .font(EchoFont.body(24, weight: .medium))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .focused($typeFieldFocused)
                    .accessibilityLabel(String(localized: "Message to speak"))
                    // The keyboard covers the tab bar, and a TextEditor has no
                    // return-to-dismiss. Without this there was no way back to
                    // the other tabs short of switching modes.
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(String(localized: "Done")) { dismissKeyboard() }
                                .font(EchoFont.body(17, weight: .bold))
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Palette.forest.opacity(0.16), lineWidth: 2)
            }

            SentencePolishBar(draft: $composedMessage, expander: sentenceExpander) { _ in
                typeFieldFocused = false
            }

            messageActions
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
    }

    private var composedMessageBar: some View {
        // Field above its buttons at accessibility sizes: side by side, the
        // Speak label wrapped one letter per line.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            TextField(String(localized: "Build a sentence"), text: $composedMessage, axis: .vertical)
                .font(EchoFont.body(19, weight: .medium))
                .lineLimit(1...2)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Palette.surface, in: .rect(cornerRadius: 15))
                .accessibilityLabel(String(localized: "Current message"))

            HStack(spacing: 8) {
            messageIconButton(
                id: "message-clear",
                icon: "xmark",
                label: String(localized: "Clear message"),
                disabled: spokenMessage.isEmpty
            ) {
                composedMessage = ""
                speaker.stopSpeaking()
            }

            Button { speakComposedMessage() } label: {
                Label(String(localized: "Speak"), systemImage: "speaker.wave.2.fill")
                    .font(EchoFont.body(16, weight: .bold))
                    .foregroundStyle(Palette.onControlAccent)
                    .frame(minWidth: 82, minHeight: 50)
                    .padding(.horizontal, 8)
                    .background(Palette.controlAccent, in: .rect(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(spokenMessage.isEmpty)
            .opacity(spokenMessage.isEmpty ? 0.45 : 1)
            .gazeSelectable(id: "message-speak", isEnabled: !spokenMessage.isEmpty) { speakComposedMessage() }
            .accessibilityLabel(String(localized: "Speak message"))
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .padding(.horizontal, 16)
    }

    private var messageActions: some View {
        HStack(spacing: 10) {
            Button {
                composedMessage = ""
                speaker.stopSpeaking()
            } label: {
                actionLabel(String(localized: "Clear"), systemImage: "xmark")
                    .font(EchoFont.body(17, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Clear message"))
            .tint(Palette.controlAccent)
            .disabled(spokenMessage.isEmpty)
            .gazeSelectable(id: "type-clear", isEnabled: !spokenMessage.isEmpty) {
                composedMessage = ""
                speaker.stopSpeaking()
            }

            Button { speakComposedMessage() } label: {
                actionLabel(String(localized: "Speak"), systemImage: "speaker.wave.2.fill")
                    .font(EchoFont.body(17, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .accessibilityLabel(String(localized: "Speak message"))
            .buttonStyle(.borderedProminent)
            .tint(Palette.controlAccent)
            .disabled(spokenMessage.isEmpty)
            .gazeSelectable(id: "type-speak", isEnabled: !spokenMessage.isEmpty) { speakComposedMessage() }

            // Always present, only enabled while speaking: a button that
            // appeared mid-sentence squeezed Clear and Speak sideways under the
            // finger or cursor.
            Button { speaker.stopSpeaking() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 54)
            }
            .buttonStyle(.bordered)
            .tint(Palette.red)
            .disabled(!speaker.isSpeaking)
            .gazeSelectable(id: "type-stop", isEnabled: speaker.isSpeaking) { speaker.stopSpeaking() }
            .accessibilityLabel(String(localized: "Stop speaking"))
        }
    }

    /// Icon and title normally; icon only at accessibility sizes, where the
    /// titles no longer fit beside each other. VoiceOver keeps the words.
    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Image(systemName: systemImage)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private func messageIconButton(
        id: String,
        icon: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.onControlAccent)
                .frame(width: 50, height: 50)
                .background(Palette.controlAccent, in: .rect(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .gazeSelectable(id: id, isEnabled: !disabled, action: action)
        .accessibilityLabel(label)
    }

    private func categoryButton(_ category: AACWordCategory) -> some View {
        let selected = category.id == selectedCategory.id
        return Button {
            selectedCategoryID = category.id
            browsingCategories = false
        } label: {
            Text(category.title)
                .font(EchoFont.body(dynamicTypeSize.isAccessibilitySize ? 16 : 15, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .foregroundStyle(selected ? Palette.onControlAccent : Palette.controlAccent)
                .frame(
                    maxWidth: .infinity,
                    minHeight: isWide ? categoryTileHeight : (dynamicTypeSize.isAccessibilitySize ? 72 : 62)
                )
                .padding(.horizontal, 5)
                .background(selected ? Palette.controlAccent : Palette.surface, in: .rect(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .gazeSelectable(id: "category-\(category.id)") {
            selectedCategoryID = category.id
            browsingCategories = false
        }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func coreWordButton(_ word: String, index: Int) -> some View {
        Button {
            useCoreWord(word)
        } label: {
            Text(word)
                .font(EchoFont.body(isWide && store.boardDensity == "compact" ? 15 : (isWide ? 19 : 16), weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: isWide ? coreTileHeight : 62)
                .padding(.horizontal, 8)
                .background(Palette.surface, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2)
                }
        }
        .buttonStyle(Pressable())
        .gazeSelectable(id: "word-\(selectedCategory.id)-\(corePage)-\(index)") {
            useCoreWord(word)
        }
        .accessibilityLabel(
            AACVocabulary.speaksImmediately(categoryID: selectedCategory.id)
                ? String(localized: "Speak %@", defaultValue: "Speak \(String(describing: word))")
                : String(localized: "Add %@ to sentence", defaultValue: "Add \(String(describing: word)) to sentence")
        )
    }

    private func useCoreWord(_ word: String) {
        if AACVocabulary.speaksImmediately(categoryID: selectedCategory.id) {
            Haptics.tap()
            store.rememberSpokenMessage(word)
            speaker.speakRawText(word, rate: store.speechRate, volume: store.speechVolume)
        } else {
            composedMessage = AACVocabulary.appending(word, to: composedMessage)
        }
    }

    @ViewBuilder
    private func pageControls(
        id: String,
        current: Int,
        total: Int,
        previous: @escaping () -> Void,
        next: @escaping () -> Void
    ) -> some View {
        if total > 1 {
            HStack(spacing: 10) {
                pageButton(id: "\(id)-previous", icon: "chevron.left", label: String(localized: "Previous page"), disabled: current == 0, action: previous)

                Text(String(localized: "Page %@ of %@", defaultValue: "Page \(String(describing: current + 1)) of \(String(describing: total))"))
                    .font(EchoFont.body(16, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Motion.snap, value: current)

                pageButton(id: "\(id)-next", icon: "chevron.right", label: String(localized: "Next page"), disabled: current >= total - 1, action: next)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func pageButton(
        id: String,
        icon: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let animatedAction: () -> Void = {
            withAnimation(reduceMotion ? nil : Motion.snap) { action() }
        }
        return Button(action: animatedAction) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .frame(width: 62, height: 52)
                .background(Palette.surface, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .gazeSelectable(id: id, isEnabled: !disabled, action: animatedAction)
        .accessibilityLabel(label)
    }

    /// Clears focus and resigns UIKit's first responder too: leaving Type
    /// mode removed the editor but left the keyboard on screen.
    private func dismissKeyboard() {
        typeFieldFocused = false
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func speakComposedMessage() {
        guard !spokenMessage.isEmpty else { return }
        Haptics.tap()
        store.rememberSpokenMessage(spokenMessage)
        speaker.speakRawText(spokenMessage, rate: store.speechRate, volume: store.speechVolume)
    }

    /// Wrapping is for blink navigation: someone whose only page control is a
    /// held blink would otherwise be stranded on the last page.
    private func advanceCurrentPage(wrapping: Bool = false) {
        func next(_ page: Int, _ count: Int) -> Int {
            page + 1 < count ? page + 1 : (wrapping ? 0 : page)
        }
        withAnimation(reduceMotion ? nil : Motion.snap) {
            switch boardMode {
            case .quick:
                quickPage = next(quickPage, quickPageCount)
            case .core:
                if browsingCategories {
                    categoryPage = next(categoryPage, categoryPageCount)
                } else {
                    corePage = next(corePage, corePageCount)
                }
            case .type:
                break
            }
        }
        eyeGaze.resetDwell()
    }

    private func clampPages() {
        quickPage = min(quickPage, quickPageCount - 1)
        categoryPage = min(categoryPage, categoryPageCount - 1)
        corePage = min(corePage, corePageCount - 1)
    }

    // MARK: Lock Button (Hold 1.5s to Unlock)

    private var lockButton: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(isHoldingUnlock ? String(localized: "Hold...") : String(localized: "Locked"))
                    .font(EchoFont.body(13, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.orange.opacity(0.2))
                    GeometryReader { geo in
                        Capsule().fill(Palette.orange)
                            .frame(width: geo.size.width * unlockProgress)
                    }
                }
            )
            .foregroundStyle(Palette.forest)
            .clipShape(Capsule())
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHoldingUnlock {
                        startUnlockHold()
                    }
                }
                .onEnded { _ in
                    cancelUnlockHold()
                }
        )
        .accessibilityLabel(String(localized: "Board locked"))
        .accessibilityHint(String(localized: "Hold for 1.5 seconds to unlock caregiver settings"))
    }

    private func startUnlockHold() {
        isHoldingUnlock = true
        unlockProgress = 0.0
        let startTime = Date()

        unlockTimer?.invalidate()
        unlockTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak store] _ in
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(startTime)
                self.unlockProgress = min(elapsed / 1.5, 1.0)
                if self.unlockProgress >= 1.0 {
                    self.cancelUnlockHold()
                    store?.lockedToBoard = false
                }
            }
        }
    }

    private func cancelUnlockHold() {
        unlockTimer?.invalidate()
        unlockTimer = nil
        isHoldingUnlock = false
        withAnimation { unlockProgress = 0.0 }
    }

    // MARK: Tile

    private func tile(for phrase: Phrase) -> some View {
        let speaking = speaker.speakingPhraseID == phrase.id
        let gazeID = "phrase-\(phrase.id)"
        let isGazeHovered = isHandsFreeActive && eyeGaze.hoveredTargetID == gazeID
        let isCompact = store.boardDensity == "compact" && !dynamicTypeSize.isAccessibilitySize
        let showSymbol = store.showSymbols
        let cornerRadius: CGFloat = isCompact ? 15 : 28
        let iconSize: CGFloat = isCompact ? 30 : ((!isWide && !isHandsFreeActive) ? 44 : 56)
        let glyphSize: CGFloat = isCompact ? 17 : ((!isWide && !isHandsFreeActive) ? 22 : 28)
        // Keep phone targets large while reserving whole rows above pagination.
        // Accessibility sizes use larger cards and fewer phrases per page.
        // Under hands-free control the tile has to be tall enough to hold a
        // drifting cursor for the whole dwell period, which is a different and
        // larger requirement than being tappable.
        let standardTileMinHeight: CGFloat = isHandsFreeActive
            ? max(tileMinHeight, 140)
            : ((!isWide && !dynamicTypeSize.isAccessibilitySize) ? 72 : tileMinHeight)
        let standardVerticalPadding: CGFloat = isHandsFreeActive
            ? 22
            : ((!isWide && !dynamicTypeSize.isAccessibilitySize) ? 7 : 18)
        let iconBG = store.highContrastEnabled
            ? Color.white.opacity(0.11)
            : (phrase.tint == Phrase.TintKind.forest
                ? Color.white.opacity(0.18)
                : (phrase.tint == Phrase.TintKind.plain ? Palette.forest.opacity(0.08) : Color.white.opacity(0.5)))

        // Stacked icon-over-label reads well in a squarish tile, but wastes most
        // of a full-width one. Switch to side-by-side only when there's a single
        // column, so several phrases still fit on screen.
        let isRow = columnCount == 1
        let tileLayout = isRow
            ? AnyLayout(HStackLayout(spacing: 16))
            : AnyLayout(VStackLayout(spacing: isCompact ? 4 : ((!isWide && !isHandsFreeActive) ? 6 : 10)))

        return Button {
            // In hold-to-speak mode the hold gesture below speaks instead.
            guard !store.holdToSpeak else { return }
            speakFromTouch(phrase)
        } label: {
            tileLayout {
                if showSymbol {
                    ZStack {
                        Circle().fill(iconBG).frame(width: iconSize, height: iconSize)
                            .scaleEffect(speaking && !reduceMotion ? 1.10 : 1)
                        PhraseGlyph(symbol: phrase.symbol, color: phrase.tint.foreground)
                            .frame(width: glyphSize, height: glyphSize)

                        if isGazeHovered && !isCompact {
                            DwellRing(diameter: iconSize + 8)
                        }
                    }
                }
                Text(phrase.label)
                    .font(EchoFont.display(isCompact ? (isWide ? 16 : 15) : (isWide ? 25 : 20), weight: .bold))
                    .foregroundStyle(phrase.tint.foreground)
                    .multilineTextAlignment(isRow ? .leading : .center)
                    // Shrink slightly rather than break a word across lines — a
                    // label split as "Bathroo / m" is far harder to recognise at
                    // a glance than the same word one step smaller.
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .frame(maxWidth: isRow ? .infinity : nil, alignment: isRow ? .leading : .center)
            }
            // Taller tiles on iPad: the extra height fills a screen that would
            // otherwise sit half empty, and makes each target bigger for someone
            // reaching for a mounted device.
            .frame(maxWidth: .infinity, minHeight: isCompact ? (isWide ? 56 : 78) : (isRow ? rowMinHeight : standardTileMinHeight))
            .padding(.horizontal, isCompact ? 5 : (isRow ? 18 : 12))
            .padding(.vertical, isCompact ? 5 : (isRow ? 12 : standardVerticalPadding))
            .background(
                ZStack {
                    if speaking {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Palette.orange)
                            .blur(radius: 12)
                            .opacity(0.6)
                    }
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(phraseGradient(for: phrase))
                }
            )
            // A scaled tile overlaps its neighbours in the tight grid. The
            // border and shadow carry the speaking/hover state without hiding
            // text or making adjacent targets look merged.
            // Lifts off the page while speaking, so the active tile is obvious
            // from across a room.
            .shadow(
                color: speaking ? Palette.orange.opacity(0.45)
                                : Palette.forest.opacity(phrase.tint == Phrase.TintKind.plain ? 0.06 : 0.12),
                radius: speaking ? 18 : 10,
                y: speaking ? 10 : 6
            )
            .animation(reduceMotion ? nil : Motion.pop, value: speaking)
            .animation(reduceMotion ? nil : Motion.snap, value: isGazeHovered)
            .overlay {
                if phrase.tint == Phrase.TintKind.plain && !isGazeHovered {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2)
                }
                if isGazeHovered {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Palette.gazeHighlight, lineWidth: 4)
                }
                if speaking {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Palette.orange, lineWidth: 4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if phrase.hasRecording {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: isCompact ? 12 : 16))
                        .foregroundStyle(
                            store.highContrastEnabled
                                ? Palette.controlAccent
                                : (phrase.tint == Phrase.TintKind.forest ? Palette.lime : Palette.forest)
                        )
                        .background(Circle().fill(.white))
                        .padding(isCompact ? 4 : 8)
                }
            }
        }
        .buttonStyle(Pressable())
        .holdToSpeak(enabled: store.holdToSpeak) { speakFromTouch(phrase) }
        .gazeSelectable(id: gazeID, showsHighlight: false) { speakAndLearn(phrase) }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: QuickTileHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .contextMenu {
            // Hold-to-speak uses the same press, so the menu steps aside; phrases
            // can still be removed from Settings.
            if !store.lockedToBoard && !store.holdToSpeak {
                if store.phrases.first?.id != phrase.id {
                    Button {
                        store.movePhrase(phrase, to: 0)
                    } label: {
                        Label(String(localized: "Move to Top"), systemImage: "arrow.up.to.line")
                    }
                }
                Button(role: .destructive) {
                    store.deletePhrase(phrase)
                } label: {
                    Label(String(localized: "Remove “%@”", defaultValue: "Remove \u{201C}\(String(describing: phrase.label))\u{201D}"), systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phrase.text + (phrase.hasRecording ? String(localized: ", recorded in your own voice") : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(String(localized: "Speaks this phrase aloud"))
        .accessibilityInputLabels([phrase.label, phrase.text])
        // VoiceOver and Switch Control activations are deliberate: skip the tap
        // filter and the hold requirement, which exist for unsteady touches.
        .accessibilityAction(.default) { Haptics.tap(); speakAndLearn(phrase) }
        .accessibilityAction(named: String(localized: "Remove phrase")) {
            if !store.lockedToBoard { store.deletePhrase(phrase) }
        }
    }

    private func phraseGradient(for phrase: Phrase) -> LinearGradient {
        if store.highContrastEnabled {
            let flatColor: Color = switch phrase.tint {
            case .lime: Palette.contrastSage
            case .orange: Palette.contrastAmber
            case .sky: Palette.contrastBlue
            case .lavender: Palette.contrastPlum
            case .rose: Palette.contrastRose
            case .forest: Palette.contrastForest
            case .plain: Palette.surface
            }
            return LinearGradient(colors: [flatColor, flatColor], startPoint: .top, endPoint: .bottom)
        }

        switch phrase.tint {
        case .lime:
            return LinearGradient(colors: [Palette.lime, Palette.lime.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .orange:
            return LinearGradient(colors: [Palette.orange, Palette.orange.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sky:
            return LinearGradient(colors: [Palette.sky, Palette.sky.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lavender:
            return LinearGradient(colors: [Palette.lavender, Palette.lavender.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .rose:
            return LinearGradient(colors: [Palette.rose, Palette.rose.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .forest:
            return LinearGradient(colors: [Palette.forest, Palette.forest.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .plain:
            return LinearGradient(colors: [Palette.surface, Palette.background.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: HELP

    /// The single entry point for calling for help, shared by the HELP button and
    /// the eye-gaze blink trigger. For someone who can't move, the blink is the
    /// *primary* path — it must do exactly what the button does, not less.
    ///
    /// No message is sent anywhere: this app has no backend by design. What it
    /// does is speak, loudly and repeatedly, so a caregiver in the home hears it.
    /// The UI says only that.
    /// Carry out whatever Siri, the Action Button, or a Shortcut asked for.
    ///
    /// Runs here rather than in the intent so the request always happens with
    /// the board visible: an emergency call needs the screen showing the
    /// emergency state for whoever arrives, and any spoken phrase needs a
    /// visible Stop.
    private func performPendingIntent() {
        guard let pending = PendingIntentAction.consume() else { return }
        switch pending.action {
        case .help:
            triggerHelp()
        case .speakPhrase:
            guard let id = pending.phraseID,
                  let phrase = store.phrases.first(where: { $0.id == id })
            else { return }
            boardMode = .quick
            speakAndLearn(phrase)
        }
    }

    private func handleBlinkHelp() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-EchoVoiceLogGaze") { print("ECHOVOICE_GAZE event=boardRaisesHelp onScreen=\(isOnScreen)") }
        #endif
        if showHandsFreeConversation {
            helpAfterConversation = true
            showHandsFreeConversation = false
        } else {
            triggerHelp()
        }
    }

    private func triggerHelp() {
        // Cancel any in-flight call before starting a new one, so a second press
        // never leaves two speech loops overlapping or an old timer alive to
        // dismiss the new alert early.
        helpSpeakTask?.cancel()
        helpDismissTask?.cancel()

        activeAlert = .help

        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif

        helpSpeakTask = Task { @MainActor in
            for repetition in 0..<helpRepetitions {
                if Task.isCancelled { return }
                if repetition > 0 {
                    try? await Task.sleep(for: .milliseconds(700))
                    if Task.isCancelled { return }
                }

                // Waits for the utterance to actually finish. Polling
                // `isSpeaking` here does not work: it is still false right after
                // `speak` returns, so every repetition would fire at once.
                await speaker.speakRawTextAndWait(helpPhrase, rate: store.speechRate, volume: 1.0)
            }
            finishHelpAutomatically()
        }

        // Safety net: if the loop stalls for any reason, the alert still clears.
        helpDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(45))
            if Task.isCancelled { return }
            finishHelpAutomatically()
        }
    }

    /// The repetitions ran out. Close HELP, unless a text to the emergency
    /// contact is mid-compose: then go quiet and leave closing it to the person.
    private func finishHelpAutomatically() {
        guard isTextingContact else { stopHelp(); return }
        helpSpeakTask?.cancel()
        helpSpeakTask = nil
        helpDismissTask?.cancel()
        helpDismissTask = nil
        speaker.stopSpeaking()
    }

    /// Stop speaking and dismiss the help overlay. Safe to call repeatedly.
    private func stopHelp() {
        helpSpeakTask?.cancel()
        helpSpeakTask = nil
        helpDismissTask?.cancel()
        helpDismissTask = nil
        speaker.stopSpeaking()
        if activeAlert == .help { activeAlert = nil }
    }

    // MARK: HELP / I'm Okay

    private var helpRow: some View {
        HStack(spacing: 12) {
            EmergencyHelpButton { triggerHelp() }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .gazeSelectable(id: "emergency-help", kind: .emergency) { triggerHelp() }

            Button {
                recordOkayAndSpeak()
            } label: {
                HStack(spacing: 8) {
                    VectorIconShape(rawPath: EchoIcon.check()).stroke(Palette.cream, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 20, height: 20)
                    Text(String(localized: "I'm Okay")).font(EchoFont.display(20, weight: .extraBold)).foregroundStyle(Palette.cream)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            }
            .background(Palette.forest, in: .rect(cornerRadius: 18))
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .gazeSelectable(id: "status-okay") {
                recordOkayAndSpeak()
            }
            .accessibilityLabel(String(localized: "I'm okay"))
            .accessibilityHint(String(localized: "Records that you're okay"))
        }
        .buttonStyle(Pressable())
    }

    private func recordOkayAndSpeak() {
        guard !showOkayConfirmation else { return }
        guard store.recordOkay() else { return }
        Haptics.tap()
        speaker.speakRawText(String(localized: "I'm okay."), rate: store.speechRate, volume: store.speechVolume)
        showOkayConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            showOkayConfirmation = false
        }
    }

    // MARK: Overlays

    private func speakingToast(_ label: String) -> some View {
        HStack(spacing: 10) {
            // Light bear straight on the toast; no backing disc.
            BearMascotView(mood: .speaking, style: .onDark)
                .scaleEffect(1.55, anchor: UnitPoint(x: 0.5, y: 0.6))
                .frame(width: 60, height: 44)

            Text(String(localized: "Speaking: “%@”", defaultValue: "Speaking: \u{201C}\(String(describing: label))\u{201D}"))
                .font(EchoFont.display(16, weight: .bold))
                .foregroundStyle(Palette.cream)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                speaker.stopSpeaking()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.cream)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .gazeSelectable(id: "speaking-stop") { speaker.stopSpeaking() }
            .accessibilityLabel(String(localized: "Stop speaking"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.forest, in: .rect(cornerRadius: 15))
        .shadow(color: Palette.forest.opacity(0.3), radius: 10, y: 4)
    }

    /// One full-screen confirmation, presented as a modal cover so it sits above
    /// the tab bar. `onStop` is non-nil only for the help alert, which must stay
    /// up (and interruptible) while it repeats.
    @ViewBuilder
    private func alertScreen(
        iconName: String,
        title: String,
        subtitle: String,
        tint: Color,
        onStop: (() -> Void)?
    ) -> some View {
        let details = VStack(spacing: 20) {
            Spacer(minLength: 0)

            Image(systemName: iconName)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
                .padding(24)
                .background(Color.white.opacity(0.18), in: Circle())
                .popIn()

            Text(title)
                .font(EchoFont.display(36, weight: .extraBold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .popIn(delay: 0.06)

            Text(subtitle)
                .font(EchoFont.body(20, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .popIn(delay: 0.11)

            Spacer(minLength: 0)

            // Touch only, not gaze-selectable: iOS asks for a tap to confirm
            // a call and Messages needs a tap on Send, so opening either for
            // someone who can't touch would only cover the Stop they can reach.
            if onStop != nil, let phone = store.emergencyContactPhone {
              // Stacked full width: side by side, a contact's name clipped
              // against the button edge.
              VStack(spacing: 12) {
                if let callURL = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Button {
                        openURL(callURL)
                    } label: {
                        Label(callContactTitle, systemImage: "phone.fill")
                            .font(EchoFont.display(24, weight: .bold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 68)
                            .background(.white, in: .rect(cornerRadius: 20))
                    }
                    .accessibilityHint("Calls your emergency contact")
                }
              if MessageComposer.canSend {
                Button {
                    isTextingContact = true
                } label: {
                    Label("Text", systemImage: "message.fill")
                        .font(EchoFont.display(24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 68)
                        .background(Color.white.opacity(0.22), in: .rect(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 2))
                }
                .accessibilityHint("Opens Messages with a help text ready to send")
                .sheet(isPresented: $isTextingContact) {
                    MessageComposer(
                        recipient: phone,
                        body: "\(helpPhrase) (\(store.boardLanguage == "es" ? "Enviado desde" : "Sent from") EchoVoice)",
                        onFinish: { isTextingContact = false }
                    )
                    .ignoresSafeArea()
                }
              }
              }
            }
        }

        ZStack {
            tint.ignoresSafeArea()

            VStack(spacing: 20) {
                ViewThatFits(in: .vertical) {
                    details
                    ScrollView { details }
                }
                if let onStop {
                    if eyeGaze.isSelectionReady {
                        // A cursor already resting where Stop appears does not
                        // count — a HELP call is never cancelled by accident.
                        Text(String(localized: "To cancel, look at Stop."))
                            .font(EchoFont.body(17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Button(action: onStop) {
                        Text(String(localized: "Stop"))
                            .font(EchoFont.display(26, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 68)
                            .background(Palette.surface, in: .rect(cornerRadius: 20))
                    }
                    .gazeSelectable(id: "help-stop") { onStop() }
                    .accessibilityLabel(String(localized: "Stop calling for help"))
                    .accessibilityHint(String(localized: "Stops speaking and closes this screen"))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
            .readableContentWidth()

            // The alert covers the board's cursor, so it draws its own: someone
            // who cannot touch must still be able to stop a false alarm.
            if eyeGaze.isHandsFreeActive {
                GazeCursorOverlay().ignoresSafeArea()
            }
        }
        .accessibilityAddTraits(.isModal)
        // Any dismissal route must stop the audio, not just the Stop button.
        .onDisappear { speaker.stopSpeaking() }
    }
}

private struct ConversationWorkspaceSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var message: String
    @State private var shortcutQuery = ""
    @State private var showHistory = false
    @State private var selectedSituation = "Appointment"

    private let interjections = [
        (String(localized: "One moment"), "pause.circle.fill"),
        (String(localized: "Please repeat"), "arrow.counterclockwise.circle.fill"),
        (String(localized: "Yes"), "checkmark.circle.fill"),
        (String(localized: "No"), "xmark.circle.fill"),
        (String(localized: "That’s not what I meant"), "arrow.uturn.backward.circle.fill")
    ]

    private var matchedPhrase: Phrase? { store.phrase(matchingShortcut: shortcutQuery) }
    private var cleanedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    draftSection
                    interjectionSection
                    shortcutSection
                    situationSection
                    if !store.conversationHistory.isEmpty { historySection }
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "Conversation Workspace"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Done")) { dismiss() } }
            }
        }
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Draft"), systemImage: "pencil.and.outline")
                    .font(EchoFont.body(18, weight: .bold))
                    .foregroundStyle(Palette.forest)
                Spacer()
                Text(String(localized: "Saved on this device"))
                    .font(EchoFont.body(12, weight: .bold))
                    .foregroundStyle(Palette.muted)
            }

            TextEditor(text: $message)
                .font(EchoFont.body(22, weight: .medium))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 150)
                .background(Palette.background, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.forest.opacity(0.14), lineWidth: 2))
                .accessibilityLabel(String(localized: "Conversation draft"))

            HStack(spacing: 10) {
                Button {
                    message = ""
                    speaker.stopSpeaking()
                } label: {
                    Label(String(localized: "Clear"), systemImage: "xmark")
                        .font(EchoFont.body(16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(Palette.controlAccent)
                .disabled(cleanedMessage.isEmpty)

                Button {
                    speak(message)
                } label: {
                    Label(String(localized: "Speak draft"), systemImage: "speaker.wave.2.fill")
                        .font(EchoFont.body(16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.controlAccent)
                .disabled(cleanedMessage.isEmpty)
            }
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.1), lineWidth: 2))
    }

    private var interjectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Interruptions without losing your thought"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.forest)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(interjections, id: \.0) { item in
                    Button { speak(item.0) } label: {
                        Label(item.0, systemImage: item.1)
                            .font(EchoFont.body(14, weight: .bold))
                            .foregroundStyle(Palette.controlAccent)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .background(Palette.controlAccent.opacity(0.1), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "Speaks this repair phrase and keeps your draft"))
                }
            }
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Personal phrase shortcuts"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.forest)
            TextField(String(localized: "Type a shortcut or phrase label"), text: $shortcutQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(EchoFont.body(17))
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Palette.surface, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2))

            if let matchedPhrase {
                Button {
                    appendPhrase(matchedPhrase.text)
                    shortcutQuery = ""
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "command")
                            .foregroundStyle(Palette.controlAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(matchedPhrase.shortcut.isEmpty ? matchedPhrase.label : matchedPhrase.shortcut)
                                .font(EchoFont.body(14, weight: .bold))
                                .foregroundStyle(Palette.forest)
                            Text(matchedPhrase.text)
                                .font(EchoFont.body(14))
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Palette.controlAccent)
                    }
                    .padding(14)
                    .background(Palette.lime.opacity(0.25), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Add %@ to draft", defaultValue: "Add \(String(describing: matchedPhrase.text)) to draft"))
            } else {
                Text(String(localized: "Create shortcuts from Settings → Manage Phrase Cards. Exact wording stays under your control."))
                    .font(EchoFont.body(13))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private var historySection: some View {
        DisclosureGroup(String(localized: "Recent messages"), isExpanded: $showHistory) {
            VStack(spacing: 8) {
                ForEach(Array(store.conversationHistory.reversed().enumerated()), id: \.offset) { _, item in
                    Button {
                        message = item
                    } label: {
                        Text(item)
                            .font(EchoFont.body(14))
                            .foregroundStyle(Palette.forest)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Palette.background, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                Button(String(localized: "Clear recent messages"), role: .destructive) { store.clearConversationHistory() }
                    .font(EchoFont.body(14, weight: .bold))
            }
            .padding(.top, 8)
        }
        .font(EchoFont.body(17, weight: .bold))
        .foregroundStyle(Palette.forest)
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: 18))
    }

    private var situationSection: some View {
        let phrases: [String]
        switch selectedSituation {
        case "Home care":
            phrases = [String(localized: "Please reposition me."), String(localized: "I need a break."), String(localized: "Please check my position.")]
        case "Family & friends":
            phrases = [String(localized: "I want to tell you something."), String(localized: "Please stay with me."), String(localized: "I love you.")]
        default:
            phrases = [String(localized: "I need more time to answer."), String(localized: "Please explain that again."), String(localized: "I have a question.")]
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Prepare for a situation"))
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.forest)
            Picker(String(localized: "Situation"), selection: $selectedSituation) {
                Text(String(localized: "Appointment")).tag("Appointment")
                Text(String(localized: "Home care")).tag("Home care")
                Text(String(localized: "Family & friends")).tag("Family & friends")
            }
            .pickerStyle(.segmented)
            ForEach(phrases, id: \.self) { phrase in
                Button {
                    appendPhrase(phrase)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(phrase)
                            .font(EchoFont.body(14, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(Palette.controlAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Palette.controlAccent.opacity(0.08), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: 18))
    }

    private func appendPhrase(_ phrase: String) {
        let separator = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " "
        message = message.trimmingCharacters(in: .whitespacesAndNewlines) + separator + phrase
    }

    private func speak(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        Haptics.tap()
        speaker.speakRawText(cleaned, rate: store.speechRate, volume: store.speechVolume)
        store.rememberSpokenMessage(cleaned)
    }
}

// MARK: Helper Animation Views

struct EmergencyHelpButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                EchoIcon.exclaim().fill(.white).frame(width: 20, height: 20)
                Text(String(localized: "HELP"))
                    .font(EchoFont.display(20, weight: .extraBold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Palette.red, in: .rect(cornerRadius: 18))
        }
    }
}

struct EqualizerWaveformView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Palette.lime)
                    .frame(width: 3.5, height: animate ? CGFloat([18, 10, 22, 14][index]) : 6)
                    .animation(
                        Animation.easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

private extension View {
    /// Speaks after a deliberate hold. Attached only when the mode is on, so it
    /// can't slow down scrolling or taps for everyone else.
    func holdToSpeak(enabled: Bool, perform action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            LongPressGesture(minimumDuration: AppStore.holdToSpeakDuration).onEnded { _ in action() },
            including: enabled ? .all : .subviews
        )
    }
}
