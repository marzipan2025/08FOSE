import AppKit
import SwiftUI

// Result of one update check against the GitHub releases feed.
enum UpdateStatus: Equatable {
    case upToDate(current: String)
    // notes: the release body's first paragraph; thumbnail: the release's
    // update.png asset (560×236, drawn at 280×118). Either may be missing —
    // the popup then simply leaves that slot out.
    case available(latest: String, current: String, dmgURL: URL?,
                   notes: String?, thumbnail: NSImage?)
    case failed
}

// Update check against the public GitHub releases feed. A newer release offers
// a one-click, self-contained install: the dmg is downloaded to a temp dir and
// mounted silently (no Finder window); an "Install & Relaunch" toast then lets
// a detached helper replace the running bundle in place, unmount, and relaunch,
// after which the fresh instance confirms with an "Updated to vX" toast.
// Releases without a dmg asset fall back to opening the releases page in the
// browser.
//
// Two entry points share fetchStatus():
//  - launch: only a newer release surfaces a toast (carrying a Download
//    button). Up-to-date and failure both stay silent — an unprompted
//    "you're current" toast, or an error, is never worth interrupting launch.
//  - Settings "Check" button: the result becomes UpdateResultPopup, where a
//    failure IS shown (the user explicitly asked).
@MainActor
enum UpdateCheck {
    static let releasesPageURL = URL(string: "https://github.com/marzipan2025/08FOSE/releases")!
    private static let latestAPIURL = URL(string: "https://api.github.com/repos/marzipan2025/08FOSE/releases/latest")!

    static func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }

    // Called once from RootView when the app launches.
    static func checkOnLaunch(toasts: ToastCenter) {
        Task {
            switch await fetchStatus() {
            case .upToDate:
                // Already on the latest release: stay silent. An unprompted
                // "you're up to date" toast on every launch is just noise —
                // the launch toast is reserved for when there's an update.
                break
            case .available(let latest, let current, let dmgURL, _, _):
                toasts.show(Toast(
                    style: .info,
                    title: "Update available — v \(latest)",
                    detail: "You're on v \(current).",
                    icon: "arrow.down.circle",
                    actionLabel: dmgURL != nil ? "Download" : "View",
                    action: {
                        if let dmgURL {
                            downloadAndInstall(dmgURL, version: latest, toasts: toasts)
                        } else {
                            openReleasesPage()
                        }
                    }
                ))
            case .failed:
                break
            }
        }
    }

    static func fetchStatus() async -> UpdateStatus {
        guard let release = await fetchLatestRelease() else { return .failed }
        let latest = release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag
        guard isNewer(latest, than: Theme.appVersion) else {
            return .upToDate(current: Theme.appVersion)
        }
        // The thumbnail is fetched before the popup appears so it never pops in
        // and resizes the card; a slow or failed fetch just drops the image.
        var thumbnail: NSImage?
        if let url = release.thumbnailURL { thumbnail = await fetchThumbnail(url) }
        return .available(latest: latest, current: Theme.appVersion, dmgURL: release.dmgURL,
                          notes: release.notes, thumbnail: thumbnail)
    }

    private static func fetchThumbnail(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }

    // First paragraph of a release body, as plain text: markdown headings and
    // list markers are dropped, and line breaks inside it are joined.
    static func firstParagraph(of body: String) -> String? {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var paragraph: [String] = []
        for line in lines {
            if line.hasPrefix("#") { if paragraph.isEmpty { continue } else { break } }
            if line.isEmpty { if paragraph.isEmpty { continue } else { break } }
            var text = line
            for marker in ["- ", "* ", "+ "] where text.hasPrefix(marker) {
                text = String(text.dropFirst(marker.count))
            }
            paragraph.append(text)
        }
        let joined = paragraph.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    enum UpdateError: Error { case mountFailed }

    // Downloads the release dmg to a temp location, mounts it silently (no
    // Finder window), verifies the app is inside, and offers a single
    // "Install & Relaunch" confirmation. The actual install runs in a detached
    // helper (see installAndRelaunch). A failure at any step shows an error
    // toast whose View button falls back to the releases page.
    static func downloadAndInstall(_ dmgURL: URL, version: String, toasts: ToastCenter) {
        Task {
            toasts.show(Toast(
                style: .info,
                title: "Downloading v \(version)…",
                detail: "Preparing the update in the background.",
                icon: "arrow.down.circle",
                sticky: true
            ))
            do {
                let (tmp, response) = try await URLSession.shared.download(from: dmgURL)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                // The dmg lives in a temp dir; the installer deletes it after.
                let dmgDest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("08FOSE-\(version).dmg")
                try? FileManager.default.removeItem(at: dmgDest)
                try FileManager.default.moveItem(at: tmp, to: dmgDest)

                // Mount without a Finder window and locate the app inside.
                guard let mountPoint = await attachDMG(at: dmgDest.path) else {
                    throw UpdateError.mountFailed
                }
                let appSource = (mountPoint as NSString).appendingPathComponent("08FOSE.app")
                guard FileManager.default.fileExists(atPath: appSource) else {
                    _ = await runProcessData("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"])
                    throw UpdateError.mountFailed
                }

                // Everything staged — one confirmation drives the rest.
                toasts.show(Toast(
                    style: .success,
                    title: "Ready to install — v \(version)",
                    detail: "08FOSE will quit, update itself and reopen.",
                    icon: "arrow.down.circle",
                    actionLabel: "Install & Relaunch",
                    action: {
                        installAndRelaunch(appSource: appSource,
                                           mountPoint: mountPoint,
                                           dmgPath: dmgDest.path,
                                           version: version)
                    },
                    sticky: true
                ))
            } catch {
                toasts.show(Toast(
                    style: .error,
                    title: "Download failed",
                    detail: "The update couldn't be prepared from GitHub.",
                    actionLabel: "View",
                    action: { openReleasesPage() }
                ))
            }
        }
    }

    // Writes a detached bash helper that: waits for THIS app to quit, replaces
    // the installed bundle (Bundle.main) with the mounted build, unmounts,
    // deletes the dmg, and relaunches — passing -updatedTo (or -updateFailed)
    // so the fresh instance can confirm the outcome. Then it terminates the
    // app. A process can't atomically replace and relaunch itself, so the
    // copy/relaunch must live in a separate process (the approach Sparkle's
    // relauncher takes). The replace is staged (ditto → backup old → move new,
    // restoring the backup on failure) so a mid-copy error can't leave the app
    // missing from /Applications.
    private static func installAndRelaunch(appSource: String, mountPoint: String,
                                           dmgPath: String, version: String) {
        let dest = Bundle.main.bundlePath
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let script = """
        #!/bin/bash
        APP_PID="$1"; SRC="$2"; DEST="$3"; MOUNT="$4"; DMG="$5"; VERSION="$6"
        for i in $(seq 1 150); do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.1; done
        OK=0
        STAGE="${DEST}.update-$$"; BACKUP="${DEST}.old-$$"
        rm -rf "$STAGE" "$BACKUP"
        if ditto "$SRC" "$STAGE"; then
          xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null
          if mv "$DEST" "$BACKUP" 2>/dev/null; then
            if mv "$STAGE" "$DEST" 2>/dev/null; then
              OK=1; rm -rf "$BACKUP"
            else
              mv "$BACKUP" "$DEST" 2>/dev/null
            fi
          fi
        fi
        rm -rf "$STAGE" 2>/dev/null
        hdiutil detach "$MOUNT" -quiet 2>/dev/null
        rm -f "$DMG" 2>/dev/null
        if [ "$OK" = "1" ]; then
          open -a "$DEST" --args -updatedTo "$VERSION"
        else
          open -a "$DEST" --args -updateFailed 1
        fi
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("08fose-install.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            // Couldn't stage the helper — nothing destructive happened, so just
            // leave the app running rather than quitting into a dead end.
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path, pid, appSource, dest, mountPoint, dmgPath, version]
        do { try task.run() } catch { return }
        NSApp.terminate(nil)
    }

    // Mounts a dmg with no Finder window and returns its mount point, parsed
    // from hdiutil's plist output (robust against the tab-delimited format).
    private static func attachDMG(at path: String) async -> String? {
        let data = await runProcessData(
            "/usr/bin/hdiutil",
            ["attach", path, "-nobrowse", "-noverify", "-plist"]
        )
        guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { return nil }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }

    // Runs a process off the main thread and returns its stdout. Used for
    // hdiutil; the detached installer helper is spawned separately (fire and
    // forget) since it must outlive this process.
    private static func runProcessData(_ launchPath: String, _ args: [String]) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = Pipe()
                do { try process.run() } catch {
                    continuation.resume(returning: Data()); return
                }
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: out)
            }
        }
    }

    // Called once at launch: if we were relaunched by the installer helper,
    // confirm the result. The flags come from the argument domain (-updatedTo /
    // -updateFailed passed to `open --args`), so they're transient and clear on
    // the next normal launch.
    static func showPostUpdateToastIfNeeded(toasts: ToastCenter) {
        let defaults = UserDefaults.standard
        if let version = defaults.string(forKey: "updatedTo") {
            toasts.show(Toast(
                style: .success,
                title: "Updated to v \(version)",
                detail: "You're now on the latest version.",
                icon: "checkmark.seal"
            ))
        } else if defaults.bool(forKey: "updateFailed") {
            toasts.show(Toast(
                style: .error,
                title: "Update didn't complete",
                detail: "08FOSE couldn't be replaced. Try again from Settings → Check for Updates.",
                actionLabel: "View",
                action: { openReleasesPage() }
            ))
        }
    }

    private struct LatestRelease {
        let tag: String
        let dmgURL: URL?
        let notes: String?
        let thumbnailURL: URL?
    }

    // Latest (non-draft, non-prerelease) release: its tag_name plus the first
    // .dmg asset's download URL, or nil on any failure. Unauthenticated: fine
    // at this frequency (the API allows 60 calls/hour per IP).
    private static func fetchLatestRelease() async -> LatestRelease? {
        var request = URLRequest(url: latestAPIURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String
        else { return nil }
        let assets = object["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        let dmgURL = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let thumb = assets.first { ($0["name"] as? String)?.lowercased() == "update.png" }
        let thumbnailURL = (thumb?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let notes = (object["body"] as? String).flatMap(firstParagraph(of:))
        return LatestRelease(tag: tag, dmgURL: dmgURL, notes: notes, thumbnailURL: thumbnailURL)
    }

    // Numeric component-wise semver compare ("0.7.10" > "0.7.9"); missing
    // components count as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// In-app modal card showing the result of a manual update check (Settings →
// Updates → Check). Same card language as the rename-tag / import-choice
// popups. ESC / ✕ / backdrop close it; the available state adds a button
// that downloads the dmg and mounts it (or, with no dmg asset, opens the
// releases page in the browser).
struct UpdateResultPopup: View {
    let status: UpdateStatus
    let onClose: () -> Void

    @State private var primaryHovering = false
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var toasts: ToastCenter

    var body: some View {
        // Pinned to the top center (toasts' column, 48pt below their 12pt
        // top gap) rather than floating mid-window.
        ZStack(alignment: .top) {
            Color.black.opacity(colorScheme == .light ? 0.15 : 0.35)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            card
                .padding(.top, 60)
        }
        .ignoresSafeArea()
    }

    private var thumbnail: NSImage? {
        if case .available(_, _, _, _, let thumbnail?) = status { return thumbnail }
        return nil
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Release thumbnail, only when the release ships one: full-bleed
            // across the top, its upper corners rounded by the card's clip.
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.cardWidth, height: Self.thumbnailHeight)
                    .clipped()
            }

            content
                .padding(Self.margin)
                // 2pt tighter under the thumbnail than the plain card's top.
                .padding(.top, thumbnail == nil ? 0 : -2)
        }
        .frame(width: Self.cardWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.panelBackground)
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .light ? Color(white: 0.56) : Color.white.opacity(0.8),
                        lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            PopupCloseButton(overImage: thumbnail != nil) { onClose() }
                .padding(.top, 18)
                .padding(.trailing, 18)   // same corner inset as the other popups
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title carries the state, so it reads at a glance.
            Text(statusTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            // The version(s) as a single emphasized line under the title.
            Text(versionLine)
                .font(.system(size: Theme.smallSize - 2, weight: .light))   // 2pt under the body
                .foregroundStyle(.primary)
                .padding(.top, 3)

            // Release notes when available, otherwise a number-free explanation.
            Text(descLine)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            // Only the available state carries a button (left-aligned); the
            // up-to-date / failed cards close via ✕ / ESC / backdrop only.
            if case .available(let latest, _, let dmgURL, _, _) = status {
                HStack {
                    if let dmgURL {
                        popupButton("Download and Install", tint: Theme.accent, hovering: $primaryHovering) {
                            UpdateCheck.downloadAndInstall(dmgURL, version: latest, toasts: toasts)
                            onClose()
                        }
                    } else {
                        popupButton("View Release", tint: Theme.accent, hovering: $primaryHovering) {
                            UpdateCheck.openReleasesPage()
                            onClose()
                        }
                    }
                    Spacer()
                }
                .padding(.top, 16)
            }
        }
    }

    // Text sits inside the popups' usual 20pt margin; the thumbnail runs
    // edge to edge across the card's full width at a 256:108 ratio
    // (280×118 — ship update.png at 560×236 for Retina).
    static let margin: CGFloat = 20
    static let contentWidth: CGFloat = 240
    static let cardWidth = contentWidth + margin * 2
    static let thumbnailHeight = (cardWidth * 108 / 256).rounded()

    private var statusTitle: String {
        switch status {
        case .upToDate:  return "You're up to date."
        case .available: return "New Update!"
        case .failed:    return "Error"
        }
    }

    private var versionLine: String {
        switch status {
        case .upToDate(let current):        return "v \(current)"
        case .available(let latest, let current, _, _, _): return "v \(current) → v \(latest)"
        case .failed:                       return "v \(Theme.appVersion)"
        }
    }

    private var descLine: String {
        switch status {
        case .upToDate:
            return "This is the latest release on GitHub — there's nothing new to download."
        case .available(_, _, let dmgURL, let notes, _):
            if let notes { return notes }
            return dmgURL != nil
                ? "A newer release is ready on GitHub. 08FOSE downloads it, updates itself and reopens."
                : "A newer release is ready on GitHub. Open the releases page to download it."
        case .failed:
            return "GitHub couldn't be reached. Check your connection and try again."
        }
    }

    private func popupButton(_ title: String, tint: Color,
                             hovering: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.smallSize + 1, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .fill(tint.opacity(hovering.wrappedValue ? 0.24 : 0.12))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering.wrappedValue = $0 }
    }
}
