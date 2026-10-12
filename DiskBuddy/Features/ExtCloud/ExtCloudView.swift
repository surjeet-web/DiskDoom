import SwiftUI

// MARK: - Extension cloud: file kinds sized by bytes (from the real record index)

struct ExtCloudView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedExt: String? = nil
    // WHY memoized: `groups` and `topFiles` aggregated the whole ~400k-record
    // index inside `body`, which reruns on every AppState publish (progress
    // ticks, selection, banner timers) — hundreds of ms of main-actor work per
    // render, i.e. multi-second main-thread stalls when renders land back to
    // back. Each pass now runs only when its key (every input) changes.
    @State private var groupsMemo = DerivationMemo<[ExtGroup]>()
    @State private var topFilesMemo = DerivationMemo<[ScannedRecord]>()

    private struct ExtGroup: Identifiable {
        var id: String { ext }
        let ext: String
        let bytes: Int64
        let files: Int
    }

    /// Complete input set of a records-derived pass. `records` is only ever
    /// replaced wholesale (a new scan or a cached restore — both bump
    /// `lastScanDate`) or appended to (count changes), so this key changes
    /// exactly when the data behind the pass can change.
    private struct RecordsKey: Hashable {
        let recordsCount: Int
        let scanDate: Date?
    }

    /// `topFiles` additionally depends on which kind is selected.
    private struct TopFilesKey: Hashable {
        let recordsCount: Int
        let scanDate: Date?
        let ext: String
    }

    private var groups: [ExtGroup] {
        groupsMemo(key: RecordsKey(recordsCount: state.records.count, scanDate: state.lastScanDate)) {
            var totals: [String: (bytes: Int64, files: Int)] = [:]
            for record in state.records where !record.isDirectory {
                let ext = (record.path as NSString).pathExtension.lowercased()
                let key = ext.isEmpty ? "(no extension)" : ".\(ext)"
                totals[key, default: (0, 0)] = (totals[key]?.bytes ?? 0 + record.bytes, totals[key]?.files ?? 0 + 1)
            }
            return totals.map { ExtGroup(ext: $0.key, bytes: $0.value.bytes, files: $0.value.files) }
                .sorted { $0.bytes > $1.bytes }
        }
    }

    // NaN guard: a scan can index many zero-byte files, making `first?.bytes` 0
    // (not nil), so `sqrt(0/0)` flows into `.font(size:)` and SwiftUI traps with
    // "Invalid frame dimension (NaN)". Clamp the divisor and the derived scale.
    private var maxBytes: Int64 { max(groups.first?.bytes ?? 0, 1) }

    /// Chips rendered per pass; the rest are dropped, so say so out loud rather
    /// than silently truncating a real scan's kind list.
    private let kindsLimit = 60

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
                        ForEach(groups.prefix(kindsLimit)) { group in
                            // NaN guard: clamp into 0...1 so rounding in the byte totals
                            // can never produce a negative or NaN font size.
                            let scale = min(1, max(0, sqrt(CGFloat(group.bytes) / CGFloat(maxBytes))))
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
                Text(groups.count > kindsLimit
                     ? "Top \(kindsLimit) of \(groups.count) kinds by size · \(groups.prefix(kindsLimit).reduce(Int64(0)) { $0 + $1.bytes }.fileSizeString) shown"
                     : "\(groups.count) kinds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        topFilesMemo(key: TopFilesKey(recordsCount: state.records.count, scanDate: state.lastScanDate, ext: ext)) {
            state.records
                .filter {
                    !$0.isDirectory && ((($0.path as NSString).pathExtension.lowercased().isEmpty ? "(no extension)" : ".\(($0.path as NSString).pathExtension.lowercased())") == ext)
                }
                .sorted { $0.bytes > $1.bytes }
        }
    }
}

/// Memoizes a whole-index derivation keyed by every input it reads.
///
/// WHY: without this, `body` re-ran the full aggregate/filter/sort pass on
/// every AppState publish. At ~400k records each pass blocked the main actor
/// for hundreds of milliseconds, so routine interaction (typing, selection,
/// progress ticks) turned into multi-second main-thread stalls.
@MainActor
private final class DerivationMemo<Value> {
    private var entry: (key: AnyHashable, value: Value)?

    /// Returns the cached value when `key` is unchanged; otherwise runs
    /// `compute` once and stores the result under the new key.
    func callAsFunction<Key: Hashable>(key: Key, _ compute: () -> Value) -> Value {
        let erased = AnyHashable(key)
        if let entry, entry.key == erased { return entry.value }
        let fresh = compute()
        entry = (erased, fresh)
        return fresh
    }
}

#Preview {
    ExtCloudView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
