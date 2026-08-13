import SwiftUI

// MARK: - Pencil Icon

// The designed pencil glyph (from pencil icon.svg, 21×21), emitted as a Path
// in unit space so it scales with its frame and tints via fill(). Even-odd
// fill keeps the two inner cutouts (body + eraser band) hollow.
struct PencilShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0.5512 * w, y: 0.0292 * h))
        p.addCurve(to: CGPoint(x: 0.6349 * w, y: 0.0127 * h), control1: CGPoint(x: 0.5698 * w, y: 0.0015 * h), control2: CGPoint(x: 0.6073 * w, y: -0.0059 * h))
        p.addLine(to: CGPoint(x: 0.9183 * w, y: 0.2027 * h))
        p.addCurve(to: CGPoint(x: 0.9348 * w, y: 0.2864 * h), control1: CGPoint(x: 0.9460 * w, y: 0.2213 * h), control2: CGPoint(x: 0.9534 * w, y: 0.2587 * h))
        p.addLine(to: CGPoint(x: 0.5072 * w, y: 0.9240 * h))
        p.addCurve(to: CGPoint(x: 0.4688 * w, y: 0.9496 * h), control1: CGPoint(x: 0.4983 * w, y: 0.9373 * h), control2: CGPoint(x: 0.4845 * w, y: 0.9465 * h))
        p.addLine(to: CGPoint(x: 0.2321 * w, y: 0.9962 * h))
        p.addCurve(to: CGPoint(x: 0.1612 * w, y: 0.9487 * h), control1: CGPoint(x: 0.1994 * w, y: 1.0027 * h), control2: CGPoint(x: 0.1677 * w, y: 0.9814 * h))
        p.addLine(to: CGPoint(x: 0.1146 * w, y: 0.7120 * h))
        p.addCurve(to: CGPoint(x: 0.1236 * w, y: 0.6668 * h), control1: CGPoint(x: 0.1115 * w, y: 0.6963 * h), control2: CGPoint(x: 0.1147 * w, y: 0.6800 * h))
        p.addLine(to: CGPoint(x: 0.4087 * w, y: 0.2417 * h))
        p.addLine(to: CGPoint(x: 0.5512 * w, y: 0.0292 * h))
        p.closeSubpath()
        p.move(to: CGPoint(x: 0.4753 * w, y: 0.3590 * h))
        p.addLine(to: CGPoint(x: 0.2377 * w, y: 0.7132 * h))
        p.addLine(to: CGPoint(x: 0.2679 * w, y: 0.8662 * h))
        p.addLine(to: CGPoint(x: 0.4209 * w, y: 0.8361 * h))
        p.addLine(to: CGPoint(x: 0.6585 * w, y: 0.4818 * h))
        p.addLine(to: CGPoint(x: 0.4753 * w, y: 0.3590 * h))
        p.closeSubpath()
        p.move(to: CGPoint(x: 0.7257 * w, y: 0.3816 * h))
        p.addLine(to: CGPoint(x: 0.8010 * w, y: 0.2693 * h))
        p.addLine(to: CGPoint(x: 0.6178 * w, y: 0.1464 * h))
        p.addLine(to: CGPoint(x: 0.5425 * w, y: 0.2588 * h))
        p.addLine(to: CGPoint(x: 0.7257 * w, y: 0.3816 * h))
        p.closeSubpath()
        return p
    }
}

// MARK: - Rename Tag Button

// Small pencil next to the "Tag : x" stats label in the center panel's top
// bar. Opens the rename popup for the active tag.
struct RenameTagButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            PencilShape()
                .fill(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary),
                      style: FillStyle(eoFill: true))
                .frame(width: 12, height: 12)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help("Rename this tag")
    }
}

// MARK: - Rename Tag Popup

// In-app modal card for renaming a tag everywhere it appears. Enter commits
// (after validation), the Cancel button / backdrop click dismisses. ESC first
// drops the field focus (global key monitor), a second ESC closes the popup
// via the RootView cascade.
struct RenameTagPopup: View {
    let tag: String
    let count: Int
    let onCancel: () -> Void
    let onCommit: (String) -> Void
    let onDelete: () -> Void

    @State private var text: String
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    // Two-stage delete: first press arms the button (label flips to Confirm
    // in place), second press deletes. No separate alert.
    @State private var confirmingDelete = false
    @State private var deleteHovering = false
    @State private var renameHovering = false
    // (Cancel is the ✕ button / ESC / backdrop — no Cancel button in the row.)
    @Environment(\.colorScheme) private var colorScheme

    init(tag: String, count: Int,
         onCancel: @escaping () -> Void,
         onCommit: @escaping (String) -> Void,
         onDelete: @escaping () -> Void) {
        self.tag = tag
        self.count = count
        self.onCancel = onCancel
        self.onCommit = onCommit
        self.onDelete = onDelete
        _text = State(initialValue: tag)
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop; clicking it cancels. Light mode dims gently —
            // a heavy dim would land the backdrop at the same grey as the
            // card's 0.56 hairline and swallow it.
            Color.black.opacity(colorScheme == .light ? 0.15 : 0.35)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            card
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rename Tag")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            Text("#\(tag) · applied to \(count) font\(count == 1 ? "" : "s")")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Theme.surfaceRadius).fill(Theme.surfaceFill))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.surfaceRadius)
                        .stroke(focused ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
                )
                .focused($focused)
                .onSubmit(commit)
                .padding(.top, 14)

            // Fixed slot so the card doesn't jump when the error appears.
            Text(errorMessage ?? " ")
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(.red)
                .padding(.top, 6)

            HStack(spacing: 8) {
                textButton(confirmingDelete ? "Confirm" : "Delete Tag",
                           hovering: $deleteHovering) {
                    if confirmingDelete { onDelete() } else { confirmingDelete = true }
                }
                Spacer()
                popupButton("Rename", tint: Theme.accent, hovering: $renameHovering, action: commit)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 320)
        // Same surface treatment as the font-detail card: 18pt continuous
        // corners with the light-grey / soft-white hairline.
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.panelBackground)
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
        )
        // Same hairline as the font-detail card (kept in sync with
        // FontDetailView's card stroke).
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .light ? Color(white: 0.56) : Color.white.opacity(0.8),
                        lineWidth: 1)
        )
        // Circular ✕ in the top-right corner — same design as the Settings
        // close button, sized down for the card. Cancels like ESC / backdrop.
        .overlay(alignment: .topTrailing) {
            PopupCloseButton { onCancel() }
                .padding(.top, 18)
                .padding(.trailing, 18)
        }
        .onAppear { focused = true }
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

    // Bare-text button (no box, no horizontal padding) for Delete Tag /
    // Confirm. contentShape makes the whole label rect (incl. the vertical
    // padding) clickable — without it only the glyph strokes would hit-test.
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

    private func commit() {
        guard let name = MemoStore.normalizeTagName(text) else {
            errorMessage = "Tags can't be empty or contain spaces, commas, or #."
            return
        }
        if name == tag { onCancel(); return }
        onCommit(name)
    }
}

// Same look as the Settings CloseButton (circle-backed ✕), scaled down to sit
// inside a card corner. Shared by the in-app popup cards (rename tag, import
// choice).
struct PopupCloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .offset(y: -0.5)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovering ? Theme.surfaceFillHover : Theme.surfaceFill))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityLabel("Close")
        .help("Close (Esc)")
    }
}
