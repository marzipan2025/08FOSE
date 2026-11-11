import AppKit
import CoreText

// ⌘-clicking a glyph in the detail card's grid adds that exact glyph to the end
// of the weight-row samples, whether or not the font maps a character to it —
// small caps, alternates, a letter the font forgot to map, even .notdef.
//
// Text can't hold a glyph, only characters, so each clicked glyph without a
// character of its own gets a stand-in: a private-use character (plane 15)
// remembered here. Wherever the sample is laid out, `GlyphTokens.resolve`
// marks every stand-in with a glyph-info attribute naming the glyph to draw
// instead. Core Text (the sample label, the SVG/PNG export) and TextKit (the
// try-out editor) both honour that attribute — the same key and object work
// for both.

/// One clicked glyph: where it was seen, and how to find it again in another face.
struct GlyphRef: Hashable {
    let psName: String
    let glyph: CGGlyph
    // The glyph's name, which is how another weight's file is searched for
    // the same drawing. nil when the font carries no names.
    let name: String?
    let fileURL: URL?
    let glyphCount: Int
}

enum GlyphTokens {
    private static let firstScalar: UInt32 = 0xF0000
    private static let lastScalar: UInt32 = 0xFFFFD
    // Touched only from the main thread (the detail card and the views that
    // lay its samples out).
    nonisolated(unsafe) private static var refs: [UInt32: GlyphRef] = [:]
    nonisolated(unsafe) private static var tokens: [GlyphRef: UInt32] = [:]

    /// The stand-in character for `glyph` in face `psName`. The same glyph
    /// always gets the same one, for the life of the app.
    static func token(for glyph: CGGlyph, psName: String) -> String? {
        let font = CTFontCreateWithName(psName as CFString, 12, nil)
        let cgFont = CTFontCopyGraphicsFont(font, nil)
        let ref = GlyphRef(psName: psName, glyph: glyph,
                           name: cgFont.name(for: glyph) as String?,
                           fileURL: CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
                           glyphCount: CTFontGetGlyphCount(font))
        if let existing = tokens[ref], let scalar = Unicode.Scalar(existing) { return String(scalar) }
        let next = firstScalar + UInt32(refs.count)
        guard next <= lastScalar, let scalar = Unicode.Scalar(next) else { return nil }
        refs[next] = ref
        tokens[ref] = next
        return String(scalar)
    }

    static func ref(for scalar: Unicode.Scalar) -> GlyphRef? { refs[scalar.value] }

    /// The glyph `ref` stands for, as drawn by `font`.
    ///
    /// Glyph numbers belong to one font file, so another weight is searched by
    /// the glyph's name first. A weight without that glyph shows its .notdef,
    /// which is the honest answer. Unnamed glyphs carry over by number only
    /// within the same file and glyph set (named instances of a variable font).
    static func glyph(_ ref: GlyphRef, in font: CTFont) -> CGGlyph {
        if (CTFontCopyPostScriptName(font) as String) == ref.psName { return ref.glyph }
        if let name = ref.name {
            if name == ".notdef" { return 0 }
            let found = CTFontCopyGraphicsFont(font, nil).getGlyphWithGlyphName(name: name as CFString)
            if found != 0 { return found }
        }
        if let url = ref.fileURL, (CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL) == url,
           CTFontGetGlyphCount(font) == ref.glyphCount {
            return ref.glyph
        }
        return 0
    }

    /// The stand-ins in `string`, as (UTF-16 range, glyph ref).
    static func occurrences(in string: NSString, within range: NSRange? = nil) -> [(NSRange, GlyphRef)] {
        guard !refs.isEmpty else { return [] }
        let span = range ?? NSRange(location: 0, length: string.length)
        var found: [(NSRange, GlyphRef)] = []
        var index = span.location
        while index < NSMaxRange(span) {
            let r = string.rangeOfComposedCharacterSequence(at: index)
            index = NSMaxRange(r)
            // Plane-15 scalars are always a surrogate pair.
            guard r.length == 2,
                  let scalar = string.substring(with: r).unicodeScalars.first,
                  let ref = refs[scalar.value] else { continue }
            found.append((r, ref))
        }
        return found
    }

    /// Mark every stand-in in `text` with the glyph to draw, in the font set on
    /// it. Clears glyph info everywhere else first, so a character typed next
    /// to a stand-in doesn't inherit its glyph.
    ///
    /// Shaping still runs over a glyph put in this way: Playwrite's `ccmp`
    /// would split an Á back into A and an accent, Pretendard's contextual
    /// rules would swap its alternates. So each stand-in is also set in a copy
    /// of its font with the substitution features switched off. The original
    /// font rides along under `baseFontKey`, so text typed next to a stand-in,
    /// which picks up its attributes, gets its own font back here.
    static func resolve(in text: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        guard whole.length > 0 else { return }
        text.removeAttribute(.glyphInfo, range: whole)
        // Put the original font back — but only where the font is still the
        // unshaped copy set below. If the font was changed since (the editor
        // is filled with its text first and gets its font after, which sets
        // .font over everything), the remembered base is stale: restoring it
        // drew the stand-in in the text view's default Helvetica 12.
        text.enumerateAttribute(baseFontKey, in: whole) { base, range, _ in
            guard let base else { return }
            text.enumerateAttributes(in: range) { attrs, sub, _ in
                if let current = attrs[.font] as? NSFont,
                   let unshaped = attrs[unshapedFontKey] as? NSFont,
                   current == unshaped {
                    text.addAttribute(.font, value: base, range: sub)
                }
            }
            text.removeAttribute(baseFontKey, range: range)
            text.removeAttribute(unshapedFontKey, range: range)
        }
        for (range, ref) in occurrences(in: text.string as NSString) {
            guard let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            else { continue }
            let unshaped = unshapedCopy(of: font)
            guard let info = NSGlyphInfo(cgGlyph: glyph(ref, in: font as CTFont), for: unshaped,
                                         baseString: (text.string as NSString).substring(with: range))
            else { continue }
            text.addAttributes([.font: unshaped, baseFontKey: font, unshapedFontKey: unshaped,
                                .glyphInfo: info], range: range)
        }
    }

    static let baseFontKey = NSAttributedString.Key("FOSEGlyphTokenBaseFont")
    // The unshaped copy a stand-in was given, so `resolve` can tell whether
    // its font is still that copy or has been replaced from outside.
    static let unshapedFontKey = NSAttributedString.Key("FOSEGlyphTokenUnshapedFont")

    // Every substitution feature in common use, off. A font ignores the tags
    // it doesn't have. Apple's own AAT fonts (Geeza Pro) shape through
    // tables these switches don't reach; their contextual forms can still
    // turn into another form.
    private static let substitutionTags: [String] = {
        let fixed = """
        aalt abvs akhn blwf blws c2sc calt case ccmp cfar cjct clig cswh dlig dnom \
        fin2 fin3 fina frac half haln hist hlig init isol liga ljmo lnum locl med2 \
        medi mset nukt numr onum ordn pnum pres pstf psts rclt rkrf rlig rphf rvrn \
        salt sinf smcp subs sups swsh tjmo tnum vatu vjmo zero
        """
        return fixed.split(separator: " ").map(String.init)
            + (1...20).map { String(format: "ss%02d", $0) }
            + (1...99).map { String(format: "cv%02d", $0) }
    }()

    private static func unshapedCopy(of font: NSFont) -> NSFont {
        let settings = substitutionTags.map {
            [kCTFontOpenTypeFeatureTag: $0, kCTFontOpenTypeFeatureValue: 0] as [CFString: Any]
        }
        let desc = CTFontDescriptorCreateWithAttributes(
            [kCTFontFeatureSettingsAttribute: settings] as CFDictionary)
        return CTFontCreateCopyWithAttributes(font as CTFont, font.pointSize, nil, desc) as NSFont
    }

    /// `string` laid out in `attributes`, stand-ins marked.
    static func attributed(_ string: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let text = NSMutableAttributedString(string: string, attributes: attributes)
        resolve(in: text)
        return text
    }
}

/// The try-out editor's storage. TextKit swaps the font of any character the
/// font can't draw for a fallback — the stand-ins included, which would point
/// their glyph numbers at the wrong font. This keeps the stand-ins in the
/// editor's own font and re-marks their glyphs on every edit.
final class GlyphTokenTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        // ≤100 characters: re-marking the whole string is cheaper to reason
        // about than tracking the edited paragraph.
        GlyphTokens.resolve(in: self)
        super.processEditing()
    }

    override func fixAttributes(in range: NSRange) {
        let kept = GlyphTokens.occurrences(in: string as NSString, within: range).compactMap { r, _ in
            attribute(.font, at: r.location, effectiveRange: nil).map { (r, $0) }
        }
        super.fixAttributes(in: range)
        for (r, font) in kept { addAttribute(.font, value: font, range: r) }
    }
}
