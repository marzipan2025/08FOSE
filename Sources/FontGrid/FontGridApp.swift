import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var originalButtonOrigins: [ObjectIdentifier: [NSWindow.ButtonType: CGPoint]] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make .help() tooltips (memo alt-text on cells) appear near-instantly.
        // NSInitialToolTipDelay (the documented defaults key) is not honored by
        // the .help()/NSView tooltip path on modern macOS, so go through the
        // private NSToolTipManager. 0.05s reads as immediate without flashing on
        // fast pointer passes.
        tuneTooltipDelay(0.05)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        applyAppIcon()
        applyWindowStyle()
        adjustTrafficLights()

        let restyleEvents: [NSNotification.Name] = [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResizeNotification
        ]
        for name in restyleEvents {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowEvent),
                name: name,
                object: nil
            )
        }
    }

    @objc private func handleWindowEvent() {
        // Window style is set once at launch; only traffic-light positions need
        // to be re-applied synchronously to avoid a one-frame flash.
        adjustTrafficLightsNow()
    }

    // Set the Dock icon at launch.
    //
    // - Packaged .app: load the rounded PNG generated beside the .icns so the
    //   running Dock tile has the same silhouette Finder shows.
    // - Dev (`swift run`): there is no app bundle, so fall back to the PNG
    //   carried in the SwiftPM resource bundle (Bundle.module). Checked second
    //   so the packaged path never evaluates Bundle.module.
    private func applyAppIcon() {
        // Packaged .app already shows the rounded .icns via Info.plist; still set
        // it on the running tile to match.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
            return
        }
        // Dev (`swift run`): no app bundle, so the full-bleed master PNG would
        // show as a hard square. Round it to the macOS squircle at runtime so
        // the Dock tile matches the packaged app.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = Self.roundedIcon(image) ?? image
        }
    }

    /// Mask a full-bleed square icon into the macOS rounded-rect silhouette.
    /// Mirrors Tools/make-icon.swift (radius 230 on a 1024 canvas).
    private static func roundedIcon(_ image: NSImage) -> NSImage? {
        let side: CGFloat = 1024
        let radius = 230.0 / 1024.0 * side
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: Int(side), height: Int(side),
                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .high
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(cg, in: rect)
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: side, height: side))
    }

    @objc private func applyWindowStyle() {
        // Deferred on launch because the SwiftUI WindowGroup window may not
        // exist yet at applicationDidFinishLaunching time.
        DispatchQueue.main.async { self.applyWindowStyleNow() }
    }

    @objc private func adjustTrafficLights() {
        DispatchQueue.main.async { self.adjustTrafficLightsNow() }
    }

    private func applyWindowStyleNow() {
        for window in NSApp.windows {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            if let toolbar = window.toolbar {
                toolbar.showsBaselineSeparator = false
            }
        }
    }

    private func adjustTrafficLightsNow() {
        let offsetX: CGFloat = 10
        let offsetY: CGFloat = -10   // AppKit Y is up; negative = visually down
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for window in NSApp.windows {
            let id = ObjectIdentifier(window)
            var stored = self.originalButtonOrigins[id] ?? [:]
            for type in types {
                guard let btn = window.standardWindowButton(type) else { continue }
                if stored[type] == nil {
                    stored[type] = btn.frame.origin
                }
                guard let original = stored[type] else { continue }
                btn.setFrameOrigin(CGPoint(x: original.x + offsetX, y: original.y + offsetY))
            }
            self.originalButtonOrigins[id] = stored
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func tuneTooltipDelay(_ seconds: TimeInterval) {
        guard let cls = NSClassFromString("NSToolTipManager") as? NSObject.Type else { return }
        let sel = NSSelectorFromString("sharedToolTipManager")
        guard cls.responds(to: sel),
              let mgr = cls.perform(sel)?.takeUnretainedValue() as? NSObject else { return }
        mgr.setValue(seconds, forKey: "initialToolTipDelay")
    }
}

@main
struct FontGridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 860)
    }
}
