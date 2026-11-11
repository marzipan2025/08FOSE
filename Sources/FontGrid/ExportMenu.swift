import SwiftUI
import AppKit

// The weight-row ▶︎ export menu (Save / Copy as PNG / SVG), drawn as an in-app
// card rather than an NSMenu. An NSMenu is its own window and floats above the
// window-wide wallpaper overlay, so it never picks up the tint; this card is
// drawn by RootView UNDER the wallpaper — the same layer as the detail card it
// belongs to — and is styled as a pocket-sized version of that card.

/// What the open menu acts on, plus where its ▶︎ button sits (global coords).
struct ExportMenuRequest: Identifiable, Equatable {
    let id = UUID()
    var buttonFrame: CGRect
    var text: String
    var fontName: String
    var baseName: String
    var variation: (axisID: Int, value: Double)?
    var features: SampleFeatures

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct ExportMenuPopup: View {
    @Environment(\.colorScheme) private var colorScheme
    let request: ExportMenuRequest
    let onPick: (WeightArtwork.Action) -> Void
    let onDismiss: () -> Void

    static let titles = ["Save as PNG", "Save as SVG", "Copy as PNG", "Copy as SVG"]
    static let fontSize: CGFloat = Theme.bodySize + 1
    private static let rowHeight: CGFloat = 24
    // Card edge → hover highlight. The text sits textInset further in, so the
    // text's left margin is hPad + textInset — and the right margin matches it.
    // Kept equal: card edge → highlight box = highlight box → text.
    private static let hPad: CGFloat = 7
    private static let vPad: CGFloat = 9
    static let textInset: CGFloat = 7
    private static let separatorBlock: CGFloat = 9
    private static let gap: CGFloat = 4
    private static var height: CGFloat { vPad * 2 + rowHeight * 4 + separatorBlock }
    // Hugs the longest title: equal margins on both sides of the text.
    static let width: CGFloat = {
        let font = NSFont.systemFont(ofSize: fontSize)
        let widest = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(widest) + (hPad + textInset) * 2
    }()

    // Same light-mode easing as the detail card's shadows.
    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let b = request.buttonFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            // Right edge lines up with the button; drops below it, or flips
            // above when there's no room underneath.
            let x = min(max(8, b.maxX - Self.width), proxy.size.width - Self.width - 8)
            let below = b.maxY + Self.gap
            let y = below + Self.height + 8 <= proxy.size.height
                ? below : max(8, b.minY - Self.gap - Self.height)

            ZStack(alignment: .topLeading) {
                // Click anywhere else closes it, like a menu.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                card
                    .offset(x: x, y: y)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Save as PNG", .savePNG)
            row("Save as SVG", .saveSVG)
            Rectangle()
                .fill(colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 4)
                .frame(height: Self.separatorBlock)
            row("Copy as PNG", .copyPNG)
            row("Copy as SVG", .copySVG)
        }
        .padding(.horizontal, Self.hPad)
        .padding(.vertical, Self.vPad)
        .frame(width: Self.width, height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .light ? Color(white: 1.0) : Theme.panelBackground)
                .shadow(color: .black.opacity(0.35 * shadowScale), radius: 6, x: 0, y: 4)
                .shadow(color: .black.opacity(0.45 * shadowScale), radius: 16, x: 0, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(colorScheme == .light ? Color(white: 0.56) : Color.white.opacity(0.8), lineWidth: 1)
        )
    }

    private func row(_ title: String, _ action: WeightArtwork.Action) -> some View {
        ExportMenuRow(title: title, height: Self.rowHeight) { onPick(action) }
    }
}

private struct ExportMenuRow: View {
    @Environment(\.accentColors) private var accent
    let title: String
    let height: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: ExportMenuPopup.fontSize))
                .foregroundStyle(hovering ? AnyShapeStyle(accent.text) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, ExportMenuPopup.textInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Theme.surfaceFillHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .frame(height: height)
        .onHover { hovering = $0 }
    }
}
