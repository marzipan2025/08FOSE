import SwiftUI

struct RightPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var pins: PinsStore
    @EnvironmentObject var memos: MemoStore
    @EnvironmentObject var glyphs: GlyphsStore
    @State private var sortHovering = false
    // Collapsed on arrival: the list is a convenience, not something to keep
    // open, and it sits under two sections that are.
    @State private var glyphsExpanded = false
    @State private var glyphsChevronHovering = false
    // When true, the TAGS section grows up to cover the pins list (down to
    // just below the PINNED divider).
    @State private var tagsExpanded = false
    @State private var tagsChevronHovering = false

    private var hasTags: Bool { !memos.tagCounts.isEmpty }
    private var hasGlyphs: Bool { !glyphs.glyphs.isEmpty }

    // GLYPHS is open and has something to show, so it is holding the space the
    // tags chips were in.
    private var glyphsOwnsSpace: Bool { glyphsExpanded && hasGlyphs }
    // TAGS is open over the pins list. Stays true while GLYPHS is on top of it,
    // so collapsing GLYPHS puts the panel back exactly as it was.
    private var tagsCoversPins: Bool { hasTags && tagsExpanded }

    @ViewBuilder
    private var pinsArea: some View {
        if pins.ordered.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("No pins yet.")
                    .font(.system(size: Theme.smallSize))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.panelHPadding)
                    .padding(.vertical, Theme.panelVPadding)
                Spacer(minLength: 0)
            }
        } else {
            pinsList
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pinsHeader
                .padding(.horizontal, Theme.panelHPadding)
                .padding(.vertical, Theme.panelVPadding)
            PanelHDivider()

            // The three sections stack, and a section opening takes its space
            // from the ones ABOVE it, never the ones below. So TAGS opens over
            // the pins list, and GLYPHS opens over the tags — and over the pins
            // too, if TAGS had already covered them. Nothing below ever moves,
            // which is what makes the chevrons predictable: each one only ever
            // grows upward.
            if !tagsCoversPins {
                pinsArea
                    .frame(maxHeight: .infinity)
                // Only when the pins list is actually between the two headers.
                // Emitting it unconditionally put this rule hard against the
                // one under the pins header whenever TAGS had covered the list,
                // and two 1pt rules touching draw as one 2pt rule.
                if hasTags {
                    PanelHDivider()
                }
            }

            if hasTags {
                tagsSection(expanded: tagsCoversPins, chipsHidden: glyphsOwnsSpace)
                    .frame(maxHeight: tagsCoversPins && !glyphsOwnsSpace ? .infinity : nil)
            }

            PanelHDivider()
            glyphsSection

            PanelHDivider()
            versionFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBackground.ignoresSafeArea())
    }

    private var versionFooter: some View {
        Text("© pa_st - v \(Theme.appVersion)")
            .font(.system(size: Theme.smallSize))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Theme.panelHPadding)
            // Right-aligned so the bottom-inner corner is free for the floating
            // panel-collapse button (see RootView).
            .frame(maxWidth: .infinity, alignment: .trailing)
            // 44 = old 36 + 8: lifts the divider 8px and centers the text in the
            // taller footer region (matches the left panel's Settings footer);
            // nudged up 3px.
            .frame(height: 44)
            .offset(y: -3)
    }

    // MARK: - Copied glyphs

    private var glyphsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            glyphsHeader
                .padding(.horizontal, Theme.panelHPadding)
                .padding(.vertical, Theme.panelVPadding)

            // Built exactly like the tags chips above, and for the same reason:
            // the grid STAYS in the tree and only its height animates.
            //
            // It used to sit behind an `if`, which reads as the tidier thing to
            // write but hands SwiftUI an insert/remove instead of a resize. The
            // cells then dissolved on the transition's own clock while the
            // header travelled on the layout animation's — so they faded in at
            // their final position before the header had finished moving to
            // meet them, and the section read as two pieces. Animating one
            // height moves the header and the cells as the single block they
            // are. The divider rides inside it so nothing is left behind when
            // the height goes to zero.
            VStack(alignment: .leading, spacing: 0) {
                PanelHDivider()
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Self.glyphGridSpacing),
                                       count: Self.glyphColumns),
                        spacing: Self.glyphGridSpacing
                    ) {
                        ForEach(glyphs.glyphs) { entry in
                            CopiedGlyphCard(
                                entry: entry,
                                onCopy: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.character, forType: .string)
                                },
                                onOpen: {
                                    guard let family = vm.library.families
                                        .first(where: { $0.name == entry.familyName }) else { return false }
                                    // Already on this font: don't reopen the
                                    // card, just move it to the glyph. Reopening
                                    // would replay the expand animation over a
                                    // card that is already where it belongs.
                                    if vm.selectedFamily?.name != family.name {
                                        vm.openDetail(family, source: .grid)
                                    }
                                    vm.glyphFocus = AppViewModel.GlyphFocus(
                                        familyName: entry.familyName,
                                        psName: entry.psName,
                                        character: entry.character
                                    )
                                    return true
                                },
                                onDelete: { glyphs.remove(entry) }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.panelHPadding)
                    .padding(.top, 16)
                    .padding(.bottom, Theme.panelVPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
            }
            .frame(maxHeight: glyphsContentHeight)
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: glyphsOwnsSpace && tagsCoversPins ? .infinity : nil)
    }

    // Zero when shut. Open, it takes everything left over if TAGS had already
    // cleared the pins list, and otherwise just the slot the chips vacated.
    private var glyphsContentHeight: CGFloat {
        guard glyphsOwnsSpace else { return 0 }
        return tagsCoversPins ? .infinity : Self.stackedSlotHeight
    }

    // Three to a row at the panel's default width, which is what sets the card
    // size — they shrink and grow with the panel from there.
    private static let glyphColumns = 3
    private static let glyphGridSpacing: CGFloat = 8

    private var chevronColor: HierarchicalShapeStyle {
        guard hasGlyphs else { return .quaternary }
        return glyphsChevronHovering ? .primary : .secondary
    }

    private var glyphsHeader: some View {
        HStack(spacing: 8) {
            Text("GLYPHS")
                .font(.system(size: Theme.sectionHeaderSize, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text("\(glyphs.glyphs.count)")
                .font(.system(size: Theme.smallSize, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 8)
            // The section stays on the panel even with nothing in it, so the
            // place a copied glyph will land is visible before the first one
            // does. With nothing to show there is nothing to open, so the
            // chevron goes quiet rather than expanding onto an empty box.
            Button {
                guard hasGlyphs else { return }
                withAnimation(.easeOut(duration: 0.2)) { glyphsExpanded.toggle() }
            } label: {
                Image(systemName: glyphsExpanded && hasGlyphs ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(chevronColor)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(!hasGlyphs)
            .onHover { glyphsChevronHovering = $0 }
            .help(hasGlyphs ? (glyphsExpanded ? "Collapse glyphs" : "Expand glyphs")
                            : "Click a glyph in a font's detail to keep it here")
        }
    }

    // MARK: - Tags

    // Append a tag (as a "#tag" token) to the open font's memo. If the memo
    // already has text, the tag is added after it, separated by a space so it
    // parses as its own token.
    private func appendTagToMemo(_ tag: String, family: FontFamily) {
        let token = "#\(tag)"
        let existing = memos.note(for: family.name)
        let newNote = existing.isEmpty ? token : existing + " " + token
        memos.setNote(newNote, for: family.name)
    }

    // `chipsHidden` leaves only the header — the state TAGS is in while GLYPHS
    // is expanded into the room the chips were using.
    private func tagsSection(expanded: Bool, chipsHidden: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tagsHeader
                .padding(.horizontal, Theme.panelHPadding)
                .padding(.vertical, Theme.panelVPadding)
            if !chipsHidden {
            PanelHDivider()
            ScrollView {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(memos.tagCounts, id: \.tag) { item in
                        TagCapsule(
                            tag: item.tag,
                            count: item.count,
                            active: vm.selectedFamily == nil && vm.activeTag == item.tag
                        ) {
                            // With the detail open, a tag tap appends the tag to
                            // that font's memo; otherwise it toggles the filter.
                            if let family = vm.selectedFamily {
                                appendTagToMemo(item.tag, family: family)
                            } else {
                                vm.activeTag = (vm.activeTag == item.tag) ? nil : item.tag
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.panelHPadding)
                .padding(.top, 16)
                .padding(.bottom, Theme.panelVPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: expanded ? .infinity : Self.stackedSlotHeight)
            .scrollContentBackground(.hidden)
            }
        }
    }

    // How tall a section gets when it is open but something below it is open
    // too — the slot the tags chips occupy at rest, which is also what GLYPHS
    // grows into when it takes that slot over.
    private static let stackedSlotHeight: CGFloat = 256

    private var tagsHeader: some View {
        HStack(spacing: 8) {
            Text("TAGS")
                .font(.system(size: Theme.sectionHeaderSize, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text("\(memos.tagCounts.count)")
                .font(.system(size: Theme.smallSize, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 8)
            // Expand/collapse over the pins list. Same chevron as the memo
            // area's toggle, but without the filled background.
            // While GLYPHS is covering the chips, this chevron's job is to get
            // them back rather than to toggle how far they reach — so it folds
            // GLYPHS away and leaves tagsExpanded exactly as it was.
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if glyphsOwnsSpace { glyphsExpanded = false }
                    else { tagsExpanded.toggle() }
                }
            } label: {
                Image(systemName: tagsCoversPins && !glyphsOwnsSpace ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tagsChevronHovering ? .primary : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { tagsChevronHovering = $0 }
            .help(tagsExpanded ? "Collapse tags" : "Expand tags")
        }
    }

    private var pinsHeader: some View {
        HStack(spacing: 8) {
            Text("PINNED")
                .font(.system(size: Theme.sectionHeaderSize, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if !pins.ordered.isEmpty {
                Text("\(pins.ordered.count)")
                    .font(.system(size: Theme.smallSize, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 8)
            if !pins.ordered.isEmpty {
                sortToggle
            }
        }
    }

    private var sortToggle: some View {
        Button {
            vm.pinsByRecent.toggle()
        } label: {
            Text(vm.pinsByRecent ? "Recent" : "A–Z")
                .font(.system(size: Theme.smallSize, weight: .medium))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .frame(width: 56)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.accent.opacity(sortHovering ? 0.24 : 0.15))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { sortHovering = $0 }
        .help("Sort: \(vm.pinsByRecent ? "most recent first" : "alphabetical")")
    }

    private var displayedPins: [String] {
        vm.pinsByRecent ? pins.byRecency : pins.sorted
    }

    // Resolve the deterministic preview face per the weight rule, falling back
    // to the family name when no Regular / 400 / 500 member exists. Deliberately
    // NOT tied to the Face filter: pins are a fixed list that filters never
    // thin out, so the rows stay on the family's usual face no matter what the
    // grid is currently showing.
    private func previewFontName(for name: String) -> String {
        (vm.library.families.first { $0.name == name }?.previewFontName) ?? name
    }

    private var pinsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedPins, id: \.self) { name in
                    PinRow(name: name, previewFontName: previewFontName(for: name), tooltipSuppressed: vm.showSettings) {
                        if let family = vm.library.families.first(where: { $0.name == name }) {
                            vm.openDetail(family, source: .pins)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Tag Capsule

// A pill button for one note tag in the right panel. Shows the tag (without
// '#') and how many fonts use it; highlights in the accent color when active.
struct TagCapsule: View {
    let tag: String
    let count: Int
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(tag)
                    .font(.system(size: Theme.smallSize + 1, weight: .medium))
                Text("\(count)")
                    .font(.system(size: Theme.smallSize))
                    .monospacedDigit()
                    .opacity(0.6)
            }
            .foregroundStyle(active ? Theme.accent : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(active ? Theme.accent.opacity(0.16)
                                      : (hovering ? Theme.surfaceFillHover : Theme.surfaceFill))
            )
            .overlay(
                Capsule().stroke(active ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

// MARK: - Pin Row

struct PinRow: View {
    let name: String
    // PostScript face used to render the sample (deterministic weight); falls
    // back to the family name upstream when no preferred member exists.
    var previewFontName: String
    var tooltipSuppressed: Bool = false
    let onSelect: () -> Void
    @EnvironmentObject var pins: PinsStore
    @EnvironmentObject var memos: MemoStore
    @EnvironmentObject var samples: SampleStore
    @EnvironmentObject var inputSource: InputSourceManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("previewText") private var previewText: String = "The quick brown fox jumps over lazy dog"
    @State private var hovering = false

    // Light mode uses a lighter shadow (30% of dark-mode strength), matching
    // the font cells.
    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    private var hasMemo: Bool { memos.hasNote(for: name) }
    private var hasSpecimen: Bool { samples.hasSample(for: name) }

    private var sampleText: String {
        // A custom specimen replaces the preview text here too (color unchanged).
        if hasSpecimen { return samples.sample(for: name) }
        return inputSource.resolved(previewText)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: Theme.smallSize))
                    .foregroundStyle(Theme.weightBadge)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Nudge up to line the name up with the trailing dot, without
                    // changing the row's layout height.
                    .offset(y: -2)

                Text(sampleText)
                    .font(.custom(previewFontName, size: 20))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // 34: extra headroom top and bottom so tall scripts (e.g.
                    // Hangul, incl. fallback-font glyphs) aren't clipped, font
                    // size unchanged.
                    .frame(height: 34, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .offset(y: -3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                if hasMemo || hasSpecimen {
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
                Button { pins.toggle(name) } label: {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 9, height: 9)
                }
                .buttonStyle(.plain)
            }
            .opacity(hovering ? 1 : 0.7)
        }
        .padding(.horizontal, 10)
        // Top margin matches the horizontal margin so the pin dot sits the
        // same distance from the top edge as from the right edge.
        .padding(.top, 10)
        // 65: grows with the taller sample area above.
        .frame(height: 65, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Theme.rowHoverFill : .clear)
                // Soft, wide shadow dropping below the row; lighter in light mode.
                .shadow(color: .black.opacity(hovering ? 0.45 * shadowScale : 0),
                        radius: hovering ? 28 : 0, x: 0, y: hovering ? 17 : 0)
        )
        .zIndex(hovering ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering = $0 }
        .nativeTooltip(memoTooltip)
    }

    // Hover tooltip: the memo text (up to 16 chars) when one exists, else empty,
    // shown exactly as written (including any '#' tag markers).
    private var memoTooltip: String {
        // No tooltip while it would be hidden behind the Settings blur.
        guard !tooltipSuppressed else { return "" }
        let note = memos.note(for: name)
        guard !note.isEmpty else { return "" }
        return note.count > 16 ? String(note.prefix(16)) + "…" : note
    }
}

// The delete button's X, traced from x_btn.svg. The artwork is a 60x60 box
// holding a full-bleed disc and this mark, so the coordinates below are kept in
// that space and scaled to whatever rect the view gets — which is what keeps
// the mark's size and position relative to the disc exactly as drawn.
//
// Colour is deliberately NOT baked in here: the button inverts between light
// and dark, so the shape only describes the geometry and the view fills it.
private struct XMark: Shape {
    private static let artboard: CGFloat = 60

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.artboard
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()

        path.move(to: pt(18.6854, 21.514))
        path.addCurve(to: pt(18.6854, 18.6856),
                      control1: pt(17.9043, 20.733), control2: pt(17.9043, 19.4666))
        path.addCurve(to: pt(21.5138, 18.6856),
                      control1: pt(19.4664, 17.9045), control2: pt(20.7328, 17.9045))
        path.addLine(to: pt(41.3128, 38.4846))
        path.addCurve(to: pt(41.3128, 41.313),
                      control1: pt(42.0939, 39.2656), control2: pt(42.0939, 40.5319))
        path.addCurve(to: pt(38.4844, 41.313),
                      control1: pt(40.5318, 42.094), control2: pt(39.2654, 42.094))
        path.closeSubpath()

        path.move(to: pt(38.4844, 18.6854))
        path.addCurve(to: pt(41.3128, 18.6854),
                      control1: pt(39.2655, 17.9043), control2: pt(40.5318, 17.9043))
        path.addCurve(to: pt(41.3128, 21.5138),
                      control1: pt(42.0939, 19.4664), control2: pt(42.0939, 20.7328))
        path.addLine(to: pt(21.5138, 41.3128))
        path.addCurve(to: pt(18.6854, 41.3128),
                      control1: pt(20.7328, 42.0939), control2: pt(19.4665, 42.0939))
        path.addCurve(to: pt(18.6854, 38.4844),
                      control1: pt(17.9044, 40.5318), control2: pt(17.9044, 39.2654))
        path.closeSubpath()

        return path
    }
}

// MARK: - Copied Glyph Card

// One glyph kept from a detail card. The box deliberately mirrors the glyph
// tiles in the center panel (same corner radius, same fill and hover density),
// so a glyph reads as the same object in both places.
//
// Tapping the card — the whole surface, and the reason the card exists —
// copies the glyph again, and confirms it with the same COPIED flash the glyph
// grid uses, scaled to this smaller box. One smaller target rides on top,
// revealed on rollover so the resting grid stays all glyph: delete, overhanging
// the top-right corner.
struct CopiedGlyphCard: View {
    let entry: CopiedGlyph
    let onCopy: () -> Void
    // Returns whether the font was actually opened — a card whose family is no
    // longer installed has nothing to open, and must not claim otherwise.
    let onOpen: () -> Bool
    let onDelete: () -> Void

    // What the card is confirming, if anything. Copy wears the accent, the
    // app's "that worked" colour. Opening wears plain ink instead: it is
    // navigation rather than a result, and the accent would overstate it.
    //
    // `.primary`, not a literal black — black is exactly what it resolves to in
    // light mode, and in dark mode a black word would be unreadable on the card
    // and a black wash invisible against it.
    private enum Flash {
        case copied, opened

        var label: String {
            switch self {
            case .copied: return "COPIED"
            case .opened: return "OPEN"
            }
        }
        var tint: Color {
            switch self {
            case .copied: return Theme.accent
            case .opened: return .primary
            }
        }
        // Ink carries further than the accent at the same value, so it washes
        // a little lighter to land at the same weight.
        var washOpacity: Double {
            switch self {
            case .copied: return 0.10
            case .opened: return 0.07
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false
    @State private var deleteHovering = false
    @State private var flashWord: Flash? = nil
    // The wash is its own state so it can run on its own clock: it leaves a
    // little ahead of the word, which keeps the two from reading as one slab of
    // colour arriving and going.
    @State private var flashWash: Flash? = nil
    // True from the moment a long press fires until the next press begins, so
    // the tap that may follow the release opens nothing and copies nothing.
    @State private var openedByHold = false

    private static let radius: CGFloat = 12
    private static let height: CGFloat = 64
    private static let glyphSize: CGFloat = 28
    // The grid's own COPIED label is 10pt on a cell that starts at 56pt and
    // grows with the preview-size slider; this box is fixed and smaller than
    // that for most of the slider's range, so the label comes down with it.
    private static let copiedSize: CGFloat = 8
    // A shade quicker than the word it accompanies.
    private static let washSpeedup: Double = 0.75
    // Long enough not to fire while someone is simply clicking, short enough
    // that holding doesn't feel like waiting.
    private static let holdToOpen: Double = 0.4
    private static let deleteSize: CGFloat = 18
    private static let deleteInset: CGFloat = 2

    // The face the glyph was copied in — unless it has since been uninstalled,
    // in which case the system sans stands in. The card stays: the glyph is
    // still worth copying, and the font may well come back.
    private var glyphFont: Font {
        NSFont(name: entry.psName, size: Self.glyphSize) != nil
            ? .custom(entry.psName, size: Self.glyphSize)
            : .system(size: Self.glyphSize)
    }

    private var isMissing: Bool { NSFont(name: entry.psName, size: 12) == nil }

    var body: some View {
        // One shape, declared once and reused for the fill, the border and the
        // hit area, so the three can't disagree about where the card's edge is.
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return Text(entry.character)
            .font(glyphFont)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            // Rollover moves the FILL and leaves the outline alone: the border
            // draws the card's shape, and a shape that changes colour under the
            // pointer reads as the card itself changing rather than responding.
            .background(
                shape
                    .fill(hovering ? Theme.surfaceFillHover : Theme.surfaceFill)
                    .opacity(hovering ? 0.7 : 0.35)
            )
            // strokeBorder, not stroke: stroke centres the line ON the path, so
            // half a point of it lands outside the card — and because these
            // cards are sized by a flexible grid their edges sit at fractions
            // of a pixel, which turned that outer half into an uneven smear.
            // strokeBorder insets the line to sit wholly inside the shape.
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            // Copy feedback: an accent wash under the word, both inside the
            // same shape so neither can spill past the border.
            .overlay {
                if let flashWash {
                    shape.fill(flashWash.tint.opacity(flashWash.washOpacity))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if let flashWord {
                    Text(flashWord.label)
                        .font(.system(size: Self.copiedSize, weight: .bold))
                        .foregroundStyle(flashWord.tint)
                        .padding(.bottom, 3)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hovering { deleteButton }
            }
            .contentShape(shape)
            // Tap copies, hold opens the font. The hold is what replaced the
            // corner button, so the tooltip has to say so — nothing on the card
            // shows it.
            .onTapGesture { if !openedByHold { copy() } }
            .onLongPressGesture(minimumDuration: Self.holdToOpen) {
                openedByHold = true
                if onOpen() { flash(.opened) }
            } onPressingChanged: { pressing in
                if pressing { openedByHold = false }
            }
            .onHover { hovering = $0 }
            // Not .help(): this card re-renders while the pointer sits on it
            // (the delete button appears), and SwiftUI re-registers .help()'s
            // tooltip rect on every body pass, which restarts AppKit's show
            // sequence and means the name intermittently never appeared. See
            // NativeTooltip.
            .nativeTooltip(tooltip)
            .accessibilityLabel("\(entry.character) in \(entry.psName)")
    }

    private var tooltip: String {
        isMissing
            ? "\(entry.familyName) — no longer installed"
            : "\(entry.familyName) — hold to open"
    }

    // Tucked fully inside the card, 2pt off the top and right edges. It only
    // exists while the pointer is on the card, so the hole it takes out of the
    // copy target is never there when someone is aiming for the glyph.
    private var deleteButton: some View {
        Button(action: onDelete) {
            // The mark carries the artwork's own inset from the disc edge, so
            // it fills the same box the disc does rather than sitting in a
            // smaller frame of its own.
            XMark()
                .fill(deleteMark)
                .frame(width: Self.deleteSize, height: Self.deleteSize)
                .background(
                    Circle()
                        .fill(deleteDisc)
                        .shadow(color: .black.opacity(deleteHovering ? 0.28 : 0.18),
                                radius: 2.5, x: 0, y: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { deleteHovering = $0 }
        .padding(.top, Self.deleteInset)
        .padding(.trailing, Self.deleteInset)
        .help("Remove this glyph")
        .accessibilityLabel("Remove this glyph")
    }

    // Inverted in dark mode: the disc has to read as a button lifted off the
    // card, which a light disc does on a light panel and a dark one does on a
    // dark panel. Keeping it white in both would make it the brightest thing on
    // a dark sidebar, over a control that only removes something.
    private var deleteDisc: Color {
        colorScheme == .dark ? Color(white: 0.16) : .white
    }
    private var deleteMark: Color {
        colorScheme == .dark ? Color(white: 0.82) : Color(white: 0.25)
    }

    private func copy() {
        onCopy()
        flash(.copied)
    }

    // One confirmation for both actions, so they can only ever differ in what
    // they say and what colour they say it in.
    private func flash(_ kind: Flash) {
        withAnimation(.easeOut(duration: Theme.copyFlashIn)) { flashWord = kind }
        withAnimation(.easeOut(duration: Theme.copyFlashIn * Self.washSpeedup)) { flashWash = kind }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.copyFlashHold * Self.washSpeedup) {
            withAnimation(.easeIn(duration: Theme.copyFlashOut * Self.washSpeedup)) { flashWash = nil }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.copyFlashHold) {
            withAnimation(.easeIn(duration: Theme.copyFlashOut)) { flashWord = nil }
        }
    }
}
