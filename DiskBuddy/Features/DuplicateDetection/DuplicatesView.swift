import SwiftUI
import AppKit

// MARK: - Verified duplicates: choose a retained copy, then review the others in Trash queue.

struct DuplicatesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var finder: DuplicateFinder
    @State private var search = ""
    @State private var hideStaged = false
    @State private var verificationCancelled = false

    private struct FinderInput: Hashable {
        let scanID: UUID?
        let recordCount: Int
        let minimumBytes: Int64
    }

    private var resultsAreCurrent: Bool {
        finder.lastRunScanID == state.scanRoot?.id &&
        finder.lastRunRecordCount == state.records.count &&
        finder.lastRunMinBytes == state.dupMinBytes
    }

    private var visibleSets: [DuplicateSet] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (resultsAreCurrent ? finder.sets : []).filter { set in
            (query.isEmpty || set.files.contains { $0.path.localizedStandardContains(query) }) &&
            (!hideStaged || set.files.contains { file in
                file.id != set.keptFile(selectedID: state.duplicateKeeps[set.id])?.id && !isStaged(file.path)
            })
        }
    }

    private var potentialSavings: Int64 {
        (resultsAreCurrent ? finder.sets : []).reduce(0) { $0 + $1.reclaimable }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            if state.records.isEmpty {
                EmptyState(symbol: "doc.on.doc", title: "Scan to find duplicates",
                           message: "Find byte-identical files, choose a copy to keep, and review the rest before cleanup.",
                           actionTitle: "Start Scan (⌘R)", action: { state.startScan() })
            } else if finder.isRunning || (!resultsAreCurrent && !verificationCancelled && state.scanPhase == .done) {
                VStack(spacing: DesignTokens.Space.m) {
                    ProgressView(value: finder.progress) {
                        Text("Verifying file contents…")
                    }
                    .frame(maxWidth: 340)
                    Text("Matching sizes, sampling contents, then verifying with SHA-256.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if verificationCancelled && !resultsAreCurrent {
                EmptyState(symbol: "pause.circle", title: "Verification stopped",
                           message: "Start again to verify duplicates in this scan.",
                           actionTitle: "Scan Again", action: { runFinder() })
            } else if finder.sets.isEmpty {
                EmptyState(symbol: "checkmark.circle", title: "No duplicates found",
                           message: "No verified matching files above \(ByteFormatting.format(state.dupMinBytes)). Try a smaller minimum size.")
            } else if visibleSets.isEmpty {
                EmptyState(symbol: "line.3.horizontal.decrease.circle", title: "No matching sets",
                           message: "Try another filename or show sets already staged.",
                           actionTitle: "Clear filters", action: { search = ""; hideStaged = false })
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Space.m) {
                        ForEach(visibleSets) { set in
                            DuplicateSetCard(duplicateSet: set)
                        }
                    }
                    .padding(DesignTokens.Space.m)
                }
                Divider()
                footer
            }
        }
        .task(id: FinderInput(scanID: state.scanRoot?.id, recordCount: state.records.count,
                              minimumBytes: state.dupMinBytes)) {
            if state.scanPhase == .done, !state.records.isEmpty,
               (finder.lastRunMinBytes != state.dupMinBytes ||
                finder.lastRunScanID != state.scanRoot?.id ||
                finder.lastRunRecordCount != state.records.count) {
                state.saveSettings()
                runFinder()
            }
        }
        .onDisappear { finder.cancel() }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Space.l) {
            Image(systemName: "doc.on.doc.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicates").font(.title2.weight(.semibold))
                Text("Verified matches · choose one copy to keep per set")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(potentialSavings.fileSizeString) potential")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("\(finder.sets.count) sets · actual recovered space may vary")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Space.m)
    }

    private var controls: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Picker("Minimum file size", selection: $state.dupMinBytes) {
                Text("1 MB").tag(Int64(1_000_000))
                Text("10 MB").tag(Int64(10_000_000))
                Text("100 MB").tag(Int64(100_000_000))
                Text("1 GB").tag(Int64(1_000_000_000))
            }
            .frame(width: 175)
            TextField("Search filenames", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .accessibilityLabel("Filter duplicate sets by filename")
            if !search.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
            Toggle("Hide fully staged", isOn: $hideStaged)
                .toggleStyle(.checkbox)
            Spacer()
            if finder.isRunning {
                ProgressView(value: finder.progress)
                    .frame(width: 100)
                    .accessibilityLabel("Verifying duplicates")
                Button("Cancel") { finder.cancel(); verificationCancelled = true }
                    .buttonStyle(.bordered)
            } else {
                Button("Scan Again", systemImage: "arrow.clockwise") {
                    runFinder()
                }
                .disabled(state.records.isEmpty)
                .buttonStyle(.bordered)
            }
        }
        .font(.caption)
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
    }

    private var footer: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Text("\(visibleSets.count) of \(finder.sets.count) sets shown")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Review Queue (\(state.cleanupItems.count))") { state.showCleanup = true }
                .buttonStyle(.bordered)
            Button("Stage Visible & Review") {
                for set in visibleSets {
                    let keepID = set.keptFile(selectedID: state.duplicateKeeps[set.id])?.id
                    if let kept = set.keptFile(selectedID: state.duplicateKeeps[set.id]), isStaged(kept.path) {
                        state.banner = AppState.Banner(message: "Remove the kept copy from the cleanup queue before staging its duplicates.", actionTitle: "OK")
                        continue
                    }
                    for file in set.files where file.id != keepID {
                        state.stage(source: "Duplicates", path: file.path, bytes: file.bytes)
                    }
                }
                state.showCleanup = true
            }
            .buttonStyle(.borderedProminent)
            .help("Stage redundant copies from the visible sets; nothing moves to Trash until you confirm in the queue")
        }
        .padding(DesignTokens.Space.m)
    }

    private func isStaged(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        return state.cleanupItems.contains { $0.path == expanded }
    }

    private func runFinder() {
        verificationCancelled = false
        finder.find(in: state.records, minBytes: state.dupMinBytes, scanID: state.scanRoot?.id)
    }
}

private struct DuplicateSetCard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let duplicateSet: DuplicateSet
    @State private var expanded = true

    private var kept: DuplicateFile? { duplicateSet.keptFile(selectedID: state.duplicateKeeps[duplicateSet.id]) }
    private var hasStagedCopies: Bool {
        duplicateSet.files.contains { file in
            file.id != kept?.id && isStaged(file.path)
        }
    }
    private var keptIsStaged: Bool { kept.map { isStaged($0.path) } ?? false }

    private func isStaged(_ path: String) -> Bool {
        state.cleanupItems.contains { $0.path == (path as NSString).expandingTildeInPath }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            Button {
                withAnimation(reduceMotion ? nil : DesignTokens.Motion.navigation) { expanded.toggle() }
            } label: {
                HStack(spacing: DesignTokens.Space.m) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kept.map { ($0.path as NSString).lastPathComponent } ?? "Duplicate set")
                            .font(.headline).lineLimit(1)
                        Text("SHA-256 verified · \(duplicateSet.files.count) identical copies")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(duplicateSet.reclaimable.fileSizeString) potential")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(duplicateSet.files.count) identical copies, \(duplicateSet.reclaimable.fileSizeString) potential savings")
            .accessibilityHint(expanded ? "Collapse set" : "Expand set")
            .help(duplicateSet.hashPrefix)

            if expanded {
                ForEach(duplicateSet.files) { file in
                    HStack(spacing: DesignTokens.Space.s) {
                        Button {
                            state.duplicateKeeps[duplicateSet.id] = file.id
                        } label: {
                            Image(systemName: kept?.id == file.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(kept?.id == file.id ? .green : .secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Keep \(file.path)")
                        .accessibilityAddTraits(kept?.id == file.id ? [.isSelected] : [])
                        .disabled(hasStagedCopies && kept?.id != file.id)
                        .help(hasStagedCopies ? "Remove this set's files from the queue before changing which copy to keep" : "Keep this copy")
                        VStack(alignment: .leading, spacing: 2) {
                            Text((file.path as NSString).lastPathComponent)
                                .font(.callout.weight(.medium)).lineLimit(1)
                            Text(file.path)
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                                .help(file.path)
                        }
                        Spacer(minLength: DesignTokens.Space.s)
                        if kept?.id == file.id {
                            Text(state.duplicateKeeps[duplicateSet.id] == nil ? "SUGGESTED KEEP" : "KEEP")
                                .font(.caption2.weight(.bold)).foregroundStyle(.green)
                        }
                        Button("Reveal", systemImage: "folder") {
                            NSWorkspace.shared.selectFile((file.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                        }
                        .labelStyle(.iconOnly)
                        .help("Reveal in Finder")
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, DesignTokens.Space.xs)
                    .padding(.horizontal, DesignTokens.Space.s)
                    .background(kept?.id == file.id ? Color.green.opacity(0.08) : Color.clear,
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
                }
                HStack {
                    Text(keptIsStaged ? "Your kept copy is in the queue. Remove it before staging other copies."
                         : hasStagedCopies ? "Copies staged. Remove them from the queue before changing the kept copy."
                         : "One copy stays. Other copies go to your review queue, not directly to Trash.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stage Other Copies") {
                        for file in duplicateSet.files where file.id != kept?.id {
                            state.stage(source: "Duplicates", path: file.path, bytes: file.bytes)
                        }
                        state.showCleanup = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(keptIsStaged)
                }
            }
        }
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(AppState())
        .environmentObject(DuplicateFinder())
        .frame(width: 900, height: 650)
}
