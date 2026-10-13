import Foundation

// MARK: - D12 Privacy Cleanup Engine (ObservableObject; SAFE scope only)
//
// Review fix applied: this engine NEVER targets whole browser profiles
// (passwords, bookmarks, sessions live there). It matches only known
// third-party analytics / ad / crash SDK caches by path pattern, and every
// finding is staged individually — no category-wide "delete all" for anything
// the user didn't explicitly pick file-by-file.

struct PrivacyFinding: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let bytes: Int64
    let trackerName: String
    let category: PrivacyCategory
    let severity: Severity
    let impact: String // what clearing does (honest side effects)
    var isSizeComplete = true

    enum PrivacyCategory: String, CaseIterable, Sendable {
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
            case .adTracking: return "Paths matching ad SDK names; not verified tracking activity. Review before clearing."
            case .analytics: return "Paths matching analytics SDK names; data collection is not verified."
            case .crashReporter: return "Paths matching crash SDK names. Clearing may remove unsent reports."
            case .socialSDK: return "Paths matching social SDK names. Clearing may sign you out of in-app features."
            }
        }
    }

    enum Severity: Int, Comparable, Sendable {
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

struct PrivacyScanResult: Sendable {
    let findings: [PrivacyFinding]
    let locationsExamined: Int
    let unreadable: Int
    let incompleteReason: String?
    let completedAt: Date
    var failureReason: String? = nil

    var scoreMeasurement: Measurement<Int> {
        if let failureReason { return .error(reason: failureReason) }
        if let incompleteReason { return .unavailable(reason: incompleteReason) }
        guard unreadable == 0, findings.allSatisfy(\.isSizeComplete) else {
            return .unavailable(reason: "Some locations could not be read; scan coverage is incomplete.")
        }
        return .available(value: max(0, 100 - findings.reduce(0) { $0 + $1.severity.rawValue * 3 }),
                          measuredAt: completedAt, source: "SDK path-pattern heuristic (not a privacy assessment)")
    }
}

@MainActor
final class PrivacyScannerEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var findings: [PrivacyFinding] = []
    @Published private(set) var isScanning = false
    /// How many matching locations were actually examined, and how many were
    /// unreadable (typically: no Full Disk Access). Surfaced in the UI so the
    /// result is never mistaken for a complete measurement.
    @Published private(set) var scannedLocationCount = 0
    @Published private(set) var unreadableLocationCount = 0
    @Published private(set) var scanMeasurement: Measurement<Int> = .notMeasured
    @Published private(set) var lastScanAt: Date?
    nonisolated static let freshnessTTL: TimeInterval = 3_600
    private var task: Task<Void, Never>?

    // Curated SDK patterns: analytics/ad/crash caches ONLY.
    nonisolated private static let patterns: [(String, String, PrivacyFinding.PrivacyCategory, PrivacyFinding.Severity, String)] = [
        ("com.facebook.sdk", "Facebook SDK", .adTracking, .high, "Name match only; review contents. Data may regenerate after clearing."),
        ("com.appsflyer", "AppsFlyer", .adTracking, .high, "Name match only; review contents. Data may regenerate after clearing."),
        ("com.adjust.sdk", "Adjust SDK", .adTracking, .high, "Name match only; review contents. Data may regenerate after clearing."),
        ("com.amplitude", "Amplitude", .analytics, .medium, "Name match only; review contents. Data may regenerate after clearing."),
        ("com.mixpanel", "Mixpanel", .analytics, .medium, "Name match only; review contents. Data may regenerate after clearing."),
        ("com.segment", "Segment", .analytics, .medium, "Name match only; review contents. Data may regenerate after clearing."),
        ("com.crashlytics", "Crashlytics", .crashReporter, .low, "Unsent crash reports will not be delivered."),
        ("com.sentry", "Sentry", .crashReporter, .low, "Unsent crash reports will not be delivered."),
        ("com.twitter.sdk", "Twitter SDK", .socialSDK, .medium, "May sign you out of in-app social features."),
    ]

    var score: Int? { scoreMeasurement.availableValue }
    var scoreMeasurement: Measurement<Int> {
        scanMeasurement.applyingFreshness(maxAge: Self.freshnessTTL)
    }

    func apply(_ result: PrivacyScanResult) {
        findings = result.findings
        scannedLocationCount = result.locationsExamined
        unreadableLocationCount = result.unreadable
        lastScanAt = result.completedAt
        scanMeasurement = result.scoreMeasurement
        isScanning = false
    }

    var totalBytes: Int64 {
        findings.reduce(0) { total, finding in
            let (sum, overflow) = total.addingReportingOverflow(finding.bytes)
            return overflow ? Int64.max : sum
        }
    }

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
        isScanning = true
        scanMeasurement = .notMeasured
        task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isScanning = true
                self.findings = []
                self.scannedLocationCount = 0
                self.unreadableLocationCount = 0
            }
            let worker = Task.detached(priority: .utility) {
                Self.realScan()
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.apply(result)
            }
        }
    }

    nonisolated private static func realScan() -> PrivacyScanResult {
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
        var incompleteReason: String?
        var failureReason: String?

        outer: for root in roots {
            let children: [String]
            do {
                children = try fm.contentsOfDirectory(atPath: root)
            } catch {
                unreadable += 1
                let error = error as NSError
                if error.domain != NSCocoaErrorDomain || error.code != NSFileReadNoPermissionError {
                    failureReason = "Could not enumerate a scoped Library root: \(error.localizedDescription)"
                }
                continue
            }
            for name in children {
                if Task.isCancelled || Date() > deadline || entryBudget <= 0 {
                    incompleteReason = "Scan stopped before all scoped locations were examined (cancelled or scan limit reached)."
                    break outer
                }
                entryBudget -= 1
                guard let match = patterns.first(where: {
                    name.localizedCaseInsensitiveContains($0.0)
                }) else { continue }
                let path = root + "/" + name
                examined += 1
                var st = stat()
                guard lstat(path, &st) == 0 else { unreadable += 1; continue }
                var bytes: Int64
                var isSizeComplete = true
                if (st.st_mode & S_IFMT) == S_IFDIR {
                    let size = boundedDirectorySize(at: path, deadline: deadline, entryBudget: &entryBudget)
                    bytes = size.bytes
                    unreadable += size.unreadable
                    isSizeComplete = size.complete && size.unreadable == 0
                    if !size.complete { incompleteReason = "A matching directory was only partially measured (scan limit reached)." }
                } else {
                    bytes = Int64(st.st_size)
                }
                guard bytes > 0 else { continue }
                findings.append(PrivacyFinding(
                    path: path, bytes: bytes, trackerName: match.1,
                    category: match.2, severity: match.3, impact: match.4, isSizeComplete: isSizeComplete))
            }
        }
        return PrivacyScanResult(findings: findings.sorted { $0.severity > $1.severity },
                                 locationsExamined: examined, unreadable: unreadable,
                                 incompleteReason: incompleteReason, completedAt: Date(), failureReason: failureReason)
    }

    /// Recursive size with a deadline so one huge SDK folder can't hang the scan.
    nonisolated private static func boundedDirectorySize(at path: String, deadline: Date, entryBudget: inout Int) -> (bytes: Int64, unreadable: Int, complete: Bool) {
        var total: Int64 = 0
        var stack = [path]
        var steps = 0
        var unreadable = 0
        while let dir = stack.popLast() {
            steps += 1
            if steps > 20_000 || Date() > deadline || Task.isCancelled { return (total, unreadable, false) }
            guard let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { unreadable += 1; continue }
            for kid in kids {
                if entryBudget <= 0 || Date() > deadline || Task.isCancelled { return (total, unreadable, false) }
                entryBudget -= 1
                let child = dir + "/" + kid
                var st = stat()
                guard lstat(child, &st) == 0 else { unreadable += 1; continue }
                if (st.st_mode & S_IFMT) == S_IFDIR {
                    stack.append(child)
                } else {
                    let (sum, overflow) = total.addingReportingOverflow(Int64(st.st_size))
                    guard !overflow else { return (total, unreadable, false) }
                    total = sum
                }
            }
        }
        return (total, unreadable, true)
    }

    func cancel() {
        if isScanning { scanMeasurement = .unavailable(reason: "Scan cancelled before completion.") }
        task?.cancel()
        task = nil
        isScanning = false
    }
}
