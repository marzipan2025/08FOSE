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

/// Editable stand-in for `WrappingPreviewLabel`, swapped in while the detail
/// card's sample is being typed into. An `NSTextView` rather than keystrokes
/// fed to the Core Text view, so Hangul (and every other input method) composes
/// natively. Same font, size and wrap width as the label it replaces; it sizes
/// itself to its laid-out text so the row grows and shrinks as you type.
struct SampleTryEditor: NSViewRepresentable {
    // Characters (grapheme clusters) a try-out sample may hold.
    static let maxLength = 100

    @Binding var text: String
    let fontName: String
    let fontSize: CGFloat
    var variationAxisID: Int? = nil
    var variationWeight: Double? = nil
    var layoutWidth: CGFloat? = nil
    // Fired when the editor gives up focus (click away, ESC via RootView's
    // cascade, or the window losing key).
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> SampleTryTextView {
        let view = SampleTryTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = false
        view.layoutManager?.delegate = view
        view.textColor = .labelColor
        view.string = text
        apply(to: view)
        return view
    }

    func updateNSView(_ view: SampleTryTextView, context: Context) {
        context.coordinator.text = $text
        view.onEnd = onEnd
        apply(to: view)
        // Don't stomp on an in-flight IME composition with our own echo.
        if view.string != text && !view.hasMarkedText() {
            view.string = text
            view.invalidateIntrinsicContentSize()
        }
    }

    private func apply(to view: SampleTryTextView) {
        let font: NSFont
        if let axisID = variationAxisID, let weight = variationWeight {
            font = makeVariationFont(psName: fontName, size: fontSize, axisID: axisID, value: weight)
        } else {
            font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        }
        if view.font != font {
            view.font = font
            view.typingAttributes[.font] = font
            view.invalidateIntrinsicContentSize()
        }
        view.onEnd = onEnd
        view.setLayoutWidth(layoutWidth)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        // Cap at maxLength. Shrinking edits always pass (the seed may already
        // be at the cap). A paste that would overflow is cut to what fits;
        // mid-composition (marked text) an overflowing edit is just refused,
        // so the input method's own bookkeeping isn't disturbed.
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard let replacementString else { return true }
            let current = textView.string as NSString
            let next = current.replacingCharacters(in: range, with: replacementString)
            let limit = SampleTryEditor.maxLength
            if next.count <= limit || next.count <= textView.string.count { return true }
            guard !textView.hasMarkedText() else { return false }
            let room = limit - (textView.string.count - current.substring(with: range).count)
            if room > 0 {
                textView.insertText(String(replacementString.prefix(room)), replacementRange: range)
            } else {
                NSSound.beep()
            }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? SampleTryTextView else { return }
            text.wrappedValue = view.string
            view.invalidateIntrinsicContentSize()
        }
    }
}

final class SampleTryTextView: NSTextView, NSLayoutManagerDelegate {
    var onEnd: (() -> Void)?
    private var layoutWidth: CGFloat?
    private var focusedOnce = false
    // While focused: a click anywhere outside the editor ends the try-out.
    // AppKit leaves first responder alone when the click lands on something
    // that doesn't take focus (the card's background, a SwiftUI button), so
    // without this the caret lingers and keeps single-key shortcuts and ←/→
    // font stepping switched off.
    private var clickMonitor: Any?

    fileprivate func setLayoutWidth(_ width: CGFloat?) {
        guard width != layoutWidth else { return }
        layoutWidth = width
        syncContainerWidth()
    }

    private func syncContainerWidth() {
        let width = (layoutWidth ?? 0) > 0 ? layoutWidth! : bounds.width
        guard width > 0, textContainer?.containerSize.width != width else { return }
        textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if layoutWidth == nil { syncContainerWidth() }
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        var height = layoutManager.usedRect(for: textContainer).height
        // An empty field still keeps one line, so the row doesn't collapse.
        if height <= 0, let font { height = layoutManager.defaultLineHeight(for: font) }
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
    }

    // Take focus as soon as it lands in the window: the click that swapped it
    // in is the click that means "type here". Caret goes to the end.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !focusedOnce else { return }
        focusedOnce = true
        syncContainerWidth()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window.makeFirstResponder(self)
            self.setSelectedRange(NSRange(location: (self.string as NSString).length, length: 0))
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { removeClickMonitor() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became && clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(point) {
                    // Let the click do its own job too (press a button, open
                    // another row's editor); ending is deferred past it.
                    DispatchQueue.main.async {
                        if window.firstResponder === self { window.makeFirstResponder(nil) }
                    }
                }
                return event
            }
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            removeClickMonitor()
            DispatchQueue.main.async { [weak self] in self?.onEnd?() }
        }
        return resigned
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    // MARK: Matching the label's line metrics
    //
    // TextKit and Core Text space lines differently: TextKit adds the font's
    // leading under every line (the last one too) and keeps fractional
    // heights, Core Text rounds each line and drops the trailing leading. On
    // fonts with a large leading (Didot LT Std: 8pt at 40pt) the row jumped
    // taller the moment it turned into an editor. So each line fragment is
    // placed where `WrappingPreviewView`'s Core Text frame puts that line —
    // the same text and width, laid out once per change (it's ≤100 chars).

    private struct CoreTextLines {
        var starts: [Int] = []        // string index each line begins at
        var baselines: [CGFloat] = [] // from the top
        var tops: [CGFloat] = []      // fragment top for each line
        var height: CGFloat = 0
    }
    private var coreTextCache: (string: String, width: CGFloat, font: NSFont?, lines: CoreTextLines)?

    private func coreTextLines(width: CGFloat) -> CoreTextLines? {
        guard let textStorage, textStorage.length > 0, width > 0 else { return nil }
        if let c = coreTextCache, c.width == width, c.font == font, c.string == textStorage.string {
            return c.lines
        }
        let attributed = NSAttributedString(attributedString: textStorage)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let pathHeight: CGFloat = 100_000
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0),
            CGPath(rect: CGRect(x: 0, y: 0, width: width, height: pathHeight), transform: nil), nil)
        guard let ctLines = CTFrameGetLines(frame) as? [CTLine], !ctLines.isEmpty else { return nil }
        var origins = [CGPoint](repeating: .zero, count: ctLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var lines = CoreTextLines()
        for (i, line) in ctLines.enumerated() {
            var ascent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)
            let baseline = pathHeight - origins[i].y
            lines.starts.append(CTLineGetStringRange(line).location)
            lines.baselines.append(baseline)
            lines.tops.append(i == 0 ? 0 : max(lines.tops[i - 1], baseline - ascent))
        }
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        lines.height = ceil(size.height)
        coreTextCache = (textStorage.string, width, font, lines)
        return lines
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        guard let lines = coreTextLines(width: textContainer.containerSize.width) else { return false }
        let start = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).location
        // A line the two engines broke differently keeps TextKit's own metrics.
        guard let i = lines.starts.firstIndex(of: start) else { return false }
        let top = lines.tops[i]
        let bottom = i + 1 < lines.tops.count ? lines.tops[i + 1] : lines.height
        guard bottom > top else { return false }
        lineFragmentRect.pointee.origin.y = top
        lineFragmentRect.pointee.size.height = bottom - top
        lineFragmentUsedRect.pointee.origin.y = top
        lineFragmentUsedRect.pointee.size.height = bottom - top
        baselineOffset.pointee = lines.baselines[i] - top
        return true
    }
}
