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

    // Pixel-per-unit factor used when rasterizing to PNG. Starting value —
    // tune after a real export.
    static let pngScale: CGFloat = 20

    // MARK: - Availability

    /// SVG export flattens the text to vector outlines, so it needs at least one
    /// non-whitespace character of `text` to have a non-empty outline in the
    /// actual font (no fallback substitution). False for empty/whitespace text,
    /// for text the font doesn't cover, and for bitmap/sbix or COLR color fonts
    /// (e.g. Toss Face Font, Apple Color Emoji) whose glyphs carry no outline.
    /// Kept cheap (BMP fast-path, capped scan) so it can drive a button's
    /// enabled state on every render.
    static func canExportSVG(text: String, fontName: String) -> Bool {
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

    /// PNG export rasterizes the same flattened outlines as SVG, so today it has
    /// exactly the same requirement. Kept as its own entry point so the button
    /// can require BOTH formats explicitly (and so this can diverge later if PNG
    /// ever gains a bitmap-rendering path).
    static func canExportPNG(text: String, fontName: String) -> Bool {
        canExportSVG(text: text, fontName: fontName)
    }

    /// The export button is enabled only when BOTH SVG and PNG can be produced;
    /// if either format is unavailable the weight isn't exportable.
    static func canExport(text: String, fontName: String) -> Bool {
        canExportSVG(text: text, fontName: fontName)
            && canExportPNG(text: text, fontName: fontName)
    }

    // MARK: - SVG / PNG generation

    /// Build an SVG document for `text` rendered in `fontName`, glyphs flattened
    /// to a single filled `<path>`. Honors `\n` as line breaks. Returns nil when
    /// no outlines result (so callers can no-op gracefully).
    static func svg(text: String, fontName: String, fill: String = "#000000") -> String? {
        guard let (path, size) = flatten(text: text, fontName: fontName) else { return nil }
        let w = fmt(size.width), h = fmt(size.height)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <path d="\(pathData(path))" fill="\(fill)"/>
        </svg>
        """
    }

    /// Rasterize the same flattened path used by `svg(...)` to a transparent
    /// PNG, filled with `color`. Returns nil when there are no outlines.
    static func pngData(text: String, fontName: String, color: NSColor, scale: CGFloat = pngScale) -> Data? {
        guard let (path, size) = flatten(text: text, fontName: fontName) else { return nil }
        let w = max(1, Int(ceil(size.width * scale)))
        let h = max(1, Int(ceil(size.height * scale)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = gc
        let cg = gc.cgContext
        cg.scaleBy(x: scale, y: scale)
        // The flattened path is in SVG (y-down) space starting at (0, 0); flip
        // vertically so it lands right-side-up in CG's y-up bitmap.
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        let rgb = color.usingColorSpace(.sRGB) ?? color
        cg.setFillColor(rgb.cgColor)
        cg.addPath(path)
        cg.fillPath()
        return rep.representation(using: .png, properties: [:])
    }

    // Flatten the rendered text to a single CGPath in SVG coords (origin at
    // top-left, y growing down), along with its bounding-box size. Shared by
    // the SVG and PNG paths.
    private static func flatten(text: String, fontName: String) -> (path: CGPath, size: CGSize)? {
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
        let out = CGMutablePath()
        out.addPath(combined, transform: flip)
        return (out, CGSize(width: box.width, height: box.height))
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
