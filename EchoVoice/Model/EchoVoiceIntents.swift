import AppIntents
import Foundation
import SwiftData

/// System-level entry points into EchoVoice: Siri, the Action Button, Shortcuts,
/// and Spotlight.
///
/// ## Why an AAC app needs these
///
/// Every product principle here reduces to fewer reliable actions. Unlocking a
/// phone, finding an app, and locating a tile is four or five actions before a
/// single word is spoken — and for someone whose hands are unreliable it is four
/// or five chances to fail. A hardware button or a spoken shortcut collapses
/// that to one, and both work when the screen is locked.
///
/// It also covers a real gap: someone who has lost speech but retains *some*
/// voice may still be able to trigger Siri when they cannot reliably tap. Two
/// unreliable channels covering each other is worth more than one.
///
/// ## Why these open the app rather than acting silently
///
/// Both intents set `openAppWhenRun`. A message spoken by a background process
/// gives the person no way to see what was said, stop it, or follow it up — and
/// for HELP in particular, a caregiver arriving needs the screen already showing
/// the emergency state. The intent records what was asked for; `RootView`
/// performs it once the interface is on screen.
enum PendingIntentAction: String {
    case help
    case speakPhrase

    private static let actionKey = "echovoice.pendingIntent.action"
    private static let phraseKey = "echovoice.pendingIntent.phraseID"

    /// Hand an action to the app.
    ///
    /// `UserDefaults` rather than an in-memory singleton: an intent may run
    /// before the app process exists, and the request has to survive launch.
    static func post(_ action: PendingIntentAction, phraseID: UUID? = nil) {
        UserDefaults.standard.set(action.rawValue, forKey: actionKey)
        UserDefaults.standard.set(phraseID?.uuidString, forKey: phraseKey)
    }

    /// Read and clear the pending action. Consuming it here means a relaunch
    /// cannot replay an old HELP request.
    static func consume() -> (action: PendingIntentAction, phraseID: UUID?)? {
        guard let raw = UserDefaults.standard.string(forKey: actionKey),
              let action = PendingIntentAction(rawValue: raw)
        else { return nil }
        let phraseID = UserDefaults.standard.string(forKey: phraseKey).flatMap(UUID.init(uuidString:))
        UserDefaults.standard.removeObject(forKey: actionKey)
        UserDefaults.standard.removeObject(forKey: phraseKey)
        return (action, phraseID)
    }
}

// MARK: - Phrase entity

/// A board phrase, exposed to the system so Siri and Shortcuts can offer the
/// person's own vocabulary by name rather than a fixed built-in list.
@available(iOS 17.0, *)
struct PhraseEntity: AppEntity {
    let id: UUID
    let label: String
    let text: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Phrase" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(text)")
    }

    static var defaultQuery = PhraseQuery()
}

/// Reads phrases straight from the app's SwiftData store.
///
/// Opens its own container against the same default store rather than reaching
/// for `AppStore`, because an intent can run in a process where no `AppStore`
/// exists. Read-only, so there is no write contention with a running app.
@available(iOS 17.0, *)
struct PhraseQuery: EntityQuery {
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Phrase.self, CheckIn.self, Recording.self, StatusEvent.self)
    }

    private func fetchAll() -> [Phrase] {
        guard let container = try? Self.makeContainer() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Phrase>(sortBy: [SortDescriptor(\Phrase.orderIndex, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func entities(for identifiers: [UUID]) async throws -> [PhraseEntity] {
        let wanted = Set(identifiers)
        return fetchAll()
            .filter { wanted.contains($0.id) }
            .map { PhraseEntity(id: $0.id, label: $0.label, text: $0.text) }
    }

    func suggestedEntities() async throws -> [PhraseEntity] {
        // The first page of the board — the phrases someone reaches for most,
        // and short enough to be a usable Siri list.
        fetchAll().prefix(12).map { PhraseEntity(id: $0.id, label: $0.label, text: $0.text) }
    }
}

@available(iOS 17.0, *)
extension PhraseQuery: EntityStringQuery {
    /// Matches what someone would actually say: the short board label, or the
    /// beginning of the full sentence.
    func entities(matching string: String) async throws -> [PhraseEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return fetchAll()
            .filter { $0.label.lowercased().contains(needle) || $0.text.lowercased().hasPrefix(needle) }
            .map { PhraseEntity(id: $0.id, label: $0.label, text: $0.text) }
    }
}

// MARK: - Intents

/// Speak one saved phrase.
@available(iOS 17.0, *)
struct SpeakPhraseIntent: AppIntent {
    static var title: LocalizedStringResource = "Speak a Phrase"
    static var description = IntentDescription(
        "Opens EchoVoice and speaks one of your saved phrases, in your banked recording when there is one."
    )
    static var openAppWhenRun = true

    @Parameter(title: "Phrase")
    var phrase: PhraseEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Speak \(\.$phrase)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingIntentAction.post(.speakPhrase, phraseID: phrase.id)
        return .result()
    }
}

/// Call for help without unlocking, finding the app, or hitting a target.
///
/// Worth being a separate parameterless intent rather than a case of
/// `SpeakPhraseIntent`: only a parameterless intent can be bound to the Action
/// Button or a Control Center control, and this is the one action where the
/// number of steps matters most.
@available(iOS 17.0, *)
struct CallForHelpIntent: AppIntent {
    static var title: LocalizedStringResource = "Call For Help"
    static var description = IntentDescription(
        "Opens EchoVoice and repeats the call for help aloud until someone stops it."
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingIntentAction.post(.help)
        return .result()
    }
}

// MARK: - Shortcuts

/// Spoken phrasings offered without any setup.
///
/// Deliberately few. A long list makes Siri ambiguous, and an ambiguous
/// emergency phrase is worse than no emergency phrase.
@available(iOS 17.0, *)
struct EchoVoiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CallForHelpIntent(),
            phrases: [
                "Call for help with \(.applicationName)",
                "\(.applicationName) help",
                "I need help with \(.applicationName)"
            ],
            shortTitle: "Call For Help",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: SpeakPhraseIntent(),
            phrases: [
                "Speak with \(.applicationName)",
                "Say something with \(.applicationName)"
            ],
            shortTitle: "Speak a Phrase",
            systemImageName: "speaker.wave.2.fill"
        )
    }
}
