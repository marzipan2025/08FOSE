import SwiftUI
import AppKit
import CoreText

struct FontCell: View {
    let family: FontFamily
    let previewText: String
    let fontSize: Double
    var tooltipSuppressed: Bool = false
    var onHoverChange: (Bool) -> Void = { _ in }
    let onTap: () -> Void

    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    // Light mode uses lighter shadows (30% of the dark-mode strength).
    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    private var isFavorited: Bool { favorites.contains(family.name) }
    private var hasMemo: Bool { memos.hasNote(for: family.name) }

    private var cellHeight: CGFloat { Theme.cellHeight(fontSize: fontSize) }

    var body: some View {
        Color.clear
            .frame(height: cellHeight)
            .overlay(alignment: .topLeading) {
                headerRow
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
            }
            .overlay(alignment: .bottomLeading) {
                // CyclingPreviewLabel owns weightIndex state so the 400ms weight
                // cycling re-renders only the preview label, not the whole cell.
                CyclingPreviewLabel(
                    family: family,
                    previewText: previewText,
                    fontSize: fontSize,
                    isHovering: hovering
                )
                .frame(height: fontSize * 1.9)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.cellSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .anchorPreference(key: HoveredCellAnchorKey.self, value: .bounds) {
                hovering ? HoveredCellInfo(id: family.id, anchor: $0) : nil
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    hovering = isHovering
                }
                onHoverChange(isHovering)
            }
            .nativeTooltip(memoTooltip)
    }

    // Hover tooltip: the memo text (up to 16 chars) when one exists, else empty
    // (an empty string shows no tooltip).
    private var memoTooltip: String {
        // No tooltip while it would be hidden behind the Settings blur.
        guard !tooltipSuppressed else { return "" }
        let note = memos.note(for: family.name).replacingOccurrences(of: "#", with: "")
        guard !note.isEmpty else { return "" }
        return note.count > 16 ? String(note.prefix(16)) + "…" : note
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            Text(family.name)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            trailingBadge
        }
    }

    private var borderColor: Color {
        if hasMemo { return Theme.memoAccent }
        if isFavorited { return Theme.accent.opacity(0.45) }
        if hovering { return Theme.borderHover }
        return Theme.border
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if hovering || isFavorited || hasMemo {
            HStack(spacing: 3) {
                if hasMemo {
                    Circle()
                        .fill(Theme.memoAccent)
                        .frame(width: 9, height: 9)
                }
                if hovering || isFavorited {
                    Button { favorites.toggle(family.name) } label: {
                        ZStack {
                            if isFavorited {
                                Circle().fill(Theme.accent)
                            } else {
                                Circle().fill(Color.white.opacity(0.12))
                                Circle().strokeBorder(Color.secondary, lineWidth: 1)
                            }
                        }
                        .frame(width: 9, height: 9)
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 9, height: 9)
                }
            }
            .offset(x: 1, y: 1)
        } else {
            Text(String(format: "%02d", family.weightCount))
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(Theme.weightBadge)
        }
    }
}

// MARK: - Cycling Preview Label

private struct CyclingPreviewLabel: View {
    let family: FontFamily
    let previewText: String
    let fontSize: Double
    let isHovering: Bool

    @State private var weightIndex: Int = 0
    @State private var cycleTask: Task<Void, Never>? = nil

    private var displayedFontName: String {
        guard !family.memberFontNames.isEmpty else { return family.name }
        return family.memberFontNames[weightIndex % family.memberFontNames.count]
    }

    private var resolvedPreviewText: String {
        previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText
    }

    var body: some View {
        FontPreviewLabel(text: resolvedPreviewText, fontName: displayedFontName, fontSize: fontSize)
            .animation(.easeInOut(duration: 0.15), value: weightIndex)
            .onChange(of: isHovering) { hovering in
                if hovering { startCycling() } else { stopCycling() }
            }
            .onDisappear { stopCycling() }
    }

    private func startCycling() {
        cycleTask?.cancel()
        weightIndex = 0
        guard family.memberFontNames.count > 1 else { return }
        cycleTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                weightIndex = (weightIndex + 1) % family.memberFontNames.count
            }
        }
    }

    private func stopCycling() {
        cycleTask?.cancel()
        cycleTask = nil
        weightIndex = 0
    }
}

// MARK: - Preview Label (Core Text)

/// Single-line, tail-truncating font preview drawn with Core Text.
///
/// `NSTextField` and SwiftUI `Text` position the baseline from the PRIMARY
/// font's ascent. So when a Latin-only font (e.g. dotty, Bandwidth BRK) draws
/// Korean through system fallback, the taller fallback glyphs are sheared off
/// at the top. `CTLineGetTypographicBounds` instead reports the line's REAL
/// metrics — including the fallback runs — so the line can be centred by its
/// true height and nothing is clipped, whatever the primary font's ascent is.
struct FontPreviewLabel: NSViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: Double

    func makeNSView(context: Context) -> PreviewTextView {
        let view = PreviewTextView()
        view.configure(text: text, fontName: fontName, fontSize: fontSize)
        return view
    }

    func updateNSView(_ view: PreviewTextView, context: Context) {
        view.configure(text: text, fontName: fontName, fontSize: fontSize)
    }
}

final class PreviewTextView: NSView {
    private var text: String = ""
    private var fontName: String = ""
    private var fontSize: Double = 28
    private var font: NSFont = .systemFont(ofSize: 28)

    func configure(text: String, fontName: String, fontSize: Double) {
        guard text != self.text || fontName != self.fontName || fontSize != self.fontSize else {
            return
        }
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        needsDisplay = true
    }

    override var isFlipped: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]
        NSColor.labelColor.setFill()

        var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let maxWidth = Double(bounds.width)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: attrs))
            if let truncated = CTLineCreateTruncatedLine(line, maxWidth, .end, ellipsis) {
                line = truncated
            }
        }

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let baselineY = (bounds.height - (ascent + descent)) / 2 + descent
        ctx.textPosition = CGPoint(x: 0, y: baselineY)
        CTLineDraw(line, ctx)
    }
}
