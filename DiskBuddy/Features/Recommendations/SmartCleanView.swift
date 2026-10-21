import SwiftUI

// MARK: - Smart Clean: recommendations + Quick Clean + large/old file finders

struct SmartCleanView: View {
    @EnvironmentObject var engine: RecommendationsEngine
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode = .recommendations

    enum Mode: String, CaseIterable {
        case recommendations, large, old
        var title: String {
            switch self {
            case .recommendations: return "Recommended"
            case .large: return "Large Files"
            case .old: return "Old Files"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Space.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Smart Clean").font(.title2.weight(.semibold))
                    Text("Review suggestions, then move selected files to Trash.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    state.showCleanup = true
                } label: {
                    Label("Queue (\(state.cleanupItems.count))", systemImage: "tray.full")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Review staged files before moving anything to Trash")
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in Text(m.title).tag(m) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            if state.records.isEmpty {
                EmptyState(symbol: "sparkles", title: "Scan first", message: "Recommendations are generated from your real scan data.", actionTitle: "Start Scan (⌘R)", action: { state.startScan() })
            } else {
                Group {
                    switch mode {
                    case .recommendations: recommendationsList
                    case .large: fileList(files: engine.largeFiles, empty: "No files above \(ByteFormatting.format(engine.largeThreshold)).")
                    case .old: fileList(files: engine.oldFiles, empty: "No files older than \(engine.oldMonths) months.")
                    }
                }
                .id(mode)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.base), value: mode)
        // WHY: `.onAppear` ran against a *partial* index (cache hydration streams the
        // records in), so recommendations were computed from a few thousand
        // records and never recomputed. Gate on a finished scan and re-run when
        // the index actually changes.
        .task(id: state.scanPhase == .done ? state.records.count : -1) {
            guard state.scanPhase == .done, !state.records.isEmpty else { return }
            engine.compute(records: state.records)
        }
    }

    private var recommendationsList: some View {
        VStack(spacing: 0) {
            if engine.quickCleanBytes > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Review up to \(ByteFormatting.format(engine.quickCleanBytes))")
                            .font(.headline)
                        Text("\(engine.quickCleanFileCount) suggested files · nothing is removed until you confirm in the queue")
                            .font(.caption).foregroundStyle(.secondary)
                        // WHY: only the top paths each recommendation lists are
                        // staged — state what is offered (and out of what) so
                        // the headline can't promise un-actionable space.
                        if engine.quickCleanPopulationBytes > engine.quickCleanBytes {
                            Text("Showing top \(engine.quickCleanFileCount) files · \(ByteFormatting.format(engine.quickCleanBytes)) of \(ByteFormatting.format(engine.quickCleanPopulationBytes)) total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Review Quick Clean") {
                        for rec in engine.recommendations where rec.confidence == .highlyRecommended {
                            for item in rec.paths {
                                state.stage(source: "Quick Clean", path: item.path, bytes: item.bytes)
                            }
                        }
                        state.showCleanup = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(DesignTokens.Space.m)
                Divider()
            }
            if engine.recommendations.isEmpty {
                EmptyState(
                    symbol: "checkmark.seal",
                    title: "Nothing to recommend yet",
                    message: "No stale files, app caches, or old logs were found in this scan. Check Large Files or Old Files for items to review manually."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Space.m) {
                        ForEach(engine.recommendations) { rec in
                            recommendationCard(rec)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func recommendationCard(_ rec: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text(rec.title).font(.headline)
                Spacer()
                Text(confidenceLabel(rec.confidence))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(confidenceColor(rec.confidence).opacity(0.15), in: Capsule())
                    .foregroundStyle(confidenceColor(rec.confidence))
            }
            Text(rec.detail).font(.callout).foregroundStyle(.secondary)
            Text("Up to \(ByteFormatting.format(rec.stageableBytes)) offered · \(ByteFormatting.format(rec.bytes)) found in total")
                .font(.callout.monospacedDigit()).foregroundStyle(.green)
            ForEach(rec.paths.prefix(3), id: \.path) { item in
                HStack(spacing: DesignTokens.Space.s) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(item.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.path)
                    Spacer(minLength: DesignTokens.Space.s)
                    Text(ByteFormatting.format(item.bytes))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if rec.paths.count > 3 {
                Text("+ \(rec.paths.count - 3) more files in this suggestion")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            HStack {
                Text("\(stagedCount(in: rec)) of \(rec.paths.count) staged")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Stage \(rec.paths.count) & Review") {
                    for item in rec.paths {
                        state.stage(source: "Smart Clean", path: item.path, bytes: item.bytes)
                    }
                    state.showCleanup = true
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(rec.paths.isEmpty)
            }
        }
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
    }

    private func stagedCount(in rec: Recommendation) -> Int {
        let staged = Set(state.cleanupItems.map { ($0.path as NSString).expandingTildeInPath })
        return rec.paths.filter { staged.contains(($0.path as NSString).expandingTildeInPath) }.count
    }

    private func isStaged(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        return state.cleanupItems.contains { ($0.path as NSString).expandingTildeInPath == expanded }
    }

    private func fileList(files: [ScannedRecord], empty: String) -> some View {
        Group {
            if files.isEmpty {
                EmptyState(symbol: "checkmark.circle", title: "Nothing found", message: empty)
            } else {
                List(files.prefix(500), id: \.path) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text((file.path as NSString).lastPathComponent).font(.callout).lineLimit(1)
                            Text(file.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(file.modified.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(ByteFormatting.format(file.bytes))
                            .font(.callout.monospacedDigit())
                            .frame(width: 80, alignment: .trailing)
                        Button(isStaged(file.path) ? "Review Queue" : "Stage") {
                            if isStaged(file.path) {
                                state.showCleanup = true
                            } else {
                                state.stage(source: "Smart Clean", path: file.path, bytes: file.bytes)
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                        }
                        Button("Stage for Cleanup") {
                            state.stage(source: "Smart Clean", path: file.path, bytes: file.bytes)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func confidenceLabel(_ c: Recommendation.Confidence) -> String {
        switch c {
        case .highlyRecommended: return "Highly Recommended"
        case .recommended: return "Recommended"
        case .consider: return "Consider"
        }
    }

    private func confidenceColor(_ c: Recommendation.Confidence) -> Color {
        switch c {
        case .highlyRecommended: return .green
        case .recommended: return .blue
        case .consider: return .gray
        }
    }
}

#Preview {
    SmartCleanView()
        .environmentObject(RecommendationsEngine())
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
