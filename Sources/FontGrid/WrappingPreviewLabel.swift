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

    func makeNSView(context: Context) -> WrappingPreviewView {
        let view = WrappingPreviewView()
        view.update(text: text, fontName: fontName, fontSize: fontSize)
        return view
    }

    func updateNSView(_ view: WrappingPreviewView, context: Context) {
        view.update(text: text, fontName: fontName, fontSize: fontSize)
    }
}

final class WrappingPreviewView: NSView {
    private var attributed = NSAttributedString(string: "")

    override var isFlipped: Bool { true }

    func update(text: String, fontName: String, fontSize: CGFloat) {
        let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]
        attributed = NSAttributedString(string: text, attributes: attrs)
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
        guard attributed.length > 0 else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        return size.height
    }

    override func draw(_ dirtyRect: NSRect) {
        guard attributed.length > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.labelColor.setFill()

        // We use a flipped view (origin top-left); Core Text draws bottom-up,
        // so flip the context vertically before laying out the frame.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), path, nil
        )
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}
