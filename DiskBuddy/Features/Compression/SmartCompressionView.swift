import SwiftUI

// MARK: - D8 Smart Compression view

struct SmartCompressionView: View {
    @EnvironmentObject var engine: SmartCompressionEngine

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Compression").font(.title2.weight(.semibold))
                    Text("APFS transparent compression for old files — same paths, nothing breaks")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Analyze") { engine.analyze() }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isAnalyzing || engine.isCompressing)
            }
            .padding(DesignTokens.Space.m)
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
                EmptyState(symbol: "archivebox.fill", title: "No compression candidates", message: "Run Analyze to find old, uncompressed files that APFS can shrink in place.", actionTitle: "Analyze", action: { engine.analyze() })
            } else {
                HStack(spacing: DesignTokens.Space.xl) {
                    VStack { Text("\(engine.files.count)").font(.title.weight(.bold)).monospacedDigit(); Text("Files").font(.caption).foregroundStyle(.secondary) }
                    VStack { Text(ByteFormatting.format(engine.totalSaving)).font(.title.weight(.bold)).foregroundStyle(.green).monospacedDigit(); Text("Potential Saving").font(.caption).foregroundStyle(.secondary) }
                    VStack { Text("APFS in-place").font(.title3.weight(.bold)); Text("Method").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(DesignTokens.Space.m)
                Divider()
                List(engine.files) { file in
                    HStack {
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
                            Text(ByteFormatting.format(file.physicalBytes)).font(.caption.monospacedDigit()).strikethrough()
                            Text("→ \(ByteFormatting.format(file.physicalBytes - file.estimatedSaving))").font(.caption.monospacedDigit()).foregroundStyle(.green)
                        }
                        Text("-\(ByteFormatting.format(file.estimatedSaving))").font(.caption.weight(.medium)).foregroundStyle(.green).frame(width: 80, alignment: .trailing)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                if let error = engine.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }
                HStack {
                    Text("Atomic apply via replaceItemAt — originals are never left half-written.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Compress All") { engine.compressAll() }
                        .buttonStyle(.borderedProminent).tint(.green)
                }
                .padding(DesignTokens.Space.m)
            }
        }
        .onDisappear { engine.cancel() }
    }
}

#Preview {
    SmartCompressionView()
        .environmentObject({ let e = SmartCompressionEngine(); e.analyze(); return e }())
        .frame(width: 800, height: 600)
}
