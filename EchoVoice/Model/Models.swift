import Foundation
import SwiftData
import SwiftUI

/// A phrase the patient can speak aloud. Caregiver-authored; the app never
/// invents speech on a nonverbal person's behalf.
@Model
final class Phrase: Identifiable {
    @Attribute(.unique) var id: UUID
    var label: String
    var text: String
    var symbolRaw: String
    var tintRaw: String
    var orderIndex: Int
    var hasRecording: Bool
    var audioFileName: String?
    /// Optional user-authored shorthand. A shortcut is a retrieval aid only;
    /// it never changes the phrase's spoken text.
    // The default lets SwiftData migrate stores saved before this field existed;
    // without it, opening an older install fails with a validation error.
    var shortcut: String = ""
    var createdAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        text: String,
        symbolRaw: String = "custom",
        tintRaw: String = "lime",
        orderIndex: Int = 0,
        hasRecording: Bool = false,
        audioFileName: String? = nil,
        shortcut: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.label = label
        self.text = text
        self.symbolRaw = symbolRaw
        self.tintRaw = tintRaw
        self.orderIndex = orderIndex
        self.hasRecording = hasRecording
        self.audioFileName = audioFileName
        self.shortcut = shortcut
        self.createdAt = createdAt
    }

    convenience init(
        text: String,
        label: String,
        symbol: Symbol,
        tint: TintKind,
        orderIndex: Int = 0,
        shortcut: String = ""
    ) {
        self.init(
            id: UUID(),
            label: label,
            text: text,
            symbolRaw: symbol.rawValue,
            tintRaw: tint.rawValue,
            orderIndex: orderIndex,
            hasRecording: false,
            audioFileName: nil,
            shortcut: shortcut,
            createdAt: .now
        )
    }

    var symbol: Symbol {
        get { Symbol(rawValue: symbolRaw) ?? .custom }
        set { symbolRaw = newValue.rawValue }
    }

    var tint: TintKind {
        get { TintKind(rawValue: tintRaw) ?? .lime }
        set { tintRaw = newValue.rawValue }
    }

    enum Symbol: String, Codable, CaseIterable {
        case yes, no, water, bathroom, pain, hungry, cold, blanket
        case sitUp, love, tv, music, custom

        var localizedName: String {
            switch self {
            case .yes: return String(localized: "yes")
            case .no: return String(localized: "no")
            case .water: return String(localized: "water")
            case .bathroom: return String(localized: "bathroom")
            case .pain: return String(localized: "pain")
            case .hungry: return String(localized: "hungry")
            case .cold: return String(localized: "cold")
            case .blanket: return String(localized: "blanket")
            case .sitUp: return String(localized: "sitUp")
            case .love: return String(localized: "love")
            case .tv: return String(localized: "tv")
            case .music: return String(localized: "music")
            case .custom: return String(localized: "custom")
            }
        }
    }

    enum TintKind: String, Codable, CaseIterable {
        case lime, plain, orange, sky, lavender, rose, forest

        var localizedName: String {
            switch self {
            case .lime: return String(localized: "lime")
            case .plain: return String(localized: "plain")
            case .orange: return String(localized: "orange")
            case .sky: return String(localized: "sky")
            case .lavender: return String(localized: "lavender")
            case .rose: return String(localized: "rose")
            case .forest: return String(localized: "forest")
            }
        }
    }

    /// Starter board. Yes and No lead deliberately: in AAC they are the highest
    /// frequency messages by a wide margin, and without them someone who has
    /// just lost speech cannot answer a question on day one. The rest cover the
    /// needs a person is most often stuck unable to express — comfort,
    /// positioning, and the ones that are about being a person rather than a
    /// patient. All of it is editable; this is a starting point, not a
    /// prescription.
    static let starter: [(text: String, label: String, symbol: Symbol, tint: TintKind)] = [
        ("Yes", "Yes", .yes, .forest),
        ("No", "No", .no, .plain),
        ("I'd like some water, please", "Water", .water, .lime),
        ("I need to use the bathroom", "Bathroom", .bathroom, .plain),
        ("I am in pain, please help", "Pain", .pain, .orange),
        ("I'm hungry", "Hungry", .hungry, .lime),
        ("I'm feeling cold", "Cold", .cold, .lime),
        ("Can I have a blanket?", "Blanket", .blanket, .plain),
        ("Can you help me sit up?", "Sit Me Up", .sitUp, .orange),
        ("I love you", "I Love You", .love, .forest),
        ("Can you turn on the TV?", "TV", .tv, .plain),
        ("Can you put some music on?", "Music", .music, .lime)
    ]
}

extension Phrase {
    /// The starter board in Spanish, same order and symbols. Offered from
    /// Settings as an addition, never as a rewrite of phrases a caregiver may
    /// have edited or recorded.
    static let starterSpanish: [(text: String, label: String, symbol: Symbol, tint: TintKind)] = [
        ("Sí", "Sí", .yes, .forest),
        ("No", "No", .no, .plain),
        ("Quisiera un poco de agua, por favor", "Agua", .water, .lime),
        ("Necesito ir al baño", "Baño", .bathroom, .plain),
        ("Tengo dolor, ayúdame por favor", "Dolor", .pain, .orange),
        ("Tengo hambre", "Hambre", .hungry, .lime),
        ("Tengo frío", "Frío", .cold, .lime),
        ("¿Me das una cobija?", "Cobija", .blanket, .plain),
        ("¿Me ayudas a sentarme?", "Sentarme", .sitUp, .orange),
        ("Te quiero", "Te Quiero", .love, .forest),
        ("¿Puedes prender la tele?", "Tele", .tv, .plain),
        ("¿Puedes poner música?", "Música", .music, .lime)
    ]

    static func starters(for language: String) -> [(text: String, label: String, symbol: Symbol, tint: TintKind)] {
        language == "es" ? starterSpanish : starter
    }
}

extension Phrase.TintKind {
    var background: Color {
        switch self {
        case .lime: return Palette.lime
        case .plain: return Palette.surface
        case .orange: return Palette.orange
        case .sky: return Palette.sky
        case .lavender: return Palette.lavender
        case .rose: return Palette.rose
        case .forest: return Palette.forest
        }
    }
    var foreground: Color {
        if self == .forest { return Palette.onForestPhrase }
        if self == .plain { return Palette.controlAccent }
        return Palette.contrastPhraseText
    }
}

/// One weekly speech-journal entry. Stored on-device only.
@Model
final class CheckIn: Identifiable {
    @Attribute(.unique) var id: UUID
    var date: Date
    var wpm: Double
    var pitch: Double
    var pauseRatio: Double
    var articulationRate: Double
    var flagged: Bool
    var reasonsRaw: String

    /// Word accuracy from on-device speech recognition, 0...1.
    /// Negative means no reading was captured (recognition unavailable that week),
    /// which is distinct from a genuine score of 0.
    var intelligibility: Double = -1

    /// Marks a reading that was generated to demonstrate the journal rather than
    /// recorded by this person.
    ///
    /// Sample readings are stored in the same table so the chart, the baseline,
    /// and the trend logic exercise the real code path — but every surface that
    /// shows them has to say so, and they are removable in one action. A journal
    /// that quietly mixes invented readings into someone's own history would be
    /// worse than having no demonstration at all.
    ///
    /// Defaulted, so existing stores migrate without a schema version bump.
    var isSample: Bool = false

    init(
        id: UUID = UUID(),
        date: Date = .now,
        wpm: Double,
        pitch: Double = 0,
        pauseRatio: Double = 0,
        articulationRate: Double = 0,
        flagged: Bool = false,
        reasonsRaw: String = "",
        intelligibility: Double = -1,
        isSample: Bool = false
    ) {
        self.id = id
        self.date = date
        self.wpm = wpm
        self.pitch = pitch
        self.pauseRatio = pauseRatio
        self.articulationRate = articulationRate
        self.flagged = flagged
        self.reasonsRaw = reasonsRaw
        self.intelligibility = intelligibility
        self.isSample = isSample
    }

    /// Whether this check-in captured an intelligibility reading.
    var hasIntelligibility: Bool { intelligibility >= 0 }

    var reasons: [String] {
        get {
            guard !reasonsRaw.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: Data(reasonsRaw.utf8))) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue), let str = String(data: data, encoding: .utf8) {
                reasonsRaw = str
            }
        }
    }

    var metrics: CheckinMetrics {
        CheckinMetrics(wpm: wpm, pauseRatio: pauseRatio, pitchStability: pitch)
    }
}

/// Type alias for backward compatibility with Checkin
typealias Checkin = CheckIn

@Model
final class Recording: Identifiable {
    @Attribute(.unique) var id: UUID
    var phraseId: UUID
    var audioFileName: String
    var createdAt: Date
    var durationSec: Double

    init(
        id: UUID = UUID(),
        phraseId: UUID,
        audioFileName: String,
        createdAt: Date = .now,
        durationSec: Double = 0.0
    ) {
        self.id = id
        self.phraseId = phraseId
        self.audioFileName = audioFileName
        self.createdAt = createdAt
        self.durationSec = durationSec
    }
}

/// Lightweight event record for user status checks (e.g., "I'm Okay").
/// Stored on-device only for check-in history.
@Model
final class StatusEvent: Identifiable {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kindRaw: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        kindRaw: String = "okay"
    ) {
        self.id = id
        self.date = date
        self.kindRaw = kindRaw
    }
}
