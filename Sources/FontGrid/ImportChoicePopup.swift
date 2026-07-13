import SwiftUI

// In-app modal card asking how to load a backup when the app already holds
// user data: Merge (keep + add, the safe default) or Replace (erase first).
// Replaces the old NSAlert so the choice shares the popup design language.
// Presented above the Settings overlay; ESC / ✕ / backdrop cancel.
struct ImportChoicePopup: View {
    let payload: ExportData
    let onCancel: () -> Void
    let onMerge: () -> Void
    let onReplace: () -> Void

    // Two-stage replace, same pattern as the rename popup's Delete Tag:
    // first press arms the button (label flips to Confirm), second replaces.
    @State private var confirmingReplace = false
    @State private var replaceHovering = false
    @State private var mergeHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .light ? 0.15 : 0.35)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            card
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Import Backup")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            // Line 1 — did it work: the file has been read and decoded.
            Text("The backup file was read successfully.")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            // Line 2 — what it contains.
            Text(payloadSummary)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            // Line 3 — what the choice below will do.
            Text("You already have data in this app. Merge keeps it and adds the backup on top — differing memos are combined. Replace erases everything first and loads only the backup.")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            HStack(spacing: 8) {
                textButton(confirmingReplace ? "Confirm" : "Replace",
                           hovering: $replaceHovering) {
                    if confirmingReplace { onReplace() } else { confirmingReplace = true }
                }
                Spacer()
                popupButton("Merge", tint: Theme.accent, hovering: $mergeHovering, action: onMerge)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 340)
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
            PopupCloseButton { onCancel() }
                .padding(.top, 18)
                .padding(.trailing, 18)
        }
    }

    // e.g. "12 pins · 34 memos · 3 specimens · 2 muted"
    private var payloadSummary: String {
        var parts: [String] = []
        func add(_ count: Int, _ noun: String) {
            guard count > 0 else { return }
            parts.append("\(count) \(noun)")
        }
        add(payload.pins.count, payload.pins.count == 1 ? "pin" : "pins")
        add(payload.memos.count, payload.memos.count == 1 ? "memo" : "memos")
        add((payload.samples ?? [:]).count, (payload.samples ?? [:]).count == 1 ? "specimen" : "specimens")
        add((payload.muted ?? []).count, "muted")
        return parts.isEmpty ? "This backup is empty." : "Backup holds " + parts.joined(separator: " · ")
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

    private func textButton(_ title: String, hovering: Binding<Bool>,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.smallSize + 1, weight: .medium))
                .foregroundStyle(hovering.wrappedValue ? AnyShapeStyle(.primary)
                                                       : AnyShapeStyle(.secondary))
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering.wrappedValue = $0 }
    }
}
