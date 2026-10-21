import SwiftUI
import Charts

// MARK: - Disk Forecast view: alerts, trend, chart, category growth, history

struct DiskForecastView: View {
    @EnvironmentObject var engine: DiskForecastEngine
    @EnvironmentObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            content
        }
    }

    private var content: some View {
        ScrollView {
            if let forecast = engine.forecast {
                VStack(spacing: DesignTokens.Space.l) {
                    if !engine.alerts.isEmpty {
                        alertsSection
                    }
                    forecastHeader(forecast)
                    chartSection(forecast)
                    trendCards(forecast)
                    if !forecast.categoryGrowth.isEmpty {
                        categoryGrowthSection(forecast)
                    }
                    historySection(forecast)
                }
                .padding()
            } else if engine.isComputing {
                ProgressView("Computing forecast…")
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                insufficientDataView
            }
        }
        .task {
            if engine.forecast == nil, !engine.isComputing {
                await engine.compute()
            }
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        VStack(spacing: DesignTokens.Space.s) {
            ForEach(engine.alerts) { alert in
                HStack(alignment: .top, spacing: DesignTokens.Space.m) {
                    Image(systemName: alert.severity.icon)
                        .foregroundStyle(alert.severity.color)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title).font(.callout.weight(.semibold))
                        Text(alert.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let tab = alert.actionTab {
                        Button("Take Action") {
                            state.sidebarTab = tab
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .padding(24)
                .background {
                    MetalSurface(family: .boot, flatSide: .right, accent: alert.severity.color, active: true)
                }
            }
        }
    }

    // MARK: - Header (big number + trend + projections)

    private func forecastHeader(_ forecast: DiskForecast) -> some View {
        HStack(spacing: DesignTokens.Space.xl) {
            VStack(spacing: DesignTokens.Space.s) {
                if case .estimatedFull(let days) = forecast.riskEvidence() {
                    Text("\(days)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(days <= 7 ? .red : days <= 30 ? .orange : .primary)
                    Text(days == 1 ? "1 day or less until full (estimate)" : "days until full (estimate)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if forecast.riskEvidence() == .insufficient || forecast.riskEvidence() == .stale {
                    // `daysUntilFull == nil` means either "no risk" or "not
                    // enough history" — showing a green tick for the latter
                    // would be its own lie.
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(forecast.riskEvidence().label)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                    Text("Needs \(Int(DiskForecastEngine.minimumDaySpanForProjection))+ days of snapshots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if forecast.riskEvidence() == .noRiskDetected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("No fill risk detected")
                        .font(.title3.weight(.medium))
                    Text(forecast.trendDirection == .stable ? "Usage is stable" : "Usage is decreasing")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40)).foregroundStyle(.orange)
                    Text(forecast.riskEvidence().label)
                        .font(.title3.weight(.medium)).multilineTextAlignment(.center)
                }
            }
            .frame(width: 180)
            .accessibleChart(summary: "Disk forecast: \(forecast.trendDirection.label), \(forecast.dailyChangeFormatted). \(forecast.riskEvidence().label).")

            Divider().frame(height: 90)

            VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                HStack(spacing: 8) {
                    Image(systemName: forecast.trendDirection.icon)
                        .foregroundStyle(forecast.trendDirection.color)
                    Text(forecast.trendDirection.label)
                        .font(.headline)
                        .foregroundStyle(forecast.trendDirection.color)
                }
                HStack(spacing: 6) {
                    Text("Daily").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                    Text(forecast.dailyChangeFormatted).font(.caption.weight(.medium).monospacedDigit())
                }
                HStack(spacing: 6) {
                    Text("Weekly").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                    Text(forecast.weeklyChangeFormatted).font(.caption.weight(.medium).monospacedDigit())
                }
                HStack(spacing: 4) {
                    Image(systemName: forecast.confidenceLevel.icon).font(.caption)
                    Text(forecast.confidenceLevel.label).font(.caption)
                }
                .foregroundStyle(forecast.confidenceLevel.color)
                Text("\(forecast.dataPointCount) data points")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let latest = forecast.history.last {
                    Text("Measured: \(latest.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(latest.measurementSource ?? "Unverified source") · 24-hour freshness")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if engine.history.count > forecast.history.count {
                    Text("\(engine.history.count - forecast.history.count) legacy/unverified, future or incompatible records retained but excluded")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider().frame(height: 90)

            VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                Text("Projections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
                if forecast.hasReliableProjection && forecast.riskEvidence() != .stale {
                    ProjectionRow(label: "30 days", current: forecast.currentUsed, projected: forecast.projectedUsage30Days, capacity: forecast.totalCapacity)
                    ProjectionRow(label: "90 days", current: forecast.currentUsed, projected: forecast.projectedUsage90Days, capacity: forecast.totalCapacity)
                } else {
                    // Projecting from < 7 days of history produced figures like
                    // "100% used, +412 GB" with no indication the model had
                    // simply saturated. Show nothing rather than nonsense.
                    Text("Projections need \(Int(DiskForecastEngine.minimumDaySpanForProjection))+ days of history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let critical = forecast.criticalDate {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("10% free: \(critical.formatted(date: .abbreviated, time: .omitted)) (not full)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Spacer()
        }
        .padding(24)
        .background {
            MetalSurface(family: .canopy, flatSide: .left, accent: DesignTokens.Palette.cyan)
        }
    }

    // MARK: - Chart (Swift Charts: solid history, dashed projection, thresholds)

    private func chartSection(_ forecast: DiskForecast) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text("Usage Over Time").font(.headline)
                Spacer()
                HStack(spacing: DesignTokens.Space.m) {
                    chartLegend(color: .blue, label: "Historical", dashed: false)
                    chartLegend(color: .blue.opacity(0.4), label: "Projected", dashed: true)
                    chartLegend(color: .red, label: "90% used", dashed: true)
                    chartLegend(color: .orange, label: "80% used", dashed: true)
                }
                .font(.caption)
            }
            .padding(.horizontal, DesignTokens.Space.m)

            Chart {
                ForEach(forecast.points.filter { !$0.isProjected }) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Used", Double(point.usedBytes) / 1_073_741_824))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Used", Double(point.usedBytes) / 1_073_741_824))
                    .foregroundStyle(.blue)
                }
                ForEach(forecast.points.filter(\.isProjected)) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Used", Double(point.usedBytes) / 1_073_741_824))
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                RuleMark(y: .value("Critical", Double(forecast.totalCapacity) * 0.9 / 1_073_741_824))
                    .foregroundStyle(.red.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("Warning", Double(forecast.totalCapacity) * 0.8 / 1_073_741_824))
                    .foregroundStyle(.orange.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartYScale(domain: 0...(Double(forecast.totalCapacity) / 1_073_741_824 * 1.05))
            .chartYAxisLabel("GB used")
            .frame(height: 240)
            .padding(.horizontal, DesignTokens.Space.m)
            .padding(.bottom, DesignTokens.Space.m)
        }
        .padding(20)
        .background {
            MetalSurface(family: .well, flatSide: .right, accent: DesignTokens.Palette.cyan)
        }
    }

    private func chartLegend(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 16, height: 2)
                .overlay(alignment: .center) {
                    if dashed {
                        Color.clear.frame(width: 16, height: 2)
                    }
                }
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Trend cards

    private func trendCards(_ forecast: DiskForecast) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300))], spacing: DesignTokens.Space.m) {
            TrendCard(
                title: "Current Usage",
                value: ByteFormatting.format(forecast.currentUsed),
                subtitle: String(format: "%.1f%% of %@", Double(forecast.currentUsed) / Double(max(forecast.totalCapacity, 1)) * 100, ByteFormatting.format(forecast.totalCapacity)),
                icon: "internaldrive.fill", color: .blue)
            TrendCard(
                title: "Free Space",
                value: ByteFormatting.format(forecast.currentFree),
                subtitle: String(format: "%.1f%%", Double(forecast.currentFree) / Double(max(forecast.totalCapacity, 1)) * 100),
                icon: "checkmark.circle", color: .green)
            TrendCard(
                title: "Daily Change",
                value: forecast.dailyChangeFormatted,
                subtitle: forecast.trendDirection.label,
                icon: forecast.trendDirection.icon,
                color: forecast.trendDirection.color)
            if let warning = forecast.warningDate {
                TrendCard(
                    title: "Below 20% Free",
                    value: warning.formatted(date: .abbreviated, time: .omitted),
                    subtitle: "\(max(0, Int(warning.timeIntervalSinceNow / 86_400)))) days",
                    icon: "exclamationmark.triangle.fill", color: .orange)
            }
        }
    }

    // MARK: - Category growth

    private func categoryGrowthSection(_ forecast: DiskForecast) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            Text("Category Growth").font(.headline)
                .padding(.horizontal, DesignTokens.Space.m)
            Text("Comparing explicit category measurements only; missing categories are not zero.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Space.m)
            let maxCategory = forecast.categoryGrowth.map(\.currentSize).max() ?? 1
            ForEach(forecast.categoryGrowth) { growth in
                HStack(spacing: DesignTokens.Space.m) {
                    Text(growth.category.capitalized)
                        .font(.callout)
                        .frame(width: 100, alignment: .leading)
                    Text(growth.currentFormatted)
                        .font(.callout.monospacedDigit())
                        .frame(width: 72, alignment: .trailing)
                    HStack(spacing: 4) {
                        Image(systemName: growth.changeBytes == 0 ? "arrow.right" : growth.isGrowing ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                            .foregroundStyle(growth.isGrowing ? .red : .green)
                        Text((growth.changeBytes == 0 ? "" : growth.isGrowing ? "+" : "-") + growth.changeFormatted)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(growth.isGrowing ? .red : .green)
                    }
                    .frame(width: 84, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(growth.isGrowing ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(growth.isGrowing ? Color.red.opacity(0.5) : Color.green.opacity(0.5))
                                    .frame(width: max(geo.size.width * CGFloat(growth.currentSize) / CGFloat(max(maxCategory, 1)), 2))
                            }
                    }
                    .frame(height: 14)
                    Text(growth.dailyRateFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, DesignTokens.Space.m)
            }
        }
        .padding(20)
        .background {
            MetalSurface(family: .tiered, flatSide: .left, accent: DesignTokens.Palette.violet)
        }
    }

    // MARK: - History table

    private func historySection(_ forecast: DiskForecast) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text("Usage History").font(.headline)
                Spacer()
                Text("\(forecast.history.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Space.m)

            HStack(spacing: DesignTokens.Space.m) {
                Text("Date").font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Text("Source").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Text("Used").font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
                Text("Free").font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
                Text("% Used").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Space.m)

            ForEach(Array(forecast.history.suffix(20).reversed())) { snapshot in
                HStack(spacing: DesignTokens.Space.m) {
                    Text(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .frame(width: 110, alignment: .leading)
                    Text(snapshot.source.rawValue.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .frame(width: 70, alignment: .leading)
                    Text(ByteFormatting.format(snapshot.usedSize))
                        .font(.caption.monospacedDigit())
                        .frame(width: 72, alignment: .trailing)
                    Text(ByteFormatting.format(snapshot.freeSize))
                        .font(.caption.monospacedDigit())
                        .frame(width: 72, alignment: .trailing)
                    let percent = snapshot.usedPercent
                    Text(String(format: "%.1f%%", percent))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(percent > 90 ? .red : percent > 75 ? .orange : .secondary)
                        .frame(width: 60, alignment: .trailing)
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Insufficient data

    private var insufficientDataView: some View {
        VStack(spacing: DesignTokens.Space.l) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(engine.forecastMeasurement.statusLabel).font(.title2.weight(.semibold))
            Text(engine.forecastMeasurement.reason ?? "DiskDoom records disk usage at launch and scan. At least three comparable snapshots spanning seven days are needed for risk estimates.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                Label("Usage is recorded automatically at each launch", systemImage: "1.circle.fill")
                    .foregroundStyle(Color.blue)
                Label("Run scans to record category breakdowns too", systemImage: "2.circle.fill")
                    .foregroundStyle(Color.blue)
                Label("After 7+ days, full forecasting with projections", systemImage: "3.circle.fill")
                    .foregroundStyle(Color.blue)
            }
            .font(.callout)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Subviews

private struct ProjectionRow: View {
    let label: String
    let current: Int64
    let projected: Int64
    let capacity: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                let change = projected - current
                Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2)
                    .foregroundStyle(change > 0 ? .red : .green)
                Text(ByteFormatting.format(projected))
                    .font(.callout.weight(.medium).monospacedDigit())
                Text((change > 0 ? "+" : "") + ByteFormatting.format(change))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(change > 0 ? .red : .green)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(projected > Int64(Double(capacity) * 0.9) ? Color.red.opacity(0.5) : Color.blue.opacity(0.3))
                            .frame(width: max(geo.size.width * CGFloat(projected) / CGFloat(max(capacity, 1)), 2))
                    }
            }
            .frame(height: 4)
        }
    }
}

private struct TrendCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background {
            MetalSurface(family: .plate, flatSide: .bottom, accent: color)
        }
    }
}

#Preview {
    DiskForecastView()
        .environmentObject(DiskForecastEngine())
        .environmentObject(AppState())
        .frame(width: 900, height: 620)
}
