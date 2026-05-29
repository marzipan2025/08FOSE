import SwiftUI

struct FontCell: View {
    let family: FontFamily
    let previewText: String
    let fontSize: Double
    var onHoverChange: (Bool) -> Void = { _ in }
    let onTap: () -> Void

    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var memos: MemoStore
    @State private var hovering = false
    @State private var weightIndex: Int = 0
    @State private var cycleTask: Task<Void, Never>? = nil

    private var isFavorited: Bool { favorites.contains(family.name) }
    private var hasMemo: Bool { memos.hasNote(for: family.name) }

    private var displayedFontName: String {
        guard !family.memberFontNames.isEmpty else { return family.name }
        return family.memberFontNames[weightIndex % family.memberFontNames.count]
    }

    private var cellHeight: CGFloat { Theme.cellHeight(fontSize: fontSize) }

    private var resolvedPreviewText: String {
        previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText
    }

    var body: some View {
        Color.clear
            .frame(height: cellHeight)
            .overlay(alignment: .topLeading) {
                headerRow
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
            }
            .overlay(alignment: .bottomLeading) {
                Text(resolvedPreviewText)
                    .font(.custom(displayedFontName, size: fontSize))
                    .lineSpacing(fontSize * 0.3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .alignmentGuide(.bottom) { d in d[.lastTextBaseline] + 24 }
                    .animation(.easeInOut(duration: 0.15), value: weightIndex)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.cellSurface)
                    .shadow(
                        color: .black.opacity(hovering ? 0.75 : 0),
                        radius: hovering ? 14 : 0,
                        x: 0,
                        y: hovering ? 16 : 0
                    )
                    .shadow(
                        color: .black.opacity(hovering ? 0.90 : 0),
                        radius: hovering ? 80 : 0,
                        x: 0,
                        y: hovering ? 70 : 0
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    hovering = isHovering
                }
                if isHovering { startCycling() } else { stopCycling() }
                onHoverChange(isHovering)
            }
            .onDisappear { stopCycling() }
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            Text(family.name)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            trailingBadge
        }
    }

    private func startCycling() {
        cycleTask?.cancel()
        weightIndex = 0
        guard family.memberFontNames.count > 1 else { return }
        cycleTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                weightIndex = (weightIndex + 1) % family.memberFontNames.count
            }
        }
    }

    private func stopCycling() {
        cycleTask?.cancel()
        cycleTask = nil
        weightIndex = 0
    }

    private var borderColor: Color {
        if hasMemo { return Theme.memoAccent }
        if isFavorited { return Theme.accent.opacity(0.45) }
        if hovering { return Theme.borderHover }
        return Theme.border
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if hovering || isFavorited || hasMemo {
            HStack(spacing: 3) {
                if hasMemo {
                    Circle()
                        .fill(Theme.memoAccent)
                        .frame(width: 9, height: 9)
                }
                if hovering || isFavorited {
                    Button { favorites.toggle(family.name) } label: {
                        ZStack {
                            if isFavorited {
                                Circle().fill(Theme.accent)
                            } else {
                                Circle().fill(Color.white.opacity(0.12))
                                Circle().strokeBorder(Color.secondary, lineWidth: 1)
                            }
                        }
                        .frame(width: 9, height: 9)
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 9, height: 9)
                }
            }
            .offset(x: 1, y: 1)
        } else {
            Text(String(format: "%02d", family.weightCount))
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(Theme.weightBadge)
        }
    }
}
