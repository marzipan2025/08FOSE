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

struct FontFamily: Identifiable, Hashable {
    let name: String
    let memberFontNames: [String]   // PostScript names sorted by weight (light → heavy)
    let script: ScriptCategory      // primary script bucket
    let isVariable: Bool            // backed by an OpenType variable font (has variation axes)
    var weightCount: Int { memberFontNames.count }
    var id: String { name }
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
    var previewFontName: String? {
        if let cached = FontFamily.previewCache[name] { return cached }
        let resolved = FontFamily.resolvePreviewName(memberFontNames)
        FontFamily.previewCache[name] = resolved
        return resolved
    }

    // Resolved once per family; the inputs (installed faces) don't change during
    // a run. Value is Optional so a nil result is cached too.
    private static var previewCache: [String: String?] = [:]

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
    // and variable-font detection all key off, so they stay in agreement.
    static func previewBaseName(for members: [String]) -> String {
        resolvePreviewName(members) ?? members.first ?? ""
    }

    private static func resolvePreviewName(_ members: [String]) -> String? {
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

    init() { reload() }

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

    func reload() {
        let manager = NSFontManager.shared
        let names = manager.availableFontFamilies
        var scriptCache = (UserDefaults.standard.dictionary(forKey: Self.scriptCacheKey) as? [String: String]) ?? [:]
        var variableCache = (UserDefaults.standard.dictionary(forKey: Self.variableCacheKey) as? [String: String]) ?? [:]
        var cacheDirty = false
        func cachedClassify(psName: String) -> ScriptCategory {
            if let raw = scriptCache[psName], let cached = ScriptCategory(rawValue: raw) {
                return cached
            }
            let script = Self.classify(psName: psName)
            scriptCache[psName] = script.rawValue
            cacheDirty = true
            return script
        }
        // Keyed by the PREVIEW face (the Regular the slider/hover actually use),
        // since that's the face detection probes.
        func cachedIsVariable(baseName: String) -> Bool {
            if let raw = variableCache[baseName] { return raw == "1" }
            let variable = Self.detectWeightVariable(psName: baseName)
            variableCache[baseName] = variable ? "1" : "0"
            cacheDirty = true
            return variable
        }
        let loadedFamilies = names.compactMap { family -> FontFamily? in
            guard !family.hasPrefix(".") else { return nil }
            guard let members = manager.availableMembers(ofFontFamily: family) else { return nil }

            // member layout: [postScriptName, faceName, weight(NSNumber), traits(NSNumber)]
            let sortedNames: [String] = members
                .compactMap { row -> (String, Int)? in
                    guard row.count >= 3,
                          let postScript = row[0] as? String,
                          let weight = row[2] as? Int
                    else { return nil }
                    return (postScript, weight)
                }
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }

            guard !sortedNames.isEmpty else { return nil }
            let displayName = decodeFontFamilyName(family)
            return FontFamily(
                name: displayName,
                memberFontNames: sortedNames,
                script: cachedClassify(psName: sortedNames[0]),
                isVariable: cachedIsVariable(baseName: FontFamily.previewBaseName(for: sortedNames))
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if cacheDirty {
            UserDefaults.standard.set(scriptCache, forKey: Self.scriptCacheKey)
            UserDefaults.standard.set(variableCache, forKey: Self.variableCacheKey)
        }

        var counts: [ScriptCategory: Int] = [:]
        for family in loadedFamilies { counts[family.script, default: 0] += 1 }
        stats = FontLibraryStats(total: loadedFamilies.count, counts: counts)
        families = loadedFamilies
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
    private func decodeFontFamilyName(_ name: String) -> String {
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
