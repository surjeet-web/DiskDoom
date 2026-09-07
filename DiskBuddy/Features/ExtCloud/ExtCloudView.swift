import SwiftUI

// MARK: - Extension cloud: file kinds sized by bytes (from the real record index)

struct ExtCloudView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedExt: String? = nil

    private struct ExtGroup: Identifiable {
        var id: String { ext }
        let ext: String
        let bytes: Int64
        let files: Int
    }

    private var groups: [ExtGroup] {
        var totals: [String: (bytes: Int64, files: Int)] = [:]
        for record in state.records where !record.isDirectory {
            let ext = (record.path as NSString).pathExtension.lowercased()
            let key = ext.isEmpty ? "(no extension)" : ".\(ext)"
            totals[key, default: (0, 0)] = (totals[key]?.bytes ?? 0 + record.bytes, totals[key]?.files ?? 0 + 1)
        }
        return totals.map { ExtGroup(ext: $0.key, bytes: $0.value.bytes, files: $0.value.files) }
            .sorted { $0.bytes > $1.bytes }
    }

    private var maxBytes: Int64 { groups.first?.bytes ?? 1 }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("File Kinds by Size")
                    .font(.headline)
                Spacer()
                Text("Chip area ∝ bytes · click a kind to list its largest files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if groups.isEmpty {
                EmptyState(symbol: "cloud.fill", title: "Scan first", message: "The extension cloud is built from your real file index.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                        ForEach(groups.prefix(60)) { group in
                            let scale = sqrt(CGFloat(group.bytes) / CGFloat(maxBytes))
                            Button {
                                selectedExt = selectedExt == group.ext ? nil : group.ext
                            } label: {
                                VStack(spacing: 2) {
                                    Text(group.ext)
                                        .font(.system(size: 11 + 13 * scale, weight: .semibold))
                                        .lineLimit(1)
                                    Text(group.bytes.fileSizeString)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(DesignTokens.Space.s)
                                .frame(minWidth: 80)
                                .background(selectedExt == group.ext ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06))
                                .clipShape(.rect(cornerRadius: DesignTokens.Radius.s))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.s)
                                        .stroke(selectedExt == group.ext ? Color.accentColor : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help("\(group.ext): \(group.bytes.fileSizeString) across \(group.files.formatted()) files")
                        }
                    }
                    .padding(.vertical, DesignTokens.Space.s)
                }
                if let ext = selectedExt {
                    Divider()
                    List(topFiles(ext: ext).prefix(30), id: \.path) { file in
                        HStack {
                            Text((file.path as NSString).lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Text(file.bytes.fileSizeString)
                                .font(.callout.monospacedDigit())
                            Button("Stage") {
                                state.stage(source: "ExtCloud", path: file.path, bytes: file.bytes)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 160)
                }
            }
        }
        .padding(DesignTokens.Space.m)
    }

    private func topFiles(ext: String) -> [ScannedRecord] {
        state.records
            .filter {
                !$0.isDirectory && ((($0.path as NSString).pathExtension.lowercased().isEmpty ? "(no extension)" : ".\(($0.path as NSString).pathExtension.lowercased())") == ext)
            }
            .sorted { $0.bytes > $1.bytes }
    }
}

#Preview {
    ExtCloudView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
