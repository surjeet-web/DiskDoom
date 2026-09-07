import SwiftUI
import Charts

// MARK: - D2 Disk Space Forecast view (Swift Charts, macOS 13+)

struct DiskForecastView: View {
    @EnvironmentObject var engine: DiskForecastEngine

    var body: some View {
        VStack(spacing: 0) {
            if let forecast = engine.forecast {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disk Space Forecast").font(.title2.weight(.semibold))
                        Text("\(forecast.isFilling ? "Filling up" : "Stable") · \(String(format: "%+.2f", forecast.dailyGrowthGB)) GB/day")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let days = forecast.daysUntilFull, days < 90 {
                        VStack(alignment: .trailing) {
                            Label("Full in \(days) days", systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(days < 30 ? .red : .orange)
                            if let date = forecast.fillDate {
                                Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(DesignTokens.Space.m)
                Divider()
                Chart {
                    ForEach(forecast.points.filter { !$0.isPrediction }) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Used", point.usedGB))
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Date", point.date), y: .value("Used", point.usedGB))
                            .foregroundStyle(.blue)
                    }
                    ForEach(forecast.points.filter(\.isPrediction)) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Used", point.usedGB))
                            .foregroundStyle(.orange.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                    RuleMark(y: .value("Capacity", forecast.totalGB))
                        .foregroundStyle(.red.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 0...(forecast.totalGB * 1.05))
                .frame(height: 250)
                .padding()
                Divider()
                HStack(spacing: DesignTokens.Space.xl) {
                    ForecastStatCard(label: "Free Space", value: String(format: "%.0f GB", forecast.freeGB), color: .green)
                    ForecastStatCard(label: "Daily Growth", value: String(format: "%+.2f GB", forecast.dailyGrowthGB), color: forecast.isFilling ? .red : .green)
                    ForecastStatCard(label: "Days Until Full", value: forecast.daysUntilFull.map(String.init) ?? "∞", color: (forecast.daysUntilFull ?? 999) < 30 ? .red : .green)
                }
                .padding()
            } else {
                EmptyState(symbol: "chart.line.uptrend.xyaxis", title: "Need at least 2 snapshots to forecast", message: "Save snapshots over time and DiskDoom will predict when you'll run out of space.")
            }
        }
        .onAppear { if engine.forecast == nil { engine.compute() } }
    }
}

private struct ForecastStatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.bold)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
    }
}

#Preview {
    DiskForecastView()
        .environmentObject({ let e = DiskForecastEngine(); e.compute(); return e }())
        .frame(width: 700, height: 600)
}
