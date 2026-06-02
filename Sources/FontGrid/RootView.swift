import SwiftUI
import AppKit

struct RootView: View {
    @StateObject private var vm = AppViewModel()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var memos = MemoStore()

    @State private var leftWidth: CGFloat = Theme.panelDefaultWidth
    @State private var rightWidth: CGFloat = 256
    @State private var leftDragStart: CGFloat? = nil
    @State private var rightDragStart: CGFloat? = nil

    var body: some View {
        HStack(spacing: 0) {
            LeftPanel()
                .frame(width: leftWidth)
            ResizableVDivider(
                width: $leftWidth,
                dragStartWidth: $leftDragStart,
                minWidth: Theme.panelMinWidth,
                maxWidth: Theme.panelMaxWidth,
                edge: .left
            )
            CenterPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ResizableVDivider(
                width: $rightWidth,
                dragStartWidth: $rightDragStart,
                minWidth: Theme.panelMinWidth,
                maxWidth: Theme.panelMaxWidth,
                edge: .right
            )
            RightPanel()
                .frame(width: rightWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Wallpaper overlay: same mechanism in both dark and light mode, driven
        // by vm.wallpaper. Image, blend mode and opacity are all picked inside
        // WallpaperOverlay based on the current colorScheme.
        .overlay { WallpaperOverlay(name: vm.wallpaper) }
        .background(Theme.panelBackground.ignoresSafeArea())
        .background(InitialFocusClearer())
        .environmentObject(vm)
        .environmentObject(favorites)
        .environmentObject(memos)
        .preferredColorScheme(vm.isLightMode ? .light : .dark)
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
        "Wallpaper01": .multiply,
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
