import SwiftUI

struct CenterPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @AppStorage("previewText") private var previewText = "The quick brown fox jumps over lazy dog"
    @Namespace private var cellHero

    private var displayed: [FontFamily] {
        vm.library.families
            .filter { vm.searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(vm.searchQuery) }
            .filter { vm.minWeightCount <= 1 || $0.weightCount >= vm.minWeightCount }
            .filter { !vm.favoritesOnly || favorites.contains($0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            gridArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PanelHDivider()
            PreviewInputBar(text: $previewText)
                .padding(.horizontal, Theme.gridPadding)
                .padding(.vertical, 12)
        }
        .background(Theme.panelBackground.ignoresSafeArea())
    }

    private var gridArea: some View {
        GeometryReader { geo in
            let computed = computeMaxColumns(width: geo.size.width)
            let effective = min(max(1, vm.columnCount), computed)
            let cols = Array(
                repeating: GridItem(.flexible(), spacing: Theme.gridSpacing),
                count: effective
            )

            ZStack(alignment: .top) {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: Theme.gridSpacing) {
                        ForEach(displayed) { family in
                            if vm.selectedFamily?.id == family.id {
                                Color.clear
                                    .frame(height: Theme.cellHeight(fontSize: vm.fontSize))
                            } else {
                                FontCell(family: family,
                                         previewText: previewText,
                                         fontSize: vm.fontSize) {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                                        vm.selectedFamily = family
                                    }
                                }
                                .matchedGeometryEffect(id: family.id, in: cellHero)
                            }
                        }
                    }
                    .padding(Theme.gridPadding)
                    .padding(.bottom, 16)

                    if displayed.isEmpty {
                        Text(emptyMessage)
                            .font(.system(size: Theme.bodySize))
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                }
                .scrollContentBackground(.hidden)

                if vm.selectedFamily != nil {
                    Theme.panelBackground
                        .ignoresSafeArea(edges: .top)
                        .transition(.opacity)
                }

                if let family = vm.selectedFamily {
                    FontDetailView(
                        family: family,
                        previewText: previewText,
                        onClose: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                vm.selectedFamily = nil
                            }
                        }
                    )
                    .matchedGeometryEffect(id: family.id, in: cellHero)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .onAppear {
                vm.maxColumns = computed
                if vm.columnCount > computed { vm.columnCount = computed }
            }
            .onChange(of: geo.size.width) { newWidth in
                let m = computeMaxColumns(width: newWidth)
                vm.maxColumns = m
                if vm.columnCount > m { vm.columnCount = m }
            }
        }
    }

    private var emptyMessage: String {
        if !vm.searchQuery.isEmpty {
            return "'\(vm.searchQuery)'와 일치하는 폰트가 없습니다."
        }
        if vm.favoritesOnly {
            return "즐겨찾기된 폰트가 없습니다."
        }
        return "표시할 폰트가 없습니다."
    }

    private func computeMaxColumns(width: CGFloat) -> Int {
        let usable = max(0, width - Theme.gridPadding * 2)
        let n = Int(floor((usable + Theme.gridSpacing) / (Theme.minCellWidth + Theme.gridSpacing)))
        return max(1, n)
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
            TextField("The quick brown fox jumps over lazy dog.", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(focused ? Theme.borderHover : Theme.border, lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }
}
