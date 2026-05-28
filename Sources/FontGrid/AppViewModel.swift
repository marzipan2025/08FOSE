import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    let library: FontLibrary

    @Published var searchQuery: String = ""
    @Published var minWeightCount: Int = 1
    @Published var favoritesOnly: Bool = false

    @Published var columnCount: Int = 4
    @Published var maxColumns: Int = 6
    @Published var fontSize: Double = 28

    @Published var selectedFamily: FontFamily? = nil

    init() {
        self.library = FontLibrary()
    }
}
