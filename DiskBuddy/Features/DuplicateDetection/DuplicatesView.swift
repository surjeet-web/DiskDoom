import SwiftUI

// MARK: - §15 Duplicates View (mock hash sets, keep-1 recommendation)

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState
    @State private var minSize: Int64 = 10_000_000
    @State private var onlyReclaimable = false

    private var sets: [DuplicateSet] {
        MockDuplicates.sets.filter { $0.perCopy >= minSize }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            HStack {
                Text("\(sets.count) duplicate sets · \(sets.reduce(0) { $0 + $1.total }.fileSizeString) total")
                    .font(.headline)
                Spacer()
                Text("Reclaimable: \(MockDuplicates.totalReclaimable.fileSizeString) (keep 1 copy)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Picker("Min size", selection: $minSize) {
                    Text("1 MB").tag(Int64(1_000_000))
                    Text("10 MB").tag(Int64(10_000_000))
                    Text("100 MB").tag(Int64(100_000_000))
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                Toggle("Only show reclaimable", isOn: $onlyReclaimable)
                Spacer()
            }
            .font(.caption)
            ScrollView {
                LazyVStack(spacing: DesignTokens.Space.m) {
                    ForEach(sets, id: \.id) { set in
                        DuplicateSetCard(set: set)
                    }
                }
            }
            HStack {
                Button("Select All Recommended") {
                    for set in sets where state.duplicateKeeps[set.id] == nil {
                        state.duplicateKeeps[set.id] = recommendedKeep(for: set)?.id
                    }
                }
                .buttonStyle(.bordered)
                Button("Stage All Selected") {
                    for set in sets {
                        let keepID = state.duplicateKeeps[set.id] ?? recommendedKeep(for: set)?.id
                        for file in set.files where file.id != keepID {
                            state.stage(source: "Duplicates", path: file.path, bytes: file.bytes)
                        }
                    }
                    state.showCleanup = true
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Text("\(MockDuplicates.totalReclaimable.fileSizeString) selected")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Space.m)
    }

    private func recommendedKeep(for set: DuplicateSet) -> DuplicateFile? {
        // Prefer most canonical location: Desktop > Documents > Downloads > elsewhere.
        let rank: [String] = ["~/Desktop", "~/Documents", "~/Downloads"]
        return set.files.sorted {
            let a = rank.firstIndex(where: $0.path.hasPrefix) ?? 99
            let b = rank.firstIndex(where: $1.path.hasPrefix) ?? 99
            return a < b
        }.first
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
                    Text("Recommendation: Keep \(set.files.first?.path ?? "") — most recently accessed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    DuplicatesView().environmentObject(AppState())
        .frame(width: 800, height: 600)
}
