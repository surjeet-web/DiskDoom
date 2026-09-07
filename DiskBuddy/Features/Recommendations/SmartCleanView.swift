import SwiftUI

// MARK: - Smart Clean: recommendations + Quick Clean + large/old file finders

struct SmartCleanView: View {
    @EnvironmentObject var engine: RecommendationsEngine
    @EnvironmentObject var state: AppState
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
            HStack {
                Text("Smart Clean").font(.title2.weight(.semibold))
                Spacer()
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
                switch mode {
                case .recommendations: recommendationsList
                case .large: fileList(files: engine.largeFiles, empty: "No files above \(ByteFormatting.format(engine.largeThreshold)).")
                case .old: fileList(files: engine.oldFiles, empty: "No files older than \(engine.oldMonths) months.")
                }
            }
        }
        .onAppear { engine.compute(records: state.records) }
    }

    private var recommendationsList: some View {
        VStack(spacing: 0) {
            if engine.quickCleanBytes > 0 {
                HStack {
                    Text("Quick Clean can free \(ByteFormatting.format(engine.quickCleanBytes))")
                        .font(.headline)
                    Spacer()
                    Button("Quick Clean") {
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
            ScrollView {
                LazyVStack(spacing: DesignTokens.Space.m) {
                    ForEach(engine.recommendations) { rec in
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
                            Text("\(ByteFormatting.format(rec.bytes)) reclaimable · \(rec.paths.count) files")
                                .font(.callout.monospacedDigit()).foregroundStyle(.green)
                            HStack {
                                Spacer()
                                Button("Stage These") {
                                    for item in rec.paths {
                                        state.stage(source: "Smart Clean", path: item.path, bytes: item.bytes)
                                    }
                                    state.showCleanup = true
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        .padding(DesignTokens.Space.m)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
                    }
                }
                .padding()
            }
        }
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
                        Button("Stage") {
                            state.stage(source: "Smart Clean", path: file.path, bytes: file.bytes)
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
