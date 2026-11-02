import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct VoiceBankView: View {
    @Environment(AppStore.self) private var store
    @Environment(Speaker.self) private var speaker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var audioPlayer: AVAudioPlayer?
    @State private var playingPhraseID: UUID?

    @State private var showFileImporter = false
    @State private var statusMessage: String?

    @State private var recordingStudioPhrase: Phrase?
    /// A banked recording may be impossible to make again, so deleting one asks first.
    @State private var recordingToDelete: Phrase?
    @State private var showVoiceOptions = false
    @State private var phrasePage = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var recordingMinWidth = 320

    private var recordingColumns: [GridItem] {
        horizontalSizeClass == .regular
            ? [GridItem(.adaptive(minimum: recordingMinWidth), spacing: 14, alignment: .top)]
            : [GridItem(.flexible())]
    }

    /// The list scrolls, so a page can hold more than fits at once; two per
    /// page left half of a phone blank and six pages to step through.
    private var phrasesPerPage: Int {
        if dynamicTypeSize.isAccessibilitySize { return 2 }
        return horizontalSizeClass == .regular ? 6 : 4
    }
    private var phrasePageCount: Int {
        max(1, Int(ceil(Double(store.phrases.count) / Double(phrasesPerPage))))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if BankingUrgency.evaluate(checkins: store.checkins, phrases: store.phrases).isEmphasized {
                        bankingPromptCard
                    }
                    DisclosureGroup(isExpanded: $showVoiceOptions) {
                        VStack(spacing: 18) {
                            personalVoiceSection
                            exportImportCard
                        }
                        .padding(.top, 14)
                        .readableContentWidth()
                    } label: {
                        Text(String(localized: "Voice options"))
                            .font(EchoFont.body(16, weight: .bold))
                            .foregroundStyle(Palette.primaryText)
                    }
                    .tint(Palette.controlAccent)
                    .padding(16)
                    .background(Palette.surface, in: .rect(cornerRadius: 18))
                    phrasesRecordingSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .readableContentWidth(1000)
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "Your Voice"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(item: $recordingStudioPhrase) { phrase in
                RecordPhraseStudioSheet(phrase: phrase)
            }
            .confirmationDialog(
                String(localized: "Delete this recording?"),
                isPresented: Binding(get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } }),
                titleVisibility: .visible,
                presenting: recordingToDelete
            ) { phrase in
                Button(String(localized: "Delete Recording"), role: .destructive) {
                    store.deleteBankedRecording(for: phrase)
                    recordingToDelete = nil
                }
                Button(String(localized: "Keep It"), role: .cancel) { recordingToDelete = nil }
            } message: { phrase in
                Text(String(localized: "“%@” will go back to the computer voice. You can undo this for 10 seconds.", defaultValue: "\u{201C}\(String(describing: phrase.label))\u{201D} will go back to the computer voice. You can undo this for 10 seconds."))
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .onChange(of: store.phrases.count) {
                phrasePage = min(phrasePage, phrasePageCount - 1)
            }
            .onChange(of: phrasesPerPage) {
                phrasePage = min(phrasePage, phrasePageCount - 1)
            }
        }
    }

    // MARK: Banking Prompt
    //
    // The journal and the bank talk to each other here: the trend in the person's
    // own readings decides how this card is framed and which phrases it surfaces.

    private var bankingPromptCard: some View {
        let recommendation = BankingUrgency.evaluate(checkins: store.checkins, phrases: store.phrases)
        let emphasized = recommendation.isEmphasized

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(emphasized ? Palette.orange.opacity(0.22) : Palette.lime.opacity(0.3))
                        .frame(width: 42, height: 42)
                    Image(systemName: recommendation.hasUnbanked
                          ? (emphasized ? "waveform.badge.exclamationmark" : "waveform.badge.mic")
                          : "checkmark.seal.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(emphasized ? Palette.orange : Palette.forest)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(EchoFont.body(17, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recommendation.detail)
                        .font(EchoFont.body(14))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if recommendation.hasUnbanked {
                // Up to three concrete next actions — a list of everything unbanked
                // reads as a chore, three reads as a doable afternoon.
                VStack(spacing: 8) {
                    ForEach(recommendation.unbankedPhrases.prefix(3)) { phrase in
                        Button {
                            recordingStudioPhrase = phrase
                        } label: {
                            HStack(spacing: 10) {
                                PhraseGlyph(symbol: phrase.symbol, color: Palette.forest)
                                    .frame(width: 20, height: 20)
                                Text(phrase.label)
                                    .font(EchoFont.body(15, weight: .bold))
                                    .foregroundStyle(Palette.forest)
                                Spacer(minLength: 8)
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(String(localized: "Record"))
                                    .font(EchoFont.body(14, weight: .bold))
                            }
                            .foregroundStyle(Palette.forest)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(emphasized ? Palette.orange.opacity(0.14) : Palette.forest.opacity(0.06),
                                        in: .rect(cornerRadius: 14))
                        }
                        .accessibilityLabel(String(localized: "Record %@ in your own voice", defaultValue: "Record \(String(describing: phrase.label)) in your own voice"))
                    }

                    if recommendation.unbankedPhrases.count > 3 {
                        Text(String(localized: "+ %@ more below", defaultValue: "+ \(String(describing: recommendation.unbankedPhrases.count - 3)) more below"))
                            .font(EchoFont.body(13))
                            .foregroundStyle(Palette.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(emphasized ? Palette.orange.opacity(0.55) : Palette.forest.opacity(0.08),
                              lineWidth: emphasized ? 2.5 : 2)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: Personal Voice Status

    private var personalVoiceSection: some View {
        PersonalVoiceSetupCard()
    }

    // MARK: Progress Ring

    private var progressRingCard: some View {
        let count = store.bankedCount
        let target = store.phrases.count
        let progress = target == 0 ? 0 : min(Double(count) / Double(target), 1.0)

        return HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Palette.forest.opacity(0.12), lineWidth: 10)
                    .frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Palette.lime, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(EchoFont.display(22, weight: .extraBold))
                        .foregroundStyle(Palette.forest)
                    Text(String(localized: "of %@", defaultValue: "of \(String(describing: target))"))
                        .font(EchoFont.body(11))
                        .foregroundStyle(Palette.muted)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Phrases Banked in Your Voice"))
                    .font(EchoFont.body(17, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(count > 0 ? String(localized: "%@ custom phrases recorded.", defaultValue: "\(String(describing: count)) custom phrases recorded.") : String(localized: "Tap record on any phrase below to record in your real voice."))
                    .font(EchoFont.body(14))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    // MARK: Export / Import Card

    private var exportImportCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Backup & Transfer"))
                        .font(EchoFont.body(17, weight: .bold))
                        .foregroundStyle(Palette.forest)
                    Text(String(localized: "Export your voice recordings to keep forever."))
                        .font(EchoFont.body(14))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
            }

            VStack(spacing: 12) {
                Button {
                    exportBank()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(String(localized: "Export Backup"))
                    }
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.cream)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.forest, in: .rect(cornerRadius: 16))
                }

                Button {
                    shareKeepsake()
                } label: {
                    HStack {
                        Image(systemName: "heart.text.square")
                        Text(String(localized: "Share as Audio Files"))
                    }
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.forest)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.lime.opacity(0.35), in: .rect(cornerRadius: 16))
                }
                .accessibilityHint(String(localized: "Shares each recording as an ordinary audio file named after its phrase, to keep anywhere"))

                Button {
                    showFileImporter = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text(String(localized: "Import"))
                    }
                    .font(EchoFont.body(15, weight: .bold))
                    .foregroundStyle(Palette.forest)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.forest.opacity(0.1), in: .rect(cornerRadius: 16))
                }
            }

            if let msg = statusMessage {
                Text(msg)
                    .font(EchoFont.body(13, weight: .bold))
                    .foregroundStyle(Palette.forest)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 2))
    }

    // MARK: Phrase Recording List

    private var phrasesRecordingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                BearMascotView(mood: .listening)
                    .frame(width: 56, height: 56)
                    .padding(.vertical, -6)
                Text(String(localized: "Record a phrase"))
                    .font(EchoFont.body(19, weight: .bold))
                    .foregroundStyle(Palette.forest)
            }
            Text(String(localized: "%@ of %@ saved in your voice", defaultValue: "\(String(describing: store.bankedCount)) of \(String(describing: store.phrases.count)) saved in your voice"))
                .font(EchoFont.body(14))
                .foregroundStyle(Palette.muted)

            LazyVGrid(columns: recordingColumns, alignment: .leading, spacing: 14) {
                ForEach(Array(store.phrases.dropFirst(phrasePage * phrasesPerPage).prefix(phrasesPerPage))) { phrase in
                    phraseRecordingRow(phrase: phrase)
                }
            }
            if phrasePageCount > 1 {
                HStack(spacing: 12) {
                    Button {
                        phrasePage = max(0, phrasePage - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 52, height: 52)
                    }
                    .disabled(phrasePage == 0)
                    .accessibilityLabel(String(localized: "Previous phrases"))

                    Spacer(minLength: 0)
                    Text(String(localized: "Page %@ of %@", defaultValue: "Page \(String(describing: phrasePage + 1)) of \(String(describing: phrasePageCount))"))
                        .font(EchoFont.body(14, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                    Spacer(minLength: 0)

                    Button {
                        phrasePage = min(phrasePageCount - 1, phrasePage + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 52, height: 52)
                    }
                    .disabled(phrasePage == phrasePageCount - 1)
                    .accessibilityLabel(String(localized: "Next phrases"))
                }
                .foregroundStyle(Palette.controlAccent)
                .buttonStyle(.plain)
            }
        }
    }

    private func phraseRecordingRow(phrase: Phrase) -> some View {
        let isPlaying = playingPhraseID == phrase.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(phrase.tint == Phrase.TintKind.forest ? Palette.forest : Palette.lime.opacity(0.3))
                        .frame(width: 44, height: 44)
                    PhraseGlyph(symbol: phrase.symbol, color: phrase.tint == Phrase.TintKind.forest ? Palette.cream : Palette.forest)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(phrase.label)
                        .font(EchoFont.body(17, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\u{201C}\(phrase.text)\u{201D}")
                        .font(EchoFont.body(14))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if phrase.hasRecording {
                    Button {
                        playRecording(for: phrase)
                    } label: {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 14))
                            .frame(width: 44, height: 44)
                            .background(Palette.forest.opacity(0.1), in: Circle())
                            .foregroundStyle(Palette.forest)
                    }
                    .accessibilityLabel(isPlaying ? String(localized: "Stop recording") : String(localized: "Play recording"))

                    Button {
                        recordingStudioPhrase = phrase
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14))
                            .frame(width: 44, height: 44)
                            .background(Palette.lime, in: Circle())
                            .foregroundStyle(Palette.forest)
                    }
                    .accessibilityLabel(String(localized: "Record again"))

                    Button {
                        recordingToDelete = phrase
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .frame(width: 44, height: 44)
                            .background(Palette.red.opacity(0.1), in: Circle())
                            .foregroundStyle(Palette.red)
                    }
                    .accessibilityLabel(String(localized: "Delete recording"))
                } else {
                    Button {
                        recordingStudioPhrase = phrase
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                            Text(String(localized: "Record"))
                                .font(EchoFont.body(14, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Palette.forest, in: .rect(cornerRadius: 14))
                        .foregroundStyle(Palette.cream)
                    }
                }
            }
        }
        .padding(14)
        .background(Palette.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.forest.opacity(0.08), lineWidth: 1.5))
    }

    private func playRecording(for phrase: Phrase) {
        if playingPhraseID == phrase.id {
            audioPlayer?.stop()
            playingPhraseID = nil
            return
        }

        if let fn = phrase.audioFileName {
            let url = AudioFileManager.getURL(for: fn)
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                playingPhraseID = phrase.id
            } catch {
                statusMessage = String(localized: "Couldn't play recording.")
            }
        }
    }

    private func exportBank() {
        guard let archive = AudioFileManager.createExportPackage(phrases: store.phrases) else {
            statusMessage = store.bankedCount == 0
                ? String(localized: "Add at least one phrase before exporting.")
                : String(localized: "Couldn't build the export file.")
            return
        }
        SharePresenter.present([archive])
    }

    /// Each recording as "Phrase label.m4a", so a family can keep the voice
    /// without needing EchoVoice to open it. See `VoiceKeepsake`.
    private func shareKeepsake() {
        let items = store.phrases.compactMap { phrase -> VoiceKeepsake.Item? in
            guard let fileName = phrase.audioFileName else { return nil }
            return VoiceKeepsake.Item(label: phrase.label, source: AudioFileManager.getURL(for: fileName))
        }
        guard !items.isEmpty else {
            statusMessage = String(localized: "Record at least one phrase first.")
            return
        }
        do {
            let files = try VoiceKeepsake.prepare(items)
            guard !files.isEmpty else {
                statusMessage = String(localized: "Couldn't find those recordings on this device.")
                return
            }
            SharePresenter.present(files)
        } catch {
            statusMessage = String(localized: "Couldn't prepare the audio files. Try again.")
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .failure:
            statusMessage = String(localized: "Import cancelled.")
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let summary = try store.importBank(from: url)
                if summary.recordingsImported == 0 && summary.phrasesCreated == 0 {
                    statusMessage = String(localized: "That backup contained no restorable phrases.")
                } else {
                    var parts: [String] = []
                    if summary.phrasesCreated > 0 {
                        parts.append((summary.phrasesCreated == 1 ? String(localized: "restored.phrase.one") : String(localized: "restored.phrase.many", defaultValue: "\(String(summary.phrasesCreated)) phrases with saved wording")))
                    }
                    if summary.recordingsImported > 0 {
                        parts.append((summary.recordingsImported == 1 ? String(localized: "restored.recording.one") : String(localized: "restored.recording.many", defaultValue: "\(String(summary.recordingsImported)) recordings")))
                    }
                    statusMessage = String(localized: "Restored ") + parts.joined(separator: String(localized: " and ")) + "."
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

/// Presents the system share sheet from the frontmost view controller.
///
/// Wrapping `UIActivityViewController` in a SwiftUI `.sheet` showed an empty
/// white sheet on iOS 26: the share sheet is itself a presented controller and
/// does not draw when embedded as a child. Presenting it directly is what
/// UIKit expects, and on iPad it gets the popover anchor it requires.
enum SharePresenter {
    @MainActor
    static func present(_ items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
