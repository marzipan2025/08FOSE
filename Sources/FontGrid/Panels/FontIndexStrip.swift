import SwiftUI
import AppKit
import CoreText

// One stop on the index strip: a label and the first family in the list that
// files under it.
struct FontIndexEntry: Identifiable, Equatable {
    let label: String
    let familyID: FontFamily.ID
    var id: String { label }
}

enum FontIndex {
    // Double consonants file under their plain form, as in a phone book, so
    // the strip never spends a stop on ㄲ.
    private static let choseong: [String] = [
        "ㄱ", "ㄱ", "ㄴ", "ㄷ", "ㄷ", "ㄹ", "ㅁ", "ㅂ", "ㅂ", "ㅅ",
        "ㅅ", "ㅇ", "ㅈ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// Which stop a family name files under: a digit, a Latin letter, a Hangul
    /// initial, or "#" for anything else (kana, Hanzi, symbols).
    static func label(for name: String) -> String {
        guard let first = name.first else { return "#" }
        let folded = String(first)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .uppercased()
        guard let scalar = folded.unicodeScalars.first else { return "#" }
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A:
            return String(scalar)
        case 0xAC00...0xD7A3:
            return choseong[Int(scalar.value - 0xAC00) / 588]
        default:
            return "#"
        }
    }

    /// One entry per label, in list order. Taken from the list itself rather
    /// than a fixed alphabet, so the strip follows the active filters and the
    /// locale's collation, and never offers a stop with nothing behind it.
    static func entries(for families: [FontFamily]) -> [FontIndexEntry] {
        var seen = Set<String>()
        var result: [FontIndexEntry] = []
        for family in families {
            let label = label(for: family.name)
            if seen.insert(label).inserted {
                result.append(FontIndexEntry(label: label, familyID: family.id))
            }
        }
        return result
    }

    /// Compresses entries into rows that fit `height`, as A··E··I··M··: every
    /// Nth label stays, and up to two dots stand in for those skipped. Each
    /// script run restarts the count, so A and ㄱ always show. N is the smallest
    /// that leaves the rows room to breathe, so taller windows show more labels.
    static func layout(_ entries: [FontIndexEntry], height: CGFloat) -> [FontIndexRow] {
        guard !entries.isEmpty, height > 0 else { return [] }
        // A short list has nothing worth hiding.
        let firstStride = entries.count <= 12 ? 1 : 2
        var rows = rows(entries, stride: firstStride)
        var stride = firstStride
        while contentHeight(rows) * roomyScale > height, stride < entries.count {
            stride += 1
            rows = self.rows(entries, stride: stride)
        }
        let scale = min(height / contentHeight(rows), maxScale)
        return rows.map {
            FontIndexRow(id: $0.id, label: $0.label, range: $0.range, height: $0.height * scale)
        }
    }

    private static let labelHeight: CGFloat = 14
    private static let dotHeight: CGFloat = 6
    private static let roomyScale: CGFloat = 1.3
    private static let maxScale: CGFloat = 1.5

    private static func contentHeight(_ rows: [FontIndexRow]) -> CGFloat {
        rows.reduce(0) { $0 + $1.height }
    }

    private static func rows(_ entries: [FontIndexEntry], stride step: Int) -> [FontIndexRow] {
        var rows: [FontIndexRow] = []
        var runStart = 0
        while runStart < entries.count {
            let kind = script(of: entries[runStart].label)
            var runEnd = runStart + 1
            while runEnd < entries.count, script(of: entries[runEnd].label) == kind { runEnd += 1 }

            for index in stride(from: runStart, to: runEnd, by: step) {
                rows.append(FontIndexRow(id: rows.count, label: entries[index].label,
                                         range: index..<(index + 1), height: labelHeight))
                let hiddenEnd = min(index + step, runEnd)
                let hidden = hiddenEnd - (index + 1)
                let dots = min(hidden, 2)
                for dot in 0..<dots {
                    // Shares the skipped entries out between the dots, so
                    // every one of them can still be reached by rolling over.
                    let lower = index + 1 + hidden * dot / dots
                    let upper = index + 1 + hidden * (dot + 1) / dots
                    rows.append(FontIndexRow(id: rows.count, label: nil,
                                             range: lower..<upper, height: dotHeight))
                }
            }
            runStart = runEnd
        }
        return rows
    }

    private enum Script { case digit, latin, hangul, other }

    private static func script(of label: String) -> Script {
        guard let value = label.unicodeScalars.first?.value else { return .other }
        switch value {
        case 0x30...0x39: return .digit
        case 0x41...0x5A: return .latin
        case 0x3131...0x314E: return .hangul
        default: return .other
        }
    }
}

// One row of the strip: a label, or a dot (nil) standing in for skipped entries.
// `range` is the entries it covers, as indices into the full list.
struct FontIndexRow: Identifiable {
    let id: Int
    let label: String?
    let range: Range<Int>
    let height: CGFloat
}

// The phone-book index between the left panel and the grid. Rolling over it
// scrolls the grid to the entry under the pointer and reports that entry, so
// the grid can show which one it is.
struct FontIndexStrip: View {
    static let width: CGFloat = 28

    // Only the middle of the height is used.
    private static let heightShare: CGFloat = 0.6
    // The strip lies on the way from the left panel to the grid. Waiting this
    // long before the first jump lets the pointer cross it without moving the
    // list; once engaged, jumps follow the pointer immediately.
    private static let engageDelay: Double = 0.12

    let entries: [FontIndexEntry]
    // False while something covers the grid. AppKit tracking ignores what is
    // drawn on top, so the tracker has to be taken away instead.
    let interactive: Bool
    // The entry rolled over, or nil once the pointer leaves.
    let onActive: (FontIndexEntry?) -> Void

    @State private var pointerEntry: FontIndexEntry? = nil
    @State private var engaged = false
    @State private var lastReported: String? = nil
    @State private var engageToken = 0

    var body: some View {
        GeometryReader { geo in
            let rows = FontIndex.layout(entries, height: geo.size.height * Self.heightShare)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
            .frame(width: Self.width)
            .contentShape(Rectangle())
            .background {
                if interactive {
                    IndexPointerTracker(
                        onMove: { y in pointerMoved(to: entry(atY: y, in: rows)) },
                        onExit: { pointerLeft() }
                    )
                }
            }
            .onTapGesture { location in
                guard let hit = entry(atY: location.y, in: rows) else { return }
                engaged = true
                pointerEntry = hit
                report(hit)
            }
            .frame(width: Self.width, height: geo.size.height)
        }
        .frame(width: Self.width)
        // Switching apps with the pointer on the strip sends no hover end, which
        // would leave the large label stranded over the list.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            pointerLeft()
        }
    }

    @ViewBuilder
    private func rowView(_ row: FontIndexRow) -> some View {
        let active = isActive(row)
        Group {
            if let label = row.label {
                Text(label)
                    .font(.system(size: Theme.sectionHeaderSize, weight: .medium))
                    .lineLimit(1)
            } else {
                Circle().frame(width: 2, height: 2)
            }
        }
        .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
        .frame(width: Self.width, height: row.height)
    }

    private func isActive(_ row: FontIndexRow) -> Bool {
        guard engaged, let pointerEntry, let index = entries.firstIndex(of: pointerEntry) else { return false }
        return row.range.contains(index)
    }

    private func entry(atY y: CGFloat, in rows: [FontIndexRow]) -> FontIndexEntry? {
        guard !rows.isEmpty else { return nil }
        var top: CGFloat = 0
        for row in rows {
            if y < top + row.height {
                let fraction = max(0, (y - top) / row.height)
                let offset = min(Int(fraction * CGFloat(row.range.count)), row.range.count - 1)
                return entries[row.range.lowerBound + offset]
            }
            top += row.height
        }
        return entries[rows[rows.count - 1].range.upperBound - 1]
    }

    private func pointerMoved(to entry: FontIndexEntry?) {
        pointerEntry = entry
        if engaged {
            if let entry { report(entry) }
            return
        }
        engageToken += 1
        let token = engageToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.engageDelay) {
            guard token == engageToken, let current = pointerEntry else { return }
            engaged = true
            report(current)
        }
    }

    private func pointerLeft() {
        engageToken += 1
        pointerEntry = nil
        engaged = false
        lastReported = nil
        onActive(nil)
    }

    private func report(_ entry: FontIndexEntry) {
        guard entry.label != lastReported else { return }
        lastReported = entry.label
        onActive(entry)
    }
}

// Reports the pointer over the strip. Built on NSTrackingArea, and backed by a
// poll of the real pointer position while inside: the large label must never be
// left behind, and a tracking exit alone can go missing when the pointer leaves
// fast while the grid is busy drawing the fonts it just jumped to. hitTest
// returns nil, so clicks still reach the strip.
private struct IndexPointerTracker: NSViewRepresentable {
    let onMove: (CGFloat) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onMove = onMove
        view.onExit = onExit
    }

    final class TrackingView: NSView {
        var onMove: ((CGFloat) -> Void)?
        var onExit: (() -> Void)?
        private var area: NSTrackingArea?
        private var poll: Timer?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let new = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
                owner: self, userInfo: nil)
            addTrackingArea(new)
            area = new
        }

        override func mouseEntered(with event: NSEvent) { pointerInside(event) }
        override func mouseMoved(with event: NSEvent) { pointerInside(event) }
        override func mouseExited(with event: NSEvent) { pointerGone() }

        private func pointerInside(_ event: NSEvent) {
            startPolling()
            onMove?(convert(event.locationInWindow, from: nil).y)
        }

        private func startPolling() {
            guard poll == nil else { return }
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard let window = self.window, window.isVisible else { return self.pointerGone() }
                let local = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if !self.bounds.contains(local) { self.pointerGone() }
            }
            RunLoop.main.add(timer, forMode: .common)
            poll = timer
        }

        private func pointerGone() {
            poll?.invalidate()
            poll = nil
            onExit?()
        }

        // Removed mid-rollover (the detail or Settings opened). This runs inside
        // a view update, where state can't change yet.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window == nil else { return }
            poll?.invalidate()
            poll = nil
            let exit = onExit
            DispatchQueue.main.async { exit?() }
        }
    }
}

// The current index label, shown large in the middle of the list while the
// strip is rolled over: the cells' color with an accent outline and a shadow,
// and nothing behind it.
//
// The outline is a stroke laid UNDER the fill. That leaves only its outer half
// showing, so it sits outside the letter. It also hides the contours where a
// glyph's strokes overlap: system fonts are variable and draw M or N as
// overlapping shapes, and a stroke on top traces those seams through the letter.
struct FontIndexPreview: View {
    private static let fontSize: CGFloat = 240
    // Twice the visible outline, since the fill covers the inner half.
    private static let strokeWidth: CGFloat = 1.5

    let label: String

    var body: some View {
        let glyphs = GlyphOutline(text: label, fontSize: Self.fontSize)
        ZStack {
            glyphs.stroke(Theme.accent, style: StrokeStyle(lineWidth: Self.strokeWidth, lineJoin: .round))
            glyphs.fill(Theme.cellSurface)
        }
        .frame(width: Self.fontSize * 1.6, height: Self.fontSize * 1.6)
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
    }
}

// Text as a vector shape, centered on its ink. SwiftUI's Text has no outline
// on this deployment target. Reading the runs from CTLine brings font fallback,
// so Hangul labels come out of whichever font actually draws them.
private struct GlyphOutline: Shape {
    let text: String
    let fontSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        let outline = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName] else { continue }
            let runFont = value as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                outline.addPath(glyph, transform: CGAffineTransform(
                    translationX: positions[index].x, y: positions[index].y))
            }
        }
        // Core Text draws y-up; SwiftUI is y-down.
        let ink = outline.boundingBoxOfPath
        let placed = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: 1, y: -1)
            .translatedBy(x: -ink.midX, y: -ink.midY)
        return Path(outline).applying(placed)
    }
}
