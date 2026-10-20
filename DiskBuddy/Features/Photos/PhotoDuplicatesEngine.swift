import Foundation
import Photos
import AppKit
import CryptoKit

// MARK: - Photos Library duplicate engine (PhotoKit)
//
// The reference app integrates with the Photos app: it finds exact and
// similar photos, moves them into a dedicated "Trash" album, and can delete
// them from the library. This engine uses PhotoKit instead of AppleScript so
// it works without Automation permission prompts for the Photos app itself.

enum PhotoLibraryAccessState: Equatable {
    case unknown
    case denied
    case limited
    case authorized

    var label: String {
        switch self {
        case .unknown: return "Not requested"
        case .denied: return "Denied"
        case .limited: return "Limited access"
        case .authorized: return "Authorized"
        }
    }
}

enum PhotoScanMode: String, CaseIterable, Identifiable {
    case similar
    case exact

    var id: String { rawValue }
    var title: String { self == .similar ? "Similar Photos" : "Exact Duplicates" }
    var detail: String {
        self == .similar
            ? "Perceptual hash — catches re-encodes, resizes, and minor edits."
            : "Full SHA-256 of each original — byte-identical only."
    }
}

struct PhotoAssetInfo: Identifiable, Sendable {
    let id: String
    let filename: String
    let bytes: Int64
    let width: Int
    let height: Int
    let creationDate: Date?
    let hash: UInt64?
    let contentHash: String?

    var dimensionsLabel: String { "\(width) × \(height)" }
    var megapixels: Double { Double(width * height) / 1_000_000 }
}

struct PhotoDuplicateGroup: Identifiable {
    enum Kind { case exact, similar }

    let id: String
    let kind: Kind
    let assets: [PHAsset]
    let items: [PhotoAssetInfo]
    let reclaimable: Int64
    let maxDistance: Int

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var title: String {
        items.first.map { "\($0.filename) + \(items.count - 1) more" } ?? "Photo set"
    }
}

struct PhotoRemovalResult {
    let movedToAlbum: Int
    let deletedFromLibrary: Int
    let bytes: Int64
    let failures: [String]
}

@MainActor
final class PhotoDuplicatesEngine: ObservableObject {
    @Published private(set) var access: PhotoLibraryAccessState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var phase = ""
    @Published private(set) var groups: [PhotoDuplicateGroup] = []
    @Published private(set) var scannedAssets = 0
    @Published private(set) var totalAssets = 0
    @Published private(set) var lastError: String?

    @Published var threshold: Int = 8
    @Published var minimumDimension: Int = 128
    var albumTitle = "Trash (DiskBuddy)"

    private var scanTask: Task<Void, Never>?
    private var runID = UUID()

    init() {
        access = Self.currentAccess()
    }

    // MARK: Authorization

    nonisolated static func currentAccess() -> PhotoLibraryAccessState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    func requestAccess() async {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
        access = Self.map(status)
    }

    private nonisolated static func map(_ status: PHAuthorizationStatus) -> PhotoLibraryAccessState {
        switch status {
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    // MARK: Scan

    func scan(mode: PhotoScanMode) {
        guard !isScanning else { return }
        scanTask?.cancel()
        let id = UUID()
        runID = id
        isScanning = true
        groups = []
        progress = 0
        lastError = nil
        phase = "Requesting Photos access…"
        let threshold = max(0, min(32, threshold))
        let minimumDimension = max(1, minimumDimension)

        scanTask = Task { [weak self] in
            guard let self else { return }
            if self.access == .unknown || self.access == .denied {
                await self.requestAccess()
            }
            guard self.access == .authorized || self.access == .limited else {
                self.isScanning = false
                self.lastError = "Photos access is required. Grant it in System Settings → Privacy & Security → Photos."
                self.phase = "No access"
                return
            }
            self.phase = "Fetching photos…"
            let assets = await Task.detached(priority: .userInitiated) {
                Self.fetchImageAssets()
            }.value
            guard !Task.isCancelled, self.runID == id else { return }
            self.totalAssets = assets.count
            self.scannedAssets = 0
            self.phase = mode == .exact ? "Hashing originals…" : "Comparing thumbnails…"

            var infos: [(asset: PHAsset, info: PhotoAssetInfo)] = []
            for (index, asset) in assets.enumerated() {
                if Task.isCancelled { break }
                let resource = Self.primaryResource(for: asset)
                let bytes = Self.fileSize(of: resource)
                let filename = resource?.originalFilename ?? (asset.value(forKey: "filename") as? String) ?? "Photo"
                let hash = mode == .similar ? await Self.thumbnailHash(for: asset) : nil
                let contentHash = mode == .exact ? await Self.contentHash(for: asset) : nil
                if mode == .exact && contentHash == nil { continue }
                if mode == .similar && hash == nil { continue }
                let info = PhotoAssetInfo(
                    id: asset.localIdentifier, filename: filename, bytes: bytes,
                    width: asset.pixelWidth, height: asset.pixelHeight,
                    creationDate: asset.creationDate, hash: hash, contentHash: contentHash)
                infos.append((asset, info))
                if index % 5 == 0 {
                    self.scannedAssets = index + 1
                    self.progress = Double(index + 1) / Double(max(assets.count, 1)) * 0.95
                }
            }
            guard !Task.isCancelled, self.runID == id else { return }

            self.phase = "Building groups…"
            let built: [PhotoDuplicateGroup]
            if mode == .exact {
                built = Self.exactGroups(from: infos)
            } else {
                built = Self.similarGroups(from: infos, threshold: threshold,
                                           minimumDimension: minimumDimension)
            }
            guard !Task.isCancelled, self.runID == id else { return }
            self.groups = built
            self.scannedAssets = infos.count
            self.progress = 1
            self.isScanning = false
            self.phase = built.isEmpty
                ? "No \(mode == .exact ? "exact duplicates" : "similar photos") found"
                : "\(built.count) groups · \(built.reduce(0) { $0 + $1.reclaimable }.fileSizeString) potential"
        }
    }

    func cancel() {
        runID = UUID()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        phase = "Stopped"
    }

    // MARK: Removal

    func moveToTrashAlbum(assets: [PHAsset]) async -> PhotoRemovalResult {
        guard !assets.isEmpty else {
            return PhotoRemovalResult(movedToAlbum: 0, deletedFromLibrary: 0, bytes: 0, failures: [])
        }
        let ids = Set(assets.map(\.localIdentifier))
        let bytes = groups.flatMap(\.items).filter { ids.contains($0.id) }.reduce(0) { $0 + $1.bytes }
        var failures: [String] = []
        do {
            try await addToAlbum(assets)
            return PhotoRemovalResult(movedToAlbum: assets.count, deletedFromLibrary: 0,
                                      bytes: bytes, failures: failures)
        } catch {
            failures.append(error.localizedDescription)
            return PhotoRemovalResult(movedToAlbum: 0, deletedFromLibrary: 0,
                                      bytes: 0, failures: failures)
        }
    }

    /// Deletes the assets from the Photos library. They remain in the Photos
    /// "Recently Deleted" album, exactly like the reference app's flow.
    func deleteFromLibrary(assets: [PHAsset]) async -> PhotoRemovalResult {
        guard !assets.isEmpty else {
            return PhotoRemovalResult(movedToAlbum: 0, deletedFromLibrary: 0, bytes: 0, failures: [])
        }
        let ids = Set(assets.map(\.localIdentifier))
        let bytes = groups.flatMap(\.items).filter { ids.contains($0.id) }.reduce(0) { $0 + $1.bytes }
        var failures: [String] = []
        do {
            try await addToAlbum(assets)
            try await deleteAssets(assets)
            return PhotoRemovalResult(movedToAlbum: assets.count, deletedFromLibrary: assets.count,
                                      bytes: bytes, failures: failures)
        } catch {
            failures.append(error.localizedDescription)
            return PhotoRemovalResult(movedToAlbum: 0, deletedFromLibrary: 0,
                                      bytes: 0, failures: failures)
        }
    }

    private func addToAlbum(_ assets: [PHAsset]) async throws {
        let album = try await findOrCreateAlbum(title: albumTitle)
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
                request.addAssets(assets as NSArray)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? Self.genericError("Could not move photos to the album."))
                }
            })
        }
    }

    private func deleteAssets(_ assets: [PHAsset]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? Self.genericError("Could not delete photos."))
                }
            })
        }
    }

    private func findOrCreateAlbum(title: String) async throws -> PHAssetCollection {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", title)
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        if let album = existing.firstObject { return album }
        var placeholder: PHObjectPlaceholder?
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                placeholder = request.placeholderForCreatedAssetCollection
            }, completionHandler: { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? Self.genericError("Could not create the Trash album."))
                }
            })
        }
        guard let identifier = placeholder?.localIdentifier else {
            throw Self.genericError("Could not create the Trash album.")
        }
        let fetched = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil)
        guard let album = fetched.firstObject else {
            throw Self.genericError("Could not open the Trash album.")
        }
        return album
    }

    private nonisolated static func genericError(_ message: String) -> NSError {
        NSError(domain: "DiskBuddy.Photos", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: PhotoKit helpers

    private nonisolated static func fetchImageAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        let fetch = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(min(fetch.count, 60_000))
        fetch.enumerateObjects { asset, index, stop in
            if index >= 60_000 { stop.pointee = true; return }
            assets.append(asset)
        }
        return assets
    }

    private nonisolated static func primaryResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { $0.type == .photo || $0.type == .fullSizePhoto }
            ?? resources.first { $0.type == .alternatePhoto }
            ?? resources.first
    }

    private nonisolated static func fileSize(of resource: PHAssetResource?) -> Int64 {
        guard let resource else { return 0 }
        if let number = resource.value(forKey: "fileSize") as? NSNumber {
            return max(0, number.int64Value)
        }
        return 0
    }

    private nonisolated static func thumbnailHash(for asset: PHAsset) async -> UInt64? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        let gate = ResumeGate()
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 128, height: 128),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
                guard gate.claim() else { return }
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                guard let cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: SimilarPhotoFinder.differenceHash(cgImage))
            }
        }
    }

    private nonisolated static func contentHash(for asset: PHAsset) async -> String? {
        guard let resource = primaryResource(for: asset) else { return nil }
        let accumulator = SHA256Accumulator()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in accumulator.update(data) },
                completionHandler: { error in
                    continuation.resume(returning: error == nil ? accumulator.finalize() : nil)
                })
        }
    }

    // MARK: Grouping

    private nonisolated static func exactGroups(
        from infos: [(asset: PHAsset, info: PhotoAssetInfo)]
    ) -> [PhotoDuplicateGroup] {
        var buckets: [String: [(asset: PHAsset, info: PhotoAssetInfo)]] = [:]
        for entry in infos {
            guard let hash = entry.info.contentHash else { continue }
            buckets[hash, default: []].append(entry)
        }
        var groups: [PhotoDuplicateGroup] = []
        for (hash, entries) in buckets where entries.count >= 2 {
            let sorted = entries.sorted { $0.info.filename < $1.info.filename }
            let items = sorted.map(\.info)
            let total = items.reduce(Int64(0)) { $0 + $1.bytes }
            let largest = items.map(\.bytes).max() ?? 0
            groups.append(PhotoDuplicateGroup(
                id: "exact:\(hash.prefix(12))", kind: .exact,
                assets: sorted.map(\.asset), items: items,
                reclaimable: max(0, total - largest), maxDistance: 0))
        }
        groups.sort { $0.reclaimable > $1.reclaimable }
        return groups
    }

    private nonisolated static func similarGroups(
        from infos: [(asset: PHAsset, info: PhotoAssetInfo)],
        threshold: Int, minimumDimension: Int
    ) -> [PhotoDuplicateGroup] {
        let entries = infos.filter {
            guard let hash = $0.info.hash else { return false }
            _ = hash
            return $0.info.width >= minimumDimension && $0.info.height >= minimumDimension
        }
        guard entries.count > 1 else { return [] }

        var buckets: [Int: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            let ratio = entry.info.height > 0
                ? Double(entry.info.width) / Double(entry.info.height) : 1
            buckets[Int((ratio * 20).rounded()), default: []].append(index)
        }
        var union = PhotoUnionFind(count: entries.count)
        var comparisons = 0
        let maxComparisons = 12_000_000
        for key in buckets.keys.sorted() {
            if Task.isCancelled { break }
            var candidates = buckets[key] ?? []
            candidates += buckets[key - 1] ?? []
            candidates += buckets[key + 1] ?? []
            guard candidates.count > 1 else { continue }
            for i in 0..<(candidates.count - 1) {
                for j in (i + 1)..<candidates.count {
                    comparisons += 1
                    if comparisons > maxComparisons { break }
                    let a = candidates[i], b = candidates[j]
                    guard union.find(a) != union.find(b),
                          let hashA = entries[a].info.hash,
                          let hashB = entries[b].info.hash else { continue }
                    guard (hashA ^ hashB).nonzeroBitCount <= threshold else { continue }
                    let maxA = Double(max(entries[a].info.width, entries[a].info.height))
                    let maxB = Double(max(entries[b].info.width, entries[b].info.height))
                    guard maxA / max(1, maxB) > 0.2 else { continue }
                    union.union(a, b)
                }
                if comparisons > maxComparisons { break }
            }
            if comparisons > maxComparisons { break }
        }

        var members: [Int: [Int]] = [:]
        for index in entries.indices { members[union.find(index), default: []].append(index) }
        var groups: [PhotoDuplicateGroup] = []
        for indices in members.values where indices.count >= 2 {
            let sorted = indices.map { entries[$0] }.sorted { $0.info.filename < $1.info.filename }
            let items = sorted.map(\.info)
            let total = items.reduce(Int64(0)) { $0 + $1.bytes }
            let largest = items.map(\.bytes).max() ?? 0
            var maxDistance = 0
            if sorted.count <= 40 {
                for i in 0..<(sorted.count - 1) {
                    for j in (i + 1)..<sorted.count {
                        if let a = sorted[i].info.hash,
                           let b = sorted[j].info.hash {
                            maxDistance = max(maxDistance, (a ^ b).nonzeroBitCount)
                        }
                    }
                }
            }
            groups.append(PhotoDuplicateGroup(
                id: "similar:\(indices.sorted().first ?? 0)",
                kind: .similar,
                assets: sorted.map(\.asset),
                items: items,
                reclaimable: max(0, total - largest),
                maxDistance: maxDistance))
        }
        groups.sort { $0.reclaimable > $1.reclaimable }
        return groups
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

private final class SHA256Accumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var hasher = SHA256()

    func update(_ data: Data) {
        lock.lock()
        hasher.update(data: data)
        lock.unlock()
    }

    func finalize() -> String {
        lock.lock()
        let digest = hasher.finalize()
        lock.unlock()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct PhotoUnionFind {
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
