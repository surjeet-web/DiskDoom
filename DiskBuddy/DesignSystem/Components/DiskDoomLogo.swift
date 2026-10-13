import SwiftUI

// MARK: - DiskDoom logo (cracked disk platter, SwiftUI-native)

struct DiskDoomLogo: View {
    enum Style {
        case full // icon + stacked DISK/DOOM + tagline
        case iconOnly
        case compact // icon + inline DISKDOOM
        case sidebar // 28px row for sidebar header
    }

    static let doomRed = Color(red: 1.0, green: 0.27, blue: 0.0)

    let style: Style
    let size: CGFloat

    @State private var sparksOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch style {
        case .full: fullLogo
        case .iconOnly: icon
        case .compact: compactLogo
        case .sidebar: sidebarLogo
        }
    }

    // MARK: Icon

    private var icon: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.18),
                            Color(red: 0.04, green: 0.04, blue: 0.07),
                        ],
                        center: .init(x: 0.45, y: 0.4),
                        startRadius: 0,
                        endRadius: size * 0.5))
                .frame(width: size, height: size)
            ForEach(1...6, id: \.self) { ring in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: ring % 2 == 0 ? 0.8 : 1.2)
                    .frame(width: size * CGFloat(ring) / 7.0, height: size * CGFloat(ring) / 7.0)
            }
            ForEach([5, 4, 3, 2], id: \.self) { ring in
                Circle()
                    .stroke(Color.blue.opacity(0.06), lineWidth: size * 0.02)
                    .frame(width: size * CGFloat(ring) / 7.5, height: size * CGFloat(ring) / 7.5)
            }
            Circle()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.08))
                .frame(width: size * 0.14, height: size * 0.14)
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: size * 0.14, height: size * 0.14)
            Circle()
                .fill(Color(red: 0.1, green: 0.1, blue: 0.15))
                .frame(width: size * 0.06, height: size * 0.06)
            CrackShape(points: [
                CGPoint(x: 0.72, y: 0.22), CGPoint(x: 0.66, y: 0.30),
                CGPoint(x: 0.62, y: 0.36), CGPoint(x: 0.58, y: 0.42),
                CGPoint(x: 0.55, y: 0.48), CGPoint(x: 0.52, y: 0.50),
            ])
            .stroke(Self.doomRed.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.008, lineCap: .round))
            .frame(width: size, height: size)
            .shadow(color: Self.doomRed.opacity(0.6), radius: 4)
            CrackShape(points: [
                CGPoint(x: 0.28, y: 0.75), CGPoint(x: 0.34, y: 0.70),
                CGPoint(x: 0.40, y: 0.64), CGPoint(x: 0.45, y: 0.58),
                CGPoint(x: 0.49, y: 0.53),
            ])
            .stroke(Self.doomRed.opacity(0.8), style: StrokeStyle(lineWidth: size * 0.006, lineCap: .round))
            .frame(width: size, height: size)
            .shadow(color: Self.doomRed.opacity(0.5), radius: 3)
            CrackShape(points: [
                CGPoint(x: 0.66, y: 0.30), CGPoint(x: 0.68, y: 0.34),
                CGPoint(x: 0.67, y: 0.39),
            ])
            .stroke(Self.doomRed.opacity(0.5), style: StrokeStyle(lineWidth: size * 0.005, lineCap: .round))
            .frame(width: size, height: size)
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(Color(red: 1.0, green: 0.4, blue: 0.0))
                    .frame(width: size * 0.012, height: size * 0.012)
                    .shadow(color: .orange.opacity(0.8), radius: 3)
                    .offset(sparkOffset(index: i))
                    .opacity(reduceMotion ? 0.8 : (sparksOn ? 1 : 0.6))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(Double(i) * 0.25),
                        value: sparksOn)
            }
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 2)
                .frame(width: size * 0.96, height: size * 0.96)
            Path { path in
                path.addArc(
                    center: CGPoint(x: size * 0.5, y: size * 0.47),
                    radius: size * 0.46,
                    startAngle: .degrees(200), endAngle: .degrees(280), clockwise: false)
            }
            .stroke(Color.white.opacity(0.04), lineWidth: size * 0.01)
        }
        .frame(width: size, height: size)
        .onAppear { sparksOn = !reduceMotion }
        .accessibilityHidden(true)
    }

    private func sparkOffset(index: Int) -> CGSize {
        let positions: [CGSize] = [
            CGSize(width: size * 0.18, height: -size * 0.18),
            CGSize(width: size * 0.12, height: -size * 0.12),
            CGSize(width: size * 0.06, height: -size * 0.06),
            CGSize(width: -size * 0.16, height: size * 0.18),
            CGSize(width: -size * 0.10, height: size * 0.12),
            CGSize(width: -size * 0.04, height: size * 0.06),
        ]
        return positions[index]
    }

    // MARK: Variants

    private var fullLogo: some View {
        VStack(spacing: size * 0.15) {
            icon
            VStack(spacing: size * 0.02) {
                Text("DISK")
                    .font(.system(size: size * 0.2, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(size * 0.08)
                Text("DOOM")
                    .font(.system(size: size * 0.2, weight: .black))
                    .foregroundStyle(Self.doomRed)
                    .tracking(size * 0.08)
            }
            Text("Reclaim your storage.")
                .font(.system(size: size * 0.055, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(size * 0.02)
        }
    }

    private var compactLogo: some View {
        HStack(spacing: size * 0.15) {
            icon
                .frame(width: size * 0.6, height: size * 0.6)
            HStack(spacing: 0) {
                Text("DISK")
                    .font(.system(size: size * 0.25, weight: .black))
                    .foregroundStyle(.white)
                Text("DOOM")
                    .font(.system(size: size * 0.25, weight: .black))
                    .foregroundStyle(Self.doomRed)
            }
        }
    }

    private var sidebarLogo: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 28, height: 28)
            HStack(spacing: 0) {
                Text("DISK")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                Text("DOOM")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Self.doomRed)
            }
        }
        .accessibilityLabel("DiskDoom")
    }
}

// MARK: - Deterministic crack path (stable across layout passes)

struct CrackShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard !points.isEmpty else { return }
            let scaled = points.map { CGPoint(x: $0.x * rect.width, y: $0.y * rect.height) }
            path.move(to: scaled[0])
            for i in 1..<scaled.count {
                let prev = scaled[i - 1]
                let current = scaled[i]
                // Deterministic jitter from the segment index (no random()
                // — random would redraw a different crack every layout pass).
                let jitter = CGFloat((i * 37) % 7) - 3.0
                path.addQuadCurve(
                    to: current,
                    control: CGPoint(
                        x: (prev.x + current.x) / 2 + jitter,
                        y: (prev.y + current.y) / 2 - jitter))
            }
        }
    }
}
