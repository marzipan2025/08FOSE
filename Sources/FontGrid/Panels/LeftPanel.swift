import SwiftUI

struct LeftPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @FocusState private var searchFocused: Bool
    @State private var settingsHovering = false
    // The Face box's own disclosure, and the pull-down nested inside it.
    @State private var faceBoxExpanded = false
    @State private var weightListOpen = false

    // Top row of the Weights grid; "10+" sits on the second row beside Variable.
    // The four buckets partition the range with no gaps: 1 / 2–4 / 5–9 / 10+.
    private let weightOptions: [(label: String, value: WeightFilter)] = [
        ("1", .exactly(1)), ("2+", .range(2, 4)), ("5+", .range(5, 9))
    ]
    private let wideWeightOption: (label: String, value: WeightFilter) = ("10+", .atLeast(10))

    // Every group in the panel — Weight Count, Collections, Scripts, the two
    // sliders, Theme, Wallpaper — is a label over its controls, so the two
    // metrics below are shared instead of re-picked per group: they used to
    // drift (8 for the chip groups, 6 for the sliders) and read as uneven.
    private static let groupLabelSpacing: CGFloat = 8
    private static let groupLabelTopPad: CGFloat = 2
    // A Slider carries ~4pt of its own padding above the track, so the same
    // declared spacing reads looser under a slider label than under a pill
    // row. Subtract it here to keep every label-to-control gap even.
    private static let sliderLabelSpacing: CGFloat = groupLabelSpacing - 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed top: search.
            PanelSection {
                searchField
            }

            PanelHDivider()

            // Scrollable middle: grows as more controls are added without
            // pushing the Settings footer off-screen.
            // Two groups under plain headers. PanelSection's own title styling
            // already matches the right panel's PINNED / TAGS rows, so the
            // header rides inside the section rather than sitting above a rule.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PanelSection("Filters") {
                        VStack(alignment: .leading, spacing: 14) {
                            weightFilterSection
                            collectionsSection
                            scriptsSection
                        }
                    }
                    .zIndex(weightListOpen ? 1 : 0)

                    PanelHDivider()

                    PanelSection("View") {
                        VStack(alignment: .leading, spacing: 14) {
                            columnSlider
                            fontSizeSlider
                            themePicker
                                // Font Size ends in the tick-mark row, which is
                                // mostly empty space, so this one gap reads
                                // wider than the rest at the same spacing.
                                .padding(.top, -4)
                            wallpaperPicker
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)

            // Fixed bottom: Settings entry. Mirrors the right panel's version
            // footer (divider above, same height).
            PanelHDivider()
            settingsFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBackground.ignoresSafeArea())
    }

    // MARK: - Settings footer

    private var settingsFooter: some View {
        Button {
            vm.showSettings = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: Theme.bodySize))
                Text("Settings")
                    .font(.system(size: Theme.smallSize))
            }
            .foregroundStyle(settingsHovering ? Theme.accent : Color.secondary)
            .padding(.horizontal, Theme.panelHPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 44 = old 36 + 8: lifts the divider 8px and centers the content in
            // the taller footer region; nudged up 2px.
            .frame(height: 44)
            .offset(y: -2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { settingsHovering = $0 }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.bodySize))
                .foregroundStyle(searchFocused ? Theme.accent : Color.secondary)
            TextField("Search", text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.bodySize))
                .focused($searchFocused)
            if !vm.searchQuery.isEmpty {
                Button { vm.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.smallSize))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.surfaceRadius, style: .continuous)
                .fill(Theme.surfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.surfaceRadius, style: .continuous)
                .stroke(searchFocused ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Filter

    // Three equal columns: 1 / 3+ / 7+ on the first row, then 10+ beside the
    // Variable filter, which spans the remaining two columns for a 1:2 split.
    // Variable lives here rather than under Collections because it's another way
    // of asking "what weights does this family give me" — a continuous axis
    // instead of a count. All four chips combine as a union.
    private var weightFilterSection: some View {
        VStack(alignment: .leading, spacing: Self.groupLabelSpacing) {
            groupLabel("Weight Count")
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ForEach(weightOptions, id: \.value) { weightPill($0) }
                }
                GridRow {
                    weightPill(wideWeightOption)
                    variablesOnlyToggle.gridCellColumns(2)
                }
            }
            faceBox
                .padding(.top, 4)
        }
        // The open pull-down overlays the groups below, so this group has to
        // paint after them. VStack draws in declaration order, which would
        // otherwise put Collections on top of the list.
        .zIndex(weightListOpen ? 1 : 0)
    }


    // MARK: - Face

    // The Face box: a weight pull-down and the two slant toggles, boxed off from
    // the chips above it.
    //
    // It is boxed because it is the one control in this panel that reaches INTO
    // the cell — everything else decides which families survive, this also
    // decides which cut of each survivor gets drawn. Folding it away keeps that
    // difference from reading as "just three more chips", and keeps a 14-row
    // pull-down from permanently crowding the panel.
    //
    // The header doubles as the title: it shows the current selection, so there
    // is nothing to name. "Any Weight" is the resting state.
    private var faceBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            faceBoxHeader
            if faceBoxExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    weightPulldown
                        // Floated, not inserted: the box keeps its height and the
                        // slant row below it stays put while the list is open.
                        .overlay(alignment: .topLeading) {
                            if weightListOpen {
                                weightList.offset(y: 27)
                            }
                        }
                        // zIndex only orders SIBLINGS, so the open list has to be
                        // lifted once per container it needs to escape: over the
                        // slant row here, over Collections/Scripts in the Filters
                        // stack, and over the whole View section in the scroll
                        // stack. Miss any one level and the list slides under it.
                        .zIndex(weightListOpen ? 1 : 0)
                    slantRow
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        // Fill AND border both live in the background layer. An .overlay border
        // paints on top of everything the box contains — including the open
        // pull-down — so the box's own outline used to cut straight across the
        // floating list. Content is inset from the edge anyway, so putting the
        // stroke behind it looks identical everywhere else.
        .background(
            RoundedRectangle(cornerRadius: Theme.surfaceRadius, style: .continuous)
                .fill(Theme.surfaceFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.surfaceRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
        )
    }

    private var faceBoxHeader: some View {
        HStack(spacing: 4) {
            // Same ink as every other button label in the panel, selected or
            // not. The accent is spent on the controls inside the box, and the
            // Clear button appearing is already the "something is set" signal —
            // colouring the header too made it compete with the pull-down.
            Text(faceSummary)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            // Clear sits left of the chevron and shows in both states, so a
            // folded box never hides a selection the user cannot undo from here.
            if vm.hasFaceSelection {
                FaceClearButton { vm.clearFaceSelection() }
            }
            Image(systemName: faceBoxExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                faceBoxExpanded.toggle()
                // Folding the box also folds the pull-down, so reopening starts
                // from the compact state instead of a 14-row list.
                if !faceBoxExpanded { weightListOpen = false }
            }
        }
        .help(faceBoxExpanded ? "Collapse face options" : "Expand face options")
    }

    // Collapsed summary. Mirrors the center panel's stats line: one segment
    // spells itself out, two or more abbreviate.
    private var faceSummary: String {
        var full: [String] = []
        var short: [String] = []
        if let w = vm.faceWeight { full.append(w.label); short.append(w.abbreviation) }
        if let s = vm.faceSlant { full.append(s.label); short.append(s.abbreviation) }
        if full.isEmpty { return "More" }
        if full.count == 1 { return full[0] }
        return short.joined(separator: "\u{2009}·\u{2009}")
    }

    // The pull-down's closed face: a pill like every other button here, with a
    // triangle added. Drawn by hand rather than with Menu so it opens INLINE —
    // a floating menu would be clipped by the enclosing ScrollView, and 14 rows
    // is taller than the space a popover gets in a 240pt panel.
    private var weightPulldown: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { weightListOpen.toggle() }
        } label: {
            HStack(spacing: 5) {
                Text(vm.faceWeight?.label ?? "All")
                    .font(.system(size: Theme.smallSize,
                                  weight: vm.faceWeight == nil ? .regular : .medium))
                Spacer(minLength: 4)
                Image(systemName: weightListOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(vm.faceWeight == nil ? Color.secondary : Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.pillRadius)
                    .fill(vm.faceWeight == nil ? Theme.surfaceFill : Theme.accent.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillRadius)
                    .stroke(vm.faceWeight == nil ? Theme.border : Theme.accent.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    // Every rung is listed whether or not the current results hold one, so the
    // list never reshuffles under the cursor. A rung with no matches just lands
    // on the grid's existing "Nothing found" state.
    private var weightList: some View {
        VStack(spacing: 0) {
            weightRow(nil)
            ForEach(FaceWeight.allCases, id: \.self) { weightRow($0) }
        }
        .padding(.vertical, 3)
        // Two fills: the panel's own background makes it opaque (Theme.surfaceFill
        // is translucent and would let the chips behind it read through), then
        // the usual surface tint sits on top for the same lift as a closed pill.
        .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.surfaceFill))
        .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.sidebarBackground))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
    }

    private func weightRow(_ weight: FaceWeight?) -> some View {
        FaceListRow(
            label: weight?.label ?? "All",
            isOn: vm.faceWeight == weight
        ) {
            vm.faceWeight = weight
            withAnimation(.easeOut(duration: 0.18)) { weightListOpen = false }
        }
    }

    // Italic / Oblique. Mutually exclusive — tapping the active one clears it —
    // and independent of the weight above: a family passes when it ships both
    // parts, even if no single face carries them together.
    private var slantRow: some View {
        HStack(spacing: 6) {
            ForEach(FaceSlant.allCases, id: \.self) { slant in
                filterPill(label: slant.label, icon: nil, isOn: vm.faceSlant == slant) {
                    vm.faceSlant = vm.faceSlant == slant ? nil : slant
                }
            }
        }
    }

    private func weightPill(_ option: (label: String, value: WeightFilter)) -> some View {
        PillButton(label: option.label, icon: nil, isOn: vm.weightFilters.contains(option.value)) {
            vm.toggleWeightFilter(option.value)
        }
    }

    // Pins / Memo filters, pulled out of the old "Sortings" group into
    // their own labeled section.
    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: Self.groupLabelSpacing) {
            groupLabel("Collections")
            HStack(spacing: 6) {
                pinnedOnlyToggle
                memoOnlyToggle
            }
            HStack(spacing: 6) {
                mutedToggle
                mutedOnlyToggle
            }
        }
    }

    // Include variable fonts. Sits in the Weights grid (see above). Always
    // enabled — with no variable fonts installed it just shows the "Nothing
    // found" empty state.
    private var variablesOnlyToggle: some View {
        filterPill(
            label: "Variable Fonts",
            icon: nil,
            isOn: vm.variablesOnly
        ) {
            vm.variablesOnly.toggle()
        }
    }

    // Show only muted fonts (mirrors Pins/Memo only). Always enabled — with
    // nothing muted it just shows the "Nothing found" empty state.
    private var mutedOnlyToggle: some View {
        filterPill(
            label: "Muted",
            icon: nil,
            isOn: vm.mutedOnly
        ) {
            vm.mutedOnly.toggle()
        }
    }

    // Full-width 3-state control for muted fonts:
    //   Show muted → Hide muted → Only muted → (back to Show)
    private var mutedToggle: some View {
        let (label, active): (String, Bool) = {
            switch vm.mutedFilter {
            case .shown:  return ("Show muted", false)
            case .hidden: return ("Hide muted", true)
            }
        }()
        return Button {
            vm.cycleMutedFilter()
        } label: {
            Text(label)
                .font(.system(size: Theme.smallSize, weight: active ? .medium : .regular))
                .foregroundStyle(active ? Theme.accent : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .fill(active ? Theme.accent.opacity(0.15) : Theme.surfaceFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .stroke(active ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Muted fonts: \(vm.mutedFilter == .shown ? "shown (dimmed)" : "hidden")")
    }

    // The six script buckets, labeled "Scripts".
    private var scriptsSection: some View {
        VStack(alignment: .leading, spacing: Self.groupLabelSpacing) {
            groupLabel("Scripts")
            scriptFilterRows
        }
    }

    private func groupLabelText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.smallSize))
            .foregroundStyle(.secondary)
    }

    // Shared group label. The top pad lifts each label off the group above it.
    private func groupLabel(_ text: String) -> some View {
        groupLabelText(text)
            .padding(.top, Self.groupLabelTopPad)
    }

    // Group label for the sliders: same label, plus the live value trailing.
    // Padded as a row so the value stays baseline-aligned with the label.
    private func sliderLabel(_ text: String, value: String) -> some View {
        HStack {
            groupLabelText(text)
            Spacer()
            Text(value)
                .font(.system(size: Theme.smallSize, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.top, Self.groupLabelTopPad)
    }

    private var pinnedOnlyToggle: some View {
        // Always enabled — with no pins it just shows the empty "Nothing
        // found" state, like any other filter.
        filterPill(
            label: "Pinned",
            icon: nil,
            isOn: vm.pinnedOnly
        ) {
            vm.pinnedOnly.toggle()
        }
    }

    private var memoOnlyToggle: some View {
        filterPill(
            label: "Memo",
            icon: nil,
            isOn: vm.memoOnly
        ) {
            vm.memoOnly.toggle()
        }
    }

    // Script buckets, two per row. Chinese / Symbol are omitted (see
    // ScriptCategory.filterable).
    private var scriptFilterRows: some View {
        let cats = ScriptCategory.filterable
        return VStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: cats.count, by: 2)), id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(cats[start..<min(start + 2, cats.count)], id: \.self) { category in
                        filterPill(label: category.label, icon: nil,
                                   isOn: vm.scriptFilter.contains(category)) {
                            vm.toggleScript(category)
                        }
                    }
                }
            }
        }
    }

    private func filterPill(
        label: String,
        icon: String?,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        PillButton(label: label, icon: icon, isOn: isOn, action: action)
    }

    // MARK: - Layout

    private var columnSlider: some View {
        let safeMax = max(2, vm.maxColumns)
        let current = min(max(1, vm.columnCount), max(1, vm.maxColumns))
        return VStack(alignment: .leading, spacing: Self.sliderLabelSpacing) {
            sliderLabel("Columns", value: "\(current)")
            Slider(
                value: Binding(
                    get: { Double(current) },
                    set: { vm.columnCount = Int($0.rounded()) }
                ),
                in: 1...Double(safeMax),
                step: 1
            )
            .disabled(vm.maxColumns <= 1)
        }
    }

    private var fontSizeSlider: some View {
        VStack(alignment: .leading, spacing: Self.sliderLabelSpacing) {
            sliderLabel("Font Size", value: formattedOffset(vm.previewSizeOffset))
            // Stepless so AppKit doesn't comb the track with one tick per unit;
            // the binding rounds instead, which keeps the offset integral and
            // the thumb snapping exactly as the stepped slider did.
            Slider(
                value: Binding(
                    get: { vm.previewSizeOffset },
                    set: { vm.previewSizeOffset = $0.rounded() }
                ),
                in: AppViewModel.previewOffsetRange
            )
            sliderScale
        }
    }

    // Three tick marks — the two range ends and 0 — standing in for the old
    // number row. The range is asymmetric (-10...30), so 0 is NOT at the
    // track's midpoint: each tick sits at its true fractional position so it
    // lines up with the thumb.
    private var sliderScale: some View {
        let lo = AppViewModel.previewOffsetRange.lowerBound
        let hi = AppViewModel.previewOffsetRange.upperBound
        return GeometryReader { geo in
            let inset: CGFloat = 11   // ≈ slider knob half-width
            let usable = max(1, geo.size.width - inset * 2)
            ZStack(alignment: .topLeading) {
                ForEach([lo, 0, hi], id: \.self) { value in
                    let f = CGFloat((value - lo) / (hi - lo))
                    Rectangle()
                        .fill(.tertiary)
                        .frame(width: 1, height: 4)
                        .position(x: inset + usable * f, y: 2)
                }
            }
        }
        .frame(height: 6)
    }

    // Wallpaper switcher (None / 1–4). Shared between dark and light mode —
    // the per-wallpaper blend map inside WallpaperOverlay decides how each
    // image composites onto whichever appearance is active.
    private var wallpaperPicker: some View {
        VStack(alignment: .leading, spacing: Self.groupLabelSpacing) {
            groupLabel("Wallpaper")
            HStack(spacing: 6) {
                filterPill(label: "0", icon: nil, isOn: vm.wallpaper.isEmpty) {
                    vm.wallpaper = ""
                }
                ForEach(Array(AppViewModel.wallpapers.enumerated()), id: \.offset) { index, name in
                    filterPill(label: "\(index + 1)", icon: nil, isOn: vm.wallpaper == name) {
                        vm.wallpaper = name
                    }
                }
            }
        }
    }

    // Dark / Light theme switch. Light mode is a work in progress.
    private var themePicker: some View {
        VStack(alignment: .leading, spacing: Self.groupLabelSpacing) {
            groupLabel("Theme")
            HStack(spacing: 6) {
                filterPill(label: "Dark", icon: "moon.fill", isOn: !vm.isLightMode) {
                    vm.isLightMode = false
                }
                filterPill(label: "Light", icon: "sun.max.fill", isOn: vm.isLightMode) {
                    vm.isLightMode = true
                }
            }
        }
    }

    private func formattedOffset(_ value: Double) -> String {
        let i = Int(value.rounded())
        if i > 0 { return "+\(i)" }
        return "\(i)"
    }
}

// One row of the weight pull-down. Plain text with a hover wash — the list is
// already inside two nested surfaces, so a third border per row would be noise.
private struct FaceListRow: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: Theme.smallSize, weight: isOn ? .medium : .regular))
                .foregroundStyle(isOn ? Theme.accent : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hovering ? Theme.surfaceFillHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

// The Face box's Clear. A word rather than an ✕ because it sits beside a
// chevron that already means "this control does something to the box" — two
// bare glyphs there read as a pair of unlabelled switches. Kept as its own
// button so tapping it does not also fold the box.
private struct FaceClearButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Clear")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(Theme.accent.opacity(hovering ? 1 : 0.8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Clear face selection")
        .onHover { hovering = $0 }
    }
}

// Pill-style toggle button with a light hover state: the fill grows a little
// denser on rollover. Used for all left-panel toggles.
private struct PillButton: View {
    let label: String
    var icon: String? = nil
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: Theme.smallSize))
                }
                Text(label)
                    .font(.system(size: Theme.smallSize, weight: isOn ? .medium : .regular))
            }
            .foregroundStyle(isOn ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.pillRadius).fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillRadius)
                    .stroke(isOn ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }

    private var fillColor: Color {
        if isOn { return Theme.accent.opacity(hovering ? 0.24 : 0.15) }
        return hovering ? Theme.surfaceFillHover : Theme.surfaceFill
    }
}
