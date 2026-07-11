import AppKit
import SwiftUI

// Result of one update check against the GitHub releases feed.
enum UpdateStatus: Equatable {
    case upToDate(current: String)
    case available(latest: String, current: String)
    case failed
}

// Notify-only update check against the public GitHub releases feed: no
// downloading, no self-update — a newer release just links to the releases
// page in the browser.
//
// Two entry points share fetchStatus():
//  - launch: the result becomes a toast (up-to-date auto-dismisses; a newer
//    release carries a View button). Failures stay silent — an unasked-for
//    update nudge is never worth an error.
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
            case .upToDate(let current):
                toasts.show(Toast(
                    style: .success,
                    title: "You're up to date",
                    detail: "v \(current) is the latest version."
                ))
            case .available(let latest, let current):
                toasts.show(Toast(
                    style: .info,
                    title: "Update available — v \(latest)",
                    detail: "You're on v \(current).",
                    icon: "arrow.down.circle",
                    actionLabel: "View",
                    action: { openReleasesPage() }
                ))
            case .failed:
                break
            }
        }
    }

    static func fetchStatus() async -> UpdateStatus {
        guard let tag = await fetchLatestTag() else { return .failed }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(latest, than: Theme.appVersion)
            ? .available(latest: latest, current: Theme.appVersion)
            : .upToDate(current: Theme.appVersion)
    }

    // tag_name of the latest (non-draft, non-prerelease) release, or nil on
    // any failure. Unauthenticated: fine at this frequency (the API allows
    // 60 calls/hour per IP).
    private static func fetchLatestTag() async -> String? {
        var request = URLRequest(url: latestAPIURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String
        else { return nil }
        return tag
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
// that opens the releases page in the browser.
struct UpdateResultPopup: View {
    let status: UpdateStatus
    let onClose: () -> Void

    @State private var primaryHovering = false
    @Environment(\.colorScheme) private var colorScheme

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
            Text("Check for Updates")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            Text(statusLine)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text(detailLine)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            // Only the available state carries a button (left-aligned); the
            // up-to-date / failed cards close via ✕ / ESC / backdrop only.
            if case .available = status {
                HStack {
                    popupButton("View Release", tint: Theme.accent, hovering: $primaryHovering) {
                        UpdateCheck.openReleasesPage()
                        onClose()
                    }
                    Spacer()
                }
                .padding(.top, 16)
            }
        }
        .padding(20)
        .frame(width: 320)
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
                .padding(.trailing, 18)
        }
    }

    private var statusLine: String {
        switch status {
        case .upToDate:  return "You're up to date."
        case .available: return "A newer version is available."
        case .failed:    return "The update check failed."
        }
    }

    private var detailLine: String {
        switch status {
        case .upToDate(let current):
            return "v \(current) is the latest version on GitHub."
        case .available(let latest, let current):
            return "v \(latest) is out — you're on v \(current). The releases page has the download."
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
