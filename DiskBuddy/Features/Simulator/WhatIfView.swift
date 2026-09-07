import SwiftUI

// MARK: - D3 "What If" Simulator view

struct WhatIfView: View {
    @EnvironmentObject var simulator: WhatIfSimulator
    @EnvironmentObject var state: AppState

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Simulated Deletions").font(.headline)
                    Spacer()
                    Button("Clear All") { simulator.clear() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(DesignTokens.Space.m)
                Divider()
                if simulator.staged.isEmpty {
                    VStack(spacing: DesignTokens.Space.m) {
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 48)).foregroundStyle(.tertiary)
                        Text("Stage items from any view to simulate").foregroundStyle(.secondary)
                        Text("Nothing will be deleted until you commit").font(.caption).foregroundStyle(.tertiary)
                        Button("Stage Library Caches (demo)") {
                            if let lib = MockScanData.topLevel.first(where: { $0.name == "Library" }),
                               let caches = lib.children.first(where: { $0.name == "Caches" }) {
                                simulator.stage(caches)
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(simulator.staged) { action in
                            HStack {
                                Circle()
                                    .fill(riskColor(action.risk))
                                    .frame(width: 8, height: 8)
                                Text(action.name).lineLimit(1)
                                Spacer()
                                Text(ByteFormatting.format(action.bytes))
                                    .font(.caption.monospacedDigit())
                                Text(action.risk.label)
                                    .font(.caption2)
                                    .foregroundStyle(riskColor(action.risk))
                                Button { simulator.remove(action) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 320)
            VStack(spacing: DesignTokens.Space.l) {
                Text("Impact Preview").font(.title2.weight(.semibold))
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                        .frame(width: 120, height: 120)
                    VStack(spacing: 2) {
                        Text("+\(ByteFormatting.format(simulator.totalBytes))")
                            .font(.title3.weight(.bold)).foregroundStyle(.green).monospacedDigit()
                        Text("would free").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: DesignTokens.Space.xl) {
                    ImpactStat(label: "Would Free", value: ByteFormatting.format(simulator.totalBytes), color: .green)
                    ImpactStat(label: "Items", value: "\(simulator.staged.count)", color: .blue)
                }
                VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                    Text("Risk Assessment").font(.headline)
                    RiskRow(label: "Safe to remove", bytes: simulator.safeBytes, color: .green)
                    RiskRow(label: "Review recommended", bytes: simulator.cautionBytes, color: .orange)
                    RiskRow(label: "Risky", bytes: simulator.riskyBytes, color: .red)
                }
                if simulator.riskyBytes > 0 {
                    Label("\(simulator.staged.filter { $0.risk == .dangerous }.count) items are risky to remove", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button("Commit to Cleanup Queue") { simulator.commit(to: state) }
                    .buttonStyle(.borderedProminent)
                    .disabled(simulator.staged.isEmpty)
            }
            .frame(minWidth: 320)
            .padding()
        }
    }

    private func riskColor(_ risk: CleanupRisk) -> Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
}

private struct ImpactStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct RiskRow: View {
    let label: String
    let bytes: Int64
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.callout)
            Spacer()
            Text(ByteFormatting.format(bytes)).font(.caption.monospacedDigit())
        }
    }
}

#Preview {
    WhatIfView()
        .environmentObject(WhatIfSimulator())
        .environmentObject(AppState())
        .frame(width: 800, height: 500)
}
