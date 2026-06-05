import SwiftUI
import AppKit

struct PanelSection<Content: View>: View {
    let title: String?
    let trailing: AnyView?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String? = nil,
        trailing: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            if title != nil || trailing != nil {
                HStack(spacing: 8) {
                    if let title {
                        Text(title.uppercased())
                            .font(.system(size: Theme.sectionHeaderSize, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    trailing
                }
            }
            content()
        }
        .padding(.horizontal, Theme.panelHPadding)
        .padding(.vertical, Theme.panelVPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PanelHDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }
}

struct PanelVDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1)
            .ignoresSafeArea()
    }
}

struct ResizableVDivider: View {
    enum Edge { case left, right }

    @Binding var width: Double
    @Binding var dragStartWidth: Double?
    let minWidth: Double
    let maxWidth: Double
    let edge: Edge

    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || dragStartWidth != nil ? Theme.borderHover : Theme.divider)
            .frame(width: 1)
            .ignoresSafeArea()
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        hovering = isHovering
                        if isHovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if dragStartWidth == nil {
                                    dragStartWidth = width
                                }
                                guard let base = dragStartWidth else { return }
                                let delta = Double(edge == .left
                                    ? value.translation.width
                                    : -value.translation.width)
                                width = min(maxWidth, max(minWidth, base + delta))
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )
            )
    }
}
