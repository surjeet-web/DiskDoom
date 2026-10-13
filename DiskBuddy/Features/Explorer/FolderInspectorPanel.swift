import SwiftUI
import AppKit

// MARK: - Explorer inspector (Finder/clipboard actions only)

struct FolderInspectorPanel: View {
    let node: FolderNode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
                header
                Divider()
                // WHY: unreadable (permission-denied) nodes carry a 0 size
                // that is an absence of data — label it unknown, never "0 bytes".
                LabeledContent("Size", value: node.sizeDisplay)
                LabeledContent("Share", value: node.shareDisplay)
                if node.isDirectory {
                    LabeledContent("Contents", value: node.childCountDisplay)
                    LabeledContent("Files", value: node.fileCountDisplay)
                }
                LabeledContent("Modified", value: node.modifiedDisplay)
                Text(node.provenanceDisplay).font(.caption).foregroundStyle(.secondary)
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
    @EnvironmentObject var overlays: OverlayStack

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
        VStack(alignment: .leading, spacing: DesignTokens.Space.l) {
            ModalHeader(title: "Inspector", overlayID: "explorer-inspector") {
                dismiss()
            }
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
                    // WHY: unreadable nodes never claim a measured "0 bytes".
                    Text(node.sizeDisplay).fontWeight(.medium).monospacedDigit()
                }
                GridRow {
                    Text("Type").foregroundStyle(.secondary)
                    Text(node.isDirectory ? "Directory" : (node.fileExtension?.uppercased() ?? "File"))
                }
                if node.isDirectory {
                    GridRow {
                        Text("Items").foregroundStyle(.secondary)
                        Text(node.childCountDisplay)
                    }
                }
                if node.isDirectory {
                    GridRow {
                        Text("Files").foregroundStyle(.secondary)
                        Text(node.fileCountDisplay)
                    }
                }
                GridRow {
                    Text("Modified").foregroundStyle(.secondary)
                    Text(node.modifiedDisplay)
                }
                if !node.isUnreadable {
                    GridRow {
                        Text("Share").foregroundStyle(.secondary)
                        Text(node.shareDisplay)
                    }
                }
                if node.isUnreadable {
                    GridRow {
                        Text("Note").foregroundStyle(.secondary)
                        Text("Permission denied — contents not measured").foregroundStyle(.orange)
                    }
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
            Text(node.provenanceDisplay).font(.caption).foregroundStyle(.secondary)
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
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520, minHeight: 400)
        .onAppear { overlays.present("explorer-inspector") }
        .onDisappear { overlays.dismiss("explorer-inspector") }
        }
    }
}
