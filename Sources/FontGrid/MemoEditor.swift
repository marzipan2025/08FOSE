import SwiftUI
import AppKit

struct MemoEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var lineSpacing: CGFloat = 0
    var textColor: NSColor = .labelColor

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.textBinding = $text
        if textView.string != text {
            setText(text, in: textView)
        } else {
            applyDefaults(to: textView)
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

        init(text: Binding<String>) { self.textBinding = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            textBinding.wrappedValue = tv.string
        }
    }
}
