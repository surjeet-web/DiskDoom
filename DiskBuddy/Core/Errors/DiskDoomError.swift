import Foundation

// MARK: - Unified error type for the whole app.
//
// Every failure path maps to a case with a user-visible message plus a
// recovery suggestion; severity drives the banner styling.

enum DiskDoomError: LocalizedError, Identifiable {
    var id: String { errorDescription ?? "unknown" }

    // Scan
    case scanFailed(underlying: Error)
    case scanCancelled
    case scanTimeout
    case accessDenied(path: String)
    case pathNotFound(path: String)
    case diskFull

    // Duplicates / cleanup
    case hashFailed(path: String)
    case trashFailed(path: String, underlying: Error)

    // Applications
    case uninstallFailed(bundleID: String)
    case appNotFound(bundleID: String)

    // Caches / persistence
    case cacheCorrupted(store: String)
    case cacheWriteFailed(store: String)

    // License
    case licenseInvalid
    case licenseExpired
    case licenseActivationFailed(reason: String)
    case licenseServerUnreachable

    // System
    case permissionDenied
    case fileSystemError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .scanFailed(let err): return "Scan failed: \(err.localizedDescription)"
        case .scanCancelled: return "Scan was cancelled."
        case .scanTimeout: return "Scan timed out — the disk may be very slow or busy."
        case .accessDenied(let path): return "Access denied: \(path)"
        case .pathNotFound(let path): return "Path not found: \(path)"
        case .diskFull: return "Disk is full. Free some space before scanning."
        case .hashFailed(let path): return "Failed to hash file: \(path)"
        case .trashFailed(let path, let err): return "Failed to move \(path) to Trash: \(err.localizedDescription)"
        case .uninstallFailed(let id): return "Failed to uninstall \(id)."
        case .appNotFound(let id): return "Application not found: \(id)"
        case .cacheCorrupted(let store): return "\(store) cache is corrupted — it will be rebuilt."
        case .cacheWriteFailed(let store): return "Failed to save the \(store) cache."
        case .licenseInvalid: return "License key is invalid."
        case .licenseExpired: return "Your license has expired."
        case .licenseActivationFailed(let reason): return "Activation failed: \(reason)"
        case .licenseServerUnreachable: return "Cannot reach the license server — working offline."
        case .permissionDenied: return "Permission denied."
        case .fileSystemError(let err): return "File system error: \(err.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .scanFailed: return "Try scanning a smaller folder first; if it persists, restart the app."
        case .scanCancelled: return "No action needed."
        case .scanTimeout: return "Try excluding the slow directory, or scan when the disk is less busy."
        case .accessDenied, .permissionDenied: return "System Settings → Privacy & Security → Full Disk Access → enable DiskDoom."
        case .pathNotFound: return "The item may have been moved or deleted."
        case .diskFull: return "Empty the Trash or remove large files, then try again."
        case .hashFailed: return "The file may be locked or corrupted — it will be skipped."
        case .trashFailed: return "Check whether the file is in use; close the app that owns it."
        case .uninstallFailed: return "Try moving the app to the Trash manually."
        case .appNotFound: return "The app may already be uninstalled."
        case .cacheCorrupted: return "The cache rebuilds automatically — no action needed."
        case .cacheWriteFailed: return "Check free disk space; the cache retries on the next operation."
        case .licenseInvalid: return "Check your license key and try again."
        case .licenseExpired: return "Renew your license to re-enable cleaning."
        case .licenseActivationFailed: return "Contact support for help with this key."
        case .licenseServerUnreachable: return "Your license keeps working offline for the grace period."
        case .fileSystemError: return "Check disk health with First Aid in Disk Utility."
        }
    }

    var iconName: String {
        switch self {
        case .accessDenied, .permissionDenied: return "lock.fill"
        case .diskFull: return "externaldrive.badge.exclamationmark"
        case .licenseInvalid, .licenseExpired: return "lock.slash"
        case .scanTimeout: return "clock.badge.exclamationmark"
        default: return "exclamationmark.triangle.fill"
        }
    }

    var severity: Severity {
        switch self {
        case .scanCancelled, .cacheCorrupted: return .info
        case .accessDenied, .permissionDenied, .licenseServerUnreachable: return .warning
        default: return .error
        }
    }

    enum Severity {
        case info, warning, error
    }
}
