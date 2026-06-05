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
    // Mirrors the key window's .fullScreen styleMask. In fullscreen there is no
    // titlebar inset, so the topBar would sit directly on top of the detail card
    // — we keep it hidden in that case.
    @State private var isFullscreen: Bool = false

    // Height of the pinned title band (top padding 4 + height 28), plus a small
    // margin. Grid cells scrolling above this overlap the title text.
    private static let titleBandHeight: CGFloat = 40

    // The topBar is hidden only when a grid cell is actually about to overlap
    // the title band. When the detail overlay is open in WINDOWED mode, the
    // grid is covered by the card and the titlebar inset gives the topBar a
    // place to sit clear of the card — so we force it visible. In fullscreen
    // there is no such inset, and the topBar would overlap the card; we let
    // the normal "hidden when scrolled to the top" path apply.
    private var topBarHidden: Bool {
        if vm.selectedFamily != nil && !isFullscreen { return false }
        return gridTopY < Self.titleBandHeight
    }

    private func syncFullscreenState() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
        isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
    }

    private var displayed: [FontFamily] {
        vm.library.families
            .filter { family in
                vm.searchQuery.isEmpty
                    || family.name.localizedCaseInsensitiveContains(vm.searchQuery)
                    || memos.note(for: family.name).localizedCaseInsensitiveContains(vm.searchQuery)
            }
            .filter { vm.weightFilter.matches($0.weightCount) }
            .filter { !vm.favoritesOnly || favorites.contains($0.name) }
            .filter { !vm.memoOnly || memos.hasNote(for: $0.name) }
            .filter { vm.scriptFilter.isEmpty || vm.scriptFilter.contains($0.script) }
            .filter { vm.activeTag == nil || memos.tags(for: $0.name).contains(vm.activeTag!) }
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
        .onPreferenceChange(GridTopYKey.self) { gridTopY = $0 }
        .onAppear { syncFullscreenState() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
        .background(Theme.panelBackground.ignoresSafeArea())
    }

    // Title + font-count stats in the otherwise-empty title-bar band at the top
    // of the center panel. Uses the smallest type size in the app.
    private var topBar: some View {
        HStack(spacing: 8) {
            if vm.selectedFamily != nil {
                // Detail open: previous font (left) / next font (right). Display
                // only — the bar is non-interactive (allowsHitTesting false).
                Text(detailNeighbour(-1).map { "←  \($0)" } ?? "")
                    .font(.system(size: Theme.sectionHeaderSize + 2))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(detailNeighbour(1).map { "\($0)  →" } ?? "")
                    .font(.system(size: Theme.sectionHeaderSize + 2))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text("08FOSE")
                    .font(.system(size: Theme.sectionHeaderSize + 2, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(statsText)
                    .font(.system(size: Theme.sectionHeaderSize + 2))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Theme.gridPadding)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.top, 4)
    }

    private var statsText: String {
        let stats = vm.library.stats
        return "\(stats.total) fonts"
    }

    @ViewBuilder
    private func emptyOverlay(_ displayedFamilies: [FontFamily]) -> some View {
        if displayedFamilies.isEmpty {
            Text("Nothing found")
                .font(.custom(emptyStateFontName ?? "Helvetica", size: vm.gridFontSize))
                .foregroundStyle(Color.primary.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .onAppear { pickEmptyStateFont() }
        }
    }

    private func pickEmptyStateFont() {
        let candidates = vm.library.families.filter { $0.script == .latin }
        emptyStateFontName = candidates.randomElement()?.memberFontNames.first
    }

    // Ordered list the arrow keys step through, matching how the detail was
    // opened: the filtered grid, or the favorites list in its current sort.
    private var navigationFamilies: [FontFamily] {
        switch vm.detailSource {
        case .favorites:
            let names = vm.favoritesByRecent ? favorites.byRecency : favorites.sorted
            return names.compactMap { name in
                vm.library.families.first { $0.name == name }
            }
        case .grid:
            return displayed
        }
    }

    // Move the open detail to the previous/next font (clamped at the ends).
    private func stepDetail(_ delta: Int) {
        guard let current = vm.selectedFamily else { return }
        let list = navigationFamilies
        guard let idx = list.firstIndex(where: { $0.id == current.id }) else { return }
        let next = idx + delta
        guard next >= 0, next < list.count else { return }
        vm.selectedFamily = list[next]
    }

    // Names of the neighbours in the navigation list, for the top-bar label
    // shown while the detail is open. nil at the list ends (matches clamp).
    private func detailNeighbour(_ delta: Int) -> String? {
        guard let current = vm.selectedFamily else { return nil }
        let list = navigationFamilies
        guard let idx = list.firstIndex(where: { $0.id == current.id }) else { return nil }
        let n = idx + delta
        guard n >= 0, n < list.count else { return nil }
        return list[n].name
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
                DetailArrowKeyHandler(onStep: { stepDetail($0) })
            )
            .zIndex(30)
        }
    }

    private func gridArea(_ displayedFamilies: [FontFamily]) -> some View {
        GeometryReader { geo in
            let computed = computeMaxColumns(width: geo.size.width)
            let effective = min(max(1, vm.columnCount), computed)

            FontGridScroll(
                families: displayedFamilies,
                columns: effective,
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

// One rendered cell's id + its top edge (minY) in the scroll viewport's
// coordinate space. Collected for every visible cell so we can find which
// family currently sits at the top of the viewport.
private struct TopCandidate: Equatable {
    let id: FontFamily.ID
    let minY: CGFloat
}

private struct TopVisibleKey: PreferenceKey {
    static var defaultValue: [TopCandidate] = []
    static func reduce(value: inout [TopCandidate], nextValue: () -> [TopCandidate]) {
        value.append(contentsOf: nextValue())
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
    static let scrollOffsetKey = "centerGridScrollY"

    let families: [FontFamily]
    let columns: Int
    let previewText: String
    let cellHero: Namespace.ID

    // Equal-width flexible columns, matching the manual HStack layout this
    // replaced. LazyVGrid (vs LazyVStack of HStacks) tracks every font as its
    // own element, so ScrollViewProxy.scrollTo(family.id) reliably reaches a
    // font even when it has scrolled off-screen — which is what makes the
    // column/font-size position compensation work.
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacing),
              count: max(1, columns))
    }

    @EnvironmentObject var vm: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredFamilyID: FontFamily.ID? = nil
    // The family currently at the top of the viewport. Tracked locally (so it
    // does NOT invalidate CenterPanel's body / the filter chain) and read only
    // when the column count or font size changes, to keep that family in view.
    @State private var topVisibleFamily: FontFamily.ID? = nil

    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Theme.gridSpacing) {
                ForEach(families) { family in
                    cellView(for: family)
                        .frame(maxWidth: .infinity)
                        .id(family.id)
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: TopVisibleKey.self,
                                    value: [TopCandidate(
                                        id: family.id,
                                        minY: g.frame(in: .named("fontGridScroll")).minY
                                    )]
                                )
                            }
                        )
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
            // Lives INSIDE the scroll view (background of the grid content) so
            // its hosting NSView is a descendant of NSScrollView's document
            // view — `enclosingScrollView` then resolves correctly. If this is
            // moved out of the ScrollView, the probe can't find the scroller
            // and offset restore silently no-ops.
            .background(ScrollOffsetPersistence(key: Self.scrollOffsetKey))
            .padding(Theme.gridPadding)
            .padding(.bottom, 48)
        }
        .coordinateSpace(name: "fontGridScroll")
        .scrollContentBackground(.hidden)
        // Shadow for the single hovered cell, drawn above all cells so it is not
        // covered by neighbours (LazyVGrid paints rows in document order and
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
        // Track which family is at the top of the viewport. Local state only —
        // updated just at row-boundary crossings (the id guard), so it does not
        // re-render on every scroll frame.
        .onPreferenceChange(TopVisibleKey.self) { candidates in
            guard !candidates.isEmpty else { return }
            // The top-of-viewport cell is the lowest one whose top is still at
            // or above the visible top region (largest minY among those ≤ 20).
            // Fall back to the first cell when scrolled all the way up.
            let atOrAboveTop = candidates.filter { $0.minY <= 20 }
            let best = atOrAboveTop.max(by: { $0.minY < $1.minY })
                ?? candidates.min(by: { $0.minY < $1.minY })
            if let id = best?.id, id != topVisibleFamily {
                topVisibleFamily = id
            }
        }
        // On a layout change (columns or font size), keep the previously-top
        // family in view. Async so the new layout has been applied before we
        // scroll. The target is captured synchronously to avoid a race with the
        // preference updates the relayout triggers.
        .onChange(of: vm.columnCount) { _ in keepTopInView(proxy) }
        .onChange(of: vm.previewSizeOffset) { _ in keepTopInView(proxy) }
        } // ScrollViewReader
    }

    private func keepTopInView(_ proxy: ScrollViewProxy) {
        guard let target = topVisibleFamily else { return }
        // Two passes: the first realizes the target's region (it may have been
        // recycled by the lazy grid during the relayout); the second, after that
        // cell exists, lands its top exactly at the viewport top.
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                proxy.scrollTo(target, anchor: .top)
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
                // Suppress memo tooltips while the Settings blur covers the grid.
                tooltipSuppressed: vm.showSettings,
                onHoverChange: { isHovering in
                    if isHovering {
                        hoveredFamilyID = family.id
                    } else if hoveredFamilyID == family.id {
                        hoveredFamilyID = nil
                    }
                },
                onTap: {
                    vm.detailSource = .grid
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
            withAnimation(.easeOut(duration: 0.3).delay(0.06)) { shown = true }
        }
    }
}

// ←/→ navigation while the detail view is open: step to the previous/next
// font. Ignored when a text field is being edited (so the preview bar / memo
// editor keep normal cursor movement). ESC is handled globally in RootView.
private struct DetailArrowKeyHandler: NSViewRepresentable {
    var onStep: (Int) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        // Drop text-field focus (e.g. the preview bar) when the detail opens so
        // the arrow keys navigate instead of moving a hidden text cursor.
        DispatchQueue.main.async { view.window?.makeFirstResponder(nil) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onStep = onStep
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStep: onStep)
    }

    final class Coordinator {
        var onStep: (Int) -> Void
        private var monitor: Any?

        init(onStep: @escaping (Int) -> Void) {
            self.onStep = onStep
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // ←(123) / →(124)
                guard event.keyCode == 123 || event.keyCode == 124 else { return event }
                // Let text editing keep arrow keys (cursor movement).
                if event.window?.firstResponder is NSText { return event }
                // Plain arrows only — leave ⌘/⌥/⌃ combos for the system.
                if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                    return event
                }
                self.onStep(event.keyCode == 124 ? 1 : -1)
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

// MARK: - Scroll Offset Persistence
//
// SwiftUI ScrollView exposes no public API for reading or setting its
// content offset, so we walk up from a hidden NSView to find the enclosing
// NSScrollView and:
//   - on first sighting, restore the saved Y offset (after one runloop tick
//     so the lazy grid has produced enough content for the offset to clamp
//     correctly);
//   - observe contentView bounds changes and write the new Y to defaults.
//
// The Y is in NSScrollView document coordinates (flipped or not depending on
// the document view's isFlipped), but we read and write through the same
// path so the value round-trips cleanly.

private struct ScrollOffsetPersistence: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.key = key
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.key = key
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? ProbeView)?.detach()
    }

    private final class ProbeView: NSView {
        var key: String = ""
        private weak var observedClipView: NSClipView?
        private var didRestore = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // The scroll view doesn't exist yet on this tick; defer.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard observedClipView == nil,
                  let scroll = enclosingScrollView,
                  let clip = scroll.contentView as NSClipView?
            else { return }

            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
            observedClipView = clip

            if !didRestore {
                didRestore = true
                let saved = UserDefaults.standard.double(forKey: key)
                if saved > 0 {
                    restoreWithRetry(target: saved, attempts: 12)
                }
            }
        }

        // LazyVGrid only realizes the visible window of cells, so the
        // documentView is initially short and our target Y clamps to the
        // bottom. Each restore pass scrolls toward the target, which forces
        // the lazy grid to realize more rows; we retry until the documentView
        // is tall enough (or we run out of attempts). Suppress the bounds
        // observer's writes during this dance so the saved value isn't
        // overwritten by intermediate clamped positions.
        private func restoreWithRetry(target: CGFloat, attempts: Int) {
            guard attempts > 0,
                  let clip = observedClipView,
                  let scroll = clip.enclosingScrollView else {
                // Out of retries (or detached) without reaching the target —
                // e.g. fewer fonts than last launch, so the saved Y is now past
                // the bottom. Re-enable persistence; the clamped position we
                // landed on is a fine value to start saving from.
                suppressWrites = false
                return
            }
            suppressWrites = true
            let docHeight = scroll.documentView?.bounds.height ?? 0
            let maxY = max(0, docHeight - clip.bounds.height)
            let clamped = min(max(0, target), maxY)
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: clamped))
            scroll.reflectScrolledClipView(clip)

            if clamped >= target - 0.5 {
                // Reached the target. Re-enable writes on the next tick so any
                // settle-frame doesn't overwrite the saved key.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.suppressWrites = false
                }
            } else {
                // documentView wasn't tall enough yet — give the lazy grid a
                // tick to realize more rows, then try again.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    self?.restoreWithRetry(target: target, attempts: attempts - 1)
                }
            }
        }

        private var suppressWrites = false

        @objc private func boundsChanged(_ note: Notification) {
            guard !suppressWrites, let clip = note.object as? NSClipView else { return }
            UserDefaults.standard.set(Double(clip.bounds.origin.y), forKey: key)
        }

        func detach() {
            if let clip = observedClipView {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clip)
            }
            observedClipView = nil
        }

        deinit { detach() }
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
