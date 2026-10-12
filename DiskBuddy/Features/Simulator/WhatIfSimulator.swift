import Foundation
import SwiftUI
import AppKit

// MARK: - What-If Simulator: toggle cleanups on/off, see combined impact
// before touching a single file.
//
// Items are gathered from every real engine (dev caches, duplicates, old
// downloads, old large files, trash, APFS snapshots, abandoned apps).
// Executing routes filesystem paths through the shared cleanup queue
// (Trash); the only direct action is the explicitly-confirmed Empty Trash.

// MARK: - Models

struct SimItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let savings: Int64
    let source: SimSource
    let risk: SimRisk
    let icon: String
    let color: Color
    /// Filesystem paths staged into the cleanup queue when executed.
    let stagePaths: [String]
    /// Non-queue action (empty trash / copy command), executed directly.
    let directAction: SimDirectAction?
    /// Why this item can't be executed automatically (manual route).
    let manualNote: String?

    var savingsFormatted: String { ByteFormatting.format(savings) }
}

enum SimSource: String, CaseIterable, Identifiable {
    case devCaches = "Dev Caches"
    case duplicates = "Duplicates"
    case oldFiles = "Old Large Files"
    case downloads = "Downloads"
    case trash = "Trash"
    case snapshots = "Snapshots"
    case unusedApps = "Unused Apps"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .devCaches: return "terminal.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .oldFiles: return "doc.fill.badge.clock"
        case .downloads: return "arrow.down.circle.fill"
        case .trash: return "trash.fill"
        case .snapshots: return "camera.metering.spot"
        case .unusedApps: return "app.badge.minus"
        }
    }

    var color: Color {
        switch self {
        case .devCaches: return .green
        case .duplicates: return .blue
        case .oldFiles: return .yellow
        case .downloads: return .purple
        case .trash: return .gray
        case .snapshots: return .cyan
        case .unusedApps: return .orange
        }
    }
}

enum SimRisk: Comparable, Hashable {
    case safe, safeSlow, caution, dangerous

    var sortOrder: Int {
        switch self {
        case .safe: return 0
        case .safeSlow: return 1
        case .caution: return 2
        case .dangerous: return 3
        }
    }

    static func < (l: SimRisk, r: SimRisk) -> Bool { l.sortOrder < r.sortOrder }

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .safeSlow: return "Safe (slow rebuild)"
        case .caution: return "Inspect first"
        case .dangerous: return "Careful"
        }
    }

    var icon: String {
        switch self {
        case .safe, .safeSlow: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .dangerous: return "xmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .safeSlow: return .yellow
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
}

enum SimDirectAction {
    case emptyTrash
    case copySnapshotThinCommand
}

struct SimReport: Identifiable {
    let id = UUID()
    var attempted = 0
    var succeeded = 0
    var failed = 0
    var skipped = 0
    var totalFreed: Int64 = 0
    var failures: [(item: String, reason: String)] = []
    var skips: [(item: String, reason: String)] = []

    var summary: String {
        "\(succeeded) cleaned · \(failed) failed · \(ByteFormatting.format(totalFreed)) freed"
    }
}

// MARK: - Engine

@MainActor
final class WhatIfSimulator: ObservableObject {
    @Published private(set) var items: [SimItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published private(set) var isBuilding = false
    @Published private(set) var statusText = ""

    // Volume snapshot at build time.
    @Published private(set) var totalCapacity: Int64 = 0
    @Published private(set) var currentFree: Int64 = 0
    @Published private(set) var currentUsed: Int64 = 0

    // Filtering (view-bound).
    @Published var filterSource: SimSource?
    @Published var filterRisk: SimRisk?
    @Published var filterText = ""
    @Published var sortBy: SortMode = .savingsDescending

    enum SortMode: String, CaseIterable {
        case savingsDescending = "Largest First"
        case savingsAscending = "Smallest First"
        case riskAscending = "Safest First"
        case riskDescending = "Riskiest First"
        case nameAscending = "Name"
    }

    // MARK: Computed selection math

    var selectedSavings: Int64 {
        items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.savings }
    }
    var projectedFree: Int64 { currentFree + selectedSavings }
    var projectedUsed: Int64 { max(0, currentUsed - selectedSavings) }
    var currentFreePercent: Double { totalCapacity > 0 ? Double(currentFree) / Double(totalCapacity) * 100 : 0 }
    var projectedFreePercent: Double { totalCapacity > 0 ? Double(projectedFree) / Double(totalCapacity) * 100 : 0 }

    var filteredItems: [SimItem] {
        items.filter { item in
            if let source = filterSource, item.source != source { return false }
            if let risk = filterRisk, item.risk != risk { return false }
            if !filterText.isEmpty {
                let q = filterText.lowercased()
                if !item.title.lowercased().contains(q) && !item.subtitle.lowercased().contains(q) { return false }
            }
            return true
        }
    }

    var sortedFilteredItems: [SimItem] {
        let filtered = filteredItems
        switch sortBy {
        case .savingsDescending: return filtered.sorted { $0.savings > $1.savings }
        case .savingsAscending: return filtered.sorted { $0.savings < $1.savings }
        case .riskAscending: return filtered.sorted { $0.risk.sortOrder < $1.risk.sortOrder }
        case .riskDescending: return filtered.sorted { $0.risk.sortOrder > $1.risk.sortOrder }
        case .nameAscending: return filtered.sorted { $0.title < $1.title }
        }
    }

    // MARK: Selection

    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    func selectAll() { selectedIDs = Set(filteredItems.map(\.id)) }
    func selectNone() { selectedIDs.removeAll() }
    func selectSafeOnly() {
        selectedIDs = Set(filteredItems.filter { $0.risk == .safe || $0.risk == .safeSlow }.map(\.id))
    }

    func selectBySource(_ source: SimSource) {
        let ids = Set(filteredItems.filter { $0.source == source }.map(\.id))
        if ids.isSubset(of: selectedIDs) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    // MARK: - Build from real engines

    func build(
        state: AppState,
        devCache: DevCacheEngine,
        inventory: AppInventoryService,
        lifecycle: AppLifecycleEngine
    ) async {
        isBuilding = true
        statusText = "Collecting cleanup targets…"
        items = []
        selectedIDs = []

        // Volume state (cheap, main).
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = v.volumeTotalCapacity {
            let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            totalCapacity = Int64(total)
            currentFree = free
            currentUsed = Int64(total) - free
        }

        // Heavy measurements off-main.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let measurements = await Task.detached { () -> (trash: Int64, oldDownloads: [(String, Int64)], snapshotCount: Int) in
            let trash = ProCacheScanner.measure(path: home.appendingPathComponent(".Trash").path).bytes
            // Old downloads: top-level entries older than 30 days.
            var oldEntries: [(String, Int64)] = []
            let downloads = home.appendingPathComponent("Downloads").path
            let cutoff = Date().addingTimeInterval(-30 * 86_400)
            if let names = try? FileManager.default.contentsOfDirectory(atPath: downloads) {
                for name in names {
                    let path = (downloads as NSString).appendingPathComponent(name)
                    if let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                       modified < cutoff {
                        let size = ProCacheScanner.measure(path: path).bytes
                        if size > 0 { oldEntries.append((path, size)) }
                    }
                }
            }
            // APFS local Time Machine snapshots (count only).
            let snapshotCount = Self.countLocalSnapshots()
            return (trash, oldEntries, snapshotCount)
        }.value

        var built: [SimItem] = []

        // 1. Dev caches (real scan results).
        for item in devCache.items where item.isSafeToClean && item.bytes > 10_000_000 {
            built.append(SimItem(
                title: "Clean \(item.name)",
                subtitle: "\(item.kind.label) · \(ByteFormatting.format(item.bytes))",
                savings: item.bytes,
                source: .devCaches,
                risk: item.kind == .git ? .dangerous : (item.isSafeToClean ? .safeSlow : .caution),
                icon: item.kind.symbol,
                color: .green,
                stagePaths: [item.path],
                directAction: nil,
                manualNote: nil))
        }

        // 2. Duplicate sets (real content-hash results).
        for set in state.dupFinder.sets where set.reclaimable > 1_000_000 {
            let keepID = state.duplicateKeeps[set.id] ?? recommendedKeep(for: set)?.id
            let paths = set.files.filter { $0.id != keepID }.map(\.path)
            built.append(SimItem(
                title: "Duplicate set — \(set.files.count) copies",
                subtitle: "\(set.files.count - 1) redundant copies · \(set.hashPrefix)",
                savings: set.reclaimable,
                source: .duplicates,
                risk: .safe,
                icon: "doc.on.doc.fill",
                color: .blue,
                stagePaths: paths,
                directAction: nil,
                manualNote: nil))
        }

        // 3. Old large files (90+ days, > 100 MB, home directory only).
        let cutoff90 = Date().addingTimeInterval(-90 * 86_400)
        let homePrefix = home.path + "/"
        let oldLarge = state.records
            .filter { !$0.isDirectory && $0.bytes > 100_000_000 && $0.modified < cutoff90 && $0.path.hasPrefix(homePrefix) }
            .sorted { $0.bytes > $1.bytes }
            .prefix(20)
        let oldLargeBytes = oldLarge.reduce(Int64(0)) { $0 + $1.bytes }
        if oldLarge.count >= 3 {
            built.append(SimItem(
                title: "Old Large Files (90+ days)",
                subtitle: "\(oldLarge.count) files over 100 MB, untouched for 3+ months",
                savings: oldLargeBytes,
                source: .oldFiles,
                risk: .caution,
                icon: "doc.fill.badge.clock",
                color: .yellow,
                stagePaths: oldLarge.map(\.path),
                directAction: nil,
                manualNote: nil))
        }

        // 4. Old Downloads (30+ days).
        let downloadsBytes = measurements.oldDownloads.reduce(Int64(0)) { $0 + $1.1 }
        if downloadsBytes > 100_000_000 {
            built.append(SimItem(
                title: "Old Downloads (30+ days)",
                subtitle: "\(measurements.oldDownloads.count) items in Downloads older than 30 days",
                savings: downloadsBytes,
                source: .downloads,
                risk: .caution,
                icon: "arrow.down.circle.fill",
                color: .purple,
                stagePaths: measurements.oldDownloads.map(\.0),
                directAction: nil,
                manualNote: nil))
        }

        // 5. Trash.
        if measurements.trash > 10_000_000 {
            built.append(SimItem(
                title: "Empty Trash",
                subtitle: "Permanently delete everything in the Trash",
                savings: measurements.trash,
                source: .trash,
                risk: .safe,
                icon: "trash.fill",
                color: .gray,
                stagePaths: [],
                directAction: .emptyTrash,
                manualNote: nil))
        }

        // 6. APFS snapshots (estimate; thinning is a manual Terminal action).
        if measurements.snapshotCount > 5 {
            built.append(SimItem(
                title: "Thin APFS Snapshots",
                subtitle: "\(measurements.snapshotCount) local Time Machine snapshots · ~\(ByteFormatting.format(Int64(measurements.snapshotCount) * 500_000_000)) estimated",
                savings: Int64(measurements.snapshotCount) * 500_000_000,
                source: .snapshots,
                risk: .caution,
                icon: "camera.metering.spot",
                color: .cyan,
                stagePaths: [],
                directAction: .copySnapshotThinCommand,
                manualNote: nil))
        }

        // 7. Abandoned apps (uninstall flow is in the Applications tab).
        let abandonedBundleIDs = Set(lifecycle.abandoned.map(\.bundleID))
        for app in inventory.apps where abandonedBundleIDs.contains(app.bundleID) && app.totalBytes > 50_000_000 {
            built.append(SimItem(
                title: "Uninstall \(app.name)",
                subtitle: "Not opened in 90+ days · \(ByteFormatting.format(app.totalBytes)) total footprint",
                savings: app.totalBytes,
                source: .unusedApps,
                risk: .caution,
                icon: "app.badge.minus",
                color: .orange,
                stagePaths: [],
                directAction: nil,
                manualNote: "Use the Applications tab to uninstall \(app.name) safely."))
        }

        built.sort { $0.savings > $1.savings }
        items = built
        // Auto-select all safe items.
        selectedIDs = Set(built.filter { $0.risk == .safe }.map(\.id))
        isBuilding = false
        statusText = built.isEmpty
            ? "No significant cleanup targets found"
            : "\(built.count) targets · \(ByteFormatting.format(built.reduce(0) { $0 + $1.savings })) potential savings"
    }

    // MARK: - Execute selected (queue-routed, with report)

    func executeSelected(state: AppState) -> SimReport {
        var report = SimReport()
        let toExecute = items.filter { selectedIDs.contains($0.id) }
        report.attempted = toExecute.count

        guard state.license.canClean else {
            report.skips.append((item: "License", reason: "Read-only mode — activate a license to clean."))
            return report
        }

        var directFreed: Int64 = 0
        for item in toExecute {
            switch item.directAction {
            case .emptyTrash:
                let result = Self.emptyTrashNow()
                directFreed += result.freed
                if result.failures.isEmpty {
                    report.succeeded += 1
                } else {
                    report.failed += 1
                    report.failures.append((item.title, "\(result.failures.count) items couldn't be removed"))
                }
            case .copySnapshotThinCommand:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("tmutil thinlocalsnapshots / 99999999999999 4", forType: .string)
                report.skipped += 1
                report.skips.append((item.title, "Command copied to clipboard — run it in Terminal."))
            case nil:
                if let note = item.manualNote {
                    report.skipped += 1
                    report.skips.append((item.title, note))
                } else if item.stagePaths.isEmpty {
                    report.skipped += 1
                    report.skips.append((item.title, "Nothing to stage"))
                }
            }
        }

        // Stage everything stageable, then run the queue (Trash) once.
        let stageable = toExecute.filter { !$0.stagePaths.isEmpty && $0.directAction == nil && $0.manualNote == nil }
        for item in stageable {
            for path in item.stagePaths {
                state.stage(source: "What If?", path: path)
            }
        }
        var trashResult = TrashResult(trashedBytes: 0, trashedCount: 0, failures: [])
        if !state.cleanupItems.isEmpty {
            trashResult = state.executeCleanup()
        }

        // Attribute queue results back to items.
        let failedPaths = Set(trashResult.failures.map(\.path))
        for item in stageable {
            let itemFailures = item.stagePaths.filter { failedPaths.contains($0) }
            if itemFailures.isEmpty {
                report.succeeded += 1
                report.totalFreed += item.savings
            } else {
                report.failed += 1
                let reason = trashResult.failures.first { itemFailures.contains($0.path) }?.reason ?? "Failed"
                report.failures.append((item.title, reason))
            }
        }
        report.totalFreed += directFreed

        // Remove executed items and reset selection.
        let executedIDs = Set(toExecute.map(\.id))
        items.removeAll { executedIDs.contains($0.id) }
        selectedIDs.subtract(executedIDs)
        return report
    }

    // MARK: - Helpers

    private func recommendedKeep(for set: DuplicateSet) -> DuplicateFile? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func rank(_ path: String) -> Int {
            if path.hasPrefix(home + "/Desktop") { return 0 }
            if path.hasPrefix(home + "/Documents") { return 1 }
            if path.hasPrefix(home + "/Downloads") { return 2 }
            return 3
        }
        return set.files.sorted { rank($0.path) < rank($1.path) }.first
    }

    /// Permanently empty ~/.Trash (the one explicit user-intent exception).
    nonisolated private static func emptyTrashNow() -> (freed: Int64, failures: [String]) {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: [.totalFileSizeKey]) else { return (0, []) }
        var freed: Int64 = 0
        var failures: [String] = []
        for entry in entries {
            let size = Int64((try? entry.resourceValues(forKeys: [.totalFileSizeKey]))?.totalFileSize ?? 0)
            do {
                try FileManager.default.removeItem(at: entry)
                freed += size
            } catch {
                failures.append(entry.lastPathComponent)
            }
        }
        return (freed, failures)
    }

    /// Count local Time Machine snapshots (read-only tmutil).
    nonisolated private static func countLocalSnapshots() -> Int {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain before waiting — 64 KB pipe-buffer deadlock otherwise.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(separator: "\n")
                .filter { $0.contains("com.apple.TimeMachine.") }
                .count
        } catch {
            return 0
        }
    }
}
