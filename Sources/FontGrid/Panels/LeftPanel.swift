import SwiftUI

struct LeftPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @FocusState private var searchFocused: Bool

    private let weightOptions: [(label: String, value: Int)] = [
        ("All", 1), ("2+", 2), ("3+", 3), ("5+", 5)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSection {
                searchField
            }

            PanelHDivider()

            PanelSection("Filters") {
                VStack(alignment: .leading, spacing: 14) {
                    weightFilter
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sortings")
                            .font(.system(size: Theme.smallSize))
                            .foregroundStyle(.secondary)
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                favoritesOnlyToggle
                                memoOnlyToggle
                            }
                            HStack(spacing: 6) {
                                koreanToggle
                                englishToggle
                            }
                        }
                    }
                }
            }

            PanelHDivider()

            PanelSection("Layout") {
                VStack(alignment: .leading, spacing: 14) {
                    columnSlider
                    fontSizeSlider
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBackground.ignoresSafeArea())
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

    private var weightFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Min. Weights")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(weightOptions, id: \.value) { option in
                    let isSelected = vm.minWeightCount == option.value
                    Button { vm.minWeightCount = option.value } label: {
                        Text(option.label)
                            .font(.system(size: Theme.smallSize, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.pillRadius)
                                    .fill(isSelected
                                          ? Theme.accent.opacity(0.15)
                                          : Theme.surfaceFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.pillRadius)
                                    .stroke(isSelected
                                            ? Theme.accent.opacity(0.6)
                                            : Theme.border,
                                            lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
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

    private var koreanToggle: some View {
        filterPill(label: "Korean", icon: nil, isOn: vm.koreanOnly) {
            vm.koreanOnly.toggle()
        }
    }

    private var englishToggle: some View {
        filterPill(label: "English", icon: nil, isOn: vm.englishOnly) {
            vm.englishOnly.toggle()
        }
    }

    private func filterPill(
        label: String,
        icon: String?,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
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
                RoundedRectangle(cornerRadius: Theme.pillRadius)
                    .fill(isOn ? Theme.accent.opacity(0.15) : Theme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillRadius)
                    .stroke(isOn ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            HStack {
                Text("\(Int(AppViewModel.previewOffsetRange.lowerBound))")
                Spacer()
                Text("0")
                Spacer()
                Text("+\(Int(AppViewModel.previewOffsetRange.upperBound))")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }

    private func formattedOffset(_ value: Double) -> String {
        let i = Int(value.rounded())
        if i > 0 { return "+\(i)" }
        return "\(i)"
    }
}
