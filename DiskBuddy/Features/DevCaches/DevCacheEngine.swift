import Foundation

// MARK: - D4 Developer Cache Manager (mock inventory; Foundation only)
//
// Production scan notes (cost: O(fixed tool paths) + one bounded home-dir
// walk, typically 2–8s on a dev machine — runs in a background Task with
// cancellation, pruning .git/node_modules/Library internals upfront):
// - Docker usage comes from `docker system df` when the CLI + daemon are
//   available, falling back to the Docker Desktop VM disk image at
//   ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw.
//   NEVER report ~/.docker/machine/machines (legacy docker-machine) as
//   if it were current Docker usage.

struct DevCacheItem: Identifiable {
    let id = UUID()
    let kind: DevCacheKind
    let name: String // display name (tool or project dir)
    let path: String
    let bytes: Int64
    let project: String?

    enum DevCacheKind: String, CaseIterable {
        case xcode, node, swiftpm, homebrew, docker, git, python, rust

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
            }
        }
    }

    var isSafeToClean: Bool {
        // Archives, VM images, node_modules and .git contents may hold
        // irreplaceable work or be expensive to recreate → caution.
        if path.hasSuffix(".raw") || path.hasSuffix(".qcow2") { return false }
        if kind == .git { return false }
        if name == "node_modules" { return false }
        return true
    }
}

// Main-confined in practice (driven from UI/main thread), hence Sendable.
final class DevCacheEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var items: [DevCacheItem] = []
    @Published private(set) var isScanning = false

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var safeBytes: Int64 { items.filter(\.isSafeToClean).reduce(0) { $0 + $1.bytes } }

    /// Mock inventory matching the production scan surface above.
    func scan() {
        isScanning = true
        defer { isScanning = false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        items = [
            DevCacheItem(kind: .xcode, name: "DerivedData", path: "\(home)/Library/Developer/Xcode/DerivedData", bytes: 12_800_000_000, project: "12 projects"),
            DevCacheItem(kind: .xcode, name: "iOS DeviceSupport", path: "\(home)/Library/Developer/Xcode/iOS DeviceSupport", bytes: 3_100_000_000, project: nil),
            DevCacheItem(kind: .xcode, name: "Archives", path: "\(home)/Library/Developer/Xcode/Archives", bytes: 2_200_000_000, project: nil),
            DevCacheItem(kind: .docker, name: "Docker.raw (Desktop VM disk)", path: "\(home)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", bytes: 18_400_000_000, project: "via docker system df"),
            DevCacheItem(kind: .node, name: "node_modules", path: "\(home)/Projects/webapp/node_modules", bytes: 1_900_000_000, project: "webapp"),
            DevCacheItem(kind: .node, name: "npm cache", path: "\(home)/.npm", bytes: 1_200_000_000, project: nil),
            DevCacheItem(kind: .homebrew, name: "Homebrew cache", path: "\(home)/Library/Caches/Homebrew", bytes: 2_600_000_000, project: nil),
            DevCacheItem(kind: .swiftpm, name: "SPM checkouts", path: "\(home)/Library/Developer/Xcode/DerivedData/DiskDoom/SourcePackages", bytes: 800_000_000, project: nil),
            DevCacheItem(kind: .git, name: ".git", path: "\(home)/Projects/monorepo/.git", bytes: 900_000_000, project: "monorepo"),
            DevCacheItem(kind: .python, name: "pip cache", path: "\(home)/Library/Caches/pip", bytes: 600_000_000, project: nil),
            DevCacheItem(kind: .rust, name: "cargo registry", path: "\(home)/.cargo/registry", bytes: 1_100_000_000, project: nil),
        ].sorted { $0.bytes > $1.bytes }
    }
}
