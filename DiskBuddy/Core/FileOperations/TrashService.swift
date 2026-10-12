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
    /// Paths this tool will never move to the Trash. Enforced here as the
    /// final backstop — `AppState.stage` also checks, but any future caller
    /// that bypasses staging must still be blocked.
    private static let deniedPrefixes = [
        "/System", "/usr", "/bin", "/sbin", "/dev", "/cores", "/opt",
        "/private/var/db", "/private/var/folders/", "/private/etc",
        "/Library/Extensions", "/Library/LaunchDaemons", "/Library/LaunchAgents",
        "/Library/Keychains", "/Library/Preferences/.GlobalPreferences",
    ]

    private static let deniedExact: Set<String> = [
        "/", "/System", "/Library", "/Applications", "/Users", "/private",
        "/opt", "/usr", "/bin", "/sbin", "/dev", "/cores", "/Volumes",
        "/Network", "/home", "/var",
    ]

    /// Returns a refusal reason, or nil when the path is allowed.
    static func deletionRefusal(for path: String) -> String? {
        let p = (path as NSString).expandingTildeInPath
        if deniedExact.contains(p) { return "system directory" }
        for prefix in deniedPrefixes where p == prefix || p.hasPrefix(prefix + "/") {
            return "protected system path"
        }
        let own = Bundle.main.bundlePath
        if !own.isEmpty, p == own || p.hasPrefix(own + "/") {
            return "this is DiskDoom itself"
        }
        return nil
    }

    /// Moves paths to Trash one by one. Never deletes permanently.
    /// Returns what succeeded plus per-item failure reasons (in use,
    /// permissions, missing, …) for the §31C report + retry.
    static func trash(paths: [(path: String, bytes: Int64)]) -> TrashResult {
        let fm = FileManager.default
        var okBytes: Int64 = 0
        var okCount = 0
        var failures: [TrashFailure] = []
        for item in paths {
            let expandedPath = (item.path as NSString).expandingTildeInPath
            guard expandedPath.hasPrefix("/"), fm.fileExists(atPath: expandedPath) else {
                failures.append(TrashFailure(path: item.path, bytes: item.bytes, reason: "File no longer exists"))
                continue
            }
            // Refuse protected/system paths even if they were somehow queued.
            if let refusal = deletionRefusal(for: expandedPath) {
                failures.append(TrashFailure(path: item.path, bytes: item.bytes,
                                             reason: "Refused — \(refusal)"))
                continue
            }
            let url = URL(fileURLWithPath: expandedPath)
            do {
                var resultingURL: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &resultingURL)
                let (sum, overflow) = okBytes.addingReportingOverflow(item.bytes)
                okBytes = overflow ? Int64.max : sum
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
