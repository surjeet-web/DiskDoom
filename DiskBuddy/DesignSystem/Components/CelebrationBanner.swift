import SwiftUI
import AppKit

// MARK: - Celebration banner + confetti + XP toast

struct CelebrationBanner: View {
    let celebration: GameCelebration
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if !reduceMotion {
                ConfettiBurst(seed: celebration.id.hashValue)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            HStack(spacing: DesignTokens.Space.m) {
                Image(systemName: celebration.symbol)
                    .font(.title)
                    .foregroundStyle(.yellow)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(celebration.title)
                        .font(.title3.weight(.bold))
                    Text(celebration.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                if celebration.isLevelUp {
                    Text("LEVEL UP")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.yellow.opacity(0.2), in: .capsule)
                        .foregroundStyle(.yellow)
                }
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(DesignTokens.Space.m)
            .frame(maxWidth: 520)
            .background(
                LinearGradient(colors: [Color(hex: 0x3A1C71), Color(hex: 0x6A38C2)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.l))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.l)
                    .stroke(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .padding(.top, 18)
        }
        .task(id: celebration.id) {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(celebration.title). \(celebration.detail)")
        .onAppear {
            guard !reduceMotion else { return }
            NSSound(named: "Glass")?.play()
        }
    }
}

struct XPRewardToast: View {
    let reward: GameReward
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text("+\(reward.amount) XP")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(reward.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.yellow.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        .task(id: reward.id) {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Earned \(reward.amount) XP for \(reward.reason)")
    }
}

private struct ConfettiBurst: View {
    let seed: Int
    @State private var animate = false

    private let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .yellow, .cyan]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<44, id: \.self) { index in
                    let width = 5 + random(index, 0) * 7
                    let height = 9 + random(index, 1) * 10
                    let x = random(index, 2) * geometry.size.width
                    let delay = random(index, 3) * 0.35
                    let travel = geometry.size.height + 80
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(colors[index % colors.count])
                        .frame(width: width, height: height)
                        .rotationEffect(.degrees(animate ? random(index, 4) * 1_080 : 0))
                        .position(x: x, y: animate ? travel : -30)
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeIn(duration: 1.7).delay(delay),
                            value: animate)
                }
            }
        }
        .onAppear { animate = true }
    }

    private func random(_ index: Int, _ salt: Int) -> Double {
        var value = UInt64(bitPattern: Int64(seed &* 31 &+ index &* 997 &+ salt &* 7_919))
        value ^= value >> 33
        value = value &* 0xff51afd7ed558ccd
        value ^= value >> 33
        return Double(value % 10_000) / 10_000
    }
}
