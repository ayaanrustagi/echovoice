import SwiftUI

/// Listen mode: shows what the conversation partner just said and offers
/// one-selection replies to it.
///
/// A separate screen rather than a strip on the board, for the same reason as
/// the hands-free conversation surface: a caption that appears and disappears
/// above the board would move every tile while someone is aiming at one.
struct PartnerListenView: View {
    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .body) private var replyMinWidth = 220

    let onHelp: () -> Void

    @State private var listener = PartnerListener()
    @State private var result: PartnerReplySuggester.Result?
    @State private var timeline = ConversationTimeline()
    /// Counts partner turns, so model replies for an older turn are dropped.
    @State private var turn = 0
    @State private var smartCount = 0
    /// Model replies still being written for this turn; each holds a tile.
    @State private var smartPending = 0
    @State private var drafter = SmartReplyDrafter()
    @State private var drafting: Task<Void, Never>?

    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.adaptive(minimum: replyMinWidth), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statusLine
                    heardCard
                    if let result, !result.replies.isEmpty || smartPending > 0 {
                        reasonLine(result)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(result.replies.enumerated()), id: \.element) { index, reply in
                                replyButton(reply, index: index)
                            }
                            ForEach(0..<smartPending, id: \.self) { _ in
                                ThinkingTile()
                            }
                        }
                    }
                    bottomControls
                    if !timeline.entries.isEmpty {
                        timelineSection
                    }
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            if eyeGaze.isHandsFreeActive {
                GazeCursorOverlay().ignoresSafeArea()
            }
        }
        // This screen covers the board, whose controls drop out of dwell
        // selection while it is up. Its own controls have to opt back in.
        .environment(\.gazeSelectionEnabled, true)
        .foregroundStyle(Palette.primaryText)
        .task {
            listener.onTurn = { heard in
                timeline.append(.partner, heard)
                let rules = PartnerReplySuggester.suggest(heard: heard, candidates: candidates)
                result = rules
                smartCount = 0
                turn += 1
                eyeGaze.resetDwell()
                addSmartReplies(to: heard, turn: turn, shown: rules.replies)
            }
            listener.onRoomReading = { speaker.roomReading = $0 }
            drafter.prepare()
            speaker.keepsMicrophoneOpen = true
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-EchoVoiceListenSample"), args.indices.contains(i + 1) {
                listener.simulateTurn(args[i + 1])
                return  // layout check only: leave the microphone off
            }
            #endif
            await listener.start()
        }
        .onChange(of: speaker.isSpeaking) { _, speaking in listener.setSuppressed(speaking) }
        .onChange(of: scenePhase) { _, phase in
            // The microphone is only ever on while this screen is in front.
            // `.inactive` is not "left": permission prompts, Control Center,
            // and the notification shade all pass through it, and stopping
            // there would cancel the very start that raised the prompt.
            if phase == .background {
                listener.stop()
            } else if phase == .active, listener.state == .idle {
                Task { await listener.start() }
            }
        }
        .onDisappear {
            drafting?.cancel()
            listener.stop()
            speaker.keepsMicrophoneOpen = false
        }
    }

    private var candidates: [PartnerReplySuggester.Candidate] {
        store.phrases.map { .init(id: $0.id, label: $0.label, text: $0.text) }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            BearMascotView(mood: listenMood)
                .frame(width: 60, height: 60)
                .padding(.vertical, -8)    // keep the header row its original height
            // One line always: with Help and Close beside it, large text sizes
            // broke the word itself ("Liste / n"). Shrink before wrapping.
            Text(String(localized: "Listen"))
                .font(EchoFont.display(28, weight: .extraBold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer()
            // The board raises HELP once this screen has closed; presenting the
            // alert from under a closing cover would drop it.
            control(String(localized: "Help"), id: "listen-help", kind: .emergency, tint: Palette.red) { onHelp() }
            control(String(localized: "Close"), id: "listen-close") { dismiss() }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(statusText)
                .font(EchoFont.body(14, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var listenMood: BearMascotView.Mood {
        if speaker.isSpeaking { return .speaking }
        if case .listening = listener.state { return .listening }
        return .idle
    }

    private var statusColor: Color {
        switch listener.state {
        case .listening: return speaker.isSpeaking ? Palette.orange : Palette.lime
        case .idle: return Palette.faint
        case .unavailable: return Palette.red
        }
    }

    private var statusText: String {
        switch listener.state {
        case .listening:
            return speaker.isSpeaking
                ? String(localized: "Paused while EchoVoice speaks.")
                : String(localized: "Listening on this device. Nothing is recorded or sent anywhere.")
        case .idle: return String(localized: "Not listening.")
        case .unavailable(let reason): return reason
        }
    }

    private var heardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "They said"))
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.secondaryText)
                .textCase(.uppercase)
            Group {
                if !listener.liveText.isEmpty {
                    Text(listener.liveText).foregroundStyle(Palette.secondaryText)
                } else if let heard = listener.lastHeard {
                    Text(heard)
                } else {
                    Text(String(localized: "Ask a question and replies will appear here."))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .font(EchoFont.display(26, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: listener.liveText)
        }
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func reasonLine(_ result: PartnerReplySuggester.Result) -> some View {
        var parts: [String] = []
        switch result.kind {
        case .yesNo: parts.append(String(localized: "Yes/no question"))
        case .choice(let options): parts.append(String(localized: "Choice: %@", defaultValue: "Choice: \(String(describing: options.joined(separator: String(localized: " or "))))"))
        case .question: parts.append(String(localized: "Question"))
        case .statement: parts.append(String(localized: "Statement"))
        case .nothing: break
        }
        if !result.matchedWords.isEmpty {
            parts.append(String(localized: "matches your board: %@", defaultValue: "matches your board: \(String(describing: result.matchedWords.joined(separator: ", ")))"))
        }
        if smartCount > 0 {
            parts.append(smartCount == 1 ? String(localized: "smartReply.one")
                : String(localized: "smartReply.many", defaultValue: "\(String(smartCount)) on-device suggestions"))
        }
        return Text(parts.joined(separator: " · "))
            .font(EchoFont.body(13, weight: .semibold))
            .foregroundStyle(Palette.secondaryText)
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            if case .listening = listener.state {
                control(String(localized: "Clear"), id: "listen-clear") {
                    listener.clearHeard()
                    drafting?.cancel()
                    smartPending = 0
                    result = nil
                    timeline.clear()
                }
            } else if listener.state == .idle {
                control(String(localized: "Start listening"), id: "listen-start") { Task { await listener.start() } }
            }
            control(String(localized: "Stop voice"), id: "listen-stop-voice") { speaker.stopSpeaking() }
        }
        .padding(.top, 4)
    }

    /// Recent turns, oldest first, so the thread is easy to pick back up.
    /// Below the replies, so it never moves them.
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Conversation"))
                .font(EchoFont.body(13, weight: .bold))
                .foregroundStyle(Palette.secondaryText)
                .textCase(.uppercase)
            ForEach(timeline.entries.suffix(8)) { entry in
                let mine = entry.speaker == .me
                HStack {
                    if mine { Spacer(minLength: 40) }
                    VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                        Text(mine ? String(localized: "You") : String(localized: "They"))
                            .font(EchoFont.body(11, weight: .bold))
                            .foregroundStyle(Palette.secondaryText)
                        Text(entry.text)
                            .font(EchoFont.body(16, weight: .medium))
                            .multilineTextAlignment(mine ? .trailing : .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(mine ? Palette.lime.opacity(0.35) : Palette.surface, in: .rect(cornerRadius: 14))
                    if !mine { Spacer(minLength: 40) }
                }
                .accessibilityElement(children: .combine)
            }
            Text(String(localized: "Kept only while Listen is open."))
                .font(EchoFont.body(12))
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.top, 8)
    }

    // MARK: Controls

    private func replyButton(_ reply: PartnerReplySuggester.Reply, index: Int) -> some View {
        let title = label(for: reply)
        let banked = phrase(for: reply)?.audioFileName != nil
        return Button { speak(reply) } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(EchoFont.display(22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                if banked {
                    Label(String(localized: "Your voice"), systemImage: "waveform")
                        .font(EchoFont.body(12, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(10)
            .background(index < 2 ? Palette.lime.opacity(0.35) : Palette.surface, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.controlAccent.opacity(0.15), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .gazeSelectable(id: "listen-reply-\(index)-\(title)") { speak(reply) }
        .accessibilityLabel(banked ? String(localized: "%@, in your recorded voice", defaultValue: "\(String(describing: title)), in your recorded voice") : title)
    }

    private func control(
        _ title: String, id: String, kind: DwellTarget.Kind = .standard,
        tint: Color = Palette.controlAccent, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(EchoFont.body(16, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 16)
                .frame(minWidth: 64, minHeight: 48)
                .background(Palette.surface, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .gazeSelectable(id: id, kind: kind, action: action)
    }

    // MARK: Speaking

    private func phrase(for reply: PartnerReplySuggester.Reply) -> Phrase? {
        guard case .phrase(let id) = reply else { return nil }
        return store.phrases.first { $0.id == id }
    }

    /// Appends on-device model replies after the rule-based ones, one by one as
    /// each is written. Appended, never inserted: a tile someone is already
    /// aiming at must not move. Each reply lands in a "Thinking" tile's slot.
    private func addSmartReplies(to heard: String, turn requested: Int, shown: [PartnerReplySuggester.Reply]) {
        drafting?.cancel()
        guard SmartReplies.isAvailable else {
            smartPending = 0
            return
        }
        let conversation = timeline.entries.map { ($0.speaker == .partner ? String(localized: "They: ") : String(localized: "Me: ")) + $0.text }
        let existing = shown.map { phrase(for: $0)?.text ?? label(for: $0) }
        smartPending = Self.smartSlots
        drafting = Task {
            await drafter.draft(to: heard, conversation: conversation, existing: existing) { reply in
                guard requested == turn, var current = result else { return }
                current.replies.append(.text(reply))
                result = current
                smartCount += 1
                smartPending = max(0, smartPending - 1)
            }
            if requested == turn { smartPending = 0 }
        }
    }

    private static let smartSlots = 3

    private func label(for reply: PartnerReplySuggester.Reply) -> String {
        switch reply {
        case .phrase: return phrase(for: reply)?.label ?? ""
        case .text(let text): return text
        }
    }

    private func speak(_ reply: PartnerReplySuggester.Reply) {
        // What was actually said, not the tile's short label.
        timeline.append(.me, phrase(for: reply)?.text ?? label(for: reply))
        if let phrase = phrase(for: reply) {
            store.recordPhraseUse(phrase)
            store.rememberSpokenMessage(phrase.text)
            speaker.speak(phrase, rate: store.speechRate, volume: store.speechVolume)
        } else if case .text(let text) = reply {
            store.rememberSpokenMessage(text)
            speaker.speakRawText(text, rate: store.speechRate, volume: store.speechVolume)
        }
    }
}

/// Holds the slot of a model reply that is still being written.
private struct ThinkingTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(String(localized: "Thinking…"))
                .font(EchoFont.body(16, weight: .semibold))
        }
        .foregroundStyle(Palette.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(10)
        .background(Palette.surface, in: .rect(cornerRadius: 18))
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityLabel(String(localized: "Writing more replies"))
    }
}
