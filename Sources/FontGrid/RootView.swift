import SwiftUI
import AppKit

struct RootView: View {
    @StateObject private var vm = AppViewModel()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var memos = MemoStore()
    @StateObject private var samples = SampleStore()
    @StateObject private var muted = MutedStore()

    @State private var leftDragStart: Double? = nil
    @State private var rightDragStart: Double? = nil
    // Session-only panel collapse state (not persisted; both open on launch).
    @State private var leftPanelOpen = true
    @State private var rightPanelOpen = true

    // Floating collapse/expand button geometry.
    private static let toggleSize: CGFloat = 26
    private static let toggleEdgeInset: CGFloat = 12
    private static let toggleBottomInset: CGFloat = 9

    var body: some View {
        HStack(spacing: 0) {
            if leftPanelOpen {
                LeftPanel()
                    .frame(width: vm.leftPanelWidth)
                    .transition(.move(edge: .leading))
                ResizableVDivider(
                    width: $vm.leftPanelWidth,
                    dragStartWidth: $leftDragStart,
                    minWidth: Double(Theme.panelMinWidth),
                    maxWidth: Double(Theme.panelMaxWidth),
                    edge: .left
                )
            }
            CenterPanel(leftCollapsed: !leftPanelOpen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if rightPanelOpen {
                ResizableVDivider(
                    width: $vm.rightPanelWidth,
                    dragStartWidth: $rightDragStart,
                    minWidth: Double(Theme.panelMinWidth),
                    maxWidth: Double(Theme.panelMaxWidth),
                    edge: .right
                )
                RightPanel()
                    .frame(width: vm.rightPanelWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Wallpaper overlay: same mechanism in both dark and light mode, driven
        // by vm.wallpaper. Image, blend mode and opacity are all picked inside
        // WallpaperOverlay based on the current colorScheme.
        .overlay { WallpaperOverlay(name: vm.wallpaper) }
        // Floating panel collapse/expand buttons. When a panel is open the
        // button sits at that panel's bottom-inner corner showing "−"; when
        // collapsed it docks at the screen's bottom-outer corner showing "+".
        .overlay(alignment: .bottomLeading) {
            PanelToggleButton(open: leftPanelOpen) {
                withAnimation(.easeInOut(duration: 0.22)) { leftPanelOpen.toggle() }
            }
            .offset(x: leftToggleX, y: -Self.toggleBottomInset)
        }
        .overlay(alignment: .bottomTrailing) {
            PanelToggleButton(open: rightPanelOpen) {
                withAnimation(.easeInOut(duration: 0.22)) { rightPanelOpen.toggle() }
            }
            .offset(x: rightToggleX, y: -Self.toggleBottomInset)
        }
        // Full-window Settings modal, above everything including the wallpaper.
        .overlay {
            if vm.showSettings {
                // Blur is full-window, but the settings content + close button
                // are confined to the center panel column (dividers are 1pt).
                SettingsOverlay(leftInset: vm.leftPanelWidth + 1, rightInset: vm.rightPanelWidth + 1)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: vm.showSettings)
        .background(Theme.panelBackground.ignoresSafeArea())
        .background(InitialFocusClearer())
        .background(GlobalShortcutHandler(
            onKey: handleShortcut,
            onCloseDetail: closeDetailIfOpen,
            onCloseSettings: closeSettingsIfOpen,
            onToggleSettings: toggleSettings,
            onCommandArrow: handleCommandArrow
        ))
        .environmentObject(vm)
        .environmentObject(favorites)
        .environmentObject(memos)
        .environmentObject(samples)
        .environmentObject(muted)
        .preferredColorScheme(vm.isLightMode ? .light : .dark)
    }

    // Horizontal offset for the left toggle (anchored bottom-leading):
    // open → bottom-inner corner of the left panel (near the divider);
    // closed → docked at the left screen edge.
    private var leftToggleX: CGFloat {
        leftPanelOpen
            ? CGFloat(vm.leftPanelWidth) - Self.toggleEdgeInset - Self.toggleSize + 3  // 3px further inward
            : Self.toggleEdgeInset - 3                                                 // tucked toward the corner
    }

    // Horizontal offset for the right toggle (anchored bottom-trailing):
    // open → bottom-inner corner of the right panel; closed → right screen edge.
    private var rightToggleX: CGFloat {
        rightPanelOpen
            ? -(CGFloat(vm.rightPanelWidth) - Self.toggleEdgeInset - Self.toggleSize) - 3  // 3px further inward
            : -(Self.toggleEdgeInset - 3)                                                  // tucked toward the corner
    }

    // App-wide single-key shortcuts (no modifiers, not while editing text):
    //   0–4 → wallpaper (0 = none, 1–4 = Wallpaper01–04)
    //   t   → toggle dark / light theme
    //   w   → cycle Weights filter (All → 1 → 3+ → 5+ → All)
    //   f/m → favorites / memo filter
    //   k/j/c/l/s/o → toggle script bucket
    //   (korean / japanese / chinese / latin / symbol / other)
    // Returns true when the key was handled (and should be consumed).
    private func handleShortcut(_ key: String) -> Bool {
        // While the Settings modal is open, only theme (t) and wallpaper (0–4)
        // stay live so they can be previewed; other shortcuts are swallowed so
        // they don't silently mutate filters behind the blur. ESC is handled
        // separately in the key cascade.
        if vm.showSettings && !["t", "0", "1", "2", "3", "4"].contains(key) {
            return false
        }
        switch key {
        case "0":
            vm.wallpaper = ""
            return true
        case "1", "2", "3", "4":
            let index = Int(key)! - 1
            if index < AppViewModel.wallpapers.count {
                vm.wallpaper = AppViewModel.wallpapers[index]
            }
            return true
        case "t":
            vm.isLightMode.toggle()
            return true
        case "w":
            vm.cycleWeightFilter()
            return true
        case "f":
            vm.favoritesOnly.toggle()
            return true
        case "m":
            vm.memoOnly.toggle()
            return true
        case "k", "j", "l", "o":
            // Chinese/Symbol are folded into Other, so only the filterable
            // buckets have live shortcuts.
            if let category = ScriptCategory.filterable.first(where: { $0.shortcutKey == key }) {
                vm.toggleScript(category)
            }
            return true
        case "[":
            withAnimation(.easeInOut(duration: 0.22)) { leftPanelOpen.toggle() }
            return true
        case "]":
            withAnimation(.easeInOut(duration: 0.22)) { rightPanelOpen.toggle() }
            return true
        case "u":
            vm.cycleMutedFilter()
            return true
        case "i":
            vm.mutedOnly.toggle()
            return true
        default:
            return false
        }
    }

    // ⌘ + arrows: ↑/↓ adjust Font Size, →/← adjust Columns (→ increases).
    // Returns true when handled.
    private func handleCommandArrow(_ keyCode: Int) -> Bool {
        if vm.showSettings { return false }
        switch keyCode {
        case 126: adjustFontSize(+1); return true   // up
        case 125: adjustFontSize(-1); return true   // down
        case 124: adjustColumns(+1); return true    // right
        case 123: adjustColumns(-1); return true    // left
        default: return false
        }
    }

    private func adjustFontSize(_ delta: Double) {
        let range = AppViewModel.previewOffsetRange
        vm.previewSizeOffset = min(max(range.lowerBound, vm.previewSizeOffset + delta), range.upperBound)
    }

    private func adjustColumns(_ delta: Int) {
        let maxC = max(1, vm.maxColumns)
        vm.columnCount = min(max(1, vm.columnCount + delta), maxC)
    }

    // ESC cascade step: close the detail overlay if it's open. Returns true when
    // it actually closed something (so the key is consumed for that press).
    private func closeDetailIfOpen() -> Bool {
        guard vm.selectedFamily != nil else { return false }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            vm.selectedFamily = nil
        }
        return true
    }

    // ESC cascade step: close the Settings modal if it's open. Returns true
    // when it actually closed something.
    private func closeSettingsIfOpen() -> Bool {
        guard vm.showSettings else { return false }
        // A Clear All confirmation is open: let ESC fall through so it dismisses
        // only the dialog, keeping Settings open.
        if vm.isPresentingConfirm { return false }
        withAnimation(.easeOut(duration: 0.18)) { vm.showSettings = false }
        return true
    }

    // ⌘, toggles the Settings modal (the standard macOS settings shortcut).
    private func toggleSettings() -> Bool {
        withAnimation(.easeOut(duration: 0.18)) { vm.showSettings.toggle() }
        return true
    }
}

// App-wide key monitor.
//
// ESC runs a one-step-per-press cascade (independent of text-editing state):
//   1. a text field is being edited → blur it
//   2. the Settings modal is open    → close it (via onCloseSettings)
//   3. the detail overlay is open    → close it (via onCloseDetail)
//   4. the window is fullscreen      → exit fullscreen
//
// Plain letter/number keys (no ⌘/⌥/⌃) are routed to `onKey`, but only when no
// text field is being edited so search / memo / preview keep normal typing.
// Both callbacks return true to consume the event.
private struct GlobalShortcutHandler: NSViewRepresentable {
    let onKey: (String) -> Bool
    let onCloseDetail: () -> Bool
    let onCloseSettings: () -> Bool
    let onToggleSettings: () -> Bool
    let onCommandArrow: (Int) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.onCloseDetail = onCloseDetail
        context.coordinator.onCloseSettings = onCloseSettings
        context.coordinator.onToggleSettings = onToggleSettings
        context.coordinator.onCommandArrow = onCommandArrow
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onKey: onKey,
                    onCloseDetail: onCloseDetail,
                    onCloseSettings: onCloseSettings,
                    onToggleSettings: onToggleSettings,
                    onCommandArrow: onCommandArrow)
    }

    final class Coordinator {
        var onKey: (String) -> Bool
        var onCloseDetail: () -> Bool
        var onCloseSettings: () -> Bool
        var onToggleSettings: () -> Bool
        var onCommandArrow: (Int) -> Bool
        private var monitor: Any?

        init(onKey: @escaping (String) -> Bool,
             onCloseDetail: @escaping () -> Bool,
             onCloseSettings: @escaping () -> Bool,
             onToggleSettings: @escaping () -> Bool,
             onCommandArrow: @escaping (Int) -> Bool) {
            self.onKey = onKey
            self.onCloseDetail = onCloseDetail
            self.onCloseSettings = onCloseSettings
            self.onToggleSettings = onToggleSettings
            self.onCommandArrow = onCommandArrow
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }

                // ESC cascade.
                if event.keyCode == 53 {
                    if let window = event.window, window.firstResponder is NSText {
                        window.makeFirstResponder(nil)
                        return nil
                    }
                    if self.onCloseSettings() { return nil }
                    if self.onCloseDetail() { return nil }
                    if let window = event.window, window.styleMask.contains(.fullScreen) {
                        window.toggleFullScreen(nil)
                        return nil
                    }
                    return event
                }

                let mods = event.modifierFlags.intersection([.command, .option, .control])

                // ⌘ + key combos.
                if mods == [.command] {
                    // ⌘, toggles Settings (standard macOS shortcut). Works even
                    // while editing text, like the system Settings shortcut.
                    if event.charactersIgnoringModifiers == "," {
                        if self.onToggleSettings() { return nil }
                    }
                    // ⌘ + arrows: Font Size (↑/↓) and Columns (←/→). Skipped
                    // while editing text so ⌘-arrow keeps its navigation meaning.
                    if event.window?.firstResponder is NSText { return event }
                    if self.onCommandArrow(Int(event.keyCode)) { return nil }
                    return event
                }

                // Plain letter/number shortcuts. While a Korean input source is
                // active, a letter key reports its Hangul jamo, so map it back to
                // the Latin letter on the same physical key first.
                if event.window?.firstResponder is NSText { return event }
                if !mods.isEmpty { return event }
                guard let raw = event.charactersIgnoringModifiers?.lowercased() else { return event }
                let key = Self.latinForHangul(raw)
                guard self.onKey(key) else { return event }
                return nil
            }
        }

        // Korean 2-set (두벌식) layout: each key produces a jamo. Map those jamo
        // back to the Latin letter on the same physical key so single-key
        // shortcuts (t, w, f, m, k, j, c, l, s, o, …) still fire while the input
        // source is Korean.
        private static let hangulToLatin: [Character: String] = [
            "ㅂ": "q", "ㅃ": "q", "ㅈ": "w", "ㅉ": "w", "ㄷ": "e", "ㄸ": "e",
            "ㄱ": "r", "ㄲ": "r", "ㅅ": "t", "ㅆ": "t", "ㅛ": "y", "ㅕ": "u",
            "ㅑ": "i", "ㅐ": "o", "ㅒ": "o", "ㅔ": "p", "ㅖ": "p",
            "ㅁ": "a", "ㄴ": "s", "ㅇ": "d", "ㄹ": "f", "ㅎ": "g", "ㅗ": "h",
            "ㅓ": "j", "ㅏ": "k", "ㅣ": "l",
            "ㅋ": "z", "ㅌ": "x", "ㅊ": "c", "ㅍ": "v", "ㅠ": "b", "ㅜ": "n", "ㅡ": "m"
        ]

        private static func latinForHangul(_ s: String) -> String {
            guard s.count == 1, let ch = s.first, let latin = hangulToLatin[ch] else { return s }
            return latin
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { uninstall() }
    }
}

// Floating rounded-square button that collapses ("−") or expands ("+") a side
// panel. Uses the left panel's button rounding while open; when collapsed and
// docked in a window corner it drops to a tiny radius so its corner nests
// concentrically inside the window's rounded corner.
private struct PanelToggleButton: View {
    let open: Bool
    let action: () -> Void
    @State private var hovering = false

    // Open: same rounding as the left-panel filter buttons. Collapsed: small,
    // for concentricity with the window corner.
    private var radius: CGFloat { open ? Theme.pillRadius + 2 : 8 }

    var body: some View {
        Button(action: action) {
            Image(systemName: open ? "minus" : "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hovering ? Theme.accent : Color.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(hovering ? Theme.surfaceFillHover : Theme.surfaceFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(open ? "Collapse panel" : "Expand panel")
    }
}

private struct InitialFocusClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            view.window?.makeFirstResponder(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Window-wide wallpaper drawn as the top layer over the whole app at low
// opacity. Sits at the root, so filling the window needs no clipping or
// per-panel safe-area handling, and it never affects layout.
struct WallpaperOverlay: View {
    let name: String
    @Environment(\.colorScheme) private var colorScheme

    // Per-wallpaper blend mode for DARK mode. Unknown / "" falls back to
    // .normal, preserving the no-wallpaper path.
    private static let darkBlendModes: [String: BlendMode] = [
        "Wallpaper01": .normal,
        "Wallpaper02": .plusLighter,
        "Wallpaper03": .screen,
        "Wallpaper04": .softLight
    ]

    // Per-wallpaper blend mode for LIGHT mode. Defaults to .multiply for any
    // wallpaper not listed (additive/lighten modes blow out against a bright
    // background, so .multiply is the sane default).
    private static let lightBlendModes: [String: BlendMode] = [
        "Wallpaper01": .darken,
        "Wallpaper02": .multiply,
        "Wallpaper03": .overlay,
        "Wallpaper04": .multiply
    ]

    // Per-mode opacity. Dark stays at 0.24 (subtle texture over the dark base);
    // light goes fully opaque because the L_ assets are designed to read at
    // full strength under .multiply.
    private static let darkOpacity: Double = 0.24
    private static let lightOpacity: Double = 0.5

    private var resolvedImageName: String {
        // "" stays empty so the no-wallpaper branch below short-circuits.
        guard !name.isEmpty else { return "" }
        return colorScheme == .light ? "L_\(name)" : name
    }

    // All wallpapers ship as .webp now (≈25 KB – 1.5 MB vs 1–13 MB PNG).
    // NSImage decodes webp natively since macOS 11 via ImageIO.
    private static let imageExtension = "webp"

    private var resolvedBlendMode: BlendMode {
        if colorScheme == .light {
            return Self.lightBlendModes[name] ?? .multiply
        }
        return Self.darkBlendModes[name] ?? .normal
    }

    private var resolvedOpacity: Double {
        colorScheme == .light ? Self.lightOpacity : Self.darkOpacity
    }

    var body: some View {
        let imageName = resolvedImageName
        if !imageName.isEmpty, let img = Self.image(named: imageName, ext: Self.imageExtension) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(img.size.width / img.size.height, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .compositingGroup()
                .blendMode(resolvedBlendMode)
                .opacity(resolvedOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private static var imageCache: [String: NSImage] = [:]

    private static func image(named name: String, ext: String) -> NSImage? {
        // Cache key includes the extension so dark .png and light .webp under
        // the same logical name (e.g. Wallpaper01 vs L_Wallpaper01) never
        // collide if the resolver ever drops the L_ prefix.
        let key = "\(name).\(ext)"
        if let cached = imageCache[key] { return cached }
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Wallpapers"
        ),
              let image = NSImage(contentsOf: url)
        else { return nil }
        imageCache[key] = image
        return image
    }
}
