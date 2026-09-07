import SwiftUI

// MARK: - Explorer quick-path card

struct QuickPathCard: View {
    let quickPath: FolderExplorerEngine.QuickPath
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Space.m) {
                Image(systemName: quickPath.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quickPath.name)
                        .font(.callout.weight(.medium))
                    Text(quickPath.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Space.m)
            .background(
                isHovered ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
