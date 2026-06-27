import SwiftUI
import AppKit
import Carbon

struct CenterPanel: View {
    // True when the left panel is collapsed, so the center panel reaches the
    // window's left edge and the top bar must clear the traffic-light buttons.
    var leftCollapsed: Bool = false

    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @EnvironmentObject var muted: MutedStore
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

    // Extra leading inset for the top bar when the left panel is collapsed, so
    // the leading text starts ~16px to the right of the traffic-light buttons
    // instead of running under them.
    private static let trafficLightClearance: CGFloat = 84

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
            .filter { family in
                if vm.mutedOnly { return muted.contains(family.name) }
                switch vm.mutedFilter {
                case .shown:  return true
                case .hidden: return !muted.contains(family.name)
                }
            }
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
            topBar(count: displayedFamilies.count)
                .opacity(topBarHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: topBarHidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                // Interactive only while the detail is open (for the prev/next
                // nav buttons) and the bar is actually visible; otherwise the
                // empty band must let grid clicks/scroll pass through.
                .allowsHitTesting(vm.selectedFamily != nil && !topBarHidden)
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
    private func topBar(count: Int) -> some View {
        HStack(spacing: 8) {
            if vm.selectedFamily != nil {
                // Detail open: previous font (left) / next font (right). Each is a
                // button that steps the detail, mirroring the ←/→ arrow keys. Both
                // slots always render (disabled at a list end) so the view identity
                // stays stable across navigation — otherwise hover/press state would
                // reset and the button under the cursor wouldn't respond to a repeat
                // click. The Spacer keeps each button hugging its own edge.
                NeighbourNavButton(name: detailNeighbour(-1), delta: -1) { stepDetail(-1) }
                Spacer(minLength: 8)
                NeighbourNavButton(name: detailNeighbour(1), delta: 1) { stepDetail(1) }
            } else {
                Text("08FOSE")
                    .font(.system(size: Theme.sectionHeaderSize + 2, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(statsText(count))
                    .font(.system(size: Theme.sectionHeaderSize + 2))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, leftCollapsed ? Self.trafficLightClearance : 0)
        .padding(.horizontal, Theme.gridPadding)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        // Nudged down to sit level with the window traffic-light buttons.
        .padding(.top, 11)
    }

    // Right-aligned stats label, reflecting the active list/filter. `count` is
    // the number of families currently shown.
    private func statsText(_ count: Int) -> String {
        if let tag = vm.activeTag { return "Tag : \(tag)" }

        // Collection + script filters joined by middle dots. With a single
        // segment the full word is used; with 2+ segments (≥1 middle dot)
        // everything abbreviates: FAV / MEM / MUT and KR / JP / LTN / ETC.
        let scripts = ScriptCategory.allCases.filter { vm.scriptFilter.contains($0) }
        let total = (vm.favoritesOnly ? 1 : 0) + (vm.memoOnly ? 1 : 0)
            + (vm.mutedOnly ? 1 : 0) + scripts.count
        if total == 0 { return "\(count) fonts" }
        let abbr = total >= 2

        var segments: [String] = []
        if vm.favoritesOnly { segments.append(abbr ? "FAV" : "favorites") }
        if vm.memoOnly { segments.append(abbr ? "MEM" : "Memoed") }
        if vm.mutedOnly { segments.append(abbr ? "MUT" : "Muted") }
        segments.append(contentsOf: scripts.map { abbr ? $0.abbreviation : $0.label })

        // Thin spaces (U+2009) around the middle dot keep the separators tight.
        return "\(count) \(segments.joined(separator: "\u{2009}·\u{2009}"))"
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
        vm.openDetail(list[next], source: vm.detailSource)
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
                onClose: { vm.closeDetail() }
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
    @EnvironmentObject var muted: MutedStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredFamilyID: FontFamily.ID? = nil
    // The family currently at the top of the viewport. Tracked locally (so it
    // does NOT invalidate CenterPanel's body / the filter chain) and read only
    // when the column count or font size changes, to keep that family in view.
    @State private var topVisibleFamily: FontFamily.ID? = nil
    // Bumped on each keep-in-view request so pending passes from a superseded
    // change (e.g. mid-drag) cancel themselves instead of piling up.
    @State private var keepTopToken = 0

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
            // The family whose top is nearest the viewport top. A fixed
            // threshold (e.g. minY ≤ 20) misses the top row when it sits just
            // beyond it and grabs the off-screen row above — a one-row error
            // that the column count then multiplies into a visible drift.
            let best = candidates.min(by: { abs($0.minY) < abs($1.minY) })
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
        // Re-assert across several frames. A font-size change settles fast, but a
        // column-count change restructures the LazyVGrid (and tends to reset the
        // scroll to the top), which settles later — so a single early pass gets
        // overridden. The later passes land the target back once the layout is
        // stable. Debounced via a token so a rapid slider drag doesn't pile up
        // dozens of overlapping passes — only the latest change's passes run.
        keepTopToken += 1
        let token = keepTopToken
        for delay in [0.0, 0.05, 0.15, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard token == keepTopToken else { return }
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
                // Suppress memo tooltips while the grid is covered — by the
                // Settings blur or by the open detail card.
                tooltipSuppressed: vm.showSettings || vm.selectedFamily != nil,
                // Muted fonts read de-emphasized but stay fully tappable.
                dimmed: muted.contains(family.name),
                onHoverChange: { isHovering in
                    if isHovering {
                        hoveredFamilyID = family.id
                    } else if hoveredFamilyID == family.id {
                        hoveredFamilyID = nil
                    }
                },
                onTap: {
                    vm.openDetail(family, source: .grid)
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
                .shadow(color: .black.opacity(0.35 * shadowScale), radius: 36, x: 0, y: 32)
                .shadow(color: .black.opacity(0.6 * shadowScale), radius: 20, x: 0, y: 20)
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25).delay(0.05)) { shown = true }
        }
    }
}

// Clickable previous/next-font label in the detail top bar. Same action as the
// ←/→ arrow keys (stepDetail). The hit target is the text plus a little padding
// (full band height, but only as wide as the label — not the half-bar), and hover
// only deepens the text (tertiary → primary, no hue) plus a pointing-hand cursor
// so it reads as a button. `name` is nil at a list end → the button disables but
// stays in place, keeping a stable identity so repeat clicks register.
private struct NeighbourNavButton: View {
    let name: String?
    let delta: Int                 // -1 = previous (left), +1 = next (right)
    let action: () -> Void
    @State private var hovering = false

    private var enabled: Bool { name != nil }

    var body: some View {
        Button(action: action) {
            Text(name.map { delta < 0 ? "←  \($0)" : "\($0)  →" } ?? "")
                .font(.system(size: Theme.sectionHeaderSize + 2))
                .foregroundStyle(hovering && enabled ? .primary : .tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)   // full band height, label width only
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // .set() (not push/pop) so a missed exit can't leak a stacked cursor.
        .onHover { inside in
            hovering = inside
            (inside && enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
        // If navigation disables this slot while the cursor is still over it,
        // the hover-exit may not fire — reset state and cursor explicitly.
        .onChange(of: enabled) { nowEnabled in
            if !nowEnabled { hovering = false; NSCursor.arrow.set() }
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
    @EnvironmentObject var inputSource: InputSourceManager
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                inputSource.toggle()
                focused = true
            } label: {
                Text(inputSource.isKorean ? "가" : "A")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(inputSource.isKorean ? "Switch to English input" : "Switch to Korean input")

            TextField(inputSource.pangram, text: $text)
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

    // Empty-state preview pangram, by current input source. Single source of
    // truth for the fallback shown when the preview field is cleared.
    var pangram: String {
        isKorean ? "다람쥐 헌 쳇바퀴에 타고파." : "The quick brown fox jumps over lazy dog."
    }

    // The text to render: what the user typed, or the language pangram if empty.
    func resolved(_ text: String) -> String { text.isEmpty ? pangram : text }

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
