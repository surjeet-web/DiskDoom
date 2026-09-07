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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy Scanner").font(.title2.weight(.semibold))
                    Text("Third-party SDK caches only — never browser profiles or passwords")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PrivacyScoreGauge(score: engine.score)
                Button("Scan") { engine.scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isScanning)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            if engine.isScanning {
                ProgressView("Scanning for tracking data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if engine.findings.isEmpty {
                EmptyState(symbol: "lock.shield.fill", title: "No tracking data detected", message: "Run a scan to look for ad, analytics, and crash SDK caches.", actionTitle: "Scan", action: { engine.scan() })
            } else {
                HStack(spacing: DesignTokens.Space.xl) {
                    Text("\(engine.findings.count) findings").font(.headline)
                    Text(ByteFormatting.format(engine.totalBytes)).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.vertical, DesignTokens.Space.s)
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
                                    Text(ByteFormatting.format(finding.bytes))
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
        .onAppear { if engine.findings.isEmpty { engine.scan() } }
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
    let score: Int
    private var color: Color {
        switch score {
        case 80...100: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6).frame(width: 56, height: 56)
            Circle().trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                Text("/100").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    PrivacyView()
        .environmentObject({ let e = PrivacyScannerEngine(); e.scan(); return e }())
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
