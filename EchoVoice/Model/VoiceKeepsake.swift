import Foundation

/// Banked recordings as ordinary audio files, named after their phrases.
///
/// The message-bank backup is a single `.echovoice` file that only EchoVoice
/// can open. That is right for restoring a board, and wrong for a family who
/// wants to keep a voice: years from now, "I love you.m4a" will still open on
/// anything, with or without this app. So this copies each recording out
/// under its phrase's own label, ready for the share sheet.
enum VoiceKeepsake {
    struct Item {
        let label: String
        let source: URL
    }

    static let folderName = String(localized: "EchoVoice Voice Keepsake")
    static let maxNameLength = 60

    /// File names for `labels`, in order: safe on every common file system,
    /// never empty, and never repeated ("Water.m4a", "Water 2.m4a").
    static func fileNames(for labels: [String], fileExtension: String = "m4a") -> [String] {
        var used = Set<String>()
        return labels.map { label in
            let base = safeName(label)
            var name = "\(base).\(fileExtension)"
            var copy = 2
            while used.contains(name.lowercased()) {
                name = "\(base) \(copy).\(fileExtension)"
                copy += 1
            }
            used.insert(name.lowercased())
            return name
        }
    }

    /// Copy every item into a fresh temporary folder under its phrase's name.
    /// Items whose recording is missing are skipped. Returns the copied files.
    static func prepare(_ items: [Item], in parent: URL = FileManager.default.temporaryDirectory) throws -> [URL] {
        let fileManager = FileManager.default
        let folder = parent.appendingPathComponent(folderName, isDirectory: true)
        // A fresh folder each time, so a phrase deleted since the last share
        // can't linger in the next one.
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let present = items.filter { fileManager.fileExists(atPath: $0.source.path) }
        let names = fileNames(for: present.map(\.label))
        return try zip(present, names).map { item, name in
            let destination = folder.appendingPathComponent(name)
            try fileManager.copyItem(at: item.source, to: destination)
            return destination
        }
    }

    /// Strip characters that are illegal or troublesome in file names on
    /// macOS, Windows, and Android, collapse whitespace, and cap the length.
    static func safeName(_ label: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = label
            .components(separatedBy: illegal).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let capped = String(cleaned.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? String(localized: "Phrase") : capped
    }
}
