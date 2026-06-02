import Foundation

@MainActor
final class MemoStore: ObservableObject {
    @Published private(set) var notes: [String: String] = [:]
    private let key = "FontGrid.memos"

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            notes = saved
        }
    }

    func note(for name: String) -> String { notes[name] ?? "" }

    func hasNote(for name: String) -> Bool {
        !(notes[name]?.isEmpty ?? true)
    }

    func setNote(_ text: String, for name: String) {
        if text.isEmpty {
            notes.removeValue(forKey: name)
        } else {
            notes[name] = text
        }
        UserDefaults.standard.set(notes, forKey: key)
    }

    // MARK: - Tags

    /// Tags in a single note: tokens beginning with '#', taken up to the next
    /// whitespace, comma, or newline, lowercased. Empty tokens (`#`, `#,`) drop.
    static func parseTags(_ note: String) -> Set<String> {
        var tags = Set<String>()
        let chars = Array(note)
        var i = 0
        while i < chars.count {
            guard chars[i] == "#" else { i += 1; continue }
            var token = ""
            var j = i + 1
            while j < chars.count {
                let c = chars[j]
                if c == "," || c.isWhitespace { break }
                token.append(c)
                j += 1
            }
            let normalized = token.lowercased()
            if !normalized.isEmpty { tags.insert(normalized) }
            i = j
        }
        return tags
    }

    /// Tags attached to one font's note.
    func tags(for name: String) -> Set<String> { Self.parseTags(note(for: name)) }

    /// Every tag across all notes with the number of fonts using it, most-used
    /// first (ties broken alphabetically).
    var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for note in notes.values {
            for tag in Self.parseTags(note) { counts[tag, default: 0] += 1 }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (tag: $0.key, count: $0.value) }
    }
}
