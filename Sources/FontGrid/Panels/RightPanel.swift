import SwiftUI

struct RightPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @State private var sortHovering = false
    // When true, the TAGS section grows up to cover the favorites list (down to
    // just below the FAVORITES divider).
    @State private var tagsExpanded = false
    @State private var tagsChevronHovering = false

    private var hasTags: Bool { !memos.tagCounts.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            favoritesHeader
                .padding(.horizontal, Theme.panelHPadding)
                .padding(.vertical, Theme.panelVPadding)
            PanelHDivider()

            if hasTags && tagsExpanded {
                tagsSection(expanded: true)
                    .frame(maxHeight: .infinity)
            } else {
                Group {
                    if favorites.ordered.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("No favorites yet.")
                                .font(.system(size: Theme.smallSize))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Theme.panelHPadding)
                                .padding(.vertical, Theme.panelVPadding)
                            Spacer(minLength: 0)
                        }
                    } else {
                        favoritesList
                    }
                }
                .frame(maxHeight: .infinity)

                if hasTags {
                    PanelHDivider()
                    tagsSection(expanded: false)
                }
            }

            PanelHDivider()
            versionFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBackground.ignoresSafeArea())
    }

    private var versionFooter: some View {
        Text("© pa_st - v\(Theme.appVersion)")
            .font(.system(size: Theme.smallSize))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Theme.panelHPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 44 = old 36 + 8: lifts the divider 8px and centers the text in the
            // taller footer region (matches the left panel's Settings footer);
            // nudged up 3px.
            .frame(height: 44)
            .offset(y: -3)
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

    private func tagsSection(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tagsHeader
                .padding(.horizontal, Theme.panelHPadding)
                .padding(.vertical, Theme.panelVPadding)
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
            .frame(maxHeight: expanded ? .infinity : 220)
            .scrollContentBackground(.hidden)
        }
    }

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
            // Expand/collapse over the favorites list. Same chevron as the memo
            // area's toggle, but without the filled background.
            Button {
                withAnimation(.easeOut(duration: 0.2)) { tagsExpanded.toggle() }
            } label: {
                Image(systemName: tagsExpanded ? "chevron.down" : "chevron.up")
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
                        .fill(Theme.accent.opacity(sortHovering ? 0.24 : 0.15))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { sortHovering = $0 }
        .help("Sort: \(vm.favoritesByRecent ? "most recent first" : "alphabetical")")
    }

    private var displayedFavorites: [String] {
        vm.favoritesByRecent ? favorites.byRecency : favorites.sorted
    }

    private var favoritesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedFavorites, id: \.self) { name in
                    FavoriteRow(name: name, tooltipSuppressed: vm.showSettings) {
                        if let family = vm.library.families.first(where: { $0.name == name }) {
                            vm.detailSource = .favorites
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

// MARK: - Favorite Row

struct FavoriteRow: View {
    let name: String
    var tooltipSuppressed: Bool = false
    let onSelect: () -> Void
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("previewText") private var previewText: String = "The quick brown fox jumps over lazy dog"
    @State private var hovering = false

    // Light mode uses a lighter shadow (30% of dark-mode strength), matching
    // the font cells.
    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    private var hasMemo: Bool { memos.hasNote(for: name) }

    private var sampleText: String {
        previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText
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
                    .font(.custom(name, size: 20))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 25, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .offset(y: -3)
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
        // Top margin matches the horizontal margin so the favorite dot sits the
        // same distance from the top edge as from the right edge.
        .padding(.top, 10)
        .frame(height: 56, alignment: .top)
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
