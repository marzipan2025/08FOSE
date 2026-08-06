import SwiftUI
import AppKit

/// A native AppKit tooltip backed by a stable NSView.
///
/// SwiftUI's `.help()` re-registers its tooltip rectangle on every body
/// evaluation. For views that re-render while the pointer sits still — hover
/// state changes, the weight-cycling font preview, pin-row shadows —
/// that re-registration restarts `NSToolTipManager`'s show sequence. Because
/// the rect is torn down and re-added while the pointer is *already inside*
/// it (with no fresh mouse-moved event), the manager never starts a new show
/// timer, so the tooltip intermittently never appears.
///
/// Setting `NSView.toolTip` on a representable view keeps the registration
/// stable across SwiftUI updates: the same NSView instance is reused and the
/// string is written only when it actually changes, so a stationary pointer
/// reliably triggers the tooltip.
struct NativeTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = resolved
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.toolTip != resolved {
            view.toolTip = resolved
        }
    }

    // An empty tooltip string still shows an (empty) tooltip on AppKit, so map
    // it to nil to mean "no tooltip".
    private var resolved: String? { text.isEmpty ? nil : text }
}

/// Set while a modal covers the app, to silence tooltips underneath it.
///
/// AppKit drives `NSView.toolTip` from tracking rects on the view itself, which
/// a SwiftUI overlay laid on top does not remove — so a modal's own backdrop
/// won't stop the views beneath from popping their tooltips as the pointer
/// crosses them. Blanking the string is what actually stops it.
private struct TooltipsSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tooltipsSuppressed: Bool {
        get { self[TooltipsSuppressedKey.self] }
        set { self[TooltipsSuppressedKey.self] = newValue }
    }
}

// Reads the environment on behalf of the `nativeTooltip` modifier, which as a
// plain View extension can't see it.
private struct TooltipHost: View {
    let text: String
    @Environment(\.tooltipsSuppressed) private var suppressed

    var body: some View {
        NativeTooltip(text: suppressed ? "" : text)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Attaches a stable native tooltip as a hit-transparent overlay. Prefer
    /// this over `.help()` on views that re-render while hovered.
    func nativeTooltip(_ text: String) -> some View {
        overlay(TooltipHost(text: text))
    }
}
