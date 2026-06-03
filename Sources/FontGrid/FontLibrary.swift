import AppKit
import CoreText
import Foundation

// Primary script bucket a font is filed under. Single-select per font (the
// font's dominant writing system), chosen by the coverage pipeline below.
enum ScriptCategory: String, CaseIterable, Hashable {
    case korean, japanese, chinese, latin, symbol, other

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
    var weightCount: Int { memberFontNames.count }
    var id: String { name }
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

    func reload() {
        let manager = NSFontManager.shared
        let names = manager.availableFontFamilies
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
                script: Self.classify(psName: sortedNames[0])
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var counts: [ScriptCategory: Int] = [:]
        for family in loadedFamilies { counts[family.script, default: 0] += 1 }
        stats = FontLibraryStats(total: loadedFamilies.count, counts: counts)
        families = loadedFamilies
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
        if has(0x4E00) { return .chinese }                      // 一 (Han, no kana/hangul)
        if distinctiveNonLatinScripts.contains(where: { has($0) }) { return .other }
        if has(0x0041) { return .latin }                        // A
        if has(0x0391) || has(0x0410) { return .other }         // Greek / Cyrillic only
        return .symbol                                          // no real-script letters
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
        if bit(18) || bit(20) { return .chinese }               // GBK / Big5
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
