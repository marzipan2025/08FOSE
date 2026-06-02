import SwiftUI
import AppKit
import CoreText

struct FontDetailView: View {
    let family: FontFamily
    let previewText: String
    let onClose: () -> Void

    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var memoExpanded: Bool = false
    @State private var closeHovering = false
    @State private var memoHeaderHovering = false

    // Light mode uses lighter shadows (30% of the dark-mode strength).
    private var shadowScale: Double { colorScheme == .light ? 0.3 : 1.0 }

    private var isFavorited: Bool { favorites.contains(family.name) }

    private var sampleText: String {
        previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText
    }

    // Hairline between header / weight list / memo. White in dark mode (lifts
    // off the dark bg), black at the same strength in light mode (sits darker
    // than its surroundings).
    private var detailDivider: Color {
        colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.12)
    }

    private var memoBinding: Binding<String> {
        Binding(
            get: { memos.note(for: family.name) },
            set: { memos.setNote($0, for: family.name) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleArea
            Rectangle()
                .fill(detailDivider)
                .frame(height: 1)
            if memoExpanded {
                expandedMemoArea
            } else {
                weightList
                    .frame(maxHeight: .infinity)
                Rectangle()
                .fill(detailDivider)
                .frame(height: 1)
                collapsedMemoArea
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                // Light mode: card body is brighter than the global panel bg
                // (0.92 → 0.952, white-ward 40%) so the card lifts off the grid.
                .fill(colorScheme == .light ? Color(white: 0.952) : Theme.panelBackground)
                .shadow(color: .black.opacity(0.55 * shadowScale), radius: 14, x: 0, y: 10)
                .shadow(color: .black.opacity(0.75 * shadowScale), radius: 60, x: 0, y: 38)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .light ? Color(white: 0.56) : Color.white, lineWidth: 1)
        )
        .onExitCommand {
            if memoExpanded {
                withAnimation(.easeOut(duration: 0.2)) { memoExpanded = false }
            } else {
                onClose()
            }
        }
    }

    // MARK: - Memo (collapsed: single-line + expand toggle)

    private var collapsedMemoArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            memoHeader(
                icon: "chevron.up",
                help: "Expand memo"
            ) {
                withAnimation(.easeOut(duration: 0.2)) { memoExpanded = true }
            }
            ZStack(alignment: .leading) {
                if memos.note(for: family.name).isEmpty {
                    Text("Add a note…")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.memoAccent)
                        .allowsHitTesting(false)
                }
                TextField("", text: memoBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.memoAccent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(memoAreaBackground)
    }

    // Memo strip background. Light mode uses a brighter solid (≈0.93,
    // white-ward 40%) instead of the global memoSurface overlay.
    private var memoAreaBackground: Color {
        colorScheme == .light ? Color(white: 0.93) : Theme.memoSurface
    }

    // MARK: - Memo (expanded: fills body)

    private var expandedMemoArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            memoHeader(
                icon: "chevron.down",
                help: "Collapse memo"
            ) {
                withAnimation(.easeOut(duration: 0.2)) { memoExpanded = false }
            }
            ZStack(alignment: .topLeading) {
                if memos.note(for: family.name).isEmpty {
                    Text("Add a note…")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.memoAccent)
                        .allowsHitTesting(false)
                }
                MemoEditor(
                    text: memoBinding,
                    fontSize: 17,
                    lineSpacing: 17 * 0.5,
                    textColor: NSColor(Theme.memoAccent)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(memoAreaBackground)
    }

    private func memoHeader(icon: String, help: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text("Memo")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(memoHeaderHovering ? Theme.surfaceFillHover : Theme.surfaceFill)
                    )
            }
            .buttonStyle(.plain)
            .onHover { memoHeaderHovering = $0 }
            .help(help)
        }
    }

    // MARK: - Title Area

    private var titleArea: some View {
        // Header darkening gradient is full strength in dark mode, very faint
        // in light.
        let gradientScale = colorScheme == .light ? 0.06 : 1.0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(family.name)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text("\(family.weightCount) weight\(family.weightCount == 1 ? "" : "s")")
                        .font(.system(size: Theme.bodySize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .unifiedGeometry()

                Spacer(minLength: 16)

                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        // Same color rule as the memo chevron button: secondary
                        // glyph on a surfaceFill background (denser on hover).
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(closeHovering ? Theme.surfaceFillHover : Theme.surfaceFill))
                }
                .buttonStyle(.plain)
                .onHover { closeHovering = $0 }
                .accessibilityLabel("Close detail")
                .help("Close detail")
            }

            HStack(spacing: 8) {
                ActionButton(
                    icon: nil,
                    label: isFavorited ? "Favorited" : "Favorite",
                    active: isFavorited
                ) { favorites.toggle(family.name) }

                ActionButton(
                    icon: copied ? "checkmark" : nil,
                    label: copied ? "Copied" : "Copy name",
                    active: copied
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(family.name, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                }

                ActionButton(icon: "folder", label: "Show in Finder", active: false) {
                    openInFinder()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(
            // Subtle top-down darkening of the header, independent of the
            // wallpaper. Clipped into the card by the view's outer clipShape.
            LinearGradient(
                colors: [Color.black.opacity(0.10 * gradientScale),
                         Color.black.opacity(0.30 * gradientScale)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Weight List

    private var weightList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(family.memberFontNames.enumerated()), id: \.offset) { index, psName in
                    WeightRow(psName: psName, sampleText: sampleText, sampleSize: CGFloat(vm.weightRowFontSize))
                    if index < family.memberFontNames.count - 1 {
                        Divider().opacity(0.15).padding(.horizontal, 24)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func openInFinder() {
        guard let psName = family.memberFontNames.first else { return }
        let descriptor = CTFontDescriptorCreateWithNameAndSize(psName as CFString, 0)
        guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Geometry Helper

private extension View {
    /// Treats a view's subtree as a single geometry unit so children animate
    /// together (instead of background/text sliding independently) during an
    /// ancestor's matchedGeometryEffect resize. Falls back to no-op pre-macOS 14.
    @ViewBuilder
    func unifiedGeometry() -> some View {
        if #available(macOS 14.0, *) {
            self.geometryGroup()
        } else {
            self
        }
    }
}

// MARK: - Weight Row

struct WeightRow: View {
    let psName: String
    let sampleText: String
    let sampleSize: CGFloat

    private var faceName: String {
        guard let font = NSFont(name: psName, size: 12) else { return psName }
        return (font.fontDescriptor.object(forKey: .face) as? String) ?? psName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(faceName)
                    .font(.system(size: Theme.bodySize, weight: .medium))
                    .foregroundStyle(.primary)
                Text(psName)
                    .font(.system(size: Theme.smallSize).monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            WrappingPreviewLabel(text: sampleText, fontName: psName, fontSize: sampleSize)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Title-area action button (Favorite / Copy name / Show in Finder) with a
// light hover state: the fill grows a little denser on rollover.
private struct ActionButton: View {
    let icon: String?
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: Theme.bodySize))
                }
                Text(label).font(.system(size: Theme.bodySize))
            }
            .foregroundStyle(active ? Theme.accent : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(active ? Theme.accent.opacity(0.4) : Theme.border, lineWidth: 1)
            )
            .unifiedGeometry()
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
    }

    private var fillColor: Color {
        if active { return Theme.accent.opacity(hovering ? 0.16 : 0.08) }
        return hovering ? Theme.surfaceFillHover : Theme.surfaceFill
    }
}
