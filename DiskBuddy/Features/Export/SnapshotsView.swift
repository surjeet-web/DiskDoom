import SwiftUI

// MARK: - §20 Snapshots List + §21 Comparison (mock data)

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
                Button("Save Current Scan") {
                    state.snapshots.insert(
                        Snapshot(date: Date(), label: "Just now", totalBytes: 256_000_000_000, files: 1_892_341, target: state.scanTargetName),
                        at: 0)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.scanPhase != .done)
                if state.compareIDs.count == 2 {
                    Button("Compare Selected") { comparing = true }
                        .buttonStyle(.bordered)
                }
            }
            ScrollView {
                LazyVStack(spacing: DesignTokens.Space.m) {
                    ForEach(state.snapshots) { snap in
                        SnapshotCard(snap: snap, dateText: dateText)
                    }
                }
            }
            Text("Storage: \(state.snapshots.count) snapshots · Auto-save: After each scan")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
        .sheet(isPresented: $comparing) {
            SnapshotComparisonView()
                .environmentObject(state)
        }
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
                state.snapshots.removeAll { $0.id == snap.id }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
        .padding(DesignTokens.Space.m)
        .background(Color.secondary.opacity(0.06))
        .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
    }
}

// MARK: - §21 Comparison view

private struct SnapshotComparisonView: View {
    @EnvironmentObject var state: AppState
    @State private var filter: ChangeFilter = .all

    enum ChangeFilter: String, CaseIterable { case all, grew, shrank }

    private var rows: [MockSnapshots.DeltaRow] {
        switch filter {
        case .all: return MockSnapshots.comparison
        case .grew: return MockSnapshots.comparison.filter { $0.delta > 0 }
        case .shrank: return MockSnapshots.comparison.filter { $0.delta < 0 }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
            Text("Compare: Yesterday → Today")
                .font(.title3.weight(.semibold))
            HStack(spacing: DesignTokens.Space.xl) {
                Text("Total: 254 GB → 256 GB (+2.1 GB)")
                Text("Files: 1,889,102 → 1,892,341 (+3,239)")
            }
            .font(.callout.monospacedDigit())
            Picker("Filter", selection: $filter) {
                ForEach(ChangeFilter.allCases, id: \.self) { f in
                    Text(f.rawValue.capitalized).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            List(rows) { row in
                HStack {
                    Circle()
                        .fill(row.delta > 0 ? .red : row.delta < 0 ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(row.name)
                    Spacer()
                    Text(row.oldBytes.fileSizeString)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("→")
                        .foregroundStyle(.tertiary)
                    Text(row.newBytes.fileSizeString)
                        .font(.callout.monospacedDigit())
                    Text((row.delta >= 0 ? "+" : "") + row.delta.fileSizeString)
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(row.delta > 0 ? .red : row.delta < 0 ? .green : .secondary)
                        .frame(width: 90, alignment: .trailing)
                }
            }
            .listStyle(.plain)
            HStack {
                Spacer()
                Button("Export Comparison") { }
                    .buttonStyle(.bordered)
                Button("Done") { state.compareIDs.removeAll() }
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
