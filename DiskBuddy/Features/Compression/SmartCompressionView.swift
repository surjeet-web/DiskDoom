import SwiftUI

// MARK: - D8 Smart Compression view

struct SmartCompressionView: View {
    @EnvironmentObject var engine: SmartCompressionEngine
    @EnvironmentObject var state: AppState
    /// Per-file opt-in; never compress anything the user didn't tick.
    @State private var selected: Set<String> = []

    private var supportsCompression: Bool {
        SmartCompressionEngine.volumeSupportsCompression(at: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Compression").font(.title2.weight(.semibold))
                    Text("Transparent file compression — same paths, nothing breaks")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Analyze") { engine.analyze(records: state.records) }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isAnalyzing || engine.isCompressing)
            }
            .padding(DesignTokens.Space.m)
            // APFS has no transparent compression. Say so up front rather than
            // letting the user start a multi-hour rewrite of their home folder
            // that saves nothing (and temporarily doubles compressed files).
            if !supportsCompression {
                Label(
                    "This volume doesn't support transparent compression (APFS doesn't have it). Compressing is disabled — the savings below are estimates only.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, DesignTokens.Space.m)
                    .padding(.bottom, DesignTokens.Space.s)
            }
            if engine.isAnalyzing {
                ProgressView("Analyzing candidates…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if engine.isCompressing {
                VStack(spacing: DesignTokens.Space.m) {
                    Spacer()
                    ProgressView(value: engine.progress).frame(maxWidth: 320)
                    Text("Compressing… \(Int(engine.progress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Cancel") { engine.cancel() }.buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if engine.files.isEmpty {
                EmptyState(symbol: "archivebox.fill", title: "No compression candidates", message: supportsCompression ? "Run a scan, then Analyze to find old, uncompressed files that can be shrunk in place." : "Run a scan, then Analyze to see which files would compress well. This volume doesn't actually support compression, so nothing can be applied.", actionTitle: "Analyze", action: { engine.analyze(records: state.records) })
            } else {
                HStack(spacing: DesignTokens.Space.xl) {
                    VStack { Text("\(engine.files.count)").font(.title.weight(.bold)).monospacedDigit(); Text("Files").font(.caption).foregroundStyle(.secondary) }
                    VStack { Text(ByteFormatting.format(engine.totalSaving)).font(.title.weight(.bold)).foregroundStyle(.green).monospacedDigit(); Text("Est. Saving").font(.caption).foregroundStyle(.secondary) }
                    VStack { Text(supportsCompression ? "In-place" : "Unavailable").font(.title3.weight(.bold)); Text("Method").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(DesignTokens.Space.m)
                Divider()
                List(engine.files) { file in
                    HStack {
                        // Per-file opt-in. "Compress All" rewrote every file
                        // under $HOME >= 100 MB, including ~/Library/Mail and
                        // iCloud data, with no way to deselect.
                        Toggle("", isOn: Binding(
                            get: { selected.contains(file.path) },
                            set: { on in
                                if on { selected.insert(file.path) } else { selected.remove(file.path) }
                            }))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).font(.callout)
                            HStack(spacing: DesignTokens.Space.s) {
                                Text(file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                if let days = file.daysSinceAccess {
                                    Text("· \(days)d old").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            // No strikethrough on the "before" figure: it is the
                            // LOGICAL size (physicalBytes mirrors bytes), not an
                            // on-disk size.
                            Text(ByteFormatting.format(file.physicalBytes))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("est. \(ByteFormatting.format(file.physicalBytes - file.estimatedSaving))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.green)
                        }
                        Text("-\(ByteFormatting.format(file.estimatedSaving))").font(.caption.weight(.medium)).foregroundStyle(.green).frame(width: 80, alignment: .trailing)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                if let error = engine.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }
                HStack {
                    Text(supportsCompression
                         ? "Atomic apply via replaceItemAt — originals are never left half-written. Savings are estimates from file type, not measurements."
                         : "Disabled: this volume has no transparent compression. Applying would rewrite every file and free nothing.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Compress Selected (\(selected.count))") {
                        engine.compress(files: engine.files.filter { selected.contains($0.path) })
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(!state.license.canClean || !supportsCompression || selected.isEmpty)
                    if !state.license.canClean {
                        Text("Activate a license to compress files.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(DesignTokens.Space.m)
            }
        }
        .task(id: state.records.count) {
            // Only analyze once the scan has actually finished. This used to
            // fire on the first 20k-record batch streamed in by cache
            // hydration, producing a list computed from ~6% of the index.
            guard state.scanPhase == .done, !state.records.isEmpty else { return }
            if engine.files.isEmpty { engine.analyze(records: state.records) }
        }
        .onDisappear { engine.cancel() }
    }
}

#Preview {
    SmartCompressionView()
        .environmentObject({ let e = SmartCompressionEngine(); e.analyze(records: []); return e }())
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
