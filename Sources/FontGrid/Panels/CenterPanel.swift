import SwiftUI
import AppKit
import Carbon

struct CenterPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @AppStorage("previewText") private var previewText = "The quick brown fox jumps over lazy dog"
    @Namespace private var cellHero
    @State private var hoveredFamilyID: FontFamily.ID? = nil

    private var displayed: [FontFamily] {
        vm.library.families
            .filter { vm.searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(vm.searchQuery) }
            .filter { vm.minWeightCount <= 1 || $0.weightCount >= vm.minWeightCount }
            .filter { !vm.favoritesOnly || favorites.contains($0.name) }
            .filter { !vm.memoOnly || memos.hasNote(for: $0.name) }
            .filter { !vm.koreanOnly || $0.supportsKorean }
            .filter { !vm.englishOnly || $0.supportsLatin }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            gridArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            BottomFadeOverlay()
                .frame(height: 110)
                .allowsHitTesting(false)
            detailOverlay
            PreviewInputBar(text: $previewText)
                .padding(.horizontal, Theme.gridPadding)
                .padding(.vertical, 12)
        }
        .background(Theme.panelBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private var detailOverlay: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Theme.gridPadding)
            .padding(.top, Theme.gridPadding)
            .padding(.bottom, 67)
        }
    }

    private var gridArea: some View {
        GeometryReader { geo in
            let computed = computeMaxColumns(width: geo.size.width)
            let effective = min(max(1, vm.columnCount), computed)
            let rows = displayed.chunked(into: effective)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: Theme.gridSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: Theme.gridSpacing) {
                                ForEach(row) { family in
                                    cellView(for: family)
                                        .frame(maxWidth: .infinity)
                                        .zIndex(hoveredFamilyID == family.id ? 1 : 0)
                                }
                                if row.count < effective {
                                    ForEach(0..<(effective - row.count), id: \.self) { _ in
                                        Color.clear.frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .zIndex(row.contains(where: { $0.id == hoveredFamilyID }) ? 1 : 0)
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
        if vm.memoOnly {
            return "메모가 있는 폰트가 없습니다."
        }
        return "표시할 폰트가 없습니다."
    }

    private func computeMaxColumns(width: CGFloat) -> Int {
        let usable = max(0, width - Theme.gridPadding * 2)
        let n = Int(floor((usable + Theme.gridSpacing) / (Theme.minCellWidth + Theme.gridSpacing)))
        return max(1, n)
    }

    @ViewBuilder
    private func cellView(for family: FontFamily) -> some View {
        if vm.selectedFamily?.id == family.id {
            Color.clear
                .frame(height: Theme.cellHeight(fontSize: vm.gridFontSize))
        } else {
            FontCell(
                family: family,
                previewText: previewText,
                fontSize: vm.gridFontSize,
                onHoverChange: { isHovering in
                    if isHovering {
                        hoveredFamilyID = family.id
                    } else if hoveredFamilyID == family.id {
                        hoveredFamilyID = nil
                    }
                },
                onTap: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                        vm.selectedFamily = family
                    }
                }
            )
            .matchedGeometryEffect(id: family.id, in: cellHero)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

// MARK: - Preview Input Bar

struct PreviewInputBar: View {
    @Binding var text: String
    @StateObject private var inputSource = InputSourceManager()
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                inputSource.toggle()
                focused = true
            } label: {
                Group {
                    if inputSource.isKorean {
                        Text("가")
                            .font(.system(size: 14, weight: .medium))
                    } else {
                        Image(systemName: "textformat")
                            .font(.system(size: 13))
                    }
                }
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(inputSource.isKorean ? "Switch to English input" : "Switch to Korean input")

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
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(focused ? Theme.borderHover : Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Bottom Fade Overlay

struct BottomFadeOverlay: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.85), location: 0.55),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0), location: 0),
                    .init(color: Color.black.opacity(0.35), location: 0.45),
                    .init(color: Color.black.opacity(0.75), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - System Input Source Manager

@MainActor
final class InputSourceManager: ObservableObject {
    @Published var isKorean: Bool = false

    init() {
        refresh()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleChange),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    @objc private func handleChange() {
        DispatchQueue.main.async { self.refresh() }
    }

    func toggle() { selectFirst(matchingKorean: !isKorean) }

    private func refresh() {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else { return }
        let source = unmanaged.takeRetainedValue()
        isKorean = sourceMatchesKorean(source)
    }

    private func selectFirst(matchingKorean wantKorean: Bool) {
        guard let listUnmanaged = TISCreateInputSourceList(nil, false) else { return }
        let array = listUnmanaged.takeRetainedValue() as NSArray
        for case let source as TISInputSource in array {
            guard isSelectable(source) else { continue }
            let matches = wantKorean ? sourceMatchesKorean(source) : sourceMatchesEnglish(source)
            if matches {
                TISSelectInputSource(source)
                isKorean = wantKorean
                return
            }
        }
    }

    private func isSelectable(_ source: TISInputSource) -> Bool {
        boolProperty(source, key: kTISPropertyInputSourceIsSelectCapable) &&
        boolProperty(source, key: kTISPropertyInputSourceIsEnabled)
    }

    private func sourceMatchesKorean(_ source: TISInputSource) -> Bool {
        let id = stringProperty(source, key: kTISPropertyInputSourceID).lowercased()
        if id.contains("korean") || id.contains("hangul") { return true }
        return languages(source).contains { $0.hasPrefix("ko") }
    }

    private func sourceMatchesEnglish(_ source: TISInputSource) -> Bool {
        let id = stringProperty(source, key: kTISPropertyInputSourceID).lowercased()
        if id.contains("keylayout.abc") || id.contains("keylayout.us") { return true }
        return languages(source).contains { $0.hasPrefix("en") }
    }

    private func stringProperty(_ source: TISInputSource, key: CFString) -> String {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }

    private func languages(_ source: TISInputSource) -> [String] {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        return (Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String]) ?? []
    }
}
