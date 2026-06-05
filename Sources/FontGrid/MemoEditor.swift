import SwiftUI
import AppKit

struct MemoEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var lineSpacing: CGFloat = 0
    var textColor: NSColor = .labelColor
    // When true, the field shows a tail ellipsis (instead of clipping a line
    // mid-glyph) while it is NOT being edited, and switches to full word-wrap +
    // scrolling while editing so the whole note stays reachable.
    var truncatesWhenInactive: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, truncates: truncatesWhenInactive)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        applyDefaults(to: textView)
        setText(text, in: textView)

        scrollView.documentView = textView

        // Wire the coordinator for the inactive-truncation behavior.
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.fontSize = fontSize
        context.coordinator.lineSpacing = lineSpacing
        context.coordinator.truncates = truncatesWhenInactive
        if truncatesWhenInactive {
            scrollView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.frameChanged),
                name: NSView.frameDidChangeNotification,
                object: scrollView
            )
            DispatchQueue.main.async { context.coordinator.applyTruncationIfNeeded() }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.textBinding = $text
        context.coordinator.fontSize = fontSize
        context.coordinator.lineSpacing = lineSpacing
        context.coordinator.truncates = truncatesWhenInactive
        if textView.string != text {
            setText(text, in: textView)
        } else {
            applyDefaults(to: textView)
        }
        // Re-apply truncation unless the field is currently being edited.
        if truncatesWhenInactive, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { context.coordinator.applyTruncationIfNeeded() }
        }
    }

    // MARK: - Styling

    private func paragraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    private func attributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    private func applyDefaults(to textView: NSTextView) {
        textView.defaultParagraphStyle = paragraphStyle()
        textView.typingAttributes = attributes()
        if let storage = textView.textStorage, storage.length > 0 {
            storage.setAttributes(attributes(), range: NSRange(location: 0, length: storage.length))
        }
    }

    private func setText(_ str: String, in textView: NSTextView) {
        textView.string = str
        applyDefaults(to: textView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>
        var truncates: Bool
        var fontSize: CGFloat = 13
        var lineSpacing: CGFloat = 0
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?

        init(text: Binding<String>, truncates: Bool) {
            self.textBinding = text
            self.truncates = truncates
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            textBinding.wrappedValue = tv.string
        }

        // Editing: show the whole note (word-wrap + scroll).
        func textDidBeginEditing(_ notification: Notification) {
            setTruncating(false)
        }

        // Done editing: collapse back to the fitted, ellipsized view.
        func textDidEndEditing(_ notification: Notification) {
            applyTruncationIfNeeded()
        }

        @objc func frameChanged() {
            // Don't fight the user while they're typing.
            if let tv = textView, tv.window?.firstResponder === tv { return }
            applyTruncationIfNeeded()
        }

        func applyTruncationIfNeeded() {
            guard truncates else { return }
            setTruncating(true)
        }

        private func setTruncating(_ on: Bool) {
            guard let tv = textView, let container = tv.textContainer else { return }
            if on {
                let visible = scrollView?.contentSize.height ?? tv.bounds.height
                let lh = lineHeight()
                let maxLines = max(1, Int(floor((visible + lineSpacing) / lh)))
                container.lineBreakMode = .byTruncatingTail
                container.maximumNumberOfLines = maxLines
                tv.scroll(.zero)
            } else {
                container.lineBreakMode = .byWordWrapping
                container.maximumNumberOfLines = 0
            }
            if let lm = tv.layoutManager {
                lm.ensureLayout(for: container)
            }
            tv.needsDisplay = true
        }

        private func lineHeight() -> CGFloat {
            let font = NSFont.systemFont(ofSize: fontSize)
            return NSLayoutManager().defaultLineHeight(for: font) + lineSpacing
        }
    }
}
