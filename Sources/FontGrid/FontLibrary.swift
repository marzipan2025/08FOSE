import AppKit
import Foundation

struct FontFamily: Identifiable, Hashable {
    let name: String
    let memberFontNames: [String]   // PostScript names sorted by weight (light → heavy)
    let supportsKorean: Bool        // covers a Hangul syllable (가)
    let supportsLatin: Bool         // covers a Latin letter (A)
    let isSymbolFont: Bool          // covers NO real-script letter → dingbat/symbol/emoji
    var weightCount: Int { memberFontNames.count }
    var id: String { name }

    /// A text-bearing font that is not Korean: the "English" filter bucket.
    /// Includes Latin, Cyrillic, Arabic, Hebrew, Indic, CJK… anything with a
    /// real orthography, but excludes Hangul fonts and pure symbol/emoji fonts.
    var isNonKoreanText: Bool { !supportsKorean && !isSymbolFont }
}

@MainActor
final class FontLibrary: ObservableObject {
    @Published private(set) var families: [FontFamily] = []

    init() { reload() }

    func reload() {
        let manager = NSFontManager.shared
        let names = manager.availableFontFamilies
        families = names.compactMap { family -> FontFamily? in
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
            let support = Self.scriptSupport(psName: sortedNames[0])
            return FontFamily(
                name: displayName,
                memberFontNames: sortedNames,
                supportsKorean: support.korean,
                supportsLatin: support.latin,
                isSymbolFont: support.isSymbol
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // One representative LETTER from every major writing system. A font that
    // covers at least one of these carries a real orthography; a font that
    // covers none is a dingbat / symbol / emoji / icon font (e.g. Wingdings,
    // Zapf Dingbats, Apple Color Emoji, Apple Braille).
    private static let scriptLetters: [UInt32] = [
        0x0041, // Latin A
        0x0391, // Greek Α
        0x0410, // Cyrillic А
        0x0531, // Armenian
        0x05D0, // Hebrew א
        0x0627, // Arabic ا
        0x0710, // Syriac
        0x0780, // Thaana
        0x07C0, // NKo
        0x0905, // Devanagari अ
        0x0985, // Bengali
        0x0A05, // Gurmukhi
        0x0A85, // Gujarati
        0x0B05, // Oriya
        0x0B85, // Tamil
        0x0C05, // Telugu
        0x0C85, // Kannada
        0x0D05, // Malayalam
        0x0D85, // Sinhala
        0x0E01, // Thai
        0x0E81, // Lao
        0x0F40, // Tibetan
        0x1000, // Myanmar
        0x10A0, // Georgian
        0x1100, // Hangul jamo ㄱ (conjoining)
        0x1200, // Ethiopic
        0x13A0, // Cherokee
        0x1700, // Tagalog
        0x1780, // Khmer
        0x1820, // Mongolian
        0x1BC0, // Batak
        0x3042, // Hiragana あ
        0x30A2, // Katakana ア
        0x4E00, // CJK 一
        0xAC00, // Hangul syllable 가
    ]

    private static func scriptSupport(psName: String) -> (korean: Bool, latin: Bool, isSymbol: Bool) {
        guard let font = NSFont(name: psName, size: 12) else {
            return (false, false, false)
        }
        let cs = font.coveredCharacterSet
        let korean = cs.contains(Unicode.Scalar(0xAC00)!)   // 가
        let latin = cs.contains(Unicode.Scalar(0x0041)!)    // A
        let hasLetter = scriptLetters.contains { cs.contains(Unicode.Scalar($0)!) }
        return (korean, latin, isSymbol: !hasLetter)
    }

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
