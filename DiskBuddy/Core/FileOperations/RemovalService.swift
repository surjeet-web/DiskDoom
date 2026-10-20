import Foundation

// MARK: - Removal methods (Trash / move to folder / permanent delete)
//
// The reference app offers three removal methods plus an overwrite option.
// Trash remains the default. Permanent deletion is explicit and still honors
// the same protected-path backstop as cleanup staging.

enum RemovalMethod: String, CaseIterable, Identifiable, Codable {
    case trash
    case move
    case permanent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trash: return "Move to Trash"
        case .move: return "Move to Folder"
        case .permanent: return "Delete Permanently"
        }
    }

    var detail: String {
        switch self {
        case .trash: return "Recoverable until you empty the Trash."
        case .move: return "Files are moved to a destination folder you choose."
        case .permanent: return "Bypasses the Trash. This cannot be undone."
        }
    }

    var symbol: String {
        switch self {
        case .trash: return "trash"
        case .move: return "folder"
        case .permanent: return "trash.slash"
        }
    }
}

struct RemovalFailure: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let bytes: Int64
    let reason: String
}

struct RemovalResult: Sendable {
    let method: RemovalMethod
    let removedBytes: Int64
    let removedCount: Int
    let failures: [RemovalFailure]
    let destination: String?

    var summary: String {
        let size = ByteFormatting.format(removedBytes)
        switch method {
        case .trash:
            return "Moved \(removedCount) item\(removedCount == 1 ? "" : "s") (\(size)) to Trash."
        case .move:
            return "Moved \(removedCount) item\(removedCount == 1 ? "" : "s") (\(size)) to \(destination ?? "the destination folder")."
        case .permanent:
            return "Permanently deleted \(removedCount) item\(removedCount == 1 ? "" : "s") (\(size))."
        }
    }
}

enum RemovalService {
    /// Removes files using the selected method. Directory removal is refused
    /// for protected paths; individual failures are reported, not swallowed.
    static func remove(items: [(path: String, bytes: Int64)],
                       method: RemovalMethod,
                       destination: String? = nil,
                       overwrite: Bool = false) -> RemovalResult {
        switch method {
        case .trash:
            let result = TrashService.trash(paths: items)
            return RemovalResult(
                method: .trash,
                removedBytes: result.trashedBytes,
                removedCount: result.trashedCount,
                failures: result.failures.map {
                    RemovalFailure(path: $0.path, bytes: $0.bytes, reason: $0.reason)
                },
                destination: nil)
        case .move:
            return move(items: items, destination: destination, overwrite: overwrite)
        case .permanent:
            return deletePermanently(items: items)
        }
    }

    // MARK: Move

    private static func move(items: [(path: String, bytes: Int64)],
                             destination: String?,
                             overwrite: Bool) -> RemovalResult {
        let fm = FileManager.default
        guard let rawDestination = destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawDestination.isEmpty else {
            return RemovalResult(method: .move, removedBytes: 0, removedCount: 0,
                                 failures: items.map {
                                     RemovalFailure(path: $0.path, bytes: $0.bytes,
                                                    reason: "No destination folder selected")
                                 }, destination: nil)
        }
        let destinationPath = (rawDestination as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if !fm.fileExists(atPath: destinationPath, isDirectory: &isDirectory) {
            do {
                try fm.createDirectory(atPath: destinationPath, withIntermediateDirectories: true)
            } catch {
                return RemovalResult(method: .move, removedBytes: 0, removedCount: 0,
                                     failures: items.map {
                                         RemovalFailure(path: $0.path, bytes: $0.bytes,
                                                        reason: "Could not create destination: \(error.localizedDescription)")
                                     }, destination: destinationPath)
            }
        } else if !isDirectory.boolValue {
            return RemovalResult(method: .move, removedBytes: 0, removedCount: 0,
                                 failures: items.map {
                                     RemovalFailure(path: $0.path, bytes: $0.bytes,
                                                    reason: "Destination is a file, not a folder")
                                 }, destination: destinationPath)
        }
        let destinationURL = URL(fileURLWithPath: destinationPath).standardizedFileURL
        var movedBytes: Int64 = 0
        var movedCount = 0
        var failures: [RemovalFailure] = []
        for item in items {
            let sourcePath = (item.path as NSString).expandingTildeInPath
            if let refusal = TrashService.deletionRefusal(for: sourcePath) {
                failures.append(RemovalFailure(path: item.path, bytes: item.bytes,
                                               reason: "Refused — \(refusal)"))
                continue
            }
            let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
            guard fm.fileExists(atPath: sourceURL.path) else {
                failures.append(RemovalFailure(path: item.path, bytes: item.bytes,
                                               reason: "File no longer exists"))
                continue
            }
            // Never move a folder inside itself.
            if destinationURL.path == sourceURL.path
                || destinationURL.path.hasPrefix(sourceURL.path + "/") {
                failures.append(RemovalFailure(path: item.path, bytes: item.bytes,
                                               reason: "Destination is inside the source"))
                continue
            }
            let target = uniqueDestination(for: sourceURL.lastPathComponent,
                                           in: destinationURL, overwrite: overwrite)
            do {
                if fm.fileExists(atPath: target.path) {
                    if let refusal = TrashService.deletionRefusal(for: target.path) {
                        throw NSError(domain: "DiskBuddy", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Refused to overwrite — \(refusal)"])
                    }
                    try fm.removeItem(at: target)
                }
                try fm.moveItem(at: sourceURL, to: target)
                movedBytes += max(0, item.bytes)
                movedCount += 1
            } catch {
                failures.append(RemovalFailure(path: item.path, bytes: item.bytes,
                                               reason: error.localizedDescription))
            }
        }
        return RemovalResult(method: .move, removedBytes: movedBytes, removedCount: movedCount,
                             failures: failures, destination: destinationPath)
    }

    private static func uniqueDestination(for name: String, in folder: URL,
                                          overwrite: Bool) -> URL {
        let base = folder.appendingPathComponent(name)
        guard !overwrite else { return base }
        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return base }
        let ext = base.pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
            if index > 9999 { return folder.appendingPathComponent(UUID().uuidString) }
        }
    }

    // MARK: Permanent

    private static func deletePermanently(items: [(path: String, bytes: Int64)]) -> RemovalResult {
        let fm = FileManager.default
        var removedBytes: Int64 = 0
        var removedCount = 0
        var failures: [RemovalFailure] = []
        for item in items {
            let path = (item.path as NSString).expandingTildeInPath
            if let refusal = TrashService.deletionRefusal(for: path) {
                failures.append(RemovalFailure(path: item.path, bytes: item.bytes,
                                               reason: "Refused — \(refusal)"))
                continue
            }
            guard fm.fileExists(atPath: path) else {
                failures.append(RemovalFailure(path: item.path, bytes: item.bytes,
                                               reason: "File no longer exists"))
                continue
            }
            do {
                try fm.removeItem(atPath: path)
                removedBytes += max(0, item.bytes)
                removedCount += 1
            } catch {
                failures.append(RemovalFailure(path: item.path, bytes: item.bytes,
                                               reason: error.localizedDescription))
            }
        }
        return RemovalResult(method: .permanent, removedBytes: removedBytes,
                             removedCount: removedCount, failures: failures,
                             destination: nil)
    }
}
