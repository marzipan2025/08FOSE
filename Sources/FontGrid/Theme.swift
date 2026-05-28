import SwiftUI
import AppKit

enum Theme {
    // Panels
    static let leftPanelWidth: CGFloat = 220
    static let rightPanelWidth: CGFloat = 260
    static let panelHPadding: CGFloat = 16
    static let panelVPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 10

    // Grid
    static let gridPadding: CGFloat = 16
    static let gridSpacing: CGFloat = 6
    static let minCellWidth: CGFloat = 120

    // Type sizes
    static let sectionHeaderSize: CGFloat = 10
    static let smallSize: CGFloat = 11
    static let bodySize: CGFloat = 12

    // Radii (kept until we decide on square design)
    static let surfaceRadius: CGFloat = 8
    static let cardRadius: CGFloat = 10
    static let pillRadius: CGFloat = 6

    static func cellHeight(fontSize: Double) -> CGFloat {
        max(90, CGFloat(fontSize) + 62)
    }

    // Colors
    static let accent = Color(red: 217/255, green: 166/255, blue: 51/255)
    static let weightBadge = Color(red: 84/255, green: 97/255, blue: 111/255)
    static let memoAccent = Color(red: 82/255, green: 112/255, blue: 143/255)   // #52708F
    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .underPageBackgroundColor)
    static let cellSurface = Color(nsColor: .controlBackgroundColor).opacity(0.4)
    static let divider = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.10)
    static let borderHover = Color.white.opacity(0.35)
    static let surfaceFill = Color.white.opacity(0.06)
}
