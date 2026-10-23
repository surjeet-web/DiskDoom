import SwiftUI
import Testing
@testable import DiskDoom

/// The Explore palette is decorative reinforcement, not the only identifier.
/// These checks protect determinism (a folder keeps its hue between launches)
/// and breadth (the mode strip is not a single-hue control row).
struct ExploreColorTests {
    @Test func spectrumHasTwelveDistinctHues() {
        let colors = Set((0..<12).map { DesignTokens.Spectrum.color(at: $0) })
        #expect(colors.count == 12)
    }

    @Test func spectrumIndexWrapsBothDirections() {
        #expect(DesignTokens.Spectrum.color(at: 12) == DesignTokens.Spectrum.color(at: 0))
        #expect(DesignTokens.Spectrum.color(at: -1) == DesignTokens.Spectrum.color(at: 11))
    }

    @Test func keyedColorIsStableAndInPalette() {
        let first = DesignTokens.Spectrum.color(for: "/Users/example/Documents")
        let second = DesignTokens.Spectrum.color(for: "/Users/example/Documents")
        #expect(first == second)
        #expect((0..<12).map { DesignTokens.Spectrum.color(at: $0) }.contains(first))
        #expect(DesignTokens.Spectrum.color(for: "") == DesignTokens.Spectrum.color(at: 0))
    }

    @Test func everyExploreModeHasItsOwnTint() {
        let tints = Set(AppState.ExploreView.allCases.map(\.tint))
        #expect(tints.count == AppState.ExploreView.allCases.count)
        #expect(AppState.ExploreView.allCases.count == 12)
    }

    @Test func siblingFoldersDoNotAllCollapseToOneHue() {
        let nodes = (0..<12).map { index in
            ScanNode(name: "Folder \(index)", path: "/Users/example/Folder-\(index)",
                     sizeBytes: Int64(index + 1), category: .userData, fileCount: 1)
        }
        #expect(Set(nodes.map(\.visualColor)).count >= 6)
        #expect(nodes[0].visualColor == nodes[0].visualColor)
    }

    @Test func syntheticRollupKeepsNeutralCategoryColor() {
        let rollup = ScanNode(name: "Other (100 items)", path: "", sizeBytes: 1_000,
                              category: .other, fileCount: 100, isSyntheticAggregate: true)
        #expect(rollup.visualColor == NodeCategory.other.color)
    }
}
