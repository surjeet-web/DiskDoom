import SwiftUI
import AppKit

// MARK: - Explorer inspector (Finder/clipboard actions only)

struct FolderInspectorPanel: View {
    let node: FolderNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
                header
                Divider()
                LabeledContent("Size", value: node.sizeFormatted)
                if node.percentageOfParent > 0 {
                    LabeledContent("Share", value: String(format: "%.1f%%", node.percentageOfParent))
                }
                if let count = node.childCount {
                    LabeledContent("Contents", value: "\(count) items")
                }
                if let count = node.fileCount {
                    LabeledContent("Files", value: "\(count)")
                }
                if let modified = node.modified {
                    LabeledContent("Modified", value: modified.formatted(date: .long, time: .shortened))
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(node.path)
                        .font(.caption)
                        .monospaced()
                        .textSelection(.enabled)
                }
                Spacer(minLength: 20)
                VStack(spacing: DesignTokens.Space.s) {
                    Button {
                        NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(node.path, forType: .string)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(node.isDirectory ? "Folder" : (node.fileExtension?.uppercased() ?? "File"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FolderInspectorSheet: View {
    let node: FolderNode
    let engine: FolderExplorerEngine

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.l) {
            HStack {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name)
                        .font(.title2.weight(.semibold))
                    Text(node.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                GridRow {
                    Text("Size").foregroundStyle(.secondary)
                    Text(node.sizeFormatted).fontWeight(.medium).monospacedDigit()
                }
                GridRow {
                    Text("Type").foregroundStyle(.secondary)
                    Text(node.isDirectory ? "Directory" : (node.fileExtension?.uppercased() ?? "File"))
                }
                if let count = node.childCount {
                    GridRow {
                        Text("Items").foregroundStyle(.secondary)
                        Text("\(count)")
                    }
                }
                if let count = node.fileCount {
                    GridRow {
                        Text("Files").foregroundStyle(.secondary)
                        Text("\(count)")
                    }
                }
                if let modified = node.modified {
                    GridRow {
                        Text("Modified").foregroundStyle(.secondary)
                        Text(modified.formatted(date: .long, time: .shortened))
                    }
                }
                GridRow {
                    Text("Share").foregroundStyle(.secondary)
                    Text(String(format: "%.1f%% of parent", node.percentageOfParent))
                }
                if node.isSymlink {
                    GridRow {
                        Text("Note").foregroundStyle(.secondary)
                        Text("Symbolic link").foregroundStyle(.orange)
                    }
                }
                if node.isPackage {
                    GridRow {
                        Text("Package").foregroundStyle(.secondary)
                        Text("Treated as leaf").foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            HStack {
                Button("Open in Finder") { engine.openInFinder(node.path) }
                    .buttonStyle(.borderedProminent)
                Button("Copy Path") { engine.copyPath(node.path) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520, minHeight: 360)
    }
}
