import SwiftUI
import AppKit

struct RootView: View {
    @StateObject private var vm = AppViewModel()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var memos = MemoStore()
    @StateObject private var samples = SampleStore()
    @StateObject private var muted = MutedStore()
    @StateObject private var inputSource = InputSourceManager()

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
        .environmentObject(inputSource)
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
        vm.closeDetail()
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
        "Wallpaper01": .softLight,
        "Wallpaper02": .plusLighter,
        "Wallpaper03": .screen,
        "Wallpaper04": .softLight
    ]

    // Per-wallpaper blend mode for LIGHT mode. Defaults to .multiply for any
    // wallpaper not listed (additive/lighten modes blow out against a bright
    // background, so .multiply is the sane default).
    private static let lightBlendModes: [String: BlendMode] = [
        "Wallpaper01": .exclusion,
        "Wallpaper02": .multiply,
        "Wallpaper03": .overlay,
        "Wallpaper04": .multiply
    ]

    // Per-mode opacity. Dark stays at 0.24 (subtle texture over the dark base);
    // light goes fully opaque because the L_ assets are designed to read at
    // full strength under .multiply.
    private static let darkOpacity: Double = 0.24
    private static let lightOpacity: Double = 0.5

    // Per-wallpaper light-mode opacity override. Wallpaper04 is a flat solid
    // color, so it needs more strength than the textured assets to read as
    // a vivid tint rather than a wash. Falls back to lightOpacity otherwise.
    private static let lightOpacityOverrides: [String: Double] = [
        "Wallpaper01": 0.18,
        "Wallpaper04": 0.8
    ]

    // Per-wallpaper dark-mode opacity override. Falls back to darkOpacity.
    private static let darkOpacityOverrides: [String: Double] = [
        "Wallpaper04": 0.75
    ]

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
        if colorScheme == .light {
            return Self.lightOpacityOverrides[name] ?? Self.lightOpacity
        }
        return Self.darkOpacityOverrides[name] ?? Self.darkOpacity
    }

    // Per-wallpaper light-mode color tint, multiplied onto the source image
    // before blending. Lets us warm/shift a flat solid color (e.g. nudge
    // Wallpaper04 toward a forsythia gold) without re-exporting the webp.
    // .white is a no-op, so unlisted wallpapers are unaffected.
    private static let lightTintOverrides: [String: Color] = [
        // 골드를 흰색에 50% 섞어 은은하게 곱한다 (gold ≈ 1.0,0.84,0.0)
        "Wallpaper01": Color(red: 1.0, green: 0.922, blue: 0.5),
        // 핑크를 흰색에 50% 섞어 은은하게 곱한다 (pink ≈ 1.0,0.753,0.796)
        "Wallpaper02": Color(red: 1.0, green: 0.877, blue: 0.898)
    ]

    private var resolvedTint: Color {
        guard colorScheme == .light else { return .white }
        return Self.lightTintOverrides[name] ?? .white
    }

    // One composited pass of the wallpaper image: a blend mode plus the opacity
    // it contributes at. Most wallpapers use a single layer (see resolvedLayers),
    // but a few stack passes to mix two blend modes of the same image.
    private struct BlendLayer {
        let mode: BlendMode
        let opacity: Double
    }

    // Per-wallpaper light-mode multi-layer overrides. When present, these stack
    // (bottom-to-top) instead of the single resolvedBlendMode/resolvedOpacity.
    // Wallpaper04 mixes a multiply base with a soft overlay highlight.
    private static let lightLayerOverrides: [String: [BlendLayer]] = [
        "Wallpaper04": [
            BlendLayer(mode: .multiply, opacity: 0.8),
            BlendLayer(mode: .softLight, opacity: 0.4)
        ]
    ]

    private var resolvedLayers: [BlendLayer] {
        if colorScheme == .light, let layers = Self.lightLayerOverrides[name] {
            return layers
        }
        return [BlendLayer(mode: resolvedBlendMode, opacity: resolvedOpacity)]
    }

    // A separate image composited on top of the base wallpaper layers, unlike
    // resolvedLayers which restacks the same wallpaper image. Used to lay a
    // shared "shine" highlight sheet over a wallpaper without baking it in.
    private struct Overlay {
        let imageName: String
        let mode: BlendMode
        let opacity: Double
    }

    // Per-wallpaper light-mode top overlay. Wallpaper04 gets an overlay-blended
    // shine sheet. Tint is intentionally not applied to the overlay.
    private static let lightOverlays: [String: Overlay] = [
        "Wallpaper04": Overlay(imageName: "shine", mode: .softLight, opacity: 0.2)
    ]

    private var resolvedOverlay: Overlay? {
        guard colorScheme == .light else { return nil }
        return Self.lightOverlays[name]
    }

    var body: some View {
        let imageName = resolvedImageName
        if !imageName.isEmpty, let img = Self.image(named: imageName, ext: Self.imageExtension) {
            ZStack {
                ForEach(Array(resolvedLayers.enumerated()), id: \.offset) { _, layer in
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(img.size.width / img.size.height, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .colorMultiply(resolvedTint)
                        .compositingGroup()
                        .blendMode(layer.mode)
                        .opacity(layer.opacity)
                }
                if let overlay = resolvedOverlay,
                   let shine = Self.overlayImage(named: overlay.imageName, ext: Self.imageExtension) {
                    Image(nsImage: shine)
                        .resizable()
                        .aspectRatio(shine.size.width / shine.size.height, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .compositingGroup()
                        .blendMode(overlay.mode)
                        .opacity(overlay.opacity)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    // Only one wallpaper is ever on screen, so cache a single decoded image
    // rather than an unbounded dictionary. Source art is ~3456×2234 (≈29 MB
    // decoded each); since the wallpaper is just a low-opacity, blended,
    // window-filling background, full resolution is wasted memory. We downscale
    // to maxWallpaperPixel on load, which drops each cached image to a few MB
    // and bounds total wallpaper memory to one image instead of growing every
    // time the wallpaper or theme changes.
    private static let maxWallpaperPixel = 2048
    private static var cachedKey: String?
    private static var cachedImage: NSImage?

    private static func image(named name: String, ext: String) -> NSImage? {
        // Key includes the extension to disambiguate variants under one logical
        // name (e.g. Wallpaper01 vs L_Wallpaper01).
        let key = "\(name).\(ext)"
        if key == cachedKey, let cached = cachedImage { return cached }
        guard let url = AppResources.bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Wallpapers"
        ),
              let raw = NSImage(contentsOf: url)
        else { return nil }
        let image = downscaled(raw, maxPixel: maxWallpaperPixel)
        cachedKey = key
        cachedImage = image
        return image
    }

    // Overlay images get their own single slot so they don't thrash the base
    // wallpaper cache (both are on screen at once); total stays bounded to two.
    private static var cachedOverlayKey: String?
    private static var cachedOverlayImage: NSImage?

    private static func overlayImage(named name: String, ext: String) -> NSImage? {
        let key = "\(name).\(ext)"
        if key == cachedOverlayKey, let cached = cachedOverlayImage { return cached }
        guard let url = AppResources.bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Wallpapers"
        ),
              let raw = NSImage(contentsOf: url)
        else { return nil }
        let image = downscaled(raw, maxPixel: maxWallpaperPixel)
        cachedOverlayKey = key
        cachedOverlayImage = image
        return image
    }

    /// Downscale so the longest side is at most `maxPixel`, preserving aspect.
    /// Renders into an explicit sRGB bitmap for a deterministic pixel size
    /// (NSImage.lockFocus would otherwise multiply by the screen backing scale).
    /// Images already within the limit are returned unchanged.
    private static func downscaled(_ image: NSImage, maxPixel: Int) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let longest = max(cg.width, cg.height)
        guard longest > maxPixel else { return image }
        let scale = Double(maxPixel) / Double(longest)
        let tw = max(1, Int((Double(cg.width) * scale).rounded()))
        let th = max(1, Int((Double(cg.height) * scale).rounded()))
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let out = ctx.makeImage() else { return image }
        return NSImage(cgImage: out, size: NSSize(width: tw, height: th))
    }
}
