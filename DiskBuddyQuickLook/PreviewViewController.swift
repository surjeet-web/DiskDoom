import Cocoa
import Quartz
import SwiftUI
import PDFKit
import AVKit
@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

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

// MARK: - Pure Quick Look measurement policy
enum QLMeasurementPolicy {
    struct DuplicateSnapshot: Codable {
        let schemaVersion: Int
        let scannedAt: Date
        let source: String
        let counts: [String: Int]
    }

    static func size(_ bytes: Int64?, measuredAt: Date, source: String, failure: String? = nil) -> Measurement<Int64> {
        if let failure { return .error(reason: failure) }
        guard let bytes, bytes >= 0 else { return .unavailable(reason: "Size metadata missing or invalid") }
        return .available(value: bytes, measuredAt: measuredAt, source: source)
    }

    static func duplicate(data: Data?, path: String, now: Date) -> Measurement<Int> {
        guard let data else { return .unavailable(reason: "No duplicate scan available") }
        guard let snapshot = try? JSONDecoder().decode(DuplicateSnapshot.self, from: data),
              snapshot.schemaVersion == 2, !snapshot.source.isEmpty,
              snapshot.scannedAt <= now else {
            return .unavailable(reason: "Duplicate cache is invalid or has no dated provenance")
        }
        guard let count = snapshot.counts[path], count > 0 else {
            return .unavailable(reason: "Not present in the last duplicate scan")
        }
        // A pathname does not establish identity, existence or contents now.
        return .stale(value: count, measuredAt: snapshot.scannedAt, source: snapshot.source)
    }
}
// MARK: - End pure Quick Look measurement policy

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
    let logicalBytes: Measurement<Int64>   // file size
    let onDiskBytes: Measurement<Int64>    // allocated (zero is valid for sparse files)
    let isCompressed: Bool    // measured UF_COMPRESSED filesystem flag
    let created: Date?
    let modified: Date?
    let whereFrom: String?    // com.apple.metadata:kMDItemWhereFroms
    let quarantined: Bool     // com.apple.quarantine
    let quarantineAgent: String?
    let duplicateCopies: Measurement<Int> // last-scan evidence, never current verification
    let imageInfo: ImageInfo?
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
        let path = url.path
        let now = Date()
        let logical: Measurement<Int64>
        let allocated: Measurement<Int64>
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey])
            logical = QLMeasurementPolicy.size(values.fileSize.map(Int64.init), measuredAt: now, source: "URL fileSize metadata")
            allocated = QLMeasurementPolicy.size(values.totalFileAllocatedSize.map(Int64.init), measuredAt: now, source: "URL allocated-size metadata")
        } catch {
            logical = QLMeasurementPolicy.size(nil, measuredAt: now, source: "URL fileSize metadata", failure: error.localizedDescription)
            allocated = QLMeasurementPolicy.size(nil, measuredAt: now, source: "URL allocated-size metadata", failure: error.localizedDescription)
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let created = attrs?[.creationDate] as? Date
        let modified = attrs?[.modificationDate] as? Date
        var fileStat = stat()
        let isCompressed = lstat(path, &fileStat) == 0
            && (fileStat.st_flags & UInt32(UF_COMPRESSED)) != 0

        let type = UTType(filenameExtension: url.pathExtension)
            ?? (try? url.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
                .flatMap { UTType($0) }
            ?? .data
        let kind = type.localizedDescription ?? "Document"

        // Provenance.
        let (whereFrom, quarantined, agent) = provenance(path: path)

        // Duplicate status from the shared scan index.
        let duplicateCopies = DuplicateIndex.lookup(path: path, now: now)

        // Media metadata.
        // Byte-budget every read. `String(contentsOf:)` materialises the
        // WHOLE file, and this extension is registered for `public.data`,
        // i.e. it is offered every file on the system. A 40 GB .dmg or a
        // multi-GB disk image got the extension jetsam-killed, so Finder
        // showed a generic preview failure. (This path also runs twice per
        // preview: once in collect, once in PreviewPayload.build.)
        let physical = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let smallEnoughToRead = physical > 0 && physical < Self.maxInlineTextBytes
        let imageInfo = physical > 0 && physical < Self.maxImageMetadataBytes ? imageMetadata(url: url) : nil
        // A/V metadata is NOT gathered here. Since macOS 13, AVFoundation
        // requires the async loading APIs (load(.duration)/load(.tracks));
        // QLPreviewRootView loads it from its .task once the synchronous UI is
        // on screen, so the preview appears immediately.
        var pdfPages: Int?
        var textPreview: String?
        if type.conforms(to: .pdf), smallEnoughToRead,
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
            isCompressed: isCompressed,
            created: created,
            modified: modified,
            whereFrom: whereFrom,
            quarantined: quarantined,
            quarantineAgent: agent,
            duplicateCopies: duplicateCopies,
            imageInfo: imageInfo,
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
        static func lookup(path: String, now: Date) -> Measurement<Int> {
            let fileData = groupContainer.flatMap { try? Data(contentsOf: $0.appendingPathComponent("duplicates.json")) }
            let data = fileData ?? UserDefaults(suiteName: "group.com.diskdoom")?.data(forKey: "duplicates-index")
            return QLMeasurementPolicy.duplicate(data: data, path: path, now: now)
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
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] else { return nil }
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

    // MARK: A/V metadata (AVFoundation async loading APIs)

    /// Loads duration/resolution/bitrate via the async AVFoundation loading
    /// APIs (macOS 13 deprecated the synchronous `asset.duration`,
    /// `tracks(withMediaType:)`, `naturalSize`, `preferredTransform` and
    /// `estimatedDataRate` properties). Called from the preview view's
    /// `.task`, off the synchronous UI setup path.
    static func loadAVInfo(url: URL) async -> AVInfo? {
        guard !Task.isCancelled else { return nil }
        let asset = AVURLAsset(url: url)
        return await withTaskCancellationHandler {
            await loadAVInfo(asset: asset)
        } onCancel: {
            asset.cancelLoading()
        }
    }

    private static func loadAVInfo(asset: AVURLAsset) async -> AVInfo? {
        guard !Task.isCancelled else { return nil }
        guard let (duration, tracks) = try? await asset.load(.duration, .tracks) else { return nil }
        guard !Task.isCancelled else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds > 0, seconds.isFinite, seconds < Double(Int.max) else { return nil }

        let durationText = seconds >= 3_600
            ? String(format: "%d:%02d:%02d", Int(seconds) / 3_600, (Int(seconds) % 3_600) / 60, Int(seconds) % 60)
            : String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)

        var resolution: String?
        var bitrate: Double = 0
        var hasVideo = false
        for track in tracks {
            guard !Task.isCancelled else { return nil }
            switch track.mediaType {
            case .video:
                hasVideo = true
                guard let (naturalSize, transform, rate) = try? await track.load(.naturalSize, .preferredTransform, .estimatedDataRate) else { continue }
                let size = naturalSize.applying(transform)
                resolution = String(format: "%.0f × %.0f", abs(size.width), abs(size.height))
                bitrate += Double(rate)
            case .audio:
                if let rate = try? await track.load(.estimatedDataRate) {
                    bitrate += Double(rate)
                }
            default:
                break
            }
        }
        guard !Task.isCancelled else { return nil }
        return AVInfo(
            duration: durationText,
            resolution: resolution,
            bitrate: bitrate > 0 ? String(format: "%.1f Mbps", bitrate / 1_000_000) : nil,
            hasVideo: hasVideo)
    }
}

// MARK: - Preview payload (what to render per file kind)

enum PreviewPayload {
    static let maxPreviewPixelSize = 1_200

    case image(NSImage)
    case pdf(Data) // rendered pages via PDFKit view
    case video // poster + A/V specs loaded async by the view (macOS 13 async AV APIs)
    case text(String)
    case generic

    static func build(url: URL, kind: String) -> PreviewPayload {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        // Same byte budget as QLMetadata.collect — this whole file was being
        // read into memory twice per preview.
        let physical = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if type.conforms(to: .image), physical > 0, physical < QLMetadata.maxImageMetadataBytes,
           let image = Self.thumbnail(url: url) {
            return .image(image)
        }
        if type.conforms(to: .pdf) {
            return physical > 0 && physical < QLMetadata.maxInlineTextBytes ? .pdf(Data()) : .generic
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            // Poster frame + duration are loaded asynchronously by the view's
            // .task (same byte budget as before — very large videos skipped).
            return physical > 0 && physical < QLMetadata.maxVideoMetadataBytes ? .video : .generic
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

    /// Decode only a bounded thumbnail, not a full-resolution NSImage. The
    /// encoded byte gate alone cannot bound a highly compressed image's pixels.
    static func thumbnail(url: URL, maxPixel: Int = 1_200) -> NSImage? {
        let pixelLimit = min(max(maxPixel, 1), maxPreviewPixelSize)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelLimit,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              cgImage.width <= pixelLimit, cgImage.height <= pixelLimit else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Poster frame at ~10% into the video (async; falls back to nil).
    /// Returns a Sendable CGImage — the caller (main actor) builds the NSImage.
    static func videoPoster(url: URL) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPreviewPixelSize, height: maxPreviewPixelSize)
        return await withTaskCancellationHandler {
            guard !Task.isCancelled,
                  let duration = try? await asset.load(.duration),
                  !Task.isCancelled else { return nil }
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { return nil }
            let time = CMTime(seconds: min(0.5, seconds * 0.1), preferredTimescale: 600)
            guard !Task.isCancelled,
                  let result = try? await generator.image(at: time),
                  !Task.isCancelled,
                  result.image.width <= maxPreviewPixelSize,
                  result.image.height <= maxPreviewPixelSize else { return nil }
            return result.image
        } onCancel: {
            asset.cancelLoading()
            generator.cancelAllCGImageGeneration()
        }
    }
}

// MARK: - SwiftUI views

struct QLPreviewRootView: View {
    let content: QLPreviewContent
    @State private var pdfDocument: PDFDocument?
    @State private var avInfo: QLMetadata.AVInfo?
    @State private var poster: NSImage?
    @State private var mediaLoadID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            MetadataSidebar(content: content, avInfo: avInfo)
                .frame(width: 280)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if case .pdf = content.preview {
                pdfDocument = PDFDocument(url: content.url)
            }
        }
        .task(id: content.url) {
            await loadMediaInfo()
        }
    }

    /// The synchronous UI (poster placeholder, sidebar shell) is on screen by
    /// the time this runs. AVFoundation's async loading APIs then fill in the
    /// poster frame and duration/resolution/bitrate — gated by the same byte
    /// budget the old synchronous collector used. `.task` also cancels
    /// automatically if the preview disappears before loading finishes.
    @MainActor
    private func loadMediaInfo() async {
        guard !Task.isCancelled else { return }
        let loadID = UUID()
        mediaLoadID = loadID
        avInfo = nil
        poster = nil
        let url = content.url
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        guard type.conforms(to: .audiovisualContent) else { return }
        let physical = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard physical > 0, physical < QLMetadata.maxVideoMetadataBytes else { return }
        let info = await QLMetadata.loadAVInfo(url: url)
        guard !Task.isCancelled, mediaLoadID == loadID else { return }
        avInfo = info
        if case .video = content.preview,
           let cgImage = await PreviewPayload.videoPoster(url: url) {
            guard !Task.isCancelled, mediaLoadID == loadID else { return }
            poster = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
        case .video:
            ZStack {
                if let poster {
                    Image(nsImage: poster)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // Placeholder while the async poster/duration load runs.
                    Image(systemName: "film")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .overlay(alignment: .bottomTrailing) {
                if let av = avInfo {
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
    let avInfo: QLMetadata.AVInfo? // filled in asynchronously by the root view
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
                    sizeRow("File size", metadata.logicalBytes)
                    sizeRow("On disk", metadata.onDiskBytes)
                    if metadata.isCompressed {
                        Label("Filesystem-compressed",
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
                if let copies = metadata.duplicateCopies.recordedValue,
                   let date = metadata.duplicateCopies.measuredAt {
                    Label("Last scan recorded \(copies) copies",
                          systemImage: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(date.formatted(date: .abbreviated, time: .shortened)) · \(metadata.duplicateCopies.source ?? "Duplicate scan")\nNot verified against the current file or copies.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(metadata.duplicateCopies.reason ?? "Run a duplicate scan in DiskDoom to check")
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
                if let av = avInfo {
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

    private func sizeRow(_ label: String, _ measurement: Measurement<Int64>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            row(label, measurement.availableValue.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "Unknown · \(measurement.statusLabel)")
            if let date = measurement.measuredAt, let source = measurement.source {
                Text("\(source) · \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            } else if let reason = measurement.reason {
                Text(reason).font(.caption2).foregroundStyle(.tertiary)
            }
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
