import SwiftUI
import AppKit

struct RootView: View {
    @StateObject private var vm = AppViewModel()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var memos = MemoStore()

    @State private var leftWidth: CGFloat = Theme.panelDefaultWidth
    @State private var rightWidth: CGFloat = Theme.panelDefaultWidth
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
        // Wallpapers are a dark-mode-only feature. Light mode shows none, but
        // the dark-mode selection (vm.wallpaper) is preserved for when you return.
        .overlay { WallpaperOverlay(name: vm.isLightMode ? "" : vm.wallpaper).opacity(0.24) }
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

    // Per-wallpaper blend mode over the rest of the app. Unknown / "" falls back
    // to .normal, preserving the no-wallpaper path.
    private static let blendModes: [String: BlendMode] = [
        "Wallpaper01": .normal,
        "Wallpaper02": .plusLighter,
        "Wallpaper03": .screen,
        "Wallpaper04": .softLight
    ]

    var body: some View {
        if !name.isEmpty, let img = Self.image(named: name) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(img.size.width / img.size.height, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .compositingGroup()
                .blendMode(Self.blendModes[name] ?? .normal)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private static var imageCache: [String: NSImage] = [:]

    private static func image(named name: String) -> NSImage? {
        if let cached = imageCache[name] { return cached }
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Wallpapers"
        ),
              let image = NSImage(contentsOf: url)
        else { return nil }
        imageCache[name] = image
        return image
    }
}
