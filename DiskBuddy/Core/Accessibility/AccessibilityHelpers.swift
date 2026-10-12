import SwiftUI

// MARK: - Consistent accessibility modifiers across all views.
//
// VoiceOver users must get the same information sighted users do: sizes as
// spoken values, gauges as percentages, charts as summaries.

extension View {
    /// Standard tappable element.
    func accessibleButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }

    /// Size display with spoken byte count.
    func accessibleSize(_ bytes: Int64) -> some View {
        self
            .accessibilityLabel(ByteFormatting.format(bytes))
            .accessibilityValue("\(bytes) bytes")
    }

    /// Gauge / usage ring with percentage value.
    func accessibleProgress(value: Double, label: String) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue("\(Int(value * 100)) percent")
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Chart or visualization VoiceOver can't parse — give it a text summary.
    func accessibleChart(summary: String) -> some View {
        self
            .accessibilityLabel(summary)
            .accessibilityAddTraits(.isImage)
    }
}
