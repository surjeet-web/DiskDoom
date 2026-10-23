import SwiftUI

// MARK: - §11 Explore: Age Map (age buckets prototype, mock data)

struct AgeMapView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedBucket: AgeBucket? = nil

    private var buckets: [AgeBucket] { state.ageBuckets }
    // NaN guard: an all-zero bucket set makes `.max()` return 0 rather than
    // nil, so `?? 1` never fires and `0/0` width reaches `.frame(width:)`.
    private var maxBytes: Int64 { max(buckets.map(\.bytes).max() ?? 0, 1) }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("File Age Distribution")
                    .font(.headline)
                Spacer()
            }
            if buckets.isEmpty {
                EmptyState(symbol: "calendar", title: "Scan first", message: "Age distribution is computed from your real scan data.", actionTitle: "Start Scan (⌘R)", action: { state.startScan() })
            } else {
                ScrollView {
                    VStack(spacing: DesignTokens.Space.s) {
                        ForEach(buckets) { bucket in
                            Button {
                                selectedBucket = bucket
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bucket.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(bucket.color.opacity(selectedBucket?.id == bucket.id ? 1 : 0.75))
                                            .frame(width: 200 * CGFloat(bucket.bytes) / CGFloat(maxBytes), height: 18)
                                        Text(bucket.bytes.fileSizeString)
                                            .font(.callout.monospacedDigit())
                                        Spacer()
                                        Text("\(bucket.files.formatted()) files")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(DesignTokens.Space.s)
                                .background(selectedBucket?.id == bucket.id ? bucket.color.opacity(0.16) : .clear)
                                .clipShape(.rect(cornerRadius: DesignTokens.Radius.s))
                            }
                            .buttonStyle(.plain)
                            .help("\(bucket.label): \(bucket.bytes.fileSizeString) across \(bucket.files.formatted()) files")
                        }
                    }
                }
                if let oldest = buckets.dropLast().last(where: { $0.bytes > 0 }) {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.orange)
                        Text("\(oldest.bytes.fileSizeString) of indexed files have dates in \(oldest.label.lowercased()). Age alone does not mean a file is safe to remove.")
                            .font(.caption)
                    }
                    .padding(DesignTokens.Space.s)
                    .background(.orange.opacity(0.1))
                    .clipShape(.rect(cornerRadius: DesignTokens.Radius.s))
                }
                Text("Based on indexed files. Unreadable or future dates appear under Unknown date; collapsed folders may contain more files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Space.m)
    }
}

#Preview {
    AgeMapView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
