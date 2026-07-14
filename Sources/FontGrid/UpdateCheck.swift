import AppKit
import SwiftUI

// Result of one update check against the GitHub releases feed.
enum UpdateStatus: Equatable {
    case upToDate(current: String)
    case available(latest: String, current: String, dmgURL: URL?)
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
            case .available(let latest, let current, let dmgURL):
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
        return isNewer(latest, than: Theme.appVersion)
            ? .available(latest: latest, current: Theme.appVersion, dmgURL: release.dmgURL)
            : .upToDate(current: Theme.appVersion)
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
        return LatestRelease(tag: tag, dmgURL: dmgURL)
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
        ZStack {
            Color.black.opacity(colorScheme == .light ? 0.15 : 0.35)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            card
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title carries the state, so it reads at a glance.
            Text(statusTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            // The version(s) as a single emphasized line under the title.
            Text(versionLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, 6)

            // Number-free explanation.
            Text(descLine)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            // Only the available state carries a button (left-aligned); the
            // up-to-date / failed cards close via ✕ / ESC / backdrop only.
            if case .available(let latest, _, let dmgURL) = status {
                HStack {
                    if let dmgURL {
                        popupButton("Download & Open", tint: Theme.accent, hovering: $primaryHovering) {
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
        .padding(20)
        // leading (not the default center): the up-to-date / failed states have
        // no width-filling child, so centering would float the text block right
        // of the padding while the close button stays pinned to the frame edge.
        .frame(width: 320, alignment: .leading)
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
            PopupCloseButton { onClose() }
                .padding(.top, 18)
                .padding(.trailing, 20)   // match the content's 20 left margin
        }
    }

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
        case .available(let latest, let current, _): return "v \(current) → v \(latest)"
        case .failed:                       return "v \(Theme.appVersion)"
        }
    }

    private var descLine: String {
        switch status {
        case .upToDate:
            return "This is the latest release on GitHub — there's nothing new to download."
        case .available(_, _, let dmgURL):
            return dmgURL != nil
                ? "A newer release is ready on GitHub. Download it and the disk image opens by itself."
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
