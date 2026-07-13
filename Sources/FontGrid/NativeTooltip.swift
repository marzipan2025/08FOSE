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

extension View {
    /// Attaches a stable native tooltip as a hit-transparent overlay. Prefer
    /// this over `.help()` on views that re-render while hovered.
    func nativeTooltip(_ text: String) -> some View {
        overlay(NativeTooltip(text: text).allowsHitTesting(false))
    }
}
