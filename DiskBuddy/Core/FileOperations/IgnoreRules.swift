import Foundation
import Combine

// MARK: - Persistent ignore list (paths + file extensions)
//
// Mirrors the reference app's "Ignore List": ignored paths are excluded from
// scans and results, ignored extensions are skipped by duplicate/similar
// finders. Kept in UserDefaults so it survives relaunches.

@MainActor
final class IgnoreRules: ObservableObject {
    @Published private(set) var ignoredPaths: [String] = []
    @Published private(set) var ignoredExtensions: [String] = []

    private let pathsKey = "ignorePaths"
    private let extensionsKey = "ignoreExtensions"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ignoredPaths = (defaults.stringArray(forKey: pathsKey) ?? [])
            .map { ($0 as NSString).expandingTildeInPath }
        ignoredExtensions = (defaults.stringArray(forKey: extensionsKey) ?? [])
            .map { Self.normalizeExtension($0) }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool { ignoredPaths.isEmpty && ignoredExtensions.isEmpty }

    nonisolated static func normalizeExtension(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasPrefix(".") { value.removeFirst() }
        return value
    }

    @discardableResult
    func addPath(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return false }
        guard !ignoredPaths.contains(expanded) else { return false }
        ignoredPaths.append(expanded)
        ignoredPaths.sort()
        persist()
        return true
    }

    func removePath(_ path: String) {
        ignoredPaths.removeAll { $0 == path }
        persist()
    }

    @discardableResult
    func addExtension(_ raw: String) -> Bool {
        let ext = Self.normalizeExtension(raw)
        guard !ext.isEmpty, !ignoredExtensions.contains(ext) else { return false }
        ignoredExtensions.append(ext)
        ignoredExtensions.sort()
        persist()
        return true
    }

    func removeExtension(_ ext: String) {
        ignoredExtensions.removeAll { $0 == ext }
        persist()
    }

    func clear() {
        ignoredPaths.removeAll()
        ignoredExtensions.removeAll()
        persist()
    }

    /// True when the path itself or any ancestor is ignored.
    func isPathIgnored(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        return ignoredPaths.contains { ignored in
            expanded == ignored || expanded.hasPrefix(ignored == "/" ? "/" : ignored + "/")
        }
    }

    func isExtensionIgnored(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return !ext.isEmpty && ignoredExtensions.contains(ext)
    }

    func shouldIgnore(path: String) -> Bool {
        isPathIgnored(path) || isExtensionIgnored(path)
    }

    func filter(_ records: [ScannedRecord]) -> [ScannedRecord] {
        guard !isEmpty else { return records }
        return records.filter { !shouldIgnore(path: $0.path) }
    }

    func filter(paths: [String]) -> [String] {
        guard !isEmpty else { return paths }
        return paths.filter { !shouldIgnore(path: $0) }
    }

    private func persist() {
        defaults.set(ignoredPaths, forKey: pathsKey)
        defaults.set(ignoredExtensions, forKey: extensionsKey)
    }
}
