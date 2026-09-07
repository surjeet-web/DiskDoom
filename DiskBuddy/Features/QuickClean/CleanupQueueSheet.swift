import SwiftUI

// MARK: - §22 Cleanup Queue + §23 Delete Confirmation + §31C partial failure

struct CleanupQueueSheet: View {
    @EnvironmentObject var state: AppState
    @State private var confirmed = false

    private var groups: [(source: String, items: [CleanupItem])] {
        Dictionary(grouping: state.cleanupItems, by: \.source)
            .sorted { $0.key < $1.key }
            .map { (source: $0.key, items: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
            Text("Cleanup Queue")
                .font(.title2.weight(.semibold))
            Text("\(state.cleanupItems.count) items staged · \(state.cleanupTotal.fileSizeString) to free")
                .font(.callout)
                .foregroundStyle(.secondary)
            if state.cleanupItems.isEmpty {
                EmptyState(symbol: "trash", title: "Queue is empty", message: "Stage files from any view to clean them up in one batch.")
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Space.m) {
                        ForEach(groups, id: \.source) { group in
                            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                                Text("From \(group.source) · \(group.items.reduce(0) { $0 + $1.bytes }.fileSizeString)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(group.items) { item in
                                    HStack {
                                        if state.failedCleanupIDs.contains(item.id) {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                        Text(item.path)
                                            .font(.callout.monospaced())
                                            .lineLimit(1)
                                        Spacer()
                                        Text(item.bytes.fileSizeString)
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
                // §31C partial failure notice.
                if state.cleanupRequiresRetry {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                        Label("Cleanup Partially Complete", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("\(state.failedCleanupIDs.count) items could not be moved (in use / permission denied). They will be skipped on retry.")
                            .font(.caption)
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
                        state.failedCleanupIDs.removeAll()
                        state.cleanupRequiresRetry = false
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button(state.cleanupRequiresRetry ? "Retry Failed Items" : "Move to Trash · \(state.cleanupTotal.fileSizeString)") {
                        state.showDeleteConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!confirmed)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 600, height: 560)
        .sheet(isPresented: $state.showDeleteConfirm) {
            DeleteConfirmSheet()
                .environmentObject(state)
        }
    }
}

// MARK: - §23 Delete confirmation sheet

private struct DeleteConfirmSheet: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Move \(state.cleanupItems.count) items to Trash?")
                .font(.title3.weight(.semibold))
            Text("You're about to free \(state.cleanupTotal.fileSizeString). Files will be moved to your Trash. You can restore them from there.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack {
                Button("Cancel") { state.showDeleteConfirm = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    state.executeCleanup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 440)
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
