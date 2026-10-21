import SwiftUI

// MARK: - D6 File Provenance view (works on real files; demo via /Applications/Safari.app)

struct FileProvenanceView: View {
    @EnvironmentObject var engine: FileProvenanceEngine
    @EnvironmentObject var state: AppState
    @State private var path = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("File Provenance").font(.title2.weight(.semibold))
                Spacer()
                Text("Which app created this file, when, and where it came from")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Space.m)
            HStack(spacing: DesignTokens.Space.s) {
                TextField("Enter a file path…", text: $path)
                    .textFieldStyle(.roundedBorder)
                Button("Analyze") { engine.analyze(path: expanded(path)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(expanded(path).isEmpty)
                Button("Selected Item") {
                    if let node = state.selectedNode {
                        path = node.path
                        engine.analyze(path: expanded(node.path))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(state.selectedNode == nil)
                Button("Demo: Safari.app") {
                    path = "/Applications/Safari.app"
                    engine.analyze(path: path)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, DesignTokens.Space.m)
            .padding(.bottom, DesignTokens.Space.s)
            Divider()
            if engine.isAnalyzing {
                ProgressView("Analyzing file origin…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let prov = engine.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
                        provenanceRow(icon: "doc.fill", title: (prov.filePath as NSString).lastPathComponent, detail: prov.filePath)
                        if let method = prov.method {
                            provenanceRow(icon: method.symbol, title: method.label, detail: prov.createdBy.map { "Created by \($0)" })
                        } else {
                            // WHY: no origin metadata exists for this file —
                            // showing nothing (or a guessed method) implied we
                            // knew an origin we never read.
                            provenanceRow(icon: "questionmark.circle", title: "Unknown — no origin metadata",
                                          detail: "No kMDItemWhereFroms or creator metadata was read for this file")
                        }
                        if let app = prov.matchedApp {
                            provenanceRow(icon: "app.fill", title: "Associated app: \(app)", detail: nil)
                        }
                        if let date = prov.createdDate {
                            provenanceRow(icon: "calendar", title: date.formatted(date: .long, time: .shortened), detail: "Creation date")
                        }
                        if let source = prov.downloadSource {
                            provenanceRow(icon: "arrow.down.circle.fill", title: source, detail: "Download source (kMDItemWhereFroms)")
                        }
                        if prov.isQuarantined {
                            Label("Quarantined — downloaded from the internet.", systemImage: "shield.checkered")
                                .font(.callout).foregroundStyle(.orange)
                        }
                        HStack(spacing: DesignTokens.Space.xs) {
                            Circle()
                                .fill(prov.confidence == .high ? .green : prov.confidence == .medium ? .orange : .red)
                                .frame(width: 8, height: 8)
                            Text("Confidence: \(prov.confidence.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !prov.xattrNames.isEmpty {
                            Text("Extended attributes: \(prov.xattrNames.joined(separator: ", "))")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .industrialPanel(.well, flatSide: .right, accent: DesignTokens.Palette.violet)
                    .padding()
                }
            } else {
                EmptyState(symbol: "magnifyingglass.circle", title: "Trace any file's origin", message: "Enter a path, use the selected item, or run the Safari demo. Real metadata via mdls + extended attributes.")
            }
        }
        .onDisappear { engine.cancel() }
    }

    private func expanded(_ p: String) -> String {
        (p as NSString).expandingTildeInPath
    }

    private func provenanceRow(icon: String, title: String, detail: String?) -> some View {
        HStack(spacing: DesignTokens.Space.m) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(DesignTokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.15))
    }
}

#Preview {
    FileProvenanceView()
        .environmentObject(FileProvenanceEngine())
        .environmentObject(AppState())
        .frame(width: 700, height: 500)
}
