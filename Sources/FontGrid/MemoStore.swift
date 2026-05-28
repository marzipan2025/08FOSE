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
}
