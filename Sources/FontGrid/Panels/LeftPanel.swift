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

            PanelSection("Filter") {
                VStack(alignment: .leading, spacing: 14) {
                    weightFilter
                    favoritesOnlyToggle
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
        .frame(width: Theme.leftPanelWidth)
        .frame(maxHeight: .infinity)
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
        return Button { vm.favoritesOnly.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: vm.favoritesOnly ? "star.fill" : "star")
                    .font(.system(size: Theme.smallSize))
                Text("Favorites only")
                    .font(.system(size: Theme.smallSize,
                                  weight: vm.favoritesOnly ? .medium : .regular))
            }
            .foregroundStyle(vm.favoritesOnly ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.pillRadius)
                    .fill(vm.favoritesOnly
                          ? Theme.accent.opacity(0.15)
                          : Theme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillRadius)
                    .stroke(vm.favoritesOnly
                            ? Theme.accent.opacity(0.6)
                            : Theme.border,
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
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
                Text("\(Int(vm.fontSize))pt")
                    .font(.system(size: Theme.smallSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            Slider(value: $vm.fontSize, in: 14...56, step: 1)
            HStack {
                Text("14")
                Spacer()
                Text("56")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }
}
