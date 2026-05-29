import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var originalButtonOrigins: [ObjectIdentifier: [NSWindow.ButtonType: CGPoint]] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        applyWindowStyle()
        adjustTrafficLights()

        let restyleEvents: [NSNotification.Name] = [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification
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
        applyWindowStyle()
    }

    @objc private func applyWindowStyle() {
        DispatchQueue.main.async {
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
    }

    @objc private func adjustTrafficLights() {
        DispatchQueue.main.async {
            let offsetX: CGFloat = 6
            let offsetY: CGFloat = -6   // AppKit Y is up; negative = visually down
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
