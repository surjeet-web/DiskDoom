import SwiftUI

// MARK: - §20 Snapshots List + §21 Comparison (real persisted snapshots + CSV export)

struct SnapshotsView: View {
    @EnvironmentObject var state: AppState
    @State private var comparing = false

    private var dateText: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            HStack {
                Text("\(state.snapshots.count) snapshots").font(.headline)
                Spacer()
                Button("Export CSV") { exportCSV() }
                    .buttonStyle(.bordered)
                    .disabled(state.snapshots.isEmpty)
                Button("Save Current Scan") {
                    state.saveSnapshotFromCurrentScan(label: "Manual")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.scanRoot == nil)
                if state.compareIDs.count == 2 {
                    Button("Compare Selected") { comparing = true }
                        .buttonStyle(.bordered)
                }
            }
            if state.snapshots.isEmpty {
                EmptyState(symbol: "camera", title: "No snapshots yet", message: "Snapshots save automatically after each scan (or save manually). They persist as compressed JSON in Application Support.")
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Space.m) {
                        ForEach(state.snapshots) { snap in
                            SnapshotCard(snap: snap, dateText: dateText)
                        }
                    }
                }
            }
            Text("Storage: \(state.snapshots.count) snapshots · Auto-save: After each scan · Retention: \(state.snapshotRetention)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
        .sheet(isPresented: $comparing) {
            SnapshotComparisonView()
                .environmentObject(state)
        }
    }

    private func exportCSV() {
        let rows: [[String]] = [["Date", "Label", "Target", "Total Bytes", "Files"]] + state.snapshots.map {
            [dateText.string(from: $0.date), $0.label, $0.target, "\($0.totalBytes)", "\($0.files)"]
        }
        _ = ExportService.csvURL(rows: rows, suggestedName: "diskbuddy-snapshots.csv")
    }
}

// MARK: - Snapshot card (§20)

private struct SnapshotCard: View {
    @EnvironmentObject var state: AppState
    let snap: Snapshot
    let dateText: DateFormatter

    var body: some View {
        HStack(spacing: DesignTokens.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(snap.label) · \(dateText.string(from: snap.date))")
                    .font(.body.weight(.medium))
                Text("\(snap.totalBytes.fileSizeString) used · \(snap.files.formatted()) files · \(snap.target) scan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Compare", isOn: Binding(
                get: { state.compareIDs.contains(snap.id) },
                set: { on in
                    if on {
                        if state.compareIDs.count < 2 { state.compareIDs.append(snap.id) }
                    } else {
                        state.compareIDs.removeAll { $0 == snap.id }
                    }
                }))
            .toggleStyle(.checkbox)
            .font(.caption)
            Button("Delete") {
                state.deleteSnapshot(snap)
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
        .padding(DesignTokens.Space.m)
        .background(Color.secondary.opacity(0.06))
        .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
    }
}

// MARK: - §21 Comparison view (real stored top-dir deltas)

private struct SnapshotComparisonView: View {
    @EnvironmentObject var state: AppState
    @State private var filter: ChangeFilter = .all

    enum ChangeFilter: String, CaseIterable { case all, grew, shrank }

    private var selected: [Snapshot] {
        state.compareIDs.compactMap { id in state.snapshots.first { $0.id == id } }
            .sorted { $0.date < $1.date }
    }

    private var rows: [(name: String, old: Int64, new: Int64)] {
        guard selected.count == 2,
              let oldTop = ScanStore.topDirs(for: selected[0]),
              let newTop = ScanStore.topDirs(for: selected[1])
        else { return [] }
        let names = Set(oldTop.keys).union(newTop.keys)
        let all = names.map { name in
            (name, oldTop[name] ?? 0, newTop[name] ?? 0)
        }.sorted { ($1.1 - $0.1) > ($1.2 - $0.2) }
        switch filter {
        case .all: return all
        case .grew: return all.filter { $0.2 > $0.1 }
        case .shrank: return all.filter { $0.2 < $0.1 }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
            if selected.count == 2 {
                let a = selected[0], b = selected[1]
                let delta = b.totalBytes - a.totalBytes
                Text("Compare: \(a.label) → \(b.label)")
                    .font(.title3.weight(.semibold))
                Text("Total: \(a.totalBytes.fileSizeString) → \(b.totalBytes.fileSizeString) (\(delta >= 0 ? "+" : "")\(delta.fileSizeString))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(delta > 0 ? .red : delta < 0 ? .green : .secondary)
                if rows.isEmpty {
                    Text("Stored size breakdowns aren't available for these snapshots (saved before this version). New snapshots record per-folder sizes for comparison.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Picker("Filter", selection: $filter) {
                        ForEach(ChangeFilter.allCases, id: \.self) { f in
                            Text(f.rawValue.capitalized).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    List(rows, id: \.name) { row in
                        let delta = row.new - row.old
                        HStack {
                            Circle()
                                .fill(delta > 0 ? .red : delta < 0 ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(row.name)
                            Spacer()
                            Text(row.old.fileSizeString).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            Text("→").foregroundStyle(.tertiary)
                            Text(row.new.fileSizeString).font(.callout.monospacedDigit())
                            Text((delta >= 0 ? "+" : "") + delta.fileSizeString)
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(delta > 0 ? .red : delta < 0 ? .green : .secondary)
                                .frame(width: 90, alignment: .trailing)
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                Text("Select two snapshots to compare.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Export CSV") {
                    let rows = [["Folder", "Old Bytes", "New Bytes", "Delta"]] + rows.map { [$0.name, "\($0.old)", "\($0.new)", "\($0.new - $0.old)"] }
                    _ = ExportService.csvURL(rows: rows, suggestedName: "diskbuddy-comparison.csv")
                }
                .buttonStyle(.bordered)
                .disabled(rows.isEmpty)
                Button("Done") {
                    state.compareIDs.removeAll()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 640, height: 520)
    }
}

#Preview {
    SnapshotsView().environmentObject(AppState())
        .frame(width: 800, height: 600)
}
