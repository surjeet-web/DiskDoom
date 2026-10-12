import Combine
import Foundation
import AppKit

// MARK: - Folder Explorer navigation state (ObservableObject, main-confined)
//
// Adapted for this codebase: ObservableObject + @Published (not @Observable),
// trash routes through the cleanup queue (never direct-delete), and the
// refresh shortcut avoids the global ⌘R (New Scan).

final class FolderExplorerEngine: ObservableObject, @unchecked Sendable {
    // Main-confined in practice: constructed and driven from SwiftUI.
    @Published private(set) var currentPath: String = "/"
    @Published private(set) var children: [FolderNode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingProgress = ""
    @Published private(set) var error: String?
    @Published private(set) var measurement: FolderMeasurement?
    @Published private(set) var navigationHistory: [String] = []
    @Published private(set) var historyIndex: Int = -1

    @Published var thresholdBytes: Int64 = 0
    @Published var thresholdLabel = "Show All"
    @Published var sortBy: SortOption = .sizeDescending
    @Published var showHidden = false
    @Published var filterText = ""
    @Published var filterExtension: String?
    @Published var selectedNode: FolderNode?
    @Published var showTreemap = false

    struct Config: Sendable {
        var maxChildren = 1000
    }

    var config = Config()

    struct ThresholdPreset: Identifiable, Hashable, Sendable {
        var id: Int64 { bytes }
        let label: String
        let bytes: Int64
    }

    let thresholdPresets: [ThresholdPreset] = [
        .init(label: "Show All", bytes: 0),
        .init(label: "> 1 MB", bytes: 1_048_576),
        .init(label: "> 10 MB", bytes: 10_485_760),
        .init(label: "> 100 MB", bytes: 104_857_600),
        .init(label: "> 500 MB", bytes: 524_288_000),
        .init(label: "> 1 GB", bytes: 1_073_741_824),
    ]

    enum SortOption: String, CaseIterable, Sendable {
        case sizeDescending = "Size (Largest)"
        case sizeAscending = "Size (Smallest)"
        case nameAscending = "Name (A-Z)"
        case nameDescending = "Name (Z-A)"
        case modifiedDescending = "Modified (Newest)"
        case modifiedAscending = "Modified (Oldest)"
    }

    struct BreadcrumbItem: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let path: String
    }

    struct QuickPath: Identifiable, Hashable, Sendable {
        var id: String { path }
        let name: String
        let path: String
        let icon: String
    }

    var quickPaths: [QuickPath] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            QuickPath(name: "Home", path: home.path, icon: "house.fill"),
            QuickPath(name: "Downloads", path: home.appendingPathComponent("Downloads").path, icon: "arrow.down.circle.fill"),
            QuickPath(name: "Documents", path: home.appendingPathComponent("Documents").path, icon: "doc.fill"),
            QuickPath(name: "Desktop", path: home.appendingPathComponent("Desktop").path, icon: "desktopcomputer"),
            QuickPath(name: "Applications", path: "/Applications", icon: "square.grid.2x2.fill"),
            QuickPath(name: "Library", path: home.appendingPathComponent("Library").path, icon: "building.2.fill"),
            QuickPath(name: "Caches", path: home.appendingPathComponent("Library/Caches").path, icon: "archivebox.fill"),
        ]
    }

    var breadcrumbPath: [BreadcrumbItem] {
        buildBreadcrumbs(path: currentPath)
    }

    private let measurementEngine: FolderMeasurementEngine
    private var navigationTask: Task<Void, Never>?

    init(measurementEngine: FolderMeasurementEngine = .shared) {
        self.measurementEngine = measurementEngine
    }

    deinit {
        navigationTask?.cancel()
    }

    // MARK: Navigation (stale requests always lose to newer ones)

    func navigate(to path: String, pushHistory: Bool = true, forceRefresh: Bool = false) {
        let canonical = canonicalPath(path)
        navigationTask?.cancel()
        navigationTask = Task { [weak self] in
            guard let self else { return }
            await self.load(canonicalPath: canonical, pushHistory: pushHistory, forceRefresh: forceRefresh)
        }
    }

    private func load(canonicalPath: String, pushHistory: Bool, forceRefresh: Bool) async {
        await MainActor.run {
            self.isLoading = true
            self.loadingProgress = "Measuring \(displayPath(canonicalPath))…"
            self.error = nil
        }
        // Copy Sendable inputs before crossing into the measurement task.
        let hidden = showHidden
        do {
            let result = try await measurementEngine.measure(path: canonicalPath, includeHidden: hidden, forceRefresh: forceRefresh)
            try Task.checkCancellation()
            let nodes = buildNodes(from: result)
            let visible = applySortAndFilter(nodes)
            await MainActor.run {
                self.measurement = result
                self.currentPath = canonicalPath
                self.children = visible
                if pushHistory { self.pushHistoryPath(canonicalPath) }
                self.isLoading = false
                self.loadingProgress = ""
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.loadingProgress = ""
                self.error = error.localizedDescription
            }
        }
    }

    func enterFolder(_ node: FolderNode) {
        if node.isDirectory && !node.isPackage {
            navigate(to: node.path)
        } else {
            openDefaultApp(node.path)
        }
    }

    func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        navigate(to: navigationHistory[historyIndex], pushHistory: false)
    }

    func goForward() {
        guard historyIndex >= 0 && historyIndex < navigationHistory.count - 1 else { return }
        historyIndex += 1
        navigate(to: navigationHistory[historyIndex], pushHistory: false)
    }

    func goUp() {
        guard currentPath != "/" else { return }
        let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        guard parent != currentPath else { return }
        navigate(to: parent)
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < navigationHistory.count - 1 }
    var canGoUp: Bool { currentPath != "/" }

    func jumpToQuickPath(_ quickPath: QuickPath) {
        navigate(to: quickPath.path)
    }

    func refresh() {
        let path = currentPath
        navigationTask?.cancel()
        Task {
            await measurementEngine.invalidateAncestors(of: path)
            navigate(to: path, pushHistory: false, forceRefresh: true)
        }
    }

    // MARK: Threshold / sort / search (view-layer only; never re-measures)

    func setThreshold(_ preset: ThresholdPreset) {
        thresholdBytes = preset.bytes
        thresholdLabel = preset.label
        rebuildVisibleChildren()
    }

    func setCustomThreshold(gb: Double) {
        let bytes = Int64(max(0, min(gb, 1024)) * 1_073_741_824)
        thresholdBytes = bytes
        thresholdLabel = bytes == 0 ? "Show All" : String(format: "> %.1f GB", max(0, min(gb, 1024)))
        rebuildVisibleChildren()
    }

    func setSort(_ option: SortOption) {
        sortBy = option
        rebuildVisibleChildren()
    }

    func setFilterText(_ text: String) {
        filterText = text
        rebuildVisibleChildren()
    }

    func setFilterExtension(_ ext: String?) {
        filterExtension = ext
        rebuildVisibleChildren()
    }

    func setShowHidden(_ value: Bool) {
        guard showHidden != value else { return }
        showHidden = value
        navigate(to: currentPath, pushHistory: false)
    }

    // MARK: Actions (Finder/clipboard only — deletion goes via cleanup queue)

    func openInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    func openDefaultApp(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func copySize(_ size: Int64) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ByteFormatting.format(size), forType: .string)
    }

    // MARK: Summary

    var summary: String {
        guard let measurement else { return "" }
        let shown = children.count
        let total = measurement.children.count
        let countText = shown == total ? "\(total) items" : "\(shown) of \(total) items"
        return "\(countText) · \(ByteFormatting.format(measurement.totalSize)) total · \(measurement.totalFileCount) files · \(measurement.totalFolderCount) folders"
    }

    /// WHY: permission-denied subtrees contribute nothing to the total, so
    /// the summary must be able to say the total is a lower bound instead
    /// of presenting it as a complete measurement.
    var unreadableFolderCount: Int { measurement?.unreadableFolderCount ?? 0 }

    var topExtensions: [String] {
        let counts = Dictionary(grouping: children.compactMap { $0.fileExtension?.lowercased() }, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5).map(\.key)
    }

    // MARK: Private

    private func rebuildVisibleChildren() {
        guard let measurement else {
            children = []
            return
        }
        children = applySortAndFilter(buildNodes(from: measurement))
    }

    private func buildNodes(from measurement: FolderMeasurement) -> [FolderNode] {
        let total = max(measurement.totalSize, 1)
        return measurement.children.map { child in
            FolderNode(
                path: child.path, name: child.name, size: child.size,
                isDirectory: child.isDirectory, isPackage: child.isPackage, isSymlink: child.isSymlink,
                childCount: child.childCount, fileCount: child.fileCount,
                modified: child.modified, fileExtension: child.fileExtension,
                percentageOfParent: Double(child.size) / Double(total) * 100,
                isUnreadable: child.isUnreadable)
        }
    }

    private func applySortAndFilter(_ input: [FolderNode]) -> [FolderNode] {
        var result = input
        if thresholdBytes > 0 { result = result.filter { $0.size >= thresholdBytes } }
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty { result = result.filter { $0.name.lowercased().contains(query) } }
        if let ext = filterExtension?.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased(), !ext.isEmpty {
            result = result.filter { $0.isDirectory || $0.fileExtension?.lowercased() == ext }
        }
        switch sortBy {
        case .sizeDescending:
            result.sort { $0.size != $1.size ? $0.size > $1.size : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .sizeAscending:
            result.sort { $0.size != $1.size ? $0.size < $1.size : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameAscending:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .modifiedDescending:
            result.sort { ($0.modified ?? .distantPast) != ($1.modified ?? .distantPast) ? ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .modifiedAscending:
            result.sort { ($0.modified ?? .distantFuture) != ($1.modified ?? .distantFuture) ? ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        if result.count > config.maxChildren { result = Array(result.prefix(config.maxChildren)) }
        return result
    }

    private func pushHistoryPath(_ path: String) {
        let canonical = canonicalPath(path)
        if historyIndex >= 0 && historyIndex < navigationHistory.count && navigationHistory[historyIndex] == canonical { return }
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(canonical)
        historyIndex = navigationHistory.count - 1
    }

    private func buildBreadcrumbs(path: String) -> [BreadcrumbItem] {
        let canonical = canonicalPath(path)
        var result = [BreadcrumbItem(id: "/", name: "/", path: "/")]
        if canonical == "/" { return result }
        var current = ""
        for component in canonical.split(separator: "/").map(String.init) {
            current += "/\(component)"
            result.append(BreadcrumbItem(id: current, name: component, path: current))
        }
        return result
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~/" + String(path.dropFirst(home.count + 1)) }
        return path
    }
}
