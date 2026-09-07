import SwiftUI

// MARK: - §11 Explore: Age Map (age buckets prototype, mock data)

struct AgeMapView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedBucket: AgeBucket? = nil

    private var buckets: [AgeBucket] { state.ageBuckets }
    private var maxBytes: Int64 { buckets.map(\.bytes).max() ?? 1 }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("File Age Distribution")
                    .font(.headline)
                Spacer()
            }
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
                            .background(selectedBucket?.id == bucket.id ? Color.accentColor.opacity(0.1) : .clear)
                            .clipShape(.rect(cornerRadius: DesignTokens.Radius.s))
                        }
                        .buttonStyle(.plain)
                        .help("\(bucket.label): \(bucket.bytes.fileSizeString) across \(bucket.files.formatted()) files")
                    }
                }
            }
            if let bucket = selectedBucket {
                Button("Show items in \(bucket.label)") {
                    state.stage(source: "AgeMap", path: "Files older than \(bucket.label)", bytes: bucket.bytes)
                    state.showCleanup = true
                }
                .buttonStyle(.borderedProminent)
            }
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("48 GB hasn't been touched in 2+ years — consider cleaning.")
                    .font(.caption)
            }
            .padding(DesignTokens.Space.s)
            .background(.orange.opacity(0.1))
            .clipShape(.rect(cornerRadius: DesignTokens.Radius.s))
        }
        .padding(DesignTokens.Space.m)
    }
}

#Preview {
    AgeMapView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
