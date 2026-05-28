import SwiftUI
import AppKit
import CoreText

struct FontDetailView: View {
    let family: FontFamily
    let previewText: String
    let onClose: () -> Void

    @EnvironmentObject var favorites: FavoritesStore
    @State private var copied = false

    private var isFavorited: Bool { favorites.contains(family.name) }

    private var sampleText: String {
        previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleArea
            Divider().opacity(0.35)
            weightList
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white, lineWidth: 1)
        )
        .onExitCommand { onClose() }
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
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                // X 버튼
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
                // Favorite
                Button {
                    favorites.toggle(family.name)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isFavorited ? "star.fill" : "star")
                            .font(.system(size: 12))
                        Text(isFavorited ? "Favorited" : "Favorite")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(isFavorited ? Color.accentYellow : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(isFavorited ? Color.accentYellow.opacity(0.08) : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(isFavorited ? Color.accentYellow.opacity(0.4) : Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Copy name
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(family.name, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(copied ? "Copied" : "Copy name")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(copied ? Color.accentYellow : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(copied ? Color.accentYellow.opacity(0.4) : Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Show in Finder
                Button { openInFinder() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                        Text("Show in Finder")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    // MARK: - Weight List

    private var weightList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(family.memberFontNames.enumerated()), id: \.offset) { index, psName in
                    WeightRow(psName: psName, sampleText: sampleText)
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

// MARK: - Weight Row

struct WeightRow: View {
    let psName: String
    let sampleText: String

    private var faceName: String {
        guard let font = NSFont(name: psName, size: 12) else { return psName }
        return (font.fontDescriptor.object(forKey: .face) as? String) ?? psName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(faceName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(psName)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(sampleText)
                .font(.custom(psName, size: 40))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
