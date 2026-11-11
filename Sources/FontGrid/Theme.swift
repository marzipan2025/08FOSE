import SwiftUI
import AppKit

enum Theme {
    // App
    static let appVersion = "0.8.28"

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

    // The COPIED flash after a glyph is copied, in and out. Taken to 60% of the
    // timings this started at (0.15 / 0.8 / 0.3): the flash confirms something
    // the user already knows they did, so it only has to register — lingering
    // past that reads as the app being slow to catch up. Shared so the glyph
    // grid and the saved-glyph cards cannot drift apart.
    static let copyFlashIn: Double = 0.09
    static let copyFlashHold: Double = 0.48
    static let copyFlashOut: Double = 0.18
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

    // Colors — backgrounds & neutrals adapt to appearance.
    //
    // The accent comes in pairs, and each wallpaper may bring its own pair (see
    // AccentColors below; views read it from the environment, never from here).
    // `fill` is for dots, chip washes and strokes; `text` is the same hue
    // darkened until it holds WCAG AA 4.5:1 for small text, because the vivid
    // fill rarely does: #FF4D00 on white is only 3.3:1, #AD3200 is 6.5:1 on a
    // cell and 4.6:1 on a hovered chip. Dark mode's gold already reads at 6.8:1,
    // so its pair is the same colour twice.
    fileprivate static let accentDark = rgb(0xD9A633)       // gold
    fileprivate static let accentLight = rgb(0xFF4D00)      // vivid orange
    fileprivate static let accentTextLight = rgb(0xAD3200)  // orange, darkened for text

    /// Per-wallpaper accent pairs, keyed by wallpaper name. A wallpaper that
    /// isn't listed (and "" for none) keeps the standard orange / gold.
    /// To add one: pick the fill, then darken the same hue until the text
    /// colour clears 4.5:1 on white and on a 24% wash of the fill.
    fileprivate static let lightAccentOverrides: [String: AccentColors.Pair] = [
        // Blue against the cool cast the exclusion blend gives this one.
        // #1DA1FF is 2.8:1 on white; text at lightness 0.39 for about 4:1 on
        // a selected chip (4.9:1 on a cell, 3.7:1 on a hovered chip).
        "Wallpaper01": .init(fill: rgb(0x1DA1FF), text: rgb(0x0074C7)),
        // Slate ink with a cobalt fill, both given: #303C4C text (11.2:1 on
        // white) and #607CEF for dots, slider tracks and chip washes
        // (3.7:1 on white, enough for non-text marks).
        "Wallpaper02": .init(fill: rgb(0x607CEF), text: rgb(0x303C4C)),
        // Green to sit with the green art. #4AC50D is 2.3:1 on white, so the
        // text colour is the same hue at lightness 0.275, aimed at about 4:1
        // rather than the full 4.5:1 to keep it green, not olive: 4.0:1 on a
        // selected chip, 4.8:1 on a cell, 3.8:1 on a hovered chip.
        "Wallpaper04": .init(fill: rgb(0x4AC50D), text: rgb(0x318409))
    ]
    fileprivate static let darkAccentOverrides: [String: AccentColors.Pair] = [
        // Hot pink. The vivid #FF3EA5 fills dots, slider tracks and chip
        // washes; words use the lighter CSS hotpink #FF69B4, 5.7:1 on a cell
        // and 4.5:1 on a selected chip (the fill alone is 3.9:1 there).
        "Wallpaper01": .init(fill: rgb(0xFF3EA5), text: rgb(0xFF69B4)),
        // Leaf green: 8.3:1 on a cell, 4.8:1 on a hovered chip, one colour.
        "Wallpaper03": .init(fill: rgb(0x77D64E), text: rgb(0x77D64E)),
        // Vivid yellow. On the dark surfaces it already reads at 11.5:1 on a
        // cell and 5.9:1 on a hovered chip, so like the gold it needs no
        // separate text colour.
        "Wallpaper04": .init(fill: rgb(0xFFE100), text: rgb(0xFFE100))
    ]

    /// The accent pair for the wallpapers chosen in each mode. Both are taken
    /// so the colour flips correctly with the appearance, the same way the
    /// wallpaper itself does.
    static func accentColors(lightWallpaper: String, darkWallpaper: String) -> AccentColors {
        AccentColors(
            light: lightAccentOverrides[lightWallpaper] ?? .init(fill: accentLight, text: accentTextLight),
            dark: darkAccentOverrides[darkWallpaper] ?? .init(fill: accentDark, text: accentDark)
        )
    }

    fileprivate static func rgb(_ hex: Int) -> NSColor {
        NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    // Family name on each grid cell. These used to be accent, which put the
    // accent on every cell and left it nothing to point at; the accent now
    // marks only what is chosen or pinned. A grey rather than `.secondary`,
    // which is 50% black (about 4:1 on white, under AA): this is 5.7:1 on a
    // light cell and 5.4:1 on a dark one.
    static let cellName = adaptive(dark: NSColor(white: 1, alpha: 0.55),
                                   light: NSColor(white: 0, alpha: 0.60))

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
    // Halfway between the old fill (0.06 / 0.04) and the bare background — an
    // overlay at half the alpha lands exactly midway on whatever is behind it.
    static let surfaceFill = adaptive(dark: NSColor(white: 1, alpha: 0.03),
                                      light: NSColor(white: 0, alpha: 0.02))
    // Hover state for buttons — a touch denser than surfaceFill.
    static let surfaceFillHover = adaptive(dark: NSColor(white: 1, alpha: 0.12),
                                           light: NSColor(white: 0, alpha: 0.07))
    // Pin row hover fill — brighter than the sidebar so the row lifts.
    // One step fainter than the stats line's own `.tertiary`, for the Face
    // segments appended to it. Deliberately a small step: the bar floats over
    // the wallpaper, and SwiftUI's `.quaternary` all but vanishes on the
    // lighter ones.
    static let statsSubtle = adaptive(dark: NSColor(white: 1, alpha: 0.18),
                                      light: NSColor(white: 0, alpha: 0.22))

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

/// The accent the current wallpapers call for, handed down from RootView
/// through the environment so every view follows a wallpaper change.
struct AccentColors {
    struct Pair {
        let fill: NSColor
        let text: NSColor
    }

    let light: Pair
    let dark: Pair

    /// Dots, chip washes, strokes.
    let fill: Color
    /// Words and icons: the fill darkened to hold 4.5:1.
    let text: Color

    init(light: Pair, dark: Pair) {
        self.light = light
        self.dark = dark
        self.fill = Theme.adaptive(dark: dark.fill, light: light.fill)
        self.text = Theme.adaptive(dark: dark.text, light: light.text)
    }

    /// The fill as a concrete NSColor, for Core Graphics drawing inside a
    /// Canvas — dynamic colours there resolve against the context's appearance
    /// rather than the view's, so the scheme has to be passed in explicitly.
    func ink(_ scheme: ColorScheme) -> NSColor {
        scheme == .light ? light.fill : dark.fill
    }

    static let standard = Theme.accentColors(lightWallpaper: "", darkWallpaper: "")
}

private struct AccentColorsKey: EnvironmentKey {
    static let defaultValue = AccentColors.standard
}

extension EnvironmentValues {
    var accentColors: AccentColors {
        get { self[AccentColorsKey.self] }
        set { self[AccentColorsKey.self] = newValue }
    }
}
