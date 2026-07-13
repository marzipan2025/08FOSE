import Foundation

@MainActor
final class PinsStore: ObservableObject {
    // Insertion order, oldest → newest. Persisted so recency survives relaunch.
    @Published private(set) var ordered: [String] = []
    private var nameSet: Set<String> = []
    // Pre-rename data under "FontGrid.favorites" is carried over by
    // LegacyKeyMigration before this store is created.
    private let key = "FontGrid.pins"

    init() {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            ordered = saved
            nameSet = Set(saved)
        }
    }

    func contains(_ name: String) -> Bool { nameSet.contains(name) }

    func toggle(_ name: String) {
        if let index = ordered.firstIndex(of: name) {
            ordered.remove(at: index)
            nameSet.remove(name)
        } else {
            ordered.append(name)   // newest goes last
            nameSet.insert(name)
        }
        UserDefaults.standard.set(ordered, forKey: key)
    }

    /// Remove every pin. Used by Settings → Data.
    func clearAll() {
        ordered.removeAll()
        nameSet.removeAll()
        UserDefaults.standard.set(ordered, forKey: key)
    }

    /// Union an imported list into the current pins, preserving existing
    /// order and appending only names not already present. Used by import.
    func merge(_ names: [String]) {
        for name in names where !nameSet.contains(name) {
            ordered.append(name)
            nameSet.insert(name)
        }
        UserDefaults.standard.set(ordered, forKey: key)
    }

    /// Snapshot for export (recency order, oldest → newest).
    var exportList: [String] { ordered }

    /// Alphabetical (가나다 / A–Z).
    var sorted: [String] {
        ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Most recently pinned first.
    var byRecency: [String] { ordered.reversed() }
}
