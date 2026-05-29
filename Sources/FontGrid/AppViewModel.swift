import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    let library: FontLibrary

    @Published var searchQuery: String = ""
    @Published var minWeightCount: Int = 1
    @Published var favoritesOnly: Bool = false
    @Published var memoOnly: Bool = false
    @Published var koreanOnly: Bool = false
    @Published var englishOnly: Bool = false

    @Published var columnCount: Int = 4
    @Published var maxColumns: Int = 6
    @Published var previewSizeOffset: Double = 0

    static let gridBaseFontSize: Double = 28
    static let weightRowBaseFontSize: Double = 40
    static let previewOffsetRange: ClosedRange<Double> = -14...14

    var gridFontSize: Double { Self.gridBaseFontSize + previewSizeOffset }
    var weightRowFontSize: Double { Self.weightRowBaseFontSize + previewSizeOffset }

    @Published var selectedFamily: FontFamily? = nil

    init() {
        self.library = FontLibrary()
    }
}
