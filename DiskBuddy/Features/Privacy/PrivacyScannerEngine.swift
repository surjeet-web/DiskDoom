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
    /// How many matching locations were actually examined, and how many were
    /// unreadable (typically: no Full Disk Access). Surfaced in the UI so the
    /// result is never mistaken for a complete measurement.
    @Published private(set) var scannedLocationCount = 0
    @Published private(set) var unreadableLocationCount = 0
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

    /// Real scan: probes the actual `~/Library` locations for the SDK patterns
    /// above and measures whatever is genuinely there.
    ///
    /// This previously returned six hardcoded findings with hardcoded byte
    /// counts, so the tab confidently reported "6 findings · 650 MB" and a
    /// score of 31/100 on a Mac with none of those SDKs installed. Fabricated
    /// numbers are worse than no feature.
    ///
    /// Bounded by both a time budget and an entry cap, and it reports how many
    /// locations it actually examined plus how many were unreadable (no Full
    /// Disk Access), so the UI can be honest about coverage.
    func scan() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isScanning = true
                self.findings = []
                self.scannedLocationCount = 0
                self.unreadableLocationCount = 0
            }
            let result = await Task.detached(priority: .utility) {
                Self.realScan()
            }.value
            guard !Task.isCancelled else {
                await MainActor.run { self.isScanning = false }
                return
            }
            await MainActor.run {
                self.findings = result.findings
                self.scannedLocationCount = result.locationsExamined
                self.unreadableLocationCount = result.unreadable
                self.isScanning = false
            }
        }
    }

    private static func realScan() -> (findings: [PrivacyFinding], locationsExamined: Int, unreadable: Int) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = [
            "\(home)/Library/Caches",
            "\(home)/Library/Application Support",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
        ]
        var findings: [PrivacyFinding] = []
        var examined = 0
        var unreadable = 0
        let deadline = Date().addingTimeInterval(8) // bounded: never stall the tab
        var entryBudget = 60_000

        outer: for root in roots {
            guard let children = try? fm.contentsOfDirectory(atPath: root) else {
                unreadable += 1
                continue
            }
            for name in children {
                if Date() > deadline || entryBudget <= 0 { break outer }
                entryBudget -= 1
                guard let match = patterns.first(where: {
                    name.localizedCaseInsensitiveContains($0.0)
                }) else { continue }
                let path = root + "/" + name
                examined += 1
                var st = stat()
                guard lstat(path, &st) == 0 else { unreadable += 1; continue }
                var bytes: Int64
                if (st.st_mode & S_IFMT) == S_IFDIR {
                    bytes = boundedDirectorySize(at: path, deadline: deadline)
                } else {
                    bytes = Int64(st.st_size)
                }
                guard bytes > 0 else { continue }
                findings.append(PrivacyFinding(
                    path: path, bytes: bytes, trackerName: match.1,
                    category: match.2, severity: match.3, impact: match.4))
            }
        }
        return (findings.sorted { $0.severity > $1.severity }, examined, unreadable)
    }

    /// Recursive size with a deadline so one huge SDK folder can't hang the scan.
    private static func boundedDirectorySize(at path: String, deadline: Date) -> Int64 {
        var total: Int64 = 0
        var stack = [path]
        var steps = 0
        while let dir = stack.popLast() {
            steps += 1
            if steps > 20_000 || Date() > deadline { return total }
            guard let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for kid in kids {
                let child = dir + "/" + kid
                var st = stat()
                guard lstat(child, &st) == 0 else { continue }
                if (st.st_mode & S_IFMT) == S_IFDIR {
                    stack.append(child)
                } else {
                    let (sum, overflow) = total.addingReportingOverflow(Int64(st.st_size))
                    total = overflow ? Int64.max : sum
                }
            }
        }
        return total
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
