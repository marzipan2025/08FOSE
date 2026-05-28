import SwiftUI

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
                            .font(.system(size: Theme.sectionHeaderSize, weight: .semibold))
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
