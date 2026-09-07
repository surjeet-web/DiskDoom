import SwiftUI

// MARK: - D4 Developer Cache view

struct DevCacheView: View {
    @EnvironmentObject var engine: DevCacheEngine
    @EnvironmentObject var state: AppState

    private var grouped: [(DevCacheItem.DevCacheKind, [DevCacheItem])] {
        Dictionary(grouping: engine.items, by: \.kind)
            .sorted { $0.value.reduce(0) { $0 + $1.bytes } > $1.value.reduce(0) { $0 + $1.bytes } }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer Caches").font(.title2.weight(.semibold))
                    Text("Total: \(ByteFormatting.format(engine.totalBytes)) · Safe to clean: \(ByteFormatting.format(engine.safeBytes))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Scan") { engine.scan() }
                    .buttonStyle(.borderedProminent)
                Button("Clean All Safe") {
                    for item in engine.items where item.isSafeToClean {
                        state.stage(source: "Dev Caches", path: item.path, bytes: item.bytes)
                    }
                    state.showCleanup = true
                }
                .buttonStyle(.bordered)
                .disabled(engine.items.isEmpty)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            List {
                ForEach(grouped, id: \.0) { kind, items in
                    Section {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: DesignTokens.Space.s) {
                                        Text(item.project ?? (item.path as NSString).lastPathComponent)
                                            .font(.body)
                                        if item.isSafeToClean {
                                            Text("Safe to clean")
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.green.opacity(0.2), in: Capsule())
                                                .foregroundStyle(.green)
                                        } else {
                                            Text("Review first")
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.orange.opacity(0.2), in: Capsule())
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Text(item.path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text(ByteFormatting.format(item.bytes))
                                    .font(.callout.monospacedDigit())
                                Button {
                                    state.stage(source: "Dev Caches", path: item.path, bytes: item.bytes)
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Stage for cleanup")
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: kind.symbol)
                            Text(kind.label)
                            Spacer()
                            Text(ByteFormatting.format(items.reduce(0) { $0 + $1.bytes }))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .onAppear { if engine.items.isEmpty { engine.scan() } }
    }
}

#Preview {
    DevCacheView()
        .environmentObject({ let e = DevCacheEngine(); e.scan(); return e }())
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
