import SwiftUI
import AppKit
import Carbon

struct CenterPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @AppStorage("previewText") private var previewText = "The quick brown fox jumps over lazy dog"
    @Namespace private var cellHero
    @State private var emptyStateFontName: String? = nil
    // Top edge of the grid container, in WINDOW coordinates. Reflects the safe
    // area (title-bar inset in windowed mode, 0 in fullscreen), so the same
    // scroll-top position reads ~44 windowed but ~16 in fullscreen.
    @State private var gridTopY: CGFloat = .infinity
    // Collapsed visibility flag actually driving opacity. We don't measure the
    // title text: it's pinned to the top of the window at a fixed height, so we
    // just compare the grid's top against that fixed band. Measuring topBar via
    // GeometryReader returned 0 in fullscreen (ignoresSafeArea + infinite frame
    // collapse), which is why the overlap check failed there.
    @State private var topBarHidden = false

    // Height of the pinned title band (top padding 4 + height 28), plus a small
    // margin. Grid cells scrolling above this overlap the title text.
    private static let titleBandHeight: CGFloat = 40

    private func recomputeTopBarHidden() {
        let hidden = gridTopY < Self.titleBandHeight
        if hidden != topBarHidden { topBarHidden = hidden }
    }

    private var displayed: [FontFamily] {
        vm.library.families
            .filter { family in
                vm.searchQuery.isEmpty
                    || family.name.localizedCaseInsensitiveContains(vm.searchQuery)
                    || memos.note(for: family.name).localizedCaseInsensitiveContains(vm.searchQuery)
            }
            .filter { vm.minWeightCount <= 1 || $0.weightCount >= vm.minWeightCount }
            .filter { !vm.favoritesOnly || favorites.contains($0.name) }
            .filter { !vm.memoOnly || memos.hasNote(for: $0.name) }
            .filter { !vm.koreanOnly || $0.supportsKorean }
            .filter { !vm.englishOnly || $0.isNonKoreanText }
    }

    var body: some View {
        let displayedFamilies = displayed
        ZStack(alignment: .bottom) {
            gridArea(displayedFamilies)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            emptyOverlay(displayedFamilies)
            BottomFadeOverlay()
                .frame(height: 110)
                .allowsHitTesting(false)
            detailOverlay
            // Title + stats, always visible at the top. Above the detail,
            // below the input bar.
            topBar
                .opacity(topBarHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: topBarHidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .zIndex(35)
            PreviewInputBar(text: $previewText)
                .padding(.horizontal, Theme.gridPadding)
                .padding(.vertical, 12)
                .zIndex(40)
        }
        .onPreferenceChange(GridTopYKey.self) { gridTopY = $0; recomputeTopBarHidden() }
        .background(Theme.panelBackground.ignoresSafeArea())
    }

    // Title + font-count stats in the otherwise-empty title-bar band at the top
    // of the center panel. Uses the smallest type size in the app.
    private var topBar: some View {
        HStack(spacing: 8) {
            Text("08FOSE")
                .font(.system(size: Theme.sectionHeaderSize + 2, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(statsText)
                .font(.system(size: Theme.sectionHeaderSize + 2))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.gridPadding)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.top, 4)
    }

    private var statsText: String {
        let stats = vm.library.stats
        return "\(stats.total) fonts · \(stats.korean) Korean · \(stats.english) English"
    }

    @ViewBuilder
    private func emptyOverlay(_ displayedFamilies: [FontFamily]) -> some View {
        if displayedFamilies.isEmpty {
            Text("No Result")
                .font(.custom(emptyStateFontName ?? "Helvetica", size: vm.gridFontSize))
                .foregroundStyle(Color.primary.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .onAppear { pickEmptyStateFont() }
        }
    }

    private func pickEmptyStateFont() {
        let candidates = vm.library.families.filter { $0.supportsLatin && !$0.supportsKorean }
        emptyStateFontName = candidates.randomElement()?.memberFontNames.first
    }

    @ViewBuilder
    private var detailOverlay: some View {
        if vm.selectedFamily != nil {
            Theme.panelBackground
                .ignoresSafeArea(edges: .top)
                .transition(.opacity)
                .zIndex(20)
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
            .background(
                EscapeKeyHandler {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        vm.selectedFamily = nil
                    }
                }
            )
            .zIndex(30)
        }
    }

    private func gridArea(_ displayedFamilies: [FontFamily]) -> some View {
        GeometryReader { geo in
            let computed = computeMaxColumns(width: geo.size.width)
            let effective = min(max(1, vm.columnCount), computed)
            let rows = displayedFamilies.chunked(into: effective)

            FontGridScroll(
                rows: rows,
                effective: effective,
                previewText: previewText,
                cellHero: cellHero
            )
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

    private func computeMaxColumns(width: CGFloat) -> Int {
        let usable = max(0, width - Theme.gridPadding * 2)
        let n = Int(floor((usable + Theme.gridSpacing) / (Theme.minCellWidth + Theme.gridSpacing)))
        return max(1, n)
    }
}

private struct GridTopYKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

// Identity + frame of the hovered cell. The id lets the shadow remount per
// cell (so each hover re-runs the fade-in) and pins its position to that cell's
// exact coordinates — no interpolation across cells.
struct HoveredCellInfo {
    let id: FontFamily.ID
    let anchor: Anchor<CGRect>
}

struct HoveredCellAnchorKey: PreferenceKey {
    static var defaultValue: HoveredCellInfo? = nil
    static func reduce(value: inout HoveredCellInfo?, nextValue: () -> HoveredCellInfo?) {
        if let next = nextValue() { value = next }
    }
}


// MARK: - Scrollable Font Grid
//
// Holds the hover state locally so hovering a cell does NOT invalidate
// CenterPanel's body (and thus does not re-run the family filter chain).
// LazyVStack keeps large installed-font libraries from instantiating every
// Core Text preview at launch. Shadow is rendered via overlayPreferenceValue
// so it always sits above all cells regardless of lazy-stack paint order.

private struct FontGridScroll: View {
    let rows: [[FontFamily]]
    let effective: Int
    let previewText: String
    let cellHero: Namespace.ID

    @EnvironmentObject var vm: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredFamilyID: FontFamily.ID? = nil

    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.gridSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Theme.gridSpacing) {
                        ForEach(row) { family in
                            cellView(for: family)
                                .frame(maxWidth: .infinity)
                        }
                        if row.count < effective {
                            ForEach(0..<(effective - row.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GridTopYKey.self,
                        value: geo.frame(in: .global).minY
                    )
                }
            )
            .padding(Theme.gridPadding)
            .padding(.bottom, 48)
        }
        .scrollContentBackground(.hidden)
        // Shadow for the single hovered cell, drawn above all cells so it is not
        // covered by neighbours (LazyVStack paints rows in document order and
        // ignores zIndex across rows). HoverShadow is keyed by the cell id, so
        // it remounts per cell: position is fixed to that cell's exact frame (no
        // glide between cells) and the fade-in re-runs on each new hover.
        .overlayPreferenceValue(HoveredCellAnchorKey.self) { info in
            if let info {
                GeometryReader { geo in
                    let f = geo[info.anchor]
                    HoverShadow(shadowScale: shadowScale)
                        .frame(width: f.width, height: f.height)
                        .position(x: f.midX, y: f.midY)
                        .id(info.id)
                }
                .allowsHitTesting(false)
            }
        }
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

// Drop shadow halo for the hovered cell. ZStack + destinationOut keeps only the
// shadow (the fill is punched out so the real cell shows through). Fades its own
// opacity in on appear — a short delay so quick passes don't flash a shadow, and
// a slightly longer ramp so it reads as the cell settling rather than snapping.
private struct HoverShadow: View {
    let shadowScale: Double
    @State private var shown = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.cellSurface)
                .shadow(color: .black.opacity(0.75 * shadowScale), radius: 14, x: 0, y: 16)
                .shadow(color: .black.opacity(0.90 * shadowScale), radius: 80, x: 0, y: 70)
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.12)) { shown = true }
        }
    }
}

private struct EscapeKeyHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEscape: onEscape)
    }

    final class Coordinator {
        private let onEscape: () -> Void
        private var monitor: Any?

        init(onEscape: @escaping () -> Void) {
            self.onEscape = onEscape
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.onEscape()
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            uninstall()
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
                .fill(Theme.cellSurface)
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
            // Tint toward the panel background (not hard black) so the fade
            // reads correctly in both light and dark appearance.
            LinearGradient(
                stops: [
                    .init(color: Theme.panelBackground.opacity(0), location: 0),
                    .init(color: Theme.panelBackground.opacity(0.35), location: 0.45),
                    .init(color: Theme.panelBackground.opacity(0.75), location: 1)
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
