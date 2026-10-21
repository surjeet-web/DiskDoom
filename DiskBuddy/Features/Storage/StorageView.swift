import SwiftUI
import AppKit

// MARK: - Storage tab: physical layer (disks→containers→volumes) + logical
// layer (Data-volume breakdown from the scan index) + honest snapshots.
//
// The two layers are visually separated and never added together: containers
// own physical blocks; the Data volume's folders are a logical view into one
// of those containers.

struct StorageView: View {
    @EnvironmentObject var topology: DiskTopologyService
    @EnvironmentObject var state: AppState
    @State private var expandedContainer: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.l) {
                // Capacity headline (dynamic Data volume, firmlink-aware).
                capacityCard

                // ── Physical layer ──
                Text("Physical Storage")
                    .font(.headline)
                if topology.physicalDisks.isEmpty && topology.containers.isEmpty {
                    Text("Loading disk topology…")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(topology.physicalDisks) { disk in
                    physicalDiskCard(disk)
                }
                // Containers whose physical store isn't mapped (external APFS, DMGs).
                ForEach(topology.containers.filter { c in !topology.physicalDisks.contains(where: { c.physicalStores.first?.device.hasPrefix($0.id) ?? false }) }) { container in
                    containerCard(container, parentLabel: "External / virtual container")
                }

                // ── Snapshots (honest: counts + names, no fake sizes) ──
                if !topology.snapshots.isEmpty {
                    snapshotCard
                }

                // ── Logical layer: Data volume from the scan index ──
                Text("Data Volume Contents")
                    .font(.headline)
                if let root = state.scanRoot, !root.children.isEmpty {
                    ForEach(root.children.prefix(12), id: \.id) { child in
                        HStack(spacing: DesignTokens.Space.m) {
                            Image(systemName: child.category.symbol)
                                .foregroundStyle(child.category.color)
                                .frame(width: 20)
                            Text(child.name).font(.callout).lineLimit(1)
                            Spacer()
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(child.category.color.opacity(0.2))
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(child.category.color.opacity(0.6))
                                            .frame(width: geo.size.width * CGFloat(child.sizeBytes) / CGFloat(max(root.sizeBytes, 1)))
                                    }
                            }
                            .frame(height: 10)
                            Text(child.sizeString).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
                            Button {
                                state.selectedNode = child
                                state.sidebarTab = .explore
                            } label: {
                                Image(systemName: "arrow.right.circle").font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Inspect in Explore")
                        }
                    }
                } else {
                    EmptyState(symbol: "internaldrive", title: "Scan to map the Data volume", message: "Physical capacity is above. Per-folder breakdown appears after a scan — one walk, many views.", actionTitle: "Start Scan (⌘R)", action: { state.startScan() })
                }

                // ── Externals ──
                if !topology.externals.isEmpty {
                    Text("External Volumes").font(.headline)
                    ForEach(topology.externals) { vol in
                        HStack {
                            Image(systemName: "externaldrive.fill").foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vol.name).font(.callout.weight(.medium))
                                Text("\(vol.filesystem) · \(vol.capacity.applyingFreshness(maxAge: DiskTopologyService.capacityFreshness).availableValue.map { "\(ByteFormatting.format($0.freeBytes)) free of \(ByteFormatting.format($0.totalBytes))" } ?? vol.capacity.applyingFreshness(maxAge: DiskTopologyService.capacityFreshness).statusLabel)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vol.isEjectable {
                                Button("Eject") { topology.eject(mountPath: vol.mountPath) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            Task {
                await topology.loadTopology()
                await topology.loadCapacity()
                await topology.loadSnapshots()
                await topology.loadExternals()
            }
        }
    }

    // MARK: Capacity headline

    private var capacityCard: some View {
        let measurement = topology.currentCapacity
        return VStack(spacing: DesignTokens.Space.s) {
            Text(topology.dataVolumeName).font(.title2.weight(.semibold))
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 16).frame(width: 140, height: 140)
                if let capacity = measurement.availableValue {
                    let frac = capacity.usedPercent / 100
                    Circle().trim(from: 0, to: frac)
                        .stroke(frac > 0.9 ? Color.red : frac > 0.75 ? Color.orange : Color.blue,
                                style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(ByteFormatting.format(capacity.freeBytes))
                            .font(.title2.weight(.bold)).monospacedDigit()
                        Text("free").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(measurement.statusLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(measurement.availableValue.map { "\(ByteFormatting.format($0.usedBytes)) used of \(ByteFormatting.format($0.totalBytes))" } ?? (measurement.reason ?? measurement.statusLabel))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            if let date = measurement.measuredAt, let source = measurement.source {
                Text("Measured \(date.formatted(date: .abbreviated, time: .shortened)) · \(source)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background {
            MetalSurface(family: .canopy, flatSide: .left, accent: DesignTokens.Palette.cyan)
        }
    }

    // MARK: Physical layer cards

    private func physicalDiskCard(_ disk: PhysicalDiskInfo) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Image(systemName: disk.isSSD ? "internaldrive.fill" : "opticaldiscdrive.fill")
                    .foregroundStyle(.blue)
                Text(disk.id).font(.headline)
                Text(disk.isInternal ? "Internal" : "External")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormatting.format(disk.sizeBytes))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(topology.containers.filter { c in c.physicalStores.first?.device.hasPrefix(disk.id) ?? c.device.hasPrefix(disk.id) }) { container in
                containerCard(container, parentLabel: nil)
            }
        }
        .padding(24)
        .background {
            MetalSurface(family: .tiered, flatSide: .right, accent: DesignTokens.Palette.cyan)
        }
    }

    private func containerCard(_ container: APFSContainerInfo, parentLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
            HStack {
                Text("APFS Container").font(.callout.weight(.semibold))
                if let parentLabel {
                    Text(parentLabel).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(ByteFormatting.format(container.usedBytes)) of \(ByteFormatting.format(container.capacityBytes))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.15))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(container.usedBytes) / CGFloat(max(container.capacityBytes, 1)))
                    }
            }
            .frame(height: 10)
            Text("Shared by \(container.volumes.count) volumes — volumes share container blocks, so their usage is not additive.")
                .font(.caption2).foregroundStyle(.tertiary)
            Button(expandedContainer == container.id ? "Hide volumes" : "Show \(container.volumes.count) volumes") {
                expandedContainer = expandedContainer == container.id ? nil : container.id
            }
            .buttonStyle(.link).font(.caption)
            if expandedContainer == container.id {
                ForEach(container.volumes) { vol in
                    HStack(spacing: DesignTokens.Space.s) {
                        Image(systemName: vol.role.symbol).foregroundStyle(.secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: DesignTokens.Space.xs) {
                                Text(vol.name).font(.caption.weight(.medium))
                                Text(vol.role.label).font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.secondary)
                                if vol.isEncrypted {
                                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.green)
                                }
                            }
                            Text(vol.role.description).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(vol.usedBytes.map { ByteFormatting.format($0) } ?? "Unavailable").font(.caption.monospacedDigit())
                            if let mount = vol.mountPoint {
                                Button(mount) { NSWorkspace.shared.open(URL(fileURLWithPath: mount)) }
                                    .buttonStyle(.link).font(.caption2).lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(20)
        .background {
            MetalSurface(family: .well, flatSide: .right, depth: 2, accent: DesignTokens.Palette.teal)
        }
    }

    // MARK: Honest snapshot card (no fabricated sizes, no shell commands)

    private var snapshotCard: some View {
        let tm = topology.snapshots.filter { $0.kind == .timeMachine }
        let sys = topology.snapshots.filter { $0.kind != .timeMachine }
        return VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Image(systemName: "camera.metering.spot").foregroundStyle(.orange)
                Text("APFS Snapshots (\(topology.snapshots.count))").font(.headline)
                Spacer()
            }
            HStack(spacing: DesignTokens.Space.l) {
                Text("\(tm.count) Time Machine").font(.caption)
                Text("\(sys.count) System / Update").font(.caption)
            }
            .foregroundStyle(.secondary)
            if let latest = topology.snapshots.compactMap({ s in s.date.map { (s, $0) } }).sorted(by: { $0.1 > $1.1 }).first?.0 {
                Text("Latest: \(latest.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Text("Snapshots share blocks with the live volume — macOS reclaims their space automatically when storage runs low.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .background {
            MetalSurface(family: .boot, flatSide: .left, accent: DesignTokens.Palette.orange)
        }
    }
}

#Preview {
    StorageView()
        .environmentObject(DiskTopologyService())
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
