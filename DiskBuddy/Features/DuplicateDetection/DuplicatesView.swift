import SwiftUI
import AppKit

// MARK: - Verified duplicates: choose a retained copy, then review the others in Trash queue.

struct DuplicatesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var finder: DuplicateFinder
    @EnvironmentObject private var ignoreRules: IgnoreRules
    @EnvironmentObject private var priorities: ScanPriorityStore
    @State private var search = ""
    @State private var hideStaged = false
    @State private var verificationCancelled = false
    @State private var marked: Set<UUID> = []
    @State private var selectedFile: DuplicateFile?
    @State private var showPreview = true
    @State private var layoutMode: LayoutMode = .list
    @State private var sortMode: SortMode = .reclaimable
    @State private var removalRequest: RemovalRequest?

    private enum LayoutMode: String, CaseIterable, Identifiable {
        case list, grid
        var id: String { rawValue }
        var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
        var title: String { self == .list ? "List" : "Grid" }
    }

    private enum SortMode: String, CaseIterable, Identifiable {
        case reclaimable, size, name, count
        var id: String { rawValue }
        var title: String {
            switch self {
            case .reclaimable: return "Potential Savings"
            case .size: return "File Size"
            case .name: return "Name"
            case .count: return "Selected Count"
            }
        }
    }

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
        let filtered = (resultsAreCurrent ? finder.sets : []).filter { set in
            let usable = set.files.filter { !ignoreRules.shouldIgnore(path: $0.path) }
            guard usable.count >= 2 else { return false }
            guard query.isEmpty || usable.contains(where: { $0.path.localizedStandardContains(query) }) else {
                return false
            }
            guard !hideStaged else {
                return usable.contains { file in
                    file.id != keeper(for: set)?.id && !isStaged(file.path)
                }
            }
            return true
        }
        return filtered.sorted { left, right in
            switch sortMode {
            case .reclaimable: return left.reclaimable > right.reclaimable
            case .size: return left.perCopy > right.perCopy
            case .name:
                let l = left.files.first?.path.localizedStandardCompare(right.files.first?.path ?? "") ?? .orderedSame
                return l == .orderedAscending
            case .count:
                let lc = left.files.filter { marked.contains($0.id) }.count
                let rc = right.files.filter { marked.contains($0.id) }.count
                return lc == rc ? left.reclaimable > right.reclaimable : lc > rc
            }
        }
    }

    private var markedFiles: [DuplicateFile] {
        visibleSets.flatMap { set in
            set.files.filter { marked.contains($0.id) && !ignoreRules.shouldIgnore(path: $0.path) }
        }
    }

    private var markedBytes: Int64 {
        markedFiles.reduce(Int64(0)) { $0 + $1.bytes }
    }

    /// Never includes the copy the user chose to keep. If every copy in a set
    /// is marked, the keeper is excluded so a removal can never erase a set.
    private var removableMarkedFiles: [DuplicateFile] {
        visibleSets.flatMap { set in
            let keep = keeper(for: set)
            let usable = set.files.filter { !ignoreRules.shouldIgnore(path: $0.path) }
            let chosen = usable.filter { marked.contains($0.id) }
            let candidates = chosen.count == usable.count ? usable : chosen
            return candidates.filter { $0.id != keep?.id }
        }
    }

    private func keeper(for set: DuplicateSet) -> DuplicateFile? {
        if let id = state.duplicateKeeps[set.id],
           let selected = set.files.first(where: { $0.id == id }) {
            return selected
        }
        return priorities.preferredKeep(in: set.files)
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
                HSplitView {
                    ScrollView {
                        if layoutMode == .grid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: DesignTokens.Space.m)],
                                      spacing: DesignTokens.Space.m) {
                                ForEach(visibleSets) { set in
                                    DuplicateSetCard(
                                        duplicateSet: set,
                                        kept: keeper(for: set),
                                        marked: $marked,
                                        selected: $selectedFile,
                                        onKeep: { file in state.duplicateKeeps[set.id] = file.id },
                                        onIgnore: ignore)
                                }
                            }
                            .padding(DesignTokens.Space.m)
                        } else {
                            LazyVStack(spacing: DesignTokens.Space.m) {
                                ForEach(visibleSets) { set in
                                    DuplicateSetCard(
                                        duplicateSet: set,
                                        kept: keeper(for: set),
                                        marked: $marked,
                                        selected: $selectedFile,
                                        onKeep: { file in state.duplicateKeeps[set.id] = file.id },
                                        onIgnore: ignore)
                                }
                            }
                            .padding(DesignTokens.Space.m)
                        }
                    }
                    .frame(minWidth: 420)
                    if showPreview {
                        QuickLookPane(path: selectedFile?.path)
                            .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                    }
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
        .sheet(item: $removalRequest) { request in
            RemovalSheet(request: request) { _ in
                marked.removeAll()
                runFinder()
            }
            .environmentObject(state)
        }
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
            Menu {
                Button("Photos Library Duplicates") { state.sidebarTab = .photos }
                Button("Similar Files") { state.sidebarTab = .similar }
                Divider()
                Button("Music") { quickScan("~/Music", label: "Music") }
                Button("Documents") { quickScan("~/Documents", label: "Documents") }
                Button("Downloads") { quickScan("~/Downloads", label: "Downloads") }
                Button("Desktop") { quickScan("~/Desktop", label: "Desktop") }
                Divider()
                Button("Choose Folder…") { chooseQuickScanFolder() }
            } label: {
                Label("Quick Scan", systemImage: "bolt.fill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Scan a common folder for duplicates")
        }
        .padding(DesignTokens.Space.m)
    }

    private var controls: some View {
        VStack(spacing: DesignTokens.Space.s) {
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
            HStack(spacing: DesignTokens.Space.m) {
                MarkDuplicatesMenu(
                    onAll: markAllDuplicates,
                    onNewest: { applyDateRule(keepNewest: true) },
                    onOldest: { applyDateRule(keepNewest: false) },
                    onInvert: invertMarks,
                    onClear: { marked.removeAll() })
                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(width: 190)
                Picker("Layout", selection: $layoutMode) {
                    ForEach(LayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Toggle("Preview", isOn: $showPreview)
                    .toggleStyle(.checkbox)
                Button("Apply Priority Keepers") {
                    let keepers = priorities.keepersByPriority(for: visibleSets)
                    for (setID, fileID) in keepers {
                        state.duplicateKeeps[setID] = fileID
                    }
                }
                .buttonStyle(.borderless)
                .disabled(priorities.isEmpty)
                .help("Use Folder Priority and File Type Priority to choose the kept copy")
                Spacer()
                Text(marked.isEmpty
                     ? "\(visibleSets.count) of \(finder.sets.count) sets shown"
                     : "\(marked.count) marked · \(markedBytes.fileSizeString)")
                    .font(.caption)
                    .foregroundStyle(marked.isEmpty ? .secondary : .primary)
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
            Button("Clear Marks") { marked.removeAll() }
                .buttonStyle(.borderless)
                .disabled(marked.isEmpty)
            Button("Review Queue (\(state.cleanupItems.count))") { state.showCleanup = true }
                .buttonStyle(.bordered)
            Button("Stage Marked") {
                guard !marked.isEmpty else { return }
                for file in removableMarkedFiles {
                    state.stage(source: "Duplicates", path: file.path, bytes: file.bytes)
                }
                state.showCleanup = true
            }
            .buttonStyle(.bordered)
            .disabled(removableMarkedFiles.isEmpty)
            .help("Stage the marked copies; nothing moves to Trash until you confirm in the queue")
            Button("Remove Marked…") {
                guard !removableMarkedFiles.isEmpty else { return }
                let items = removableMarkedFiles
                let bytes = items.reduce(Int64(0)) { $0 + $1.bytes }
                removalRequest = RemovalRequest(
                    title: "Remove \(items.count) duplicate files?",
                    detail: "\(ByteFormatting.format(bytes)) selected. The kept copy in every set is never removed.",
                    items: items.map { ($0.path, $0.bytes) },
                    context: .duplicateCleanup)
            }
            .buttonStyle(.borderedProminent)
            .disabled(marked.isEmpty)
            Button("Stage Visible & Review") {
                for set in visibleSets {
                    let keepID = keeper(for: set)?.id
                    if let kept = keeper(for: set), isStaged(kept.path) {
                        state.banner = AppState.Banner(message: "Remove the kept copy from the cleanup queue before staging its duplicates.", actionTitle: "OK")
                        continue
                    }
                    for file in set.files where file.id != keepID {
                        state.stage(source: "Duplicates", path: file.path, bytes: file.bytes)
                    }
                }
                state.showCleanup = true
            }
            .buttonStyle(.bordered)
            .help("Stage redundant copies from the visible sets; nothing moves to Trash until you confirm in the queue")
        }
        .padding(DesignTokens.Space.m)
    }

    private func isStaged(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        return state.cleanupItems.contains { $0.path == expanded }
    }

    // MARK: Mark rules

    private func markAllDuplicates() {
        for set in visibleSets {
            let keep = keeper(for: set)
            for file in set.files where file.id != keep?.id && !ignoreRules.shouldIgnore(path: file.path) {
                marked.insert(file.id)
            }
        }
    }

    private func applyDateRule(keepNewest: Bool) {
        for set in visibleSets {
            let dates = set.files.compactMap { file -> (UUID, Date)? in
                let attributes = try? FileManager.default.attributesOfItem(
                    atPath: (file.path as NSString).expandingTildeInPath)
                guard let date = attributes?[.modificationDate] as? Date else { return nil }
                return (file.id, date)
            }
            guard let boundary = keepNewest
                ? dates.map(\.1).max()
                : dates.map(\.1).min() else { continue }
            for (id, date) in dates {
                if keepNewest ? date < boundary : date > boundary {
                    marked.insert(id)
                }
            }
            ensureOneUnmarked(in: set)
        }
    }

    private func invertMarks() {
        for set in visibleSets {
            for file in set.files where !ignoreRules.shouldIgnore(path: file.path) {
                if marked.contains(file.id) { marked.remove(file.id) } else { marked.insert(file.id) }
            }
            ensureOneUnmarked(in: set)
        }
    }

    private func ensureOneUnmarked(in set: DuplicateSet) {
        guard set.files.allSatisfy({ marked.contains($0.id) }) else { return }
        if let keep = keeper(for: set) {
            marked.remove(keep.id)
        }
    }

    private func ignore(_ file: DuplicateFile) {
        let ext = (file.path as NSString).pathExtension
        if !ext.isEmpty, ignoreRules.addExtension(ext) {
            state.banner = AppState.Banner(
                message: "Ignoring .\(ext.lowercased()) files in duplicate results.",
                actionTitle: "OK")
        }
        marked.remove(file.id)
        if selectedFile?.id == file.id { selectedFile = nil }
    }

    private func quickScan(_ path: String, label: String) {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            state.banner = AppState.Banner(message: "\(path) does not exist.", actionTitle: "OK")
            return
        }
        state.startRealScan(root: URL(fileURLWithPath: expanded), label: label)
    }

    private func chooseQuickScanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            state.startRealScan(root: url, label: url.lastPathComponent)
        }
    }

    private func runFinder() {
        verificationCancelled = false
        finder.find(in: ignoreRules.filter(state.records), minBytes: state.dupMinBytes, scanID: state.scanRoot?.id)
    }
}

private struct MarkDuplicatesMenu: View {
    let onAll: () -> Void
    let onNewest: () -> Void
    let onOldest: () -> Void
    let onInvert: () -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            Button("All Duplicates (keep one per set)", action: onAll)
            Divider()
            Button("Mark Files With Earlier Date", action: onNewest)
            Button("Mark Files With Newest Date", action: onOldest)
            Divider()
            Button("Invert Marks", action: onInvert)
            Button("Clear Marks", action: onClear)
        } label: {
            Label("Mark", systemImage: "checklist")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct DuplicateSetCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var ignoreRules: IgnoreRules
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let duplicateSet: DuplicateSet
    let kept: DuplicateFile?
    @Binding var marked: Set<UUID>
    @Binding var selected: DuplicateFile?
    let onKeep: (DuplicateFile) -> Void
    let onIgnore: (DuplicateFile) -> Void
    @State private var expanded = true

    private var visibleFiles: [DuplicateFile] {
        duplicateSet.files.filter { !ignoreRules.shouldIgnore(path: $0.path) }
    }

    private var hasStagedCopies: Bool {
        visibleFiles.contains { file in
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
                        Text("SHA-256 verified · \(visibleFiles.count) identical copies")
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
            .accessibilityLabel("\(visibleFiles.count) identical copies, \(duplicateSet.reclaimable.fileSizeString) potential savings")
            .accessibilityHint(expanded ? "Collapse set" : "Expand set")
            .help(duplicateSet.hashPrefix)

            if expanded {
                ForEach(visibleFiles) { file in
                    HStack(spacing: DesignTokens.Space.s) {
                        Button {
                            if marked.contains(file.id) { marked.remove(file.id) } else { marked.insert(file.id) }
                        } label: {
                            Image(systemName: marked.contains(file.id) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(marked.contains(file.id) ? .red : .secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Mark for removal")
                        .disabled(kept?.id == file.id)

                        Button {
                            onKeep(file)
                        } label: {
                            Image(systemName: kept?.id == file.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(kept?.id == file.id ? .green : .secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Keep \(file.path)")
                        .accessibilityAddTraits(kept?.id == file.id ? [.isSelected] : [])
                        .disabled(hasStagedCopies && kept?.id != file.id)
                        .help(hasStagedCopies ? "Remove this set's files from the queue before changing which copy to keep" : "Keep this copy")

                        FileThumbnailView(path: file.path, size: 36)

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
                        Menu {
                            Button("Quick Look") { selected = file }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile((file.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                            }
                            Button("Ignore .\((file.path as NSString).pathExtension.lowercased()) Files") {
                                onIgnore(file)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                    }
                    .padding(.vertical, DesignTokens.Space.xs)
                    .padding(.horizontal, DesignTokens.Space.s)
                    .background(selected?.id == file.id ? Color.accentColor.opacity(0.08)
                                : kept?.id == file.id ? Color.green.opacity(0.08) : Color.clear,
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
                    .contentShape(Rectangle())
                    .onTapGesture { selected = file }
                }
                HStack {
                    Text(keptIsStaged ? "Your kept copy is in the queue. Remove it before staging other copies."
                         : hasStagedCopies ? "Copies staged. Remove them from the queue before changing the kept copy."
                         : "One copy stays. Marked copies can be staged or removed with the method you choose.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stage Other Copies") {
                        for file in visibleFiles where file.id != kept?.id {
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
        .environmentObject(IgnoreRules())
        .environmentObject(ScanPriorityStore())
        .frame(width: 900, height: 650)
}
