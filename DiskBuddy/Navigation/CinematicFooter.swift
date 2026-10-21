import SwiftUI

struct CinematicFooterBar: View {
    let compact: Bool
    let onActivity: () -> Void
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var topology: DiskTopologyService
    @EnvironmentObject private var coordinator: LaunchCoordinator

    init(compact: Bool, onActivity: @escaping () -> Void) {
        self.compact = compact
        self.onActivity = onActivity
    }

    private var scanStatus: String {
        switch state.scanPhase {
        case .idle: return state.scanRoot == nil ? "Not scanned" : "Saved scan"
        case .scanning: return "Scanning"
        case .done: return "Scan complete"
        case .failed: return "Scan failed"
        }
    }

    private var scanSummary: String {
        let files = state.scanPhase == .scanning ? state.scanFiles : state.scanRoot?.fileCount
        var parts = [scanStatus]
        if let files { parts.append("\(files.formatted()) files") }
        if let root = state.scanRoot {
            parts.append("\(root.isPartial ? "≥ " : "")\(ByteFormatting.format(root.sizeBytes)) mapped")
        }
        return parts.joined(separator: " · ")
    }

    private var coverageSummary: String {
        var parts = [state.lastScanDate.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "No completed scan"]
        if state.scanPhase == .scanning {
            parts.append("Scan in progress")
        } else if state.scanRoot != nil {
            // A completed traversal is not proof of full-disk coverage.
            parts.append(state.scanRoot?.isPartial == true || !state.skippedPaths.isEmpty || state.limitedMode
                         ? "Partial coverage" : "Mapped scan scope")
        }
        if !state.skippedPaths.isEmpty { parts.append("\(state.skippedPaths.count) unreadable") }
        if coordinator.staleCache { parts.append("Stale saved scan") }
        return parts.joined(separator: " · ")
    }

    private var jobSummary: String {
        if coordinator.phase == .complete {
            return "Launch jobs complete · \(coordinator.completedCount) finished"
        }
        return "Launch: \(coordinator.phase.rawValue) · \(coordinator.completedCount) finished"
            + (coordinator.currentJobName.isEmpty ? "" : " · \(coordinator.currentJobName)")
    }

    private var capacitySummary: String {
        let measurement = topology.currentCapacity
        guard let capacity = measurement.availableValue else { return measurement.statusLabel }
        return "\(ByteFormatting.format(capacity.totalBytes)) total · \(ByteFormatting.format(capacity.freeBytes)) free"
    }

    private var capacityHelp: String {
        let measurement = topology.currentCapacity
        var parts = [capacitySummary, measurement.statusLabel]
        if let source = measurement.source { parts.append(source) }
        if let date = measurement.measuredAt {
            parts.append("Measured \(date.formatted(date: .complete, time: .standard))")
        }
        if let reason = measurement.reason { parts.append(reason) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 22)
            HStack(spacing: 0) {
                leftField.frame(width: width * 0.38)
                centerField.frame(width: width * 0.28)
                rightField.frame(width: width * 0.34)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.bottom, 7)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background { CinematicFooterBacking() }
    }

    private var leftField: some View {
        VStack(spacing: 0) {
            HStack(spacing: compact ? 8 : 18) {
                ForEach(0..<6) { index in
                    Text("↗")
                        .font(.system(size: compact ? 33 : 41, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: index == 4 ? 0xFF7536 : 0x8E9BA7))
                        .rotationEffect(.degrees(-45))
                        .shadow(color: index == 4 ? Color(hex: 0xFB6E2A) : .black,
                                radius: index == 4 ? 6 : 2, y: index == 4 ? 0 : 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(scanSummary)
                Text(coverageSummary).foregroundStyle(Color(hex: 0x8F9AA4))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color(hex: 0xC5D2DC))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 10 : 20)
            .help("\(scanSummary)\n\(coverageSummary)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scan status")
            .accessibilityValue("\(scanSummary). \(coverageSummary)")
        }
        .padding(.top, compact ? 14 : 16)
        .padding(.bottom, 3)
        .overlay(alignment: .topTrailing) {
            GeometryReader { geometry in
                LinearGradient(colors: [.clear, Color(hex: 0x6A8091), Color(hex: 0xFF8B48)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geometry.size.width * 0.8, height: 2)
                    .shadow(color: Color(hex: 0xEF6B28).opacity(0.46), radius: 4)
                    .position(x: geometry.size.width * 0.58, y: 6)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var centerField: some View {
        VStack(spacing: compact ? 2 : 4) {
            pixelGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: onActivity) {
                Label("Activity & Jobs", systemImage: "list.bullet.rectangle")
                    .font(.system(size: compact ? 10 : 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(hex: 0xD2D9DF))
            .help("\(jobSummary)\n\(scanSummary)\n\(coverageSummary)")
            .accessibilityHint("Opens activity and job details. \(jobSummary)")
        }
        .padding(.top, compact ? 16 : 18)
        .padding(.bottom, 3)
        .overlay(alignment: .top) {
            HStack {
                Rectangle().strokeBorder(Color(hex: 0x666666), lineWidth: 3)
                    .frame(width: 11, height: 11).rotationEffect(.degrees(45))
                Spacer()
                Rectangle().strokeBorder(Color(hex: 0x666666), lineWidth: 3)
                    .frame(width: 11, height: 11).rotationEffect(.degrees(45))
            }
            .frame(height: 11)
            .padding(.horizontal, 11)
            .padding(.top, 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var pixelGrid: some View {
        Canvas { context, size in
            let side: CGFloat = min(compact ? 28 : 35, size.height)
            let gap: CGFloat = 12
            let start = (size.width - (side * 3 + gap * 2)) / 2
            for grid in 0..<3 {
                for row in 0..<5 {
                    for column in 0..<5 {
                        let unit = side / 5
                        let rect = CGRect(x: start + CGFloat(grid) * (side + gap) + CGFloat(column) * unit,
                                          y: (size.height - side) / 2 + CGFloat(row) * unit,
                                          width: max(1, unit - 2), height: max(1, unit - 2))
                        context.fill(Path(rect), with: .color(Color(hex: 0xD2D9DF)))
                    }
                }
            }
        }
        .clipped()
        .shadow(color: .black, radius: 1, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var rightField: some View {
        GeometryReader { geometry in
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    barcode.frame(height: 30)
                    Text(capacitySummary)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xA5B8C4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(capacityHelp)
                        .accessibilityLabel("Disk capacity")
                        .accessibilityValue(capacityHelp)
                }
                .frame(width: min(235, max(0, geometry.size.width >= 220
                                          ? geometry.size.width * 0.57 : geometry.size.width - 36)))
                if geometry.size.width >= 220 { grille }
            }
            .padding(.leading, 18)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(.top, 12)
    }

    private var barcode: some View {
        Canvas { context, size in
            for index in 0..<Int(ceil(size.width / 13)) {
                let x = CGFloat(index) * 13
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                             with: .color(Color(hex: 0xA8B8BF)))
                context.fill(Path(CGRect(x: x + 5, y: 0, width: 2, height: size.height)),
                             with: .color(Color(hex: 0x95ADBC)))
            }
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 0.55),
                                   .init(color: .clear, location: 0.8)],
                           startPoint: .top, endPoint: .bottom)
        }
        .opacity(0.75)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var grille: some View {
        VStack(spacing: 5) {
            ForEach(0..<3) { _ in
                HStack(spacing: 5) {
                    ForEach(0..<3) { _ in
                        Capsule().fill(Color(hex: 0xECF1F3)).frame(width: 16, height: 4)
                    }
                }
            }
        }
        .shadow(color: .white.opacity(0.33), radius: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
