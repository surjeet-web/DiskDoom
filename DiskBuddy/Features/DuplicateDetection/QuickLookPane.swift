import SwiftUI
import AppKit
import Quartz

// MARK: - Quick Look preview + metadata inspector
//
// Mirrors the reference app's preview pane: Quick Look for the selected file
// plus real EXIF/TIFF/GPS values. Never fabricates missing fields.

struct QuickLookPane: View {
    let path: String?
    var compact = false

    @State private var metadata: ImageFileMetadata?
    @State private var fileInfo: FileInfo?

    private struct FileInfo {
        let size: Int64
        let created: Date?
        let modified: Date?
        let kind: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let path {
                QuickLookPreview(url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
                    .frame(minHeight: compact ? 160 : 260)
                    .background(Color.black.opacity(0.85))
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                        Text((path as NSString).lastPathComponent)
                            .font(.headline)
                            .lineLimit(2)
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        if let info = fileInfo {
                            metadataRow("Size", info.size.fileSizeString)
                            metadataRow("Kind", info.kind)
                            if let created = info.created {
                                metadataRow("Created", created.formatted(date: .abbreviated, time: .shortened))
                            }
                            if let modified = info.modified {
                                metadataRow("Modified", modified.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        if let metadata {
                            Divider()
                            Text("Image").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            metadataRow("Dimensions", metadata.dimensionsLabel)
                            if metadata.megapixels > 0 {
                                metadataRow("Megapixels", String(format: "%.1f MP", metadata.megapixels))
                            }
                            metadataRow("DPI", metadata.dpiLabel)
                            if metadata.bitDepth > 0 {
                                metadataRow("Bit depth", "\(metadata.bitDepth)")
                            }
                            if !metadata.colorModel.isEmpty {
                                metadataRow("Color", metadata.colorModel)
                            }
                            if let taken = metadata.dateTaken {
                                metadataRow("Taken", taken.formatted(date: .abbreviated, time: .shortened))
                            }
                            if !metadata.cameraMake.isEmpty || !metadata.cameraModel.isEmpty {
                                metadataRow("Camera", "\(metadata.cameraMake) \(metadata.cameraModel)"
                                    .trimmingCharacters(in: .whitespaces))
                            }
                            if !metadata.lensModel.isEmpty {
                                metadataRow("Lens", metadata.lensModel)
                            }
                            if !metadata.exposureTime.isEmpty {
                                metadataRow("Exposure", "\(metadata.exposureTime)s")
                            }
                            if !metadata.fStop.isEmpty {
                                metadataRow("Aperture", "ƒ/\(metadata.fStop)")
                            }
                            if !metadata.iso.isEmpty {
                                metadataRow("ISO", metadata.iso)
                            }
                            if !metadata.focalLength.isEmpty {
                                metadataRow("Focal length", "\(metadata.focalLength) mm")
                            }
                            if let latitude = metadata.latitude, let longitude = metadata.longitude {
                                metadataRow("Location", String(format: "%.5f, %.5f", latitude, longitude))
                            }
                            if !metadata.software.isEmpty {
                                metadataRow("Software", metadata.software)
                            }
                        } else if FileMetadataReader.isImage(path) {
                            Text("No embedded image metadata")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(
                                    (path as NSString).expandingTildeInPath,
                                    inFileViewerRootedAtPath: "")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Open") {
                                NSWorkspace.shared.open(
                                    URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, DesignTokens.Space.xs)
                    }
                    .padding(DesignTokens.Space.m)
                }
            } else {
                VStack(spacing: DesignTokens.Space.m) {
                    Spacer()
                    Image(systemName: "eye")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Select a file to preview")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
        .task(id: path) {
            metadata = nil
            fileInfo = nil
            guard let path else { return }
            let expanded = (path as NSString).expandingTildeInPath
            let loaded = await Task.detached(priority: .utility) { () -> (ImageFileMetadata?, FileInfo?) in
                let meta = FileMetadataReader.read(path: expanded)
                let attrs = try? FileManager.default.attributesOfItem(atPath: expanded)
                let info = FileInfo(
                    size: (attrs?[.size] as? NSNumber)?.int64Value ?? 0,
                    created: attrs?[.creationDate] as? Date,
                    modified: attrs?[.modificationDate] as? Date,
                    kind: (attrs?[.type] as? FileAttributeType) == .typeDirectory
                        ? "Folder" : ((expanded as NSString).pathExtension.uppercased().isEmpty
                            ? "Document" : (expanded as NSString).pathExtension.uppercased()))
                return (meta, info)
            }.value
            guard !Task.isCancelled else { return }
            metadata = loaded.0
            fileInfo = loaded.1
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
