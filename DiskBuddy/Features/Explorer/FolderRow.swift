import SwiftUI

// MARK: - Explorer file/folder row (rank, icon, counts, share bar, size)

struct FolderRow: View {
    let node: FolderNode
    let rank: Int
    let onTap: () -> Void
    let onInspect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignTokens.Space.m) {
                Text("\(rank)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)
                iconView
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.callout)
                        .fontWeight(node.isDirectory ? .medium : .regular)
                        .lineLimit(1)
                        .foregroundStyle(node.name.hasPrefix(".") ? .secondary : .primary)
                    if node.isSymlink {
                        Text("Symbolic link")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let modified = node.modified {
                        Text(modified.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if node.isSymlink {
                    Image(systemName: "arrow.right.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if node.isDirectory, let count = node.childCount {
                    Text("\(count) items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 8)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(node.percentageOfParent / 100))))
                    }
                }
                .frame(width: 130, height: 9)
                Text(String(format: "%.1f%%", node.percentageOfParent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                Text(node.sizeFormatted)
                    .font(.callout.weight(.medium).monospacedDigit())
                    .frame(width: 82, alignment: .trailing)
                if isHovered {
                    Button(action: onInspect) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, DesignTokens.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(node.path)
    }

    private var iconView: some View {
        Group {
            if node.isDirectory {
                Image(systemName: node.isPackage ? "app.fill" : "folder.fill")
                    .foregroundStyle(node.isPackage ? .blue : .blue.opacity(0.75))
            } else {
                Image(systemName: fileIcon)
                    .foregroundStyle(fileColor)
            }
        }
    }

    private var barColor: Color {
        switch node.percentageOfParent {
        case 50...: return .red.opacity(0.6)
        case 20..<50: return .orange.opacity(0.6)
        case 10..<20: return .yellow.opacity(0.6)
        default: return .blue.opacity(0.4)
        }
    }

    private var fileIcon: String {
        switch node.fileExtension?.lowercased() {
        case "zip", "gz", "tar", "tgz", "bz2", "xz", "7z", "rar": return "archivebox.fill"
        case "dmg", "iso", "img": return "opticaldiscdrive.fill"
        case "app": return "app.fill"
        case "pkg", "mpkg": return "shippingbox.fill"
        case "mov", "mp4", "m4v", "avi", "mkv", "webm": return "film.fill"
        case "mp3", "m4a", "wav", "flac", "aac", "ogg": return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp": return "photo.fill"
        case "pdf": return "doc.richtext.fill"
        case "txt", "md", "rtf", "doc", "docx": return "doc.text.fill"
        case "swift", "py", "js", "ts", "tsx", "jsx", "rb", "go", "rs", "c", "cpp", "h": return "chevron.left.forwardslash.chevron.right"
        case "json", "plist", "xml", "yaml", "yml", "toml": return "doc.plaintext.fill"
        case "csv", "xlsx": return "tablecells.fill"
        case "ttf", "otf", "woff", "woff2": return "textformat"
        default: return "doc.fill"
        }
    }

    private var fileColor: Color {
        switch node.fileExtension?.lowercased() {
        case "zip", "gz", "tar", "tgz", "bz2", "xz", "7z", "rar", "swift", "py", "js", "ts", "tsx", "jsx": return .orange
        case "dmg", "iso", "img": return .purple
        case "mov", "mp4", "m4v", "avi", "mkv", "webm": return .pink
        case "mp3", "m4a", "wav", "flac", "aac", "ogg": return .green
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp": return .yellow
        default: return .secondary
        }
    }
}
