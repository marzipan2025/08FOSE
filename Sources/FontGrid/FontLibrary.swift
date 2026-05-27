import AppKit
import Foundation

struct FontFamily: Identifiable, Hashable {
    let name: String
    let memberFontNames: [String]   // PostScript names sorted by weight (light → heavy)
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
            return FontFamily(name: family, memberFontNames: sortedNames)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
