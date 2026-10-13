import SwiftUI
import Combine

// MARK: - §18 Monitor Dashboard + §19 Process Table (REAL system stats)

struct MonitorView: View {
    @StateObject private var monitor = SystemMonitor()
    @State private var mode: Mode = .dashboard
    @State private var filter: ProcFilter = .all
    @State private var query = ""
    @State private var cpuHistory = MonitorSampleHistory()
    @State private var memHistory: [Double] = []
    @State private var selectedPID: Int32? = nil
    // Samples already arrive in CPU-descending order. Let native table clicks
    // supply comparators instead of creating a non-Sendable key path in State.
    @State private var sortOrder: [KeyPathComparator<LiveProcess>] = []

    enum Mode: String, CaseIterable { case dashboard, processes }
    enum ProcFilter: String, CaseIterable { case all, apple, other, active }

    var body: some View {
        VStack {
            Picker("Monitor", selection: $mode) {
                Text("Dashboard").tag(Mode.dashboard)
                Text("Processes").tag(Mode.processes)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .padding(.top, DesignTokens.Space.s)
            if mode == .dashboard {
                dashboard
            } else {
                processTable
            }
        }
        .padding(DesignTokens.Space.m)
        .onAppear {
            monitor.start()
        }
        .onDisappear { monitor.stop() }
        .onReceive(monitor.$cpuMeasurement) { measurement in
            cpuHistory.append(measurement.map { $0 / 100 })
        }
        .onReceive(monitor.$memoryUsedGB) { value in
            guard monitor.isMemoryAvailable else { return }
            memHistory.append(value / max(monitor.memoryTotalGB, 0.01))
            if memHistory.count > 60 { memHistory.removeFirst() }
        }
    }

    // MARK: §18 Dashboard (real gauges + real CPU/memory history)

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Space.l) {
                HStack(spacing: DesignTokens.Space.xl) {
                    GaugeView(title: "CPU", value: monitor.cpuMeasurement.availableValue.map { $0 / 100 } ?? 0, label: monitor.cpuMeasurement.availableValue.map { "\(Int($0))%" } ?? monitor.cpuMeasurement.statusLabel, tint: .blue)
                    GaugeView(title: "Memory", value: monitor.isMemoryAvailable ? monitor.memoryUsedGB / max(monitor.memoryTotalGB, 0.01) : 0, label: monitor.isMemoryAvailable ? "\(String(format: "%.1f", monitor.memoryUsedGB))/\(String(format: "%.0f", monitor.memoryTotalGB)) GB" : "Unavailable", tint: .purple)
                    GaugeView(title: "Processes", value: min(Double(monitor.processes.count) / 500, 1), label: "\(monitor.processes.count)", tint: .orange)
                    GaugeView(title: "Uptime", value: 1, label: monitor.uptimeText, tint: .green)
                }
                VStack(alignment: .leading) {
                    Text("Recent CPU History").font(.headline)
                    CPUHistoryChart(samples: cpuHistory.samples, tint: .blue)
                        .frame(height: 90)
                    Text(monitor.cpuMeasurement.reason ?? monitor.cpuMeasurement.source ?? monitor.cpuMeasurement.statusLabel)
                        .font(.caption).foregroundStyle(.secondary)
                    if let date = cpuHistory.samples.last?.measuredAt {
                        Text("Last CPU sample: \(date.formatted(date: .omitted, time: .standard)) · \(cpuHistory.samples.count) actual samples")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .specCard()
                VStack(alignment: .leading) {
                    Text("Recent Memory History").font(.headline)
                    Sparkline(values: memHistory, tint: .purple)
                        .frame(height: 90)
                }
                .specCard()
            }
        }
    }

    // MARK: §19 Real process table (NSWorkspace + proc_pidinfo)

    private var filtered: [LiveProcess] {
        var list = monitor.processes
        switch filter {
        case .all: break
        case .apple: list = list.filter { $0.bundleIdentifier?.hasPrefix("com.apple.") == true }
        case .other: list = list.filter { $0.bundleIdentifier?.hasPrefix("com.apple.") != true }
        case .active: list = list.filter { $0.cpuMeasurement.availableValue.map { $0 > 0.1 } == true }
        }
        if !query.isEmpty { list = list.filter { $0.name.lowercased().contains(query.lowercased()) } }
        return sortOrder.isEmpty ? list : list.sorted(using: sortOrder)
    }

    private var processTable: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("\(monitor.processes.count) apps running").font(.headline)
                Spacer()
                TextField("Search processes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Picker("Filter", selection: $filter) {
                    ForEach(ProcFilter.allCases, id: \.self) { f in
                        Text(f.rawValue.capitalized).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            Table(filtered, selection: $selectedPID, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { proc in
                    HStack(spacing: 6) {
                        if let icon = proc.icon {
                            Image(nsImage: icon)
                                .frame(width: 16, height: 16)
                        }
                        Text(proc.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                TableColumn("PID") { proc in
                    Text("\(proc.pid)")
                        .font(.callout.monospacedDigit())
                }
                .width(60)
                TableColumn("CPU", value: \.cpuSortValue) { proc in
                    Text(proc.cpuMeasurement.availableValue.map { String(format: "%.1f%%", $0) } ?? proc.cpuMeasurement.statusLabel)
                        .help(proc.cpuMeasurement.reason ?? proc.cpuMeasurement.source ?? "Waiting for a CPU delta baseline")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(proc.cpuMeasurement.availableValue.map { $0 > 10 } == true ? .red : .primary)
                }
                .width(70)
                TableColumn("Memory", value: \.residentBytes) { proc in
                    Text(proc.isResidentMemoryAvailable ? proc.residentBytes.fileSizeString : "—")
                        .font(.callout.monospacedDigit())
                }
                .width(90)
                TableColumn("Started") { proc in
                    Text(proc.launchDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(100)
            }
            .frame(minHeight: 300)
            if let pid = selectedPID, let proc = filtered.first(where: { $0.pid == pid }) {
                Divider()
                HStack(spacing: DesignTokens.Space.xl) {
                    if let icon = proc.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proc.name).font(.headline)
                        Text("PID \(proc.pid)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    specRow("CPU", value: proc.cpuMeasurement.availableValue.map { String(format: "%.1f%%", $0) } ?? proc.cpuMeasurement.statusLabel)
                    specRow("Memory (resident)", value: proc.isResidentMemoryAvailable ? proc.residentBytes.fileSizeString : "Unavailable")
                    if let launched = proc.launchDate {
                        specRow("Started", value: launched.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .padding(DesignTokens.Space.s)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            }
        }
    }

    private func specRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }
}

// MARK: - Circular gauge (§18)

private struct GaugeView: View {
    let title: String
    let value: Double
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 10)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 80, height: 80)
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 70)
                    .multilineTextAlignment(.center)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sparkline history chart (§18)

private struct CPUHistoryChart: View {
    let samples: [MonitorSampleHistory.Sample]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard let first = samples.first, let last = samples.last else { return }
            let duration = last.measuredAt.timeIntervalSince(first.measuredAt)
            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = duration > 0 ? size.width * sample.measuredAt.timeIntervalSince(first.measuredAt) / duration : size.width / 2
                let y = size.height * (1 - min(max(sample.value, 0), 1))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
                context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(tint))
            }
            context.stroke(path, with: .color(tint), lineWidth: 2)
        }
        .accessibilityLabel("CPU history, \(samples.count) actual timestamped samples")
    }
}

private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat(min(max(v, 0), 1)))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(tint), lineWidth: 2)
        }
    }
}

#Preview {
    MonitorView()
        .frame(width: 800, height: 600)
}
