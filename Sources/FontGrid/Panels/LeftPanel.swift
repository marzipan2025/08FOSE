import SwiftUI

struct LeftPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var muted: MutedStore
    @FocusState private var searchFocused: Bool
    @State private var settingsHovering = false

    private let weightOptions: [(label: String, value: WeightFilter)] = [
        ("All", .all), ("1", .exactly(1)), ("3+", .atLeast(3)), ("5+", .atLeast(5))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed top: search.
            PanelSection {
                searchField
            }

            PanelHDivider()

            // Scrollable middle: grows as more controls are added without
            // pushing the Settings footer off-screen.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PanelSection("Filters") {
                        VStack(alignment: .leading, spacing: 14) {
                            weightFilterSection
                            collectionsSection
                            scriptsSection
                        }
                    }

                    PanelHDivider()

                    PanelSection("Layout") {
                        VStack(alignment: .leading, spacing: 14) {
                            columnSlider
                            fontSizeSlider
                        }
                    }

                    PanelHDivider()

                    PanelSection("Appearance") {
                        VStack(alignment: .leading, spacing: 14) {
                            themePicker
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

    private var weightFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weights")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(weightOptions, id: \.value) { option in
                    PillButton(label: option.label, icon: nil, isOn: vm.weightFilter == option.value) {
                        vm.weightFilter = option.value
                    }
                }
            }
        }
    }

    // Favorites / Memo filters, pulled out of the old "Sortings" group into
    // their own labeled section.
    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collections")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                favoritesOnlyToggle
                memoOnlyToggle
            }
            HStack(spacing: 6) {
                mutedToggle
                mutedOnlyToggle
            }
        }
    }

    // Show only muted fonts (mirrors Favorites/Memo only). Label carries the
    // muted count; disabled when nothing is muted.
    private var mutedOnlyToggle: some View {
        let disabled = muted.names.isEmpty
        return filterPill(
            label: "Muted \(muted.names.count)",
            icon: nil,
            isOn: vm.mutedOnly
        ) {
            vm.mutedOnly.toggle()
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Scripts")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
            scriptFilterRows
        }
    }

    private var favoritesOnlyToggle: some View {
        let disabled = favorites.sorted.isEmpty
        return filterPill(
            label: "Favorites",
            icon: nil,
            isOn: vm.favoritesOnly
        ) {
            vm.favoritesOnly.toggle()
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Columns")
                    .font(.system(size: Theme.smallSize))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(current)")
                    .font(.system(size: Theme.smallSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(current) },
                    set: { vm.columnCount = Int($0.rounded()) }
                ),
                in: 1...Double(safeMax),
                step: 1
            )
            .disabled(vm.maxColumns <= 1)
            HStack {
                Text("1")
                Spacer()
                Text("\(max(1, vm.maxColumns))")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }

    private var fontSizeSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Font Size")
                    .font(.system(size: Theme.smallSize))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedOffset(vm.previewSizeOffset))
                    .font(.system(size: Theme.smallSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            Slider(value: $vm.previewSizeOffset, in: AppViewModel.previewOffsetRange, step: 1)
            sliderScale
        }
    }

    // The range is asymmetric (e.g. -8...20), so 0 is NOT at the track's
    // midpoint. Place each label at its true fractional position so the
    // numbers line up with the slider's tick marks and thumb.
    private var sliderScale: some View {
        let lo = AppViewModel.previewOffsetRange.lowerBound
        let hi = AppViewModel.previewOffsetRange.upperBound
        let labels: [Double] = [lo, 0, hi]
        return GeometryReader { geo in
            let inset: CGFloat = 11   // ≈ slider knob half-width
            let usable = max(1, geo.size.width - inset * 2)
            ZStack {
                ForEach(labels, id: \.self) { value in
                    let f = CGFloat((value - lo) / (hi - lo))
                    Text(formattedOffset(value))
                        .position(x: inset + usable * f, y: 7)
                }
            }
        }
        .frame(height: 14)
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }

    // Wallpaper switcher (None / 1–4). Shared between dark and light mode —
    // the per-wallpaper blend map inside WallpaperOverlay decides how each
    // image composites onto whichever appearance is active.
    private var wallpaperPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wallpaper")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Theme")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
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
