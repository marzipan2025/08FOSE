import SwiftUI

struct RightPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            favoritesHeader
                .padding(.horizontal, Theme.panelHPadding)
                .padding(.vertical, Theme.panelVPadding)
            PanelHDivider()

            if favorites.ordered.isEmpty {
                Text("No favorites yet.\nHover a font card and tap the dot to add one.")
                    .font(.system(size: Theme.smallSize))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.panelHPadding)
                    .padding(.vertical, Theme.panelVPadding)
                Spacer(minLength: 0)
            } else {
                favoritesList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBackground.ignoresSafeArea())
    }

    private var favoritesHeader: some View {
        HStack(spacing: 8) {
            Text("FAVORITES")
                .font(.system(size: Theme.sectionHeaderSize, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if !favorites.ordered.isEmpty {
                Text("\(favorites.ordered.count)")
                    .font(.system(size: Theme.smallSize, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 8)
            if !favorites.ordered.isEmpty {
                sortToggle
            }
        }
    }

    private var sortToggle: some View {
        Button {
            vm.favoritesByRecent.toggle()
        } label: {
            Text(vm.favoritesByRecent ? "Recent" : "A–Z")
                .font(.system(size: Theme.smallSize, weight: .medium))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .frame(width: 56)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.accent.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .help("Sort: \(vm.favoritesByRecent ? "most recent first" : "alphabetical")")
    }

    private var displayedFavorites: [String] {
        vm.favoritesByRecent ? favorites.byRecency : favorites.sorted
    }

    private var favoritesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedFavorites, id: \.self) { name in
                    FavoriteRow(name: name) {
                        if let family = vm.library.families.first(where: { $0.name == name }) {
                            if vm.selectedFamily == nil {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                                    vm.selectedFamily = family
                                }
                            } else {
                                vm.selectedFamily = family
                            }
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

// MARK: - Favorite Row

struct FavoriteRow: View {
    let name: String
    let onSelect: () -> Void
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @AppStorage("previewText") private var previewText: String = "The quick brown fox jumps over lazy dog"
    @State private var hovering = false

    private var hasMemo: Bool { memos.hasNote(for: name) }

    private var sampleText: String {
        previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: Theme.smallSize))
                    .foregroundStyle(Theme.weightBadge)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(sampleText)
                    .font(.custom(name, size: 18))
                    .foregroundStyle(Color(white: 0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 22, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                if hasMemo {
                    Circle()
                        .fill(Theme.memoAccent)
                        .frame(width: 9, height: 9)
                }
                Button { favorites.toggle(name) } label: {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 9, height: 9)
                }
                .buttonStyle(.plain)
            }
            .opacity(hovering ? 1 : 0.7)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Color.white.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering = $0 }
    }
}
