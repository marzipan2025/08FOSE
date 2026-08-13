import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

struct FontDetailView: View {
    let family: FontFamily
    let previewText: String
    let onClose: () -> Void

    @EnvironmentObject var pins: PinsStore
    @EnvironmentObject var memos: MemoStore
    @EnvironmentObject var samples: SampleStore
    @EnvironmentObject var muted: MutedStore
    @EnvironmentObject var inputSource: InputSourceManager
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var toasts: ToastCenter
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var memoExpanded: Bool = false
    @State private var closeHovering = false
    @State private var memoHeaderHovering = false
    @State private var metadata: FontMetadata = .empty
    @State private var infoExpanded = false      // narrow layout "Read more" toggle
    @FocusState private var collapsedMemoFocused: Bool
    // Laid-out height the expanded memo editor reports; drives its grow-upward
    // frame (clamped). Title-area height is measured so the grow cap can stop
    // exactly at the header divider.
    @State private var memoContentHeight: CGFloat = 0
    @State private var titleAreaHeight: CGFloat = 0
    // PostScript name of the weight shown in the Glyphs grid (nil → default).
    @State private var glyphFontPS: String? = nil
    // Measured width of the glyph grid's content area, used to pack columns
    // edge-to-edge (adaptive grids leave the block centered with side gaps).
    @State private var glyphAreaWidth: CGFloat = 0
    // glyph → character map for the shown weight, built off the main thread so
    // opening the detail doesn't stutter; empty until ready (cells fall back to
    // outline rendering meanwhile).
    @State private var glyphMap: [CGGlyph: String] = [:]
    // Glyph inspect mode: while the space bar is held, the card recedes to one
    // flat tone, the grid switches to hairline outlines, and rolling over a
    // glyph blows it up to fill the card. See InspectKeyMonitor and inspectDim.
    @StateObject private var inspectKey = InspectKeyMonitor()
    @State private var zoomedGlyph: CGGlyph? = nil
    // Trailing debounce on the rollover, so sweeping the pointer across the grid
    // lands on where it stopped instead of flashing every cell on the way.
    @State private var zoomTask: Task<Void, Never>? = nil

    // The drawing style the held key selects, once the card actually has a glyph
    // grid to inspect. nil means neither key is down.
    private var inspectStyle: GlyphZoomStyle? {
        vm.detailGlyphsVisible ? inspectKey.style : nil
    }
    private var inspecting: Bool { inspectStyle != nil }

    // At/above this card width the info section sits in the right of the middle
    // (weight-list) section; below it, the info flows as multiple columns under
    // the header.
    private let wideThreshold: CGFloat = 640

    // Expanded-memo layout — the editor grows with content between one line and
    // a cap; everything around it (header, gap, specimen, paddings) is fixed.
    private static let memoFontSize: CGFloat = 17
    private static let memoLineSpacing: CGFloat = 17 * 0.21
    private static let memoTopPad: CGFloat = 20
    private static let memoBottomPad: CGFloat = 11
    private static let memoHeaderHeight: CGFloat = 22
    private static let memoHeaderToEditor: CGFloat = 8
    private static let memoSpecimenGap: CGFloat = 20   // memo ↔ specimen gap
    private static let specimenTotalHeight: CGFloat = 68
    // One wrapped line of the memo font, used as the lower clamp.
    private static let memoOneLine: CGFloat = {
        NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: memoFontSize)) + memoLineSpacing
    }()

    // Max height the growing memo editor may reach: from the card height, drop
    // the title area, the two hairline dividers (middle squeezed to zero), and
    // the expanded memo's fixed chrome. Falls back to a sane default until the
    // card/title measurements have arrived.
    private func expandedEditorMax(cardHeight: CGFloat) -> CGFloat {
        guard cardHeight > 0, titleAreaHeight > 0 else { return 110 }
        let maxArea = cardHeight - titleAreaHeight - 2
        let chrome = Self.memoTopPad + Self.memoBottomPad
            + Self.memoHeaderHeight + Self.memoHeaderToEditor
            + Self.memoSpecimenGap + Self.specimenTotalHeight
        return max(Self.memoOneLine, maxArea - chrome)
    }

    // Light mode uses lighter shadows (30% of the dark-mode strength).
    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    private var isPinned: Bool { pins.contains(family.name) }
    private var isMuted: Bool { muted.contains(family.name) }

    // A non-empty custom sample for this family overrides the global preview
    // text across every weight (and is drawn in the accent color).
    private var hasCustomSample: Bool { samples.hasSample(for: family.name) }

    // Under the title: weight count, plus a "• Variable Font" tail when the
    // family is backed by an OpenType variable font.
    private var subtitleText: String {
        let base = "\(family.weightCount) weight\(family.weightCount == 1 ? "" : "s")"
        return family.isVariable ? "\(base) • Variable Font" : base
    }

    private var sampleText: String {
        if hasCustomSample { return samples.sample(for: family.name) }
        return inputSource.resolved(previewText)
    }

    // nil → default label color; accent when a custom sample is in effect.
    private var sampleColor: Color? { hasCustomSample ? Theme.accent : nil }

    private var sampleBinding: Binding<String> {
        Binding(
            get: { samples.sample(for: family.name) },
            set: { samples.setSample($0, for: family.name) }
        )
    }

    // Hairline between header / weight list / memo. White in dark mode (lifts
    // off the dark bg), black at the same strength in light mode (sits darker
    // than its surroundings).
    private var detailDivider: Color {
        colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.12)
    }

    private var memoBinding: Binding<String> {
        Binding(
            get: { memos.note(for: family.name) },
            set: { memos.setNote($0, for: family.name) }
        )
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= wideThreshold {
                wideLayout(width: geo.size.width, height: geo.size.height)
            } else {
                narrowLayout(width: geo.size.width, height: geo.size.height)
            }
        }
        .onPreferenceChange(TitleHeightKey.self) { titleAreaHeight = $0 }
        // The blown-up glyph sits above everything but inside the card's clip.
        .overlay {
            if inspecting, let zoomedGlyph {
                glyphZoom(zoomedGlyph)
            }
        }
        .animation(.easeInOut(duration: 0.08), value: inspecting)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                // Light mode: card body is brighter than the global panel bg
                // (0.92 → 0.952, white-ward 40%) so the card lifts off the grid.
                .fill(colorScheme == .light ? Color(white: 0.952) : Theme.panelBackground)
                .shadow(color: .black.opacity(0.55 * shadowScale), radius: 14, x: 0, y: 10)
                .shadow(color: .black.opacity(0.75 * shadowScale), radius: 32, x: 0, y: 38)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .light ? Color(white: 0.56) : Color.white.opacity(0.8), lineWidth: 1)
        )
        // Tapping the card's empty background drops any text-input focus (search
        // / memo / preview bar) so the ←/→ navigation works again. Buttons and
        // the memo field handle their own taps first, so they're unaffected.
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        // The card keeps its key monitor while a modal covers it, so the modal
        // has to be excluded explicitly — otherwise the space bar gets swallowed
        // out from under Settings and its own scrolling stops working.
        .onAppear {
            inspectKey.start(canEngage: {
                vm.detailGlyphsVisible && !vm.showSettings && vm.renamingTag == nil
            })
        }
        .onDisappear { inspectKey.stop(); zoomTask?.cancel() }
        // Leaving inspect mode drops the blown-up glyph, so re-entering starts
        // clean instead of flashing whatever was last under the pointer.
        .onChange(of: inspecting) { active in
            if !active {
                zoomTask?.cancel()
                zoomedGlyph = nil
            }
        }
        .task(id: family.id) {
            infoExpanded = false
            memoExpanded = false
            memoContentHeight = 0
            glyphFontPS = nil
            // Metadata off the main thread: load() parses sfnt tables (file
            // I/O), and running it inline here stalls the first frames of the
            // open/navigation spring. Cached families resolve synchronously;
            // on a first visit the previous font's info stays up while the new
            // one loads (a few ms) so the column doesn't collapse-and-reinsert.
            if let cached = FontMetadata.cached(family.name) {
                metadata = cached
                return
            }
            let fam = family
            let loaded = await Task.detached(priority: .userInitiated) {
                FontMetadata.load(family: fam)
            }.value
            guard !Task.isCancelled else { return }
            FontMetadata.store(loaded, for: fam.name)
            // Ease the info section in if the card is still mid-motion, rather
            // than snapping the layout the moment the load lands.
            withAnimation(.easeOut(duration: 0.15)) { metadata = loaded }
        }
    }

    // MARK: - Layouts

    // Wide: the info column lives in the right of the middle (weight-list)
    // section only. Title and memo keep the card's full width.
    private func wideLayout(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleArea.inspectDim(inspecting)
            Rectangle().fill(detailDivider).frame(height: 1)
            HStack(spacing: 0) {
                weightList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !metadata.isEmpty {
                    infoColumn
                        .frame(width: max(180, width * 0.25))
                        .inspectDim(inspecting)
                }
            }
            .frame(maxHeight: .infinity)
            Rectangle().fill(detailDivider).frame(height: 1)
            memoArea(cardHeight: height).inspectDim(inspecting)
        }
    }

    // Narrow: info flows as multiple aligned columns directly under the header,
    // with no dividing lines and no per-item boxes. Capped to 2 rows with a
    // "Read more" toggle when it overflows. The info and the sample list share
    // one scroll so nothing gets clipped between them.
    private func narrowLayout(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleArea.inspectDim(inspecting)
            Rectangle().fill(detailDivider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !metadata.isEmpty {
                        infoColumns(width: width).inspectDim(inspecting)
                    }
                    weightListContent.inspectDim(inspecting)
                    if vm.detailGlyphsVisible { glyphsSection }
                }
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(inspecting ? .hidden : .automatic)
            // Reset scroll to top when ←/→ switches fonts.
            .id(family.id)
            Rectangle().fill(detailDivider).frame(height: 1)
            memoArea(cardHeight: height).inspectDim(inspecting)
        }
    }

    // Bottom memo strip: a single tail-ellipsized line when collapsed; when
    // expanded via the chevron, the memo editor grows upward with its content
    // (clamped at the header divider) above a fixed specimen box.
    @ViewBuilder
    private func memoArea(cardHeight: CGFloat) -> some View {
        if memoExpanded {
            expandedMemoArea(cardHeight: cardHeight)
        } else {
            collapsedMemoArea
        }
    }

    // MARK: - Info (wide: single right column; narrow: multi-column grid)

    private var infoColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(metadata.entries) { infoEntryView($0) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(inspecting ? .hidden : .automatic)
    }

    private func infoColumns(width: CGFloat) -> some View {
        let spacing: CGFloat = 20
        let minItem: CGFloat = 150
        let hPad: CGFloat = 24
        // Match the column count the grid will actually use so the 3-row cap is
        // exact, then drive the grid with that many flexible columns.
        let avail = max(0, width - hPad * 2)
        let cols = max(1, Int((avail + spacing) / (minItem + spacing)))
        let maxVisible = cols * 2
        let entries = metadata.entries
        let hasOverflow = entries.count > maxVisible
        let visible = (!infoExpanded && hasOverflow) ? Array(entries.prefix(maxVisible)) : entries

        // If the last row would hold a single item, pull it out of the grid and
        // give it the full width instead of leaving it boxed in one column.
        let singleLast = cols > 1 && visible.count > 1 && visible.count % cols == 1
        let gridEntries = singleLast ? Array(visible.dropLast()) : visible

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .topLeading),
                                   count: cols),
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(gridEntries) { infoEntryView($0) }
                }
                if singleLast, let last = visible.last {
                    infoEntryView(last)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if hasOverflow {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { infoExpanded.toggle() }
                } label: {
                    Text(infoExpanded ? "Read less" : "Read more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func infoEntryView(_ entry: InfoEntry) -> some View {
        switch entry {
        case .field(let label, let value):
            VStack(alignment: .leading, spacing: 2) {
                infoLabel(label)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .features(let tags):
            VStack(alignment: .leading, spacing: 4) {
                infoLabel("Features")
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    ForEach(tags, id: \.self) { featureTag($0) }
                }
            }
        case .scripts(let names):
            VStack(alignment: .leading, spacing: 4) {
                infoLabel("Scripts")
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    ForEach(names, id: \.self) { scriptTag($0) }
                }
            }
        }
    }

    // Same blue-italic treatment as feature tags, without the OpenType tooltip.
    private func scriptTag(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 13).italic())
            .foregroundStyle(Theme.memoAccent)
    }

    private func infoLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }

    private func featureTag(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 13).italic())
            .foregroundStyle(Theme.memoAccent)
            .help(OpenTypeFeatureNames.friendly(tag) ?? tag)
    }

    // MARK: - Memo (collapsed: single-line + expand toggle)

    private var collapsedMemoArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            memoHeader(
                icon: "chevron.up",
                help: "Expand memo"
            ) {
                memoExpanded = true   // instant, no expand/collapse animation
            }
            ZStack(alignment: .leading) {
                if memos.note(for: family.name).isEmpty {
                    Text("Add a note…")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.memoAccent)
                        .allowsHitTesting(false)
                }
                // Editing surface (hidden until focused so the read-only,
                // ellipsized label below is what shows at rest).
                TextField("", text: memoBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.memoAccent)
                    .lineLimit(1)
                    .focused($collapsedMemoFocused)
                    .opacity(collapsedMemoFocused ? 1 : 0)
                // Resting display: one line, tail-ellipsized (no mid-glyph clip).
                if !collapsedMemoFocused && !memos.note(for: family.name).isEmpty {
                    Text(memos.note(for: family.name))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.memoAccent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .allowsHitTesting(false)
                }
            }
            // Right margin of 90 total (24 + 66) so the single line clears the
            // collapse chevron area with extra room.
            .padding(.trailing, 66)
            .contentShape(Rectangle())
            .onTapGesture { collapsedMemoFocused = true }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(memoAreaBackground)
    }

    // Memo strip background: none, so the card's own body colour carries through
    // and the strip reads as part of the same surface rather than a shelf under
    // it. Clear rather than a copy of the card colour, so the two can't drift.
    private var memoAreaBackground: Color { .clear }

    // MARK: - Memo (expanded: fills body)

    private func expandedMemoArea(cardHeight: CGFloat) -> some View {
        // The editor grows with its content between one line and the cap; past
        // the cap its own scroll view takes over (specimen stays pinned below).
        let editorMax = expandedEditorMax(cardHeight: cardHeight)
        let editorHeight = min(max(memoContentHeight, Self.memoOneLine), editorMax)
        return VStack(alignment: .leading, spacing: Self.memoSpecimenGap) {
            // Memo header + editor keep the standard 24pt side margin.
            VStack(alignment: .leading, spacing: Self.memoHeaderToEditor) {
                memoHeader(
                    icon: "chevron.down",
                    help: "Collapse memo"
                ) {
                    memoExpanded = false   // instant, no expand/collapse animation
                }
                ZStack(alignment: .topLeading) {
                    if memos.note(for: family.name).isEmpty {
                        Text("Add a note…")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.memoAccent)
                            .allowsHitTesting(false)
                    }
                    MemoEditor(
                        text: memoBinding,
                        fontSize: Self.memoFontSize,
                        lineSpacing: Self.memoLineSpacing,   // 0.35 reduced a further 40%
                        textColor: NSColor(Theme.memoAccent),
                        onHeightChange: { memoContentHeight = $0 },
                        maxHeight: editorMax
                    )
                }
                .frame(height: editorHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // Extra right margin (24 + 36 = 60 total) so wrapped memo text
                // never runs under the collapse chevron at the top-right.
                .padding(.trailing, 36)
            }
            .padding(.horizontal, 24)

            // Custom specimen text: a fixed-height, slightly darker rounded box
            // pinned below the memo. When set, it replaces the preview text for
            // every weight in this detail view. Margins are ~40% of the memo's.
            specimenBox
                .padding(.horizontal, 11)
        }
        .padding(.top, Self.memoTopPad)
        .padding(.bottom, Self.memoBottomPad)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(memoAreaBackground)
    }

    private var specimenBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Specimen")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if samples.sample(for: family.name).isEmpty {
                    Text("Add specimen text…")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent.opacity(0.55))
                        .allowsHitTesting(false)
                }
                MemoEditor(
                    text: sampleBinding,
                    fontSize: 17,
                    lineSpacing: 17 * 0.4,
                    textColor: NSColor(Theme.accent)
                )
            }
            // Reserve room on the right so the specimen text never runs under
            // the clear button.
            .padding(.trailing, samples.sample(for: family.name).isEmpty ? 0 : 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // Clear-all button, mirroring the preview input bar; only when
            // non-empty. Overlaid on the input region (not the whole box) so it
            // sits level with the orange specimen text line.
            .overlay(alignment: .trailing) {
                if !samples.sample(for: family.name).isEmpty {
                    Button { sampleBinding.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .offset(y: -3)
                }
            }
        }
        // Equal top & left margins for the text, 4px larger than before.
        .padding(.leading, 16)
        .padding(.top, 16)
        .padding(.trailing, 16)
        .padding(.bottom, 8)
        // Just tall enough for the "Specimen" title + one line of input.
        .frame(height: 68)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                // Darker than the memo strip it sits on; a touch more opaque.
                .fill(Color.black.opacity(colorScheme == .light ? 0.08 : 0.24))
        )
    }

    private func memoHeader(icon: String, help: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text("Memo")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(memoHeaderHovering ? Theme.surfaceFillHover : Theme.surfaceFill)
                    )
            }
            .buttonStyle(.plain)
            .onHover { memoHeaderHovering = $0 }
            .help(help)
        }
    }

    // MARK: - Title Area

    private var titleArea: some View {
        // Header darkening gradient is full strength in dark mode, very faint
        // in light.
        let gradientScale = colorScheme == .light ? 0.06 : 1.0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(family.name)
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            // Tail-ellipsize a too-long name instead of shrinking
                            // it; the Spacer below keeps a 16px gap to the close
                            // button, so the ellipsis lands 16px clear of it.
                            .truncationMode(.tail)
                        if family.script == .korean {
                            KoreanBadge(titleSize: 23)
                                // Sit slightly above the title's vertical centre.
                                .offset(y: -23 * 0.08)
                        }
                    }
                    Text(subtitleText)
                        .font(.system(size: Theme.bodySize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .unifiedGeometry()
                // Muted fonts read as de-emphasized — dim just the identity, so
                // the action buttons (incl. Unmute) stay fully legible.
                .opacity(isMuted ? 0.4 : 1)

                Spacer(minLength: 16)

                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        // Same color rule as the memo chevron button: secondary
                        // glyph on a surfaceFill background (denser on hover).
                        .foregroundStyle(.secondary)
                        .offset(y: -0.5)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(closeHovering ? Theme.surfaceFillHover : Theme.surfaceFill))
                }
                .buttonStyle(.plain)
                .onHover { closeHovering = $0 }
                .accessibilityLabel("Close detail")
                .help("Close detail")
            }

            HStack(spacing: 8) {
                ActionButton(
                    icon: nil,
                    label: isPinned ? "Pinned" : "Pin",
                    active: isPinned
                ) { pins.toggle(family.name) }

                ActionButton(
                    icon: copied ? "checkmark" : nil,
                    label: copied ? "Copied" : "Copy name",
                    active: copied
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(family.name, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                }

                ActionButton(icon: "folder", label: "Show in Finder", active: false) {
                    openInFinder()
                }

                ActionButton(
                    icon: isMuted ? "moon.zzz.fill" : "moon.zzz",
                    label: isMuted ? "Muted" : "Mute",
                    active: isMuted
                ) { toggleMuted() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        // Fixed height: never let the VStack compress this band when the memo
        // grows. Without this, a growing memo squeezes the title, the title's
        // minimumScaleFactor shrinks the name, the measured title height drops,
        // the memo cap grows, and it feeds back into a runaway shrink loop.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            // Subtle top-down darkening of the header, independent of the
            // wallpaper. Clipped into the card by the view's outer clipShape.
            // When muted, a stronger scrim dims the whole header backdrop while
            // the action buttons (in front) stay legible and clickable.
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.10 * gradientScale),
                             Color.black.opacity(0.30 * gradientScale)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if isMuted {
                    Color.black.opacity(colorScheme == .light ? 0.10 : 0.45)
                }
            }
        )
        // Report the title-area height so the expanded memo's grow cap can stop
        // exactly at the divider just below the header.
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: TitleHeightKey.self, value: geo.size.height)
            }
        )
    }

    // MARK: - Weight List

    // Wide layout scrolls the sample list on its own; narrow layout embeds
    // `weightListContent` in a shared scroll with the info section.
    private var weightList: some View {
        ScrollView {
            weightListContent.inspectDim(inspecting)
            if vm.detailGlyphsVisible { glyphsSection }
        }
        // The scroller is drawn by AppKit outside the dimmed subtree, so it
        // stays at full strength while everything else recedes — the one bright
        // thing left on the card. Hidden for the duration; the wheel still works.
        .scrollIndicators(inspecting ? .hidden : .automatic)
        // Fresh identity per font so ←/→ navigation starts back at the top
        // instead of keeping the previous font's scroll offset.
        .id(family.id)
    }

    private var weightListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Variable fonts lead with an interactive weight-axis row: a slider
            // sweeps the sample between the axis's lightest and heaviest.
            if let axis = family.weightAxis {
                VariableWeightRow(
                    basePSName: family.previewFontName ?? family.memberFontNames.first ?? family.name,
                    familyName: family.name,
                    sampleText: sampleText,
                    sampleColor: sampleColor,
                    sampleSize: CGFloat(vm.weightRowFontSize),
                    axis: axis
                )
                Divider().opacity(0.15).padding(.horizontal, 24)
            }
            ForEach(Array(family.memberFontNames.enumerated()), id: \.offset) { index, psName in
                WeightRow(psName: psName, familyName: family.name, sampleText: sampleText, sampleColor: sampleColor, sampleSize: CGFloat(vm.weightRowFontSize))
                if index < family.memberFontNames.count - 1 {
                    Divider().opacity(0.15).padding(.horizontal, 24)
                }
            }
        }
        .padding(.vertical, 8)
        // Muted fonts read de-emphasized here too, matching the title/cell.
        .opacity(isMuted ? 0.4 : 1)
    }

    // MARK: - Glyphs

    // Point size each glyph is drawn at — the weight-row sample size.
    private var glyphPointSize: CGFloat { CGFloat(vm.weightRowFontSize) }
    private var glyphCellSize: CGFloat { glyphPointSize * 1.4 }

    // The members offered in the weight picker (PostScript name + face label).
    private var glyphMembers: [(ps: String, face: String)] {
        family.memberFontNames.map { ps in
            let face = (NSFont(name: ps, size: 12)?.fontDescriptor.object(forKey: .face) as? String) ?? ps
            return (ps, face)
        }
    }

    // Default to a Regular (or 400/500) face, falling back to the first member.
    private var selectedGlyphPS: String {
        glyphFontPS ?? family.previewFontName ?? family.memberFontNames.first ?? family.name
    }

    private var selectedGlyphFace: String {
        glyphMembers.first { $0.ps == selectedGlyphPS }?.face ?? "Regular"
    }

    private var glyphsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(detailDivider).frame(height: 1).padding(.horizontal, 24)
            HStack(spacing: 8) {
                Text("Glyphs")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                if family.memberFontNames.count > 1 {
                    glyphWeightPicker
                } else {
                    // Single weight: show just the face name (no menu/chevron),
                    // so multi-weight only looks like a chevron was added.
                    Text(selectedGlyphFace)
                        .font(.system(size: Theme.smallSize))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            // The section's own header is chrome, so it recedes with everything
            // else — only the grid stays.
            .inspectDim(inspecting)
            glyphGrid
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .opacity(isMuted ? 0.4 : 1)
        // Build the glyph→character map off-main when the weight changes, so the
        // first paint (outline) is instant and color/copy light up when ready.
        .task(id: selectedGlyphPS) {
            let ps = selectedGlyphPS
            if let cached = GlyphReverseMap.cached(ps) { glyphMap = cached; return }
            glyphMap = [:]
            let map = await Task.detached(priority: .userInitiated) {
                GlyphReverseMap.build(ps)
            }.value
            guard !Task.isCancelled else { return }
            GlyphReverseMap.store(ps, map)
            glyphMap = map
        }
    }

    private var glyphWeightPicker: some View {
        Menu {
            ForEach(glyphMembers, id: \.ps) { member in
                Button(member.face) { glyphFontPS = member.ps }
            }
        } label: {
            Text(selectedGlyphFace)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var glyphGrid: some View {
        let font = CTFontCreateWithName(selectedGlyphPS as CFString, glyphPointSize, nil)
        let count = CTFontGetGlyphCount(font)
        let cell = glyphCellSize
        let spacing: CGFloat = 8
        // Fixed flexible columns sized from the measured width, so the row fills
        // the full content width (matching the divider) instead of centering.
        let columnCount = max(1, Int((glyphAreaWidth + spacing) / (cell + spacing)))
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                GlyphCell(
                    font: font,
                    glyph: CGGlyph(index),
                    character: glyphMap[CGGlyph(index)],
                    inspecting: inspecting,
                    onRollover: { scheduleZoom($0) }
                )
                .frame(height: cell)
            }
        }
        // Fresh layout when the cell size changes: LazyVGrid reuses cells and
        // doesn't cleanly grow already-laid rows, clipping box tops when the
        // font size increases. Re-id'ing on the size forces a clean relayout.
        .id(cell)
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: GlyphAreaWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(GlyphAreaWidthKey.self) { glyphAreaWidth = $0 }
    }

    // MARK: - Glyph inspect

    // Trailing debounce: each rollover restarts the clock, so a pointer swept
    // across the grid only resolves once it settles. 80ms is long enough to skip
    // the cells passed through, short enough to feel immediate when it lands.
    private func scheduleZoom(_ glyph: CGGlyph?) {
        zoomTask?.cancel()
        zoomTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            zoomedGlyph = glyph
        }
    }

    // The blown-up glyph. Filled, at full ink strength — the one thing in the
    // card that isn't receding. Scaled so the font's em box fits the card's
    // shorter side with a 4% margin, and positioned by the font's own metrics
    // rather than by its inked bounds: relative size AND relative position hold
    // across glyphs, so a comma stays a small mark low in the frame while a
    // CJK ideograph fills it.
    @ViewBuilder
    private func glyphZoom(_ glyph: CGGlyph) -> some View {
        Canvas { ctx, size in
            // 12% breathing room per side: accents, swashes and tall marks reach
            // well past the em box, and at a tighter fit they clipped on the
            // card edge.
            let em = min(size.width, size.height) * 0.76
            guard em > 1 else { return }
            let font = CTFontCreateWithName(selectedGlyphPS as CFString, em, nil)
            var g = glyph
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advance, 1)
            let ascent = CTFontGetAscent(font)
            let descent = CTFontGetDescent(font)
            // Fully opaque, unlike the 0.85 the grid cells use: at 0.85 the
            // outlined glyphs underneath showed through the strokes and the big
            // glyph read as translucent.
            let ink = colorScheme == .light ? NSColor.black : NSColor.white
            ctx.withCGContext { cg in
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                // Centre the font's ascent-to-descent band in the card, then drop
                // it 20pt. Splitting the em box by the ascent:descent ratio (the
                // first attempt) rode high: ascent + descent normally runs past
                // one em, so normalising them into the box under-allocated the
                // ascent and pushed the glyph out through the top. Both metrics
                // are font-level, so relative position still holds across glyphs
                // — a comma stays low, an apostrophe stays high.
                let baseline = (size.height - (ascent - descent)) / 2 - 20
                // Same split as the grid cells: draw through a CTLine when the
                // glyph maps to a character, so colour fonts come out in their
                // own colours — this is what lets emoji blow up even though they
                // have no outline for the grid to trace. Everything else is
                // drawn by glyph ID.
                let path = CTFontCreatePathForGlyph(font, glyph, nil)

                // Contour: the fill flips to the opposite ink — white on light,
                // black on dark — which alone would sink into the card, so the
                // outline is traced in the accent at 1pt to carry the shape, then
                // every on-curve node gets its own marker. Needs a path, so
                // colour bitmap glyphs fall through to solid.
                if inspectStyle == .contour, let path {
                    let contourInk = colorScheme == .light ? NSColor.white : NSColor.black
                    let accent = Theme.accentInk(colorScheme)
                    cg.saveGState()
                    cg.translateBy(x: (size.width - advance.width) / 2, y: baseline)
                    cg.addPath(path)
                    cg.setFillColor(contourInk.cgColor)
                    cg.fillPath()
                    cg.addPath(path)
                    cg.setStrokeColor(accent.cgColor)
                    cg.setLineWidth(1)
                    cg.strokePath()
                    drawNodeMarkers(path, in: cg, fill: contourInk, edge: accent)
                    cg.restoreGState()
                } else if let character = glyphMap[glyph] {
                    // Bitmap colour fonts top out at their largest strike (Apple
                    // Color Emoji: 160px), so filling the card upscales several
                    // times over. No setting recovers detail that isn't there, so
                    // drop interpolation and let the pixels show rather than
                    // smear them. Only for those glyphs — vector ones scale
                    // cleanly and want the default.
                    // (Antialiasing is left on: it governs vector edges, not
                    // bitmap scaling, and killing it would only jag the rest.)
                    if path == nil { cg.interpolationQuality = .none }
                    let attr = NSAttributedString(string: character,
                                                  attributes: [.font: font, .foregroundColor: ink])
                    let line = CTLineCreateWithAttributedString(attr)
                    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                    cg.textPosition = CGPoint(x: (size.width - width) / 2, y: baseline)
                    CTLineDraw(line, cg)
                } else {
                    var pos = CGPoint(x: (size.width - advance.width) / 2, y: baseline)
                    cg.setFillColor(ink.cgColor)
                    CTFontDrawGlyphs(font, &g, &pos, 1, cg)
                }
            }
        }
        // The overlay must never take the pointer: rollover on the cells beneath
        // is what drives it, and swallowing events would freeze it on the first
        // glyph (and kill scrolling through the grid).
        .allowsHitTesting(false)
    }

    // A square on each on-curve point of the outline, the way a type editor
    // marks its nodes. Off-curve control points are skipped: they sit away from
    // the contour — outside it through a curve — and without the handle lines a
    // type editor draws to tether them, they read as strays. Dropping them also
    // roughly halves the count on curve-heavy glyphs.
    //
    // A 3×3 core, a 1pt accent edge drawn *outside* it, then a second 1pt ring
    // of the fill colour beyond that — 7 across in total. Core Graphics centres
    // a stroke on its path, so each ring's rect is outset by enough to place the
    // whole width beyond what came before.
    //
    // The core takes the glyph's own fill rather than the edge colour, so a
    // marker reads as a ring rather than a dot.
    private static let nodeMarkerSize: CGFloat = 3
    private static let nodeMarkerEdge: CGFloat = 1

    private func drawNodeMarkers(_ path: CGPath, in cg: CGContext,
                                 fill: NSColor, edge: NSColor) {
        let size = Self.nodeMarkerSize
        let width = Self.nodeMarkerEdge
        var nodes: [CGPoint] = []
        path.applyWithBlock { element in
            let p = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                nodes.append(p[0])
            // Quadratic for TrueType outlines, cubic for CFF — fonts ship both.
            // Either way the last point is where the curve lands on the contour;
            // the ones before it are controls, and are dropped.
            case .addQuadCurveToPoint:
                nodes.append(p[1])
            case .addCurveToPoint:
                nodes.append(p[2])
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        guard !nodes.isEmpty else { return }
        cg.setLineWidth(width)
        for node in nodes {
            let box = CGRect(x: node.x - size / 2, y: node.y - size / 2,
                             width: size, height: size)
            cg.setFillColor(fill.cgColor)
            cg.fill(box)
            cg.setStrokeColor(edge.cgColor)
            cg.stroke(box.insetBy(dx: -width / 2, dy: -width / 2))
            // A second ring in the glyph's own fill, same weight, just beyond
            // the accent one. Where a node sits on the contour the marker's edge
            // would otherwise run into the outline's, both being the accent at
            // the same weight; this keeps a fill-coloured gap between them so
            // the marker reads as detached.
            cg.setStrokeColor(fill.cgColor)
            cg.stroke(box.insetBy(dx: -width * 1.5, dy: -width * 1.5))
        }
    }

    // MARK: - Actions

    private func openInFinder() {
        guard let psName = family.memberFontNames.first,
              let url = CTFontDescriptorCopyAttribute(
                CTFontDescriptorCreateWithNameAndSize(psName as CFString, 0),
                kCTFontURLAttribute) as? URL
        else {
            toasts.show(Toast(style: .error, title: "Couldn't locate the font file",
                              detail: "\(family.name) has no resolvable file path."))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // Mute toggle with feedback: when the grid hides muted fonts, the family
    // vanishes the moment this is pressed — the toast explains where it went
    // and offers the way back. Unmuting / dimmed-mode muting stay silent (the
    // button state and the cell are visible proof).
    private func toggleMuted() {
        let name = family.name
        let willMute = !muted.contains(name)
        muted.toggle(name)
        guard willMute && vm.mutedFilter == .hidden && !vm.mutedOnly else { return }
        toasts.show(Toast(
            style: .info,
            title: "\(name) muted",
            detail: "Hidden from the grid",
            icon: "moon.zzz",
            actionLabel: "Undo",
            action: { muted.toggle(name) }
        ))
    }
}

// Tracks the two inspect keys for as long as the detail card is open, and
// reports which drawing style the one being held selects.
//
// Space carries the solid blow-up because the macOS idiom for "show me this
// bigger" is Quick Look, and that is the key it lives on; ⌥ carries the contour
// one because it is the modifier macOS already uses for "reveal the other
// version of this", and nothing else in the app claims it. ⌘ is unusable for
// either: it precedes every command in the app and every app-switch outside it,
// so the card would blink into inspect mode on the way to ⌘F, ⌘, or ⌘-Tab.
//
// A *local* monitor only sees events routed to this app, so "the app is
// frontmost" comes for free. Three more things it handles: the space bar is
// swallowed while engaged, or the scroll view underneath would page down on
// every press (⌥ is only observed, never consumed, so modifier state stays sane
// everywhere else); the app deactivating mid-hold releases the mode, since the
// matching key-up goes to whoever took focus rather than to us; and ⌥ already
// held when the app is activated produces no flagsChanged event at all, so the
// current flags are re-read on activation.
//
// Typing is exempt for both — a space is a space and ⌥ is a dead key for
// special characters when a text field has focus.
@MainActor final class InspectKeyMonitor: ObservableObject {
    // Which style the held key selects; nil when neither is down.
    @Published private(set) var style: GlyphZoomStyle?

    // Asked before engaging, so the keys keep their ordinary meaning when the
    // card has no glyph grid to inspect.
    private var canEngage: () -> Bool = { true }
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    private var spaceDown = false
    private var optionDown = false
    // Holding both is resolved by whichever was pressed last, so rolling from
    // one key to the other swaps the style instead of sticking on the first.
    private var lastPressed: GlyphZoomStyle?

    private static let spaceKeyCode: UInt16 = 49

    func start(canEngage: @escaping () -> Bool) {
        self.canEngage = canEngage
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.keyCode == Self.spaceKeyCode else { return event }

            // Key-up releases unconditionally — never behind the guards below.
            // A modal can open, or focus can land in a text field (⌘F), while
            // the key is still down; checking the guards here would skip the
            // release and strand the mode on with no way back.
            if event.type == .keyUp {
                guard self.spaceDown else { return event }
                self.spaceDown = false
                self.refresh()
                return nil
            }

            // A modal owns the keyboard while it's up, and a focused field owns
            // the space bar; in both cases it's just a space.
            if NSApp.modalWindow != nil { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            guard self.canEngage() else { return event }
            if !self.spaceDown {
                self.spaceDown = true
                self.lastPressed = .solid
                self.refresh()
            }
            return nil   // engaged: swallow it so nothing scrolls
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateOption(event.modifierFlags)
            return event   // observe only — never consume
        }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.releaseAll() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateOption(NSEvent.modifierFlags) }
            }
        ]
    }

    func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        releaseAll()
    }

    private func updateOption(_ flags: NSEvent.ModifierFlags) {
        // Releasing is unconditional for the same reason key-up is; only
        // engaging consults the guards.
        let held = flags.contains(.option)
        if !held {
            guard optionDown else { return }
            optionDown = false
            refresh()
            return
        }
        guard !optionDown,
              NSApp.modalWindow == nil,
              !(NSApp.keyWindow?.firstResponder is NSText),
              canEngage()
        else { return }
        optionDown = true
        lastPressed = .contour
        refresh()
    }

    private func releaseAll() {
        spaceDown = false
        optionDown = false
        refresh()
    }

    private func refresh() {
        let next: GlyphZoomStyle?
        switch (spaceDown, optionDown) {
        case (true, true): next = lastPressed
        case (true, false): next = .solid
        case (false, true): next = .contour
        case (false, false): next = nil
        }
        if next != style { style = next }
    }
}

// The recede treatment for everything that isn't the glyph grid: desaturated,
// flattened to a single tone, and faded back until it reads as texture rather
// than content. Nothing is removed — the layout stays exactly where it was.
// Hit testing goes off so clicks can't land on controls that are barely there.
private struct InspectDim: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .saturation(active ? 0 : 1)
            .contrast(active ? 0 : 1)
            .opacity(active ? 0.5 : 1)
            .allowsHitTesting(!active)
    }
}

extension View {
    func inspectDim(_ active: Bool) -> some View { modifier(InspectDim(active: active)) }
}

// One glyph centered in its cell, drawn on a SwiftUI Canvas (no per-cell NSView)
// so even ~50k-glyph CJK fonts scroll smoothly. Glyphs that map to a character
// are drawn as TEXT (CTLine) so color fonts (emoji) render in their real color;
// unmapped glyphs (ligatures, alternates) fall back to an outline by glyph ID.
private struct GlyphCell: View {
    let font: CTFont
    let glyph: CGGlyph
    // Mapped character (nil = unmapped or map not built yet → outline, no copy).
    let character: String?
    // Inspect mode: draw as a hairline outline instead of a filled shape, and
    // report rollover so the card can blow this glyph up.
    let inspecting: Bool
    let onRollover: (CGGlyph?) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false
    @State private var showCopied = false

    // Bitmap colour glyphs (Apple Color Emoji and friends) have no outline to
    // trace, so inspect mode can't draw them as line art — they recede with the
    // rest of the chrome instead. They still answer rollover: the blow-up is
    // drawn filled, which colour glyphs handle fine.
    private var outlinePath: CGPath? {
        guard inspecting else { return nil }
        return CTFontCreatePathForGlyph(font, glyph, nil)
    }
    private var hasOutline: Bool { outlinePath != nil }

    var body: some View {
        let path = outlinePath
        return Canvas { ctx, size in
            // Non-copyable glyphs (outline box) are drawn more faded.
            let ink = (colorScheme == .light ? NSColor.black : NSColor.white)
                .withAlphaComponent(character != nil ? 0.85 : 0.5)
            ctx.withCGContext { cg in
                // Flip to a y-up text space (Canvas is y-down, top-left origin).
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                if let path {
                    // Hairline trace of the outline, at half a device pixel on a
                    // 2x display — it antialiases to a fainter line rather than
                    // a thinner one, which is the point. Centred on the path's
                    // own bounds so it sits where the filled version did.
                    let b = path.boundingBoxOfPath
                    guard b.width.isFinite, b.height.isFinite else { return }
                    cg.saveGState()
                    cg.translateBy(x: (size.width - b.width) / 2 - b.minX,
                                   y: (size.height - b.height) / 2 - b.minY)
                    cg.addPath(path)
                    cg.setStrokeColor(Self.inspectInk(colorScheme).cgColor)
                    cg.setLineWidth(0.3)
                    cg.strokePath()
                    cg.restoreGState()
                } else if let character {
                    // Color-aware text render — shows the font's own color glyph.
                    let attr = NSAttributedString(string: character,
                                                  attributes: [.font: font, .foregroundColor: ink])
                    let line = CTLineCreateWithAttributedString(attr)
                    let ib = CTLineGetImageBounds(line, cg)
                    guard ib.width.isFinite, ib.height.isFinite, ib.width > 0, ib.height > 0 else { return }
                    cg.textPosition = CGPoint(
                        x: (size.width - ib.width) / 2 - ib.minX,
                        y: (size.height - ib.height) / 2 - ib.minY
                    )
                    CTLineDraw(line, cg)
                } else {
                    var g = glyph
                    var bbox = CGRect.zero
                    CTFontGetBoundingRectsForGlyphs(font, .horizontal, &g, &bbox, 1)
                    guard bbox.width.isFinite, bbox.height.isFinite,
                          bbox.width > 0, bbox.height > 0 else { return }
                    cg.setFillColor(ink.cgColor)
                    var pos = CGPoint(
                        x: (size.width - bbox.width) / 2 - bbox.minX,
                        y: (size.height - bbox.height) / 2 - bbox.minY
                    )
                    CTFontDrawGlyphs(font, &g, &pos, 1, cg)
                }
            }
        }
        // Cell box: filled when the glyph is copyable, an inner outline only
        // when it isn't (no mapped character). Denser on hover either way.
        .background(glyphBox)
        // Accent "COPIED" flash at the cell's bottom center on a successful copy.
        // Non-copyable glyphs simply don't react.
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("COPIED")
                    .font(.system(size: Theme.sectionHeaderSize, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.bottom, 3)
                    .transition(.opacity)
            }
        }
        // Colour glyphs keep their filled render in inspect mode, so fade them
        // back to match the rest of the receded chrome.
        .saturation(inspecting && !hasOutline ? 0 : 1)
        .opacity(inspecting && !hasOutline ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            self.hovering = hovering
            onRollover(hovering ? glyph : nil)
        }
        // Inspect mode owns the pointer: a click here would otherwise copy while
        // the user is only looking.
        // Entering inspect mode with the pointer already parked on a cell fires
        // no hover event, so the mode change has to report the rollover itself.
        // Only the cell under the pointer answers.
        .onChange(of: inspecting) { active in
            guard hovering else { return }
            onRollover(active ? glyph : nil)
        }
        .onTapGesture { if !inspecting { handleTap() } }
        // Hover tooltip: the character this glyph maps to. Empty when unmapped,
        // and suppressed entirely in inspect mode — the blown-up glyph is the
        // answer to "what is this", so a small popup on top of it is just noise.
        .nativeTooltip(inspecting ? "" : (character ?? ""))
    }

    // Inspect-mode ink, matching the ActionButton labels' `.secondary`.
    static func inspectInk(_ scheme: ColorScheme) -> NSColor {
        (scheme == .light ? NSColor.black : NSColor.white).withAlphaComponent(0.55)
    }

    @ViewBuilder
    private var glyphBox: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if character != nil {
            shape
                .fill(hovering ? Theme.surfaceFillHover : Theme.surfaceFill)
                .opacity(hovering ? 0.7 : 0.35)
        } else {
            shape
                .strokeBorder(hovering ? Theme.borderHover : Theme.border, lineWidth: 1)
        }
    }

    private func handleTap() {
        guard let character else { return }   // non-copyable: no reaction
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(character, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.3)) { showCopied = false }
        }
    }
}

// Reverse cmap (glyph → character) for rendering + click-to-copy, built lazily
// per font and cached. The BMP (U+0000…U+FFFF) is mapped in one batch pass for
// every font; astral planes (emoji, CJK ext) are enumerated only for modest-
// size fonts so huge CJK families don't pay the cost — this is enough to cover
// emoji fonts, which is where it matters.
private enum GlyphReverseMap {
    @MainActor private static var cache: [String: [CGGlyph: String]] = [:]
    private static let astralGlyphCap = 8000

    @MainActor static func cached(_ ps: String) -> [CGGlyph: String]? { cache[ps] }
    @MainActor static func store(_ ps: String, _ map: [CGGlyph: String]) { cache[ps] = map }

    // Pure Core Text; safe to run off the main thread.
    nonisolated static func build(_ ps: String) -> [CGGlyph: String] {
        let font = CTFontCreateWithName(ps as CFString, 16, nil)
        var map: [CGGlyph: String] = [:]

        // BMP: one batch char→glyph pass, then reverse.
        let n = 0x10000
        var chars = [UniChar](repeating: 0, count: n)
        for i in 0..<n { chars[i] = UniChar(i) }
        var glyphs = [CGGlyph](repeating: 0, count: n)
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, n)
        for i in 0..<n {
            let g = glyphs[i]
            guard g != 0, map[g] == nil, let scalar = Unicode.Scalar(UInt32(i)) else { continue }
            map[g] = String(scalar)
        }

        // Astral: only for small fonts (emoji etc.). Surrogate pairs aren't
        // handled by the batch API, so resolve each covered scalar via CTLine.
        if CTFontGetGlyphCount(font) < astralGlyphCap,
           let charset = CTFontCopyCharacterSet(font) as CharacterSet? {
            for plane in 1...16 where charset.hasMember(inPlane: UInt8(plane)) {
                let base = plane << 16
                for cp in base..<(base + 0x10000) {
                    guard let scalar = Unicode.Scalar(UInt32(cp)), charset.contains(scalar),
                          let g = glyph(of: scalar, in: font), map[g] == nil else { continue }
                    map[g] = String(scalar)
                }
            }
        }
        return map
    }

    // Glyph for a single scalar (handles astral), nil if the font lacks it (a
    // fallback font was substituted).
    private static func glyph(of scalar: Unicode.Scalar, in font: CTFont) -> CGGlyph? {
        let attr = NSAttributedString(string: String(scalar), attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1 else { return nil }
        let run = runs[0]
        guard CTRunGetGlyphCount(run) == 1 else { return nil }
        let attrs = CTRunGetAttributes(run) as NSDictionary
        if let runFont = attrs[kCTFontAttributeName as String] {
            let used = runFont as! CTFont
            if (CTFontCopyPostScriptName(used) as String) != (CTFontCopyPostScriptName(font) as String) {
                return nil
            }
        }
        var g = CGGlyph(0)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &g)
        return g == 0 ? nil : g
    }
}

// Measured width of the glyph grid content area, so columns pack edge-to-edge.
private struct GlyphAreaWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Reports the detail card's title-area height up to the root, so the expanded
// memo can compute how far it may grow before its top hits the header divider.
private struct TitleHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Korean Badge

// Custom marker shown beside the detail title for Korean-supporting fonts:
// a squircle outline (no fill) holding uppercase "KR", sized ~60% of the
// title's cap height.
private struct KoreanBadge: View {
    let titleSize: CGFloat

    var body: some View {
        let h = titleSize * 0.72   // ~60% of title, then +20%
        Text("KR")
            .font(.system(size: h * 0.6, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, h * 0.26)
            .frame(height: h)
            .overlay(
                RoundedRectangle(cornerRadius: h * 0.34, style: .continuous)
                    .stroke(Color.secondary, lineWidth: max(1, h * 0.08))
            )
            .accessibilityLabel("Korean")
    }
}

// MARK: - Geometry Helper

private extension View {
    /// Treats a view's subtree as a single geometry unit so children animate
    /// together (instead of background/text sliding independently) during an
    /// ancestor's matchedGeometryEffect resize. Falls back to no-op pre-macOS 14.
    @ViewBuilder
    func unifiedGeometry() -> some View {
        if #available(macOS 14.0, *) {
            self.geometryGroup()
        } else {
            self
        }
    }
}

// MARK: - Variable Weight Row

// Top row of a variable font's weight list: a slider drives the sample text's
// weight axis live between the axis minimum and maximum, so the whole range is
// explorable without hopping between the named instances below.
private struct VariableWeightRow: View {
    let basePSName: String
    let familyName: String
    let sampleText: String
    var sampleColor: Color? = nil
    let sampleSize: CGFloat
    let axis: WeightAxis

    @EnvironmentObject var toasts: ToastCenter
    @State private var weight: Double

    init(basePSName: String, familyName: String, sampleText: String, sampleColor: Color?, sampleSize: CGFloat, axis: WeightAxis) {
        self.basePSName = basePSName
        self.familyName = familyName
        self.sampleText = sampleText
        self.sampleColor = sampleColor
        self.sampleSize = sampleSize
        self.axis = axis
        _weight = State(initialValue: axis.defaultValue)
    }

    private var canExport: Bool {
        SVGTextExporter.canExport(text: sampleText, fontName: basePSName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Variable")
                    .font(.system(size: Theme.bodySize, weight: .medium))
                    .foregroundStyle(.primary)
                // Slider + its value, kept as a tight cluster. The slider sits
                // where the PostScript name is on the static rows: sized to 180pt
                // then scaled to 90% (handle + track — the native Slider doesn't
                // expose the handle size on its own), with the outer frame
                // reserving exactly the scaled 162pt so there's no centering slack.
                // The value is leading-aligned so it hugs the slider's right edge.
                HStack(spacing: 10) {
                    Slider(value: $weight, in: axis.minValue...axis.maxValue)
                        .controlSize(.small)
                        .frame(width: 180)
                        .scaleEffect(0.9)
                        .frame(width: 180 * 0.9)
                    Text("\(Int(weight.rounded()))")
                        .font(.system(size: Theme.smallSize).monospaced())
                        .foregroundStyle(.tertiary)
                        .frame(width: 34, alignment: .leading)
                }
                Spacer(minLength: 8)
                ExportButton(enabled: canExport, action: exportArtwork)
            }
            WrappingPreviewLabel(
                text: sampleText,
                fontName: basePSName,
                fontSize: sampleSize,
                color: sampleColor,
                variationAxisID: axis.id,
                variationWeight: weight
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Export the sample at the slider's current weight; the file stem ends with
    // "VF(nnn)" so the exact weight is captured in the name.
    private func exportArtwork() {
        func clean(_ s: String) -> String { s.replacingOccurrences(of: "/", with: "-") }
        let w = Int(weight.rounded())
        let baseName = "08FOSE) \(clean(familyName))_VF(\(w))"
        WeightArtwork.export(text: sampleText, fontName: basePSName, baseName: baseName,
                             variation: (axisID: axis.id, value: weight), toasts: toasts)
    }
}

// MARK: - Weight Row

struct WeightRow: View {
    let psName: String
    let familyName: String
    let sampleText: String
    var sampleColor: Color? = nil
    let sampleSize: CGFloat

    @EnvironmentObject var toasts: ToastCenter

    private var faceName: String {
        guard let font = NSFont(name: psName, size: 12) else { return psName }
        return (font.fontDescriptor.object(forKey: .face) as? String) ?? psName
    }

    private var canExport: Bool {
        SVGTextExporter.canExport(text: sampleText, fontName: psName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(faceName)
                        .font(.system(size: Theme.bodySize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(psName)
                        .font(.system(size: Theme.smallSize).monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                // ▶︎ pinned to the right edge of the row, centered to the line.
                ExportButton(enabled: canExport, action: exportArtwork)
            }
            WrappingPreviewLabel(text: sampleText, fontName: psName, fontSize: sampleSize, color: sampleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Flatten this weight's sample text and save as SVG or PNG.
    private func exportArtwork() {
        WeightArtwork.export(text: sampleText, fontName: psName, baseName: artworkBaseName, toasts: toasts)
    }

    // e.g. "08FOSE) SDMapssi_Regular"  ("/" sanitized for the filesystem). No
    // extension — NSSavePanel appends one based on `allowedContentTypes`.
    private var artworkBaseName: String {
        func clean(_ s: String) -> String { s.replacingOccurrences(of: "/", with: "-") }
        return "08FOSE) \(clean(familyName))_\(clean(faceName))"
    }
}

// Shared weight-row artwork export: a Save panel (format + color accessory)
// that flattens `text` in `fontName` — optionally at a specific variation
// weight — to SVG or PNG. Used by both the static weight rows and the
// variable-weight row (which supplies a `variation` and a "VF(nnn)" base name).
enum WeightArtwork {
    @MainActor
    static func export(text: String, fontName: String, baseName: String,
                       variation: (axisID: Int, value: Double)? = nil,
                       toasts: ToastCenter) {
        guard SVGTextExporter.canExport(text: text, fontName: fontName) else { NSSound.beep(); return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.showsTagField = false
        panel.nameFieldStringValue = baseName
        panel.allowedContentTypes = [.svg]

        let accessory = ExportOptionsAccessory()
        accessory.onFormatChange = { [weak panel] fmt in
            guard let panel else { return }
            panel.allowedContentTypes = [fmt == .svg ? .svg : .png]
        }
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Both failure legs matter: a nil render means the save panel closed
        // normally but NO file exists — without the error toast that's an
        // invisible failure the user only discovers later in Finder.
        let rendered: Data?
        switch accessory.format {
        case .svg:
            rendered = SVGTextExporter.svg(text: text, fontName: fontName,
                                           fill: accessory.colorHex, variation: variation)?.data(using: .utf8)
        case .png:
            rendered = SVGTextExporter.pngData(text: text, fontName: fontName,
                                               color: accessory.color, variation: variation)
        }
        let format = accessory.format == .svg ? "SVG" : "PNG"
        guard let rendered else {
            toasts.show(Toast(style: .error, title: "\(format) export failed",
                              detail: "The sample couldn't be rendered — no file was written."))
            return
        }
        do {
            try rendered.write(to: url)
            toasts.show(Toast(
                style: .success,
                title: "\(format) exported",
                detail: url.lastPathComponent,
                icon: "square.and.arrow.up"
            ))
        } catch {
            toasts.show(Toast(style: .error, title: "\(format) export failed",
                              detail: "Couldn't write to \(url.lastPathComponent). Try a different folder."))
        }
    }
}

// Save-panel accessory: format picker (SVG/PNG) on the left, two-swatch
// black/white color picker pinned to the right. The color applies to both
// formats (SVG `fill` / PNG fill). Defaults: SVG + black, reset every export.
//
// An explicit frame is set so NSSavePanel widens to fit — autolayout-only
// sizing leaves the view at 0×0 and clips controls under Cancel/Save.
private final class ExportOptionsAccessory: NSView {
    enum Format { case svg, png }

    private(set) var format: Format = .svg
    var color: NSColor { palette.color }
    var colorHex: String { palette.colorHex }
    var onFormatChange: ((Format) -> Void)?

    private let formatPopUp = NSPopUpButton()
    private let palette: SwatchPalette

    init() {
        // System (not app-override) appearance decides which fill comes first
        // and starts selected: black in system Dark mode, white in Light mode.
        let isSystemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        self.palette = SwatchPalette(blackFirst: isSystemDark)
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 60))

        formatPopUp.addItems(withTitles: ["SVG", "PNG"])
        formatPopUp.target = self
        formatPopUp.action = #selector(formatChanged)

        let formatLabel = NSTextField(labelWithString: "Format:")
        formatLabel.alignment = .right

        for v in [formatLabel, formatPopUp, palette] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            // Left cluster: "Format:" label + popup. The label is right-aligned
            // with a fixed trailing X so the colon lines up with the native
            // "Save As:" / "Where:" colons above. (Tune this constant if the
            // colons drift on a different macOS or with a wider panel.)
            formatLabel.trailingAnchor.constraint(equalTo: leadingAnchor, constant: 92),
            formatLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            formatPopUp.leadingAnchor.constraint(equalTo: formatLabel.trailingAnchor, constant: 8),
            formatLabel.centerYAnchor.constraint(equalTo: formatPopUp.centerYAnchor),

            // Right cluster: swatches pinned to the trailing edge. The palette
            // reports its full bounds incl. the accent ring, so the constant
            // lands flush with the visible ring edge.
            palette.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            palette.leadingAnchor.constraint(greaterThanOrEqualTo: formatPopUp.trailingAnchor, constant: 24),
            palette.centerYAnchor.constraint(equalTo: formatPopUp.centerYAnchor),

            // Vertical centering of the whole row.
            formatPopUp.centerYAnchor.constraint(equalTo: centerYAnchor),
            formatPopUp.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
            formatPopUp.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc private func formatChanged() {
        format = formatPopUp.indexOfSelectedItem == 1 ? .png : .svg
        onFormatChange?(format)
    }

    // When the accessory lands in the save panel's window, tweak the panel's
    // chrome: hide the separator hairlines above/below the accessory (so the
    // Format row flows with the Save As / Where rows above), and nudge the
    // Cancel/Save buttons leftward. Deferred to the next runloop tick so the
    // panel has finished laying out its private subviews.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let root = self?.window?.contentView else { return }
            Self.hideSeparators(in: root)
            Self.nudgeFooterButtons(in: root, dx: -20)
        }
    }

    // Hide every hairline-looking view in the panel chrome — NSBox separators,
    // any view whose class name hints at "Separator"/"Divider", and anonymous
    // 1pt-tall horizontal NSViews (which is how modern NSSavePanel actually
    // paints the dividers around accessoryView).
    private static func hideSeparators(in view: NSView) {
        let className = String(describing: type(of: view))
        var hide = false
        if let box = view as? NSBox, box.boxType == .separator {
            hide = true
        } else if className.contains("Separator") || className.contains("Divider") {
            hide = true
        } else if type(of: view) == NSView.self,
                  view.frame.height > 0, view.frame.height <= 1,
                  view.frame.width > 100 {
            hide = true
        }
        if hide { view.isHidden = true }
        view.subviews.forEach { hideSeparators(in: $0) }
    }

    // Translate the panel's default (Return / Escape) buttons — Cancel & Save
    // — horizontally. Identified by key equivalent so localization doesn't
    // matter. Best-effort: if autolayout re-pins them, this won't stick.
    private static func nudgeFooterButtons(in view: NSView, dx: CGFloat) {
        if let btn = view as? NSButton,
           ["\r", "\u{1b}"].contains(btn.keyEquivalent) {
            var f = btn.frame
            f.origin.x += dx
            btn.frame = f
        }
        view.subviews.forEach { nudgeFooterButtons(in: $0, dx: dx) }
    }
}

// Two inline swatches — black and white. Click to select; the active swatch
// gets an accent ring. No popover, no NSColorPanel. Order is set at init —
// whichever color is at index 0 sits on the left and is selected by default.
private final class SwatchPalette: NSView {
    let swatches: [NSColor]
    let hexValues: [String]

    private let cell: CGFloat = 14
    private let gap: CGFloat = 6
    private let ringInset: CGFloat = 2     // accent ring extends this far past each cell
    private let ringWidth: CGFloat = 1.5

    private(set) var selected: Int = 0
    var color: NSColor { swatches[selected] }
    var colorHex: String { hexValues[selected] }

    init(blackFirst: Bool) {
        if blackFirst {
            self.swatches = [.black, .white]
            self.hexValues = ["#000000", "#ffffff"]
        } else {
            self.swatches = [.white, .black]
            self.hexValues = ["#ffffff", "#000000"]
        }
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(swatches.count)
        // Include the ring margin on every side so the trailing constraint
        // lands flush with the visible ring edge instead of clipping it.
        return NSSize(
            width: count * cell + (count - 1) * gap + ringInset * 2,
            height: cell + ringInset * 2
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, c) in swatches.enumerated() {
            let r = rect(for: i)
            let path = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            c.setFill()
            path.fill()
            // Hairline so white stays visible against the panel background.
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            if i == selected {
                let ring = NSBezierPath(roundedRect: r.insetBy(dx: -ringInset, dy: -ringInset),
                                        xRadius: 5, yRadius: 5)
                NSColor.controlAccentColor.setStroke()
                ring.lineWidth = ringWidth
                ring.stroke()
            }
        }
    }

    private func rect(for index: Int) -> NSRect {
        // Inset by the ring margin on the left so the leftmost ring stays
        // inside view bounds; vertical centering handles top/bottom margin.
        let x = ringInset + CGFloat(index) * (cell + gap)
        let y = (bounds.height - cell) / 2
        return NSRect(x: x, y: y, width: cell, height: cell)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in 0..<swatches.count where rect(for: i).contains(p) {
            selected = i
            needsDisplay = true
            break
        }
    }
}

// Small ▶︎ button on a weight row: exports that weight's sample text (SVG or
// PNG — picked in the save panel's accessory view). A bare rounded-corner
// triangle (no chrome). The glyph is drawn at 84% of the text height with
// subtly rounded vertices, while the hit area stays at the full text height.
// Disabled (and dimmed) when there are no outlines to export — empty text, or
// a bitmap/color font.
private struct ExportButton: View {
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    private var ink: Color { hovering ? Theme.accent : .secondary }

    var body: some View {
        let triH = Theme.bodySize * 0.588 + 3   // 3px larger than before
        let triW = triH * 0.82                  // play-button proportions
        let hit = triH + 5                       // click target a bit past the glyph
        let rounding = triH * 0.4            // corner rounding (offset along edges)

        return Button(action: action) {
            Group {
                if enabled {
                    PlayTriangle(rounding: rounding)
                        .fill(ink)
                        .opacity(0.5)
                } else {
                    // Disabled: thin outline only, no fill.
                    PlayTriangle(rounding: rounding)
                        .stroke(ink, style: StrokeStyle(lineWidth: 0.5, lineJoin: .round))
                }
            }
            .frame(width: triW, height: triH)
            .offset(y: 1)                    // nudge down 1px to sit on the line
            .frame(width: hit, height: hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = enabled && $0 }
        .help(enabled ? "Export this weight's sample text (SVG or PNG)"
                      : "No vector outlines to export")
    }
}

// Right-pointing triangle (play-button shape) with rounded corners. `rounding`
// is how far each corner is cut back along its two edges; the vertex itself
// becomes the control point of a quadratic curve, so the corner reads as a true
// arc (clamped to half the shorter adjacent edge so it never self-overlaps).
private struct PlayTriangle: Shape {
    var rounding: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let pts = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        var path = Path()
        guard rounding > 0 else {
            path.addLines(pts)
            path.closeSubpath()
            return path
        }
        let n = pts.count
        for i in 0..<n {
            let cur = pts[i]
            let prev = pts[(i + n - 1) % n]
            let next = pts[(i + 1) % n]
            let toPrev = unit(from: cur, to: prev)
            let toNext = unit(from: cur, to: next)
            let rPrev = min(rounding, dist(cur, prev) * 0.5)
            let rNext = min(rounding, dist(cur, next) * 0.5)
            let start = CGPoint(x: cur.x + toPrev.dx * rPrev, y: cur.y + toPrev.dy * rPrev)
            let end = CGPoint(x: cur.x + toNext.dx * rNext, y: cur.y + toNext.dy * rNext)
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: cur)
        }
        path.closeSubpath()
        return path
    }

    private func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return CGVector(dx: dx / len, dy: dy / len)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
    }
}

// Title-area action button (Pin / Copy name / Show in Finder) with a
// light hover state: the fill grows a little denser on rollover.
private struct ActionButton: View {
    let icon: String?
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: Theme.bodySize))
                }
                Text(label).font(.system(size: Theme.bodySize))
            }
            .foregroundStyle(active ? Theme.accent : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(active ? Theme.accent.opacity(0.4) : Theme.border, lineWidth: 1)
            )
            .unifiedGeometry()
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
    }

    private var fillColor: Color {
        if active { return Theme.accent.opacity(hovering ? 0.16 : 0.08) }
        return hovering ? Theme.surfaceFillHover : Theme.surfaceFill
    }
}
