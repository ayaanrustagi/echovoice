import Foundation

@main
enum VoiceKeepsakeSmoke {
    static func main() throws {
        // Names: readable, safe everywhere, never repeated.
        let names = VoiceKeepsake.fileNames(for: ["I love you", "Water", "water", "Water", "Yes/No?", "  ", "...", "Line\nbreak"])
        precondition(names == [
            "I love you.m4a", "Water.m4a", "water 2.m4a", "Water 3.m4a",
            "Yes No.m4a", "Phrase.m4a", "Phrase 2.m4a", "Line break.m4a",
        ], "\(names)")
        precondition(VoiceKeepsake.safeName(String(repeating: "a", count: 200)).count == VoiceKeepsake.maxNameLength)
        precondition(VoiceKeepsake.safeName("C:\\Users\\me") == "C Users me")

        // Copying: missing recordings are skipped, the folder is rebuilt each
        // time, and the originals are untouched.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keepsake-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let love = root.appendingPathComponent("phrase_1.m4a")
        let water = root.appendingPathComponent("phrase_2.m4a")
        try Data("love".utf8).write(to: love)
        try Data("water".utf8).write(to: water)
        let missing = root.appendingPathComponent("phrase_gone.m4a")

        let first = try VoiceKeepsake.prepare([
            .init(label: "I love you", source: love),
            .init(label: "Gone", source: missing),
            .init(label: "Water", source: water),
        ], in: root)
        precondition(first.map(\.lastPathComponent) == ["I love you.m4a", "Water.m4a"], "\(first)")
        let copied = try Data(contentsOf: first[0])
        precondition(copied == Data("love".utf8))
        precondition(FileManager.default.fileExists(atPath: love.path), "original must remain")

        let second = try VoiceKeepsake.prepare([.init(label: "Water", source: water)], in: root)
        let folder = root.appendingPathComponent(VoiceKeepsake.folderName)
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(second.count == 1 && contents == ["Water.m4a"], "stale keepsake files left behind: \(contents)")

        // Timeline: order, both speakers, repeats collapsed, capacity kept.
        var timeline = ConversationTimeline()
        timeline.append(.partner, "Do you want water?")
        timeline.append(.me, "Yes")
        timeline.append(.me, "Yes")
        timeline.append(.me, "   ")
        precondition(timeline.entries.map(\.speaker) == [.partner, .me], "\(timeline.entries)")
        for i in 0..<40 { timeline.append(i.isMultiple(of: 2) ? .partner : .me, "turn \(i)") }
        precondition(timeline.entries.count == ConversationTimeline.capacity)
        precondition(timeline.entries.last?.text == "turn 39")
        precondition(Set(timeline.entries.map(\.id)).count == timeline.entries.count, "ids must stay unique")
        timeline.clear()
        precondition(timeline.entries.isEmpty)

        print("voice-keepsake: all checks passed")
    }
}
