import Foundation
import ImageIO
import CoreGraphics

// MARK: - Similar-photo finder (perceptual dHash + aspect bucketing)
//
// The reference app separates "Exact Duplicates" from "Similar Files" and
// compares photo metadata (dimensions, DPI, EXIF). This engine computes a
// 64-bit difference hash from a 9x8 grayscale thumbnail, then groups images
// whose Hamming distance stays within the user's threshold. Aspect-ratio
// buckets keep the comparison count practical for large libraries.

struct SimilarPhoto: Identifiable, Hashable, Sendable {
    let id: UUID
    let path: String
    let bytes: Int64
    let width: Int
    let height: Int
    let modified: Date
    let hash: UInt64
    let metadata: ImageFileMetadata?

    init(path: String, bytes: Int64, width: Int, height: Int,
         modified: Date, hash: UInt64, metadata: ImageFileMetadata?) {
        self.id = SimilarPhoto.stableID(path)
        self.path = path
        self.bytes = bytes
        self.width = width
        self.height = height
        self.modified = modified
        self.hash = hash
        self.metadata = metadata
    }

    var name: String { (path as NSString).lastPathComponent }
    var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 1 }
    var megapixels: Double { Double(width * height) / 1_000_000 }
    var dpi: Double { metadata?.dpiWidth ?? 0 }
    var dimensionsLabel: String {
        width > 0 && height > 0 ? "\(width) × \(height)" : "Unknown"
    }
    var dateTaken: Date? { metadata?.dateTaken }

    static func stableID(_ path: String) -> UUID {
        var hasher = Hasher()
        hasher.combine("similar:\(path)")
        let value = UInt64(bitPattern: Int64(hasher.finalize()))
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 { bytes[index] = UInt8((value >> (8 * UInt64(index))) & 0xFF) }
        for index in 0..<8 { bytes[8 + index] = UInt8((value >> (8 * UInt64(index))) & 0xFF) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SimilarPhoto, rhs: SimilarPhoto) -> Bool { lhs.id == rhs.id }
}

struct SimilarGroup: Identifiable, Sendable {
    let id: UUID
    let photos: [SimilarPhoto]
    let maxDistance: Int

    init(photos: [SimilarPhoto], maxDistance: Int) {
        self.id = photos.first?.id ?? UUID()
        self.photos = photos
        self.maxDistance = maxDistance
    }

    var totalBytes: Int64 { photos.reduce(0) { $0 + $1.bytes } }
    /// Conservative: only other copies of the largest file are counted.
    var reclaimable: Int64 {
        guard photos.count > 1, let largest = photos.max(by: { $0.bytes < $1.bytes }) else { return 0 }
        return max(0, totalBytes - largest.bytes)
    }
    var largest: SimilarPhoto? { photos.max { $0.bytes < $1.bytes } }
}

@MainActor
final class SimilarPhotoFinder: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var phase = ""
    @Published private(set) var groups: [SimilarGroup] = []
    @Published private(set) var isRunning = false
    @Published private(set) var scannedCount = 0
    @Published private(set) var candidateCount = 0
    @Published private(set) var lastRunRecords = -1

    /// Higher = looser matches. 8 is the reference app's "similar" feel.
    @Published var threshold: Int = 8
    /// Ignore tiny thumbnails/icons that collide at low resolution.
    @Published var minimumDimension: Int = 128
    @Published var minimumBytes: Int64 = 0

    private var task: Task<Void, Never>?
    private var runID = UUID()

    func scan(records: [ScannedRecord], ignoreRules: IgnoreRules?) {
        task?.cancel()
        let id = UUID()
        runID = id
        let threshold = max(0, min(32, threshold))
        let minimumDimension = max(1, minimumDimension)
        let minimumBytes = max(0, minimumBytes)
        let filtered = (ignoreRules?.filter(records) ?? records)
            .filter { !$0.isDirectory }
            .filter { FileMetadataReader.isImage($0.path) }
            .filter { $0.bytes >= minimumBytes }
        isRunning = true
        groups = []
        progress = 0
        phase = "Analyzing \(filtered.count.formatted()) images…"
        scannedCount = 0
        candidateCount = filtered.count

        task = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.findSimilar(records: filtered, threshold: threshold,
                                 minimumDimension: minimumDimension) { done in
                    Task { @MainActor [weak self] in
                        guard let self, self.runID == id else { return }
                        self.progress = done
                        self.scannedCount = Int(done * Double(filtered.count))
                    }
                }
            }.value
            guard let self, !Task.isCancelled, self.runID == id else { return }
            self.groups = result.groups
            self.candidateCount = result.candidateCount
            self.isRunning = false
            self.progress = 1
            self.phase = result.groups.isEmpty
                ? "No similar photos found"
                : "\(result.groups.count) similar groups · \(result.groups.reduce(0) { $0 + $1.reclaimable }.fileSizeString) potential"
            self.lastRunRecords = records.count
        }
    }

    func scan(folder: URL, ignoreRules: IgnoreRules?) {
        task?.cancel()
        let id = UUID()
        runID = id
        isRunning = true
        groups = []
        progress = 0
        phase = "Collecting images in \(folder.lastPathComponent)…"
        let threshold = max(0, min(32, threshold))
        let minimumDimension = max(1, minimumDimension)
        let minimumBytes = max(0, minimumBytes)
        let ignoredPaths = ignoreRules?.ignoredPaths ?? []
        let ignoredExtensions = ignoreRules?.ignoredExtensions ?? []

        task = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                let records = Self.collectImages(in: folder, ignoredPaths: ignoredPaths,
                                                 ignoredExtensions: ignoredExtensions)
                return Self.findSimilar(records: records, threshold: threshold,
                                        minimumDimension: minimumDimension) { done in
                    Task { @MainActor [weak self] in
                        guard let self, self.runID == id else { return }
                        self.progress = done
                        self.scannedCount = Int(done * Double(records.count))
                    }
                }
            }.value
            guard let self, !Task.isCancelled, self.runID == id else { return }
            self.candidateCount = result.candidateCount
            self.groups = result.groups
            self.isRunning = false
            self.progress = 1
            self.phase = result.groups.isEmpty
                ? "No similar photos found"
                : "\(result.groups.count) similar groups · \(result.groups.reduce(0) { $0 + $1.reclaimable }.fileSizeString) potential"
            self.lastRunRecords = -1
        }
    }

    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
        phase = "Stopped"
    }

    // MARK: Work

    private struct ScanOutcome {
        let groups: [SimilarGroup]
        let candidateCount: Int
    }

    nonisolated private static func collectImages(in folder: URL, ignoredPaths: [String],
                                      ignoredExtensions: [String]) -> [ScannedRecord] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var records: [ScannedRecord] = []
        var visited = 0
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            visited += 1
            if visited > 250_000 { break }
            let path = url.path
            if ignoredPaths.contains(where: { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }) {
                enumerator.skipDescendants()
                continue
            }
            guard FileMetadataReader.isImage(path) else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            if ignoredExtensions.contains(ext) { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true else { continue }
            let bytes = Int64(values.fileSize ?? 0)
            records.append(ScannedRecord(
                path: path, bytes: bytes, physical: bytes,
                modified: values.contentModificationDate ?? .distantPast,
                isDirectory: false, category: .userData))
        }
        return records
    }

    nonisolated private static func findSimilar(records: [ScannedRecord], threshold: Int,
                                    minimumDimension: Int,
                                    report: @escaping @Sendable (Double) -> Void) -> ScanOutcome {
        var photos: [SimilarPhoto] = []
        photos.reserveCapacity(records.count)
        for (index, record) in records.enumerated() {
            if Task.isCancelled { break }
            if index % 4 == 0 { report(Double(index) / Double(max(records.count, 1)) * 0.7) }
            guard let analysis = analyze(path: record.path) else { continue }
            guard analysis.width >= minimumDimension, analysis.height >= minimumDimension else { continue }
            photos.append(SimilarPhoto(
                path: record.path, bytes: record.bytes,
                width: analysis.width, height: analysis.height,
                modified: record.modified, hash: analysis.hash,
                metadata: analysis.metadata))
        }
        guard photos.count > 1 else {
            report(1)
            return ScanOutcome(groups: [], candidateCount: photos.count)
        }
        report(0.75)

        // Aspect buckets: 5% ratio bands. Compare with neighbouring bands so
        // a pair on a boundary is still considered.
        var buckets: [Int: [Int]] = [:]
        for (index, photo) in photos.enumerated() {
            let key = Int((photo.aspectRatio * 20).rounded())
            buckets[key, default: []].append(index)
        }
        var union = UnionFind(count: photos.count)
        var comparisons = 0
        let maxComparisons = 12_000_000
        var keys = Array(buckets.keys).sorted()
        for key in keys {
            if Task.isCancelled { break }
            var candidates: [Int] = buckets[key] ?? []
            candidates += buckets[key - 1] ?? []
            candidates += buckets[key + 1] ?? []
            if candidates.count < 2 { continue }
            for i in 0..<(candidates.count - 1) {
                for j in (i + 1)..<candidates.count {
                    comparisons += 1
                    if comparisons > maxComparisons { break }
                    let a = candidates[i], b = candidates[j]
                    guard union.find(a) != union.find(b) else { continue }
                    let distance = hamming(photos[a].hash, photos[b].hash)
                    guard distance <= threshold else { continue }
                    // Reject wildly different resolution pairs that happen to
                    // hash alike (e.g. a postage-stamp icon and a wallpaper).
                    let ratio = Double(max(photos[a].width, photos[a].height))
                        / Double(max(1, max(photos[b].width, photos[b].height)))
                    guard ratio > 0.2 else { continue }
                    union.union(a, b)
                }
                if comparisons > maxComparisons { break }
            }
            if comparisons > maxComparisons { break }
        }
        report(0.9)

        var members: [Int: [Int]] = [:]
        for index in photos.indices {
            members[union.find(index), default: []].append(index)
        }
        var groups: [SimilarGroup] = []
        for indices in members.values where indices.count >= 2 {
            if Task.isCancelled { break }
            let groupPhotos = indices.map { photos[$0] }.sorted { $0.path < $1.path }
            var maxDistance = 0
            for i in 0..<(groupPhotos.count - 1) {
                for j in (i + 1)..<groupPhotos.count {
                    maxDistance = max(maxDistance, hamming(groupPhotos[i].hash, groupPhotos[j].hash))
                }
                if groupPhotos.count > 40 { break }
            }
            groups.append(SimilarGroup(photos: groupPhotos, maxDistance: maxDistance))
        }
        groups.sort { $0.reclaimable > $1.reclaimable }
        report(1)
        return ScanOutcome(groups: groups, candidateCount: photos.count)
    }

    private struct Analysis {
        let hash: UInt64
        let width: Int
        let height: Int
        let metadata: ImageFileMetadata?
    }

    nonisolated private static func analyze(path: String) -> Analysis? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = intValue(properties?[kCGImagePropertyPixelWidth])
        let height = intValue(properties?[kCGImagePropertyPixelHeight])
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        guard let hash = differenceHash(image) else { return nil }
        return Analysis(hash: hash, width: width, height: height,
                        metadata: FileMetadataReader.read(path: path))
    }

    nonisolated static func differenceHash(_ image: CGImage) -> UInt64? {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let space = CGColorSpace(name: CGColorSpace.linearGray) ?? CGColorSpaceCreateDeviceGray()
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: space,
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var hash: UInt64 = 0
        var bit = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] < pixels[y * width + x + 1] {
                    hash |= UInt64(1) << UInt64(bit)
                }
                bit += 1
            }
        }
        return hash
    }

    nonisolated private static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }

    nonisolated private static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}

private struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ value: Int) -> Int {
        var value = value
        while parent[value] != value {
            parent[value] = parent[parent[value]]
            value = parent[value]
        }
        return value
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a), rootB = find(b)
        guard rootA != rootB else { return }
        if rank[rootA] < rank[rootB] {
            parent[rootA] = rootB
        } else if rank[rootA] > rank[rootB] {
            parent[rootB] = rootA
        } else {
            parent[rootB] = rootA
            rank[rootA] += 1
        }
    }
}
