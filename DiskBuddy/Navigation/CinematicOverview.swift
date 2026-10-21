import SwiftUI

/// The reference overview, backed exclusively by measured storage and scan data.
struct CinematicOverviewStrip: View {
    let compact: Bool
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var topology: DiskTopologyService
    @State private var showsDetails = false
    @State private var biggest: ScanNode?
    @State private var projectionPending = false

    private struct SourceKey: Hashable {
        let root: UUID?
        let revision: Int
    }

    private var measurement: Measurement<StorageCapacity> { topology.currentCapacity }
    private var ringSize: CGFloat { compact ? 68 : 83 }
    private var labelSize: CGFloat { compact ? 10 : 11 }
    private var valueSize: CGFloat { compact ? 10 : 12 }
    private var ink: Color { color(0xe1e6ea) }

    private var scanDate: String {
        state.lastScanDate?.formatted(date: .abbreviated, time: .shortened) ?? "Not scanned"
    }

    private var capacityHelp: String {
        var parts = [measurement.statusLabel]
        if let source = measurement.source { parts.append(source) }
        if let date = measurement.measuredAt {
            parts.append("Measured \(date.formatted(date: .complete, time: .standard))")
        }
        if let reason = measurement.reason { parts.append(reason) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            overview(biggestVisible: true, cleanableVisible: true, scanVisible: true)
            overview(biggestVisible: true, cleanableVisible: false, scanVisible: true)
            overview(biggestVisible: true, cleanableVisible: false, scanVisible: false)
            overview(biggestVisible: false, cleanableVisible: false, scanVisible: false)
        }
        .padding(.init(top: compact ? 13 : 16, leading: compact ? 14 : 27,
                       bottom: compact ? 13 : 14, trailing: compact ? 14 : 24))
        .frame(height: 117)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(ink)
        .background {
            // CSS 105deg: almost horizontal, with a slight downward slope.
            LinearGradient(stops: [
                .init(color: color(0x111921), location: 0),
                .init(color: color(0x10151c), location: 0.4),
                .init(color: color(0x0b1016), location: 1)
            ], startPoint: .init(x: 0, y: 0.366), endPoint: .init(x: 1, y: 0.634))
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(color(0x5e7886).opacity(0x6f / 255.0)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, color(0x3a88bb).opacity(0x5e / 255.0),
                                    color(0xffa04d).opacity(0x6b / 255.0), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 2)
                .accessibilityHidden(true)
        }
        .task(id: SourceKey(root: state.scanRoot?.id, revision: state.searchRevision)) {
            projectionPending = state.scanRoot != nil
            let nodes = state.effectiveTopLevel
            let records = state.records
            let worker = Task.detached(priority: .userInitiated) { Self.projectBiggest(nodes: nodes, records: records) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            biggest = result
            projectionPending = false
        }
    }

    private func overview(biggestVisible: Bool, cleanableVisible: Bool, scanVisible: Bool) -> some View {
        HStack(spacing: compact ? 7 : 14) {
            capacitySummary
            if biggestVisible { biggestMetric }
            if cleanableVisible { cleanableMetric }
            if scanVisible { scanMetric }
            if !cleanableVisible {
                Button { showsDetails = true } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Show all overview details and Smart Clean review")
                .accessibilityLabel("More overview details")
                .popover(isPresented: $showsDetails) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Storage overview").font(.headline)
                        Text(capacityHelp).font(.caption).foregroundStyle(.secondary)
                        biggestMetric
                        cleanableMetric
                        scanMetric
                    }
                    .padding(20)
                    .frame(width: 310)
                }
            }
        }
    }

    private var capacitySummary: some View {
        HStack(spacing: compact ? 10 : 14) {
            diskRing
            VStack(alignment: .leading, spacing: 4) {
                Text(topology.dataVolumeName)
                    .font(.system(size: 12, weight: .bold))
                Text(measurement.availableValue.map { "\(ByteFormatting.format($0.freeBytes)) free" }
                     ?? measurement.statusLabel)
                    .font(.system(size: 11))
                Text(measurement.availableValue.map { "\(ByteFormatting.format($0.totalBytes)) total" }
                     ?? "Capacity unknown")
                    .font(.system(size: 11))
                    .foregroundStyle(color(0x8f9aa4))
            }
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .frame(minWidth: compact ? 175 : 196, alignment: .leading)
        .help(capacityHelp)
        .accessibilityElement(children: .combine)
        .accessibilityHint(capacityHelp)
    }

    private var diskRing: some View {
        let percent = measurement.availableValue?.usedPercent
        return ZStack {
            Circle().strokeBorder(color(0x273039), lineWidth: 11)
            if let percent {
                Circle().inset(by: 5.5)
                    .trim(from: 0, to: min(1, max(0, percent / 100)))
                    .stroke(color(0x2fef78), style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Circle().strokeBorder(color(0x192129), lineWidth: 1).padding(11)
            Text(percent.map { "\(Int($0))%" } ?? "—")
                .font(.system(size: 18, weight: .heavy).monospacedDigit())
        }
        .frame(width: ringSize, height: ringSize)
        .overlay { Circle().stroke(color(0x192129), lineWidth: 5).padding(-2.5) }
        .shadow(color: color(0x18e767).opacity(percent == nil ? 0 : 0.16), radius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk usage")
        .accessibilityValue(percent.map { "\(Int($0)) percent used" } ?? measurement.statusLabel)
    }

    private var biggestMetric: some View {
        let folder = biggest
        return metric(icon: "folder", tint: color(0x43dfc1), title: "Biggest") {
            Text(folder?.name ?? (projectionPending ? "Measuring…" : state.scanRoot == nil ? "Not scanned" : "No mapped folders"))
            if let folder {
                Text("\(folder.isPartial ? "At least " : "")\(folder.sizeString)")
            }
        }
        .help(folder.map { "\($0.path) · \($0.isPartial ? "Partial scan · at least " : "")\($0.sizeString)" }
              ?? "No measured folder is available.")
    }

    /// Resolve directory metadata once per scan/index revision, off the UI
    /// thread. Selection and hover never scan the complete record index.
    nonisolated private static func projectBiggest(nodes: [ScanNode], records: [ScannedRecord]) -> ScanNode? {
        var best: ScanNode?
        var unresolved: [String: ScanNode] = [:]
        for node in nodes where !node.isSyntheticAggregate {
            if !node.children.isEmpty || node.isCollapsed {
                if best == nil || node.sizeBytes > best!.sizeBytes { best = node }
            } else { unresolved[node.path] = node }
        }
        unresolved = unresolved.filter { best == nil || $0.value.sizeBytes > best!.sizeBytes }
        guard !unresolved.isEmpty else { return best }
        for record in records {
            if Task.isCancelled { return nil }
            if let candidate = unresolved.removeValue(forKey: record.path), record.isDirectory,
               best == nil || candidate.sizeBytes > best!.sizeBytes { best = candidate }
            if unresolved.isEmpty { break }
        }
        return best
    }

    private var cleanableMetric: some View {
        metric(icon: "sparkles", tint: color(0xb95dff), title: "Cleanable") {
            Text("Not measured")
            Button("Review in Smart Clean") { state.sidebarTab = .smartClean }
                .buttonStyle(.plain)
                .foregroundStyle(color(0xb95dff))
                .help("Review cleanup candidates. Gross cache size is not verified reclaimable space; no savings estimate has been measured.")
        }
    }

    private var scanMetric: some View {
        metric(icon: "clock", tint: color(0x168fff), title: "Last scan") {
            Text(scanDate)
        }
        .help(state.lastScanDate.map {
            "Last completed scan: \($0.formatted(date: .complete, time: .standard))"
        } ?? "No completed scan is available.")
    }

    private func metric<Content: View>(icon: String, tint: Color, title: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: compact ? 7 : 12) {
            Image(systemName: icon)
                .font(.system(size: compact ? 21 : 27))
                .foregroundStyle(tint)
                .frame(width: compact ? 21 : 27)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: labelSize, weight: .bold))
                    .foregroundStyle(color(0xb0b7bd))
                    .padding(.bottom, 2)
                content()
                    .font(.system(size: valueSize, weight: .bold))
            }
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .padding(.leading, compact ? 9 : 17)
        .padding(.vertical, 5)
        .frame(minWidth: compact ? 102 : 133, maxWidth: .infinity,
               minHeight: 51, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(color(0x4e5c67).opacity(0x5e / 255.0))
                .frame(width: 1, height: title == "Biggest" ? 51 : 34)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
              green: Double((hex >> 8) & 0xff) / 255,
              blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}
