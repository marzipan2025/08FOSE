import SwiftUI

extension Color {
    static let weightBadge = Color(red: 84/255, green: 97/255, blue: 111/255)   // #54616F
    static let accentYellow = Color(red: 0.85, green: 0.65, blue: 0.20)
}

struct ContentView: View {
    @StateObject private var library = FontLibrary()
    @StateObject private var favorites = FavoritesStore()
    @AppStorage("previewText") private var previewText = "The quick brown fox jumps over lazy dog"
    @State private var columnCount: Int = 4
    @State private var maxColumns: Int = 6
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var favoritesOnly: Bool = false
    @State private var fontSize: Double = 28
    @State private var minWeightCount: Int = 1
    @State private var searchQuery: String = ""
    @State private var selectedFamily: FontFamily? = nil
    @Namespace private var cellHero

    private let minCellWidth: CGFloat = 120
    private let gridSpacing: CGFloat = 6
    private let gridPadding: CGFloat = 16
    private let sidePanelMin: CGFloat = 180
    private let sidePanelIdeal: CGFloat = 200
    private let sidePanelMax: CGFloat = 240

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LeftSidebar(
                columnCount: $columnCount,
                maxColumns: maxColumns,
                fontSize: $fontSize,
                minWeightCount: $minWeightCount,
                searchQuery: $searchQuery
            )
            .navigationSplitViewColumnWidth(min: sidePanelMin, ideal: sidePanelIdeal, max: sidePanelMax)
        } content: {
            gridArea
                .navigationTitle("")
        } detail: {
            FavoritesPanel(favoritesOnly: $favoritesOnly)
                .navigationSplitViewColumnWidth(min: sidePanelMin, ideal: sidePanelIdeal, max: sidePanelMax)
                .navigationTitle("")
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

            let displayed = library.families
                .filter { searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(searchQuery) }
                .filter { minWeightCount <= 1 || $0.weightCount >= minWeightCount }
                .filter { !favoritesOnly || favorites.contains($0.name) }

            VStack(spacing: 0) {
                // 그리드 + 오버레이 영역
                ZStack(alignment: .top) {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: gridSpacing) {
                            ForEach(displayed) { family in
                                if selectedFamily?.id == family.id {
                                    // 선택된 셀 자리 — 그리드 레이아웃 유지용 투명 placeholder
                                    Color.clear
                                        .frame(height: max(90, CGFloat(fontSize) + 62))
                                } else {
                                    FontCell(family: family, previewText: previewText, fontSize: fontSize) {
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                                            selectedFamily = family
                                        }
                                    }
                                    .matchedGeometryEffect(id: family.id, in: cellHero)
                                    .environmentObject(favorites)
                                }
                            }
                        }
                        .padding(gridPadding)
                        .padding(.bottom, 16)

                        if displayed.isEmpty {
                            Text(
                                !searchQuery.isEmpty
                                    ? "'\(searchQuery)'와 일치하는 폰트가 없습니다."
                                    : "즐겨찾기된 폰트가 없습니다."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                        }
                    }

                    // 블러 배경
                    if selectedFamily != nil {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea(edges: .top)
                            .transition(.opacity)
                    }

                    // 디테일 뷰 — ZStack 상단부터 전체 높이 채움
                    if let family = selectedFamily {
                        FontDetailView(
                            family: family,
                            previewText: previewText,
                            onClose: {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    selectedFamily = nil
                                }
                            }
                        )
                        .matchedGeometryEffect(id: family.id, in: cellHero)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, 16)
                    }
                }

                // 인풋바 — ZStack 바깥, 항상 하단에 노출
                PreviewInputBar(text: $previewText)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
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

// MARK: - Left Sidebar

struct LeftSidebar: View {
    @Binding var columnCount: Int
    let maxColumns: Int
    @Binding var fontSize: Double
    @Binding var minWeightCount: Int
    @Binding var searchQuery: String

    @FocusState private var searchFocused: Bool

    private let weightOptions: [(label: String, value: Int)] = [
        ("All", 1), ("2+", 2), ("3+", 3), ("5+", 5)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 검색 필드
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider().opacity(0.5)

            // Filter
            sectionHeader("Filter")
            weightFilter
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            Divider().opacity(0.5)

            // Layout
            sectionHeader("Layout")
            columnSlider
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            fontSizeSlider
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(searchFocused ? Color.accentYellow : Color.secondary)
            TextField("폰트 검색", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(searchFocused
                        ? Color.accentYellow.opacity(0.5)
                        : Color.white.opacity(0.10),
                        lineWidth: 1)
        )
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

    private var fontSizeSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Font Size")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fontSize))pt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            Slider(value: $fontSize, in: 14...56, step: 1)
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

    private var weightFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Min. Weights")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(weightOptions, id: \.value) { option in
                    let isSelected = minWeightCount == option.value
                    Button {
                        minWeightCount = option.value
                    } label: {
                        Text(option.label)
                            .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? Color.accentYellow : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected
                                          ? Color.accentYellow.opacity(0.15)
                                          : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected
                                            ? Color.accentYellow.opacity(0.6)
                                            : Color.white.opacity(0.10),
                                            lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Favorites Panel

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

            // Toggle button (replaces checkbox)
            Button {
                favoritesOnly.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                    Text("View favorites only")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(favoritesOnly ? Color.accentYellow : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(favoritesOnly
                              ? Color.accentYellow.opacity(0.15)
                              : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(favoritesOnly
                                ? Color.accentYellow.opacity(0.5)
                                : Color.white.opacity(0.10),
                                lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .disabled(favorites.sorted.isEmpty)
            .opacity(favorites.sorted.isEmpty ? 0.4 : 1)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }
}

// MARK: - Favorite Row

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

// MARK: - Preview Input Bar

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
