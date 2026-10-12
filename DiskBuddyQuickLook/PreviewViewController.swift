import Cocoa
import Quartz
import SwiftUI
import PDFKit
import AVKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Feature 10: Quick Look preview extension with DiskDoom metadata
//
// Registered for public.data (all files). Renders a real preview for the
// common kinds (images with EXIF, PDF, video poster + specs, audio, text,
// everything else as icon) plus a DiskDoom metadata sidebar: sizes with
// APFS compression state, dates/age, provenance (where-froms + quarantine),
// and duplicate status from the shared scan index.

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 520))
    }

    func loadPreviewView(at url: URL, completionHandler handler: @escaping (NSView?, Error?) -> Void) {
        let metadata = QLMetadata.collect(url: url)
        let content = QLPreviewContent(url: url, metadata: metadata)
        let host = NSHostingView(rootView: QLPreviewRootView(content: content))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        handler(host, nil)
    }
}

// MARK: - Metadata model

struct QLPreviewContent {
    let url: URL
    let metadata: QLMetadata
    let preview: PreviewPayload

    init(url: URL, metadata: QLMetadata) {
        self.url = url
        self.metadata = metadata
        self.preview = PreviewPayload.build(url: url, kind: metadata.kind)
    }
}

struct QLMetadata {
    let name: String
    let path: String
    let kind: String          // UTType description
    let logicalBytes: Int64   // file size
    let onDiskBytes: Int64    // allocated (post APFS compression)
    let isCompressed: Bool    // allocated < logical
    let created: Date?
    let modified: Date?
    let whereFrom: String?    // com.apple.metadata:kMDItemWhereFroms
    let quarantined: Bool     // com.apple.quarantine
    let quarantineAgent: String?
    let duplicateCopies: Int? // shared index; nil = not scanned
    let imageInfo: ImageInfo?
    let avInfo: AVInfo?
    let pdfPages: Int?
    let textPreview: String?

    struct ImageInfo {
        let pixelWidth: Int
        let pixelHeight: Int
        let dpi: Double?
        let colorModel: String?
        let camera: String?
        let iso: String?
        let exposure: String?
        let focalLength: String?
        let taken: String?
    }

    struct AVInfo {
        let duration: String
        let resolution: String?
        let bitrate: String?
        let hasVideo: Bool
    }

    var ageText: String? {
        guard let modified else { return nil }
        let days = Int(Date().timeIntervalSince(modified) / 86_400)
        if days < 1 { return "today" }
        if days == 1 { return "1 day ago" }
        if days < 30 { return "\(days) days ago" }
        if days < 365 { return "\(days / 30) months ago" }
        return "\(days / 365) years ago"
    }

    // MARK: Collector

    /// Byte budgets for preview generation. A QuickLook extension runs under a
    /// hard memory limit; reading an unbounded file gets it jetsam-killed and
    /// Finder reports a generic preview failure. Registered for `public.data`,
    /// so this extension is offered every file on the system.
    static let maxInlineTextBytes = 2_000_000
    static let maxImageMetadataBytes = 32_000_000
    static let maxVideoMetadataBytes = 512_000_000

    static func collect(url: URL) -> QLMetadata {
        let fm = FileManager.default
        let path = url.path
        var logical: Int64 = 0
        var allocated: Int64 = 0
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey]) {
            logical = Int64(values.fileSize ?? 0)
            allocated = Int64(values.totalFileAllocatedSize ?? 0)
            if allocated == 0 { allocated = logical }
        }
        if logical == 0, let attrs = try? fm.attributesOfItem(atPath: path) {
            logical = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }

        let attrs = try? fm.attributesOfItem(atPath: path)
        let created = attrs?[.creationDate] as? Date
        let modified = attrs?[.modificationDate] as? Date

        let type = UTType(filenameExtension: url.pathExtension)
            ?? (try? url.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
                .flatMap { UTType($0) }
            ?? .data
        let kind = type.localizedDescription ?? "Document"

        // Provenance.
        let (whereFrom, quarantined, agent) = provenance(path: path)

        // Duplicate status from the shared scan index.
        let duplicateCopies = DuplicateIndex.lookup(path: path)

        // Media metadata.
        // Byte-budget every read. `String(contentsOf:)` materialises the
        // WHOLE file, and this extension is registered for `public.data`,
        // i.e. it is offered every file on the system. A 40 GB .dmg or a
        // multi-GB disk image got the extension jetsam-killed, so Finder
        // showed a generic preview failure. (This path also runs twice per
        // preview: once in collect, once in PreviewPayload.build.)
        let physical = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let smallEnoughToRead = physical > 0 && physical < Self.maxInlineTextBytes
        let imageInfo = physical < Self.maxImageMetadataBytes ? imageMetadata(url: url) : nil
        let avInfo = physical < Self.maxVideoMetadataBytes ? avMetadata(url: url) : nil
        var pdfPages: Int?
        var textPreview: String?
        if type.conforms(to: .pdf), physical < Self.maxInlineTextBytes,
           let document = PDFDocument(url: url) {
            pdfPages = document.pageCount
        } else if smallEnoughToRead,
                  let plain = try? String(contentsOf: url, encoding: .utf8) {
            if isLikelyText(type: type, sample: plain) {
                textPreview = String(plain.prefix(4_000))
            }
        }

        return QLMetadata(
            name: url.lastPathComponent,
            path: path,
            kind: kind,
            logicalBytes: logical,
            onDiskBytes: allocated,
            isCompressed: allocated + 4_096 < logical,
            created: created,
            modified: modified,
            whereFrom: whereFrom,
            quarantined: quarantined,
            quarantineAgent: agent,
            duplicateCopies: duplicateCopies,
            imageInfo: imageInfo,
            avInfo: avInfo,
            pdfPages: pdfPages,
            textPreview: textPreview)
    }

    private static func isLikelyText(type: UTType, sample: String) -> Bool {
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .plainText) { return true }
        // Heuristic: no NUL bytes in the first 1KB → treat as text.
        let head = sample.prefix(1_024)
        return !head.contains("\0")
    }

    // MARK: Provenance (xattrs — no TCC needed)

    private static func provenance(path: String) -> (whereFrom: String?, quarantined: Bool, agent: String?) {
        var whereFrom: String?
        if let data = readXattr("com.apple.metadata:kMDItemWhereFroms", path: path),
           let list = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String],
           let first = list.first {
            whereFrom = first
        }
        var quarantined = false
        var agent: String?
        if let data = readXattr("com.apple.quarantine", path: path),
           let value = String(data: data, encoding: .utf8) {
            quarantined = true
            let fields = value.split(separator: ";").map(String.init)
            if fields.count >= 3, !fields[2].isEmpty {
                agent = fields[2]
            }
        }
        return (whereFrom, quarantined, agent)
    }

    private static func readXattr(_ name: String, path: String) -> Data? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { buffer in
            getxattr(path, name, buffer.baseAddress, length, 0, 0)
        }
        return result == length ? data : nil
    }

    // MARK: Duplicate status (shared app-group index written by the app)

    private enum DuplicateIndex {
        static func lookup(path: String) -> Int? {
            guard let url = groupContainer?.appendingPathComponent("duplicates.json"),
                  let data = try? Data(contentsOf: url),
                  let index = try? JSONDecoder().decode([String: Int].self, from: data) else { return nil }
            return index[path]
        }

        static var groupContainer: URL? {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.diskdoom") {
                return url
            }
            let direct = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/group.com.diskdoom", isDirectory: true)
            return FileManager.default.fileExists(atPath: direct.path) ? direct : nil
        }
    }

    // MARK: Image metadata (ImageIO — EXIF)

    private static func imageMetadata(url: URL) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard width > 0, height > 0 else { return nil }

        let dpi = (props[kCGImagePropertyDPIWidth] as? Double)
        let colorModel = (props[kCGImagePropertyColorModel] as? String)

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let make = (tiff?[kCGImagePropertyTIFFMake] as? String) ?? (exif?[kCGImagePropertyExifLensMake] as? String)
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String) ?? (exif?[kCGImagePropertyExifLensModel] as? String)
        let camera = [make, model].compactMap { $0 }.joined(separator: " ")
        let iso = exif?[kCGImagePropertyExifISOSpeed] as? Int
        let exposure = exif?[kCGImagePropertyExifExposureTime] as? Double
        let focal = exif?[kCGImagePropertyExifFocalLength] as? Double
        let taken = exif?[kCGImagePropertyExifDateTimeOriginal] as? String

        return ImageInfo(
            pixelWidth: width,
            pixelHeight: height,
            dpi: dpi,
            colorModel: colorModel,
            camera: camera.isEmpty ? nil : camera,
            iso: iso.map { "ISO \($0)" },
            exposure: exposure.map {
                $0 < 1 ? String(format: "1/%.0f s", 1 / $0) : String(format: "%.1f s", $0)
            },
            focalLength: focal.map { String(format: "%.0f mm", $0) },
            taken: taken)
    }

    // MARK: A/V metadata (AVFoundation, synchronous)

    private static func avMetadata(url: URL) -> AVInfo? {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration > 0, duration.isFinite else { return nil }

        let durationText = duration >= 3_600
            ? String(format: "%d:%02d:%02d", Int(duration) / 3_600, (Int(duration) % 3_600) / 60, Int(duration) % 60)
            : String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)

        var resolution: String?
        var bitrate: Double = 0
        var hasVideo = false
        for track in asset.tracks(withMediaType: .video) {
            hasVideo = true
            let size = track.naturalSize.applying(track.preferredTransform)
            resolution = String(format: "%.0f × %.0f", abs(size.width), abs(size.height))
            bitrate += Double(track.estimatedDataRate)
        }
        for track in asset.tracks(withMediaType: .audio) {
            bitrate += Double(track.estimatedDataRate)
        }
        return AVInfo(
            duration: durationText,
            resolution: resolution,
            bitrate: bitrate > 0 ? String(format: "%.1f Mbps", bitrate / 1_000_000) : nil,
            hasVideo: hasVideo)
    }
}

// MARK: - Preview payload (what to render per file kind)

enum PreviewPayload {
    case image(NSImage)
    case pdf(Data) // rendered pages via PDFKit view
    case videoPoster(NSImage)
    case text(String)
    case generic

    static func build(url: URL, kind: String) -> PreviewPayload {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        // Same byte budget as QLMetadata.collect — this whole file was being
        // read into memory twice per preview.
        let physical = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if type.conforms(to: .image), physical < QLMetadata.maxImageMetadataBytes,
           let image = Self.thumbnail(url: url) {
            return .image(image)
        }
        if type.conforms(to: .pdf) {
            return .pdf(Data())
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            if physical < QLMetadata.maxVideoMetadataBytes,
               let poster = Self.videoPoster(url: url) {
                return .videoPoster(poster)
            }
            return .generic
        }
        if physical > 0, physical < QLMetadata.maxInlineTextBytes,
           let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            let head = String(text.prefix(1_024))
            if !head.contains("\0") {
                return .text(String(text.prefix(4_000)))
            }
        }
        return .generic
    }

    /// Downsampled image (max ~1200px) — respects QL extension memory limits.
    static func thumbnail(url: URL, maxPixel: Int = 1_200) -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Poster frame at ~10% into the video (sync; falls back to nil).
    static func videoPoster(url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        let time = CMTime(seconds: min(0.5, CMTimeGetSeconds(asset.duration) * 0.1), preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - SwiftUI views

struct QLPreviewRootView: View {
    let content: QLPreviewContent
    @State private var pdfDocument: PDFDocument?

    var body: some View {
        HStack(spacing: 0) {
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            MetadataSidebar(content: content)
                .frame(width: 280)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if case .pdf = content.preview {
                pdfDocument = PDFDocument(url: content.url)
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        switch content.preview {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(16)
        case .pdf:
            if let document = pdfDocument {
                PDFViewRepresentable(document: document)
                    .padding(8)
            } else {
                ProgressView().padding()
            }
        case .videoPoster(let poster):
            Image(nsImage: poster)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(16)
                .overlay(alignment: .bottomTrailing) {
                    if let av = content.metadata.avInfo {
                        Label(av.duration, systemImage: "play.circle.fill")
                            .font(.callout)
                            .padding(6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(12)
                    }
                }
        case .text(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
        case .generic:
            VStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: content.metadata.path))
                    .resizable()
                    .frame(width: 128, height: 128)
                Text(content.metadata.kind)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }
}

private struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.document = document
    }
}

// MARK: - Metadata sidebar

private struct MetadataSidebar: View {
    let content: QLPreviewContent
    private var metadata: QLMetadata { content.metadata }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Header.
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.name)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(metadata.kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                // Sizes + APFS compression.
                SectionLabel("Size")
                VStack(spacing: 6) {
                    row("File size", ByteCountFormatter.string(fromByteCount: metadata.logicalBytes, countStyle: .file))
                    row("On disk", ByteCountFormatter.string(fromByteCount: metadata.onDiskBytes, countStyle: .file))
                    if metadata.isCompressed {
                        Label("APFS-compressed — saves \(ByteCountFormatter.string(fromByteCount: metadata.logicalBytes - metadata.onDiskBytes, countStyle: .file))",
                              systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                // Dates + age.
                SectionLabel("Dates")
                VStack(spacing: 6) {
                    if let created = metadata.created {
                        row("Created", created.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let modified = metadata.modified {
                        row("Modified", "\(modified.formatted(date: .abbreviated, time: .omitted))\(metadata.ageText.map { " · \($0)" } ?? "")")
                    }
                }

                // Provenance.
                SectionLabel("Provenance")
                VStack(spacing: 6) {
                    if let from = metadata.whereFrom {
                        row("Downloaded from", from)
                    }
                    if let agent = metadata.quarantineAgent {
                        row("Via", agent)
                    }
                    if metadata.quarantined && metadata.quarantineAgent == nil {
                        row("Quarantined", "Yes")
                    }
                    if metadata.whereFrom == nil && !metadata.quarantined {
                        Text("No download history recorded")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Duplicate status.
                SectionLabel("Duplicates")
                if let copies = metadata.duplicateCopies {
                    Label(copies > 1 ? "\(copies) byte-identical copies exist" : "Unique — no duplicates",
                          systemImage: copies > 1 ? "doc.on.doc.fill" : "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(copies > 1 ? .orange : .green)
                } else {
                    Text("Run a duplicate scan in DiskDoom to check")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Image EXIF.
                if let exif = metadata.imageInfo {
                    SectionLabel("Image")
                    VStack(spacing: 6) {
                        row("Dimensions", "\(exif.pixelWidth) × \(exif.pixelHeight) px")
                        if let dpi = exif.dpi, dpi > 0 {
                            row("Resolution", String(format: "%.0f DPI", dpi))
                        }
                        if let colorModel = exif.colorModel {
                            row("Color", colorModel)
                        }
                        if let camera = exif.camera {
                            row("Camera", camera)
                        }
                        if let taken = exif.taken {
                            row("Taken", taken)
                        }
                        HStack(spacing: 8) {
                            if let iso = exif.iso { chip(iso) }
                            if let exposure = exif.exposure { chip(exposure) }
                            if let focal = exif.focalLength { chip(focal) }
                        }
                    }
                }

                // A/V info.
                if let av = metadata.avInfo {
                    SectionLabel("Media")
                    VStack(spacing: 6) {
                        row("Duration", av.duration)
                        if let resolution = av.resolution {
                            row("Resolution", resolution)
                        }
                        if let bitrate = av.bitrate {
                            row("Bitrate", bitrate)
                        }
                    }
                }

                // PDF / text extras.
                if let pages = metadata.pdfPages {
                    SectionLabel("Document")
                    row("Pages", "\(pages)")
                }

                Spacer(minLength: 12)
                Text("DiskDoom · \(content.url.path)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) {
        self.text = text
    }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }
}
