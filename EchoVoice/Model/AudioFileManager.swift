import Foundation

enum AudioFileManager {
    #if ECHOVOICE_TESTING
    static var recordingsDirectoryOverride: URL?
    #endif

    static var recordingsDirectory: URL {
        #if ECHOVOICE_TESTING
        if let recordingsDirectoryOverride {
            try? FileManager.default.createDirectory(at: recordingsDirectoryOverride, withIntermediateDirectories: true)
            return recordingsDirectoryOverride
        }
        #endif
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func getURL(for fileName: String) -> URL {
        recordingsDirectory.appendingPathComponent(fileName)
    }

    static func saveRecordingData(_ data: Data, fileName: String) throws -> URL {
        let url = getURL(for: fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func deleteRecording(fileName: String) {
        let url = getURL(for: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    // A deleted recording is renamed aside rather than removed, so Undo can put
    // it back. Anything still set aside at launch missed its window and is erased.

    private static let pendingSuffix = ".pending-delete"

    static func setAsidePendingDelete(fileName: String) -> Bool {
        let url = getURL(for: fileName)
        let aside = getURL(for: fileName + pendingSuffix)
        try? FileManager.default.removeItem(at: aside)
        return (try? FileManager.default.moveItem(at: url, to: aside)) != nil
    }

    static func restorePendingDelete(fileName: String) -> Bool {
        let aside = getURL(for: fileName + pendingSuffix)
        return (try? FileManager.default.moveItem(at: aside, to: getURL(for: fileName))) != nil
    }

    static func erasePendingDelete(fileName: String) {
        try? FileManager.default.removeItem(at: getURL(for: fileName + pendingSuffix))
    }

    static func purgePendingDeletes() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: recordingsDirectory.path)) ?? []
        for name in files where name.hasSuffix(pendingSuffix) {
            try? FileManager.default.removeItem(at: recordingsDirectory.appendingPathComponent(name))
        }
    }

    static func exists(fileName: String) -> Bool {
        let url = getURL(for: fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: Export / Import
    //
    // The message bank is exported as a single self-describing JSON file with
    // base64-embedded audio rather than a zip. Two reasons:
    //   1. Foundation has no public unzip API, so a zip export could never be
    //      re-imported — the old zip path produced files nothing could read back.
    //   2. The `messages` array matches the web build's export format exactly, so
    //      a family can export on iOS and import on the web app (or vice versa).
    //      That portability is the whole point of banking your own voice.

    /// One banked recording, in the web build's interchange shape.
    struct ExportedMessage: Codable {
        let id: String
        let mime: String
        let data: String  // base64-encoded audio
    }

    /// Phrase metadata. Ignored by the web importer, used by iOS to restore
    /// phrases that don't exist on the destination device yet.
    struct ExportedPhrase: Codable {
        let id: String
        let label: String
        let text: String
        let symbol: String
        let tint: String
        /// Optional for version-1 backups, which predate personal shortcuts.
        let shortcut: String?

        init(id: String, label: String, text: String, symbol: String, tint: String, shortcut: String? = nil) {
            self.id = id
            self.label = label
            self.text = text
            self.symbol = symbol
            self.tint = tint
            self.shortcut = shortcut
        }

        private enum CodingKeys: String, CodingKey { case id, label, text, symbol, tint, shortcut }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            label = try values.decode(String.self, forKey: .label)
            text = try values.decode(String.self, forKey: .text)
            symbol = try values.decode(String.self, forKey: .symbol)
            tint = try values.decode(String.self, forKey: .tint)
            shortcut = try values.decodeIfPresent(String.self, forKey: .shortcut)
        }
    }

    struct ExportPackage: Codable {
        let version: Int
        let exported_at: String
        let messages: [ExportedMessage]
        let phrases: [ExportedPhrase]

        init(version: Int, exported_at: String, messages: [ExportedMessage], phrases: [ExportedPhrase]) {
            self.version = version
            self.exported_at = exported_at
            self.messages = messages
            self.phrases = phrases
        }

        private enum CodingKeys: String, CodingKey { case version, exported_at, messages, phrases }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            exported_at = try values.decode(String.self, forKey: .exported_at)
            messages = try values.decode([ExportedMessage].self, forKey: .messages)
            phrases = try values.decode([ExportedPhrase].self, forKey: .phrases)
        }
    }

    struct ImportSummary {
        var recordingsImported: Int
        var phrasesCreated: Int
    }

    enum ImportError: LocalizedError {
        case unreadable
        case badFormat

        var errorDescription: String? {
            switch self {
            case .unreadable: return String(localized: "Couldn't open that file.")
            case .badFormat: return String(localized: "That doesn't look like an EchoVoice message bank.")
            }
        }
    }

    /// Package all phrase metadata and available recordings into one shareable
    /// file. Unrecorded phrases are included deliberately: restoring a board
    /// must not silently erase the words a family prepared.
    static func createExportPackage(phrases: [Phrase]) -> URL? {
        var messages: [ExportedMessage] = []
        for phrase in phrases {
            guard let fileName = phrase.audioFileName,
                  exists(fileName: fileName),
                  let audioData = try? Data(contentsOf: getURL(for: fileName))
            else { continue }
            messages.append(ExportedMessage(
                id: phrase.id.uuidString,
                mime: "audio/m4a",
                data: audioData.base64EncodedString()
            ))
        }

        guard !phrases.isEmpty else { return nil }

        let package = ExportPackage(
            // Keep the package version stable: adding an optional metadata field
            // is backward compatible with the existing interchange format.
            version: 1,
            exported_at: ISO8601DateFormatter().string(from: .now),
            messages: messages,
            phrases: phrases.map { p in
                ExportedPhrase(
                    id: p.id.uuidString,
                    label: p.label,
                    text: p.text,
                    symbol: p.symbolRaw,
                    tint: p.tintRaw,
                    shortcut: p.shortcut.isEmpty ? nil : p.shortcut
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let encoded = try? encoder.encode(package) else { return nil }

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoVoice_MessageBank.echovoice")
        try? FileManager.default.removeItem(at: exportURL)
        guard (try? encoded.write(to: exportURL, options: [.atomic, .completeFileProtection])) != nil else { return nil }
        return exportURL
    }

    /// Read an exported bank off disk. Security-scoped access is required because
    /// the file comes from the document picker, outside the app container.
    static func readExportPackage(at url: URL) throws -> ExportPackage {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        guard let package = try? JSONDecoder().decode(ExportPackage.self, from: raw),
              package.version == 1 else {
            throw ImportError.badFormat
        }
        return package
    }

    /// Write one imported message's audio into the recordings directory.
    /// Returns the stored file name, or nil if the base64 payload was malformed.
    static func storeImportedAudio(_ message: ExportedMessage) -> String? {
        // UUID validation keeps a crafted import from turning an identifier into
        // a path, and the size cap prevents a bogus backup from exhausting memory.
        guard let id = UUID(uuidString: message.id),
              message.data.utf8.count <= 40_000_000,
              let audioData = Data(base64Encoded: message.data),
              !audioData.isEmpty else { return nil }
        let fileName = "phrase_\(id.uuidString)_\(UUID().uuidString).m4a"
        guard (try? saveRecordingData(audioData, fileName: fileName)) != nil else { return nil }
        return fileName
    }
}
