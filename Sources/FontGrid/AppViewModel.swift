import SwiftUI

// Weight-count filter for the grid.
// - .all: no filtering
// - .exactly(n): families with exactly n weights (n=1 means single-weight only)
// - .atLeast(n): families with n or more weights
enum WeightFilter: Hashable {
    case all
    case exactly(Int)
    case atLeast(Int)

    func matches(_ weightCount: Int) -> Bool {
        switch self {
        case .all: return true
        case .exactly(let n): return weightCount == n
        case .atLeast(let n): return weightCount >= n
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    let library: FontLibrary

    @Published var searchQuery: String = ""
    @Published var weightFilter: WeightFilter = .all
    @Published var favoritesOnly: Bool = false
    @Published var memoOnly: Bool = false
    @Published var koreanOnly: Bool = false
    @Published var englishOnly: Bool = false

    @Published var columnCount: Int = 4
    @Published var maxColumns: Int = 6
    @Published var previewSizeOffset: Double = 0

    // Wallpaper "skins" — bundled under Resources/Wallpapers/. More can be
    // dropped in and listed here; the active one is persisted so a future
    // settings switcher just binds to `wallpaper`.
    // "" = none. Otherwise a file name under Resources/Wallpapers/.
    static let wallpapers = ["Wallpaper01", "Wallpaper02", "Wallpaper03", "Wallpaper04"]
    private static let wallpaperKey = "selectedWallpaper"
    @Published var wallpaper: String = UserDefaults.standard.string(forKey: wallpaperKey) ?? "" {
        didSet { UserDefaults.standard.set(wallpaper, forKey: Self.wallpaperKey) }
    }

    // Favorites list order: false = alphabetical (가나다), true = most recent first.
    @Published var favoritesByRecent: Bool = UserDefaults.standard.bool(forKey: "favoritesByRecent") {
        didSet { UserDefaults.standard.set(favoritesByRecent, forKey: "favoritesByRecent") }
    }

    // Appearance: false = dark (default), true = light. Persisted.
    @Published var isLightMode: Bool = UserDefaults.standard.bool(forKey: "isLightMode") {
        didSet { UserDefaults.standard.set(isLightMode, forKey: "isLightMode") }
    }

    static let gridBaseFontSize: Double = 28
    static let weightRowBaseFontSize: Double = 40
    static let previewOffsetRange: ClosedRange<Double> = -8...20

    var gridFontSize: Double { Self.gridBaseFontSize + previewSizeOffset }
    var weightRowFontSize: Double { Self.weightRowBaseFontSize + previewSizeOffset }

    @Published var selectedFamily: FontFamily? = nil

    init() {
        self.library = FontLibrary()
    }
}
