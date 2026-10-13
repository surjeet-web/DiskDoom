import Foundation

/// Cooperative cancellation flag shared between an owner (main actor) and a
/// detached directory walk.
///
/// WHY: `Task.isCancelled` read *inside* `Task.detached { … }` reports the
/// detached task's own flag, which nobody ever sets — so every "Cancel" in the
/// app was a no-op for the walk actually doing the work, and pressing "Rescan"
/// left a second full walk hammering the disk alongside the first. The owner
/// keeps a handle to the token and flips it explicitly; the walk polls it.
final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }

    /// Convenience for call sites that have no token (tests, one-shot probes).
    static let never = ScanCancellation()
}

// MARK: - D4 Developer Cache Manager (REAL filesystem scan, Foundation only)
//
// Scans a catalogue of ~50 well-known tool cache locations, measuring what
// actually exists: bytes, file count, last modified. Each item carries a
// risk level and (where a dedicated tool exists) the official clean command.
// Cleaning routes through the shared cleanup queue (Trash) — never direct
// delete. Docker.raw stays manual (VM disk).

struct DevCacheItem: Identifiable {
    let id = UUID()
    let kind: DevCacheKind
    let name: String // display name (tool or project dir)
    let path: String
    let bytes: Int64
    let project: String?
    let fileCount: Int
    let lastModified: Date?
    let riskLevel: RiskLevel

    enum DevCacheKind: String, CaseIterable {
        case xcode, node, swiftpm, homebrew, docker, git, python, rust
        case go, java, android, unity, vagrant, dotnet, ruby, php, ci

        var label: String {
            switch self {
            case .xcode: return "Xcode"
            case .node: return "Node.js"
            case .swiftpm: return "SwiftPM / CocoaPods"
            case .homebrew: return "Homebrew"
            case .docker: return "Docker"
            case .git: return "Git Repos"
            case .python: return "Python"
            case .rust: return "Rust"
            case .go: return "Go"
            case .java: return "Java / JVM"
            case .android: return "Android"
            case .unity: return "Unity"
            case .vagrant: return "Vagrant / VMs"
            case .dotnet: return ".NET"
            case .ruby: return "Ruby"
            case .php: return "PHP"
            case .ci: return "CI / Build"
            }
        }

        var symbol: String {
            switch self {
            case .xcode: return "hammer.fill"
            case .node: return "shippingbox.fill"
            case .swiftpm: return "cube.fill"
            case .homebrew: return "mug.fill"
            case .docker: return "shippingbox"
            case .git: return "folder.fill.badge.gearshape"
            case .python: return "chevron.left.forwardslash.chevron.right"
            case .rust: return "gearshape.2.fill"
            case .go: return "building.2.fill"
            case .java: return "cup.and.saucer.fill"
            case .android: return "antenna.radiowaves.left.and.right"
            case .unity: return "cube.transparent.fill"
            case .vagrant: return "internaldrive.fill"
            case .dotnet: return "circle.grid.3x3.fill"
            case .ruby: return "diamond.fill"
            case .php: return "elephant.fill"
            case .ci: return "wrench.and.screwdriver.fill"
            }
        }
    }

    enum RiskLevel: Equatable {
        case safe        // auto-rebuilds quickly
        case safeSlow    // safe, rebuild takes time
        case caution     // inspect first
        case dangerous   // never offer to clean

        var label: String {
            switch self {
            case .safe: return "Safe — auto-rebuilds"
            case .safeSlow: return "Safe — rebuild is slow"
            case .caution: return "Check first"
            case .dangerous: return "Don't delete"
            }
        }

        var shortLabel: String {
            switch self {
            case .safe: return "Safe"
            case .safeSlow: return "Safe (slow)"
            case .caution: return "Check first"
            case .dangerous: return "Don't delete"
            }
        }

        var colorName: String {
            switch self {
            case .safe: return "green"
            case .safeSlow: return "yellow"
            case .caution: return "orange"
            case .dangerous: return "red"
            }
        }
    }

    var sizeFormatted: String { ByteFormatting.format(bytes) }

    /// Cleanable via the cleanup queue (Trash). Dangerous items are never.
    var isSafeToClean: Bool { riskLevel == .safe || riskLevel == .safeSlow }

    /// Official clean command when a dedicated tool exists (nil = just Trash).
    var cleanCommand: String? { DevCacheEngine.cleanCommand(for: name, path: path) }
}

// Main-confined publishes; heavy measurement runs detached.
final class DevCacheEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var items: [DevCacheItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedCount = 0
    private var task: Task<Void, Never>?
    /// Flipped explicitly by `cancel()` — `Task.isCancelled` inside the
    /// detached walk is always false (see ScanCancellation).
    private var token = ScanCancellation()
    /// Synchronous re-entrancy guard. `isScanning` is published asynchronously,
    /// so without this a second Rescan press (or a launch job racing the view's
    /// .task) started a *second* full walk of the catalogue.
    private let stateLock = NSLock()
    private var walkInFlight = false

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var safeBytes: Int64 { items.filter(\.isSafeToClean).reduce(0) { $0 + $1.bytes } }

    func scan() {
        let alreadyRunning = stateLock.withLock { () -> Bool in
            guard !walkInFlight else { return true }
            walkInFlight = true
            return false
        }
        guard !alreadyRunning else { return }

        task?.cancel()
        token.cancel()
        let token = ScanCancellation()
        self.token = token
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isScanning = true
                self.scannedCount = 0
            }
            let found = await Task.detached {
                Self.scanSync(token: token, report: { _ in })
            }.value
            guard !token.isCancelled else {
                await MainActor.run {
                    self.isScanning = false
                    self.stateLock.withLock { self.walkInFlight = false }
                }
                return
            }
            await MainActor.run {
                defer { self.stateLock.withLock { self.walkInFlight = false } }
                guard !token.isCancelled else {
                    self.isScanning = false
                    return
                }
                self.items = found.sorted { $0.bytes > $1.bytes }
                self.isScanning = false
            }
        }
    }

    func cancel() {
        token.cancel()
        task?.cancel()
        task = nil
    }

    // MARK: Catalogue of tool caches (fixed paths — no home crawl)

    private struct Candidate {
        let kind: DevCacheItem.DevCacheKind
        let name: String
        let subpath: String // relative to home
        let project: String?
        let risk: DevCacheItem.RiskLevel
    }

    private static func candidates(home: String) -> [Candidate] {
        [
            // Xcode / Apple toolchain
            .init(kind: .xcode, name: "DerivedData", subpath: "Library/Developer/Xcode/DerivedData", project: nil, risk: .safeSlow),
            .init(kind: .xcode, name: "Archives", subpath: "Library/Developer/Xcode/Archives", project: nil, risk: .caution),
            .init(kind: .xcode, name: "iOS DeviceSupport", subpath: "Library/Developer/Xcode/iOS DeviceSupport", project: nil, risk: .safe),
            .init(kind: .xcode, name: "watchOS DeviceSupport", subpath: "Library/Developer/Xcode/watchOS DeviceSupport", project: nil, risk: .safe),
            .init(kind: .xcode, name: "tvOS DeviceSupport", subpath: "Library/Developer/Xcode/tvOS DeviceSupport", project: nil, risk: .safe),
            .init(kind: .xcode, name: "visionOS DeviceSupport", subpath: "Library/Developer/Xcode/visionOS DeviceSupport", project: nil, risk: .safe),
            .init(kind: .xcode, name: "CoreSimulator (devices)", subpath: "Library/Developer/CoreSimulator/Devices", project: nil, risk: .caution),
            .init(kind: .xcode, name: "Simulator caches", subpath: "Library/Developer/CoreSimulator/Caches", project: nil, risk: .safe),
            // NOTE: `DerivedData/SourcePackages` and `DerivedData/ModuleCache.noindex`
            // are deliberately NOT listed as separate entries. They live *inside*
            // DerivedData, which is already measured above — listing them walked
            // 10–40 GB three times and counted it three times in `totalBytes`.
            .init(kind: .xcode, name: "Metal shader caches", subpath: "Library/Developer/GPU/ShaderCache", project: nil, risk: .safe),
            .init(kind: .xcode, name: "Instruments traces", subpath: "Library/Developer/Instruments/Traces", project: nil, risk: .caution),
            // SwiftPM / CocoaPods
            .init(kind: .swiftpm, name: "SPM global caches", subpath: "Library/Caches/org.swift.swiftpm", project: nil, risk: .safe),
            .init(kind: .swiftpm, name: "CocoaPods cache", subpath: "Library/Caches/CocoaPods", project: nil, risk: .safe),
            .init(kind: .swiftpm, name: "Carthage cache", subpath: "Library/Caches/org.carthage.CarthageKit", project: nil, risk: .safeSlow),
            // Node ecosystem
            .init(kind: .node, name: "npm cache", subpath: ".npm", project: nil, risk: .safe),
            .init(kind: .node, name: "npm cache (_cacache)", subpath: "Library/Caches/npm", project: nil, risk: .safe),
            .init(kind: .node, name: "yarn cache", subpath: "Library/Caches/Yarn", project: nil, risk: .safe),
            .init(kind: .node, name: "pnpm store", subpath: "Library/pnpm/store", project: nil, risk: .safe),
            .init(kind: .node, name: "node-gyp headers", subpath: "Library/Caches/node-gyp", project: nil, risk: .safe),
            // Python
            .init(kind: .python, name: "pip cache", subpath: "Library/Caches/pip", project: nil, risk: .safe),
            .init(kind: .python, name: "uv cache", subpath: "Library/Caches/uv", project: nil, risk: .safe),
            .init(kind: .python, name: "conda packages", subpath: "opt/anaconda3/pkgs", project: nil, risk: .safeSlow),
            .init(kind: .python, name: "poetry cache", subpath: "Library/Caches/pypoetry", project: nil, risk: .safe),
            // Rust / Go / JVM
            .init(kind: .rust, name: "cargo registry", subpath: ".cargo/registry", project: nil, risk: .safeSlow),
            .init(kind: .rust, name: "rustup toolchains", subpath: ".rustup", project: nil, risk: .caution),
            .init(kind: .go, name: "go module cache", subpath: "go/pkg/mod", project: nil, risk: .safeSlow),
            .init(kind: .go, name: "go build cache", subpath: "Library/Caches/go-build", project: nil, risk: .safe),
            .init(kind: .java, name: "Gradle caches", subpath: ".gradle/caches", project: nil, risk: .safeSlow),
            .init(kind: .java, name: "Maven repository", subpath: ".m2/repository", project: nil, risk: .safeSlow),
            .init(kind: .java, name: "sbt boot", subpath: ".sbt/boot", project: nil, risk: .safeSlow),
            // Android / Unity / VMs
            .init(kind: .android, name: "Android emulator images", subpath: ".android/avd", project: nil, risk: .caution),
            .init(kind: .android, name: "Gradle Android cache", subpath: "Library/Android/sdk/.gradle", project: nil, risk: .safeSlow),
            .init(kind: .android, name: "Android build caches", subpath: ".android/build-cache", project: nil, risk: .safe),
            .init(kind: .unity, name: "Unity Asset Store", subpath: "Library/Unity/Asset Store-5.x", project: nil, risk: .caution),
            .init(kind: .unity, name: "Unity Editor caches", subpath: "Library/Unity/cache", project: nil, risk: .safe),
            .init(kind: .vagrant, name: ".vagrant.d boxes", subpath: ".vagrant.d/boxes", project: nil, risk: .caution),
            .init(kind: .dotnet, name: "NuGet cache", subpath: ".nuget/packages", project: nil, risk: .safeSlow),
            // Ruby / PHP
            .init(kind: .ruby, name: "RubyGems cache", subpath: "Library/Caches/RubyGems", project: nil, risk: .safe),
            .init(kind: .php, name: "Composer cache", subpath: ".cache/composer", project: nil, risk: .safe),
            .init(kind: .php, name: "Homebrew PHP cache", subpath: "Library/Caches/homebrew-php", project: nil, risk: .safe),
            // Homebrew + CI + Docker
            // Same reason as DerivedData above: `downloads` is inside `Homebrew`, which is
            // measured on the previous line — listing both double-counted it.
            .init(kind: .homebrew, name: "Homebrew cache", subpath: "Library/Caches/Homebrew", project: nil, risk: .safe),
            .init(kind: .ci, name: "bazel output base", subpath: ".cache/bazel", project: nil, risk: .safeSlow),
            .init(kind: .ci, name: "tuist cache", subpath: "Library/Caches/Tuist", project: nil, risk: .safe),
            .init(kind: .ci, name: "Xcodegen cache", subpath: "Library/Caches/xcodegen", project: nil, risk: .safe),
            .init(kind: .docker, name: "Docker.raw (Desktop VM disk)", subpath: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", project: "Docker Desktop", risk: .caution),
            .init(kind: .docker, name: "Colima VM disk", subpath: ".colima/_lima/colima/data", project: "colima", risk: .caution),
        ]
    }

    /// Official clean commands (context menu "Copy Clean Command").
    static func cleanCommand(for name: String, path: String) -> String? {
        switch name {
        case "npm cache", "npm cache (_cacache)": return "npm cache clean --force"
        case "yarn cache": return "yarn cache clean"
        case "pnpm store": return "pnpm store prune"
        case "Homebrew cache", "Homebrew downloads": return "brew cleanup --prune=all"
        case "pip cache": return "pip cache purge"
        case "uv cache": return "uv cache clean"
        case "go module cache", "go build cache": return "go clean -cache -modcache"
        case "CocoaPods cache": return "pod cache clean --all"
        case "NuGet cache": return "dotnet nuget locals all --clear"
        case "Docker.raw (Desktop VM disk)": return "Docker Desktop → Troubleshoot → Clean / Purge data"
        case "Colima VM disk": return "colima delete && colima start"
        case "CoreSimulator (devices)": return "xcrun simctl delete unavailable"
        default: return nil
        }
    }

    /// Wall-clock budget for the whole catalogue. A launch that also runs the
    /// main 400k-node walk must not be starved by ~50 concurrent subtrees.
    private static let totalBudget: TimeInterval = 45
    /// Per-entry cap so one pathological cache (Xcode `DerivedData` can hold
    /// 1M+ files) can't monopolise the disk for minutes.
    private static let maxEntriesPerPath = 60_000

    private static func scanSync(token: ScanCancellation, report: (Int) -> Void) -> [DevCacheItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result: [DevCacheItem] = []
        let catalogue = candidates(home: home)
        let deadline = Date().addingTimeInterval(totalBudget)
        for (index, candidate) in catalogue.enumerated() {
            if token.isCancelled { break }
            if Date() >= deadline { break }
            let path = "\(home)/\(candidate.subpath)"
            let measurement = measure(path, token: token, deadline: deadline)
            guard measurement.bytes > 0 else { continue }
            result.append(DevCacheItem(
                kind: candidate.kind,
                name: candidate.name,
                path: path,
                bytes: measurement.bytes,
                project: candidate.project,
                fileCount: measurement.files,
                lastModified: (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                riskLevel: candidate.risk))
            report(index)
        }
        return result
    }

    /// Fast recursive logical size + file count in one pass (no per-file alloc).
    /// Bounded by `token`, a wall-clock `deadline` and `maxEntriesPerPath`.
    static func measure(_ path: String,
                        token: ScanCancellation = .never,
                        deadline: Date? = nil) -> (bytes: Int64, files: Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue {
            // Single big file (e.g. Docker.raw).
            if let size = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                return (Int64(size), 1)
            }
            return (0, 0)
        }
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return (0, 0) }
        var total: Int64 = 0
        var files = 0
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited & 0x3FF == 0 {           // check cheaply, not per file
                if token.isCancelled { break }
                if let deadline, Date() >= deadline { break }
                if visited > maxEntriesPerPath { break }
            }
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
               values.isDirectory != true, let size = values.fileSize {
                total += Int64(size)
                files += 1
            }
        }
        return (total, files)
    }
}
