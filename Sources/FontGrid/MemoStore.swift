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

    /// Remove every memo. Used by Settings → Data.
    func clearAll() {
        notes.removeAll()
        UserDefaults.standard.set(notes, forKey: key)
    }

    /// Merge imported memos into the current set. For each font: if there is no
    /// existing memo, take the imported one; if they are identical, keep one;
    /// if they differ, append the imported note after the existing one (a
    /// space separates them so tags stay distinct tokens — duplicates allowed).
    func merge(_ incoming: [String: String]) {
        for (name, incomingNote) in incoming where !incomingNote.isEmpty {
            let existing = notes[name] ?? ""
            if existing.isEmpty {
                notes[name] = incomingNote
            } else if existing != incomingNote {
                notes[name] = existing + " " + incomingNote
            }
        }
        UserDefaults.standard.set(notes, forKey: key)
    }

    /// Snapshot for export.
    var exportMap: [String: String] { notes }

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

    /// A valid tag name for use after '#': non-empty, with no whitespace,
    /// commas, or '#' (those end a token when parsing). Accepts a leading '#'
    /// and surrounding whitespace in the input; returns the normalized
    /// (lowercased) name, or nil when the input can't be a single tag.
    static func normalizeTagName(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        s = s.lowercased()
        guard !s.isEmpty,
              !s.contains(where: { $0 == "#" || $0 == "," || $0.isWhitespace })
        else { return nil }
        return s
    }

    /// Rename a tag across every memo: each '#old' token becomes '#new'
    /// (case-insensitive, same token boundaries as parseTags). Notes that end
    /// up holding '#new' more than once — the note already had it, or carried
    /// '#old' twice — keep only the first occurrence.
    func renameTag(_ old: String, to new: String) {
        let oldLower = old.lowercased()
        var changed = false
        for (name, note) in notes where Self.parseTags(note).contains(oldLower) {
            notes[name] = Self.replacingTag(in: note, old: oldLower, new: new)
            changed = true
        }
        if changed { UserDefaults.standard.set(notes, forKey: key) }
    }

    /// Token-wise replacement for renameTag. The first token matching old OR
    /// new emits '#new'; later matches are dropped (with one trailing space,
    /// so the note doesn't collect double gaps). All other text is untouched.
    static func replacingTag(in note: String, old: String, new: String) -> String {
        let chars = Array(note)
        var out = ""
        var emitted = false
        var i = 0
        while i < chars.count {
            guard chars[i] == "#" else { out.append(chars[i]); i += 1; continue }
            var token = ""
            var j = i + 1
            while j < chars.count {
                let c = chars[j]
                if c == "," || c.isWhitespace { break }
                token.append(c)
                j += 1
            }
            let lower = token.lowercased()
            if lower == old || lower == new {
                if !emitted {
                    out.append("#\(new)")
                    emitted = true
                } else if j < chars.count, chars[j] == " " {
                    j += 1
                }
            } else {
                out.append(contentsOf: chars[i..<j])
            }
            i = j
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

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
