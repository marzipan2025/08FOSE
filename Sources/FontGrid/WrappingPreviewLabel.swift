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

    private var nsColor: NSColor {
        color.map { NSColor($0) } ?? .labelColor
    }

    func makeNSView(context: Context) -> WrappingPreviewView {
        let view = WrappingPreviewView()
        view.update(text: text, fontName: fontName, fontSize: fontSize, color: nsColor,
                    variationAxisID: variationAxisID, variationWeight: variationWeight)
        return view
    }

    func updateNSView(_ view: WrappingPreviewView, context: Context) {
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
        let width = bounds.width > 0 ? bounds.width : NSView.noIntrinsicMetric
        guard width > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        let height = measuredHeight(forWidth: width)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != bounds.width
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
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
        guard let framesetter,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        color.setFill()

        // We use a flipped view (origin top-left); Core Text draws bottom-up,
        // so flip the context vertically before laying out the frame.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), path, nil
        )
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}
