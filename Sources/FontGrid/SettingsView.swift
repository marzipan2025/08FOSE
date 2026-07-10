import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Font sizes for the Settings screen — the app's base sizes scaled up 50%
// (rounded to whole points) since this is a focused, full-screen surface.
private enum SettingsType {
    static let title: CGFloat = 48
    static let sectionHeader: CGFloat = 18
    static let body: CGFloat = 14
    static let small: CGFloat = 14
}

// On-disk shape of an export. JSON keyed by font family name, so it imports
// cleanly on a Mac with a different font set — entries whose font is missing
// are simply kept and ignored until that font appears. `version` lets the
// format evolve without breaking older/newer files.
struct ExportData: Codable {
    var format: String = "08fose-export"
    var version: Int = 1
    var exportedAt: Date = Date()
    var favorites: [String]
    var memos: [String: String]
    // Added in later versions; optional so older backups still decode.
    var samples: [String: String]?
    var muted: [String]?
}

// Full-window Settings overlay: a blurred backdrop over the whole app with the
// settings laid directly on top (no separate card/window), confined to the
// center panel column. Driven by vm.showSettings. Dismissed by the close
// button (aligned to the content column's right edge) or ESC. Theme/wallpaper
// shortcuts stay live underneath so they can be previewed. Content is
// scrollable so future settings can be appended freely.
struct SettingsOverlay: View {
    // Width of the left / right panels (plus their 1pt dividers), so the
    // content and close button can be confined to the center panel column
    // while the blur stays full-window.
    let leftInset: CGFloat
    let rightInset: CGFloat

    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @EnvironmentObject var samples: SampleStore
    @EnvironmentObject var muted: MutedStore
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("previewText") private var previewText: String =
        "The quick brown fox jumps over lazy dog"
    private static let defaultPreviewText = "The quick brown fox jumps over lazy dog"

    // Equal gap from the top and right edges of the window for the close button.
    private static let closeInset: CGFloat = 40

    var body: some View {
        ZStack {
            // Blur everything behind. Light mode uses the brightest material
            // (.underPageBackground) to avoid a dark-grey cast; dark mode uses
            // .hudWindow which naturally sits darker.
            VisualEffectBlur(
                material: colorScheme == .dark ? .hudWindow : .underPageBackground,
                blendingMode: .withinWindow
            )
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { close() }

            // Everything below lives inside the center panel column only.
            centerRegion
                .padding(.leading, leftInset)
                .padding(.trailing, rightInset)
        }
        // Close button anchored to the top-right corner. ignoresSafeArea is
        // applied AFTER the overlay so the button (like the blur) ignores the
        // transparent title-bar inset too — otherwise the title bar would be
        // added to the top gap only, making it larger than the right gap.
        .overlay(alignment: .topTrailing) {
            CloseButton { close() }
                .padding(.top, Self.closeInset)
                .padding(.trailing, Self.closeInset)
        }
        .ignoresSafeArea()
    }

    private var centerRegion: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Settings")
                    .font(.system(size: SettingsType.title, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    // Optical alignment: large bold glyphs have more apparent
                    // left side-bearing, so nudge just the title left by 2pt
                    // to sit flush with the section labels below.
                    .offset(x: -2)
                dataSection
                    .padding(.bottom, 6)
                aboutSection
                    .padding(.bottom, 6)
                shortcutsSection
                licensesSection
                resetSection
            }
            // Fixed 480pt content column (shrinks if the center panel is
            // narrower), centered within the center region.
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 48)
        }
        .scrollContentBackground(.hidden)
        // Hide the scroll bar in the focused Settings modal for a cleaner look;
        // scrolling (wheel/trackpad) still works. Scoped to this ScrollView only.
        .scrollIndicators(.hidden)
    }

    // MARK: - Sections

    private var dataSection: some View {
        SettingsSection("Data") {
            VStack(spacing: 10) {
                dataRow(
                    title: "Favorites",
                    detail: "\(favorites.ordered.count) saved",
                    disabled: favorites.ordered.isEmpty
                ) { vm.confirmClearFavorites = true }
                .confirmationDialog(
                    "Remove all favorites?",
                    isPresented: $vm.confirmClearFavorites,
                    titleVisibility: .visible
                ) {
                    Button("Clear All Favorites", role: .destructive) { favorites.clearAll() }
                    Button("Cancel", role: .cancel) {}
                }

                dataRow(
                    title: "Memos",
                    detail: "\(memos.notes.count) saved",
                    disabled: memos.notes.isEmpty
                ) { vm.confirmClearMemos = true }
                .confirmationDialog(
                    "Remove all memos?",
                    isPresented: $vm.confirmClearMemos,
                    titleVisibility: .visible
                ) {
                    Button("Clear All Memos", role: .destructive) { memos.clearAll() }
                    Button("Cancel", role: .cancel) {}
                }

                dataRow(
                    title: "Specimens",
                    detail: "\(samples.samples.count) saved",
                    disabled: samples.samples.isEmpty
                ) { vm.confirmClearSamples = true }
                .confirmationDialog(
                    "Remove all custom specimens?",
                    isPresented: $vm.confirmClearSamples,
                    titleVisibility: .visible
                ) {
                    Button("Clear All Specimens", role: .destructive) { samples.clearAll() }
                    Button("Cancel", role: .cancel) {}
                }

                // Export / import favorites + memos + specimens (tags live inside memos).
                backupRow(
                    title: "Export",
                    detail: "Back up your current app data. Saved as a JSON file.",
                    button: "Export",
                    action: exportData
                )
                backupRow(
                    title: "Import",
                    detail: "Upload a backup JSON file to replace your current app data. This cannot be undone.",
                    button: "Import",
                    action: importData
                )
            }
        }
    }

    private func backupRow(
        title: String,
        detail: String,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: SettingsType.body))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: SettingsType.small))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            SettingsButton(label: button, action: action)
                .offset(y: 6)
        }
    }

    private func dataRow(
        title: String,
        detail: String,
        disabled: Bool,
        clear: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: SettingsType.body))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: SettingsType.small))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer()
            SettingsButton(label: "Clear All", action: clear)
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
                .offset(y: 6)
        }
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            VStack(alignment: .leading, spacing: 6) {
                (
                    Text("08FOSE © pa_st")
                        .font(.system(size: SettingsType.body, weight: .bold))
                        .foregroundColor(.primary)
                    + Text(" An Application for browsing and managing the fonts installed on your Mac.")
                        .font(.system(size: SettingsType.body))
                        .foregroundColor(.secondary)
                )
                .fixedSize(horizontal: false, vertical: true)

                Text("v \(Theme.appVersion) : The tag popup can delete a tag everywhere, ⌘F focuses search, and the version label gains a space after the v.")
                    .font(.system(size: SettingsType.small))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    private var shortcutsSection: some View {
        SettingsSection("Shortcuts") {
            VStack(alignment: .leading, spacing: 8) {
                shortcutRow("⌘ ,", "Open / close Settings")
                shortcutRow("⌘ F", "Focus search")
                shortcutRow("T", "Toggle dark / light theme")
                shortcutRow("W", "Cycle weights filter")
                shortcutRow("F", "Favorites filter")
                shortcutRow("M", "Memos filter")
                shortcutRow("0–4", "Wallpaper (0 = none)")
                shortcutRow("K J C L S O", "Toggle script bucket")
                shortcutRow("U", "Show / hide muted")
                shortcutRow("I", "Only muted")
                shortcutRow("[ ]", "Collapse / expand left · right panel")
                shortcutRow("⌘ ↑ ↓", "Font size")
                shortcutRow("⌘ ← →", "Columns")
                shortcutRow("Esc", "Close overlay / detail")
            }
        }
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(description)
                .font(.system(size: SettingsType.small))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            // Right-aligned key cap, lining up with the Clear All buttons.
            Text(keys)
                .font(.system(size: SettingsType.small, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.surfaceFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pillRadius).stroke(Theme.border, lineWidth: 1)
                )
        }
    }

    private var licensesSection: some View {
        SettingsSection("Licenses") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fonts shown in 08FOSE are installed on your Mac and remain the property of their respective owners. Each font's own license governs how it may be used — 08FOSE only previews them.")
                    .font(.system(size: SettingsType.small))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Built with Apple system frameworks (SwiftUI, AppKit). No third-party code is bundled.")
                    .font(.system(size: SettingsType.small))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var resetSection: some View {
        SettingsSection("Reset") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset everything")
                        .font(.system(size: SettingsType.body))
                        .foregroundStyle(.primary)
                    Text("Clears favorites, memos, theme, wallpaper and window size — back to a fresh install.")
                        .font(.system(size: SettingsType.small))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                SettingsButton(label: "Reset") { vm.confirmReset = true }
                    .confirmationDialog(
                        "Reset everything to a fresh install?",
                        isPresented: $vm.confirmReset,
                        titleVisibility: .visible
                    ) {
                        Button("Reset Everything", role: .destructive) { resetEverything() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This clears all data and restarts 08FOSE.")
                    }
            }
        }
    }

    // MARK: - Actions

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { vm.showSettings = false }
    }

    // MARK: - Export / Import

    // e.g. 08FOSE_260604_142530 (YYMMDD_HHMMSS, local time).
    private static func backupFileStem() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd_HHmmss"
        return "08FOSE_\(formatter.string(from: Date()))"
    }

    private func exportData() {
        let payload = ExportData(
            favorites: favorites.exportList,
            memos: memos.exportMap,
            samples: samples.exportMap,
            muted: muted.exportList
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(Self.backupFileStem()).json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? Data(contentsOf: url) else {
            presentImportError("The file could not be read.")
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(ExportData.self, from: data) else {
            presentImportError("This doesn't look like an 08FOSE backup file.")
            return
        }

        // If the app already holds user data, ask whether to merge the backup
        // into it or replace it wholesale. With nothing to lose, just load.
        let hasExistingData = !favorites.exportList.isEmpty
            || !memos.exportMap.isEmpty
            || !samples.exportMap.isEmpty
            || !muted.exportList.isEmpty
        if hasExistingData {
            switch presentImportChoice() {
            case .merge:
                break
            case .replace:
                favorites.clearAll()
                memos.clearAll()
                samples.clearAll()
                muted.clearAll()
            case .cancel:
                return
            }
        }
        // Entries for fonts not installed here are kept and simply stay hidden.
        favorites.merge(payload.favorites)
        memos.merge(payload.memos)
        samples.merge(payload.samples ?? [:])
        muted.merge(payload.muted ?? [])
    }

    private enum ImportChoice { case merge, replace, cancel }

    // Merge is the default (safe, non-destructive) button; Replace is the
    // destructive path so it sits away from the return key.
    private func presentImportChoice() -> ImportChoice {
        let alert = NSAlert()
        alert.messageText = "You already have favorites, memos, or other data in this app."
        alert.informativeText = """
            Merge keeps your current data and adds the backup on top \
            (differing memos are combined). Replace erases everything \
            first and loads only the backup.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        if #available(macOS 11.0, *) {
            alert.buttons[1].hasDestructiveAction = true
        }
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .merge
        case .alertSecondButtonReturn: return .replace
        default:                       return .cancel
        }
    }

    private func presentImportError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Import failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Reset

    private func resetEverything() {
        favorites.clearAll()
        memos.clearAll()
        samples.clearAll()
        muted.clearAll()
        previewText = Self.defaultPreviewText
        vm.resetToDefaults()                  // removePersistentDomain + live defaults
        UserDefaults.standard.synchronize()   // flush before the new instance reads
        relaunch()                            // restart into a clean first-launch state
    }

    // Quit and relaunch. A detached shell waits for THIS process to fully exit,
    // then `open`s the app fresh — avoiding the race of launching a new instance
    // while the old one is still alive. The new process reads the now-cleared
    // defaults, so window size, panels, theme, etc. return to first-launch state.
    // (Under Xcode/`swift run` the bundle lives in DerivedData under the
    // debugger, so relaunch may fail there; it works for the installed .app.)
    private func relaunch() {
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for THIS process to fully exit, give LaunchServices a moment to
        // clear the old registration, then force a brand-new instance with -n.
        // Without -n (and without the grace delay) `open` can race the just-quit
        // app — finding it still briefly registered — and no-op, so nothing
        // relaunches.
        task.arguments = ["-c",
            "while /bin/kill -0 \(pid) >/dev/null 2>&1; do /bin/sleep 0.1; done; /bin/sleep 0.5; /usr/bin/open -n \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: SettingsType.sectionHeader, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsButton: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: SettingsType.small, weight: .medium))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .fill(hovering ? Theme.surfaceFillHover : Theme.surfaceFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

// Mirrors the font detail view's close button: secondary xmark glyph on a
// surfaceFill circle that densifies on hover.
private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hovering ? Theme.surfaceFillHover : Theme.surfaceFill))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityLabel("Close settings")
        .help("Close (Esc)")
    }
}
