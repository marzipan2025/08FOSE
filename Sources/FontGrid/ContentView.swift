import SwiftUI

extension Color {
    static let weightBadge = Color(red: 84/255, green: 97/255, blue: 111/255)   // #54616F
    static let accentYellow = Color(red: 0.85, green: 0.65, blue: 0.20)
}

struct ContentView: View {
    @StateObject private var library = FontLibrary()
    @StateObject private var favorites = FavoritesStore()
    @State private var previewText = "The Quick Gray Fox Jumps over"
    @State private var columnCount: Int = 4
    @State private var maxColumns: Int = 6
    @State private var showFavoritesPanel: Bool = true
    @State private var favoritesOnly: Bool = false

    private let minCellWidth: CGFloat = 120
    private let gridSpacing: CGFloat = 12
    private let gridPadding: CGFloat = 16
    private let sidePanelMin: CGFloat = 180
    private let sidePanelIdeal: CGFloat = 200
    private let sidePanelMax: CGFloat = 240

    var body: some View {
        NavigationSplitView {
            LeftSidebar(columnCount: $columnCount, maxColumns: maxColumns)
                .navigationSplitViewColumnWidth(min: sidePanelMin, ideal: sidePanelIdeal, max: sidePanelMax)
        } detail: {
            HSplitView {
                gridArea
                    .frame(minWidth: 280)
                if showFavoritesPanel {
                    FavoritesPanel(favoritesOnly: $favoritesOnly)
                        .frame(minWidth: sidePanelMin, idealWidth: sidePanelIdeal, maxWidth: sidePanelMax)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showFavoritesPanel.toggle()
                        }
                    } label: {
                        Image(systemName: showFavoritesPanel
                              ? "sidebar.right"
                              : "sidebar.right")
                            .foregroundStyle(showFavoritesPanel ? .primary : .secondary)
                    }
                    .help(showFavoritesPanel ? "즐겨찾기 패널 숨기기" : "즐겨찾기 패널 보기")
                }
            }
        }
        .environmentObject(favorites)
        .preferredColorScheme(.dark)
    }

    private var gridArea: some View {
        GeometryReader { geo in
            let computed = computeMaxColumns(width: geo.size.width)
            let effective = min(max(1, columnCount), computed)
            let cols = Array(
                repeating: GridItem(.flexible(), spacing: gridSpacing),
                count: effective
            )

            let displayed = favoritesOnly
                ? library.families.filter { favorites.contains($0.name) }
                : library.families

            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: gridSpacing) {
                        ForEach(displayed) { family in
                            FontCell(family: family, previewText: previewText)
                                .environmentObject(favorites)
                        }
                    }
                    .padding(gridPadding)
                    .padding(.bottom, 80)

                    if displayed.isEmpty && favoritesOnly {
                        Text("즐겨찾기된 폰트가 없습니다.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                }

                PreviewInputBar(text: $previewText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .onAppear {
                maxColumns = computed
                if columnCount > computed { columnCount = computed }
            }
            .onChange(of: geo.size.width) { newWidth in
                let m = computeMaxColumns(width: newWidth)
                maxColumns = m
                if columnCount > m { columnCount = m }
            }
        }
    }

    private func computeMaxColumns(width: CGFloat) -> Int {
        let usable = max(0, width - gridPadding * 2)
        let n = Int(floor((usable + gridSpacing) / (minCellWidth + gridSpacing)))
        return max(1, n)
    }
}

struct LeftSidebar: View {
    @Binding var columnCount: Int
    let maxColumns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Layout")
            columnSlider
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            Divider().opacity(0.5)

            sectionHeader("Filter")
            Text("weight 필터 · 폰트 검색은 다음 단계에서 추가됩니다.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    private var columnSlider: some View {
        let safeMax = max(2, maxColumns)
        let current = min(max(1, columnCount), max(1, maxColumns))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Columns")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(current)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(current) },
                    set: { columnCount = Int($0.rounded()) }
                ),
                in: 1...Double(safeMax),
                step: 1
            )
            .disabled(maxColumns <= 1)
            HStack {
                Text("1")
                Spacer()
                Text("\(max(1, maxColumns))")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }
}

struct FavoritesPanel: View {
    @Binding var favoritesOnly: Bool
    @EnvironmentObject var favorites: FavoritesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Favorites")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if favorites.sorted.isEmpty {
                Text("아직 즐겨찾기가 없어요.\n폰트 카드에 마우스를 올려 별을 눌러보세요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(favorites.sorted, id: \.self) { name in
                            FavoriteRow(name: name)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }

            Divider().opacity(0.4)

            Button {
                favoritesOnly.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: favoritesOnly ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(favoritesOnly ? Color.accentYellow : Color.secondary)
                    Text("View favorites only")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(favorites.sorted.isEmpty)
            .opacity(favorites.sorted.isEmpty ? 0.4 : 1)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }
}

struct FavoriteRow: View {
    let name: String
    @EnvironmentObject var favorites: FavoritesStore
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(name)
                .font(.custom(name, size: 16))
                .lineLimit(1)
            Spacer()
            Button {
                favorites.toggle(name)
            } label: {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.accentYellow)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.white.opacity(0.05) : .clear)
        )
        .onHover { hovering = $0 }
    }
}

struct PreviewInputBar: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("미리보기 텍스트를 입력하면 모든 셀에 적용됩니다", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(focused ? 0.35 : 0.10), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }
}
