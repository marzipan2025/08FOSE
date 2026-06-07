import Foundation

/// Fonts the user has marked as "muted" (not wanted). Muted families are dimmed
/// in the grid and detail view, and the Collections muted filter can hide them,
/// show them, or show only them. Mirrors FavoritesStore's persistence.
@MainActor
final class MutedStore: ObservableObject {
    @Published private(set) var names: Set<String> = []
    private let key = "FontGrid.muted"

    init() {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            names = Set(saved)
        }
    }

    func contains(_ name: String) -> Bool { names.contains(name) }

    func toggle(_ name: String) {
        if names.contains(name) { names.remove(name) }
        else { names.insert(name) }
        persist()
    }

    /// Remove every muted mark. Used by Settings → Reset.
    func clearAll() {
        names.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(names), forKey: key)
    }
}
