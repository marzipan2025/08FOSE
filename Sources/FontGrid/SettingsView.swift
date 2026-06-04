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

    @AppStorage("previewText") private var previewText: String =
        "The quick brown fox jumps over lazy dog"
    private static let defaultPreviewText = "The quick brown fox jumps over lazy dog"

    // Equal gap from the top and right edges of the window for the close button.
    private static let closeInset: CGFloat = 40

    var body: some View {
        ZStack {
            // Blur everything behind, then dim slightly for focus.
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            Color.black.opacity(0.18)
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
                aboutSection
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

                // Export / import favorites + memos (tags live inside memos).
                backupRow(
                    title: "Export",
                    detail: "Save favorites & memos to a JSON file",
                    button: "Export",
                    action: exportData
                )
                backupRow(
                    title: "Import",
                    detail: "Merge favorites & memos from a JSON file",
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
        HStack {
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
        }
    }

    private func dataRow(
        title: String,
        detail: String,
        disabled: Bool,
        clear: @escaping () -> Void
    ) -> some View {
        HStack {
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
        }
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("08FOSE")
                        .font(.system(size: SettingsType.body, weight: .bold))
                    Text("v\(Theme.appVersion)")
                        .font(.system(size: SettingsType.small))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Text("A macOS font browser — preview, favorite and annotate the fonts installed on your Mac.")
                    .font(.system(size: SettingsType.small))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("© pa_st")
                    .font(.system(size: SettingsType.small))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var shortcutsSection: some View {
        SettingsSection("Shortcuts") {
            VStack(alignment: .leading, spacing: 8) {
                shortcutRow("⌘ ,", "Open / close Settings")
                shortcutRow("T", "Toggle dark / light theme")
                shortcutRow("W", "Cycle weights filter")
                shortcutRow("F", "Favorites filter")
                shortcutRow("M", "Memos filter")
                shortcutRow("0–4", "Wallpaper (0 = none)")
                shortcutRow("K J C L S O", "Toggle script bucket")
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
            memos: memos.exportMap
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
        // Merge: favorites union, memos appended when they differ. Entries for
        // fonts not installed here are kept and simply stay hidden.
        favorites.merge(payload.favorites)
        memos.merge(payload.memos)
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
        previewText = Self.defaultPreviewText
        vm.resetToDefaults()
        resetWindowSize()
    }

    private func resetWindowSize() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
        else { return }
        let size = NSSize(width: 1280, height: 860)   // matches .defaultSize
        let screen = window.screen ?? NSScreen.main
        let origin: NSPoint
        if let visible = screen?.visibleFrame {
            origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2)
        } else {
            origin = window.frame.origin
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
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
