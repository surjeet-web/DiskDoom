import Foundation

// MARK: - D12 Privacy Cleanup Engine (ObservableObject; SAFE scope only)
//
// Review fix applied: this engine NEVER targets whole browser profiles
// (passwords, bookmarks, sessions live there). It matches only known
// third-party analytics / ad / crash SDK caches by path pattern, and every
// finding is staged individually — no category-wide "delete all" for anything
// the user didn't explicitly pick file-by-file.

struct PrivacyFinding: Identifiable {
    let id = UUID()
    let path: String
    let bytes: Int64
    let trackerName: String
    let category: PrivacyCategory
    let severity: Severity
    let impact: String // what clearing does (honest side effects)

    enum PrivacyCategory: String, CaseIterable {
        case adTracking, analytics, crashReporter, socialSDK
        var label: String {
            switch self {
            case .adTracking: return "Ad Tracking"
            case .analytics: return "Analytics"
            case .crashReporter: return "Crash Reporters"
            case .socialSDK: return "Social SDKs"
            }
        }

        var symbol: String {
            switch self {
            case .adTracking: return "eye.slash.fill"
            case .analytics: return "chart.bar.fill"
            case .crashReporter: return "exclamationmark.triangle.fill"
            case .socialSDK: return "person.2.fill"
            }
        }

        var blurb: String {
            switch self {
            case .adTracking: return "Files that track behavior across apps for ad targeting. Safe to clear."
            case .analytics: return "Files that send usage data to analytics services. Safe to clear."
            case .crashReporter: return "Stored crash reports. Clearing means unsent reports won't be delivered."
            case .socialSDK: return "Social integration caches. Clearing may sign you out of social features inside apps."
            }
        }
    }

    enum Severity: Int, Comparable {
        case low = 1, medium = 2, high = 3
        static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
        var label: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }
    }
}

final class PrivacyScannerEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var findings: [PrivacyFinding] = []
    @Published private(set) var isScanning = false
    private var task: Task<Void, Never>?

    // Curated SDK patterns: analytics/ad/crash caches ONLY.
    private static let patterns: [(String, String, PrivacyFinding.PrivacyCategory, PrivacyFinding.Severity, String)] = [
        ("com.facebook.sdk", "Facebook SDK", .adTracking, .high, "Always safe to clear; regenerates on next launch."),
        ("com.appsflyer", "AppsFlyer", .adTracking, .high, "Always safe to clear; regenerates on next launch."),
        ("com.adjust.sdk", "Adjust SDK", .adTracking, .high, "Always safe to clear; regenerates on next launch."),
        ("com.amplitude", "Amplitude", .analytics, .medium, "Always safe to clear; regenerates on next launch."),
        ("com.mixpanel", "Mixpanel", .analytics, .medium, "Always safe to clear; regenerates on next launch."),
        ("com.segment", "Segment", .analytics, .medium, "Always safe to clear; regenerates on next launch."),
        ("com.crashlytics", "Crashlytics", .crashReporter, .low, "Unsent crash reports will not be delivered."),
        ("com.sentry", "Sentry", .crashReporter, .low, "Unsent crash reports will not be delivered."),
        ("com.twitter.sdk", "Twitter SDK", .socialSDK, .medium, "May sign you out of in-app social features."),
    ]

    var score: Int {
        max(0, 100 - findings.reduce(0) { $0 + $1.severity.rawValue * 3 })
    }

    var totalBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }

    /// Mock scan against prototype paths (production: same patterns over real scan).
    func scan() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isScanning = true }
            let found = Self.mockFindings()
            guard !Task.isCancelled else {
                await MainActor.run { self.isScanning = false }
                return
            }
            await MainActor.run {
                self.findings = found
                self.isScanning = false
            }
        }
    }

    private static func mockFindings() -> [PrivacyFinding] {
        let candidates: [(String, Int64)] = [
                ("~/Library/Caches/com.facebook.sdk/FBSDKCache", 240_000_000),
                ("~/Library/Caches/com.appsflyer/attribution", 180_000_000),
                ("~/Library/Caches/com.amplitude/session-events", 96_000_000),
                ("~/Library/Caches/com.mixpanel/mp-events", 64_000_000),
                ("~/Library/Caches/com.crashlytics/reports", 42_000_000),
                ("~/Library/Caches/com.twitter.sdk/auth", 28_000_000),
            ]
        return candidates.compactMap { (path, bytes) -> PrivacyFinding? in
            guard let match = Self.patterns.first(where: { path.localizedCaseInsensitiveContains($0.0) })
            else { return nil }
            return PrivacyFinding(path: path, bytes: bytes, trackerName: match.1, category: match.2, severity: match.3, impact: match.4)
        }
        .sorted { $0.severity > $1.severity }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
