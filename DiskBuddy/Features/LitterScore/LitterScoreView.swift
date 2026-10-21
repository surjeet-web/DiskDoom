import SwiftUI

// MARK: - D1 App Litter Score view

struct LitterScoreView: View {
    @EnvironmentObject var engine: LitterScoreEngine
    @EnvironmentObject var state: AppState
    @EnvironmentObject var inventory: AppInventoryService
    @EnvironmentObject var lifecycle: AppLifecycleEngine
    @State private var sortWorstFirst = true

    private var entries: [LitterScoreEntry] {
        sortWorstFirst ? engine.entries : engine.entries.sorted { $0.appName < $1.appName }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Litter Scores")
                        .font(.title2.weight(.semibold))
                    Text("Average: \(engine.averageScore)/100 · Total Litter: \(ByteFormatting.format(engine.totalLitter))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Picker("Sort", selection: $sortWorstFirst) {
                    Text("Worst First").tag(true)
                    Text("Name A-Z").tag(false)
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            ScrollView {
                if entries.isEmpty {
                    EmptyState(symbol: "gauge.with.dots.needle.67percent", title: "No app data yet", message: "App litter scores are computed from your installed apps. Open the Applications tab to scan your inventory.")
                } else {
                    LazyVStack(spacing: DesignTokens.Space.s) {
                        ForEach(entries) { entry in
                            LitterScoreCard(entry: entry)
                        }
                    }
                    .padding(DesignTokens.Space.m)
                }
            }
        }
        .task(id: inventory.apps.count) {
            engine.compute(apps: inventory.apps, launchDays: lifecycle.trackedDaysSinceLaunch)
        }
    }
}

private struct LitterScoreCard: View {
    @EnvironmentObject var state: AppState
    let entry: LitterScoreEntry

    private var color: Color {
        switch entry.score {
        case 0..<30: return .green
        case 30..<60: return .yellow
        case 60..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack(spacing: DesignTokens.Space.m) {
                ZStack {
                    Circle().stroke(color.opacity(0.3), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(entry.score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(entry.score)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignTokens.Space.s) {
                        Text(entry.appName).font(.headline)
                        Text(entry.scoreLabel)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(color.opacity(0.2), in: Capsule())
                            .foregroundStyle(color)
                    }
                    Text("Bundle: \(ByteFormatting.format(entry.bundleBytes)) · Artifacts: \(ByteFormatting.format(entry.artifactBytes)) · Ratio: \(String(format: "%.1f", entry.artifactRatio))x")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(ByteFormatting.format(entry.artifactBytes))
                        .font(.title3.weight(.medium)).monospacedDigit()
                    Text("litter").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(entry.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.2))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(entry.score) / 100)
                    }
            }
            .frame(height: 8)
            HStack {
                if let rec = entry.recommendation {
                    Button(rec) {
                        for path in entry.artifactPaths {
                            state.stage(source: "Litter Score", path: path)
                        }
                        state.showCleanup = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(entry.artifactPaths.isEmpty)
                }
                Spacer()
            }
        }
        .padding(24)
        .background {
            MetalSurface(family: .plate, flatSide: .right, accent: DesignTokens.Palette.orange)
        }
    }
}

#Preview {
    LitterScoreView()
        .environmentObject({ let e = LitterScoreEngine(); e.compute(apps: []); return e }())
        .environmentObject(AppState())
        .environmentObject(AppInventoryService())
        .environmentObject(AppLifecycleEngine())
        .frame(width: 700, height: 500)
}
