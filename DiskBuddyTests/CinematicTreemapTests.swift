import SwiftUI
import Testing
@testable import DiskDoom

@MainActor
struct CinematicTreemapTests {
    private func node(_ bytes: Int64, index: Int = 0, id: UUID = UUID(), name: String? = nil) -> ScanNode {
        ScanNode(id: id, name: name ?? "Measured \(index)", path: "/measured/\(index)",
                 sizeBytes: bytes, category: .userData, fileCount: index + 1)
    }

    @Test func literalHTMLMaterialsRemainSaturatedAndDistinct() {
        let expected: [(UInt32, UInt32, UInt32)] = [
            (0x23b2ff, 0x116be2, 0x09275e), (0xffa047, 0xef6f29, 0x64250f),
            (0xd69aff, 0x9051db, 0x2e145f), (0x36e9a4, 0x08a77e, 0x08382e),
            (0x859daf, 0x566777, 0x111c29), (0x2bd3eb, 0x1685d5, 0x092245),
            (0xff897d, 0xb74347, 0x4b1c30)
        ]
        #expect(CinematicTileTone.allCases.count == expected.count)
        for (tone, values) in zip(CinematicTileTone.allCases, expected) {
            #expect(tone.rgb.light == values.0)
            #expect(tone.rgb.edge == values.1)
            #expect(tone.rgb.dark == values.2)
        }
        #expect(Set(NodeCategory.allCases.map { CinematicTileTone.tone(for: $0) }).count == 7)
        for (name, tone) in zip(["Users", "Documents", "Applications", "Library", "Downloads", "Pictures", "Other"], CinematicTileTone.allCases) {
            #expect(CinematicTileTone.tone(for: node(1, name: name)) == tone)
        }
    }

    @Test func measuredAreasAndNonzeroOriginsArePreserved() {
        let bounds = CGRect(x: 37, y: 53, width: 923, height: 617)
        let nodes = [node(59, index: 0), node(23, index: 1), node(13, index: 2), node(5, index: 3)]
        let cells = TreemapLayout.layout(nodes: nodes, in: bounds)
        #expect(cells.count == nodes.count)
        for cell in cells {
            let expected = bounds.width * bounds.height * CGFloat(cell.node.sizeBytes) / 100
            #expect(abs(cell.rect.width * cell.rect.height - expected) < expected * 1e-10)
            #expect(cell.rect.minX >= bounds.minX - 1e-8)
            #expect(cell.rect.minY >= bounds.minY - 1e-8)
            #expect(cell.rect.maxX <= bounds.maxX + 1e-8)
            #expect(cell.rect.maxY <= bounds.maxY + 1e-8)
        }
        for i in cells.indices {
            for j in cells.indices where j > i {
                let overlap = cells[i].rect.intersection(cells[j].rect)
                #expect(overlap.isNull || overlap.width * overlap.height < 1e-8)
            }
        }
    }

    @Test func equalMeasurementsKeepInputOrder() {
        let nodes = (0..<64).map { node(10, index: $0) }
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let first = TreemapLayout.layout(nodes: nodes, in: rect)
        let second = TreemapLayout.layout(nodes: nodes, in: rect)
        #expect(first.map(\.node.id) == nodes.map(\.id))
        #expect(first.map(\.rect) == second.map(\.rect))
        #expect(TreemapLayout.sortedNodes(nodes).map(\.id) == nodes.map(\.id))
        #expect(TreemapLayout.largestThree(nodes).map(\.id) == Array(nodes.prefix(3)).map(\.id))
        #expect(TreemapLayout.largestThree([]).isEmpty)
        let varied = [node(1), node(9), node(4), node(12), node(3)]
        #expect(TreemapLayout.largestThree(varied).map(\.sizeBytes) == [12, 9, 4])
    }

    @Test func invalidBoundsAndNonpositiveMeasurementsHaveNoCells() {
        let nodes = [node(1), node(0), node(-1)]
        for rect in [CGRect.zero, CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
                     CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)] {
            #expect(TreemapLayout.layout(nodes: nodes, in: rect).isEmpty)
        }
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(TreemapLayout.layout(nodes: [], in: rect).isEmpty)
        #expect(TreemapLayout.layout(nodes: nodes, in: rect).map(\.node.id) == [nodes[0].id])
    }

    @Test func sumsBeyondInt64AndThinBoundsStayFinite() {
        let nodes = [node(Int64.max, index: 0), node(Int64.max, index: 1), node(Int64.max / 2, index: 2)]
        for size in [CGSize(width: 1, height: 10_000), CGSize(width: 10_000, height: 1),
                     CGSize(width: 0.25, height: 0.5)] {
            let cells = TreemapLayout.layout(nodes: nodes, in: CGRect(origin: .zero, size: size))
            #expect(cells.count == nodes.count)
            #expect(cells.allSatisfy { $0.rect.width.isFinite && $0.rect.height.isFinite && $0.rect.width > 0 && $0.rect.height > 0 })
            let area = cells.reduce(CGFloat(0)) { $0 + $1.rect.width * $1.rect.height }
            #expect(abs(area - size.width * size.height) < size.width * size.height * 1e-10)
        }
    }

    @Test func geometryCacheSkipsLayoutButReturnsFreshDisplayMetadata() throws {
        let cache = TreemapGeometryCache()
        let rect = CGRect(x: 11, y: 17, width: 800, height: 600)
        let original = node(100, name: "Original")
        let first = cache.cells(nodes: [original], in: rect)
        for _ in 0..<100 {
            _ = cache.cells(nodes: [original], in: rect)
        }
        #expect(cache.layoutCount == 1)
        let refreshed = ScanNode(id: original.id, name: "Fresh", path: "/fresh", sizeBytes: 100,
                                 category: .stale, fileCount: 812, isCollapsed: true, isSyntheticAggregate: true)
        let cell = try #require(cache.cells(nodes: [refreshed], in: rect).first)
        #expect(cache.layoutCount == 1)
        #expect(cell.rect == first.first?.rect)
        #expect(cell.node.name == "Fresh")
        #expect(cell.node.fileCount == 812)
        #expect(cell.node.isCollapsed)
        #expect(!cell.node.isActionable)
        _ = cache.cells(nodes: [node(101, id: original.id)], in: rect)
        #expect(cache.layoutCount == 2)
        _ = cache.cells(nodes: [original], in: rect.offsetBy(dx: 1, dy: 0))
        #expect(cache.layoutCount == 3)
        _ = cache.cells(nodes: [], in: rect)
        #expect(cache.cells(nodes: [], in: rect).isEmpty)
        #expect(cache.layoutCount == 4)
    }

    @Test func cacheInvalidatesForOrderingAndIdentityChanges() {
        let cache = TreemapGeometryCache()
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let nodes = (0..<8).map { node(10, index: $0) }
        _ = cache.cells(nodes: nodes, in: rect)
        let reversed = Array(nodes.reversed())
        #expect(cache.cells(nodes: reversed, in: rect).map(\.node.id) == reversed.map(\.id))
        #expect(cache.layoutCount == 2)
        _ = cache.cells(nodes: [node(10)], in: rect)
        #expect(cache.layoutCount == 3)
    }

    /// Bounded workload with diagnostic timing only, never a machine-dependent
    /// elapsed-time assertion or an unmeasured claim of improvement.
    @Test func largeMeasuredWorkloadAndCachedSelectionPasses() {
        let nodes = (0..<2_000).map { node(Int64(1 + ($0 * 7919) % 100_003), index: $0) }
        let bounds = CGRect(x: 19, y: 23, width: 1600, height: 1000)
        let clock = ContinuousClock()
        let start = clock.now
        let cells = TreemapLayout.layout(nodes: nodes, in: bounds)
        let elapsed = start.duration(to: clock.now)
        print("CinematicTreemap: 2000-node uncached layout diagnostic: \(elapsed)")
        #expect(cells.count == nodes.count)
        #expect(Set(cells.map(\.node.id)).count == nodes.count)
        let total = nodes.reduce(Double(0)) { $0 + Double($1.sizeBytes) }
        for cell in cells {
            let expected = bounds.width * bounds.height * CGFloat(Double(cell.node.sizeBytes) / total)
            #expect(cell.rect.width > 0 && cell.rect.height > 0)
            #expect(cell.rect.maxX <= bounds.maxX + 1e-7 && cell.rect.maxY <= bounds.maxY + 1e-7)
            #expect(abs(cell.rect.width * cell.rect.height - expected) < max(1e-7, expected * 1e-8))
        }
        let cache = TreemapGeometryCache()
        for _ in 0..<20 {
            #expect(cache.cells(nodes: nodes, in: bounds).count == nodes.count)
        }
        #expect(cache.layoutCount == 1)
    }
}
