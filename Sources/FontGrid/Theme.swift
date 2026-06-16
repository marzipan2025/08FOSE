import SwiftUI
import AppKit

enum Theme {
    // App
    static let appVersion = "0.5.8"

    // Panels
    static let panelDefaultWidth: CGFloat = 240
    static let panelMinWidth: CGFloat = 240
    static let panelMaxWidth: CGFloat = 440
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
        // The constant encodes the fixed zones — header (~29) + name↔sample gap
        // + bottom slack/padding (~11). The +49 (was +58) halves the built-in
        // ~18px name↔sample gap to ~9px. The preview is bottom-anchored, so this
        // tightens only the middle gap, not the bottom margin. Floor lowered in
        // step so small sizes get the same halved gap.
        max(74, CGFloat(fontSize) * 1.2 + 49)
    }

    // Colors — backgrounds & neutrals adapt to appearance. The key accent is
    // gold (#D9A633) in dark mode and hot pink in light mode.
    static let accent = adaptive(
        dark: NSColor(red: 217/255, green: 166/255, blue: 51/255, alpha: 1),    // #D9A633 gold
        light: NSColor(red: 255/255, green: 77/255, blue: 0/255, alpha: 1)      // #FF4D00 vivid orange
    )
    static let weightBadge = Color(red: 84/255, green: 97/255, blue: 111/255)
    // Blue-grey accent (memo text & memo dot). Light mode keeps the dark-mode
    // hue but bumps saturation +80% (×1.8) and brightness +40% (×1.4) so it
    // reads clearly on the white surface.
    static let memoAccent = adaptive(
        dark: NSColor(red: 82/255, green: 112/255, blue: 143/255, alpha: 1),        // #52708F
        light: NSColor(hue: 0.585, saturation: 0.767, brightness: 0.785, alpha: 1)
    )
    // Side panels share the cell color; the center panel sits a touch darker
    // than the cells so the cells lift off the background.
    static let cellSurface = adaptive(dark: NSColor(white: 0.15, alpha: 1),
                                      light: NSColor(white: 1.0, alpha: 1))
    static let sidebarBackground = adaptive(dark: NSColor(white: 0.15, alpha: 1),
                                            light: NSColor(white: 0.98, alpha: 1))
    static let panelBackground = adaptive(dark: NSColor(white: 0.11, alpha: 1),
                                          light: NSColor(white: 0.92, alpha: 1))

    // Adaptive neutrals. Dark mode = white overlays on a dark base; light mode
    // flips to black overlays on a light base so contrast holds either way.
    static let divider = adaptive(dark: NSColor(white: 1, alpha: 0.08),
                                  light: NSColor(white: 0, alpha: 0.08))
    static let border = adaptive(dark: NSColor(white: 1, alpha: 0.10),
                                 light: NSColor(white: 0, alpha: 0.12))
    static let borderHover = adaptive(dark: NSColor(white: 1, alpha: 0.35),
                                      light: NSColor(white: 0, alpha: 0.30))
    static let surfaceFill = adaptive(dark: NSColor(white: 1, alpha: 0.06),
                                      light: NSColor(white: 0, alpha: 0.04))
    // Hover state for buttons — a touch denser than surfaceFill.
    static let surfaceFillHover = adaptive(dark: NSColor(white: 1, alpha: 0.12),
                                           light: NSColor(white: 0, alpha: 0.07))
    // Favorite row hover fill — brighter than the sidebar so the row lifts.
    static let rowHoverFill = adaptive(dark: NSColor(white: 0.22, alpha: 1),
                                       light: NSColor(white: 1.0, alpha: 1))
    static let memoSurface = adaptive(dark: NSColor(white: 1, alpha: 0.05),
                                      light: NSColor(white: 0, alpha: 0.04))

    /// A color that resolves differently in light vs dark appearance. Driven by
    /// the window's effective appearance, which `preferredColorScheme` sets.
    static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
