import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    // Insertion order, oldest → newest. Persisted so recency survives relaunch.
    @Published private(set) var ordered: [String] = []
    private var nameSet: Set<String> = []
    private let key = "FontGrid.favorites"

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

    /// Remove every favorite. Used by Settings → Data.
    func clearAll() {
        ordered.removeAll()
        nameSet.removeAll()
        UserDefaults.standard.set(ordered, forKey: key)
    }

    /// Alphabetical (가나다 / A–Z).
    var sorted: [String] {
        ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Most recently favorited first.
    var byRecency: [String] { ordered.reversed() }
}
