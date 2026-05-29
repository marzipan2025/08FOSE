import AppKit
import Foundation

struct FontFamily: Identifiable, Hashable {
    let name: String
    let memberFontNames: [String]   // PostScript names sorted by weight (light → heavy)
    let supportsKorean: Bool
    let supportsLatin: Bool
    var weightCount: Int { memberFontNames.count }
    var id: String { name }
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
            let (kor, lat) = Self.scriptSupport(psName: sortedNames[0])
            return FontFamily(
                name: displayName,
                memberFontNames: sortedNames,
                supportsKorean: kor,
                supportsLatin: lat
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func scriptSupport(psName: String) -> (korean: Bool, latin: Bool) {
        guard let font = NSFont(name: psName, size: 12) else {
            return (false, false)
        }
        let cs = font.coveredCharacterSet
        let korean = cs.contains(Unicode.Scalar(0xAC00)!)   // 가
        let latin = cs.contains(Unicode.Scalar(0x0041)!)    // A
        return (korean, latin)
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
