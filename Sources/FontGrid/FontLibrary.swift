import AppKit
import CoreText
import Foundation

// Primary script bucket a font is filed under. Single-select per font (the
// font's dominant writing system), chosen by the coverage pipeline below.
enum ScriptCategory: String, CaseIterable, Hashable {
    case korean, japanese, chinese, latin, symbol, other

    // Buckets offered as filter buttons in the left panel. Chinese and Symbol
    // are still used for classification, but are rarely filtered on, so they're
    // omitted from the UI.
    static let filterable: [ScriptCategory] = [.korean, .japanese, .latin, .other]

    var label: String {
        switch self {
        case .korean:   return "Korean"
        case .japanese: return "Japanese"
        case .chinese:  return "Chinese"
        case .latin:    return "Latin"
        case .symbol:   return "Symbol"
        case .other:    return "Other"
        }
    }

    // Short form for the compact, combined stats label (used when several
    // filters are joined by middle dots).
    var abbreviation: String {
        switch self {
        case .korean:   return "KR"
        case .japanese: return "JP"
        case .chinese:  return "CN"
        case .latin:    return "LTN"
        case .symbol:   return "SYM"
        case .other:    return "ETC"
        }
    }

    // Single-key shortcut for toggling this category's filter.
    var shortcutKey: String {
        switch self {
        case .korean:   return "k"
        case .japanese: return "j"
        case .chinese:  return "c"
        case .latin:    return "l"
        case .symbol:   return "s"
        case .other:    return "o"
        }
    }
}

// One rung of the weight ladder, named the way foundries actually name faces.
// The list is deliberately FLAT — Ultralight is not folded into Thin, Medium is
// not folded into Bold — because the pull-down exists to reach the exact cut a
// family ships. Merging rungs would make some of them unreachable, which is the
// opposite of the point.
//
// Ordered light → heavy, which is the order the pull-down lists them in.
enum FaceWeight: String, CaseIterable, Hashable {
    case thin, ultralight, extraLight, light, book, regular, normal,
         medium, semiBold, bold, extraBold, heavy, black

    var label: String {
        switch self {
        case .thin:       return "Thin"
        case .ultralight: return "Ultralight"
        case .extraLight: return "ExtraLight"
        case .light:      return "Light"
        case .book:       return "Book"
        case .regular:    return "Regular"
        case .normal:     return "Normal"
        case .medium:     return "Medium"
        case .semiBold:   return "SemiBold"
        case .bold:       return "Bold"
        case .extraBold:  return "ExtraBold"
        case .heavy:      return "Heavy"
        case .black:      return "Black"
        }
    }

    // Short form for the compact combined labels, matching ScriptCategory's
    // KR / JP idiom. Every rung is Uppercase+lowercase, with two deliberate
    // exceptions that keep the two easily-confused ones apart at 11pt:
    // Book is all-lowercase "bk", Black is the three-letter "Blk".
    var abbreviation: String {
        switch self {
        case .thin:       return "Th"
        case .ultralight: return "Ul"
        case .extraLight: return "El"
        case .light:      return "Lt"
        case .book:       return "bk"
        case .regular:    return "Rg"
        case .normal:     return "Nm"
        case .medium:     return "Md"
        case .semiBold:   return "Sb"
        case .bold:       return "Bd"
        case .extraBold:  return "Eb"
        case .heavy:      return "Hv"
        case .black:      return "Blk"
        }
    }

    // Lowercased tokens that name this rung inside a face name. Matched as WHOLE
    // space-separated tokens only, never as substrings: "Lt" is Light, but the
    // "lt" inside "Salt" is not. That is the whole reason abbreviations are safe
    // to look for at all.
    var tokens: Set<String> {
        switch self {
        case .thin:       return ["thin", "th", "hairline", "hl"]
        case .ultralight: return ["ultralight", "ultlt", "ul"]
        case .extraLight: return ["extralight", "el", "xlt"]
        case .light:      return ["light", "lt"]
        case .book:       return ["book"]   // "bk" is ambiguous — see FaceTraits
        case .regular:    return ["regular", "rg", "reg", "roman"]
        case .normal:     return ["normal", "nm"]
        case .medium:     return ["medium", "md"]
        case .semiBold:   return ["semibold", "sb", "demibold", "demi"]
        case .bold:       return ["bold", "bd"]
        case .extraBold:  return ["extrabold", "eb", "ultrabold"]
        case .heavy:      return ["heavy", "hv"]
        case .black:      return ["black", "blk"]
        }
    }
}

// The slanted cuts, kept apart from weight because a family can carry both at
// once ("Light Italic") and the two are filtered independently.
enum FaceSlant: String, CaseIterable, Hashable {
    case italic, oblique

    var label: String {
        switch self {
        case .italic:  return "Italic"
        case .oblique: return "Oblique"
        }
    }

    var abbreviation: String {
        switch self {
        case .italic:  return "It"
        case .oblique: return "Obl"
        }
    }

    var tokens: Set<String> {
        switch self {
        case .italic:  return ["italic", "it", "ita"]
        case .oblique: return ["oblique", "obl"]
        }
    }
}

/// What one member face of a family declares about itself, read from its face
/// name (the "Light Italic" half of "Helvetica Neue Light Italic"). Either half
/// may be nil — plenty of faces name neither, and 179 of the 2,803 families on
/// a well-stocked Mac name no weight at all.
struct FaceTraits: Hashable {
    let weight: FaceWeight?
    let slant: FaceSlant?

    /// Parse a face name. Tokens are whole words split on whitespace, and
    /// ADJACENT PAIRS are tried before single tokens so the spaced-out spellings
    /// real families ship — "Demi Bold" (Avenir Next), "Semi Bold" (Nohemi),
    /// "Extra Light" — resolve to one rung instead of matching twice. Without
    /// the pair pass, "Demi Bold" would register as BOTH SemiBold and Bold.
    static func parse(faceName: String, declaredWeight: Int) -> FaceTraits {
        let tokens = faceName.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
        var weight: FaceWeight?
        var slant: FaceSlant?
        var i = 0
        while i < tokens.count {
            let pair = i + 1 < tokens.count ? tokens[i] + tokens[i + 1] : nil
            if let pair, let match = weightMap[pair] {
                if weight == nil { weight = match }
                i += 2
                continue
            }
            let token = tokens[i]
            if let choice = ambiguousTokens[token] {
                if weight == nil {
                    weight = declaredWeight >= ambiguousThreshold ? choice.heavy : choice.light
                }
            } else if let match = weightMap[token] {
                if weight == nil { weight = match }
            } else if let match = slantMap[token] {
                if slant == nil { slant = match }
            }
            i += 1
        }
        return FaceTraits(weight: weight, slant: slant)
    }

    // Tokens two foundries spell identically and mean opposite ends of the
    // ladder by. "Bk" is Book in Adobe's naming table (Avant Garde Gothic Bk)
    // and Black at Sandoll/SD, and no amount of case-matching separates them —
    // both write it exactly "Bk". Picking a side would just choose whose fonts
    // to misfile.
    //
    // The face settles it itself: NSFontManager reports a weight per member,
    // and the two readings do not overlap there. Across a 2,803-family library
    // every "Book" face lands at 5-6 and every "Bk" at 11-14, so the split is
    // wide and 8 sits in the empty middle.
    private static let ambiguousTokens: [String: (light: FaceWeight, heavy: FaceWeight)] = [
        "bk": (light: .book, heavy: .black)
    ]
    private static let ambiguousThreshold = 8

    // Token → rung, flattened once instead of scanning all 13 cases per token.
    private static let weightMap: [String: FaceWeight] = {
        var map: [String: FaceWeight] = [:]
        for w in FaceWeight.allCases {
            for t in w.tokens { map[t] = w }
        }
        return map
    }()

    private static let slantMap: [String: FaceSlant] = {
        var map: [String: FaceSlant] = [:]
        for s in FaceSlant.allCases {
            for t in s.tokens { map[t] = s }
        }
        return map
    }()
}

struct FontFamily: Identifiable, Hashable {
    let name: String
    let memberFontNames: [String]   // PostScript names sorted by weight (light → heavy)
    let memberFaces: [FaceTraits]   // parallel to memberFontNames, parsed at load
    let script: ScriptCategory      // primary script bucket
    let isVariable: Bool            // backed by an OpenType variable font (has variation axes)
    // The face compact previews draw with (see `previewFontName`). Stored, not
    // computed: resolving it opens every member's OS/2 table, so it is settled
    // once at load — through the persisted cache — and carried on the value.
    let previewFace: String?
    var weightCount: Int { memberFontNames.count }
    var id: String { name }

    // Which rungs and slants this family ships. Parsed once when the library
    // loads (face names cannot change during a run), so the Face filter never
    // re-reads a font to answer.
    func has(_ weight: FaceWeight) -> Bool { memberFaces.contains { $0.weight == weight } }
    func has(_ slant: FaceSlant) -> Bool { memberFaces.contains { $0.slant == slant } }
}

// The continuous weight ('wght') axis of a variable font: the animatable range
// the list preview sweeps on hover.
struct WeightAxis: Equatable {
    let id: Int              // OpenType axis tag as a 4-byte int ('wght')
    let minValue: Double
    let maxValue: Double
    let defaultValue: Double
}

/// A copy of the named face `psName` with a single variation axis overridden to
/// `value` — used to render a variable font at an arbitrary (animated or
/// slider-driven) weight. CTFont is toll-free bridged to NSFont.
func makeVariationFont(psName: String, size: CGFloat, axisID: Int, value: Double) -> NSFont {
    let base = CTFontCreateWithName(psName as CFString, size, nil)
    let variation: [NSNumber: NSNumber] = [NSNumber(value: axisID): NSNumber(value: value)]
    let attrs: [String: Any] = [kCTFontVariationAttribute as String: variation]
    let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
    return CTFontCreateCopyWithAttributes(base, size, nil, desc) as NSFont
}

extension FontFamily {
    /// PostScript name to use for compact list previews (e.g. the pins
    /// panel), so the weight is deterministic instead of whatever Core Text
    /// resolves from a bare family name. Rule:
    ///   1. a member whose face is literally named "Regular"
    ///   2. else a member whose OS/2 usWeightClass is 400, then 500
    ///   3. else nil — caller falls back to the family name (previous behavior)
    ///
    /// This used to resolve lazily behind a per-run dictionary, which meant the
    /// answer was computed TWICE for every family on every launch: once here on
    /// first read, and once at load time via `previewBaseName(for:)` — a
    /// separate call that never consulted this cache. Both passes open each
    /// member's OS/2 table. It is now settled once, at load, and stored.
    var previewFontName: String? { previewFace }

    /// Index into `memberFontNames` of the face the grid should draw, given the
    /// Face filter's selection. Nothing is re-sorted and `memberFontNames` is
    /// never reversed, which matters because classification, variable detection,
    /// metadata and Show in Finder all key off its first element.
    ///
    /// The slant narrows WITHIN the chosen weight rather than competing with it:
    /// a family that passes "Light + Italic" by shipping a Light and a separate
    /// Regular Italic has no "Light Italic" to draw, so it falls back to plain
    /// Light. Weight is the axis the user picked from a list; slant is a
    /// refinement on top, and refinements yield.
    func previewIndex(weight: FaceWeight?, slant: FaceSlant?) -> Int {
        guard !memberFontNames.isEmpty else { return 0 }
        guard weight != nil || slant != nil else { return defaultPreviewIndex }
        if let weight {
            if let slant, let i = firstIndex(weight: weight, slant: slant) { return i }
            if let i = firstIndex(weight: weight, slant: nil) { return i }
            if let i = memberFaces.firstIndex(where: { $0.weight == weight }) { return i }
            return defaultPreviewIndex
        }
        // Slant alone: the family's usual face, but slanted, if it has one.
        if let slant, let i = firstIndex(weight: nil, slant: slant) { return i }
        if let slant, let i = memberFaces.firstIndex(where: { $0.slant == slant }) { return i }
        return defaultPreviewIndex
    }

    /// PostScript name for `previewIndex(weight:slant:)`.
    func previewName(weight: FaceWeight?, slant: FaceSlant?) -> String {
        let i = previewIndex(weight: weight, slant: slant)
        return i < memberFontNames.count ? memberFontNames[i] : name
    }

    // Exact (weight, slant) match — nil slant means "explicitly unslanted", so
    // an upright Light is preferred over a Light Italic when Italic is off.
    private func firstIndex(weight: FaceWeight?, slant: FaceSlant?) -> Int? {
        memberFaces.firstIndex { $0.weight == weight && $0.slant == slant }
    }

    // Where the grid rests when the Face filter asks for nothing: the same
    // Regular/400/500 face the pinned rows and variable-font probing use.
    private var defaultPreviewIndex: Int {
        guard let base = previewFontName else { return 0 }
        return memberFontNames.firstIndex(of: base) ?? 0
    }

    /// The variable font's weight axis (min/default/max), or nil when the family
    /// isn't variable or exposes no 'wght' axis (e.g. width- or optical-only).
    /// Drives the list cell's hover weight sweep. Cached like previewFontName.
    var weightAxis: WeightAxis? {
        guard isVariable else { return nil }
        if let cached = FontFamily.weightAxisCache[name] { return cached }
        let base = previewFontName ?? memberFontNames.first ?? name
        let resolved = FontFamily.resolveWeightAxis(base)
        FontFamily.weightAxisCache[name] = resolved
        return resolved
    }

    private static var weightAxisCache: [String: WeightAxis?] = [:]

    // 'wght' OpenType axis tag packed into a big-endian 4-byte integer.
    private static let wghtAxisTag = 0x77676874

    private static func resolveWeightAxis(_ psName: String) -> WeightAxis? {
        let font = CTFontCreateWithName(psName as CFString, 12, nil)
        guard let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] else { return nil }
        for axis in axes {
            guard let id = (axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue,
                  id == wghtAxisTag else { continue }
            let mn = (axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue ?? 0
            let mx = (axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue ?? 0
            let df = (axis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)?.doubleValue ?? mn
            guard mx > mn else { return nil }
            return WeightAxis(id: id, minValue: mn, maxValue: mx, defaultValue: df)
        }
        return nil
    }

    // The face a family previews with — the same base the weight slider/hover
    // and variable-font detection all key off, so they stay in agreement. nil
    // when no member declares itself Regular/400/500; callers pick their own
    // fallback (the grid falls back to the family name, the variable probe to
    // the lightest member). Called only from FontLibrary's load, behind the
    // persisted cache — it opens font tables, so it must not run per read.
    static func resolvePreviewName(_ members: [String]) -> String? {
        // 1. A face named exactly "Regular".
        for ps in members {
            if let font = NSFont(name: ps, size: 12),
               let face = font.fontDescriptor.object(forKey: .face) as? String,
               face.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Regular") == .orderedSame {
                return ps
            }
        }
        // 2. First member at usWeightClass 400, else 500.
        var byWeight: [Int: String] = [:]
        for ps in members {
            if let w = usWeightClass(ps), byWeight[w] == nil { byWeight[w] = ps }
        }
        return byWeight[400] ?? byWeight[500]
    }

    // OS/2 usWeightClass (uint16 big-endian at byte offset 4 of the OS/2 table).
    private static func usWeightClass(_ psName: String) -> Int? {
        let font = CTFontCreateWithName(psName as CFString, 12, nil)
        guard let data = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
              data.count >= 6 else { return nil }
        let base = data.startIndex
        return Int(data[base + 4]) << 8 | Int(data[base + 5])
    }
}

struct FontLibraryStats {
    var total: Int = 0
    var counts: [ScriptCategory: Int] = [:]
    func count(_ category: ScriptCategory) -> Int { counts[category] ?? 0 }
}

@MainActor
final class FontLibrary: ObservableObject {
    @Published private(set) var families: [FontFamily] = []
    @Published private(set) var stats = FontLibraryStats()
    // True from launch until the last family has been filed. The grid reads it
    // to tell "still filling" from "genuinely nothing matches", so the empty
    // state doesn't flash across the first frames.
    @Published private(set) var isLoading = true

    /// What the last refresh actually changed. Published so the UI can react to
    /// a font going away — close a detail card standing on it, drop a hover —
    /// rather than each view polling for it. Carries a fresh id every time, so
    /// two identical changes in a row are still two events.
    struct Change: Equatable {
        let id = UUID()
        var added: [String] = []
        var removed: Set<String> = []
        var isEmpty: Bool { added.isEmpty && removed.isEmpty }
    }
    @Published private(set) var lastChange: Change?

    // The load no longer runs inside init. It used to, which meant the window
    // could not draw its FIRST frame until every installed family had been
    // read — the whole ~2.4s of it on a 2,803-family Mac, all on the main
    // thread. The Task is scheduled on the main actor and so starts after
    // SwiftUI's current render pass: the window is on screen, then the grid
    // fills. See `load()` for how it stays responsive while doing it.
    init() { Task { await load() } }

    // Persisted psName → ScriptCategory rawValue. classify() opens the font
    // file and reads sfnt tables for EVERY family, which is ~40% of the launch
    // path (~250ms for ~500 families, worse cold); a font's classification
    // never changes for a given face, so pay it once per font, not per launch.
    // The key is versioned — bump it if the classification rules change so
    // stale verdicts don't stick. Reset everything wipes it (whole domain).
    private static let scriptCacheKey = "FontGrid.scriptCache.v1"
    // Same idea for variable-font detection: probing the weight axis opens the
    // font's sfnt tables and renders a probe glyph, so cache the yes/no per face
    // across launches. Stored as "1"/"0" strings (like scriptCache) so
    // UserDefaults round-trips cleanly. Bump the version when the rule changes so
    // stale verdicts don't stick — v2 tightened "has any axis" to "has a working
    // weight axis"; v3 judges that by rendered pixels instead of glyph outlines
    // (and so no longer needs to blanket-exclude system fonts).
    private static let variableCacheKey = "FontGrid.variableCache.v3"
    // And the same for the preview face. Resolving it reads the OS/2 table of
    // every member — 166ms per launch for 508 families, ~915ms for 2,803 — and
    // none of that answer can change while a font stays installed.
    //
    // Keyed by member COUNT plus the lightest member's PostScript name, not by
    // family name: installing or removing a face changes the count, which
    // retires the stale entry on its own. (scriptCache keys off the lightest
    // member alone; this is the same idea, one notch stricter, because a
    // family's preview face is the thing a new member is most likely to move.)
    private static let previewCacheKey = "FontGrid.previewCache.v1"

    // How many families are read between yields, and how many are accumulated
    // before the grid is handed a new batch. They are separate numbers on
    // purpose: yielding is what keeps the window responsive (the main actor
    // gets to run events between chunks), while publishing is what costs — each
    // one re-runs the grid's filter chain over everything loaded so far. So
    // yield often and publish rarely.
    private static let chunkSize = 100
    private static let publishEvery = 400

    // Core Text posts this in a burst while a multi-file install is still
    // settling, so the diff waits for the burst to end rather than running per
    // notification. Measured: registering four files at once posts ONE
    // notification, ~0.45s after the call — and by the time it lands the family
    // list is already updated, which is what lets the diff below trust it.
    private static let changeDebounce: UInt64 = 400_000_000   // 0.4s

    // MARK: - Ordering
    //
    // ONE comparator, used to sort the initial load and to re-sort after a
    // refresh. Two comparators that were meant to agree is exactly how a
    // refreshed font ends up filed in the wrong place, so there is only one.
    private static func precedes(_ a: String, _ b: String) -> Bool {
        a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    // A family as the loader sees it: the raw name Core Text reports, and the
    // decoded name the grid sorts, filters and displays by.
    private struct FamilyName {
        let raw: String
        let display: String
    }

    // MARK: - Loading

    /// Read every installed family into `families`, in alphabetical order,
    /// without blocking the main thread for the duration.
    ///
    /// `NSFontManager.availableMembers` is AppKit and not documented
    /// thread-safe, so the per-family read has to stay on the main actor. What
    /// it does not have to be is one uninterruptible block. The family list is
    /// sorted UP FRONT — a Core Text call and a string sort, no font opened —
    /// so families are filed in their final order and appended; the grid grows
    /// downward and never reshuffles what is already on screen.
    func load() async {
        // Let the first frame get drawn before anything else happens.
        await Task.yield()
        isBusy = true

        let ordered = await Self.installedNames()
        var reader = FamilyReader()
        let manager = NSFontManager.shared
        var loaded: [FontFamily] = []
        loaded.reserveCapacity(ordered.count)
        var unpublished = 0

        var index = 0
        while index < ordered.count {
            let end = min(index + Self.chunkSize, ordered.count)
            for i in index..<end {
                guard let family = reader.read(ordered[i], using: manager) else { continue }
                loaded.append(family)
                unpublished += 1
            }
            index = end
            if unpublished >= Self.publishEvery { publish(loaded); unpublished = 0 }
            // Hands the main actor back between chunks: window drags, key
            // presses and the panels' own animations all get their turn while
            // the rest of the library is still being read.
            await Task.yield()
        }

        publish(loaded)
        isLoading = false
        // This pass touched every installed font, so it is the only one that
        // knows which cache entries are still live — see `flush(pruning:)`.
        reader.flush(pruning: true)

        observeFontChanges()
        isBusy = false
        if pendingRefresh { await refreshIfNeeded() }
    }

    /// Every installed family, decoded and sorted, ready to be read in order.
    ///
    /// The Core Text call is the one piece of this that is genuinely
    /// thread-safe (verified: it returns the same list off the main thread and
    /// caches nothing, ~180ms every time on a 2,803-family Mac), so it runs
    /// detached and the main actor stays free for that whole stretch. The
    /// NSFontManager fallback is for a nil that should not happen, and stays
    /// on the main actor where AppKit wants it.
    private static func installedNames() async -> [FamilyName] {
        let raw = await Task.detached(priority: .userInitiated) {
            (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        }.value
        let names = raw.isEmpty ? NSFontManager.shared.availableFontFamilies : raw
        return names
            .filter { !$0.hasPrefix(".") }
            .map { FamilyName(raw: $0, display: decodeFontFamilyName($0)) }
            .sorted { precedes($0.display, $1.display) }
    }

    private func publish(_ list: [FontFamily]) {
        var counts: [ScriptCategory: Int] = [:]
        for family in list { counts[family.script, default: 0] += 1 }
        stats = FontLibraryStats(total: list.count, counts: counts)
        families = list
    }

    // MARK: - Reacting to fonts being installed or removed

    // One library job at a time. Both paths run on the main actor, so nothing
    // races in the memory sense — what this serializes is the LOGIC. A diff run
    // against a half-filled `families` would read the 1,600 families not loaded
    // yet as 1,600 deletions, and that window is only a second or two after
    // launch, which is precisely why it would never show up in testing.
    private var isBusy = false
    private var pendingRefresh = false
    private var debounce: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    private func observeFontChanges() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: kCTFontManagerRegisteredFontsChangedNotification as NSNotification.Name,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fontsChanged() }
        }
    }

    private func fontsChanged() {
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.changeDebounce)
            guard !Task.isCancelled else { return }
            await self?.refreshIfNeeded()
        }
    }

    /// Bring `families` back in line with what is actually installed.
    ///
    /// Safe to call at any time: it does nothing while another job is running
    /// (queuing itself instead), and nothing when the installed set has not
    /// actually changed — which matters, because the notification fires for
    /// registrations the grid never shows. A hidden font being registered posts
    /// it too, and answering that with a visible reload would be a reaction to
    /// nothing.
    func refreshIfNeeded() async {
        guard !isBusy else { pendingRefresh = true; return }
        isBusy = true
        repeat {
            pendingRefresh = false
            await performRefresh()
        } while pendingRefresh
        isBusy = false
    }

    private func performRefresh() async {
        let installed = await Self.installedNames()
        guard !installed.isEmpty else { return }

        let liveNames = Set(installed.map(\.display))
        let loadedNames = Set(families.map(\.name))
        let addedNames = liveNames.subtracting(loadedNames)
        let removed = loadedNames.subtracting(liveNames)
        guard !addedNames.isEmpty || !removed.isEmpty else { return }

        // Only the newly installed families are read. Removals cost nothing —
        // they are a filter over what is already in hand.
        var reader = FamilyReader()
        let manager = NSFontManager.shared
        let toRead = installed.filter { addedNames.contains($0.display) }
        var added: [FontFamily] = []
        var index = 0
        while index < toRead.count {
            let end = min(index + Self.chunkSize, toRead.count)
            for i in index..<end {
                if let family = reader.read(toRead[i], using: manager) { added.append(family) }
            }
            index = end
            await Task.yield()
        }
        // Not pruned here: this pass only looked at the new arrivals, so it has
        // no idea which of the other entries are still live.
        reader.flush(pruning: false)

        // Rebuilt and re-sorted rather than spliced. Splicing means a second
        // piece of code deciding where a name belongs, and a second decision is
        // a chance to disagree with the first; re-sorting reuses `precedes`, so
        // there is nothing to disagree with. It costs ~9ms at 2,803 families.
        //
        // Published in ONE step, which is what keeps the scroll position: the
        // offset lives on the NSScrollView, and the cells are keyed by family
        // name, so an array that is replaced whole leaves the viewport where it
        // was. (Re-running `load()` would not — its partial publishes shrink the
        // content, and the scroller clamps the offset when that happens.)
        var next = families.filter { !removed.contains($0.name) }
        next.append(contentsOf: added)
        next.sort { Self.precedes($0.name, $1.name) }
        publish(next)
        lastChange = Change(added: added.map(\.name).sorted { Self.precedes($0, $1) }, removed: removed)
    }

    // MARK: - Reading one family

    /// Owns the three persisted caches and turns a family name into a
    /// `FontFamily`. Shared by the initial load and every later refresh, so a
    /// font read at launch and the same font read after being reinstalled go
    /// through identical rules.
    @MainActor
    private struct FamilyReader {
        private var script: [String: String]
        private var variable: [String: String]
        private var preview: [String: String]
        private var dirty = false
        private var usedScript: Set<String> = []
        private var usedVariable: Set<String> = []
        private var usedPreview: Set<String> = []

        init() {
            let defaults = UserDefaults.standard
            script = (defaults.dictionary(forKey: scriptCacheKey) as? [String: String]) ?? [:]
            variable = (defaults.dictionary(forKey: variableCacheKey) as? [String: String]) ?? [:]
            preview = (defaults.dictionary(forKey: previewCacheKey) as? [String: String]) ?? [:]
        }

        mutating func read(_ name: FamilyName, using manager: NSFontManager) -> FontFamily? {
            guard let members = manager.availableMembers(ofFontFamily: name.raw) else { return nil }

            // member layout: [postScriptName, faceName, weight(NSNumber), traits(NSNumber)]
            // The face name used to be dropped here; the Face filter needs it,
            // so it is parsed into FaceTraits on the spot. That costs nothing
            // extra — the row is already in hand — and means no font is ever
            // reopened to answer "does this family ship a Light?".
            let sorted: [(name: String, face: FaceTraits)] = members
                .compactMap { row -> (String, FaceTraits, Int)? in
                    guard row.count >= 3,
                          let postScript = row[0] as? String,
                          let weight = row[2] as? Int
                    else { return nil }
                    let faceName = (row.count >= 2 ? row[1] as? String : nil) ?? ""
                    return (postScript, FaceTraits.parse(faceName: faceName, declaredWeight: weight), weight)
                }
                .sorted { $0.2 < $1.2 }
                .map { (name: $0.0, face: $0.1) }

            guard !sorted.isEmpty else { return nil }
            let names = sorted.map(\.name)
            let previewFace = cachedPreviewFace(names)
            return FontFamily(
                name: name.display,
                memberFontNames: names,
                memberFaces: sorted.map(\.face),
                script: cachedScript(names[0]),
                // The probe wants a face in hand, so it takes the lightest
                // member when the family names no Regular.
                isVariable: cachedIsVariable(previewFace ?? names[0]),
                previewFace: previewFace
            )
        }

        private mutating func cachedScript(_ psName: String) -> ScriptCategory {
            usedScript.insert(psName)
            if let raw = script[psName], let cached = ScriptCategory(rawValue: raw) { return cached }
            let resolved = FontLibrary.classify(psName: psName)
            script[psName] = resolved.rawValue
            dirty = true
            return resolved
        }

        // Keyed by the PREVIEW face (the Regular the slider/hover actually use),
        // since that's the face detection probes.
        private mutating func cachedIsVariable(_ baseName: String) -> Bool {
            usedVariable.insert(baseName)
            if let raw = variable[baseName] { return raw == "1" }
            let resolved = FontLibrary.detectWeightVariable(psName: baseName)
            variable[baseName] = resolved ? "1" : "0"
            dirty = true
            return resolved
        }

        // Empty string stores a nil verdict, so "no Regular/400/500 member" is
        // remembered too rather than being re-derived every launch.
        private mutating func cachedPreviewFace(_ members: [String]) -> String? {
            let key = "\(members.count):\(members[0])"
            usedPreview.insert(key)
            if let raw = preview[key] { return raw.isEmpty ? nil : raw }
            let resolved = FontFamily.resolvePreviewName(members)
            preview[key] = resolved ?? ""
            dirty = true
            return resolved
        }

        /// Write the caches back, optionally dropping entries for fonts that
        /// are no longer installed.
        ///
        /// Only a pass that looked at EVERY installed family may prune, since
        /// only it knows which keys are still live — a refresh reads just the
        /// new arrivals and must not mistake the rest for dead.
        ///
        /// Pruning waits until the dead weight outnumbers the live entries 2:1.
        /// Someone who deactivates a font set in the morning and turns it back
        /// on after lunch should find it still warm; the threshold is there to
        /// bound the file, not to keep it minimal.
        mutating func flush(pruning: Bool) {
            if pruning {
                if let p = Self.pruned(script, live: usedScript) { script = p; dirty = true }
                if let p = Self.pruned(variable, live: usedVariable) { variable = p; dirty = true }
                if let p = Self.pruned(preview, live: usedPreview) { preview = p; dirty = true }
            }
            guard dirty else { return }
            let defaults = UserDefaults.standard
            defaults.set(script, forKey: scriptCacheKey)
            defaults.set(variable, forKey: variableCacheKey)
            defaults.set(preview, forKey: previewCacheKey)
        }

        private static func pruned(_ cache: [String: String], live: Set<String>) -> [String: String]? {
            guard !live.isEmpty, cache.count > live.count * 3 else { return nil }
            return cache.filter { live.contains($0.key) }
        }
    }

    // MARK: - Variable-font detection
    //
    // This app's whole variable-font feature set — the "VF" badge, the list
    // cell's hover weight sweep, the detail slider — is WEIGHT based and renders
    // through the family's PREVIEW member (its Regular/400 face). So detection
    // probes that exact face (not the lightest member): a family counts as
    // "variable" only when its preview face
    //   1. exposes a weight ('wght') axis with a real range (rules out
    //      width/optical-only fonts like SD WalkieTalkie VF, and static faces),
    //   2. and DRAWING with that axis at min vs max actually changes the pixels.
    //
    // Rule 2 must go through the same Core Text path the app draws with
    // (CTLine), not CTFontCreatePathForGlyph: SF Pro reports differing glyph
    // OUTLINES for a varied font object, yet renders identically because the
    // system font is substituted at draw time. Comparing inked pixels is what
    // actually predicts "the user will see the weight move" — and it needs no
    // allowlist of system fonts: SF Pro fails it while genuinely-working system
    // faces (SF Compact, New York, Skia, STIX Two Text, …) pass.
    //
    // Probing the preview face is also what makes mixed families behave: Asta
    // Sans bundles a variable Light with a STATIC Regular, so its slider could
    // never work — probing the Regular correctly rejects it, while Roboto Slab
    // (whose Regular is variable) stays in.
    private static let wghtAxisTag = 0x77676874          // 'wght'
    private static let probeSize: CGFloat = 48
    // Relative ink change that counts as "the weight visibly moved". Real
    // variable faces land far above this (the weakest measured is ~+44%);
    // inert ones sit at 0%, so the margin is wide.
    private static let inkChangeThreshold = 0.05

    private static func detectWeightVariable(psName: String) -> Bool {
        guard let range = weightRange(psName) else { return false }      // rule 1
        guard let sample = probeString(psName) else { return false }
        // rule 2: min- vs max-weight renders must differ in inked pixels.
        let lo = inkCoverage(variationCTFont(psName, range.min), sample)
        let hi = inkCoverage(variationCTFont(psName, range.max), sample)
        guard lo > 0 else { return false }
        return abs(hi - lo) / lo > inkChangeThreshold
    }

    // The weight axis's (min, max) for this face, or nil when it has no 'wght'
    // axis or a degenerate range.
    private static func weightRange(_ psName: String) -> (min: Double, max: Double)? {
        let font = CTFontCreateWithName(psName as CFString, probeSize, nil)
        guard let axes = CTFontCopyVariationAxes(font) as? [[String: Any]],
              let wa = axes.first(where: { ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue == wghtAxisTag }),
              let mn = (wa[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue,
              let mx = (wa[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue,
              mx > mn
        else { return nil }
        return (mn, mx)
    }

    // A CTFont copy with the weight axis pinned to `value`.
    private static func variationCTFont(_ psName: String, _ value: Double) -> CTFont {
        let base = CTFontCreateWithName(psName as CFString, probeSize, nil)
        let dict: [NSNumber: NSNumber] = [NSNumber(value: wghtAxisTag): NSNumber(value: value)]
        let attrs: [String: Any] = [kCTFontVariationAttribute as String: dict]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, probeSize, nil, desc)
    }

    // Letters spanning the scripts this app files fonts under. The probe string
    // is built only from the ones the FONT ITSELF covers, so the measurement
    // never lands on a fallback face (which would never vary) — that's what lets
    // a Syriac or Arabic variable font be judged on its own glyphs.
    private static let probeScalars: [UInt32] = [
        0x41, 0x61, 0x42, 0x6F, 0x48, 0x52,             // A a B o H R
        0xAC00, 0xB098, 0xB2E4,                         // 가 나 다
        0x3042, 0x3044, 0x30A2,                         // あ い ア
        0x4E00, 0x4E8C, 0x4E09,                         // 一 二 三
        0x0710, 0x0712, 0x0713,                         // Syriac
        0x0627, 0x0628, 0x062C,                         // Arabic
        0x05D0, 0x05D1, 0x05D2,                         // Hebrew
        0x0391, 0x0392, 0x0393,                         // Greek
        0x0410, 0x0411, 0x0412,                         // Cyrillic
        0x0531, 0x0532,                                 // Armenian
        0x10A0, 0x10A1,                                 // Georgian
        0x0905, 0x0906,                                 // Devanagari
        0x0E01, 0x0E02,                                 // Thai
        0x1200, 0x1201,                                 // Ethiopic
        0x13A0, 0x13A1,                                 // Cherokee
    ]

    /// Up to 8 characters this face both covers AND has real outlines for, as a
    /// string to draw. nil when the font has no such glyph (e.g. a bitmap or
    /// blank face) — such a font can't demonstrate a weight change anyway.
    private static func probeString(_ psName: String) -> String? {
        let font = CTFontCreateWithName(psName as CFString, probeSize, nil)
        var chars: [Character] = []
        for value in probeScalars {
            guard let scalar = Unicode.Scalar(value) else { continue }
            var ch = UniChar(value)                     // every candidate is BMP
            var glyph = CGGlyph(0)
            CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1)
            guard glyph != 0,
                  let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.isEmpty
            else { continue }
            chars.append(Character(scalar))
            if chars.count == 8 { break }
        }
        return chars.isEmpty ? nil : String(chars)
    }

    /// Fraction of inked pixels when `text` is drawn with `font`, using the same
    /// CTLine path the previews draw through. Returns 0 on failure.
    private static func inkCoverage(_ font: CTFont, _ text: String) -> Double {
        let w = 512, h = 96
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceWhite, bytesPerRow: w, bitsPerPixel: 8
        ) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { return 0 }
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(NSColor.black.cgColor)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        ctx.textPosition = CGPoint(x: 8, y: 28)
        CTLineDraw(line, ctx)
        guard let data = rep.bitmapData else { return 0 }
        var inked = 0
        for i in 0..<(w * h) where data[i] < 128 { inked += 1 }
        return Double(inked) / Double(w * h)
    }

    // MARK: - Script classification
    //
    // Coverage-based "primary script" pick. Order matters: the distinctive
    // scripts that do NOT normally ride along with Latin are tested before
    // Latin, so e.g. a Thai or Arabic font (which usually also covers ASCII)
    // is filed under .other rather than .latin. Cyrillic/Greek DO ride with
    // Latin, so they're only treated as .other when no Latin is present.
    private static func classify(psName: String) -> ScriptCategory {
        // The OS/2 code-page bits state which CJK encoding the font targets, and
        // that beats raw coverage: e.g. a Simplified-Chinese font often bundles
        // kana, which the coverage rule below would misread as Japanese.
        if let cjk = codePageCJK(psName) { return cjk }

        guard let font = NSFont(name: psName, size: 12) else { return .other }
        let cs = font.coveredCharacterSet
        func has(_ value: UInt32) -> Bool {
            guard let scalar = Unicode.Scalar(value) else { return false }
            return cs.contains(scalar)
        }

        if has(0xAC00) { return .korean }                       // 가 (Hangul syllable)
        if has(0x3042) || has(0x30A2) { return .japanese }      // あ / ア (kana)
        if has(0x4E00) { return .other }                        // 一 (Han) — Chinese folded into Other
        if distinctiveNonLatinScripts.contains(where: { has($0) }) { return .other }
        if has(0x0041) { return .latin }                        // A
        if has(0x0391) || has(0x0410) { return .other }         // Greek / Cyrillic only
        return .other                                           // no real-script letters — Symbol folded into Other
    }

    // CJK bucket from OS/2 ulCodePageRange1 (only present in OS/2 version ≥ 1).
    // Korean (949/1361) > Japanese (932) > Chinese (936/950) for multi-CJK fonts.
    // Returns nil when no CJK code page is declared, so callers fall back to
    // coverage-based detection (Latin / scripts / symbol).
    private static func codePageCJK(_ psName: String) -> ScriptCategory? {
        let font = CTFontCreateWithName(psName as CFString, 12, nil)
        let tag = ("OS/2".utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) as CTFontTableTag
        guard let data = CTFontCopyTable(font, tag, []) as Data? else { return nil }
        let b = [UInt8](data)
        guard b.count >= 82 else { return nil }                 // version 0 has no code-page range
        let version = Int(b[0]) << 8 | Int(b[1])
        guard version >= 1 else { return nil }
        let cp = UInt32(b[78]) << 24 | UInt32(b[79]) << 16 | UInt32(b[80]) << 8 | UInt32(b[81])
        func bit(_ n: Int) -> Bool { cp & (UInt32(1) << n) != 0 }
        if bit(19) || bit(21) { return .korean }                // Wansung / Johab
        if bit(17) { return .japanese }                         // JIS
        if bit(18) || bit(20) { return .other }                 // GBK / Big5 — Chinese folded into Other
        return nil
    }

    // Representative letters for scripts that generally appear on their own
    // (not bundled into Latin text fonts). Tested before Latin.
    private static let distinctiveNonLatinScripts: [UInt32] = [
        0x0531, // Armenian
        0x05D0, // Hebrew
        0x0627, // Arabic
        0x0710, // Syriac
        0x0780, // Thaana
        0x07C0, // NKo
        0x0905, // Devanagari
        0x0985, // Bengali
        0x0A05, // Gurmukhi
        0x0A85, // Gujarati
        0x0B05, // Oriya
        0x0B85, // Tamil
        0x0C05, // Telugu
        0x0C85, // Kannada
        0x0D05, // Malayalam
        0x0D85, // Sinhala
        0x0F40, // Tibetan
        0x1000, // Myanmar
        0x10A0, // Georgian
        0x1200, // Ethiopic
        0x13A0, // Cherokee
        0x1700, // Tagalog
        0x1780, // Khmer
        0x1820, // Mongolian
        0x1BC0, // Batak
    ]

    // NSFontManager returns Korean (and some other) font family names as
    // slash-separated hex Unicode scalar values, e.g. "/B9CC/B144/C124/CCB4"
    // instead of "만년설체". This decodes them back to readable strings.
    private static func decodeFontFamilyName(_ name: String) -> String {
        guard name.hasPrefix("/") else { return name }
        let parts = name.dropFirst().components(separatedBy: "/")
        let chars = parts.compactMap { hex -> Character? in
            guard let value = UInt32(hex, radix: 16),
                  let scalar = Unicode.Scalar(value) else { return nil }
            return Character(scalar)
        }
        guard chars.count == parts.count else { return name }
        return String(chars)
    }
}
