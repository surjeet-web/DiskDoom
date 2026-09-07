import SwiftUI

// MARK: - §18 Monitor Dashboard + §19 Process Table (mock 1s polling)

struct MonitorView: View {
    @State private var mode: Mode = .dashboard
    @State private var cpu: Double = 42
    @State private var memoryGB: Double = 12.4
    @State private var diskMBps: Double = 24
    @State private var cpuHistory: [Double] = Array(repeating: 0.4, count: 60)
    @State private var processes: [ProcEntry] = MockProcesses.all
    @State private var timer: Timer? = nil
    @State private var filter: ProcFilter = .all
    @State private var query = ""

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
        .onAppear { startPolling() }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: §18 Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Space.l) {
                HStack(spacing: DesignTokens.Space.xl) {
                    GaugeView(title: "CPU", value: cpu / 100, label: "\(Int(cpu))%", tint: .blue)
                    GaugeView(title: "Memory", value: memoryGB / 16, label: "\(String(format: "%.1f", memoryGB))/16 GB", tint: .purple)
                    GaugeView(title: "Disk I/O", value: min(diskMBps / 100, 1), label: "\(Int(diskMBps)) MB/s", tint: .orange)
                    GaugeView(title: "Uptime", value: 1, label: "3d 14h", tint: .green)
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

    // MARK: §19 Process table

    private var filtered: [ProcEntry] {
        var list = processes.sorted { $0.cpu > $1.cpu }
        switch filter {
        case .all: break
        case .user: list = list.filter { !$0.isSystem }
        case .system: list = list.filter(\.isSystem)
        case .active: list = list.filter { $0.cpu > 0 }
        }
        if !query.isEmpty { list = list.filter { $0.name.lowercased().contains(query.lowercased()) } }
        return list
    }

    private var processTable: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("\(processes.count) processes").font(.headline)
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
            List(filtered) { proc in
                HStack(spacing: DesignTokens.Space.m) {
                    Text("\(proc.pid)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 50, alignment: .trailing)
                    Text(proc.name)
                        .frame(width: 180, alignment: .leading)
                        .lineLimit(1)
                    Text(String(format: "%.1f%%", proc.cpu))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(proc.cpu > 10 ? .red : .primary)
                        .frame(width: 60, alignment: .trailing)
                    Text(proc.memoryBytes.fileSizeString)
                        .font(.callout.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text("\(proc.threads)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Spacer()
                    Text(proc.isSystem ? "System" : "Running")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background((proc.isSystem ? Color.purple : Color.green).opacity(0.15))
                        .foregroundStyle(proc.isSystem ? .purple : .green)
                        .clipShape(.capsule)
                }
            }
            .listStyle(.plain)
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                cpu = max(5, min(95, cpu + Double.random(in: -6...6)))
                memoryGB = max(8, min(15.5, memoryGB + Double.random(in: -0.3...0.3)))
                diskMBps = max(2, min(120, diskMBps + Double.random(in: -8...8)))
                cpuHistory.append(cpu / 100)
                if cpuHistory.count > 60 { cpuHistory.removeFirst() }
                for i in processes.indices {
                    processes[i].cpu = max(0, processes[i].cpu + Double.random(in: -0.8...0.8))
                }
            }
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
