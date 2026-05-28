import SwiftUI

struct RootView: View {
    @StateObject private var vm = AppViewModel()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var memos = MemoStore()

    var body: some View {
        HStack(spacing: 0) {
            LeftPanel()
            PanelVDivider()
            CenterPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PanelVDivider()
            RightPanel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panelBackground.ignoresSafeArea())
        .environmentObject(vm)
        .environmentObject(favorites)
        .environmentObject(memos)
        .preferredColorScheme(.dark)
    }
}
