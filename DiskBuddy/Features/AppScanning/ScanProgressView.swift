import SwiftUI
import Combine

// MARK: - §04 Scanning Progress (real engine progress, cancellable)
//
// Never looks stuck: live path, file count, elapsed time, and files/sec
// prove forward motion even while the bar sits near the top on huge trees.

struct ScanProgressView: View {
    @EnvironmentObject var state: AppState
    @State private var startedAt = Date()
    @State private var now = Date()
    @State private var lastFiles = 0
    @State private var lastTick = Date()
    @State private var filesPerSec: Double = 0
    @State private var timer: AnyCancellable?

    var body: some View {
        VStack(spacing: DesignTokens.Space.xl) {
            Spacer()
            ScanAnimationView(size: 128)
                .padding(28)
                .background { MetalSurface(family: .well, flatSide: .bottom, depth: 8, accent: DesignTokens.Palette.orange) }
            Text("Scanning \(state.scanTargetName)")
                .font(.headline)
            Text(state.scanPath.isEmpty ? "Preparing scan…" : state.scanPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressView("Measuring files · total not yet known")
            .progressViewStyle(.linear)
            .frame(maxWidth: 420)
            HStack(spacing: DesignTokens.Space.xl) {
                Text("\(state.scanFiles.formatted()) files")
                    .font(.caption.monospacedDigit())
                Text("\(Int(filesPerSec).formatted()) files/s")
                    .font(.caption.monospacedDigit())
                Text(elapsedText)
                    .font(.caption.monospacedDigit())
                if !state.skippedPaths.isEmpty {
                    Text("\(state.skippedPaths.count) skipped")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            Button("Cancel", action: state.cancelScan)
                .buttonStyle(PlateButtonStyle())
                .keyboardShortcut(.cancelAction)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startedAt = Date()
            lastTick = Date()
            lastFiles = state.scanFiles
            timer = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { tick in
                    now = tick
                    let dt = tick.timeIntervalSince(lastTick)
                    if dt > 0 {
                        let instant = Double(state.scanFiles - lastFiles) / dt
                        // Smoothed rate so the number doesn't jump wildly.
                        filesPerSec = filesPerSec == 0 ? instant : filesPerSec * 0.7 + instant * 0.3
                    }
                    lastFiles = state.scanFiles
                    lastTick = tick
                }
        }
        .onDisappear { timer?.cancel() }
    }

    private var elapsedText: String {
        let seconds = Int(now.timeIntervalSince(startedAt))
        if seconds < 60 { return "\(seconds)s elapsed" }
        return String(format: "%dm %02ds elapsed", seconds / 60, seconds % 60)
    }
}

#Preview {
    ScanProgressView().environmentObject(AppState())
}
