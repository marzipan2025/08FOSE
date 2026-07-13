import SwiftUI
import AppKit
import CoreText

struct FontCell: View {
    let family: FontFamily
    let previewText: String
    let fontSize: Double
    var tooltipSuppressed: Bool = false
    // Muted fonts render de-emphasized. Applied to the visuals only — the tap
    // area below stays at full hit-testing so a muted cell still opens detail.
    var dimmed: Bool = false
    var onHoverChange: (Bool) -> Void = { _ in }
    let onTap: () -> Void

    @EnvironmentObject var pins: PinsStore
    @EnvironmentObject var memos: MemoStore
    @EnvironmentObject var samples: SampleStore
    @EnvironmentObject var inputSource: InputSourceManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    // Light mode uses lighter shadows (30% of the dark-mode strength).
    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    private var isPinned: Bool { pins.contains(family.name) }
    private var hasMemo: Bool { memos.hasNote(for: family.name) }
    private var hasSpecimen: Bool { samples.hasSample(for: family.name) }

    // The annotation mark: shown when the font has a memo or a custom specimen.
    // Always the memo color; a specimen makes it a square instead of a circle.
    private var hasAnnotationDot: Bool { hasMemo || hasSpecimen }

    private var cellHeight: CGFloat { Theme.cellHeight(fontSize: fontSize) }

    // A custom specimen (if any) replaces the global preview text — same as the
    // detail view, but here the color is left unchanged.
    private var effectivePreviewText: String {
        hasSpecimen ? samples.sample(for: family.name) : previewText
    }

    private var resolvedPreviewText: String {
        inputSource.resolved(effectivePreviewText)
    }

    // Size the preview area to the glyphs' REAL line height (ascent + descent,
    // fallback-aware) plus a little breathing room, rather than a fixed multiple
    // of the font size. A fixed multiple (e.g. 1.9×) leaves slack that is split
    // above and below the centred line, so the bottom gap grew with the size.
    // Matching the real line height keeps the bottom gap small and roughly
    // constant while still fully containing the glyphs (no clipping). Capped so
    // it never crowds the header at large sizes for tall fonts.
    private var previewFrameHeight: CGFloat {
        let name = family.memberFontNames.first ?? family.name
        let line = previewLineHeight(fontName: name, fontSize: fontSize, text: resolvedPreviewText)
        return min(line + 10, cellHeight - 38)
    }

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
                    previewText: resolvedPreviewText,
                    fontSize: fontSize,
                    isHovering: hovering
                )
                .frame(height: previewFrameHeight)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
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
            // Dim the rendered cell, then re-assert a full-opacity hit area below
            // so muted cells stay clickable.
            .opacity(dimmed ? 0.4 : 1)
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
        let note = memos.note(for: family.name)
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
        if isPinned { return Theme.accent.opacity(0.45) }
        if hovering { return Theme.borderHover }
        return Theme.border
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if hovering || isPinned || hasAnnotationDot {
            HStack(spacing: 3) {
                if hasAnnotationDot {
                    Group {
                        if hasSpecimen {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Theme.memoAccent)
                        } else {
                            Circle()
                                .fill(Theme.memoAccent)
                        }
                    }
                    .frame(width: 9, height: 9)
                }
                if hovering || isPinned {
                    Button { pins.toggle(family.name) } label: {
                        ZStack {
                            if isPinned {
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

    var body: some View {
        // previewText arrives already resolved (never empty) from FontCell.
        FontPreviewLabel(text: previewText, fontName: displayedFontName, fontSize: fontSize)
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

/// Single-line font preview drawn with Core Text. Overflow drops whole
/// characters that don't fit (no ellipsis, no half-cut glyphs).
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

        // Single line, no ellipsis and no sliced glyphs: keep only the whole
        // characters that fully fit the available width, dropping the rest
        // instead of cutting the last glyph in half or appending a "…".
        // CTTypesetterSuggestClusterBreak reports how many leading characters fit
        // within maxWidth at a cluster boundary. The view already carries the
        // cell's horizontal padding, so the break sits an even margin in.
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let maxWidth = Double(bounds.width)
        let full = CTLineCreateWithAttributedString(attrString)
        let line: CTLine
        if CTLineGetTypographicBounds(full, nil, nil, nil) > maxWidth {
            let typesetter = CTTypesetterCreateWithAttributedString(attrString)
            let fitCount = CTTypesetterSuggestClusterBreak(typesetter, 0, maxWidth)
            let visible = (text as NSString).substring(to: fitCount)
            line = CTLineCreateWithAttributedString(NSAttributedString(string: visible, attributes: attrs))
        } else {
            line = full
        }
        // Safety net for the rare case of a single glyph wider than the cell:
        // clip to bounds so it can't bleed to the card border.
        ctx.clip(to: bounds)

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // Centred baseline, then nudged up 4pt (non-flipped view: +y is up). Pure
        // draw-time offset — the frame/layout is unchanged, the glyphs just sit
        // 4pt higher within their breathing room (top slack absorbs it, no clip).
        let baselineY = (bounds.height - (ascent + descent)) / 2 + descent + 4
        ctx.textPosition = CGPoint(x: 0, y: baselineY)
        CTLineDraw(line, ctx)
    }
}

// Real typographic height (ascent + descent, fallback-aware) of one line of the
// given text in `fontName` at `fontSize`. Mirrors PreviewTextView.draw's metrics
// so the preview frame can be sized to fit exactly what will be drawn.
private func previewLineHeight(fontName: String, fontSize: Double, text: String) -> CGFloat {
    let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    return ascent + descent
}
