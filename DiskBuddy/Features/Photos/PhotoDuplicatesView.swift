import SwiftUI
import Photos
import AppKit

// MARK: - Photos Library duplicates (exact + similar, Trash album)

struct PhotoDuplicatesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var engine: PhotoDuplicatesEngine

    @State private var mode: PhotoScanMode = .similar
    @State private var marked: Set<String> = []
    @State private var confirmDelete = false
    @State private var isRemoving = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if engine.access == .denied {
                accessDenied
            } else {
                controls
                Divider()
                results
            }
        }
        .confirmationDialog(
            "Delete \(markedCount) photos from the Photos library?",
            isPresented: $confirmDelete,
            titleVisibility: .visible) {
                Button("Move to Trash Album") { remove(moveOnly: true) }
                Button("Delete from Photos", role: .destructive) { remove(moveOnly: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Photos are first added to “\(engine.albumTitle)”. Deleting also moves them to Recently Deleted, where macOS keeps them temporarily.")
            }
    }

    private var markedCount: Int { marked.count }

    private var markedAssets: [PHAsset] {
        engine.groups.flatMap { group in
            zip(group.items, group.assets).compactMap { item, asset in
                marked.contains(item.id) ? asset : nil
            }
        }
    }

    private var markedBytes: Int64 {
        engine.groups.flatMap(\.items).filter { marked.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Image(systemName: "photo.stack.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background { MetalSurface(depth: 2, accent: DesignTokens.Palette.teal) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Photos Library Duplicates").font(.title2.weight(.semibold))
                Text("Exact and similar photos, cleaned through PhotoKit")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: engine.access.label,
                        kind: engine.access == .authorized ? .granted
                            : engine.access == .limited ? .required : .denied)
            if engine.access == .unknown || engine.access == .denied {
                Button("Grant Access") {
                    Task { await engine.requestAccess() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background { MetalSurface(family: .canopy, flatSide: .top, accent: DesignTokens.Palette.teal) }
    }

    private var accessDenied: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Photos access is required")
                .font(.title3.weight(.semibold))
            Text("Grant DiskBuddy access to your Photos library in System Settings → Privacy & Security → Photos. Nothing is read or changed without it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack {
                Button("Grant Access") { Task { await engine.requestAccess() } }
                    .buttonStyle(.borderedProminent)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            ScrollView(.horizontal) {
                controlContent
            }
            if !engine.phase.isEmpty {
                Text(engine.phase)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .background { MetalSurface(family: .well, flatSide: .top, depth: 2, accent: DesignTokens.Palette.teal) }
    }

    private var controlContent: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Picker("Mode", selection: $mode) {
                ForEach(PhotoScanMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            Text(mode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if mode == .similar {
                Text("Threshold \(engine.threshold)")
                    .font(.caption)
                Slider(value: Binding(
                    get: { Double(engine.threshold) },
                    set: { engine.threshold = Int($0.rounded()) }
                ), in: 0...20, step: 1)
                .frame(width: 120)
            }
            Spacer()
            if engine.isScanning {
                ProgressView(value: engine.progress)
                    .frame(width: 120)
                Text("\(engine.scannedAssets)/\(engine.totalAssets)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel") { engine.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button {
                    marked.removeAll()
                    engine.scan(mode: mode)
                } label: {
                    Label("Scan Photos", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if engine.groups.isEmpty && !engine.isScanning {
            EmptyState(
                symbol: "photo.stack",
                title: "Find duplicates in Photos",
                message: engine.phase.isEmpty
                    ? "Scan the Photos library for byte-identical originals or similar shots. Nothing is moved until you confirm."
                    : engine.phase,
                actionTitle: "Scan Photos",
                action: { engine.scan(mode: mode) })
        } else {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Space.m) {
                    ForEach(engine.groups) { group in
                        groupCard(group)
                    }
                }
                .padding(DesignTokens.Space.m)
            }
            Divider()
            footer
        }
    }

    private func groupCard(_ group: PhotoDuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Image(systemName: group.kind == .exact ? "equal.square.fill" : "square.on.square.dashed")
                    .foregroundStyle(group.kind == .exact ? .green : .pink)
                Text(group.kind == .exact ? "Exact duplicates" : "Similar photos")
                    .font(.headline)
                Text("\(group.items.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: .capsule)
                Spacer()
                Text("\(group.reclaimable.fileSizeString) potential")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.green)
                Button("Select All But One") {
                    selectAllButOne(in: group)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            ForEach(group.items.indices, id: \.self) { index in
                let item = group.items[index]
                let asset = group.assets[index]
                HStack(spacing: DesignTokens.Space.s) {
                    Button {
                        if marked.contains(item.id) { marked.remove(item.id) } else { marked.insert(item.id) }
                    } label: {
                        Image(systemName: marked.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(marked.contains(item.id) ? .red : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    PhotoAssetThumbnail(asset: asset)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.filename).font(.callout.weight(.medium)).lineLimit(1)
                        Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(item.dimensionsLabel).font(.caption.monospacedDigit())
                        Text(item.bytes > 0 ? item.bytes.fileSizeString : "Size unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .industrialPanel(.tiered, flatSide: .right, accent: group.kind == .exact ? DesignTokens.Palette.teal : DesignTokens.Palette.violet)
    }

    private var footer: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Text(marked.isEmpty
                 ? "\(engine.groups.count) groups · select photos to clean"
                 : "\(marked.count) marked · \(markedBytes.fileSizeString)")
                .font(.caption)
            Spacer()
            Button("Clear") { marked.removeAll() }
                .buttonStyle(.borderless)
                .disabled(marked.isEmpty)
            Button {
                confirmDelete = true
            } label: {
                Label("Review & Remove…", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(marked.isEmpty || isRemoving)
        }
        .padding(24)
        .background { MetalSurface(family: .boot, flatSide: .bottom, accent: DesignTokens.Palette.orange) }
    }

    private func selectAllButOne(in group: PhotoDuplicateGroup) {
        for (index, item) in group.items.enumerated() where index != 0 {
            marked.insert(item.id)
        }
        if group.items.count <= 1 { return }
        // Keep the first (newest, because assets are fetched newest-first).
        marked.remove(group.items[0].id)
    }

    private func remove(moveOnly: Bool) {
        let assets = markedAssets
        guard !assets.isEmpty else { return }
        isRemoving = true
        Task {
            let result: PhotoRemovalResult
            if moveOnly {
                result = await engine.moveToTrashAlbum(assets: assets)
            } else {
                result = await engine.deleteFromLibrary(assets: assets)
            }
            await MainActor.run {
                isRemoving = false
                if result.failures.isEmpty {
                    state.banner = AppState.Banner(
                        message: moveOnly
                            ? "Moved \(result.movedToAlbum) photos to “\(engine.albumTitle)”."
                            : "Deleted \(result.deletedFromLibrary) photos from the library. They remain in Photos → Recently Deleted.",
                        actionTitle: "OK")
                    // Moving to the Trash album does not remove bytes from the
                    // library, so only the delete path earns cleanup XP.
                    if !moveOnly, result.deletedFromLibrary > 0 {
                        state.gamification.record(GameEvent(
                            kind: .photoCleanup,
                            bytes: result.bytes,
                            items: result.deletedFromLibrary))
                    }
                    marked.removeAll()
                    engine.scan(mode: mode)
                } else {
                    state.banner = AppState.Banner(
                        message: "Photos cleanup partially failed: \(result.failures.joined(separator: " · "))",
                        actionTitle: "OK")
                }
                state.dismissBannerAfterDelay()
            }
        }
    }
}

// MARK: - PhotoKit thumbnail

private struct PhotoAssetThumbnail: View {
    let asset: PHAsset
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.12))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(.rect(cornerRadius: 6))
        .task(id: asset.localIdentifier) {
            image = await PhotoThumbnailLoader.load(asset)
        }
    }
}

private enum PhotoThumbnailLoader {
    static func load(_ asset: PHAsset) async -> NSImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        let gate = ThumbnailGate()
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 104, height: 104),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
                guard gate.claim() else { return }
                continuation.resume(returning: image)
            }
        }
    }
}

private final class ThumbnailGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

#Preview {
    PhotoDuplicatesView()
        .environmentObject(AppState())
        .environmentObject(PhotoDuplicatesEngine())
        .frame(width: 900, height: 700)
}
