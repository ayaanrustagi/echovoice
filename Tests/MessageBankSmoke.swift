import Foundation

struct Phrase {
    let id: UUID
    let label: String
    let text: String
    let symbolRaw: String
    let tintRaw: String
    var audioFileName: String?
    var shortcut: String = ""
}

@main
enum MessageBankSmoke {
    static func main() throws {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("EchoVoiceMessageBankSmoke-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }
        AudioFileManager.recordingsDirectoryOverride = scratch

        let recordedID = UUID()
        let audio = Data([0, 1, 2, 3, 4, 5])
        let sourceFile = "source.m4a"
        _ = try AudioFileManager.saveRecordingData(audio, fileName: sourceFile)

        let phrases = [
            Phrase(id: recordedID, label: "Love", text: "I love you", symbolRaw: "love", tintRaw: "forest", audioFileName: sourceFile),
            Phrase(id: UUID(), label: "Water", text: "Water please", symbolRaw: "water", tintRaw: "lime", audioFileName: nil)
        ]
        guard let exportURL = AudioFileManager.createExportPackage(phrases: phrases) else {
            preconditionFailure("A bank with a valid recording must export")
        }

        let package = try AudioFileManager.readExportPackage(at: exportURL)
        precondition(package.version == 1)
        precondition(package.messages.count == 1 && package.phrases.count == 2)
        precondition(package.messages[0].id == recordedID.uuidString)
        precondition(Data(base64Encoded: package.messages[0].data) == audio)

        let first = AudioFileManager.storeImportedAudio(package.messages[0])
        let second = AudioFileManager.storeImportedAudio(package.messages[0])
        precondition(first != nil && second != nil && first != second, "An import must never overwrite an existing recording")
        let importedAudio = try Data(contentsOf: AudioFileManager.getURL(for: first!))
        precondition(importedAudio == audio)

        let malformedID = AudioFileManager.ExportedMessage(id: "../escape", mime: "audio/m4a", data: audio.base64EncodedString())
        let malformedData = AudioFileManager.ExportedMessage(id: UUID().uuidString, mime: "audio/m4a", data: "not-base64")
        precondition(AudioFileManager.storeImportedAudio(malformedID) == nil)
        precondition(AudioFileManager.storeImportedAudio(malformedData) == nil)

        let badVersion = AudioFileManager.ExportPackage(
            version: 2,
            exported_at: package.exported_at,
            messages: package.messages,
            phrases: package.phrases
        )
        let badURL = scratch.appendingPathComponent("bad-version.echovoice")
        try JSONEncoder().encode(badVersion).write(to: badURL)
        do {
            _ = try AudioFileManager.readExportPackage(at: badURL)
            preconditionFailure("Unknown export versions must be rejected")
        } catch AudioFileManager.ImportError.badFormat {
            // Expected.
        }

        print("Message-bank export/import smoke tests passed")
    }
}
