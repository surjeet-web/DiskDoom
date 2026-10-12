import SwiftUI
import AppKit

// MARK: - D4 Developer Cache view (category chips, risk badges, queue-routed clean)

struct DevCacheView: View {
    @EnvironmentObject var engine: DevCacheEngine
    @EnvironmentObject var state: AppState
    @State private var selectedKind: DevCacheItem.DevCacheKind?

    private var filtered: [DevCacheItem] {
        guard let kind = selectedKind else { return engine.items }
        return engine.items.filter { $0.kind == kind }
    }

    private var kindTotals: [(kind: DevCacheItem.DevCacheKind, size: Int64)] {
        var totals: [DevCacheItem.DevCacheKind: Int64] = [:]
        for item in engine.items {
            totals[item.kind, default: 0] += item.bytes
        }
        return totals.map { (kind: $0.key, size: $0.value) }.sorted { $0.size > $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            categoryBar
            Divider()
            if engine.isScanning && engine.items.isEmpty {
                VStack(spacing: DesignTokens.Space.m) {
                    Spacer()
                    ProgressView().controlSize(.large)
                    Text("Scanning developer caches…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if filtered.isEmpty {
                emptyView
            } else {
                resultList
                Divider()
                actionBar
            }
        }
        .onAppear {
            if engine.items.isEmpty, !engine.isScanning {
                engine.scan()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Developer Caches").font(.title2.weight(.semibold))
                Text("\(engine.items.count) locations on this Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatting.format(engine.totalBytes))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(engine.totalBytes > 5_000_000_000 ? .red : .orange)
                Text("total · \(ByteFormatting.format(engine.safeBytes)) safe to clean")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                engine.scan()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(engine.isScanning)
        }
        .padding(DesignTokens.Space.m)
    }

    // MARK: - Category chips

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Space.s) {
                CategoryChip(
                    label: "All",
                    size: engine.totalBytes,
                    isSelected: selectedKind == nil,
                    color: .accentColor) {
                    selectedKind = nil
                }
                ForEach(kindTotals, id: \.kind) { item in
                    CategoryChip(
                        label: item.kind.label,
                        size: item.size,
                        isSelected: selectedKind == item.kind,
                        color: kindColor(item.kind)) {
                        selectedKind = selectedKind == item.kind ? nil : item.kind
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Space.m)
            .padding(.vertical, DesignTokens.Space.s)
        }
        .background(Color.secondary.opacity(0.03))
    }

    // MARK: - Results

    private var resultList: some View {
        List(filtered) { item in
            HStack(spacing: DesignTokens.Space.m) {
                Image(systemName: item.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(kindColor(item.kind))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.callout.weight(.medium))
                        Text(item.riskLevel.shortLabel)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(riskColor(item.riskLevel).opacity(0.15), in: Capsule())
                            .foregroundStyle(riskColor(item.riskLevel))
                    }
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.fileCount > 0 {
                    Text("\(item.fileCount.formatted()) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                if let modified = item.lastModified {
                    Text(modified.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                Text(item.sizeFormatted)
                    .font(.callout.weight(.medium).monospacedDigit())
                    .foregroundStyle(item.bytes > 1_000_000_000 ? .red : .orange)
                    .frame(width: 76, alignment: .trailing)
            }
            .padding(.vertical, 3)
            .contextMenu {
                if item.isSafeToClean {
                    Button("Stage for Cleanup (Trash)") {
                        state.stage(source: "Dev Caches", path: item.path, bytes: item.bytes)
                        state.showCleanup = true
                    }
                }
                Button("Open in Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.path, forType: .string)
                }
                if let command = item.cleanCommand {
                    Divider()
                    Button("Copy Clean Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Text("\(filtered.count) locations · \(ByteFormatting.format(filtered.reduce(0) { $0 + $1.bytes }))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                for item in filtered where item.isSafeToClean {
                    state.stage(source: "Dev Caches", path: item.path, bytes: item.bytes)
                }
                state.showCleanup = true
            } label: {
                Label("Clean All Safe", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
            .disabled(engine.safeBytes == 0)
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
        .background(.quaternary.opacity(0.4))
    }

    private var emptyView: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No developer caches found").font(.title3)
            Text("No known development tool caches exist on this Mac — or no dev tools are installed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Rescan") { engine.scan() }.buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Colors

    private func kindColor(_ kind: DevCacheItem.DevCacheKind) -> Color {
        switch kind {
        case .xcode, .swiftpm: return .blue
        case .node: return .yellow
        case .python: return .green
        case .rust: return .orange
        case .go: return .cyan
        case .java, .android: return .purple
        case .dotnet: return .mint
        case .docker: return .indigo
        case .homebrew: return .gray
        case .git: return .red
        case .unity: return .teal
        case .vagrant: return .secondary
        case .ruby: return .pink
        case .php: return .purple
        case .ci: return .brown
        }
    }

    private func riskColor(_ risk: DevCacheItem.RiskLevel) -> Color {
        switch risk {
        case .safe: return .green
        case .safeSlow: return .yellow
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
}

// MARK: - Category chip

private struct CategoryChip: View {
    let label: String
    let size: Int64
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if size > 0 {
                    Text(ByteFormatting.format(size))
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? color : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : .primary)
    }
}

#Preview {
    DevCacheView()
        .environmentObject({ let e = DevCacheEngine(); e.scan(); return e }())
        .environmentObject(AppState())
        .frame(width: 900, height: 620)
}
