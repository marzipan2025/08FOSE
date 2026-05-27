import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var names: Set<String> = []
    private let key = "FontGrid.favorites"

    init() {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            names = Set(saved)
        }
    }

    func contains(_ name: String) -> Bool { names.contains(name) }

    func toggle(_ name: String) {
        if names.contains(name) {
            names.remove(name)
        } else {
            names.insert(name)
        }
        UserDefaults.standard.set(Array(names), forKey: key)
    }

    var sorted: [String] {
        names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
