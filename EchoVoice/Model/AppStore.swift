import Foundation
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class AppStore {
    var modelContext: ModelContext?

    var phrases: [Phrase] = []
    var checkins: [CheckIn] = []
    var persistenceError: String?

    /// The current composition belongs to the communicator, not to a single
    /// board mode. Keeping it here means an interruption or a tab change never
    /// destroys the words someone has already built.
    var draftMessage: String {
        didSet { UserDefaults.standard.set(draftMessage, forKey: "echovoice.conversation.draft") }
    }

    /// A small, on-device transcript of messages EchoVoice has spoken. It is
    /// intentionally capped so the conversation workspace stays useful without
    /// becoming a surveillance log.
    var conversationHistory: [String] {
        didSet { UserDefaults.standard.set(conversationHistory, forKey: "echovoice.conversation.history") }
    }

    var lockedToBoard: Bool {
        didSet {
            UserDefaults.standard.set(lockedToBoard, forKey: "echovoice.locked")
        }
    }

    var textSize: String {
        didSet {
            UserDefaults.standard.set(textSize, forKey: "echovoice.textsize")
        }
    }

    var highContrastEnabled: Bool {
        didSet {
            UserDefaults.standard.set(highContrastEnabled, forKey: "echovoice.highContrast")
        }
    }

    /// Keeps the screen from sleeping while the Speak board is open. A locked
    /// phone leaves someone using eye tracking, or a mounted iPad, with no voice
    /// until another person unlocks it.
    var keepScreenAwake: Bool {
        didSet { UserDefaults.standard.set(keepScreenAwake, forKey: "echovoice.keepawake") }
    }

    /// Ignores a tile tap that lands within `repeatTapWindow` of the last one, so
    /// a tremor's double tap or a slide onto the next tile doesn't cut off the
    /// phrase the person actually chose.
    var ignoreRepeatTaps: Bool {
        didSet { UserDefaults.standard.set(ignoreRepeatTaps, forKey: "echovoice.ignorerepeat") }
    }
    static let repeatTapWindow: TimeInterval = 1.0

    /// Tiles speak only after a short hold, for hands that brush the screen.
    var holdToSpeak: Bool {
        didSet { UserDefaults.standard.set(holdToSpeak, forKey: "echovoice.holdtospeak") }
    }
    static let holdToSpeakDuration: Double = 0.5

    /// "en" or "es". Sets the language of HELP, and which starter phrases
    /// Settings offers to add. Each phrase is still spoken in its own language.
    var boardLanguage: String {
        didSet { UserDefaults.standard.set(boardLanguage, forKey: "echovoice.language") }
    }

    /// What HELP says aloud. Phrased as a direct request so a bystander who hears
    /// it knows what is being asked of them.
    var helpPhrase: String {
        boardLanguage == "es" ? "Necesito ayuda. Por favor, ven." : "I need help. Please come."
    }

    var boardDensity: String {
        didSet {
            UserDefaults.standard.set(boardDensity, forKey: "echovoice.boardDensity")
        }
    }

    var showSymbols: Bool {
        didSet {
            UserDefaults.standard.set(showSymbols, forKey: "echovoice.showSymbols")
        }
    }

    var smartSuggestionsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smartSuggestionsEnabled, forKey: "echovoice.smartSuggestions.enabled")
        }
    }

    private var phraseRanker = AdaptivePhraseRanker()

    var profileName: String { didSet { UserDefaults.standard.set(profileName, forKey: "echovoice.profile.name") } }
    var profileDateOfBirth: String { didSet { UserDefaults.standard.set(profileDateOfBirth, forKey: "echovoice.profile.dob") } }
    var profileAddress: String { didSet { UserDefaults.standard.set(profileAddress, forKey: "echovoice.profile.address") } }
    var profilePhone: String { didSet { UserDefaults.standard.set(profilePhone, forKey: "echovoice.profile.phone") } }
    var profileEmail: String { didSet { UserDefaults.standard.set(profileEmail, forKey: "echovoice.profile.email") } }
    var profileMedicalConditions: String { didSet { UserDefaults.standard.set(profileMedicalConditions, forKey: "echovoice.profile.medicalConditions") } }
    var profileMedications: String { didSet { UserDefaults.standard.set(profileMedications, forKey: "echovoice.profile.medications") } }
    var profileAllergies: String { didSet { UserDefaults.standard.set(profileAllergies, forKey: "echovoice.profile.allergies") } }
    var profileEmergencyContact: String { didSet { UserDefaults.standard.set(profileEmergencyContact, forKey: "echovoice.profile.emergencyContact") } }

    /// The phone number inside the free-text emergency contact ("Mom, 555-123-4567"),
    /// if there is one HELP can offer to text. Needs at least 7 digits so a
    /// name alone, or a stray number, never produces a text to nowhere.
    var emergencyContactPhone: String? {
        guard let match = profileEmergencyContact.range(of: #"\+?[\d\s().-]{7,}"#, options: .regularExpression) else { return nil }
        // The pattern also takes separators either side ("Jane - 512..."); keep
        // the number from its first digit, "+" or "(" to its last digit.
        let number = profileEmergencyContact[match]
            .trimmingCharacters(in: CharacterSet(charactersIn: "+(0123456789").inverted)
        return number.filter(\.isNumber).count >= 7 ? number : nil
    }

    /// The name part of the emergency contact, for "Text Mom". Empty when only
    /// a number was entered.
    var emergencyContactName: String {
        guard let phone = emergencyContactPhone else { return "" }
        return profileEmergencyContact
            .replacingOccurrences(of: phone, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—()\n").union(.whitespaces))
    }

    /// The minimum in-app text size. The upper bound stays open so EchoVoice never
    /// shrinks text below the size the person already chose in iOS Settings.
    var dynamicTypeRange: ClosedRange<DynamicTypeSize> {
        switch textSize {
        case "large": return .xxLarge ... .accessibility5
        case "xl": return .accessibility2 ... .accessibility5
        default: return .xSmall ... .accessibility5
        }
    }

    static let normalSpeechRate: Float = 0.5
    static let speechRateRange: ClosedRange<Float> = 0.35...0.65

    var speechRate: Float {
        didSet {
            UserDefaults.standard.set(speechRate, forKey: "echovoice.speechrate")
        }
    }

    var speechVolume: Float {
        didSet {
            UserDefaults.standard.set(speechVolume, forKey: "echovoice.speechvolume")
        }
    }

    init() {
        self.lockedToBoard = UserDefaults.standard.bool(forKey: "echovoice.locked")
        #if os(iOS)
        let defaultTextSize = UIDevice.current.userInterfaceIdiom == .pad ? "large" : "standard"
        #else
        let defaultTextSize = "standard"
        #endif
        let savedTextSize = UserDefaults.standard.string(forKey: "echovoice.textsize") ?? defaultTextSize
        // Early onboarding builds stored "xlarge" while the rest of the app uses
        // "xl". Migrate it once instead of leaving Extra Large silently broken.
        self.textSize = savedTextSize == "xlarge" ? "xl" : savedTextSize
        // Deterministic launch override is used for App Store screenshots and
        // accessibility verification; normal releases continue to use the
        // person's saved setting.
        self.highContrastEnabled = UserDefaults.standard.bool(forKey: "echovoice.highContrast")
            || ProcessInfo.processInfo.arguments.contains("-EchoVoiceHighContrast")
        self.boardDensity = UserDefaults.standard.string(forKey: "echovoice.boardDensity") ?? "comfortable"
        self.boardLanguage = UserDefaults.standard.string(forKey: "echovoice.language") ?? AppLanguage.code
        self.keepScreenAwake = UserDefaults.standard.object(forKey: "echovoice.keepawake") as? Bool ?? true
        self.ignoreRepeatTaps = UserDefaults.standard.object(forKey: "echovoice.ignorerepeat") as? Bool ?? true
        self.holdToSpeak = UserDefaults.standard.bool(forKey: "echovoice.holdtospeak")
        self.showSymbols = UserDefaults.standard.object(forKey: "echovoice.showSymbols") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "echovoice.showSymbols")
        self.smartSuggestionsEnabled = UserDefaults.standard.object(forKey: "echovoice.smartSuggestions.enabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "echovoice.smartSuggestions.enabled")
        self.profileName = UserDefaults.standard.string(forKey: "echovoice.profile.name") ?? ""
        self.profileDateOfBirth = UserDefaults.standard.string(forKey: "echovoice.profile.dob") ?? ""
        self.profileAddress = UserDefaults.standard.string(forKey: "echovoice.profile.address") ?? ""
        self.profilePhone = UserDefaults.standard.string(forKey: "echovoice.profile.phone") ?? ""
        self.profileEmail = UserDefaults.standard.string(forKey: "echovoice.profile.email") ?? ""
        self.profileMedicalConditions = UserDefaults.standard.string(forKey: "echovoice.profile.medicalConditions") ?? ""
        self.profileMedications = UserDefaults.standard.string(forKey: "echovoice.profile.medications") ?? ""
        self.profileAllergies = UserDefaults.standard.string(forKey: "echovoice.profile.allergies") ?? ""
        self.profileEmergencyContact = UserDefaults.standard.string(forKey: "echovoice.profile.emergencyContact") ?? ""
        // AVSpeechUtterance rates: 0.5 is the voice's normal pace. Older builds
        // offered 0.5...1.3, which could not slow speech down at all; bring any
        // saved value into the range Settings now offers.
        let savedRate = UserDefaults.standard.object(forKey: "echovoice.speechrate") as? Float ?? Self.normalSpeechRate
        self.speechRate = min(max(savedRate, Self.speechRateRange.lowerBound), Self.speechRateRange.upperBound)
        self.speechVolume = UserDefaults.standard.object(forKey: "echovoice.speechvolume") as? Float ?? 1.0
        self.draftMessage = UserDefaults.standard.string(forKey: "echovoice.conversation.draft") ?? ""
        self.conversationHistory = UserDefaults.standard.stringArray(forKey: "echovoice.conversation.history") ?? []
        if let savedModel = UserDefaults.standard.data(forKey: "echovoice.smartSuggestions.model"),
           let decoded = try? JSONDecoder().decode(AdaptivePhraseRanker.self, from: savedModel) {
            self.phraseRanker = decoded
        }
        self.phrases = Phrase.starters(for: boardLanguage).enumerated().map { idx, starter in
            Phrase(
                text: starter.text,
                label: starter.label,
                symbol: starter.symbol,
                tint: starter.tint,
                orderIndex: idx
            )
        }
    }

    func attachModelContext(_ context: ModelContext) {
        self.modelContext = context
        // A recording still waiting out its undo window when the app was quit.
        AudioFileManager.purgePendingDeletes()
        fetchData()
    }

    func fetchData() {
        guard let context = modelContext else { return }

        // Fetch phrases
        let phraseDescriptor = FetchDescriptor<Phrase>(sortBy: [SortDescriptor(\Phrase.orderIndex, order: .forward)])
        do {
            let fetchedPhrases = try context.fetch(phraseDescriptor)
            if fetchedPhrases.isEmpty {
                let starters = Phrase.starters(for: boardLanguage).enumerated().map { idx, starter in
                    Phrase(text: starter.text, label: starter.label,
                           symbol: starter.symbol, tint: starter.tint, orderIndex: idx)
                }
                for phrase in starters { context.insert(phrase) }
                do {
                    try context.save()
                    // Use the instances just saved. An immediate second fetch must
                    // never replace the usable starter board with an empty result.
                    phrases = starters
                    persistenceError = nil
                } catch {
                    context.rollback()
                    persistenceError = String(localized: "Couldn't save starter phrases. Please reopen EchoVoice to retry.")
                }
            } else {
                phrases = fetchedPhrases.filter { $0.id != pendingPhraseID }
                persistenceError = nil
            }
        } catch {
            // Retain the last usable board if persistence is temporarily unavailable.
            persistenceError = String(localized: "Couldn't load saved phrases. Please reopen EchoVoice to retry.")
        }

        #if DEBUG
        // Seed the loaded phrase IDs for deterministic simulator layout checks.
        if ProcessInfo.processInfo.arguments.contains("-EchoVoiceSeedSuggestions") {
            for phrase in phrases.suffix(3) {
                phraseRanker.record(phraseID: phrase.id.uuidString, at: .now)
            }
        }
        #endif

        // Fetch checkins
        let checkinDescriptor = FetchDescriptor<CheckIn>(sortBy: [SortDescriptor(\CheckIn.date, order: .forward)])
        if let fetchedCheckins = try? context.fetch(checkinDescriptor) {
            self.checkins = fetchedCheckins
        }

        #if DEBUG
        // Labelled sample readings, for demo recordings and screenshots.
        if ProcessInfo.processInfo.arguments.contains("-EchoVoiceSampleJournal") {
            _ = loadSampleHistory()
        }
        #endif
    }

    // MARK: Phrase Actions

    var hasLearnedSuggestions: Bool { phraseRanker.totalSelections >= 3 }

    func suggestedPhrases(limit: Int, at date: Date = .now) -> [Phrase] {
        guard smartSuggestionsEnabled else { return [] }
        let ids = phraseRanker.suggestions(
            candidateIDs: phrases.map { $0.id.uuidString },
            at: date,
            limit: limit
        )
        let phrasesByID = Dictionary(uniqueKeysWithValues: phrases.map { ($0.id.uuidString, $0) })
        return ids.compactMap { phrasesByID[$0] }
    }

    /// Suggestions paired with the log-probability arithmetic that produced
    /// them, for the "why this?" panel. Same call the board ranks with, so the
    /// explanation can never describe a different ordering than the one shown.
    func suggestionExplanations(limit: Int, at date: Date = .now) -> [(phrase: Phrase, explanation: AdaptivePhraseRanker.Explanation)] {
        guard smartSuggestionsEnabled else { return [] }
        let phrasesByID = Dictionary(uniqueKeysWithValues: phrases.map { ($0.id.uuidString, $0) })
        return phraseRanker
            .rank(candidateIDs: phrases.map { $0.id.uuidString }, at: date, limit: limit)
            .compactMap { explanation in
                guard let phrase = phrasesByID[explanation.phraseID] else { return nil }
                return (phrase, explanation)
            }
    }

    /// Label for a phrase id, so an explanation can name the phrase that
    /// preceded this one instead of showing a raw UUID.
    func phraseLabel(forID id: String) -> String? {
        phrases.first(where: { $0.id.uuidString == id })?.label
    }

    func recordPhraseUse(_ phrase: Phrase, at date: Date = .now) {
        guard smartSuggestionsEnabled else { return }
        phraseRanker.record(phraseID: phrase.id.uuidString, at: date)
        persistPhraseRanker()
    }

    // MARK: Conversation continuity

    func rememberSpokenMessage(_ message: String) {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        conversationHistory = Array((conversationHistory + [cleaned]).suffix(8))
    }

    func clearConversationHistory() {
        conversationHistory = []
    }

    // MARK: Personal shortcuts

    /// Returns a phrase whose exact user-authored shortcut matches the token,
    /// or whose label/text begins with it. Matching remains deterministic and
    /// offline so a shortcut is dependable for low-effort communication.
    func phrase(matchingShortcut token: String) -> Phrase? {
        let query = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return nil }
        return phrases.first(where: { $0.shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == query })
            ?? phrases.first(where: { $0.label.lowercased().hasPrefix(query) })
    }

    @discardableResult
    func setShortcut(_ shortcut: String, for phrase: Phrase) -> Bool {
        guard let context = modelContext else { return false }
        let cleaned = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count <= 24 else { return false }
        let normalized = cleaned.lowercased()
        if !normalized.isEmpty,
           phrases.contains(where: { $0.id != phrase.id && $0.shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
            return false
        }
        let previous = phrase.shortcut
        phrase.shortcut = cleaned
        do {
            try context.save()
            fetchData()
            return true
        } catch {
            phrase.shortcut = previous
            context.rollback()
            fetchData()
            return false
        }
    }

    func resetSmartSuggestions() {
        phraseRanker = AdaptivePhraseRanker()
        persistPhraseRanker()
    }

    private func persistPhraseRanker() {
        guard let encoded = try? JSONEncoder().encode(phraseRanker) else { return }
        UserDefaults.standard.set(encoded, forKey: "echovoice.smartSuggestions.model")
    }

    /// Moves a phrase to `newIndex` on the board and renumbers the rest, so the
    /// phrases someone reaches for most can sit at the top without scrolling.
    func movePhrase(_ phrase: Phrase, to newIndex: Int) {
        guard let from = phrases.firstIndex(where: { $0.id == phrase.id }) else { return }
        var reordered = phrases
        let item = reordered.remove(at: from)
        reordered.insert(item, at: max(0, min(newIndex, reordered.count)))
        for (index, p) in reordered.enumerated() { p.orderIndex = index }
        do {
            try modelContext?.save()
            phrases = reordered
        } catch {
            modelContext?.rollback()
            fetchData()
        }
    }

    /// Starter phrases for `language` that aren't on the board yet.
    func missingStarters(for language: String) -> Int {
        let existing = Set(phrases.map { $0.text.lowercased() })
        return Phrase.starters(for: language).filter { !existing.contains($0.text.lowercased()) }.count
    }

    /// Adds the starter phrases for `language` to the end of the board, skipping
    /// any already there. "No" is the same word in both, so it isn't doubled.
    @discardableResult
    func addStarters(for language: String) -> Bool {
        guard let context = modelContext else { return false }
        let existing = Set(phrases.map { $0.text.lowercased() })
        var index = phrases.count
        for starter in Phrase.starters(for: language) where !existing.contains(starter.text.lowercased()) {
            context.insert(Phrase(text: starter.text, label: starter.label, symbol: starter.symbol, tint: starter.tint, orderIndex: index))
            index += 1
        }
        do {
            try context.save()
            fetchData()
            return true
        } catch {
            context.rollback()
            fetchData()
            return false
        }
    }

    @discardableResult
    func addPhrase(_ phrase: Phrase) -> Bool {
        guard let context = modelContext else { return false }
        phrase.orderIndex = phrases.count
        context.insert(phrase)
        do {
            try context.save()
            fetchData()
            return true
        } catch {
            context.rollback()
            fetchData()
            return false
        }
    }

    /// Hides the phrase now and erases it once the undo window closes. If the app
    /// is quit inside the window the phrase survives, which is the safe way to fail.
    func deletePhrase(_ phrase: Phrase) {
        commitPendingDelete()
        pendingDelete = PendingDelete(message: String(localized: "Removed “%@”", defaultValue: "Removed \u{201C}\(String(describing: phrase.label))\u{201D}"), kind: .phrase(phrase))
        phrases.removeAll { $0.id == phrase.id }
        scheduleCommit()
    }

    private func erasePhrase(_ phrase: Phrase) {
        guard let context = modelContext else { return }
        let recordingToDelete = phrase.audioFileName
        context.delete(phrase)
        do {
            try context.save()
            if let recordingToDelete {
                AudioFileManager.deleteRecording(fileName: recordingToDelete)
            }
            fetchData()
        } catch {
            context.rollback()
            fetchData()
        }
    }

    @discardableResult
    func saveBankedRecording(for phrase: Phrase, audioData: Data) -> Bool {
        guard let context = modelContext, !audioData.isEmpty else { return false }

        // Write to a new name first. A re-record must not destroy the existing
        // voice until both the new audio and its SwiftData reference are saved.
        let fileName = "phrase_\(phrase.id.uuidString)_\(UUID().uuidString).m4a"
        let previousFileName = phrase.audioFileName
        do {
            _ = try AudioFileManager.saveRecordingData(audioData, fileName: fileName)
            phrase.hasRecording = true
            phrase.audioFileName = fileName
            try context.save()
            if let previousFileName, previousFileName != fileName {
                AudioFileManager.deleteRecording(fileName: previousFileName)
            }
            fetchData()
            return true
        } catch {
            AudioFileManager.deleteRecording(fileName: fileName)
            context.rollback()
            fetchData()
            return false
        }
    }

    /// Detaches the recording now but only sets the file aside; it is erased once
    /// the undo window closes. A banked voice may be impossible to record again.
    func deleteBankedRecording(for phrase: Phrase) {
        guard let context = modelContext, let fn = phrase.audioFileName else { return }
        commitPendingDelete()
        // A file already missing from disk has nothing to undo; just detach it.
        let onDisk = AudioFileManager.exists(fileName: fn)
        guard !onDisk || AudioFileManager.setAsidePendingDelete(fileName: fn) else { return }
        phrase.hasRecording = false
        phrase.audioFileName = nil
        do {
            try context.save()
        } catch {
            context.rollback()
            if onDisk { _ = AudioFileManager.restorePendingDelete(fileName: fn) }
            fetchData()
            return
        }
        if onDisk {
            pendingDelete = PendingDelete(message: String(localized: "Deleted the recording of “%@”", defaultValue: "Deleted the recording of \u{201C}\(String(describing: phrase.label))\u{201D}"), kind: .recording(phrase, fileName: fn))
            scheduleCommit()
        }
        fetchData()
    }

    // MARK: Undoable Deletes

    /// The most recent delete, held for `undoWindow` so a slip of the hand can be
    /// taken back. Only one is held at a time; starting another commits the first.
    struct PendingDelete: Identifiable {
        enum Kind {
            case phrase(Phrase)
            case recording(Phrase, fileName: String)
        }
        let id = UUID()
        let message: String
        let kind: Kind
    }

    static let undoWindow: Duration = .seconds(10)

    private(set) var pendingDelete: PendingDelete?
    private var commitTask: Task<Void, Never>?

    private var pendingPhraseID: UUID? {
        if case .phrase(let phrase) = pendingDelete?.kind { return phrase.id }
        return nil
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: AppStore.undoWindow)
            guard !Task.isCancelled else { return }
            self?.commitPendingDelete()
        }
    }

    /// Makes the held delete permanent.
    func commitPendingDelete() {
        commitTask?.cancel()
        commitTask = nil
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        switch pending.kind {
        case .phrase(let phrase):
            erasePhrase(phrase)
        case .recording(_, let fileName):
            AudioFileManager.erasePendingDelete(fileName: fileName)
        }
    }

    func undoDelete() {
        commitTask?.cancel()
        commitTask = nil
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        switch pending.kind {
        case .phrase:
            break
        case .recording(let phrase, let fileName):
            if AudioFileManager.restorePendingDelete(fileName: fileName) {
                phrase.hasRecording = true
                phrase.audioFileName = fileName
                try? modelContext?.save()
            }
        }
        fetchData()
    }

    // MARK: Message Bank Import

    /// Restore a message bank exported from this or another device (including the
    /// web build). Recordings are matched to phrases by id; a phrase that doesn't
    /// exist here yet is recreated from the export's metadata so a family can move
    /// their whole bank to a new device without losing anything.
    @discardableResult
    func importBank(from url: URL) throws -> AudioFileManager.ImportSummary {
        guard let context = modelContext else { return .init(recordingsImported: 0, phrasesCreated: 0) }

        let package = try AudioFileManager.readExportPackage(at: url)
        var metadataByID: [UUID: AudioFileManager.ExportedPhrase] = [:]
        for metadata in package.phrases {
            guard let id = UUID(uuidString: metadata.id) else { continue }
            metadataByID[id] = metadata
        }
        var existingByID = Dictionary(phrases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var summary = AudioFileManager.ImportSummary(recordingsImported: 0, phrasesCreated: 0)
        var importedFileNames: [String] = []
        var replacedFileNames: [String] = []

        // Restore every phrase record before attaching audio. Earlier imports
        // only recreated phrases that had a recording, which silently dropped
        // carefully prepared unrecorded vocabulary.
        for meta in package.phrases {
            guard let id = UUID(uuidString: meta.id), existingByID[id] == nil else { continue }
            let created = Phrase(
                id: id,
                label: meta.label,
                text: meta.text,
                symbolRaw: meta.symbol,
                tintRaw: meta.tint,
                orderIndex: phrases.count + summary.phrasesCreated,
                shortcut: meta.shortcut ?? ""
            )
            context.insert(created)
            existingByID[id] = created
            summary.phrasesCreated += 1
        }

        for message in package.messages {
            // Skip malformed payloads rather than aborting the whole import — a
            // partially recoverable bank is far better than none.
            guard let messageID = UUID(uuidString: message.id),
                  let storedFileName = AudioFileManager.storeImportedAudio(message)
            else { continue }

            let target: Phrase
            if let existing = existingByID[messageID] {
                target = existing
            } else if let meta = metadataByID[messageID] {
                let created = Phrase(
                    id: messageID,
                    label: meta.label,
                    text: meta.text,
                    symbolRaw: meta.symbol,
                    tintRaw: meta.tint,
                    orderIndex: phrases.count + summary.phrasesCreated,
                    shortcut: meta.shortcut ?? ""
                )
                context.insert(created)
                existingByID[messageID] = created
                summary.phrasesCreated += 1
                target = created
            } else {
                // Audio with no matching phrase and no metadata — nothing to attach it to.
                AudioFileManager.deleteRecording(fileName: storedFileName)
                continue
            }

            if let previousFileName = target.audioFileName, previousFileName != storedFileName {
                replacedFileNames.append(previousFileName)
            }
            target.hasRecording = true
            target.audioFileName = storedFileName
            if let meta = metadataByID[messageID], target.shortcut.isEmpty {
                target.shortcut = meta.shortcut ?? ""
            }
            importedFileNames.append(storedFileName)
            summary.recordingsImported += 1
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            importedFileNames.forEach(AudioFileManager.deleteRecording)
            fetchData()
            throw error
        }
        replacedFileNames.forEach(AudioFileManager.deleteRecording)
        fetchData()
        return summary
    }

    // MARK: Journal Check-ins

    @discardableResult
    func addCheckin(_ metrics: SpeechMetrics, intelligibility: IntelligibilityAnalyzer.Result? = nil) -> TrendResult? {
        guard let context = modelContext else {
            return nil
        }
        // Baselines come only from the person's own readings: labelled demo
        // samples must never shape a real check-in's comparison or flags.
        let history = realCheckins.map(\.metrics)
        let latest = CheckinMetrics(
            wpm: metrics.wpm,
            pauseRatio: metrics.pauseRatio,
            pitchStability: metrics.pitchStability
        )
        var trend = SpeechTrend.analyze(history: history, latest: latest)

        // Intelligibility is compared only against this person's own prior
        // readings — the recognizer's absolute accuracy on any one voice is not
        // meaningful, but a change in it week over week is.
        if let intelligibility {
            let priorScores = realCheckins.filter(\.hasIntelligibility).map(\.intelligibility)
            if let reason = SpeechTrend.intelligibilityReason(history: priorScores, latest: intelligibility.score) {
                trend.reasons.append(reason)
                trend.flagged = true
            }
        }

        let checkin = CheckIn(
            date: .now,
            wpm: metrics.wpm,
            pitch: metrics.pitchStability,
            pauseRatio: metrics.pauseRatio,
            articulationRate: metrics.articulationRate,
            flagged: trend.flagged,
            reasonsRaw: (try? String(data: JSONEncoder().encode(trend.reasons), encoding: .utf8)) ?? "",
            intelligibility: intelligibility?.score ?? -1
        )
        context.insert(checkin)
        do {
            try context.save()
            fetchData()
            return trend
        } catch {
            context.rollback()
            fetchData()
            return nil
        }
    }

    var latestTrend: TrendResult? {
        guard let last = checkins.last else { return nil }
        let history = Array(checkins.dropLast()).map(\.metrics)
        return SpeechTrend.analyze(history: history, latest: last.metrics)
    }

    var bankedCount: Int {
        phrases.filter(\Phrase.hasRecording).count
    }

    // MARK: Status Events

    // MARK: Journal explainability

    /// Readings this person actually recorded. Sample data is excluded from
    /// every clinician-facing surface — an export a clinician might read is the
    /// last place invented numbers belong.
    var realCheckins: [CheckIn] { checkins.filter { !$0.isSample } }

    var hasSampleHistory: Bool { checkins.contains(where: \.isSample) }

    /// The comparison behind one stored check-in: its personal baseline is the
    /// readings that came *before* it, never the whole series, so the panel
    /// shows what was known at the time rather than hindsight.
    func trendDetail(for checkin: CheckIn) -> TrendDetail {
        // Compare like with like: a real reading against real history, a
        // sample against the samples it was generated alongside.
        let priorHistory = checkins
            .filter { $0.isSample == checkin.isSample && $0.date < checkin.date }
            .map(\.metrics)
        return SpeechTrend.detail(history: priorHistory, latest: checkin.metrics)
    }

    // MARK: Sample journal history

    /// Insert a labelled demonstration history so the journal, chart, and trend
    /// logic can be seen working before someone has weeks of their own readings.
    ///
    /// Each generated reading is passed through `SpeechTrend.analyze` in date
    /// order against the readings before it, exactly as a live check-in is — so
    /// the flags that show up are produced by the shipping analyzer, not written
    /// in by the generator.
    @discardableResult
    func loadSampleHistory() -> Bool {
        guard let context = modelContext, !hasSampleHistory else { return false }

        var accumulated: [CheckinMetrics] = []
        var priorIntelligibility: [Double] = []
        var inserted: [CheckIn] = []

        for reading in SampleJournalHistory.readings() {
            let latest = CheckinMetrics(
                wpm: reading.metrics.wpm,
                pauseRatio: reading.metrics.pauseRatio,
                pitchStability: reading.metrics.pitchStability
            )
            var trend = SpeechTrend.analyze(history: accumulated, latest: latest)
            if let reason = SpeechTrend.intelligibilityReason(
                history: priorIntelligibility,
                latest: reading.intelligibility
            ) {
                trend.reasons.append(reason)
                trend.flagged = true
            }

            let checkin = CheckIn(
                date: reading.date,
                wpm: reading.metrics.wpm,
                pitch: reading.metrics.pitchStability,
                pauseRatio: reading.metrics.pauseRatio,
                articulationRate: reading.metrics.articulationRate,
                flagged: trend.flagged,
                reasonsRaw: (try? String(data: JSONEncoder().encode(trend.reasons), encoding: .utf8)) ?? "",
                intelligibility: reading.intelligibility,
                isSample: true
            )
            context.insert(checkin)
            inserted.append(checkin)
            accumulated.append(latest)
            priorIntelligibility.append(reading.intelligibility)
        }

        do {
            try context.save()
            fetchData()
            return true
        } catch {
            context.rollback()
            fetchData()
            return false
        }
    }

    /// Remove every sample reading, leaving anything the person recorded.
    @discardableResult
    func removeSampleHistory() -> Bool {
        guard let context = modelContext else { return false }
        let samples = checkins.filter(\.isSample)
        guard !samples.isEmpty else { return false }
        samples.forEach(context.delete)
        do {
            try context.save()
            fetchData()
            return true
        } catch {
            context.rollback()
            fetchData()
            return false
        }
    }

    /// Record an "I'm okay" check-in on this device.
    /// Returns whether it was actually persisted — the caller shows a confirmation,
    /// so a silent failure would tell the user something was saved when it wasn't.
    @discardableResult
    func recordOkay() -> Bool {
        guard let context = modelContext else { return false }
        context.insert(StatusEvent(kindRaw: "okay"))
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }
}
