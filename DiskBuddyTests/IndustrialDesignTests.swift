import SwiftUI
import Testing
@testable import DiskDoom

struct IndustrialDesignTests {
    @Test func shapeVerticesStayInsideBounds() {
        for family in ChassisFamily.allCases {
            for edge in DockEdge.allCases {
                for size in [CGSize(width: 1, height: 1), CGSize(width: 68, height: 36), CGSize(width: 800, height: 600)] {
                    let bounds = CGRect(origin: CGPoint(x: 7, y: 9), size: size)
                    let points = ChassisShape(family: family, flatSide: edge).vertices(in: bounds)
                    #expect(!points.isEmpty)
                    for p in points {
                        #expect(p.x >= bounds.minX && p.x <= bounds.maxX)
                        #expect(p.y >= bounds.minY && p.y <= bounds.maxY)
                        #expect(p.x.isFinite && p.y.isFinite)
                    }
                }
            }
        }
    }

    @Test func exactlyOneEdgeHasZeroDepth() {
        for dock in DockEdge.allCases {
            let faces = DockEdge.allCases.map { ChassisShape.extrusion(for: $0, flatSide: dock, depth: 6) }
            #expect(faces.filter { $0 == .zero }.count == 1)
            #expect(ChassisShape.extrusion(for: dock, flatSide: dock, depth: 6) == .zero)
        }
    }

    @Test func emptyBoundsHaveNoGeometry() {
        #expect(ChassisShape().vertices(in: .zero).isEmpty)
    }

    @Test func protectedContentInsetClearsBevelAndDepth() {
        #expect(DesignTokens.Geometry.safeInset >= DesignTokens.Geometry.cut + DesignTokens.Geometry.depth)
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 200)
        let inset = DesignTokens.Geometry.safeInset
        let protectedCorners = [CGPoint(x: inset, y: inset), CGPoint(x: bounds.maxX - inset, y: inset),
                                CGPoint(x: inset, y: bounds.maxY - inset), CGPoint(x: bounds.maxX - inset, y: bounds.maxY - inset)]
        for family in ChassisFamily.allCases {
            for edge in DockEdge.allCases {
                let path = ChassisShape(family: family, flatSide: edge).path(in: bounds)
                for corner in protectedCorners { #expect(path.contains(corner)) }
            }
        }
    }

    @MainActor @Test func navigationPreservesEveryRouteExactlyOnce() {
        let routes = AppState.SidebarTab.primary + AppState.SidebarTab.insights + AppState.SidebarTab.tools + AppState.SidebarTab.professional
        #expect(routes.count == 27)
        #expect(Set(routes) == Set(AppState.SidebarTab.allCases))
        #expect(Set(routes).count == routes.count)
        #expect(AppState.SidebarTab.primary.map(\.rawValue) == ["explore", "duplicates", "applications", "monitor", "snapshots"])
        #expect(AppState.SidebarTab.insights.first == .smartClean)
        #expect(AppState.SidebarTab.insights.last == .storage)
    }

    @MainActor @Test func localActivityDeduplicatesRetainsAndPersistsReadState() throws {
        let suite = "diskdoom.design.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = ActivityCenter(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        center.record(title: "Scan", body: "Measured", category: "SCAN", now: now)
        center.record(title: "Scan", body: "Measured", category: "SCAN", now: now.addingTimeInterval(1))
        #expect(center.notices.count == 1)
        #expect(center.unreadCount == 1)
        center.markRead(try #require(center.notices.first).id)
        #expect(ActivityCenter(defaults: defaults).unreadCount == 0)
        for index in 0..<220 {
            center.record(title: "Event \(index)", body: "Local summary", category: "SCAN", now: now.addingTimeInterval(Double(index + 10)))
        }
        #expect(center.notices.count == 200)
        #expect(center.notices.first?.title == "Event 219")
        center.markAllRead()
        #expect(center.unreadCount == 0)
    }
}
