import SwiftUI

// MARK: - §04 Scanning Progress (prototype: driven by AppState mock timer)

struct ScanProgressView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DesignTokens.Space.xl) {
            Spacer()
            Image(systemName: "circle.dotted")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
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
            Text("\(state.scanFiles.formatted()) files · \(elapsedText) elapsed")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Cancel", action: state.cancelScan)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var elapsedText: String {
        let seconds = Int(state.scanProgress * MockScanData.scanSeconds)
        return String(format: "%.1fs", Double(seconds))
    }
}

#Preview {
    let state = AppState()
    state.scanPhase = .scanning
    state.scanProgress = 0.78
    state.scanPath = "Scanning /Users/you/Library/Caches"
    state.scanFiles = 1_423_891
    return ScanProgressView().environmentObject(state)
}
