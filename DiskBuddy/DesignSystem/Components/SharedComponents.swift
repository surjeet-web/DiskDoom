import SwiftUI

// MARK: - Shared components (spec: Component Library Reference, prototype subset)

// EmptyState: SF Symbol + message + action button (§32).
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(DesignTokens.Palette.cyan)
                .frame(width: 104, height: 96)
                .background { MetalSurface(family: .well, flatSide: .bottom, depth: 8) }
                .padding(.bottom, 12)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PlateButtonStyle(primary: true))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// StatusBadge: small pill — granted (green), required (orange), denied (red).
struct StatusBadge: View {
    enum Kind { case granted, required, denied }

    let text: String
    let kind: Kind

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, DesignTokens.Space.s)
            .padding(.vertical, DesignTokens.Space.xs)
            .background(pillColor.opacity(0.15))
            .foregroundStyle(pillColor)
            .clipShape(ChassisShape(flatSide: .bottom, cut: 4))
    }

    private var pillColor: Color {
        switch kind {
        case .granted: return .green
        case .required: return .orange
        case .denied: return .red
        }
    }
}

// SizeBadge: rounded pill, color scales with size (§: Component Library).
struct SizeBadge: View {
    let bytes: Int64

    var body: some View {
        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            .font(.caption.monospacedDigit())
            .padding(.horizontal, DesignTokens.Space.s)
            .padding(.vertical, DesignTokens.Space.xs)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(ChassisShape(flatSide: .bottom, cut: 4))
    }

    private var badgeColor: Color {
        let gb: Int64 = 1_000_000_000
        if bytes > gb { return .red }
        if bytes > 100_000_000 { return .orange }
        return .secondary
    }
}

// CategoryLegend: pill swatches + labels (§05 legend, reference style).
struct CategoryLegend: View {
    let categories: [NodeCategory]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            legend
            ScrollView(.horizontal) { legend }
        }
    }

    private var legend: some View {
        HStack(spacing: DesignTokens.Space.s) {
            ForEach(categories, id: \.self) { category in
                HStack(spacing: DesignTokens.Space.xs) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(category.color)
                        .frame(width: 16, height: 16)
                    Text(category.label)
                        .font(.caption)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }
}
