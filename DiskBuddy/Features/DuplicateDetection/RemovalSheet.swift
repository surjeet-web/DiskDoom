import SwiftUI
import AppKit

// MARK: - Removal sheet (Trash / move / permanent delete + summary)

struct RemovalRequest: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let items: [(path: String, bytes: Int64)]
    var context: GameEventKind = .cleanup
}

struct RemovalSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let request: RemovalRequest
    var onFinish: ((RemovalResult) -> Void)? = nil

    @State private var method: RemovalMethod = .trash
    @State private var destination: String = ""
    @State private var overwrite = false
    @State private var understoodPermanent = false
    @State private var isWorking = false
    @State private var result: RemovalResult?
    @State private var didLoadDefaults = false

    private var knownBytes: Int64 {
        request.items.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.l) {
            HStack {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title).font(.title3.weight(.semibold))
                    Text(request.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close removal review")
            }

            if let result {
                resultView(result)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                    Text("Choose Removal Method").font(.headline)
                    Picker("Removal method", selection: $method) {
                        ForEach(RemovalMethod.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(method.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if method == .move {
                        HStack {
                            TextField("Destination folder", text: $destination)
                                .textFieldStyle(.roundedBorder)
                            Button("Choose…") { chooseDestination() }
                        }
                        Toggle("Overwrite files with the same name", isOn: $overwrite)
                            .toggleStyle(.checkbox)
                    }
                    if method == .permanent {
                        HStack(alignment: .top, spacing: DesignTokens.Space.s) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("These files will be deleted immediately and cannot be recovered from the Trash.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Toggle("I understand this cannot be undone", isOn: $understoodPermanent)
                            .toggleStyle(.checkbox)
                    }

                    HStack {
                        Text("\(request.items.count) items · \(ByteFormatting.format(knownBytes))")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                        Button(method == .permanent ? "Delete Permanently" : method.title) {
                            performRemoval()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(method == .permanent ? .red : .accentColor)
                        .disabled(isWorking || (method == .permanent && !understoodPermanent) || (method == .move && destination.isEmpty))
                    }
                    if isWorking {
                        ProgressView("Removing…")
                    }
                }
            }
        }
        .padding(24)
        .background { MetalSurface(family: .tiered, flatSide: .top, accent: DesignTokens.Palette.orange) }
        .padding(6)
        .frame(width: 600)
        .onAppear {
            guard !didLoadDefaults else { return }
            didLoadDefaults = true
            method = RemovalMethod(rawValue: state.removalMethod) ?? .trash
            destination = state.removalDestination
            overwrite = state.removalOverwrite
        }
    }

    @ViewBuilder
    private func resultView(_ result: RemovalResult) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
            HStack(spacing: DesignTokens.Space.s) {
                Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(result.failures.isEmpty ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.failures.isEmpty ? "Removal complete" : "Removal partially complete")
                        .font(.headline)
                    Text(result.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !result.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.failures) { failure in
                            Text("\(failure.path) — \(failure.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            HStack {
                Spacer()
                Button("Done") {
                    onFinish?(result)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func performRemoval() {
        isWorking = true
        state.removalMethod = method.rawValue
        state.removalDestination = destination
        state.removalOverwrite = overwrite
        state.saveSettings()
        let items = request.items
        let chosenMethod = method
        let chosenDestination = destination
        let shouldOverwrite = overwrite
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                RemovalService.remove(items: items, method: chosenMethod,
                                      destination: chosenDestination, overwrite: shouldOverwrite)
            }.value
            await MainActor.run {
                result = outcome
                isWorking = false
                if outcome.removedCount > 0 {
                    state.gamification.record(GameEvent(
                        kind: request.context,
                        bytes: outcome.removedBytes,
                        items: outcome.removedCount))
                }
                state.banner = AppState.Banner(
                    message: outcome.summary + (outcome.failures.isEmpty ? "" : " \(outcome.failures.count) failed."),
                    actionTitle: outcome.failures.isEmpty ? "OK" : "Details")
                state.dismissBannerAfterDelay()
            }
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Destination"
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }
}
