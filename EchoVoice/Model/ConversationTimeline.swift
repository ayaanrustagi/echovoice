import Foundation

/// Both sides of a conversation in Listen mode, in order.
///
/// Answering through AAC is slow and tiring, and by the third exchange it is
/// easy to lose the thread: what did they ask, what did I already say? This
/// keeps the recent turns on screen.
///
/// Memory only. It is never saved, and Listen discards it when it closes; a
/// partner's words are not the person's data to keep.
struct ConversationTimeline: Equatable, Sendable {
    enum Speaker: Equatable, Sendable {
        case partner
        case me
    }

    struct Entry: Identifiable, Equatable, Sendable {
        let id: Int
        let speaker: Speaker
        let text: String
    }

    static let capacity = 30

    private(set) var entries: [Entry] = []
    private var nextID = 0

    mutating func append(_ speaker: Speaker, _ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // A double selection of the same reply is one thing said, not two.
        if let last = entries.last, last.speaker == speaker, last.text == text { return }
        entries.append(Entry(id: nextID, speaker: speaker, text: text))
        nextID += 1
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    mutating func clear() {
        entries.removeAll()
    }
}
