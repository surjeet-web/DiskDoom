import SwiftUI

// MARK: - §04 Scanning Progress (real engine progress, cancellable)

struct ScanProgressView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DesignTokens.Space.xl) {
            Spacer()
            Image(systemName: "circle.dotted")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Scanning \(state.scanTargetName)")
                .font(.headline)
            Text(state.scanPath.isEmpty ? "Preparing scan…" : state.scanPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressView(value: state.scanProgress) {
                Text("\(Int(state.scanProgress * 100))%")
                    .font(.caption.monospacedDigit())
            }
            .progressViewStyle(.linear)
            .frame(width: 420)
            Text("\(state.scanFiles.formatted()) files found")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Cancel", action: state.cancelScan)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ScanProgressView().environmentObject(AppState())
}
