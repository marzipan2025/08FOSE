import SwiftUI
import AppKit
import CoreText

// The blown-up glyph shown while an inspect key is held.
//
// It is drawn at the *root*, above the wallpaper overlay, rather than inside the
// detail card — the wallpaper is a window-wide blended layer painted over the
// whole app, so anything under it gets tinted, and the point of this view is a
// glyph in unambiguous black or white. FontDetailView publishes where to draw it
// and what to draw via GlyphZoomKey; RootView positions it from that anchor.
struct GlyphZoomPayload {
    let psName: String
    let glyph: CGGlyph
    // The character this glyph maps to, when it has one. Colour bitmap fonts are
    // drawn through it so emoji keep their own colours.
    let character: String?
    let style: GlyphZoomStyle
    // Carried rather than read from the environment: this view renders inside
    // RootView's own body, which is above where preferredColorScheme is applied.
    let scheme: ColorScheme
}

// Where to draw the blow-up and what to draw. Named apart from the protocol's
// own `Value` associated type, which the nested name would otherwise shadow.
struct GlyphZoomRequest {
    let anchor: Anchor<CGRect>
    let payload: GlyphZoomPayload
}

// Published by the detail card, consumed at the root.
struct GlyphZoomKey: PreferenceKey {
    static var defaultValue: GlyphZoomRequest? = nil

    static func reduce(value: inout GlyphZoomRequest?, nextValue: () -> GlyphZoomRequest?) {
        value = value ?? nextValue()
    }
}

struct GlyphZoomView: View {
    let payload: GlyphZoomPayload

    // Corner radius of the detail card, so the blow-up is clipped exactly as it
    // was when it lived inside the card.
    static let cardCornerRadius: CGFloat = 18

    var body: some View {
        Canvas { ctx, size in
            draw(in: ctx, size: size)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
        // Never takes the pointer: rollover on the cells beneath is what drives
        // it, and swallowing events would freeze it on the first glyph (and kill
        // scrolling through the grid).
        .allowsHitTesting(false)
    }

    // Scaled so the font's em box fits the card's shorter side, and positioned by
    // the font's own metrics rather than by the glyph's inked bounds: relative
    // size AND relative position hold across glyphs, so a comma stays a small
    // mark low in the frame while a CJK ideograph fills it.
    private func draw(in ctx: GraphicsContext, size: CGSize) {
        // 12% breathing room per side: accents, swashes and tall marks reach
        // well past the em box, and at a tighter fit they clipped on the card
        // edge.
        let em = min(size.width, size.height) * 0.76
        guard em > 1 else { return }
        let font = CTFontCreateWithName(payload.psName as CFString, em, nil)
        var g = payload.glyph
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advance, 1)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        // Fully opaque, unlike the 0.85 the grid cells use: at 0.85 the outlined
        // glyphs underneath showed through the strokes and the big glyph read as
        // translucent.
        let ink = payload.scheme == .light ? NSColor.black : NSColor.white

        ctx.withCGContext { cg in
            cg.textMatrix = .identity
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            // Centre the font's ascent-to-descent band, then drop it 20pt.
            // Splitting the em box by the ascent:descent ratio (the first
            // attempt) rode high: ascent + descent normally runs past one em, so
            // normalising them into the box under-allocated the ascent and
            // pushed the glyph out through the top. Both metrics are font-level,
            // so relative position still holds across glyphs.
            let baseline = (size.height - (ascent - descent)) / 2 - 20
            let path = CTFontCreatePathForGlyph(font, payload.glyph, nil)

            // Contour: the fill flips to the opposite ink — white on light,
            // black on dark — which alone would sink into the card, so the
            // outline is traced in the accent at 1pt to carry the shape, then
            // every on-curve node gets its own marker. Needs a path, so colour
            // bitmap glyphs fall through to solid.
            if payload.style == .contour, let path {
                let contourInk = payload.scheme == .light ? NSColor.white : NSColor.black
                let accent = Theme.accentInk(payload.scheme)
                cg.saveGState()
                cg.translateBy(x: (size.width - advance.width) / 2, y: baseline)
                cg.addPath(path)
                cg.setFillColor(contourInk.cgColor)
                cg.fillPath()
                cg.addPath(path)
                cg.setStrokeColor(accent.cgColor)
                cg.setLineWidth(1)
                cg.strokePath()
                drawNodeMarkers(path, in: cg, fill: contourInk, edge: accent)
                cg.restoreGState()
            } else if let character = payload.character {
                // Bitmap colour fonts top out at their largest strike (Apple
                // Color Emoji: 160px), so filling the card upscales several
                // times over. No setting recovers detail that isn't there, so
                // drop interpolation and let the pixels show rather than smear
                // them. Only for those glyphs — vector ones scale cleanly and
                // want the default. (Antialiasing is left on: it governs vector
                // edges, not bitmap scaling, and killing it would only jag the
                // rest.)
                if path == nil { cg.interpolationQuality = .none }
                let attr = NSAttributedString(string: character,
                                              attributes: [.font: font, .foregroundColor: ink])
                let line = CTLineCreateWithAttributedString(attr)
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                cg.textPosition = CGPoint(x: (size.width - width) / 2, y: baseline)
                CTLineDraw(line, cg)
            } else {
                var pos = CGPoint(x: (size.width - advance.width) / 2, y: baseline)
                cg.setFillColor(ink.cgColor)
                CTFontDrawGlyphs(font, &g, &pos, 1, cg)
            }
        }
    }

    // A square on each on-curve point of the outline, the way a type editor
    // marks its nodes. Off-curve control points are skipped: they sit away from
    // the contour — outside it through a curve — and without the handle lines a
    // type editor draws to tether them, they read as strays. Dropping them also
    // roughly halves the count on curve-heavy glyphs.
    //
    // A 3×3 core, a 1pt accent edge drawn *outside* it, then a second 1pt ring
    // of the fill colour beyond that — 7 across in total. Core Graphics centres
    // a stroke on its path, so each ring's rect is outset by enough to place the
    // whole width beyond what came before.
    //
    // The core takes the glyph's own fill rather than the edge colour, so a
    // marker reads as a ring rather than a dot.
    private static let nodeMarkerSize: CGFloat = 3
    private static let nodeMarkerEdge: CGFloat = 1

    private func drawNodeMarkers(_ path: CGPath, in cg: CGContext,
                                 fill: NSColor, edge: NSColor) {
        let size = Self.nodeMarkerSize
        let width = Self.nodeMarkerEdge
        var nodes: [CGPoint] = []
        path.applyWithBlock { element in
            let p = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                nodes.append(p[0])
            // Quadratic for TrueType outlines, cubic for CFF — fonts ship both.
            // Either way the last point is where the curve lands on the contour;
            // the ones before it are controls, and are dropped.
            case .addQuadCurveToPoint:
                nodes.append(p[1])
            case .addCurveToPoint:
                nodes.append(p[2])
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        guard !nodes.isEmpty else { return }
        cg.setLineWidth(width)
        for node in nodes {
            let box = CGRect(x: node.x - size / 2, y: node.y - size / 2,
                             width: size, height: size)
            cg.setFillColor(fill.cgColor)
            cg.fill(box)
            cg.setStrokeColor(edge.cgColor)
            cg.stroke(box.insetBy(dx: -width / 2, dy: -width / 2))
            // A second ring in the glyph's own fill, same weight, just beyond
            // the accent one. Where a node sits on the contour the marker's edge
            // would otherwise run into the outline's, both being the accent at
            // the same weight; this keeps a fill-coloured gap between them so
            // the marker reads as detached.
            cg.setStrokeColor(fill.cgColor)
            cg.stroke(box.insetBy(dx: -width * 1.5, dy: -width * 1.5))
        }
    }
}
