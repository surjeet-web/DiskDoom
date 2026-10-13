import SwiftUI

// MARK: - D12 Privacy view (per-file staging only; browser profiles excluded by design)

struct PrivacyView: View {
    @EnvironmentObject var engine: PrivacyScannerEngine
    @EnvironmentObject var state: AppState

    private var grouped: [(PrivacyFinding.PrivacyCategory, [PrivacyFinding])] {
        Dictionary(grouping: engine.findings, by: \.category)
            .sorted { $0.value.reduce(0) { $0 + $1.severity.rawValue } > $1.value.reduce(0) { $0 + $1.severity.rawValue } }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy Scanner").font(.title2.weight(.semibold))
                    Text("SDK path-pattern heuristics — not verified tracking; browser profiles excluded")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PrivacyScoreGauge(measurement: engine.scoreMeasurement)
                Button("Scan") { engine.scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isScanning)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            Text(engine.scoreMeasurement.reason ?? engine.scoreMeasurement.source ?? engine.scoreMeasurement.statusLabel)
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if let date = engine.lastScanAt {
                Text("Last scan: \(date.formatted(date: .abbreviated, time: .shortened)) · \(engine.scoreMeasurement.statusLabel) · expires after 1 hour")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if engine.isScanning {
                ProgressView("Scanning for SDK path matches…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if engine.findings.isEmpty {
                EmptyState(
                    symbol: engine.score == nil ? "questionmark.circle" : "lock.shield.fill",
                    title: engine.score == nil ? engine.scoreMeasurement.statusLabel : "No SDK path matches found",
                    message: engine.scoreMeasurement.reason ?? (engine.score == nil
                        ? "Run a complete scan for a current scoped result."
                        : "Completed the four scoped Library roots. No matching nonempty paths found; this does not verify absence of tracking."),
                    actionTitle: "Scan",
                    action: { engine.scan() })
            } else {
                HStack(spacing: DesignTokens.Space.xl) {
                    Text("\(engine.findings.count) heuristic matches").font(.headline)
                    Text((engine.score == nil ? "At least " : "") + ByteFormatting.format(engine.totalBytes)).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.vertical, DesignTokens.Space.s)
                if engine.score == nil {
                    Label(engine.scoreMeasurement.reason ?? "Cached findings are stale — rescan before relying on them",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, DesignTokens.Space.m)
                        .padding(.bottom, DesignTokens.Space.s)
                }
                List {
                    ForEach(grouped, id: \.0) { category, findings in
                        Section {
                            Text(category.blurb)
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(findings) { finding in
                                HStack(spacing: DesignTokens.Space.m) {
                                    Circle()
                                        .fill(finding.severity == .high ? .red : finding.severity == .medium ? .orange : .blue)
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: DesignTokens.Space.s) {
                                            Text(finding.trackerName).font(.callout.weight(.medium))
                                            Text(finding.severity.label)
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(severityColor(finding.severity).opacity(0.15), in: Capsule())
                                                .foregroundStyle(severityColor(finding.severity))
                                        }
                                        Text(finding.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        Text(finding.impact).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Text((finding.isSizeComplete ? "" : "At least ") + ByteFormatting.format(finding.bytes))
                                        .font(.caption.monospacedDigit())
                                    Button("Stage") {
                                        state.stage(source: "Privacy", path: finding.path, bytes: finding.bytes)
                                    }
                                    .buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        } header: {
                            Label(category.label, systemImage: category.symbol)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { if case .notMeasured = engine.scanMeasurement { engine.scan() } }
        .onDisappear { engine.cancel() }
    }

    private func severityColor(_ s: PrivacyFinding.Severity) -> Color {
        switch s {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

private struct PrivacyScoreGauge: View {
    let measurement: Measurement<Int>
    private var score: Int? { measurement.availableValue }
    private var color: Color {
        switch score ?? -1 {
        case 80...100: return .green
        case 50..<80: return .orange
        default: return score == nil ? .secondary : .red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6).frame(width: 56, height: 56)
            Circle().trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "—").font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                Text(score == nil ? measurement.statusLabel : "heuristic /100").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    PrivacyView()
        .environmentObject(PrivacyScannerEngine())
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
