import AppKit
import Foundation

/// Watches the clipboard for a single glyph that came from somewhere else.
///
/// There is no clipboard-changed notification on macOS, so this polls — but
/// what it polls is `NSPasteboard.changeCount`, one integer, and it only reads
/// the actual string when that integer has moved. It runs while the app is
/// frontmost and stops when it isn't: a clipboard change the user makes in
/// another app is still caught, because coming back here makes this app active
/// again, which refreshes before the window is even drawn.
@MainActor
final class ClipboardWatcher: ObservableObject {
    /// A single glyph on the clipboard that this app did not put there, or nil
    /// when the clipboard holds anything else: several characters, whitespace
    /// alone, no text at all, or a glyph this app just copied.
    ///
    /// Our own copies are excluded deliberately. A glyph copied from a font's
    /// detail card is already kept — offering to keep it again, in the plain
    /// system face this time, would be offering a worse copy of what the user
    /// just saved.
    @Published private(set) var externalGlyph: String? = nil

    // The clipboard state already examined, the state this app itself last
    // wrote, and the state whose glyph has already been taken into the list.
    // `clearContents()` returns the new count and reading never moves it, so
    // these three are enough to tell apart every case that matters.
    private var seenChangeCount = -1
    private var ownChangeCount = -1
    private var keptChangeCount = -1

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private static let pollInterval: TimeInterval = 1.0

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.start() }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        ]
        start()
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Call straight after this app writes to the clipboard. What it wrote is
    /// then not offered back as something to keep.
    func noteOwnCopy() {
        let count = NSPasteboard.general.changeCount
        ownChangeCount = count
        seenChangeCount = count
        externalGlyph = nil
    }

    /// Call when the offered glyph has been taken into the list.
    ///
    /// What is spent is this CLIPBOARD STATE, not the glyph. The clipboard
    /// still holds it, but there is nothing left to offer for it, so the slot
    /// goes away rather than sitting there greyed out next to the card it just
    /// produced. Copy the same glyph again later and the clipboard moves on to
    /// a new state, which IS worth answering — with the spent slot, because by
    /// then the glyph really is already kept.
    func noteKept() {
        keptChangeCount = NSPasteboard.general.changeCount
        externalGlyph = nil
    }

    /// A string counts as one glyph when it is a single grapheme cluster, which
    /// is what the glyph grid treats as one tile too. Scalar count is the wrong
    /// measure: a flag is two scalars and a family emoji is seven, and both are
    /// one glyph on screen.
    static func singleGlyph(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.count == 1
        else { return nil }
        return trimmed
    }

    private func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != seenChangeCount else { return }
        seenChangeCount = count
        guard count != ownChangeCount, count != keptChangeCount else {
            externalGlyph = nil
            return
        }
        externalGlyph = Self.singleGlyph(pasteboard.string(forType: .string))
    }
}
