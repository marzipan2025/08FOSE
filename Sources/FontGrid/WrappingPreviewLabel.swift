import SwiftUI
import AppKit
import CoreText

/// Multi-line, word-wrapping font preview drawn with Core Text.
///
/// SwiftUI `Text` positions the baseline from the PRIMARY font's ascent, so a
/// font with a tall cap height (or one drawing fallback glyphs) gets sheared at
/// the top. `CTFramesetter` lays out each line by its real run metrics, so the
/// line is sized to its true height and nothing clips, whatever the font is.
struct WrappingPreviewLabel: NSViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    var color: Color? = nil   // nil → default label color
    // When both are set, `fontName` is treated as the base face and its weight
    // axis is overridden to `variationWeight` (drives the detail's Variable
    // slider row). nil → render the face as-is.
    var variationAxisID: Int? = nil
    var variationWeight: Double? = nil
    // Width to lay the text out in, regardless of how wide the view currently
    // is. The detail card's rows pass their FINAL width here so the wrap — and
    // therefore the row's height — is settled on the first frame of the open
    // instead of being recomputed as the card widens. nil keeps the old
    // behaviour of following the view's own bounds.
    var layoutWidth: CGFloat? = nil
    // false draws nothing while still reporting the full height, which is what
    // reserves each row's space during the card's expansion without paying to
    // rasterise the text on every frame of it.
    var isRevealed: Bool = true

    private var nsColor: NSColor {
        color.map { NSColor($0) } ?? .labelColor
    }

    func makeNSView(context: Context) -> WrappingPreviewView {
        let view = WrappingPreviewView()
        view.layoutWidth = layoutWidth
        view.isRevealed = isRevealed
        view.update(text: text, fontName: fontName, fontSize: fontSize, color: nsColor,
                    variationAxisID: variationAxisID, variationWeight: variationWeight)
        return view
    }

    func updateNSView(_ view: WrappingPreviewView, context: Context) {
        view.setLayoutWidth(layoutWidth)
        view.setRevealed(isRevealed)
        view.update(text: text, fontName: fontName, fontSize: fontSize, color: nsColor,
                    variationAxisID: variationAxisID, variationWeight: variationWeight)
    }
}

final class WrappingPreviewView: NSView {
    private var attributed = NSAttributedString(string: "")
    private var text: String = ""
    private var fontName: String = ""
    private var fontSize: CGFloat = 0
    private var color: NSColor = .labelColor
    private var variationAxisID: Int? = nil
    private var variationWeight: Double? = nil

    // The framesetter is immutable per attributed string, but during the detail
    // card's open/close spring this view is resized on EVERY animation frame,
    // and both the measure and the draw used to rebuild one from scratch — the
    // dominant per-frame cost of the transition. Build it once per content
    // change instead. The height measure is memoized per width for the same
    // reason (a layout pass can ask for the intrinsic size more than once).
    private var framesetter: CTFramesetter?
    private var measuredWidth: CGFloat = -1
    private var measuredHeightForWidth: CGFloat = 0
    fileprivate var layoutWidth: CGFloat?
    fileprivate var isRevealed: Bool = true

    // The width the text is actually wrapped in: the pinned one when the caller
    // supplies it, otherwise whatever the view has been given.
    private var effectiveWidth: CGFloat {
        if let layoutWidth, layoutWidth > 0 { return layoutWidth }
        return bounds.width
    }

    fileprivate func setLayoutWidth(_ width: CGFloat?) {
        guard width != layoutWidth else { return }
        layoutWidth = width
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    fileprivate func setRevealed(_ revealed: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        // Height does not change with it — only whether the glyphs are drawn —
        // so the row does not move when the text arrives.
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    func update(text: String, fontName: String, fontSize: CGFloat, color: NSColor,
                variationAxisID: Int? = nil, variationWeight: Double? = nil) {
        if color != self.color {
            self.color = color
            needsDisplay = true
        }
        guard text != self.text || fontName != self.fontName || fontSize != self.fontSize
                || variationAxisID != self.variationAxisID || variationWeight != self.variationWeight else {
            return
        }
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.variationAxisID = variationAxisID
        self.variationWeight = variationWeight
        let font: NSFont
        if let axisID = variationAxisID, let weight = variationWeight {
            font = makeVariationFont(psName: fontName, size: fontSize, axisID: axisID, value: weight)
        } else {
            font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]
        attributed = NSAttributedString(string: text, attributes: attrs)
        framesetter = attributed.length > 0
            ? CTFramesetterCreateWithAttributedString(attributed)
            : nil
        measuredWidth = -1
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    // Height needed to lay out the text at the current width.
    override var intrinsicContentSize: NSSize {
        let width = effectiveWidth > 0 ? effectiveWidth : NSView.noIntrinsicMetric
        guard width > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        let height = measuredHeight(forWidth: width)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != bounds.width
        super.setFrameSize(newSize)
        // With a pinned layout width the wrap cannot change, so a resize is not
        // a reason to re-measure — and during the card's expansion this fires on
        // every frame.
        if widthChanged && layoutWidth == nil { invalidateIntrinsicContentSize() }
        needsDisplay = true
    }

    private func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        guard let framesetter else { return 0 }
        if width == measuredWidth { return measuredHeightForWidth }
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        measuredWidth = width
        measuredHeightForWidth = size.height
        return size.height
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isRevealed,
              let framesetter,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        color.setFill()

        // We use a flipped view (origin top-left); Core Text draws bottom-up,
        // so flip the context vertically before laying out the frame.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let path = CGPath(rect: CGRect(origin: .zero,
                                       size: CGSize(width: effectiveWidth, height: bounds.height)),
                          transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), path, nil
        )
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}
