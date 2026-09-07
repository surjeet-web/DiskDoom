import Foundation

// MARK: - Real Trash execution (FileManager.trashItem; per-item failure reasons)

struct TrashFailure {
    let path: String
    let bytes: Int64
    let reason: String
}

struct TrashResult {
    let trashedBytes: Int64
    let trashedCount: Int
    let failures: [TrashFailure]
}

enum TrashService {
    /// Moves paths to Trash one by one. Never deletes permanently.
    /// Returns what succeeded plus per-item failure reasons (in use,
    /// permissions, missing, …) for the §31C report + retry.
    static func trash(paths: [(path: String, bytes: Int64)]) -> TrashResult {
        let fm = FileManager.default
        var okBytes: Int64 = 0
        var okCount = 0
        var failures: [TrashFailure] = []
        for item in paths {
            let url = URL(fileURLWithPath: (item.path as NSString).expandingTildeInPath)
            do {
                var resultingURL: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &resultingURL)
                okBytes += item.bytes
                okCount += 1
            } catch let error as NSError {
                failures.append(TrashFailure(path: item.path, bytes: item.bytes, reason: humanReason(error)))
            }
        }
        return TrashResult(trashedBytes: okBytes, trashedCount: okCount, failures: failures)
    }

    private static func humanReason(_ error: NSError) -> String {
        switch error.code {
        case NSFileNoSuchFileError: return "File no longer exists"
        case NSFileWriteNoPermissionError: return "Operation not permitted"
        case NSFileWriteVolumeReadOnlyError: return "Volume is read-only"
        default:
            if error.domain == NSPOSIXErrorDomain {
                switch error.code {
                case Int(EPERM), Int(EACCES): return "Operation not permitted"
                case Int(EBUSY): return "In use by a running application"
                default: break
                }
            }
            return error.localizedDescription
        }
    }
}
