import SwiftUI

private struct ConversationTargetFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// A separate surface keeps its dwell targets isolated from the regular board.
struct HandsFreeConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @Environment(EyeGazeManager.self) private var gaze
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .body) private var choiceMinWidth = 220
    @Binding var message: String
    let onHelp: () -> Void

    @State private var scrollBounds: CGRect?
    @State private var scrollRequest = 0
    @State private var scrollAnchor = 0
    @State private var availableHeight: CGFloat = 700
    @State private var availableWidth: CGFloat = 0
    @State private var source = String(localized: "Words")
    @State private var category = "core"
    @State private var page = 0
    @State private var paused = false
    @State private var undo: [String] = []
    @State private var notice = ""
    @State private var frames: [String: CGRect] = [:]
    @State private var dwell = DwellSelector()

    private let sources = [String(localized: "Words"), String(localized: "Phrases"), String(localized: "Spell"), String(localized: "Replies")]
    private let replies = [String(localized: "Yes"), String(localized: "No"), String(localized: "Give me a moment."), String(localized: "Please repeat that."), String(localized: "That's not what I meant."), String(localized: "I need a break.")]
    /// Choices per page from the height available. The old thresholds gave an
    /// iPhone 17 four choices and a blank third of the screen.
    private var pageSize: Int {
        if sizeClass == .regular && !typeSize.isAccessibilitySize {
            let rows = max(1, Int((availableHeight - 520) / (96 + choiceSpacing)))
            return columnCount * min(rows, 4)
        }
        if typeSize.isAccessibilitySize || availableHeight < 680 { return columnCount }
        if availableHeight < 740 { return columnCount * 2 }
        return columnCount * (availableHeight < 840 ? 3 : 4)
    }
    private var columnCount: Int {
        sizeClass == .regular ? BoardLayout.columnCount(width: gridWidth, minimum: choiceMinWidth, spacing: choiceSpacing) : 2
    }
    private var choiceSpacing: CGFloat { sizeClass == .regular ? 20 : 10 }
    private var gridWidth: CGFloat { max(1, min(availableWidth, 1100) - 24) }
    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.adaptive(minimum: min(gridWidth, choiceMinWidth)), spacing: choiceSpacing)]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }
    private var choices: [String] {
        switch source {
        case String(localized: "Phrases"): return store.phrases.map(\.text)
        case String(localized: "Spell"): return Array(AppLanguage.isSpanish ? "ABCDEFGHIJKLMNÑOPQRSTUVWXYZÁÉÍÓÚÜ" : "ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + [String(localized: "Space"), ".", ",", "?", "!", String(localized: "Backspace")]
        case String(localized: "Replies"): return replies
        default: return (AACVocabulary.categories.first { $0.id == category } ?? AACVocabulary.categories[0]).words
        }
    }
    private var pageCount: Int { max(1, (choices.count + pageSize - 1) / pageSize) }
    private var pageIndices: Range<Int> {
        let start = min(page, pageCount - 1) * pageSize
        return start..<min(start + pageSize, choices.count)
    }
    private var tracking: Bool { gaze.isHandsFreeActive && gaze.isFaceTracked }
    private var cleaned: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var status: String {
        if gaze.isEmergencyBlinkArmed { return String(localized: "HELP ready. Hold your eyes closed for 2 seconds to confirm.") }
        if !notice.isEmpty { return notice }
        if paused { return String(localized: "Selection paused. Look at Resume to continue.") }
        if !gaze.isHandsFreeActive { return String(localized: "Touch works here too. Turn on hands-free control in Settings to use gaze.") }
        if gaze.needsCalibration { return String(localized: "Head control needs its short setup (Settings) before it can select. Touch works now.") }
        if !gaze.isFaceTracked { return String(localized: "Can't see your face. Move back into the camera's view.") }
        return source == String(localized: "Replies") ? String(localized: "Replies speak immediately and keep your draft.") : String(localized: "Look to compose. Select Speak when ready.")
    }

    var body: some View {
        GeometryReader { geometry in
            ViewThatFits(in: .vertical) {
                screenContent
                ScrollViewReader { proxy in
                    VStack(spacing: 4) {
                        ScrollView { screenContent }
                            .background(GeometryReader { viewport in
                                Color.clear
                                    .onAppear { scrollBounds = viewport.frame(in: .global) }
                                    .onChange(of: viewport.frame(in: .global)) { _, rect in scrollBounds = rect }
                                    .onDisappear { scrollBounds = nil }
                            })
                        HStack {
                            control(String(localized: "Scroll up"), id: "scroll-up")
                            control(String(localized: "Scroll down"), id: "scroll-down")
                        }
                        .padding(8)
                    }
                    .onChange(of: scrollRequest) { _, _ in
                        proxy.scrollTo(scrollAnchor, anchor: .top)
                    }
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                availableHeight = size.height
                availableWidth = size.width
                dwell.reset(time: ProcessInfo.processInfo.systemUptime)
                gaze.resetDwell()
            }
            .overlay(alignment: .topLeading) {
                if tracking {
                    ZStack {
                        Circle().fill(Palette.gazeHighlight.opacity(0.3))
                        Circle().trim(from: 0, to: dwell.progress).stroke(Palette.controlAccent, lineWidth: 4)
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 30, height: 30)
                    .position(x: gaze.cursorPosition.x - geometry.frame(in: .global).minX,
                              y: gaze.cursorPosition.y - geometry.frame(in: .global).minY)
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
        .onPreferenceChange(ConversationTargetFrames.self) { newFrames in
            if frames != newFrames { dwell.reset(time: ProcessInfo.processInfo.systemUptime) }
            frames = newFrames
        }
        .onChange(of: message) { _, value in store.draftMessage = value }
        .onChange(of: pageSize) { _, _ in page = 0; dwell.reset(time: ProcessInfo.processInfo.systemUptime) }
        .task {
            gaze.resetDwell()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { break }
                tickDwell()
            }
        }
        .onDisappear { gaze.resetDwell(); speaker.stopSpeaking() }
    }

    private var screenContent: some View {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    BearMascotView(mood: speaker.isSpeaking ? .speaking : .idle, animated: false)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    Text(String(localized: "Conversation")).font(EchoFont.body(20, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                    Spacer()
                    control(String(localized: "Close"), id: "close")
                    control(paused ? String(localized: "Resume") : String(localized: "Pause"), id: "pause")
                }
                .id(0)
                Text(status).font(EchoFont.body(14)).frame(maxWidth: .infinity, alignment: .leading)
                Text(message.isEmpty ? String(localized: "Your message appears here") : message)
                    .font(EchoFont.body(24, weight: .medium))
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 3)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(12).background(Palette.surface, in: .rect(cornerRadius: 16))
                    .accessibilityLabel(String(localized: "Draft: %@", defaultValue: "Draft: \(String(describing: message))"))

                HStack(spacing: 8) {
                    control(String(localized: "Undo"), id: "undo", enabled: !undo.isEmpty)
                    control(String(localized: "Clear"), id: "clear", enabled: !message.isEmpty)
                    control(String(localized: "Save"), id: "save", enabled: !cleaned.isEmpty)
                }
                HStack(spacing: 8) {
                    control(String(localized: "Speak"), id: "speak", enabled: !cleaned.isEmpty, prominent: true)
                    control(String(localized: "Stop voice"), id: "stop")
                    control(String(localized: "Help"), id: "help")
                }
                .id(1)
                HStack(spacing: 8) {
                    ForEach(sources, id: \.self) { item in
                        control(item, id: "source-\(item)", prominent: source == item)
                    }
                }
                if source == String(localized: "Words") {
                    HStack {
                        control(String(localized: "Previous topic"), id: "topic-prev")
                        Text(AACVocabulary.categories.first { $0.id == category }?.title ?? String(localized: "Core"))
                            .font(EchoFont.body(14, weight: .bold)).frame(maxWidth: .infinity)
                        control(String(localized: "Next topic"), id: "topic-next")
                    }
                }
                LazyVGrid(columns: columns, spacing: choiceSpacing) {
                    ForEach(Array(pageIndices), id: \.self) { index in
                        control(choices[index], id: "choice-\(source)-\(category)-\(index)", minHeight: sizeClass == .regular ? 96 : 60)
                    }
                }
                .id(2)
                Spacer(minLength: 0)
                HStack {
                    control(String(localized: "Previous"), id: "prev", enabled: page > 0)
                    Text("\(min(page + 1, pageCount)) / \(pageCount)").font(EchoFont.body(14)).frame(maxWidth: .infinity)
                    control(String(localized: "Next"), id: "next", enabled: page + 1 < pageCount)
                }
                .id(3)
            }
            .padding(12)
            .readableContentWidth(1100)
            .foregroundStyle(Palette.primaryText)
            .background(Palette.background.ignoresSafeArea())
    }

    /// The same selector the board uses: snapping, hysteresis, pausing on
    /// blinks, one selection per visit, and a longer dwell for Help.
    private func tickDwell() {
        let now = ProcessInfo.processInfo.systemUptime
        let active = gaze.isSelectionReady && scenePhase == .active
        let targets: [DwellTarget] = active ? frames.compactMap { id, frame in
            let visible = id.hasPrefix("scroll-") ? frame : frame.intersection(scrollBounds ?? frame)
            guard !visible.isNull, visible.width > 1, visible.height > 1 else { return nil }
            return DwellTarget(id: id, frame: visible, kind: id == "help" ? .emergency : .standard)
        } : []
        let state: GazeTrackingState = active ? gaze.selectionState : .lost
        let cursor: CGPoint? = state == .lost ? nil : gaze.cursorPosition
        if let selected = dwell.update(cursor: cursor, state: state, targets: targets, time: now, dwellDuration: gaze.dwellDuration) {
            perform(selected)
        }
    }

    private func control(_ title: String, id: String, enabled: Bool = true, prominent: Bool = false, minHeight: CGFloat = 48) -> some View {
        let available = enabled && (!paused || ["pause", "close", "stop", "help"].contains(id))
        return Button { perform(id) } label: {
            Text(title).font(EchoFont.body(16, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .padding(.horizontal, 4)
                .foregroundStyle(prominent ? Palette.onControlAccent : Palette.controlAccent)
                .background(prominent ? Palette.controlAccent : Palette.surface, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(dwell.hoveredID == id ? Palette.gazeHighlight : .clear, lineWidth: 3))
                .opacity(available ? 1 : 0.4)
        }
        .buttonStyle(.plain).disabled(!available)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ConversationTargetFrames.self, value: available ? [id: geometry.frame(in: .global)] : [:])
        })
    }

    private func edit(_ value: String) {
        guard value != message else { return }
        undo = Array((undo + [message]).suffix(50))
        message = value
    }
    private func speak(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let phrase = store.phrases.first(where: { $0.text == value }) {
            speaker.speak(phrase, rate: store.speechRate, volume: store.speechVolume)
        } else {
            speaker.speakRawText(value, rate: store.speechRate, volume: store.speechVolume)
        }
        store.rememberSpokenMessage(value)
    }
    private func perform(_ id: String) {
        guard !paused || ["pause", "close", "stop", "help"].contains(id) else { return }
        notice = ""
        switch id {
        case "scroll-up": scrollAnchor = max(0, scrollAnchor - 1); scrollRequest += 1
        case "scroll-down": scrollAnchor = min(3, scrollAnchor + 1); scrollRequest += 1
        case "close": dismiss()
        case "pause": paused.toggle()
        case "stop": speaker.stopSpeaking()
        case "help": onHelp()
        case "undo": if let previous = undo.popLast() { message = previous }
        case "clear": edit("")
        case "speak": speak(message)
        case "save":
            guard !cleaned.isEmpty else { return }
            if store.phrases.contains(where: { $0.text == cleaned }) { notice = String(localized: "This phrase is already saved.") }
            else { notice = store.addPhrase(Phrase(label: String(cleaned.prefix(40)), text: cleaned)) ? String(localized: "Phrase saved.") : String(localized: "Couldn't save. Your draft is still here.") }
        case "prev": page = max(0, page - 1)
        case "next": page = min(pageCount - 1, page + 1)
        case "topic-prev", "topic-next":
            let categories = AACVocabulary.categories
            let current = categories.firstIndex { $0.id == category } ?? 0
            category = categories[(current + (id == "topic-next" ? 1 : categories.count - 1)) % categories.count].id
            page = 0
        default:
            if id.hasPrefix("source-") { source = String(id.dropFirst(7)); page = 0 }
            else if id.hasPrefix("choice-"), let index = Int(id.split(separator: "-").last ?? ""), choices.indices.contains(index) {
                let word = choices[index]
                if source == String(localized: "Replies") { speak(word) }
                else if source == String(localized: "Spell") {
                    if word == String(localized: "Backspace") { edit(String(message.dropLast())) }
                    else { edit(message + (word == String(localized: "Space") ? " " : word.lowercased())) }
                } else {
                    edit(cleaned + (cleaned.isEmpty || [".", ",", "?", "!"].contains(word) ? "" : " ") + word)
                }
            }
        }
    }
}
