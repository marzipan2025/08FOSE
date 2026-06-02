import Foundation
import AppKit
import CoreText

// One entry in the detail-view info section. Either a labelled value or the
// OpenType feature-tag group. Built in display order by `load(family:)`.
enum InfoEntry: Identifiable {
    case field(label: String, value: String)
    case features([String])

    var id: String {
        switch self {
        case .field(let label, _): return label
        case .features: return "__features"
        }
    }
}

// Pulls the handful of fields we surface (Format, File size, UPM, Weight,
// Width, Version, Features, Foundry, Copyright) straight out of the font file's
// sfnt tables and CoreText name table. Built once per family and cached.
struct FontMetadata {
    var entries: [InfoEntry] = []

    static let empty = FontMetadata()
    var isEmpty: Bool { entries.isEmpty }

    // MARK: - Loading

    static func load(family: FontFamily) -> FontMetadata {
        guard let psName = family.memberFontNames.first else { return .empty }
        let font = CTFontCreateWithName(psName as CFString, 0, nil)

        let os2 = tableBytes(font, "OS/2")
        let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL

        var entries: [InfoEntry] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { entries.append(.field(label: label, value: value)) }
        }

        add("Format", formatLabel(font: font, url: url))
        add("File size", url.flatMap(fileSize))
        let glyphs = CTFontGetGlyphCount(font)
        add("Glyphs", glyphs > 0 ? glyphCountFormatter.string(from: NSNumber(value: glyphs)) : nil)
        let upm = CTFontGetUnitsPerEm(font)
        add("UPM", upm > 0 ? "\(upm)" : nil)
        if let os2 {
            // A multi-weight family has no single weight to report.
            if family.weightCount <= 1 {
                add("Weight", u16(os2, 4).map(weightLabel))
            }
            add("Width", u16(os2, 6).flatMap(widthName))
        }
        add("Version", name(font, kCTFontVersionNameKey)?
            .replacingOccurrences(of: "Version ", with: ""))

        var tags = Set<String>()
        if let gsub = tableBytes(font, "GSUB") { tags.formUnion(featureTags(gsub)) }
        if let gpos = tableBytes(font, "GPOS") { tags.formUnion(featureTags(gpos)) }
        if !tags.isEmpty { entries.append(.features(tags.sorted())) }

        add("Foundry", name(font, kCTFontManufacturerNameKey))
        add("Copyright", name(font, kCTFontCopyrightNameKey))

        var m = FontMetadata()
        m.entries = entries
        return m
    }

    // MARK: - Table & name helpers

    private static func tableBytes(_ font: CTFont, _ tag: String) -> [UInt8]? {
        guard let data = CTFontCopyTable(font, tableTag(tag), []) as Data? else { return nil }
        return [UInt8](data)
    }

    private static func tableTag(_ s: String) -> CTFontTableTag {
        let b = Array(s.utf8)
        guard b.count == 4 else { return 0 }
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    private static func name(_ font: CTFont, _ key: CFString) -> String? {
        guard let s = CTFontCopyName(font, key) as String?, !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Byte readers (big-endian)

    private static func u16(_ b: [UInt8], _ o: Int) -> Int? {
        guard o >= 0, o + 1 < b.count else { return nil }
        return Int(b[o]) << 8 | Int(b[o + 1])
    }

    // MARK: - Field formatting

    private static func formatLabel(font: CTFont, url: URL?) -> String {
        let ext = url?.pathExtension.lowercased() ?? ""
        if ext == "ttc" { return "TTC" }
        if ext == "dfont" { return "dfont" }
        let hasCFF = tableBytes(font, "CFF ") != nil || tableBytes(font, "CFF2") != nil
        if hasCFF || ext == "otf" { return "OTF" }
        return "TTF"
    }

    private static func weightLabel(_ w: Int) -> String {
        let names: [Int: String] = [
            100: "Thin", 200: "Extra Light", 300: "Light", 400: "Regular",
            500: "Medium", 600: "Semibold", 700: "Bold", 800: "Extra Bold", 900: "Black"
        ]
        if let n = names[w] { return "\(w) · \(n)" }
        return "\(w)"
    }

    private static func widthName(_ w: Int) -> String? {
        let names = ["Ultra-condensed", "Extra-condensed", "Condensed", "Semi-condensed",
                     "Normal", "Semi-expanded", "Expanded", "Extra-expanded", "Ultra-expanded"]
        guard w >= 1, w <= 9 else { return nil }
        return names[w - 1]
    }

    private static let glyphCountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private static func fileSize(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // GSUB/GPOS share a header: FeatureList offset lives at byte 6. Each
    // FeatureRecord is a 4-byte tag + 2-byte offset; we only want the tags.
    private static func featureTags(_ b: [UInt8]) -> [String] {
        guard let flOff = u16(b, 6), let count = u16(b, flOff) else { return [] }
        var tags: [String] = []
        for i in 0..<count {
            let rec = flOff + 2 + i * 6
            guard rec + 4 <= b.count else { break }
            let tag = String(bytes: b[rec..<rec + 4], encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces)
            if let tag, !tag.isEmpty { tags.append(tag) }
        }
        return tags
    }
}

// Human-readable names for common OpenType feature tags, shown as the tooltip
// on each feature tag. Unknown tags just show the raw tag.
enum OpenTypeFeatureNames {
    static func friendly(_ tag: String) -> String? {
        if let exact = table[tag] { return exact }
        if tag.hasPrefix("ss"), tag.count == 4 { return "Stylistic Set \(tag.dropFirst(2))" }
        if tag.hasPrefix("cv"), tag.count == 4 { return "Character Variant \(tag.dropFirst(2))" }
        return nil
    }

    private static let table: [String: String] = [
        "liga": "Standard Ligatures", "dlig": "Discretionary Ligatures",
        "hlig": "Historical Ligatures", "clig": "Contextual Ligatures",
        "calt": "Contextual Alternates", "smcp": "Small Capitals",
        "c2sc": "Caps to Small Caps", "pcap": "Petite Capitals",
        "kern": "Kerning", "frac": "Fractions", "ordn": "Ordinals",
        "lnum": "Lining Figures", "onum": "Oldstyle Figures",
        "pnum": "Proportional Figures", "tnum": "Tabular Figures",
        "sups": "Superscript", "subs": "Subscript", "zero": "Slashed Zero",
        "swsh": "Swash", "salt": "Stylistic Alternates", "titl": "Titling",
        "case": "Case-Sensitive Forms", "ornm": "Ornaments",
        "aalt": "Access All Alternates", "nalt": "Alternate Annotation",
        "hist": "Historical Forms", "init": "Initial Forms", "fina": "Final Forms"
    ]
}
