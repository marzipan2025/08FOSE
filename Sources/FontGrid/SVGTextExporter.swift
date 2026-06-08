import AppKit
import CoreText

// Renders a string in a given font and flattens the glyphs to vector outlines,
// producing a self-contained SVG (a single <path>) that looks identical on
// machines without the font installed. Used by the font-detail weight rows to
// export each weight's sample text.
enum SVGTextExporter {
    // Em size the glyph outlines are built at — this is the SVG's coordinate
    // scale. Kept small (12.8) so the exported width/height stay compact; the
    // SVG is unitless/scalable regardless.
    static let exportFontSize: CGFloat = 12.8

    // MARK: - Availability

    /// True when `text` rendered in `fontName` would yield at least one vector
    /// outline — i.e. SVG export is meaningful. False for empty/whitespace text
    /// and for bitmap/color fonts (e.g. Apple Color Emoji) whose glyphs carry no
    /// path. Kept cheap (BMP fast-path, capped scan) so it can drive a button's
    /// enabled state on every render.
    static func canExport(text: String, fontName: String) -> Bool {
        let font = CTFontCreateWithName(fontName as CFString, exportFontSize, nil)
        var scanned = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace { continue }
            scanned += 1
            if scanned > 16 { break }   // bail on long no-outline (emoji) text
            if let g = glyph(for: scalar, in: font),
               let p = CTFontCreatePathForGlyph(font, g, nil), !p.isEmpty {
                return true
            }
        }
        return false
    }

    // MARK: - SVG generation

    /// Build an SVG document for `text` rendered in `fontName`, glyphs flattened
    /// to a single filled `<path>`. Honors `\n` as line breaks. Returns nil when
    /// no outlines result (so callers can no-op gracefully).
    static func svg(text: String, fontName: String, fill: String = "#000000") -> String? {
        let font = CTFontCreateWithName(fontName as CFString, exportFontSize, nil)
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)

        // Accumulate all glyph outlines in font (y-up) space.
        let combined = CGMutablePath()
        let lines = text.components(separatedBy: "\n")
        for (i, lineStr) in lines.enumerated() {
            let baselineY = -CGFloat(i) * lineHeight   // each line sits lower (y-up → negative)
            let ctLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: lineStr, attributes: [.font: font]))
            guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else { continue }
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let runFont = self.runFont(of: run, fallback: font)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for j in 0..<count {
                    guard let gp = CTFontCreatePathForGlyph(runFont, glyphs[j], nil) else { continue }
                    let t = CGAffineTransform(translationX: positions[j].x,
                                              y: positions[j].y + baselineY)
                    combined.addPath(gp, transform: t)
                }
            }
        }
        guard !combined.isEmpty else { return nil }

        let box = combined.boundingBoxOfPath
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { return nil }

        // Flip y-up (Core Text) → y-down (SVG) and shift the artwork to start at
        // (0, 0) so width/height == the bounding box.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -box.minX, ty: box.maxY)
        let svgPath = CGMutablePath()
        svgPath.addPath(combined, transform: flip)

        let w = fmt(box.width), h = fmt(box.height)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <path d="\(pathData(svgPath))" fill="\(fill)"/>
        </svg>
        """
    }

    // MARK: - Helpers

    private static func runFont(of run: CTRun, fallback: CTFont) -> CTFont {
        let attrs = CTRunGetAttributes(run) as NSDictionary
        if let f = attrs[kCTFontAttributeName as String] {
            return f as! CTFont
        }
        return fallback
    }

    // Glyph id for a single scalar in `font` (nil if the font lacks it). BMP via
    // the batch API; astral planes via a one-glyph CTLine.
    private static func glyph(for scalar: Unicode.Scalar, in font: CTFont) -> CGGlyph? {
        if scalar.value <= 0xFFFF {
            var ch = UniChar(scalar.value)
            var g = CGGlyph(0)
            CTFontGetGlyphsForCharacters(font, &ch, &g, 1)
            return g == 0 ? nil : g
        }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(scalar), attributes: [.font: font]))
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1 else { return nil }
        let run = runs[0]
        guard CTRunGetGlyphCount(run) == 1 else { return nil }
        var g = CGGlyph(0)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &g)
        return g == 0 ? nil : g
    }

    // Serialize a CGPath to an SVG path "d" attribute (absolute commands).
    private static func pathData(_ path: CGPath) -> String {
        var d = ""
        path.applyWithBlock { ptr in
            let e = ptr.pointee
            switch e.type {
            case .moveToPoint:
                d += "M\(fmt(e.points[0].x)) \(fmt(e.points[0].y)) "
            case .addLineToPoint:
                d += "L\(fmt(e.points[0].x)) \(fmt(e.points[0].y)) "
            case .addQuadCurveToPoint:
                d += "Q\(fmt(e.points[0].x)) \(fmt(e.points[0].y)) \(fmt(e.points[1].x)) \(fmt(e.points[1].y)) "
            case .addCurveToPoint:
                d += "C\(fmt(e.points[0].x)) \(fmt(e.points[0].y)) \(fmt(e.points[1].x)) \(fmt(e.points[1].y)) \(fmt(e.points[2].x)) \(fmt(e.points[2].y)) "
            case .closeSubpath:
                d += "Z "
            @unknown default:
                break
            }
        }
        return d.trimmingCharacters(in: .whitespaces)
    }

    private static func fmt(_ v: CGFloat) -> String { String(format: "%.2f", v) }
}
