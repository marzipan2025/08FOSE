import AppKit
import SwiftUI

// Result of one update check against the GitHub releases feed.
enum UpdateStatus: Equatable {
    case upToDate(current: String)
    case available(latest: String, current: String, dmgURL: URL?)
    case failed
}

// Update check against the public GitHub releases feed. A newer release
// offers a one-click download: the dmg asset is saved to ~/Downloads and
// opened (macOS mounts it). Once the volume mounts, a "Quit & Install" toast
// appears so the user can close the running app (freeing /Applications) before
// dragging the new build in. No self-update — installing is still the user
// dragging the app into /Applications. Releases without a dmg asset fall
// back to opening the releases page in the browser.
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
                            downloadAndMount(dmgURL, version: latest, toasts: toasts)
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

    // Saves the release's dmg into ~/Downloads and opens it, which mounts the
    // disk image. Progress rides on the toast layer: a sticky "Downloading…"
    // toast while the transfer runs, then a brief "Downloaded — opening…"
    // success. When the volume finishes mounting (detected via
    // observeMountThenOfferInstall) that's swapped for a sticky "Quit &
    // Install" toast. A transfer failure shows an error toast whose View
    // button falls back to the releases page.
    static func downloadAndMount(_ dmgURL: URL, version: String, toasts: ToastCenter) {
        Task {
            toasts.show(Toast(
                style: .info,
                title: "Downloading v \(version)…",
                detail: "The disk image will open when it's ready.",
                icon: "arrow.down.circle",
                sticky: true
            ))
            do {
                let (tmp, response) = try await URLSession.shared.download(from: dmgURL)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let folder = FileManager.default
                    .urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let dest = folder.appendingPathComponent(dmgURL.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                // Arm the mount watcher BEFORE opening so the notification can't
                // be missed, then open the dmg (which triggers the mount).
                observeMountThenOfferInstall(version: version, toasts: toasts)
                NSWorkspace.shared.open(dest)
                toasts.show(Toast(
                    style: .success,
                    title: "Downloaded v \(version)",
                    detail: "Opening the disk image…",
                    icon: "arrow.down.circle"
                ))
            } catch {
                toasts.show(Toast(
                    style: .error,
                    title: "Download failed",
                    detail: "The disk image couldn't be fetched from GitHub.",
                    actionLabel: "View",
                    action: { openReleasesPage() }
                ))
            }
        }
    }

    // Non-nil while we're watching for the just-downloaded dmg to finish
    // mounting; lets a repeat download tear down the previous watcher.
    private static var mountObserver: NSObjectProtocol?

    // Watch for OUR dmg's volume mounting, then replace the progress toast with
    // a sticky "Quit & Install" toast. Installing stays manual (the user drags
    // 08FOSE onto Applications in the mounted window), but quitting first frees
    // /Applications so the copy can't hit an "app is in use" wall — and by then
    // the disk-image window already shows the drag-to-Applications layout.
    // One-shot: the observer removes itself once our volume appears.
    private static func observeMountThenOfferInstall(version: String, toasts: ToastCenter) {
        let center = NSWorkspace.shared.notificationCenter
        if let existing = mountObserver {
            center.removeObserver(existing)
            mountObserver = nil
        }
        mountObserver = center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { note in
            // queue: .main → this runs on the main thread.
            guard let url = mountedVolumeURL(from: note),
                  // Our dmg mounts as /Volumes/08FOSE (a stale mount adds a
                  // " 1" suffix, still caught by the prefix).
                  url.lastPathComponent.hasPrefix("08FOSE") else { return }
            if let observer = mountObserver {
                center.removeObserver(observer)
                mountObserver = nil
            }
            toasts.show(Toast(
                style: .success,
                title: "Ready to install — v \(version)",
                detail: "Quit 08FOSE, then drag it onto Applications in the disk-image window.",
                icon: "arrow.down.circle",
                actionLabel: "Quit & Install",
                action: { NSApp.terminate(nil) },
                sticky: true
            ))
        }
    }

    // The mounted volume's location from a didMountNotification: the modern URL
    // key, falling back to the legacy device-path string.
    private static func mountedVolumeURL(from note: Notification) -> URL? {
        if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL { return url }
        if let path = note.userInfo?["NSDevicePath"] as? String { return URL(fileURLWithPath: path) }
        return nil
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
                            UpdateCheck.downloadAndMount(dmgURL, version: latest, toasts: toasts)
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
