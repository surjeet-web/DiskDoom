import SwiftUI

// MARK: - §15 Duplicates View (real content-hash pipeline over scan records)

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var finder: DuplicateFinder
    @State private var onlyReclaimable = false

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            HStack {
                Text("\(finder.sets.count) duplicate sets · \(finder.sets.reduce(0) { $0 + $1.total }.fileSizeString) total")
                    .font(.headline)
                Spacer()
                Text("Reclaimable: \(finder.sets.reduce(0) { $0 + $1.reclaimable }.fileSizeString) (keep 1 copy)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Picker("Min size", selection: $state.dupMinBytes) {
                    Text("1 MB").tag(Int64(1_000_000))
                    Text("10 MB").tag(Int64(10_000_000))
                    Text("100 MB").tag(Int64(100_000_000))
                    Text("1 GB").tag(Int64(1_000_000_000))
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                Toggle("Only show reclaimable", isOn: $onlyReclaimable)
                Spacer()
                if finder.isRunning {
                    ProgressView(value: finder.progress).frame(width: 120)
                } else {
                    Button("Re-run") { runFinder() }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            .font(.caption)
            if state.records.isEmpty {
                EmptyState(symbol: "doc.on.doc", title: "Scan first", message: "Duplicate detection hashes your real scan data (size → 8KB sample → full SHA-256).", actionTitle: "Start Scan (⌘R)", action: { state.startScan() })
            } else if finder.sets.isEmpty && !finder.isRunning {
                EmptyState(symbol: "checkmark.circle", title: "No Duplicates Found", message: "No byte-identical files above \(ByteFormatting.format(state.dupMinBytes)). Try lowering the minimum size.")
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Space.m) {
                        ForEach(finder.sets, id: \.id) { set in
                            DuplicateSetCard(set: set)
                        }
                    }
                }
                HStack {
                    Button("Select All Recommended") {
                        for set in finder.sets where state.duplicateKeeps[set.id] == nil {
                            state.duplicateKeeps[set.id] = recommendedKeep(for: set)?.id
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("Stage All Selected") {
                        for set in finder.sets {
                            let keepID = state.duplicateKeeps[set.id] ?? recommendedKeep(for: set)?.id
                            for file in set.files where file.id != keepID {
                                state.stage(source: "Duplicates", path: file.path, bytes: file.bytes)
                            }
                        }
                        state.showCleanup = true
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Text("\(finder.sets.reduce(0) { $0 + $1.reclaimable }.fileSizeString) selected")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignTokens.Space.m)
        .task(id: [state.dupMinBytes, Int64(state.records.count)]) {
            // Auto-run only when the scan data or threshold actually changed —
            // not on every tab visit (hashing is expensive).
            if !state.records.isEmpty, finder.lastRunMinBytes != state.dupMinBytes || finder.sets.isEmpty {
                state.saveSettings()
                runFinder()
            }
        }
        .onDisappear { finder.cancel() }
    }

    private func runFinder() {
        finder.find(in: state.records, minBytes: state.dupMinBytes)
    }

    private func recommendedKeep(for set: DuplicateSet) -> DuplicateFile? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func rank(_ path: String) -> Int {
            if path.hasPrefix(home + "/Desktop") { return 0 }
            if path.hasPrefix(home + "/Documents") { return 1 }
            if path.hasPrefix(home + "/Downloads") { return 2 }
            return 3
        }
        return set.files.sorted { rank($0.path) < rank($1.path) }.first
    }
}

// MARK: - Duplicate set card

private struct DuplicateSetCard: View {
    @EnvironmentObject var state: AppState
    let set: DuplicateSet
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            Button {
                expanded.toggle()
            } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                    Text(set.hashPrefix)
                        .font(.callout.monospaced())
                    Spacer()
                    Text("\(set.files.count) copies · \(set.perCopy.fileSizeString) each · \(set.total.fileSizeString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Reclaimable: \(set.reclaimable.fileSizeString)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(set.files, id: \.id) { file in
                    let keptID = state.duplicateKeeps[set.id] ?? set.files.first?.id
                    let isKept = keptID == file.id
                    HStack {
                        Image(systemName: isKept ? "circle.inset.filled" : "circle")
                            .foregroundStyle(isKept ? Color.green : .secondary)
                        Text(file.path)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(file.bytes.fileSizeString)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if isKept {
                            Text("KEEP").font(.caption2.weight(.bold)).foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.duplicateKeeps[set.id] = file.id
                    }
                    .help(isKept ? "Kept copy" : "Click to keep this copy instead")
                }
                HStack {
                    Spacer()
                    Button("Stage \(set.files.count - 1) copies for cleanup") {
                        let keepID = state.duplicateKeeps[set.id] ?? set.files.first?.id
                        for file in set.files where file.id != keepID {
                            state.stage(source: "Duplicates", path: file.path, bytes: file.bytes)
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
        .padding(DesignTokens.Space.m)
        .background(Color.secondary.opacity(0.06))
        .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(AppState())
        .environmentObject(DuplicateFinder())
        .frame(width: 800, height: 600)
}
