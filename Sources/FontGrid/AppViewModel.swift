import SwiftUI

// Which face of a family the grid cells and pinned rows draw with.
//
// `memberFontNames` is already sorted light → heavy, so the two ends are just
// its first and last elements — no extra sorting or metric probing. `.normal`
// keeps the existing rule (a face literally named "Regular", else usWeightClass
// 400 / 500) so it means the same thing for variable and static families alike.
enum PreviewWeight: String, CaseIterable {
    case thin, normal, heavy

    var label: String {
        switch self {
        case .thin: return "Thin"
        case .normal: return "Normal"
        case .heavy: return "Heavy"
        }
    }
}

// How the blown-up glyph is drawn while a key is held over the grid. Not a
// stored preference — the key chosen picks the style, space for one and ⌥ for
// the other, since in practice both get reached for constantly.
//
// `.solid` is the plain ink of the appearance — black on light, white on dark.
// `.contour` inverts that fill, traces the outline in the accent colour at
// 1pt (white on light, black on dark, which would otherwise sink into the
// card), and marks every on-curve node the way a type editor would. Bitmap
// colour glyphs (emoji) have no outline to trace and nothing meaningful to
// invert, so they stay solid under either.
enum GlyphZoomStyle {
    case solid, contour
}

// One weight-count bucket for the grid filter. Buckets are selected as a set;
// an empty set means no weight filtering.
// - .exactly(n): families with exactly n weights
// - .range(lo, hi): families with lo…hi weights (inclusive)
// - .atLeast(n): families with n or more weights
enum WeightFilter: Hashable {
    case exactly(Int)
    case range(Int, Int)
    case atLeast(Int)

    func matches(_ weightCount: Int) -> Bool {
        switch self {
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
    private static let weightFiltersKey = "weightFilters"
    private static let pinnedOnlyKey = "pinnedOnly"
    private static let memoOnlyKey = "memoOnly"
    private static let variablesOnlyKey = "variablesOnly"
    private static let scriptFilterKey = "scriptFilter"
    private static let previewWeightKey = "previewWeight"
    private static let activeTagKey = "activeTag"
    private static let columnCountKey = "columnCount"
    private static let previewSizeOffsetKey = "previewSizeOffset"
    private static let useMotionKey = "useMotion"

    @Published var searchQuery: String = UserDefaults.standard.string(forKey: AppViewModel.searchQueryKey) ?? "" {
        didSet { UserDefaults.standard.set(searchQuery, forKey: Self.searchQueryKey) }
    }
    // The weight-count chips and the Variable Fonts chip are one group, combined
    // as a union: a family shows if it lands in any selected bucket. Empty set
    // (with Variable off) means no weight filtering.
    @Published var weightFilters: Set<WeightFilter> = AppViewModel.loadWeightFilters() {
        didSet {
            UserDefaults.standard.set(weightFilters.map(Self.encodeWeightFilter), forKey: Self.weightFiltersKey)
        }
    }
    @Published var pinnedOnly: Bool = UserDefaults.standard.bool(forKey: AppViewModel.pinnedOnlyKey) {
        didSet { UserDefaults.standard.set(pinnedOnly, forKey: Self.pinnedOnlyKey) }
    }
    @Published var memoOnly: Bool = UserDefaults.standard.bool(forKey: AppViewModel.memoOnlyKey) {
        didSet { UserDefaults.standard.set(memoOnly, forKey: Self.memoOnlyKey) }
    }
    // Include variable fonts. Unions with weightFilters (see above).
    @Published var variablesOnly: Bool = UserDefaults.standard.bool(forKey: AppViewModel.variablesOnlyKey) {
        didSet { UserDefaults.standard.set(variablesOnly, forKey: Self.variablesOnlyKey) }
    }
    // Which face of each family the *lists* render — the grid cells and the
    // pinned rows. Purely presentational: it picks a face to draw with, and
    // changes nothing about ordering, filtering or what the detail card shows.
    @Published var previewWeight: PreviewWeight = AppViewModel.loadPreviewWeight() {
        didSet { UserDefaults.standard.set(previewWeight.rawValue, forKey: Self.previewWeightKey) }
    }
    // Whether to use animations for major transitions (opening detail, sliding panels).
    @Published var useMotion: Bool = UserDefaults.standard.object(forKey: AppViewModel.useMotionKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(useMotion, forKey: Self.useMotionKey) }
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

    // The Weights filter chips (1 / 2+ / 5+ / 10+). The chips are buckets, not
    // cumulative thresholds — each "+" runs up to the next chip (2+ is 2–4, 5+
    // is 5–9) — so together they partition every family exactly once, with no
    // weight count left unreachable.
    static let weightFilterOptions: [WeightFilter] = [.exactly(1), .range(2, 4), .range(5, 9), .atLeast(10)]

    func toggleWeightFilter(_ option: WeightFilter) {
        if weightFilters.contains(option) { weightFilters.remove(option) }
        else { weightFilters.insert(option) }
    }

    // A family passes the Weights group when it lands in any selected bucket.
    // Weight-count chips describe families by how many discrete faces they ship,
    // so variable fonts are held out of them — their member count is just how
    // many named instances the file happens to declare, which would otherwise
    // pile them into the high buckets. The Variable Fonts chip reaches them.
    func matchesWeightGroup(_ family: FontFamily) -> Bool {
        if weightFilters.isEmpty && !variablesOnly { return true }
        if family.isVariable { return variablesOnly }
        return weightFilters.contains { $0.matches(family.weightCount) }
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
        case .exactly(let n): return "exactly:\(n)"
        case .range(let lo, let hi): return "range:\(lo)-\(hi)"
        case .atLeast(let n): return "atLeast:\(n)"
        }
    }

    private static func decodeWeightFilter(_ s: String) -> WeightFilter? {
        let parts = s.split(separator: ":")
        guard parts.count == 2 else { return nil }
        let arg = String(parts[1])
        switch parts[0] {
        case "exactly": return Int(arg).map { .exactly($0) }
        case "atLeast": return Int(arg).map { .atLeast($0) }
        case "range":
            let r = arg.split(separator: "-")
            guard r.count == 2, let lo = Int(r[0]), let hi = Int(r[1]) else { return nil }
            return .range(lo, hi)
        default: return nil
        }
    }

    private static func loadWeightFilters() -> Set<WeightFilter> {
        let raw = (UserDefaults.standard.array(forKey: weightFiltersKey) as? [String]) ?? []
        // Normalize: only keep values that map to a current chip; stale ones
        // (e.g. the old 3+/5+) are dropped so no orphaned filter sticks.
        return Set(raw.compactMap(decodeWeightFilter).filter { weightFilterOptions.contains($0) })
    }

    // Defaults to .normal: it's the only setting that resolves the same way for
    // variable and static families, so the grid reads consistently out of the box.
    private static func loadPreviewWeight() -> PreviewWeight {
        PreviewWeight(rawValue: UserDefaults.standard.string(forKey: previewWeightKey) ?? "") ?? .normal
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

    // How long the Glyphs grid is held back after the card opens. With motion on
    // this tracks detailOpenSpring's response, so building the grid can't stutter
    // the expand. With motion off there's no spring to protect — but the card
    // should still paint before the grid lands on it, and a tenth of a second
    // buys that without reading as a stall.
    private static let glyphsRevealDelay: TimeInterval = 0.35
    private static let glyphsRevealDelayInstant: TimeInterval = 0.1

    // Bumped on every open/close so a pending reveal can be identified as stale.
    private var detailOpenToken = 0

    // Open the detail for `family`; the glyph grid is shown only after the open
    // animation settles so the expand stays smooth.
    func openDetail(_ family: FontFamily, source: DetailSource) {
        detailSource = source
        detailGlyphsVisible = false
        detailOpenToken += 1
        let token = detailOpenToken
        if selectedFamily == nil {
            if useMotion {
                withAnimation(Self.detailOpenSpring) { selectedFamily = family }
            } else {
                selectedFamily = family
            }
            // Hold the heavy glyphs section back until the card has settled.
            // The token matters: closing and reopening inside the delay window
            // would otherwise let the first open's timer fire into the second
            // one's animation — the exact stutter this delay exists to prevent.
            let delay = useMotion ? Self.glyphsRevealDelay : Self.glyphsRevealDelayInstant
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, token == self.detailOpenToken else { return }
                if self.selectedFamily != nil { self.detailGlyphsVisible = true }
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
        // Retire any reveal still in flight, so it can't land after the close.
        detailOpenToken += 1
        if useMotion {
            withAnimation(Self.detailCloseSpring) { selectedFamily = nil }
        } else {
            selectedFamily = nil
        }
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
        weightFilters = []
        pinnedOnly = false
        memoOnly = false
        variablesOnly = false
        scriptFilter = []
        previewWeight = .normal
        mutedFilter = .shown
        mutedOnly = false
        searchQuery = ""
        selectedFamily = nil
        detailGlyphsVisible = false
        detailSource = .grid
        useMotion = true
    }
}
