import SwiftUI

// MARK: - Toast model

// One transient feedback message. Success/info toasts auto-dismiss; error
// toasts stay until dismissed (✕ or click) so a failure can't be missed.
// An optional action (e.g. Undo) rides on the right edge.
struct Toast: Identifiable, Equatable {
    enum Style { case success, error, info }

    let id = UUID()
    var style: Style
    var title: String
    var detail: String? = nil
    // SF Symbol override; nil falls back to the style's default glyph.
    var icon: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    // Identity-based: a re-shown toast (new id) re-triggers the transition
    // even when the text happens to be identical.
    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }

    // nil = sticky (errors). Action toasts get a longer window so the user
    // can actually reach the button.
    var duration: Double? {
        if style == .error { return nil }
        return actionLabel != nil ? 4.0 : 2.0
    }

    var defaultIcon: String {
        switch style {
        case .success: return "checkmark"
        case .error:   return "exclamationmark.circle"
        case .info:    return "info.circle"
        }
    }
}

// MARK: - Toast center

// Single presenter: a new toast replaces the current one (no queue — at this
// app's scale, the latest result is the one that matters). Auto-dismiss is a
// cancellable task keyed to the toast's id so a replacement can't be killed
// by its predecessor's expiring timer; hovering parks the timer.
@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var toast: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ toast: Toast) {
        dismissTask?.cancel()
        self.toast = toast
        scheduleDismiss(for: toast, after: toast.duration)
    }

    func dismiss(_ id: UUID) {
        guard toast?.id == id else { return }
        dismissTask?.cancel()
        toast = nil
    }

    // Hover pause/resume. Resume restarts a short grace window instead of the
    // full duration — the user has already read the toast.
    func pauseAutoDismiss(_ id: UUID) {
        guard toast?.id == id else { return }
        dismissTask?.cancel()
    }

    func resumeAutoDismiss(_ id: UUID) {
        guard let toast, toast.id == id, toast.duration != nil else { return }
        scheduleDismiss(for: toast, after: 1.5)
    }

    private func scheduleDismiss(for toast: Toast, after seconds: Double?) {
        guard let seconds else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }
}

// MARK: - Toast view

// The card uses one fixed palette in every context — black surface, light
// grey text — independent of light/dark mode AND of the wallpaper (it sits on
// the topmost layer, above the wallpaper tint, and deliberately doesn't
// re-composite it). Errors tint the hairline and glyph red; everything else
// stays monochrome. Clicking anywhere on the card dismisses it.
struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void
    let onHover: (Bool) -> Void

    @State private var actionHovering = false

    // Fixed palette (mode-independent).
    private static let surface = Color(white: 0.10)
    private static let titleText = Color(white: 0.88)
    private static let detailText = Color(white: 0.62)
    private static let dimText = Color(white: 0.45)
    // Dark-mode gold: the action button always sits on the black card, so the
    // light-mode orange accent never applies here.
    private static let gold = Color(red: 217/255, green: 166/255, blue: 51/255)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon ?? toast.defaultIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toast.style == .error ? Color.red : Self.titleText)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Self.titleText)
                if let detail = toast.detail {
                    Text(detail)
                        .font(.system(size: Theme.smallSize))
                        .foregroundStyle(Self.detailText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let label = toast.actionLabel {
                Button {
                    toast.action?()
                    onDismiss()
                } label: {
                    Text(label)
                        .font(.system(size: Theme.smallSize + 1, weight: .medium))
                        .foregroundStyle(Self.gold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.pillRadius)
                                .fill(Self.gold.opacity(actionHovering ? 0.24 : 0.12))
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { actionHovering = $0 }
                .padding(.leading, 4)
            }

            if toast.style == .error {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Self.dimText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Self.surface)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onHover(perform: onHover)
    }

    // Errors tint the line red so the state reads even before the text does.
    private var hairline: Color {
        toast.style == .error ? .red.opacity(0.55) : Color.white.opacity(0.35)
    }
}
