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
        .overlay { WallpaperOverlay(name: vm.wallpaper).opacity(0.24) }
        .background(Theme.panelBackground.ignoresSafeArea())
        .background(InitialFocusClearer())
        .environmentObject(vm)
        .environmentObject(favorites)
        .environmentObject(memos)
        .preferredColorScheme(.dark)
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

    var body: some View {
        if !name.isEmpty,
           let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Wallpapers"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(img.size.width / img.size.height, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }
}
