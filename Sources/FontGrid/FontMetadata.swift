import Foundation
import AppKit
import CoreText

// One entry in the detail-view info section. Either a labelled value or the
// OpenType feature-tag group. Built in display order by `load(family:)`.
enum InfoEntry: Identifiable {
    case field(label: String, value: String)
    case features([String])
    case scripts([String])

    var id: String {
        switch self {
        case .field(let label, _): return label
        case .features: return "__features"
        case .scripts: return "__scripts"
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

        entries.append(.scripts(supportedScripts(psName: psName)))

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

    // MARK: - Supported scripts (detail readout)

    // Top 3 scripts the font meaningfully covers, in technical terms. Probes a
    // sample of each script's letters and requires a threshold (so a stray glyph
    // or two doesn't list a script). Distinctive scripts (Hangul/Kana/Han/Thai…)
    // rank ahead of Latin/Cyrillic/Greek, which commonly ride along with Latin.
    static func supportedScripts(psName: String) -> [String] {
        guard let font = NSFont(name: psName, size: 12) else { return ["Symbol"] }
        let cs = font.coveredCharacterSet
        func covers(_ samples: [UInt32], _ need: Int) -> Bool {
            var hits = 0
            for v in samples where Unicode.Scalar(v).map({ cs.contains($0) }) == true {
                hits += 1
                if hits >= need { return true }
            }
            return false
        }
        let found = scriptProbes.filter { covers($0.samples, $0.need) }.map { $0.name }
        return found.isEmpty ? ["Symbol"] : Array(found.prefix(3))
    }

    // Ordered preference: distinctive scripts first, Latin/Cyrillic/Greek last.
    private static let scriptProbes: [(name: String, samples: [UInt32], need: Int)] = [
        ("Hangul", [0xAC00,0xB098,0xB2E4,0xB77C,0xB9C8,0xBC14,0xC0AC,0xC544,0xC790,0xCC28,0xCE74,0xD0C0,0xD30C,0xD558], 10),
        ("Kana",   [0x3042,0x3044,0x3046,0x3048,0x304A,0x304B,0x304D,0x304F,0x3051,0x3053,0x3055,0x3057,0x3059,0x305B,0x305D], 11),
        ("Han",    [0x4E00,0x4E8C,0x4E09,0x56DB,0x4E94,0x516D,0x4EBA,0x5927,0x5C0F,0x4E2D,0x5C71,0x5DDD,0x65E5,0x6708,0x6728], 11),
        ("Arabic", [0x0627,0x0628,0x062A,0x062B,0x062C,0x062D,0x062E,0x062F], 6),
        ("Hebrew", [0x05D0,0x05D1,0x05D2,0x05D3,0x05D4,0x05D5,0x05D6,0x05D7], 6),
        ("Thai",   [0x0E01,0x0E02,0x0E04,0x0E07,0x0E08,0x0E09,0x0E0A], 5),
        ("Devanagari", [0x0905,0x0906,0x0907,0x0908,0x0909,0x0915,0x0916], 5),
        ("Khmer",  [0x1780,0x1781,0x1782,0x1783,0x1784], 4),
        ("Lao",    [0x0E81,0x0E82,0x0E84,0x0E87,0x0E88], 4),
        ("Myanmar",[0x1000,0x1001,0x1002,0x1003,0x1004], 4),
        ("Tamil",  [0x0B85,0x0B86,0x0B87,0x0B95,0x0B99], 4),
        ("Tibetan",[0x0F40,0x0F41,0x0F42,0x0F44,0x0F45], 4),
        ("Georgian",[0x10D0,0x10D1,0x10D2,0x10D3,0x10D4], 4),
        ("Armenian",[0x0561,0x0562,0x0563,0x0564,0x0565], 4),
        ("Ethiopic",[0x1200,0x1208,0x1210,0x1218,0x1220], 4),
        ("Latin",  [0x0041,0x0045,0x0049,0x004F,0x0055,0x0052,0x0053,0x0054,0x004E,0x0047], 8),
        ("Cyrillic",[0x0410,0x0411,0x0412,0x0413,0x0414,0x0415,0x0416,0x0417,0x0418,0x041A], 8),
        ("Greek",  [0x0391,0x0392,0x0393,0x0394,0x0395,0x0396,0x0397,0x0398,0x0399,0x039A], 8),
    ]

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
