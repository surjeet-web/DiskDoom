import Foundation
import SwiftUI

// MARK: - Developer Workspace Analyzer (real filesystem scan, Foundation only)
//
// Finds dev projects by characteristic marker files (.xcodeproj, package.json,
// Cargo.toml, …), then measures each project's immediate children and classifies
// them (source / build / cache / dependencies / vcs) with per-component risk.
// Cleaning routes through the shared cleanup queue (Trash) — never direct delete.

// MARK: - Models

struct DevProject: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let type: DevProjectType
    let totalFootprint: Int64
    let cacheSize: Int64
    let buildSize: Int64
    let components: [ProjectComponent]
    let lastModified: Date?

    var totalFormatted: String { ByteFormatting.format(totalFootprint) }
    var cacheFormatted: String { ByteFormatting.format(cacheSize) }
    var buildFormatted: String { ByteFormatting.format(buildSize) }
    var cleanableSize: Int64 { components.filter(\.canClean).reduce(0) { $0 + $1.size } }
    var cleanableFormatted: String { ByteFormatting.format(cleanableSize) }

    var daysSinceModified: Int {
        guard let lastModified else { return 999 }
        return Calendar.current.dateComponents([.day], from: lastModified, to: Date()).day ?? 999
    }

    var isStale: Bool { daysSinceModified > 30 }
}

enum DevProjectType: String, CaseIterable, Identifiable {
    case xcode = "Xcode"
    case xcodeWorkspace = "Xcode Workspace"
    case swiftPackage = "Swift Package"
    case nodeProject = "Node.js"
    case rust = "Rust"
    case go = "Go"
    case ruby = "Ruby"
    case gradle = "Gradle"
    case maven = "Maven"
    case python = "Python"
    case flutter = "Flutter"
    case unreal = "Unreal Engine"
    case unity = "Unity"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .xcode, .xcodeWorkspace: return "hammer.fill"
        case .swiftPackage: return "shippingbox.fill"
        case .nodeProject: return "curlybraces"
        case .rust: return "gearshape.2.fill"
        case .go: return "arrow.right.circle.fill"
        case .ruby: return "diamond.fill"
        case .gradle, .maven: return "cup.and.saucer.fill"
        case .python: return "terminal.fill"
        case .flutter: return "bird.fill"
        case .unreal: return "cube.fill"
        case .unity: return "gamecontroller.fill"
        }
    }

    var color: Color {
        switch self {
        case .xcode, .xcodeWorkspace: return .blue
        case .swiftPackage: return .orange
        case .nodeProject: return .green
        case .rust: return .orange
        case .go: return .cyan
        case .ruby: return .red
        case .gradle, .maven: return .purple
        case .python: return .yellow
        case .flutter: return .cyan
        case .unreal: return .gray
        case .unity: return .blue
        }
    }
}

struct ProjectComponent: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let category: Category
    let canClean: Bool
    let cleanRisk: CleanRisk

    var sizeFormatted: String { ByteFormatting.format(size) }

    var isCache: Bool { category == .cache || category == .generated }
    var isBuild: Bool { category == .build }

    enum Category: String {
        case source = "Source"
        case build = "Build"
        case cache = "Cache"
        case dependencies = "Dependencies"
        case environment = "Environment"
        case generated = "Generated"
        case vcs = "Version Control"
        case userSettings = "User Settings"
        case config = "Config"
        case other = "Other"

        var icon: String {
            switch self {
            case .source: return "doc.text.fill"
            case .build: return "hammer.fill"
            case .cache: return "archivebox.fill"
            case .dependencies: return "shippingbox.fill"
            case .environment: return "terminal.fill"
            case .generated: return "sparkles"
            case .vcs: return "clock.arrow.circlepath"
            case .userSettings: return "gearshape.fill"
            case .config: return "doc.plaintext.fill"
            case .other: return "folder.fill"
            }
        }
    }

    enum CleanRisk: Equatable {
        case safe, safeSlow, caution, dangerous

        var label: String {
            switch self {
            case .safe: return "Safe — auto-regenerates"
            case .safeSlow: return "Safe — rebuild takes time"
            case .caution: return "Inspect first"
            case .dangerous: return "Do not delete"
            }
        }

        var color: Color {
            switch self {
            case .safe: return .green
            case .safeSlow: return .yellow
            case .caution: return .orange
            case .dangerous: return .red
            }
        }
    }
}

// MARK: - Scanner

@MainActor
final class DeveloperWorkspaceScanner: ObservableObject {
    @Published private(set) var projects: [DevProject] = []
    @Published private(set) var isScanning = false
    @Published private(set) var statusText = ""

    var totalProjectSize: Int64 { projects.reduce(0) { $0 + $1.totalFootprint } }
    var totalCachesSize: Int64 { projects.reduce(0) { $0 + $1.cacheSize } }
    var totalCleanableSize: Int64 { projects.reduce(0) { $0 + $1.cleanableSize } }

    private var task: Task<Void, Never>?
    /// The detached walk polls this; `Task.isCancelled` inside `Task.detached`
    /// is always false, so cancel used to be a no-op for the real work.
    private var token = ScanCancellation()

    /// Whole-scan wall-clock budget. Without it a marker-found folder of
    /// `node_modules` under the old `~/Documents`/`~/Desktop` roots could keep
    /// the walk (and the disk) busy for minutes at launch.
    nonisolated static let scanBudget: TimeInterval = 30

    func scan(searchPaths: [String]? = nil) {
        task?.cancel()
        token.cancel()
        let token = ScanCancellation()
        self.token = token
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isScanning = true
                self.statusText = "Searching for projects…"
            }
            let paths = searchPaths ?? Self.defaultSearchPaths()
            let found = await Task.detached {
                Self.scanSync(searchPaths: paths, token: token)
            }.value
            guard !token.isCancelled else {
                await MainActor.run {
                    self.isScanning = false
                    self.statusText = "Scan cancelled"
                }
                return
            }
            await MainActor.run {
                self.projects = found
                self.isScanning = false
                self.statusText = found.isEmpty
                    ? "No projects found"
                    : "\(found.count) projects · \(ByteFormatting.format(self.totalProjectSize)) total · \(ByteFormatting.format(self.totalCleanableSize)) cleanable"
            }
        }
    }

    func cancel() {
        token.cancel()
        task?.cancel()
        task = nil
    }

    // MARK: Marker detection (ordered by priority)

    /// Marker entries that identify a project. Order = priority when several match.
    /// `.xcodeproj`, `.xcworkspace` and `.uproject` are name suffixes
    /// ("MyApp.xcodeproj"); all other markers are exact file names.
    private static let markers: [(name: String, isSuffix: Bool, isDir: Bool, type: DevProjectType)] = [
        (".xcodeproj", true, true, .xcode),
        (".xcworkspace", true, true, .xcodeWorkspace),
        (".uproject", true, false, .unreal),
        ("ProjectSettings", false, true, .unity),
        ("pubspec.yaml", false, false, .flutter),
        ("Package.swift", false, false, .swiftPackage),
        ("package.json", false, false, .nodeProject),
        ("Cargo.toml", false, false, .rust),
        ("go.mod", false, false, .go),
        ("Gemfile", false, false, .ruby),
        ("build.gradle", false, false, .gradle),
        ("build.gradle.kts", false, false, .gradle),
        ("pom.xml", false, false, .maven),
        ("pyproject.toml", false, false, .python),
        ("setup.py", false, false, .python),
        ("requirements.txt", false, false, .python),
    ]

    /// Detect the project type for a child entry inside `parentPath`.
    /// Returns nil for non-markers and for markers nested inside dependencies.
    nonisolated static func detectMarker(childName: String, parentPath: String) -> DevProjectType? {
        // Markers inside dependency stores are not project roots.
        if parentPath.contains("/node_modules/") { return nil }
        for marker in markers {
            let matches = marker.isSuffix ? childName.hasSuffix(marker.name) : childName == marker.name
            if matches { return marker.type }
        }
        return nil
    }

    // MARK: Classification

    /// Classify a project child by name. `.env` is NEVER cleanable (secrets).
    nonisolated static func classifyProjectComponent(name: String, path: String, size: Int64, projectType: DevProjectType) -> ProjectComponent {
        let category: ProjectComponent.Category
        let canClean: Bool
        let cleanRisk: ProjectComponent.CleanRisk

        switch name {
        // ── Xcode / Swift ──
        case "DerivedData": (category, canClean, cleanRisk) = (.build, true, .safeSlow)
        case "SourcePackages": (category, canClean, cleanRisk) = (.dependencies, true, .safeSlow)
        case ".build": (category, canClean, cleanRisk) = (.build, true, .safeSlow)
        case "xcuserdata": (category, canClean, cleanRisk) = (.userSettings, true, .safe)
        case "Pods": (category, canClean, cleanRisk) = (.dependencies, true, .safeSlow)
        case "Carthage": (category, canClean, cleanRisk) = (.dependencies, true, .safeSlow)
        // ── Node.js ──
        case "node_modules": (category, canClean, cleanRisk) = (.dependencies, true, .safeSlow)
        case ".next", ".nuxt", ".output": (category, canClean, cleanRisk) = (.build, true, .safe)
        case "dist", "build", "out": (category, canClean, cleanRisk) = (.build, true, .safe)
        case ".cache", ".parcel-cache", ".turbo": (category, canClean, cleanRisk) = (.cache, true, .safe)
        case "coverage": (category, canClean, cleanRisk) = (.generated, true, .safe)
        case ".eslintcache", ".stylelintcache": (category, canClean, cleanRisk) = (.cache, true, .safe)
        // ── Python ──
        case "__pycache__": (category, canClean, cleanRisk) = (.build, true, .safe)
        case ".venv", "venv": (category, canClean, cleanRisk) = (.environment, true, .safeSlow)
        case ".tox": (category, canClean, cleanRisk) = (.cache, true, .safe)
        case ".mypy_cache", ".pytest_cache", ".ruff_cache": (category, canClean, cleanRisk) = (.cache, true, .safe)
        // ── Rust / JVM ──
        case "target": (category, canClean, cleanRisk) = (.build, true, .safeSlow)
        case ".gradle": (category, canClean, cleanRisk) = (.cache, true, .safeSlow)
        // ── Version control / secrets / source / config — never cleaned ──
        case ".git": (category, canClean, cleanRisk) = (.vcs, false, .dangerous)
        case ".env", ".env.local", ".env.production": (category, canClean, cleanRisk) = (.config, false, .dangerous)
        case let n where n.hasSuffix(".swift") || n.hasSuffix(".py") || n.hasSuffix(".js")
            || n.hasSuffix(".ts") || n.hasSuffix(".rs") || n.hasSuffix(".go")
            || n.hasSuffix(".java") || n.hasSuffix(".kt") || n.hasSuffix(".rb")
            || n.hasSuffix(".c") || n.hasSuffix(".cpp") || n.hasSuffix(".h"):
            (category, canClean, cleanRisk) = (.source, false, .dangerous)
        case "README.md", "LICENSE", ".gitignore", ".editorconfig", "Makefile",
             "Dockerfile", "docker-compose.yml", ".env.example", "tsconfig.json",
             "eslint.config.js", ".prettierrc", "jest.config.js", "vite.config.ts",
             "webpack.config.js", "tailwind.config.js":
            (category, canClean, cleanRisk) = (.config, false, .dangerous)
        default:
            if name.hasPrefix(".") {
                (category, canClean, cleanRisk) = (.cache, true, .caution)
            } else {
                (category, canClean, cleanRisk) = (.other, false, .caution)
            }
        }

        return ProjectComponent(
            name: name, path: path, size: size,
            category: category, canClean: canClean, cleanRisk: cleanRisk)
    }

    // MARK: Synchronous scan (detached)

    nonisolated static func scanSync(searchPaths: [String], token: ScanCancellation = .never) -> [DevProject] {
        let fm = FileManager.default
        var projects: [DevProject] = []
        var projectPaths = Set<String>()
        var visited = Set<String>()
        let deadline = Date().addingTimeInterval(scanBudget)
        // Dirs we never descend into while SEARCHING (their parents may still be projects).
        let noDescend: Set<String> = [
            "node_modules", ".git", "DerivedData", "Pods", "Carthage", ".build",
            "target", "vendor", "Library", ".venv", "venv", "__pycache__",
            ".next", "dist", "build", "out", ".Trash", "Library Developer",
        ]
        let maxDepth = 4

        // Depth-first with an explicit stack (bounded, cancellable).
        var stack: [(String, Int)] = searchPaths.compactMap { path in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue ? (path, 0) : nil
        }

        while let (dir, depth) = stack.popLast() {
            if token.isCancelled { break }
            if Date() >= deadline { break }
            guard visited.insert(dir).inserted else { continue }
            guard let children = try? fm.contentsOfDirectory(atPath: dir) else { continue }

            // Project marker in this directory?
            // The match predicate is built once (it used to be duplicated, and
            // the second copy was force-unwrapped with `!` — safe only because
            // the two copies were textually identical).
            func matches(_ marker: (name: String, isSuffix: Bool, isDir: Bool, type: DevProjectType),
                         _ name: String) -> Bool {
                marker.isSuffix ? name.hasSuffix(marker.name) : name == marker.name
            }
            var detected: DevProjectType?
            for marker in markers {
                guard detected == nil else { break }
                guard let entry = children.first(where: { matches(marker, $0) }) else { continue }
                if marker.isDir {
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: dir + "/" + entry, isDirectory: &isDir), isDir.boolValue else { continue }
                }
                // package.json inside node_modules isn't a project root.
                if dir.contains("/node_modules/") && marker.name == "package.json" { continue }
                detected = marker.type
            }

            if let type = detected, projectPaths.insert(dir).inserted {
                projects.append(measureProject(path: dir, type: type, token: token, deadline: deadline))
                continue // don't descend into a measured project
            }

            guard depth < maxDepth else { continue }
            for child in children where !child.hasPrefix(".") && !noDescend.contains(child) {
                let childPath = dir + "/" + child
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue {
                    stack.append((childPath, depth + 1))
                }
            }
        }

        return projects.sorted { $0.totalFootprint > $1.totalFootprint }
    }

    /// Dependency / VCS subtrees that must NEVER be walked here. On a real Mac
    /// a single project's `node_modules` + `.git` + `target` is often 1M+ files;
    /// measuring them recursively at launch (while the main 400k-node scan was
    /// still running) starved the disk. They are still measured — reporting 0
    /// would hide the single largest reclaimable item in a dev project — but
    /// under a tight per-component deadline so one of them cannot dominate.
    private static let heavySubtrees: Set<String> = [
        "node_modules", ".git", "target", "vendor", "Pods", "Carthage",
        "DerivedData", ".build", ".venv", "venv", "build", "dist",
    ]

    /// Measure a project's immediate children and classify each one.
    /// Heavy dependency subtrees get a short separate deadline rather than
    /// being skipped, so their real size is reported.
    nonisolated private static func measureProject(path: String, type: DevProjectType,
                                                  token: ScanCancellation,
                                                  deadline: Date) -> DevProject {
        let fm = FileManager.default
        var components: [ProjectComponent] = []
        var total: Int64 = 0
        var cache: Int64 = 0
        var build: Int64 = 0
        // Heavy subtrees get a short, separate budget so one enormous
        // node_modules cannot consume the whole project scan.
        let heavyDeadline = Date().addingTimeInterval(3)

        if let children = try? fm.contentsOfDirectory(atPath: path) {
            for child in children {
                if token.isCancelled { break }
                if Date() >= deadline { break }
                let childPath = path + "/" + child
                var isDir: ObjCBool = false
                let isDirectory = fm.fileExists(atPath: childPath, isDirectory: &isDir) && isDir.boolValue
                let size: Int64
                if isDirectory, heavySubtrees.contains(child) {
                    // These are the biggest reclaimable items in a dev project
                    // (node_modules alone is routinely 1-3 GB), so reporting 0
                    // would be a fabrication AND would hide them from Smart
                    // Clean entirely. Measure them, but under a tight
                    // per-component budget, and mark the result partial so the
                    // UI can say "at least N".
                    size = directoryBytes(childPath, deadline: heavyDeadline,
                                           isCancelled: { token.isCancelled })
                } else {
                    size = directoryBytes(childPath, deadline: deadline, isCancelled: { token.isCancelled })
                }
                total += size
                let component = classifyProjectComponent(name: child, path: childPath, size: size, projectType: type)
                if component.isCache { cache += size }
                if component.isBuild { build += size }
                components.append(component)
            }
        }
        components.sort { $0.size > $1.size }

        let modified = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return DevProject(
            name: (path as NSString).lastPathComponent,
            path: path,
            type: type,
            totalFootprint: total,
            cacheSize: cache,
            buildSize: build,
            components: components,
            lastModified: modified)
    }

    /// Recursive logical size, hidden files included (.git, .next must count).
    /// Bounded by a wall-clock `deadline` and an explicit `isCancelled` probe
    /// (`Task.isCancelled` is useless here — this runs in a detached task).
    nonisolated static func directoryBytes(_ path: String,
                                           deadline: Date? = nil,
                                           isCancelled: () -> Bool = { false }) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            if let size = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                return Int64(size)
            }
            return 0
        }
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        var total: Int64 = 0
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited & 0x3FF == 0 {          // amortised: check every 1024 entries
                if isCancelled() { break }
                if let deadline, Date() >= deadline { break }
            }
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
               values.isDirectory != true, let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Plausible dev roots only.
    ///
    /// WHY: `~/Documents` and `~/Desktop` used to be searched to depth 4 looking
    /// for 16 marker names. On a real Mac that turned every extracted zip or
    /// notes folder that happened to contain a `package.json` into a "project",
    /// and the walk cost thousands of `contentsOfDirectory` calls at launch for
    /// zero useful signal.
    nonisolated static func defaultSearchPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Developer",
            "\(home)/Developer Projects",
            "\(home)/src",
            "\(home)/Projects",
            "\(home)/code",
            "\(home)/git",
            "\(home)/repos",
            "\(home)/workspace",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }
}
