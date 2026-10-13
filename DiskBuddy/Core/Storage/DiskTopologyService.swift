import Foundation
import AppKit

// MARK: - APFS-aware storage topology (container is the accounting boundary)
//
// Corrected model per review:
// - Physical storage is accounted at the CONTAINER (CapacityCeiling/Free).
//   Volume usage is never summed — APFS volumes share container blocks.
// - Topology comes from `diskutil apfs list -plist` (structured), capacity
//   from df + volume resource values, snapshots from tmutil + listSnapshots
//   plist (UUID/name/XID only — no fabricated sizes; blocks are shared with
//   the live volume so per-snapshot "size" would be misleading anyway).
// - The user-visible Data volume is resolved dynamically (mounted at "/"),
//   never via a hardcoded /System/Volumes/Data path.
// - No tree walks here: directory/file analysis comes from the scan index.

enum VolumeRole: String, Sendable, CaseIterable {
    case system, data, preboot, recovery, vm, update, other

    var label: String { rawValue.capitalized }

    var description: String {
        switch self {
        case .system: return "Read-only system volume (OS binaries)"
        case .data: return "Your files, apps, and user data"
        case .preboot: return "Boot support files"
        case .recovery: return "Recovery OS"
        case .vm: return "Swap and sleep image"
        case .update: return "Pending OS updates"
        case .other: return "Other volume"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "gear.circle.fill"
        case .data: return "internaldrive.fill"
        case .preboot: return "lock.shield.fill"
        case .recovery: return "cross.circle.fill"
        case .vm: return "memorychip.fill"
        case .update: return "arrow.triangle.2.circlepath"
        case .other: return "questionmark.circle"
        }
    }
}

struct APFSVolumeInfo: Identifiable, Sendable {
    let id: String // volume UUID
    let name: String
    let role: VolumeRole
    let device: String // disk1s5
    let mountPoint: String?
    let usedBytes: Int64? // nil means diskutil did not report a measurement
    let isEncrypted: Bool
}

struct APFSContainerInfo: Identifiable, Sendable {
    let id: String // container UUID
    let device: String // disk1
    let capacityBytes: Int64 // CapacityCeiling
    let freeBytes: Int64 // CapacityFree
    let physicalStores: [(device: String, bytes: Int64)]
    let volumes: [APFSVolumeInfo]

    var usedBytes: Int64 { max(0, capacityBytes - freeBytes) }
}

struct PhysicalDiskInfo: Identifiable, Sendable {
    let id: String // disk0
    let sizeBytes: Int64
    let isInternal: Bool
    let isSSD: Bool
}

struct SnapshotEntry: Identifiable, Sendable {
    let id: String // name or UUID
    let name: String
    let date: Date?
    let kind: Kind

    enum Kind: Sendable {
        case timeMachine, system, update
        var label: String {
            switch self {
            case .timeMachine: return "Time Machine"
            case .system: return "System"
            case .update: return "OS Update"
            }
        }
    }
}

struct ExtVolumeInfo: Identifiable, Sendable {
    let id: String // mount path
    let name: String
    let mountPath: String
    let capacity: Measurement<StorageCapacity>
    let filesystem: String
    let isEjectable: Bool
}

struct LargeFileEntry: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let bytes: Int64
}

final class DiskTopologyService: ObservableObject, @unchecked Sendable {
    // Main-confined publishes; all heavy work in detached tasks.
    @Published private(set) var physicalDisks: [PhysicalDiskInfo] = []
    @Published private(set) var containers: [APFSContainerInfo] = []
    @Published private(set) var snapshots: [SnapshotEntry] = []
    @Published private(set) var externals: [ExtVolumeInfo] = []
    @Published private(set) var dataVolumeName = "Startup volume"
    @Published private(set) var capacityMeasurement: Measurement<StorageCapacity> = .notMeasured
    @Published private(set) var isLoading = false
    private var capacityPollingTask: Task<Void, Never>?
    static let capacityFreshness: TimeInterval = 90

    var currentCapacity: Measurement<StorageCapacity> {
        capacityMeasurement.applyingFreshness(maxAge: Self.capacityFreshness)
    }

    deinit { capacityPollingTask?.cancel() }

    @MainActor
    func startCapacityMonitoring() {
        guard capacityPollingTask == nil else { return }
        capacityPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { break }
                guard self != nil, !Task.isCancelled else { break }
                await self?.loadCapacity()
            }
        }
    }

    // MARK: Split loads (progressive UI: topology+capacity first)

    func loadTopology() async {
        await setLoading(true)
        let (disks, containers) = await Task.detached { Self.parseTopology() }.value
        await MainActor.run {
            self.physicalDisks = disks
            self.containers = containers
            self.isLoading = false
        }
    }

    func loadCapacity() async {
        let capacity = await Task.detached(priority: .utility) { StorageCapacityReader.read() }.value
        guard !Task.isCancelled else { return }
        let name = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName
        await MainActor.run {
            self.dataVolumeName = name ?? "Startup volume"
            self.capacityMeasurement = capacity
        }
    }

    func loadSnapshots() async {
        let snaps = await Task.detached { Self.readSnapshots() }.value
        await MainActor.run { self.snapshots = snaps }
    }

    func loadExternals() async {
        let volumes = await Task.detached { Self.readExternals() }.value
        await MainActor.run { self.externals = volumes }
    }

    func eject(mountPath: String) {
        try? NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: mountPath))
        Task { await loadExternals() }
    }

    @MainActor
    private func setLoading(_ value: Bool) {
        isLoading = value
    }

    // MARK: Parsers (static, Sendable in/out)

    private static func parseTopology() -> ([PhysicalDiskInfo], [APFSContainerInfo]) {
        var disks: [PhysicalDiskInfo] = []
        var containers: [APFSContainerInfo] = []
        let dfMounts = dfDeviceMounts()

        // Physical disks: documented purpose of `diskutil list -plist`.
        if let listData = shell("/usr/bin/diskutil", ["list", "-plist"]).data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: listData, format: nil) as? [String: Any],
           let parts = plist["AllDisksAndPartitions"] as? [[String: Any]] {
            for part in parts {
                guard let id = part["DeviceIdentifier"] as? String,
                      let content = part["Content"] as? String,
                      content == "GUID_partition_scheme",
                      let size = part["Size"] as? Int64
                else { continue }
                let internal_ = (part["OSInternal"] as? Bool) ?? true
                disks.append(PhysicalDiskInfo(id: id, sizeBytes: size, isInternal: internal_, isSSD: diskIsSSD(id)))
            }
        }

        // APFS containers: the accounting boundary.
        if let apfsData = shell("/usr/bin/diskutil", ["apfs", "list", "-plist"]).data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: apfsData, format: nil) as? [String: Any],
           let rawContainers = plist["Containers"] as? [[String: Any]] {
            for raw in rawContainers {
                guard let uuid = raw["APFSContainerUUID"] as? String,
                      let ref = raw["ContainerReference"] as? String,
                      let ceiling = raw["CapacityCeiling"] as? Int64,
                       let free = raw["CapacityFree"] as? Int64
                else { continue }
                guard StorageCapacity(totalBytes: ceiling, freeBytes: free) != nil else { continue }
                let stores: [(String, Int64)] = (raw["PhysicalStores"] as? [[String: Any]] ?? []).compactMap {
                    guard let dev = $0["DeviceIdentifier"] as? String, let size = $0["Size"] as? Int64 else { return nil }
                    return (dev, size)
                }
                let volumes: [APFSVolumeInfo] = (raw["Volumes"] as? [[String: Any]] ?? []).compactMap { vol in
                    guard let vuuid = vol["APFSVolumeUUID"] as? String,
                          let name = vol["Name"] as? String,
                          let device = vol["DeviceIdentifier"] as? String
                    else { return nil }
                    let roles = vol["Roles"] as? [String] ?? []
                    let role = VolumeRole(rawValue: roles.first?.lowercased() ?? "") ?? roleFromName(name)
                    return APFSVolumeInfo(
                        id: vuuid, name: name, role: role, device: device,
                        mountPoint: dfMounts[device],
                        usedBytes: (vol["CapacityInUse"] as? Int64).flatMap { $0 >= 0 ? $0 : nil },
                        isEncrypted: (vol["Encryption"] as? Bool) ?? false)
                }
                containers.append(APFSContainerInfo(
                    id: uuid, device: ref, capacityBytes: ceiling, freeBytes: free,
                    physicalStores: stores, volumes: volumes))
            }
        }
        return (disks, containers)
    }

    private static func diskIsSSD(_ device: String) -> Bool {
        guard let data = shell("/usr/bin/diskutil", ["info", "-plist", device]).data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return (plist["SolidState"] as? Bool) ?? false
    }

    private static func roleFromName(_ name: String) -> VolumeRole {
        let lower = name.lowercased()
        if lower.contains("data") { return .data }
        if lower.contains("preboot") { return .preboot }
        if lower.contains("recovery") { return .recovery }
        if lower == "vm" || lower.contains(" vm") { return .vm }
        if lower.contains("update") { return .update }
        if lower == "macintosh hd" { return .system }
        return .other
    }

    /// df -Pk device node → mount point (handles spaces: mount = cols 8...).
    private static func dfDeviceMounts() -> [String: String] {
        var map: [String: String] = [:]
        for line in shell("/bin/df", ["-Pk"]).split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 9 else { continue }
            let device = URL(fileURLWithPath: parts[0]).lastPathComponent
            map[device] = parts[8...].joined(separator: " ")
        }
        return map
    }

    private static func readSnapshots() -> [SnapshotEntry] {
        var entries: [SnapshotEntry] = []
        // Time Machine local snapshots: names embed dates.
        for line in shell("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).split(separator: "\n") {
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            entries.append(SnapshotEntry(id: name, name: name, date: parseSnapshotDate(name), kind: name.contains("TimeMachine") ? .timeMachine : .system))
        }
        // APFS snapshot UUIDs (no sizes exposed — shared blocks, see header).
        if let data = shell("/usr/sbin/diskutil", ["apfs", "listSnapshots", "-plist", "/"]).data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let snaps = plist["Snapshots"] as? [[String: Any]] {
            for snap in snaps {
                guard let uuid = snap["SnapshotUUID"] as? String,
                      let name = snap["SnapshotName"] as? String,
                      !entries.contains(where: { $0.id == uuid || $0.name == name })
                else { continue }
                let kind: SnapshotEntry.Kind = name.contains("TimeMachine") ? .timeMachine : name.contains("os.update") ? .update : .system
                entries.append(SnapshotEntry(id: uuid, name: name, date: parseSnapshotDate(name), kind: kind))
            }
        }
        return entries
    }

    private static func parseSnapshotDate(_ name: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        for part in name.split(separator: ".") {
            let str = String(part)
            if str.count == 15, let date = formatter.date(from: str) { return date }
        }
        return nil
    }

    private static func readExternals() -> [ExtVolumeInfo] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return [] }
        var result: [ExtVolumeInfo] = []
        for name in contents {
            let mount = "/Volumes/\(name)"
            let url = URL(fileURLWithPath: mount)
            guard let values = try? url.resourceValues(forKeys: [
                .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                .volumeLocalizedFormatDescriptionKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
            ]),
                // Skip the boot volume group members.
                name != "Macintosh HD" && name != "Macintosh HD - Data"
            else { continue }
            result.append(ExtVolumeInfo(
                id: mount, name: values.volumeName ?? name, mountPath: mount,
                capacity: StorageCapacityReader.fromReadings(
                    totalBytes: values.volumeTotalCapacity.map(Int64.init),
                    freeBytes: values.volumeAvailableCapacity.map(Int64.init)),
                filesystem: values.volumeLocalizedFormatDescription ?? "Unknown",
                isEjectable: values.volumeIsEjectable ?? false))
        }
        return result
    }

    private static func shell(_ path: String, _ args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain the pipe BEFORE waiting. The kernel pipe buffer is 64 KB;
            // if the child writes more than that it blocks on write, and
            // `waitUntilExit()` then blocks forever — a permanent deadlock.
            // `diskutil apfs list -plist` exceeds 64 KB on any multi-volume
            // Mac, which hung the whole launch sequence.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
