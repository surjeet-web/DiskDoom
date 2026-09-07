import SwiftUI
import Combine

// MARK: - §18 Monitor Dashboard + §19 Process Table (REAL system stats)

struct MonitorView: View {
    @StateObject private var monitor = SystemMonitor()
    @State private var mode: Mode = .dashboard
    @State private var filter: ProcFilter = .all
    @State private var query = ""
    @State private var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @State private var selectedPID: Int32? = nil

    enum Mode: String, CaseIterable { case dashboard, processes }
    enum ProcFilter: String, CaseIterable { case all, user, system, active }

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
            cpuHistory = Array(repeating: monitor.cpuPercent / 100, count: 60)
        }
        .onDisappear { monitor.stop() }
        .onReceive(monitor.$cpuPercent) { value in
            cpuHistory.append(value / 100)
            if cpuHistory.count > 60 { cpuHistory.removeFirst() }
        }
    }

    // MARK: §18 Dashboard (real gauges + real CPU history)

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Space.l) {
                HStack(spacing: DesignTokens.Space.xl) {
                    GaugeView(title: "CPU", value: monitor.cpuPercent / 100, label: "\(Int(monitor.cpuPercent))%", tint: .blue)
                    GaugeView(title: "Memory", value: monitor.memoryUsedGB / max(monitor.memoryTotalGB, 0.01), label: "\(String(format: "%.1f", monitor.memoryUsedGB))/\(String(format: "%.0f", monitor.memoryTotalGB)) GB", tint: .purple)
                    GaugeView(title: "Processes", value: min(Double(monitor.processes.count) / 500, 1), label: "\(monitor.processes.count)", tint: .orange)
                    GaugeView(title: "Uptime", value: 1, label: monitor.uptimeText, tint: .green)
                }
                VStack(alignment: .leading) {
                    Text("CPU History (60s)").font(.headline)
                    Sparkline(values: cpuHistory, tint: .blue)
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
        case .user: list = list.filter { !$0.name.lowercased().hasPrefix("com.apple.") }
        case .system: list = list.filter { $0.pid < 500 }
        case .active: list = list.filter { $0.cpuPercent > 0.1 }
        }
        if !query.isEmpty { list = list.filter { $0.name.lowercased().contains(query.lowercased()) } }
        return list.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    private var processTable: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("\(monitor.processes.count) processes").font(.headline)
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
            HSplitView {
                List(filtered, id: \.id, selection: $selectedPID) { proc in
                    HStack(spacing: DesignTokens.Space.m) {
                        Text("\(proc.pid)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 50, alignment: .trailing)
                        Text(proc.name)
                            .frame(width: 180, alignment: .leading)
                            .lineLimit(1)
                        Text(String(format: "%.1f%%", proc.cpuPercent))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(proc.cpuPercent > 10 ? .red : .primary)
                            .frame(width: 60, alignment: .trailing)
                        Text(proc.residentBytes > 0 ? proc.residentBytes.fileSizeString : "—")
                            .font(.callout.monospacedDigit())
                            .frame(width: 80, alignment: .trailing)
                        Spacer()
                        Text(proc.launchDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(proc.pid)
                }
                .listStyle(.plain)
                .frame(minWidth: 400)
                if let pid = selectedPID, let proc = filtered.first(where: { $0.pid == pid }) {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                        Text(proc.name).font(.headline)
                        Text("PID \(proc.pid)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Divider()
                        specRow("CPU", value: String(format: "%.1f%%", proc.cpuPercent))
                        specRow("Memory (resident)", value: proc.residentBytes > 0 ? proc.residentBytes.fileSizeString : "Restricted (SIP)")
                        if let launched = proc.launchDate {
                            specRow("Started", value: launched.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .padding(DesignTokens.Space.m)
                    .frame(minWidth: 200, idealWidth: 240)
                }
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
