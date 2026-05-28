import SwiftUI

struct FontCell: View {
    let family: FontFamily
    let previewText: String
    let fontSize: Double
    let onTap: () -> Void

    @EnvironmentObject var favorites: FavoritesStore
    @State private var hovering = false
    @State private var weightIndex: Int = 0
    @State private var cycleTask: Task<Void, Never>? = nil

    private var isFavorited: Bool { favorites.contains(family.name) }

    private var displayedFontName: String {
        guard !family.memberFontNames.isEmpty else { return family.name }
        let i = weightIndex % family.memberFontNames.count
        return family.memberFontNames[i]
    }

    // Cell height grows with font size: at fontSize=28 → 90pt, at fontSize=56 → 118pt
    private var cellHeight: CGFloat { max(90, CGFloat(fontSize) + 62) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(family.name)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.accentYellow)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                trailingBadge
            }

            Text(previewText.isEmpty ? "The quick brown fox jumps over lazy dog." : previewText)
                .font(.custom(displayedFontName, size: fontSize))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.15), value: weightIndex)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(height: cellHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { isHovering in
            hovering = isHovering
            if isHovering {
                startCycling()
            } else {
                stopCycling()
            }
        }
        .onDisappear { stopCycling() }
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
        if isFavorited { return Color.accentYellow.opacity(0.45) }
        if hovering { return Color.white.opacity(0.35) }
        return Color.white.opacity(0.08)
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if hovering || isFavorited {
            Button {
                favorites.toggle(family.name)
            } label: {
                Image(systemName: isFavorited ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(isFavorited ? Color.accentYellow : Color.secondary)
            }
            .buttonStyle(.plain)
        } else {
            Text(String(format: "%02d", family.weightCount))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.weightBadge)
        }
    }
}
