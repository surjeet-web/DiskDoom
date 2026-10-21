import SwiftUI

// MARK: - D11 Disk Health view

struct DiskHealthView: View {
    @EnvironmentObject var engine: DiskHealthEngine
    @EnvironmentObject var state: AppState
    @EnvironmentObject var inventory: AppInventoryService
    @EnvironmentObject var lifecycle: AppLifecycleEngine

    var body: some View {
        ScrollView {
            if let score = engine.score {
                VStack(spacing: DesignTokens.Space.xl) {
                    VStack(spacing: DesignTokens.Space.m) {
                        ZStack {
                            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 16)
                                .frame(width: 160, height: 160)
                            Circle()
                                .trim(from: 0, to: CGFloat(score.overall) / 100)
                                .stroke(healthColor(score.overall), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                .frame(width: 160, height: 160)
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 4) {
                                Text(score.grade)
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(healthColor(score.overall))
                                Text("\(score.overall)/100")
                                    .font(.title3.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(score.recommendation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .industrialPanel(.canopy, flatSide: .left, accent: DesignTokens.Palette.teal)
                    .accessibleChart(summary: "Disk health grade \(score.grade), score \(score.overall) out of 100. Junk \(score.junkPercent) percent, stale \(score.stalePercent) percent, cache bloat \(score.cacheBloatScore) out of 100. \(score.recommendation)")
                    VStack(spacing: DesignTokens.Space.m) {
                        HealthComponentRow(label: "Junk Files", badPercent: score.junkPercent, icon: "trash")
                        HealthComponentRow(label: "Stale Files", badPercent: score.stalePercent, icon: "clock.badge.exclamationmark")
                        HealthComponentRow(label: "Cache Bloat", badPercent: score.cacheBloatScore, icon: "archivebox")
                        HealthComponentRow(
                            label: lifecycle.trackedDaysSinceLaunch.isEmpty
                                ? "Unused Apps (not tracked yet)"
                                : "Unused Apps",
                            badPercent: score.unusedAppRatio,
                             icon: "app.badge.checkmark")
                    }
                    .industrialPanel(.well, flatSide: .right, accent: DesignTokens.Palette.teal)
                    Divider()
                    VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
                        Text("Recommended Actions").font(.headline)
                        ForEach(Array(score.improvements.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: DesignTokens.Space.m) {
                                VStack(alignment: .leading) {
                                    Text(item.action).font(.callout)
                                }
                                Spacer()
                                Text("~ free up to \(ByteFormatting.format(item.potentialSaving))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.green)
                                    .frame(width: 150, alignment: .trailing)
                            }
                            .padding(DesignTokens.Space.s)
                            .background(.quaternary.opacity(0.15))
                        }
                    }
                    .industrialPanel(.boot, flatSide: .left, accent: DesignTokens.Palette.orange)
                }
                .padding()
            } else {
                VStack(spacing: DesignTokens.Space.m) {
                    Spacer()
                    Image(systemName: state.scanRoot == nil ? "magnifyingglass" : "hourglass")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text(state.scanRoot == nil
                         ? "Scan to see your disk health score"
                         : "Not enough data yet")
                        .font(.title3.weight(.semibold))
                    Text(state.scanRoot == nil
                         ? "The grade is computed from your scan results. Nothing is measured until you scan."
                         : "A health grade needs at least \(DiskHealthEngine.minimumRecordsForScore.formatted()) indexed files — this scan indexed \(state.records.count.formatted()).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: [state.records.count, inventory.apps.count, lifecycle.trackedDaysSinceLaunch.count]) {
            engine.compute(records: state.records, apps: inventory.apps, unusedBundleIDs: Set(lifecycle.trackedDaysSinceLaunch.filter { $0.value > 90 }.keys))
        }
    }

    private func healthColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}

private struct HealthComponentRow: View {
    let label: String
    let badPercent: Int // raw 0–100, higher = worse
    let icon: String

    private var health: Int { max(0, 100 - badPercent) }
    private var color: Color {
        switch health {
        case 80...100: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 20)
            Text(label).font(.callout).frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.2))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(health) / 100)
                    }
            }
            .frame(height: 10)
            Text("\(health)").font(.caption.monospacedDigit()).foregroundStyle(color)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

#Preview {
    DiskHealthView()
        .environmentObject({ let e = DiskHealthEngine(); e.compute(records: [], apps: []); return e }())
        .environmentObject(AppState())
        .environmentObject(AppInventoryService())
        .environmentObject(AppLifecycleEngine())
        .frame(width: 700, height: 600)
}
