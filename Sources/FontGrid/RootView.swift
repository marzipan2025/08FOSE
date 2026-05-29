import SwiftUI

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
        .background(Theme.panelBackground.ignoresSafeArea())
        .environmentObject(vm)
        .environmentObject(favorites)
        .environmentObject(memos)
        .preferredColorScheme(.dark)
    }
}
