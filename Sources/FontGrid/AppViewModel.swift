import SwiftUI

// Weight-count filter for the grid.
// - .all: no filtering
// - .exactly(n): families with exactly n weights
// - .range(lo, hi): families with lo…hi weights (inclusive)
// - .atLeast(n): families with n or more weights
enum WeightFilter: Hashable {
    case all
    case exactly(Int)
    case range(Int, Int)
    case atLeast(Int)

    func matches(_ weightCount: Int) -> Bool {
        switch self {
        case .all: return true
        case .exactly(let n): return weightCount == n
        case .range(let lo, let hi): return weightCount >= lo && weightCount <= hi
        case .atLeast(let n): return weightCount >= n
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    let library: FontLibrary

    // Persisted left-panel state — restored across launches so the user lands
    // in the same filter/search context they left in. Keys are read at init
    // and rewritten on every change via didSet.
    private static let searchQueryKey = "searchQuery"
    private static let weightFilterKey = "weightFilter"
    private static let pinnedOnlyKey = "pinnedOnly"
    private static let memoOnlyKey = "memoOnly"
    private static let variablesOnlyKey = "variablesOnly"
    private static let scriptFilterKey = "scriptFilter"
    private static let activeTagKey = "activeTag"
    private static let columnCountKey = "columnCount"
    private static let previewSizeOffsetKey = "previewSizeOffset"

    @Published var searchQuery: String = UserDefaults.standard.string(forKey: AppViewModel.searchQueryKey) ?? "" {
        didSet { UserDefaults.standard.set(searchQuery, forKey: Self.searchQueryKey) }
    }
    @Published var weightFilter: WeightFilter = AppViewModel.loadWeightFilter() {
        didSet { UserDefaults.standard.set(Self.encodeWeightFilter(weightFilter), forKey: Self.weightFilterKey) }
    }
    @Published var pinnedOnly: Bool = UserDefaults.standard.bool(forKey: AppViewModel.pinnedOnlyKey) {
        didSet { UserDefaults.standard.set(pinnedOnly, forKey: Self.pinnedOnlyKey) }
    }
    @Published var memoOnly: Bool = UserDefaults.standard.bool(forKey: AppViewModel.memoOnlyKey) {
        didSet { UserDefaults.standard.set(memoOnly, forKey: Self.memoOnlyKey) }
    }
    // Show only variable fonts (mirrors pinnedOnly / memoOnly).
    @Published var variablesOnly: Bool = UserDefaults.standard.bool(forKey: AppViewModel.variablesOnlyKey) {
        didSet { UserDefaults.standard.set(variablesOnly, forKey: Self.variablesOnlyKey) }
    }
    // Selected script buckets. Empty = no script filter (show all). Multiple
    // may be on at once (union); combined AND with the other filters.
    @Published var scriptFilter: Set<ScriptCategory> = AppViewModel.loadScriptFilter() {
        didSet {
            UserDefaults.standard.set(scriptFilter.map { $0.rawValue }, forKey: Self.scriptFilterKey)
        }
    }

    // How muted (not-wanted) fonts are treated in the grid:
    //  .shown  → visible but dimmed (default)
    //  .hidden → excluded from the grid
    enum MutedFilter: String { case shown, hidden }
    private static let mutedFilterKey = "mutedFilter"
    @Published var mutedFilter: MutedFilter =
        MutedFilter(rawValue: UserDefaults.standard.string(forKey: AppViewModel.mutedFilterKey) ?? "") ?? .shown {
        didSet { UserDefaults.standard.set(mutedFilter.rawValue, forKey: Self.mutedFilterKey) }
    }

    // Toggle the muted filter: shown ↔ hidden.
    func cycleMutedFilter() {
        mutedFilter = (mutedFilter == .shown) ? .hidden : .shown
    }

    // Show only muted fonts (mirrors pinnedOnly / memoOnly). Takes precedence
    // over mutedFilter when on.
    private static let mutedOnlyKey = "mutedOnly"
    @Published var mutedOnly: Bool = UserDefaults.standard.bool(forKey: AppViewModel.mutedOnlyKey) {
        didSet { UserDefaults.standard.set(mutedOnly, forKey: Self.mutedOnlyKey) }
    }

    func toggleScript(_ category: ScriptCategory) {
        if scriptFilter.contains(category) { scriptFilter.remove(category) }
        else { scriptFilter.insert(category) }
    }

    // Canonical order of the Weights filter chips (All → 1 → 3+ → 5+), shared
    // by the LeftPanel chips and the `w` shortcut so they stay in sync.
    static let weightFilterCycle: [WeightFilter] = [.all, .exactly(1), .range(2, 3), .range(4, 5), .atLeast(6)]

    // Advance the weight filter one step through weightFilterCycle, wrapping
    // back to .all. Bound to the `w` shortcut.
    func cycleWeightFilter() {
        let idx = Self.weightFilterCycle.firstIndex(of: weightFilter) ?? 0
        weightFilter = Self.weightFilterCycle[(idx + 1) % Self.weightFilterCycle.count]
    }

    // Active note tag (lowercased, without '#'). nil = no tag filter. Single
    // selection: tapping the active tag again clears it.
    @Published var activeTag: String? = AppViewModel.loadActiveTag() {
        didSet { UserDefaults.standard.set(activeTag ?? "", forKey: Self.activeTagKey) }
    }

    // Tag whose rename popup is open (the tag's current name). nil = closed.
    // Not persisted — a transient UI state, unlike activeTag above.
    @Published var renamingTag: String? = nil

    @Published var columnCount: Int = AppViewModel.loadColumnCount() {
        didSet { UserDefaults.standard.set(columnCount, forKey: Self.columnCountKey) }
    }
    @Published var maxColumns: Int = 6

    // Sidebar widths. Persisted here (not via @AppStorage) so they save reliably
    // and so resetToDefaults can restore them live, matching the rest of the
    // persisted UI state.
    private static let leftPanelWidthKey = "leftPanelWidth"
    private static let rightPanelWidthKey = "rightPanelWidth"
    static let defaultLeftPanelWidth = Double(Theme.panelDefaultWidth)
    static let defaultRightPanelWidth: Double = 256

    @Published var leftPanelWidth: Double = AppViewModel.loadWidth(AppViewModel.leftPanelWidthKey, AppViewModel.defaultLeftPanelWidth) {
        didSet { UserDefaults.standard.set(leftPanelWidth, forKey: Self.leftPanelWidthKey) }
    }
    @Published var rightPanelWidth: Double = AppViewModel.loadWidth(AppViewModel.rightPanelWidthKey, AppViewModel.defaultRightPanelWidth) {
        didSet { UserDefaults.standard.set(rightPanelWidth, forKey: Self.rightPanelWidthKey) }
    }

    // Distinguish "never set" (use default) from a stored 0, which would
    // otherwise collapse a panel to zero width on first launch.
    private static func loadWidth(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.double(forKey: key)
    }
    @Published var previewSizeOffset: Double = UserDefaults.standard.double(forKey: AppViewModel.previewSizeOffsetKey) {
        didSet { UserDefaults.standard.set(previewSizeOffset, forKey: Self.previewSizeOffsetKey) }
    }

    // Drives the full-window Settings overlay (see SettingsView).
    @Published var showSettings: Bool = false
    // Settings → Data "Reset everything" confirmation dialog. Kept here (not in
    // the view) so the ESC key cascade can tell when it's open and let ESC
    // dismiss only the dialog instead of closing the whole Settings modal.
    @Published var confirmReset: Bool = false
    var isPresentingConfirm: Bool { confirmReset }

    // Decoded backup waiting on the Merge / Replace choice (ImportChoicePopup,
    // shown above Settings). Kept here so the ESC cascade can dismiss just the
    // popup instead of the whole Settings modal. nil = closed.
    @Published var pendingImport: ExportData? = nil

    // Result of a manual update check (UpdateResultPopup, shown above
    // Settings). Same ESC-cascade contract as pendingImport. nil = closed.
    @Published var updateStatus: UpdateStatus? = nil

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

    // WeightFilter is an enum with associated values, so it has no Codable
    // synthesis for free — round-trip through a short string instead.
    private static func encodeWeightFilter(_ w: WeightFilter) -> String {
        switch w {
        case .all: return "all"
        case .exactly(let n): return "exactly:\(n)"
        case .range(let lo, let hi): return "range:\(lo)-\(hi)"
        case .atLeast(let n): return "atLeast:\(n)"
        }
    }

    private static func loadWeightFilter() -> WeightFilter {
        guard let s = UserDefaults.standard.string(forKey: weightFilterKey) else { return .all }
        if s == "all" { return .all }
        let parts = s.split(separator: ":")
        var decoded: WeightFilter? = nil
        if parts.count == 2 {
            let arg = String(parts[1])
            switch parts[0] {
            case "exactly": if let n = Int(arg) { decoded = .exactly(n) }
            case "atLeast": if let n = Int(arg) { decoded = .atLeast(n) }
            case "range":
                let r = arg.split(separator: "-")
                if r.count == 2, let lo = Int(r[0]), let hi = Int(r[1]) { decoded = .range(lo, hi) }
            default: break
            }
        }
        // Normalize: only keep values that map to a current chip; stale ones
        // (e.g. the old 3+/5+) fall back to All so no orphaned filter sticks.
        if let decoded, weightFilterCycle.contains(decoded) { return decoded }
        return .all
    }

    private static func loadScriptFilter() -> Set<ScriptCategory> {
        let raw = (UserDefaults.standard.array(forKey: scriptFilterKey) as? [String]) ?? []
        return Set(raw.compactMap { ScriptCategory(rawValue: $0) })
    }

    private static func loadActiveTag() -> String? {
        let s = UserDefaults.standard.string(forKey: activeTagKey)
        return (s?.isEmpty ?? true) ? nil : s
    }

    // columnCount has a non-zero default (4) so we can't use the plain
    // integer(forKey:) sentinel — distinguish "never set" from "set to 0".
    private static func loadColumnCount() -> Int {
        if UserDefaults.standard.object(forKey: columnCountKey) == nil { return 4 }
        return max(1, UserDefaults.standard.integer(forKey: columnCountKey))
    }

    // Pins list order: false = alphabetical (가나다), true = most recent first.
    // Default to Recent (most-recent-first) when unset; distinguish "never set"
    // from a stored false.
    @Published var pinsByRecent: Bool =
        UserDefaults.standard.object(forKey: "pinsByRecent") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pinsByRecent, forKey: "pinsByRecent") }
    }

    // Appearance: false = dark (default), true = light. Persisted.
    @Published var isLightMode: Bool = UserDefaults.standard.bool(forKey: "isLightMode") {
        didSet { UserDefaults.standard.set(isLightMode, forKey: "isLightMode") }
    }

    static let gridBaseFontSize: Double = 28
    static let weightRowBaseFontSize: Double = 40
    static let previewOffsetRange: ClosedRange<Double> = -10...30

    var gridFontSize: Double { Self.gridBaseFontSize + previewSizeOffset }
    var weightRowFontSize: Double { Self.weightRowBaseFontSize + previewSizeOffset }

    @Published var selectedFamily: FontFamily? = nil

    // Gates the heavy Glyphs grid: false during the open/close motion, true once
    // the detail has settled open. Keeps the expand/collapse animation smooth.
    @Published var detailGlyphsVisible: Bool = false

    // Where the open detail view was launched from — decides which ordered list
    // the left/right arrow keys step through.
    enum DetailSource { case grid, pins }
    @Published var detailSource: DetailSource = .grid

    init() {
        self.library = FontLibrary()
    }

    private static let detailOpenSpring = Animation.spring(response: 0.42, dampingFraction: 0.80)
    private static let detailCloseSpring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    // Open the detail for `family`; the glyph grid is shown only after the open
    // animation settles so the expand stays smooth.
    func openDetail(_ family: FontFamily, source: DetailSource) {
        detailSource = source
        detailGlyphsVisible = false
        if selectedFamily == nil {
            withAnimation(Self.detailOpenSpring) { selectedFamily = family }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [self] in
                if selectedFamily != nil { detailGlyphsVisible = true }
            }
        } else {
            // Already open (← / → or list switch): keep glyphs, just swap.
            selectedFamily = family
            detailGlyphsVisible = true
        }
    }

    // Close synchronously so the X / ESC always lands. Removing the glyph grid
    // (detailGlyphsVisible) and clearing selectedFamily in one transaction means
    // the grid isn't dragged through the collapse, while staying responsive.
    func closeDetail() {
        detailGlyphsVisible = false
        withAnimation(Self.detailCloseSpring) { selectedFamily = nil }
    }

    // Wipe ALL persisted state and return every in-memory setting to its
    // first-launch default. Pins/memos are cleared by their own stores
    // (see SettingsView.resetEverything); this handles the view-model's own
    // persisted keys (wallpaper, theme, sort order) and live UI state.
    func resetToDefaults() {
        // Remove the entire app defaults domain (wallpaper, theme, sort order,
        // preview text, pins/memos keys, the saved window frame, …).
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // Restore live published state to defaults so the UI updates without a
        // relaunch. The didSet observers re-write these default values.
        darkWallpaper = ""
        lightWallpaper = ""
        isLightMode = false
        pinsByRecent = true
        columnCount = 4
        maxColumns = 6
        leftPanelWidth = Self.defaultLeftPanelWidth
        rightPanelWidth = Self.defaultRightPanelWidth
        previewSizeOffset = 0
        activeTag = nil
        weightFilter = .all
        pinnedOnly = false
        memoOnly = false
        variablesOnly = false
        scriptFilter = []
        mutedFilter = .shown
        mutedOnly = false
        searchQuery = ""
        selectedFamily = nil
        detailGlyphsVisible = false
        detailSource = .grid
    }
}
