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
    @EnvironmentObject var vm: AppViewModel
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
        // Measure the face actually on screen: a Heavy cut can be taller than the
        // family's lightest, and measuring the wrong one clips it.
        let name = family.previewName(weight: vm.faceWeight, slant: vm.faceSlant)
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
                // Variable fonts with a weight axis sweep that axis smoothly on
                // hover; everything else cycles through its discrete faces. Both
                // own their own animation state so only the preview label
                // re-renders, not the whole cell.
                Group {
                    if let axis = family.weightAxis {
                        VariableWeightPreviewLabel(
                            text: resolvedPreviewText,
                            basePSName: family.previewName(weight: vm.faceWeight, slant: vm.faceSlant),
                            fontSize: fontSize,
                            axis: axis,
                            isHovering: hovering
                        )
                    } else {
                        CyclingPreviewLabel(
                            family: family,
                            previewText: resolvedPreviewText,
                            fontSize: fontSize,
                            isHovering: hovering,
                            restingIndex: family.previewIndex(weight: vm.faceWeight, slant: vm.faceSlant)
                        )
                    }
                }
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
        } else if family.isVariable {
            // Variable fonts get a "VF" mark instead of the weight count, in the
            // same muted color as the number it replaces.
            Text("VF")
                .font(.system(size: Theme.smallSize, weight: .medium))
                .foregroundStyle(Theme.weightBadge)
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
    // Where the cycle sits at rest and returns to — the face chosen by the
    // Preview Weight setting. The sweep itself still runs the whole family in
    // light → heavy order, just starting from here.
    let restingIndex: Int

    @State private var weightIndex: Int? = nil
    @State private var cycleTask: Task<Void, Never>? = nil

    private var displayedFontName: String {
        guard !family.memberFontNames.isEmpty else { return family.name }
        return family.memberFontNames[(weightIndex ?? restingIndex) % family.memberFontNames.count]
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
        weightIndex = restingIndex
        guard family.memberFontNames.count > 1 else { return }
        cycleTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                weightIndex = ((weightIndex ?? restingIndex) + 1) % family.memberFontNames.count
            }
        }
    }

    private func stopCycling() {
        cycleTask?.cancel()
        cycleTask = nil
        // nil, not restingIndex: the resting face then follows the setting live
        // if it changes while this cell is off-hover.
        weightIndex = nil
    }
}

// MARK: - Variable Weight Preview Label

/// Preview for a variable font: at rest it renders at the axis minimum (the
/// lightest face, matching the discrete cell's resting look); on hover it sweeps
/// the weight up to the maximum and back, forever, with eased ends. The sweep
/// runs inside the NSView (its own timer) so SwiftUI isn't re-invoked per frame.
private struct VariableWeightPreviewLabel: NSViewRepresentable {
    let text: String
    let basePSName: String
    let fontSize: Double
    let axis: WeightAxis
    let isHovering: Bool

    func makeNSView(context: Context) -> VariableWeightTextView {
        let view = VariableWeightTextView()
        view.configure(text: text, basePSName: basePSName, fontSize: fontSize, axis: axis)
        view.setHovering(isHovering)
        return view
    }

    func updateNSView(_ view: VariableWeightTextView, context: Context) {
        view.configure(text: text, basePSName: basePSName, fontSize: fontSize, axis: axis)
        view.setHovering(isHovering)
    }

    static func dismantleNSView(_ view: VariableWeightTextView, coordinator: ()) {
        view.setHovering(false)
    }
}

final class VariableWeightTextView: NSView {
    private var text: String = ""
    private var basePSName: String = ""
    private var fontSize: Double = 28
    private var axis = WeightAxis(id: 0, minValue: 0, maxValue: 0, defaultValue: 0)

    private var currentWeight: Double = 0
    private var timer: Timer?
    private var startTime: CFTimeInterval = 0
    // One full up-and-back sweep. Brisk, but still eased at both ends.
    private static let period: CFTimeInterval = 1.6

    func configure(text: String, basePSName: String, fontSize: Double, axis: WeightAxis) {
        guard text != self.text || basePSName != self.basePSName
                || fontSize != self.fontSize || axis != self.axis else { return }
        self.text = text
        self.basePSName = basePSName
        self.fontSize = fontSize
        self.axis = axis
        if timer == nil { currentWeight = axis.minValue }   // resting weight
        needsDisplay = true
    }

    func setHovering(_ hovering: Bool) {
        if hovering { startAnimating() } else { stopAnimating() }
    }

    private func startAnimating() {
        guard timer == nil, axis.maxValue > axis.minValue else { return }
        startTime = CACurrentMediaTime()
        // .common so the sweep keeps ticking while the grid is being scrolled.
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - startTime
        // 0 → 1 → 0 with a cosine ease, so the weight lingers a touch at both
        // extremes instead of snapping around. Starts at min (== resting) so
        // there's no jump when the sweep begins.
        let phase = (1 - cos(2 * Double.pi * elapsed / Self.period)) / 2
        currentWeight = axis.minValue + (axis.maxValue - axis.minValue) * phase
        needsDisplay = true
    }

    private func stopAnimating() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        currentWeight = axis.minValue
        needsDisplay = true
    }

    override var isFlipped: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let font = makeVariationFont(psName: basePSName, size: CGFloat(fontSize),
                                     axisID: axis.id, value: currentWeight)
        PreviewLineRenderer.draw(text: text, font: font, in: bounds, context: ctx)
    }

    deinit { timer?.invalidate() }
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
        PreviewLineRenderer.draw(text: text, font: font, in: bounds, context: ctx)
    }
}

// MARK: - Shared single-line renderer

/// Draws one centred, overflow-clipped line of `text` in `font`, matching the
/// metrics both PreviewTextView (static faces) and VariableWeightTextView
/// (animated variable weight) need, so they stay pixel-identical.
enum PreviewLineRenderer {
    static func draw(text: String, font: NSFont, in bounds: CGRect, context ctx: CGContext) {
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
        ctx.saveGState()
        ctx.clip(to: bounds)

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // Centred baseline, then nudged up 4pt (non-flipped view: +y is up). Pure
        // draw-time offset — the frame/layout is unchanged, the glyphs just sit
        // 4pt higher within their breathing room (top slack absorbs it, no clip).
        let baselineY = (bounds.height - (ascent + descent)) / 2 + descent + 4
        ctx.textPosition = CGPoint(x: 0, y: baselineY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
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
