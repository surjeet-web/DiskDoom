import SwiftUI

// MARK: - Explorer breadcrumb bar

struct BreadcrumbBar: View {
    let items: [FolderExplorerEngine.BreadcrumbItem]
    let onSelect: (FolderExplorerEngine.BreadcrumbItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 4) {
                            if index == 0 {
                                Image(systemName: "internaldrive.fill")
                                    .font(.caption2)
                            }
                            Text(item.name)
                                .font(.caption)
                                .fontWeight(index == items.count - 1 ? .semibold : .regular)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            index == items.count - 1 ? Color.accentColor.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help(item.path)
                }
            }
            .padding(.horizontal, DesignTokens.Space.m)
            .padding(.vertical, 5)
        }
        .background(Color.secondary.opacity(0.03))
    }
}
