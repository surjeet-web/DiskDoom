import SwiftUI
import AppKit

// MARK: - Similar Files (perceptual photo grouping + mark rules)
//
// Ported behaviour from the reference app: similar-file results, automatic
// marking rules (smaller size / dimensions / DPI / dates / missing metadata),
// Quick Look preview with EXIF, ignore rules, and the same removal methods.

struct SimilarFilesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var finder: SimilarPhotoFinder
    @EnvironmentObject private var ignoreRules: IgnoreRules
    @EnvironmentObject private var priorities: ScanPriorityStore

    @State private var marked: Set<UUID> = []
    @State private var selected: SimilarPhoto?
    @State private var search = ""
    @State private var showPreview = true
    @State private var removalRequest: RemovalRequest?

    private var visibleGroups: [SimilarGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return finder.groups.compactMap { group in
            let photos = group.photos.filter { photo in
                !ignoreRules.shouldIgnore(path: photo.path) &&
                (query.isEmpty || photo.name.localizedStandardContains(query)
                    || photo.path.localizedStandardContains(query))
            }
            guard photos.count >= 2 else { return nil }
            return SimilarGroup(photos: photos, maxDistance: group.maxDistance)
        }
    }

    private var markedPhotos: [SimilarPhoto] {
        visibleGroups.flatMap { group in
            group.photos.filter { marked.contains($0.id) }
        }
    }

    private var markedBytes: Int64 {
        markedPhotos.reduce(Int64(0)) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            HSplitView {
                results
                    .frame(minWidth: 420)
                if showPreview {
                    QuickLookPane(path: selected?.path)
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                }
            }
            Divider()
            footer
        }
        .task(id: state.records.count) {
            guard !state.records.isEmpty, !finder.isRunning,
                  finder.lastRunRecords != state.records.count else { return }
            finder.scan(records: state.records, ignoreRules: ignoreRules)
        }
        .onDisappear { finder.cancel() }
        .sheet(item: $removalRequest) { request in
            RemovalSheet(request: request) { _ in
                marked.removeAll()
                if !state.records.isEmpty {
                    finder.scan(records: state.records, ignoreRules: ignoreRules)
                }
            }
            .environmentObject(state)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DesignTokens.Space.l) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.pink)
                .frame(width: 44, height: 44)
                .background(.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            VStack(alignment: .leading, spacing: 2) {
                Text("Similar Files").font(.title2.weight(.semibold))
                Text("Perceptual matches · keep the best shot, review the rest")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(finder.groups.count) groups")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("\(finder.groups.reduce(0) { $0 + $1.reclaimable }.fileSizeString) potential")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                scanFolder()
            } label: {
                Label("Scan Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            Button {
                finder.scan(records: state.records, ignoreRules: ignoreRules)
            } label: {
                Label("Scan Current Results", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.records.isEmpty || finder.isRunning)
        }
        .padding(DesignTokens.Space.m)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack(spacing: DesignTokens.Space.m) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Similarity threshold: \(finder.threshold)")
                        .font(.caption.weight(.medium))
                    Slider(value: Binding(
                        get: { Double(finder.threshold) },
                        set: { finder.threshold = Int($0.rounded()) }
                    ), in: 0...20, step: 1)
                    .frame(width: 180)
                    .help("0 = nearly identical, 20 = loose")
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Minimum dimension: \(finder.minimumDimension)px")
                        .font(.caption)
                    Stepper("", value: Binding(
                        get: { finder.minimumDimension },
                        set: { finder.minimumDimension = max(16, $0) }
                    ), in: 16...2048, step: 64)
                    .labelsHidden()
                }
                TextField("Search similar files", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                MarkMenu(
                    onMarkAllButBest: { applyRule { group, photo in photo.id != bestPhoto(in: group)?.id } },
                    onLowerQuality: { applyRule { group, photo in
                        let bestArea = group.photos.map { $0.width * $0.height }.max() ?? 0
                        return photo.width * photo.height < bestArea
                    } },
                    onSmallerDimensions: { applyRule { group, photo in
                        let bestArea = group.photos.map { $0.width * $0.height }.max() ?? 0
                        return photo.width * photo.height < bestArea
                    } },
                    onSmallerFile: { applyRule { group, photo in
                        let maxBytes = group.photos.map(\.bytes).max() ?? 0
                        return photo.bytes < maxBytes
                    } },
                    onSmallerDPI: { applyRule { group, photo in
                        let maxDPI = group.photos.map(\.dpi).max() ?? 0
                        return photo.dpi > 0 && photo.dpi < maxDPI
                    } },
                    onEarlierDate: { applyRule { group, photo in
                        let newest = group.photos.compactMap { $0.dateTaken ?? $0.modified }.max() ?? .distantPast
                        return (photo.dateTaken ?? photo.modified) < newest
                    } },
                    onNewestDate: { applyRule { group, photo in
                        let oldest = group.photos.compactMap { $0.dateTaken ?? $0.modified }.min() ?? .distantFuture
                        return (photo.dateTaken ?? photo.modified) > oldest
                    } },
                    onWithoutMetadata: { applyRule { _, photo in
                        !FileMetadataReader.hasMeaningfulMetadata(photo.metadata)
                    } },
                    onInvert: invertMarks,
                    onClear: { marked.removeAll() }
                )
                Toggle("Preview", isOn: $showPreview)
                    .toggleStyle(.checkbox)
                Spacer()
                if finder.isRunning {
                    ProgressView(value: finder.progress)
                        .frame(width: 120)
                    Button("Cancel") { finder.cancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if !finder.phase.isEmpty {
                HStack {
                    Text(finder.phase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if finder.candidateCount > 0 {
                        Text("\(finder.candidateCount.formatted()) candidate images")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if state.records.isEmpty && finder.groups.isEmpty {
            EmptyState(
                symbol: "photo.stack",
                title: "Find similar photos",
                message: "Scan your Mac first, or pick a folder. DiskBuddy compares thumbnails — it does not modify anything until you confirm removal.",
                actionTitle: "Choose Folder…",
                action: { scanFolder() })
        } else if finder.isRunning && finder.groups.isEmpty {
            VStack(spacing: DesignTokens.Space.m) {
                ProgressView(value: finder.progress)
                    .frame(maxWidth: 320)
                Text(finder.phase).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleGroups.isEmpty {
            EmptyState(
                symbol: "checkmark.circle",
                title: "No similar photos",
                message: search.isEmpty
                    ? "No perceptual matches above the current threshold. Try a looser threshold or a smaller minimum dimension."
                    : "No groups match “\(search)”.",
                actionTitle: search.isEmpty ? nil : "Clear search",
                action: search.isEmpty ? nil : { search = "" })
        } else {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Space.m) {
                    ForEach(visibleGroups) { group in
                        SimilarGroupCard(
                            group: group,
                            marked: $marked,
                            selected: $selected,
                            best: bestPhoto(in: group),
                            onIgnore: ignore)
                    }
                }
                .padding(DesignTokens.Space.m)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Text(marked.isEmpty
                 ? "\(visibleGroups.count) groups · select files to mark"
                 : "\(marked.count) marked · \(ByteFormatting.format(markedBytes))")
                .font(.caption)
                .foregroundStyle(marked.isEmpty ? .secondary : .primary)
            Spacer()
            Button("Clear") { marked.removeAll() }
                .buttonStyle(.borderless)
                .disabled(marked.isEmpty)
            Button("Stage Marked") {
                for photo in markedPhotos {
                    state.stage(source: "Similar Files", path: photo.path, bytes: photo.bytes)
                }
                state.showCleanup = true
            }
            .buttonStyle(.bordered)
            .disabled(marked.isEmpty)
            Button("Remove Marked…") {
                removalRequest = buildRemovalRequest()
            }
            .buttonStyle(.borderedProminent)
            .disabled(marked.isEmpty)
        }
        .padding(DesignTokens.Space.m)
    }

    // MARK: Mark rules

    private func visibleGroup(containing photo: SimilarPhoto) -> SimilarGroup? {
        visibleGroups.first { $0.photos.contains(where: { $0.id == photo.id }) }
    }

    private func bestPhoto(in group: SimilarGroup) -> SimilarPhoto? {
        if priorities.isEmpty {
            return group.photos.max {
                let lhs = ($0.width * $0.height, $0.bytes)
                let rhs = ($1.width * $1.height, $1.bytes)
                return lhs < rhs
            }
        }
        let files = group.photos.map { DuplicateFile(path: $0.path, bytes: $0.bytes) }
        guard let preferred = priorities.preferredKeep(in: files) else { return group.largest }
        return group.photos.first { $0.path == preferred.path } ?? group.largest
    }

    private func applyRule(_ select: (SimilarGroup, SimilarPhoto) -> Bool) {
        for group in visibleGroups {
            for photo in group.photos where select(group, photo) {
                marked.insert(photo.id)
            }
            ensureOneUnmarked(in: group)
        }
    }

    private func ensureOneUnmarked(in group: SimilarGroup) {
        guard group.photos.allSatisfy({ marked.contains($0.id) }) else { return }
        if let keep = bestPhoto(in: group) {
            marked.remove(keep.id)
        }
    }

    private func invertMarks() {
        for group in visibleGroups {
            for photo in group.photos {
                if marked.contains(photo.id) {
                    marked.remove(photo.id)
                } else {
                    marked.insert(photo.id)
                }
            }
            ensureOneUnmarked(in: group)
        }
    }

    private func ignore(_ photo: SimilarPhoto) {
        let ext = (photo.path as NSString).pathExtension
        if !ext.isEmpty, ignoreRules.addExtension(ext) {
            state.banner = AppState.Banner(
                message: "Ignoring .\(ext.lowercased()) files in similar scans.",
                actionTitle: "Undo")
        }
        marked.remove(photo.id)
        if selected?.id == photo.id { selected = nil }
    }

    private func buildRemovalRequest() -> RemovalRequest? {
        var items: [(path: String, bytes: Int64)] = []
        for group in visibleGroups {
            let chosen = group.photos.filter { marked.contains($0.id) }
            guard !chosen.isEmpty else { continue }
            let removable: [SimilarPhoto]
            if chosen.count == group.photos.count {
                let keep = bestPhoto(in: group)
                removable = group.photos.filter { $0.id != keep?.id }
            } else {
                removable = chosen
            }
            items += removable.map { ($0.path, $0.bytes) }
        }
        guard !items.isEmpty else { return nil }
        let bytes = items.reduce(Int64(0)) { $0 + $1.1 }
        return RemovalRequest(
            title: "Remove \(items.count) similar photos?",
            detail: "\(ByteFormatting.format(bytes)) · one photo per group is kept. Review the method before continuing.",
            items: items,
            context: .similarCleanup)
    }

    private func scanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan for Similar"
        if panel.runModal() == .OK, let url = panel.url {
            marked.removeAll()
            selected = nil
            finder.scan(folder: url, ignoreRules: ignoreRules)
        }
    }
}

// MARK: - Mark menu

private struct MarkMenu: View {
    let onMarkAllButBest: () -> Void
    let onLowerQuality: () -> Void
    let onSmallerDimensions: () -> Void
    let onSmallerFile: () -> Void
    let onSmallerDPI: () -> Void
    let onEarlierDate: () -> Void
    let onNewestDate: () -> Void
    let onWithoutMetadata: () -> Void
    let onInvert: () -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            Button("All Similars (keep best)", action: onMarkAllButBest)
            Button("Lower Quality", action: onLowerQuality)
            Divider()
            Button("Mark Images With Smaller Dimensions", action: onSmallerDimensions)
            Button("Mark Files With Smaller Size", action: onSmallerFile)
            Button("Mark Images With Smaller DPI", action: onSmallerDPI)
            Button("Mark Files With Earlier Date", action: onEarlierDate)
            Button("Mark Files With Newest Date", action: onNewestDate)
            Button("Mark Images Without Metadata", action: onWithoutMetadata)
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

// MARK: - Group card

private struct SimilarGroupCard: View {
    let group: SimilarGroup
    @Binding var marked: Set<UUID>
    @Binding var selected: SimilarPhoto?
    let best: SimilarPhoto?
    let onIgnore: (SimilarPhoto) -> Void

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            Button {
                withAnimation(.easeOut(duration: DesignTokens.Motion.fast)) { expanded.toggle() }
            } label: {
                HStack(spacing: DesignTokens.Space.s) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("\(group.photos.count) similar photos")
                        .font(.headline)
                    Text("distance ≤ \(group.maxDistance)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.pink.opacity(0.12), in: .capsule)
                        .foregroundStyle(.pink)
                    Spacer()
                    Text("\(group.reclaimable.fileSizeString) potential")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(group.photos) { photo in
                    HStack(spacing: DesignTokens.Space.s) {
                        Button {
                            if marked.contains(photo.id) { marked.remove(photo.id) } else { marked.insert(photo.id) }
                        } label: {
                            Image(systemName: marked.contains(photo.id) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(marked.contains(photo.id) ? .red : .secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Mark for removal")

                        FileThumbnailView(path: photo.path, size: 52)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(photo.name).font(.callout.weight(.medium)).lineLimit(1)
                            Text(photo.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(photo.path)
                        }
                        Spacer(minLength: DesignTokens.Space.s)
                        if best?.id == photo.id {
                            Text("BEST")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(photo.dimensionsLabel).font(.caption.monospacedDigit())
                            Text("\(photo.bytes.fileSizeString)\(photo.dpi > 0 ? " · \(Int(photo.dpi)) DPI" : "")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Menu {
                            Button("Quick Look") { selected = photo }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(
                                    (photo.path as NSString).expandingTildeInPath,
                                    inFileViewerRootedAtPath: "")
                            }
                            Button("Ignore .\((photo.path as NSString).pathExtension.lowercased()) Files") {
                                onIgnore(photo)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .background(selected?.id == photo.id ? Color.accentColor.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
                    .contentShape(Rectangle())
                    .onTapGesture { selected = photo }
                }
            }
        }
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
    }
}

#Preview {
    SimilarFilesView()
        .environmentObject(AppState())
        .environmentObject(SimilarPhotoFinder())
        .environmentObject(IgnoreRules())
        .environmentObject(ScanPriorityStore())
        .frame(width: 1000, height: 720)
}
