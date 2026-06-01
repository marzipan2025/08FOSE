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

    // Wallpaper "skins" — bundled under Resources/Wallpapers/. The picker writes
    // a logical name (e.g. "Wallpaper02"); WallpaperOverlay resolves the actual
    // file based on the current appearance (Wallpaper02.webp dark vs
    // L_Wallpaper02.webp light).
    // "" = none.
    static let wallpapers = ["Wallpaper01", "Wallpaper02", "Wallpaper03", "Wallpaper04"]
    // Independent per-mode selections so dark and light each remember their
    // own choice; toggling theme restores the corresponding wallpaper.
    private static let darkWallpaperKey = "selectedWallpaperDark"
    private static let lightWallpaperKey = "selectedWallpaperLight"
    // Legacy key kept only for first-launch migration on existing installs.
    private static let legacyWallpaperKey = "selectedWallpaper"

    @Published var darkWallpaper: String = AppViewModel.loadInitialWallpaper(for: darkWallpaperKey) {
        didSet { UserDefaults.standard.set(darkWallpaper, forKey: Self.darkWallpaperKey) }
    }
    @Published var lightWallpaper: String = AppViewModel.loadInitialWallpaper(for: lightWallpaperKey) {
        didSet { UserDefaults.standard.set(lightWallpaper, forKey: Self.lightWallpaperKey) }
    }

    // Mode-aware accessor. Call sites that read `vm.wallpaper` (LeftPanel
    // picker, WallpaperOverlay) keep working unchanged, but reads/writes are
    // routed to the per-mode storage.
    var wallpaper: String {
        get { isLightMode ? lightWallpaper : darkWallpaper }
        set {
            if isLightMode { lightWallpaper = newValue }
            else { darkWallpaper = newValue }
        }
    }

    /// Resolve the initial value for a per-mode wallpaper key. Falls back to
    /// the legacy single-key value the first time this build runs on an
    /// existing install, so neither mode loses its previously-set choice.
    private static func loadInitialWallpaper(for key: String) -> String {
        let defaults = UserDefaults.standard
        if let v = defaults.string(forKey: key) { return v }
        return defaults.string(forKey: legacyWallpaperKey) ?? ""
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
