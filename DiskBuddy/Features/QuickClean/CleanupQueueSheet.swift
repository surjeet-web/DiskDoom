import SwiftUI

// MARK: - §22 Cleanup Queue + §23 Delete Confirmation + §31C real failure report

struct CleanupQueueSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var overlays: OverlayStack
    @State private var confirmed = false

    private var groups: [(source: String, items: [CleanupItem])] {
        Dictionary(grouping: state.cleanupItems, by: \.source)
            .sorted { $0.key < $1.key }
            .map { (source: $0.key, items: $0.value) }
    }

    private var failedIDs: Set<String> {
        Set(state.trashFailures.map(\.path))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
            ModalHeader(title: "Cleanup Queue", overlayID: "cleanup") {
                state.showCleanup = false
            }
            Text("Cleanup Queue")
                .font(.title2.weight(.semibold))
            Text("\(state.cleanupItems.count) items staged · \(state.cleanupSizeSummary)")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !state.license.canClean {
                Label("Read-only mode — trial expired. Activate a license to execute cleanup.", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if state.cleanupItems.isEmpty && state.trashFailures.isEmpty {
                EmptyState(symbol: "trash", title: "Queue is empty", message: "Stage files from any view to clean them up in one batch.")
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Space.m) {
                        ForEach(groups, id: \.source) { group in
                            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                                Text("From \(group.source) · \(CleanupItem.sizeSummary(group.items))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(group.items) { item in
                                    HStack {
                                        if failedIDs.contains(item.path) {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                        Text(item.path)
                                            .font(.callout.monospaced())
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Text(item.sizeLabel)
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Button {
                                            state.cleanupItems.removeAll { $0.id == item.id }
                                        } label: {
                                            Image(systemName: "xmark.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove from queue")
                                    }
                                }
                            }
                            .specCard()
                        }
                    }
                }
                // §31C real partial-failure report.
                if !state.trashFailures.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                        Label("Cleanup Partially Complete", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                        ForEach(state.trashFailures, id: \.path) { failure in
                            HStack {
                                Text(failure.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(failure.reason).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Text("Close the app using the file, fix permissions, then retry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(DesignTokens.Space.m)
                    .background(.orange.opacity(0.08))
                    .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
                }
                Toggle("I understand these files will be moved to Trash", isOn: $confirmed)
                    .font(.callout)
                HStack {
                    Button("Clear Queue") {
                        state.cleanupItems.removeAll()
                        state.trashFailures.removeAll()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Move to Trash") {
                        state.showDeleteConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!confirmed || !state.license.canClean || state.cleanupIsMeasuring || state.cleanupItems.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 600, height: 560)
        .onAppear { overlays.present("cleanup") }
        .onDisappear { overlays.dismiss("cleanup") }
        .sheet(isPresented: $state.showDeleteConfirm) {
            DeleteConfirmSheet()
                .environmentObject(state)
                .environmentObject(overlays)
        }
    }
}

// MARK: - §23 Delete confirmation sheet

private struct DeleteConfirmSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var overlays: OverlayStack

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            ModalHeader(title: "Confirm Cleanup", overlayID: "cleanup-confirm") {
                state.showDeleteConfirm = false
            }
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Move \(state.cleanupItems.count) items to Trash?")
                .font(.title3.weight(.semibold))
            Text("\(state.cleanupSizeSummary). Files will be moved to Trash, not permanently deleted. You can restore them from there. Moving to Trash does not reclaim storage; empty Trash later to reclaim space.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack {
                Button("Cancel") { state.showDeleteConfirm = false }
                    .buttonStyle(.bordered)
                Button("Move to Trash") {
                    state.executeCleanup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!state.license.canClean || state.cleanupIsMeasuring || state.cleanupItems.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 440)
        .onAppear { overlays.present("cleanup-confirm") }
        .onDisappear { overlays.dismiss("cleanup-confirm") }
    }
}

#Preview {
    let s = AppState()
    s.cleanupItems = [
        CleanupItem(source: "Duplicates", path: "~/Downloads/photo_2024.jpg", bytes: 420_000_000),
        CleanupItem(source: "App Cleanup", path: "Google Chrome artifacts", bytes: 8_300_000_000),
    ]
    return CleanupQueueSheet().environmentObject(s)
}
