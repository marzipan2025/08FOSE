import SwiftUI
import AppKit
import CoreText

struct FontDetailView: View {
    let family: FontFamily
    let previewText: String
    let onClose: () -> Void

    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @EnvironmentObject var samples: SampleStore
    @EnvironmentObject var muted: MutedStore
    @EnvironmentObject var vm: AppViewModel
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

    private var isFavorited: Bool { favorites.contains(family.name) }
    private var isMuted: Bool { muted.contains(family.name) }

    // A non-empty custom sample for this family overrides the global preview
    // text across every weight (and is drawn in the accent color).
    private var hasCustomSample: Bool { samples.hasSample(for: family.name) }

    private var sampleText: String {
        if hasCustomSample { return samples.sample(for: family.name) }
        return previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText
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
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                // Light mode: card body is brighter than the global panel bg
                // (0.92 → 0.952, white-ward 40%) so the card lifts off the grid.
                .fill(colorScheme == .light ? Color(white: 0.952) : Theme.panelBackground)
                .shadow(color: .black.opacity(0.55 * shadowScale), radius: 14, x: 0, y: 10)
                .shadow(color: .black.opacity(0.75 * shadowScale), radius: 60, x: 0, y: 38)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .light ? Color(white: 0.56) : Color.white, lineWidth: 1)
        )
        // Tapping the card's empty background drops any text-input focus (search
        // / memo / preview bar) so the ←/→ navigation works again. Buttons and
        // the memo field handle their own taps first, so they're unaffected.
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .task(id: family.id) {
            infoExpanded = false
            memoExpanded = false
            memoContentHeight = 0
            glyphFontPS = nil
            metadata = FontMetadata.load(family: family)
        }
    }

    // MARK: - Layouts

    // Wide: the info column lives in the right of the middle (weight-list)
    // section only. Title and memo keep the card's full width.
    private func wideLayout(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleArea
            Rectangle().fill(detailDivider).frame(height: 1)
            HStack(spacing: 0) {
                weightList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !metadata.isEmpty {
                    infoColumn
                        .frame(width: max(180, width * 0.25))
                }
            }
            .frame(maxHeight: .infinity)
            Rectangle().fill(detailDivider).frame(height: 1)
            memoArea(cardHeight: height)
        }
    }

    // Narrow: info flows as multiple aligned columns directly under the header,
    // with no dividing lines and no per-item boxes. Capped to 2 rows with a
    // "Read more" toggle when it overflows. The info and the sample list share
    // one scroll so nothing gets clipped between them.
    private func narrowLayout(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleArea
            Rectangle().fill(detailDivider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !metadata.isEmpty { infoColumns(width: width) }
                    weightListContent
                    if vm.detailGlyphsVisible { glyphsSection }
                }
            }
            .frame(maxHeight: .infinity)
            // Reset scroll to top when ←/→ switches fonts.
            .id(family.id)
            Rectangle().fill(detailDivider).frame(height: 1)
            memoArea(cardHeight: height)
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

    // Memo strip background. Light mode uses a brighter solid (≈0.93,
    // white-ward 40%) instead of the global memoSurface overlay.
    private var memoAreaBackground: Color {
        colorScheme == .light ? Color(white: 0.93) : Theme.memoSurface
    }

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
                    Text("\(family.weightCount) weight\(family.weightCount == 1 ? "" : "s")")
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
                    label: isFavorited ? "Favorited" : "Favorite",
                    active: isFavorited
                ) { favorites.toggle(family.name) }

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
                ) { muted.toggle(family.name) }
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
            weightListContent
            if vm.detailGlyphsVisible { glyphsSection }
        }
        // Fresh identity per font so ←/→ navigation starts back at the top
        // instead of keeping the previous font's scroll offset.
        .id(family.id)
    }

    private var weightListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(family.memberFontNames.enumerated()), id: \.offset) { index, psName in
                WeightRow(psName: psName, sampleText: sampleText, sampleColor: sampleColor, sampleSize: CGFloat(vm.weightRowFontSize))
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
                GlyphCell(font: font, glyph: CGGlyph(index), character: glyphMap[CGGlyph(index)])
                    .frame(height: cell)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: GlyphAreaWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(GlyphAreaWidthKey.self) { glyphAreaWidth = $0 }
    }

    // MARK: - Actions

    private func openInFinder() {
        guard let psName = family.memberFontNames.first else { return }
        let descriptor = CTFontDescriptorCreateWithNameAndSize(psName as CFString, 0)
        guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false
    @State private var showCopied = false

    var body: some View {
        Canvas { ctx, size in
            // Non-copyable glyphs (outline box) are drawn more faded.
            let ink = (colorScheme == .light ? NSColor.black : NSColor.white)
                .withAlphaComponent(character != nil ? 0.85 : 0.5)
            ctx.withCGContext { cg in
                // Flip to a y-up text space (Canvas is y-down, top-left origin).
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                if let character {
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
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { handleTap() }
        // Hover tooltip: the character this glyph maps to. Empty when unmapped.
        .nativeTooltip(character ?? "")
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

// MARK: - Weight Row

struct WeightRow: View {
    let psName: String
    let sampleText: String
    var sampleColor: Color? = nil
    let sampleSize: CGFloat

    private var faceName: String {
        guard let font = NSFont(name: psName, size: 12) else { return psName }
        return (font.fontDescriptor.object(forKey: .face) as? String) ?? psName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            WrappingPreviewLabel(text: sampleText, fontName: psName, fontSize: sampleSize, color: sampleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Title-area action button (Favorite / Copy name / Show in Finder) with a
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
