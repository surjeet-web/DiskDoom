import Foundation
import Combine

// MARK: - Folder + file-type priority
//
// The reference app lets the user rank folders ("keep originals here") and
// file types. Priority is applied when suggesting which copy to keep:
// lower rank wins. Unlisted folders/types rank after every listed entry.

@MainActor
final class ScanPriorityStore: ObservableObject {
    @Published private(set) var folderPaths: [String] = []
    @Published private(set) var fileExtensions: [String] = []

    private let foldersKey = "priorityFolders"
    private let extensionsKey = "priorityFileExtensions"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folderPaths = (defaults.stringArray(forKey: foldersKey) ?? [])
            .map { ($0 as NSString).expandingTildeInPath }
        fileExtensions = (defaults.stringArray(forKey: extensionsKey) ?? [])
            .map { IgnoreRules.normalizeExtension($0) }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool { folderPaths.isEmpty && fileExtensions.isEmpty }

    // MARK: Folders

    @discardableResult
    func addFolder(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !folderPaths.contains(expanded) else { return false }
        folderPaths.append(expanded)
        persist()
        return true
    }

    func removeFolder(_ path: String) {
        folderPaths.removeAll { $0 == path }
        persist()
    }

    func moveFolder(from source: Int, to destination: Int) {
        guard folderPaths.indices.contains(source) else { return }
        let value = folderPaths.remove(at: source)
        folderPaths.insert(value, at: min(max(0, destination), folderPaths.count))
        persist()
    }

    // MARK: File types

    @discardableResult
    func addExtension(_ raw: String) -> Bool {
        let ext = IgnoreRules.normalizeExtension(raw)
        guard !ext.isEmpty, !fileExtensions.contains(ext) else { return false }
        fileExtensions.append(ext)
        persist()
        return true
    }

    func removeExtension(_ ext: String) {
        fileExtensions.removeAll { $0 == ext }
        persist()
    }

    func moveExtension(from source: Int, to destination: Int) {
        guard fileExtensions.indices.contains(source) else { return }
        let value = fileExtensions.remove(at: source)
        fileExtensions.insert(value, at: min(max(0, destination), fileExtensions.count))
        persist()
    }

    // MARK: Ranking

    /// Lower is better. A file directly inside a listed folder ranks before
    /// one nested deeper in it; every unlisted folder ranks after the list.
    func folderRank(forPath path: String) -> Int {
        let expanded = (path as NSString).expandingTildeInPath
        for (index, folder) in folderPaths.enumerated() {
            if expanded == folder { return index * 2 }
            if expanded.hasPrefix(folder == "/" ? "/" : folder + "/") { return index * 2 + 1 }
        }
        return folderPaths.count * 2 + 1
    }

    func extensionRank(forPath path: String) -> Int {
        let ext = (path as NSString).pathExtension.lowercased()
        if let index = fileExtensions.firstIndex(of: ext) { return index }
        return fileExtensions.count
    }

    /// Deterministic keeper: folder priority, then file-type priority, then
    /// the reference app's Documents/Desktop/Downloads preference, then path.
    func preferredKeep(in files: [DuplicateFile]) -> DuplicateFile? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func legacyRank(_ path: String) -> Int {
            let expanded = (path as NSString).expandingTildeInPath
            if expanded.hasPrefix(home + "/Documents/") { return 0 }
            if expanded.hasPrefix(home + "/Desktop/") { return 1 }
            if expanded.hasPrefix(home + "/Downloads/") { return 2 }
            return 3
        }
        return files.min { left, right in
            let lf = folderRank(forPath: left.path), rf = folderRank(forPath: right.path)
            if lf != rf { return lf < rf }
            let le = extensionRank(forPath: left.path), re = extensionRank(forPath: right.path)
            if le != re { return le < re }
            let ll = legacyRank(left.path), rl = legacyRank(right.path)
            if ll != rl { return ll < rl }
            return left.path < right.path
        }
    }

    /// Keeper for a same-hash set. Files are all equal in content, so size is
    /// not a tiebreaker here.
    func keepersByPriority(for sets: [DuplicateSet]) -> [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for set in sets {
            if let keeper = preferredKeep(in: set.files) {
                result[set.id] = keeper.id
            }
        }
        return result
    }

    private func persist() {
        defaults.set(folderPaths, forKey: foldersKey)
        defaults.set(fileExtensions, forKey: extensionsKey)
    }
}
