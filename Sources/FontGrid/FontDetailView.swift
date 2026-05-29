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
    @State private var copied = false
    @State private var memoExpanded: Bool = false

    private var isFavorited: Bool { favorites.contains(family.name) }

    private var sampleText: String {
        previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText
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
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
            if memoExpanded {
                expandedMemoArea
            } else {
                weightList
                    .frame(maxHeight: .infinity)
                Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                collapsedMemoArea
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.panelBackground)
                .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 10)
                .shadow(color: .black.opacity(0.75), radius: 60, x: 0, y: 38)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white, lineWidth: 1)
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
                icon: "arrow.up.left.and.arrow.down.right",
                help: "Expand memo"
            ) {
                withAnimation(.easeOut(duration: 0.2)) { memoExpanded = true }
            }
            ZStack(alignment: .leading) {
                if memos.note(for: family.name).isEmpty {
                    Text("Add a note…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.memoAccent)
                        .allowsHitTesting(false)
                }
                TextField("", text: memoBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.memoAccent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.memoSurface)
    }

    // MARK: - Memo (expanded: fills body)

    private var expandedMemoArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            memoHeader(
                icon: "arrow.down.right.and.arrow.up.left",
                help: "Collapse memo"
            ) {
                withAnimation(.easeOut(duration: 0.2)) { memoExpanded = false }
            }
            ZStack(alignment: .topLeading) {
                if memos.note(for: family.name).isEmpty {
                    Text("Add a note…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.memoAccent)
                        .allowsHitTesting(false)
                }
                MemoEditor(
                    text: memoBinding,
                    fontSize: 13,
                    lineSpacing: 13 * 0.5,
                    textColor: NSColor(Theme.memoAccent)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.memoSurface)
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
                            .fill(Theme.surfaceFill)
                    )
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }

    // MARK: - Title Area

    private var titleArea: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                actionButton(
                    icon: isFavorited ? "circle.fill" : "circle",
                    label: isFavorited ? "Favorited" : "Favorite",
                    active: isFavorited
                ) { favorites.toggle(family.name) }

                actionButton(
                    icon: copied ? "checkmark" : "doc.on.doc",
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

                actionButton(icon: "folder", label: "Show in Finder", active: false) {
                    openInFinder()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private func actionButton(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: Theme.bodySize))
                Text(label).font(.system(size: Theme.bodySize))
            }
            .foregroundStyle(active ? Theme.accent : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(active ? Theme.accent.opacity(0.08) : Theme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(active ? Theme.accent.opacity(0.4) : Theme.border, lineWidth: 1)
            )
            .unifiedGeometry()
        }
        .buttonStyle(.plain)
        .fixedSize()
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
            Text(sampleText)
                .font(.custom(psName, size: sampleSize))
                .foregroundStyle(.primary)
                .lineSpacing(sampleSize * 0.3)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

