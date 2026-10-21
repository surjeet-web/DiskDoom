import SwiftUI
import AppKit

// MARK: - §05 Explore: Treemap (squarified layout, real scan data)

struct TreemapView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []
    @State private var layoutCache = TreemapGeometryCache()
    @State private var showAccessibleList = false

    private var currentNodes: [ScanNode] {
        if let last = drillPath.last, !last.children.isEmpty { return last.children }
        return state.effectiveTopLevel
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text(drillPath.last?.path ?? state.scanRoot?.path ?? state.scanTargetName)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { showAccessibleList.toggle() } label: {
                    Label(showAccessibleList ? "Show map" : "Accessible list", systemImage: showAccessibleList ? "square.grid.3x3" : "list.bullet")
                }.buttonStyle(PlateButtonStyle(selected: showAccessibleList))
            }
            if !drillPath.isEmpty {
                breadcrumb
            }
            if showAccessibleList {
                List(TreemapLayout.sortedNodes(currentNodes)) { node in
                    HStack {
                        Button {
                            state.selectedNode = node
                        } label: {
                            HStack {
                                Label(node.name, systemImage: node.category.symbol)
                                Spacer()
                                Text(node.sizeString).monospacedDigit()
                            }.frame(minHeight: 36)
                        }.buttonStyle(.plain)
                        Button("Open") { open(node) }
                            .disabled(node.children.isEmpty && !node.isCollapsed)
                            .accessibilityLabel("Open \(node.name)")
                    }
                }
            } else {
            GeometryReader { proxy in
                let cells = layoutCache.cells(nodes: currentNodes, in: CGRect(origin: .zero, size: proxy.size))
                ZStack(alignment: .topLeading) {
                    ForEach(cells, id: \.node.id) { cell in
                        // Not a Button (see BubblesView): a Button consumes the
                        // single tap so the double-tap drill never fires.
                        TreemapCell(
                            node: cell.node,
                            rect: cell.rect,
                            isSelected: state.selectedNode?.id == cell.node.id,
                             canOpen: !cell.node.children.isEmpty || cell.node.isCollapsed)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(cell.node.name), \(cell.node.sizeString)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { state.selectedNode = cell.node }
                            .accessibilityAction(named: Text("Open folder")) { open(cell.node) }
                            .contextMenu {
                            if cell.node.isActionable {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.selectFile((cell.node.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                                }
                                Button("Quick Look") { state.quickLookNode = cell.node }
                            } else {
                                Text("Aggregated items — not a real folder").font(.caption)
                            }
                                Divider()
                                Button("Focus (re-root view here)") {
                                    if !cell.node.children.isEmpty { drillPath.append(cell.node) }
                                }
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(cell.node.path, forType: .string)
                                }
                                Button("Copy Size") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(cell.node.sizeString, forType: .string)
                                }
                                Divider()
                                if cell.node.isActionable {
                                    Button("Stage for Cleanup") {
                                        state.stage(source: "Treemap", path: cell.node.path, bytes: cell.node.sizeBytes)
                                    }
                                } else {
                                    Text("Aggregated items — not a real folder").font(.caption)
                                }
                                Divider()
                                Button("Info") { state.selectedNode = cell.node }
                            }
                            .onTapGesture(count: 2) {
                                open(cell.node)
                            }
                            .onTapGesture {
                                state.selectedNode = cell.node
                            }
                    }
                }
            }
            }
            HStack {
                Text("Click to inspect · double-click to open a folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                CategoryLegend(categories: NodeCategory.allCases)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
        }
        .padding(DesignTokens.Space.m)
    }

    private func open(_ node: ScanNode) {
        if !node.children.isEmpty { drillPath.append(node) }
        else if node.isCollapsed { state.expandNode(path: node.path) }
    }

    /// VoiceOver summary of the visualization (charts are opaque to it).
    private var accessibilitySummary: String {
        let top = TreemapLayout.largestThree(currentNodes)
            .map { "\($0.name) \($0.sizeString)" }
            .joined(separator: ", ")
        return "Treemap of \(currentNodes.count) folders. Largest: \(top.isEmpty ? "none" : top)"
    }

    private var breadcrumb: some View {
        PageHeader(
            title: "Treemap",
            segments: crumbs,
            canGoBack: !drillPath.isEmpty,
            onBack: { drillPath.removeLast() },
            fallback: { drillPath.removeAll() })
    }

    private var crumbs: [Crumb] {
        var result: [Crumb] = [.link("All") { drillPath.removeAll() }]
        for node in drillPath {
            if node.id == drillPath.last?.id {
                result.append(.here(node.name))
            } else {
                result.append(.link(node.name) {
                    while drillPath.last?.id != node.id { drillPath.removeLast() }
                })
            }
        }
        return result
    }
}

// MARK: - Single treemap cell

private struct TreemapCell: View {
    let node: ScanNode
    let rect: CGRect
    let isSelected: Bool
    let canOpen: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showLabel: Bool { rect.width > 60 && rect.height > 40 }
    private var compact: Bool { rect.width < 150 || rect.height < 130 }
    private var hero: Bool { rect.width > 180 && rect.height > max(300, rect.width * 1.65) }
    private var tone: CinematicTileTone { .tone(for: node) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CinematicTileSurface(tone: tone, isSelected: isSelected)
            if showLabel {
                VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                    if rect.height > 85 {
                        Image(systemName: node.category.symbol)
                            .font(.system(size: hero ? 39 : (compact ? 19 : 27), weight: .semibold))
                            .frame(width: hero ? 46 : (compact ? 24 : 32), height: hero ? 46 : (compact ? 24 : 32))
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                            .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                        if !compact && !hero { Spacer(minLength: 8) }
                    }
                    Text(node.name)
                        .font(.system(size: hero ? 17 : (compact ? 12 : 14), weight: .heavy))
                         .lineLimit(1)
                    Text(node.sizeString)
                        .font(.system(size: hero ? 18 : (compact ? 11 : 14), weight: .bold).monospacedDigit())
                    if !compact {
                        Text("\(node.fileCount.formatted()) files\(node.isCollapsed ? " · ×2 to expand" : "")")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                .padding(.trailing, canOpen && rect.width > 100 ? 26 : 0)
                .padding(.horizontal, hero ? 32 : (compact ? 14 : 24))
                .padding(.vertical, hero ? 35 : (compact ? 14 : 24))
                if canOpen && rect.width > 100 && rect.height > 60 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: compact ? 11 : 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: compact ? 20 : 28, height: compact ? 20 : 28)
                        .background(Color(red: 7 / 255, green: 20 / 255, blue: 37 / 255).opacity(0.44), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.16)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottomTrailing : .trailing)
                        .padding(compact ? 8 : 14)
                        .accessibilityHidden(true)
                }
            }
        }
        // Gutters are decoration inside measured rectangles, never fake area weights.
        .frame(width: max(0, rect.width - min(9, rect.width * 0.12)),
               height: max(0, rect.height - min(9, rect.height * 0.12)))
        .overlay {
            if hero {
                CinematicTileOutline(hero: true)
                    .stroke(isSelected ? CinematicTileTone.color(0xd2f5ff) : .white.opacity(0.35), lineWidth: isSelected ? 4 : 1)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(CinematicTileOutline(hero: hero))
        .shadow(color: .black.opacity(0.6), radius: 7, y: 6)
        .shadow(color: CinematicTileTone.color(tone.rgb.glow).opacity(isSelected ? 0.4 : 0.18), radius: isSelected ? 10 : 8)
        .brightness(isHovered ? 0.10 : 0)
        .offset(y: isHovered && !reduceMotion ? -2 : 0)
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        .help(node.tooltip) // native tooltip, 200ms hover per spec
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// The reference's tall hero silhouette is decorative only; the measured cell
/// and its hit target remain the complete proportional rectangle.
private struct CinematicTileOutline: Shape {
    let hero: Bool

    func path(in rect: CGRect) -> Path {
        guard hero else { return RoundedRectangle(cornerRadius: 14).path(in: rect) }
        let fractions: [CGPoint] = [.init(x: 0.07, y: 0), .init(x: 0.96, y: 0),
                                   .init(x: 1, y: 0.05), .init(x: 1, y: 0.93),
                                   .init(x: 0.93, y: 1), .init(x: 0.06, y: 1),
                                   .init(x: 0, y: 0.94), .init(x: 0, y: 0.06)]
        var path = Path()
        path.addLines(fractions.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath()
        return path
    }
}

// Literal CSS tile variables from diskdoom-cinematic (1).html. These are surface
// materials, not substitutes for measured data or the app's semantic colors.
enum CinematicTileTone: CaseIterable, Hashable {
    case blue, orange, purple, green, slate, teal, red

    var rgb: (light: UInt32, edge: UInt32, dark: UInt32, glow: UInt32) {
        switch self {
        case .blue: return (0x23b2ff, 0x116be2, 0x09275e, 0x008cff)
        case .orange: return (0xffa047, 0xef6f29, 0x64250f, 0xff7d22)
        case .purple: return (0xd69aff, 0x9051db, 0x2e145f, 0xb95dff)
        case .green: return (0x36e9a4, 0x08a77e, 0x08382e, 0x06ffb0)
        case .slate: return (0x859daf, 0x566777, 0x111c29, 0xb3dafb)
        case .teal: return (0x2bd3eb, 0x1685d5, 0x092245, 0x1ecfff)
        case .red: return (0xff897d, 0xb74347, 0x4b1c30, 0xfb6764)
        }
    }

    static func tone(for category: NodeCategory) -> Self {
        switch category {
        case .userData: return .blue
        case .applications, .duplicates: return .purple
        case .caches: return .green
        case .system: return .slate
        case .logs: return .orange
        case .stale: return .red
        case .other: return .teal
        }
    }

    static func tone(for node: ScanNode) -> Self {
        // Match the reference's familiar folders without changing their size,
        // placement, names, or the semantic classification used by actions.
        switch node.name.lowercased() {
        case "users": return .blue
        case "documents": return .orange
        case "applications": return .purple
        case "library": return .green
        case "downloads": return .slate
        case "pictures": return .teal
        case "other": return .red
        default: return tone(for: node.category)
        }
    }

    fileprivate static func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
}

private struct CinematicTileSurface: View {
    let tone: CinematicTileTone
    let isSelected: Bool

    var body: some View {
        let light = CinematicTileTone.color(tone.rgb.light)
        let edge = CinematicTileTone.color(tone.rgb.edge)
        let dark = CinematicTileTone.color(tone.rgb.dark)
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(stops: [.init(color: light, location: 0),
                                             .init(color: edge, location: 0.6),
                                             .init(color: light, location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            ZStack {
                LinearGradient(colors: [light, dark], startPoint: .topLeading, endPoint: .bottomTrailing)
                EllipticalGradient(colors: [dark, .clear], center: UnitPoint(x: 0.75, y: 0.7), endRadiusFraction: 0.73)
                EllipticalGradient(colors: [light, .clear], center: UnitPoint(x: 0, y: 1.1), endRadiusFraction: 0.47)
                EllipticalGradient(colors: [.white.opacity(0.47), .clear], center: UnitPoint(x: 1.03, y: 0), endRadiusFraction: 0.3)
                // Soft conic reflections, corresponding to .tile-art (never rasterized text).
                AngularGradient(stops: [.init(color: .clear, location: 0),
                                        .init(color: .white.opacity(0.33), location: 29 / 360),
                                        .init(color: .clear, location: 48 / 360),
                                        .init(color: .black.opacity(0.27), location: 100 / 360),
                                        .init(color: .white.opacity(0.2), location: 145 / 360),
                                        .init(color: .clear, location: 215 / 360),
                                        .init(color: .white.opacity(0.33), location: 295 / 360),
                                        .init(color: .clear, location: 340 / 360)],
                                center: UnitPoint(x: 0.7, y: 0.55), angle: .degrees(7))
                    .blur(radius: 14).opacity(0.42)
                CinematicTileFacets()
                    .blendMode(.screen).opacity(0.52)
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(.black.opacity(0.24), lineWidth: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .padding(2)
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.53), .clear, .black.opacity(0.4)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? CinematicTileTone.color(0xd2f5ff) : .clear, lineWidth: 2)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct CinematicTileFacets: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var facet = Path()
            let points: [CGPoint] = [.init(x: 0, y: 0), .init(x: w, y: 0), .init(x: w * 0.83, y: h * 0.35),
                                     .init(x: w, y: h * 0.6), .init(x: w * 0.49, y: h),
                                     .init(x: 0, y: h * 0.9), .init(x: w * 0.24, y: h * 0.42)]
            facet.addLines(points)
            facet.closeSubpath()
            context.clip(to: facet)
            // The two fine diagonal seams and bounded brushed-metal striations.
            var seams = Path()
            seams.move(to: CGPoint(x: 0, y: h * 0.26))
            seams.addLine(to: CGPoint(x: w, y: h * 0.72))
            seams.move(to: CGPoint(x: 0, y: h * 0.78))
            seams.addLine(to: CGPoint(x: w, y: h * 0.32))
            context.stroke(seams, with: .color(.white.opacity(0.19)), lineWidth: 1)
            var brush = Path()
            for index in 0..<min(100, Int((w + h) / 37) + 2) {
                let x = CGFloat(index) * 37 - h * 0.4
                brush.move(to: CGPoint(x: x, y: h))
                brush.addLine(to: CGPoint(x: x + h * 0.4, y: 0))
            }
            context.stroke(brush, with: .color(.white.opacity(0.043)), lineWidth: 1)
            context.fill(facet, with: .radialGradient(Gradient(colors: [.white.opacity(0.3), .clear]),
                                                    center: CGPoint(x: w * 0.72, y: h * 0.94),
                                                    startRadius: 0, endRadius: max(w, h) * 0.3))
        }
    }
}

// MARK: - Squarified treemap layout
//
// Classic Bruls/Dick squarify: each strip is laid along the longer edge and
// grown while the worst aspect ratio improves — rectangles stay close to
// square instead of the thin slivers slice-and-dice produces.

enum TreemapLayout {
    struct Cell { let node: ScanNode; let rect: CGRect }

    /// Equal measurements retain scan order, rather than jumping on refresh.
    static func sortedNodes(_ nodes: [ScanNode]) -> [ScanNode] {
        nodes.enumerated().sorted {
            $0.element.sizeBytes == $1.element.sizeBytes
                ? $0.offset < $1.offset : $0.element.sizeBytes > $1.element.sizeBytes
        }.map(\.element)
    }

    /// The VoiceOver summary needs only three entries, not another full sort
    /// whenever selection changes on the shared app state.
    static func largestThree(_ nodes: [ScanNode]) -> [ScanNode] {
        var top: [ScanNode] = []
        top.reserveCapacity(4)
        for node in nodes {
            let insertion = top.firstIndex { node.sizeBytes > $0.sizeBytes } ?? top.endIndex
            if insertion < 3 {
                top.insert(node, at: insertion)
                if top.count > 3 { top.removeLast() }
            }
        }
        return top
    }

    static func layout(nodes: [ScanNode], in rect: CGRect) -> [Cell] {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.maxX.isFinite, rect.maxY.isFinite,
              rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
              (rect.width * rect.height).isFinite else { return [] }
        let items = sortedNodes(nodes.filter { $0.sizeBytes > 0 })
        guard !items.isEmpty else { return [] }
        // Sum in floating point: several valid Int64 measurements can exceed Int64.max.
        let totalBytes = items.reduce(CGFloat(0)) { $0 + CGFloat($1.sizeBytes) }
        let scale = (rect.width * rect.height) / totalBytes
        guard scale > 0, scale.isFinite else { return [] }

        var cells: [Cell] = []
        cells.reserveCapacity(items.count)
        var bounds = rect
        var nextIndex = 0
        // WHY the guards below: when the final strip exactly exhausts `bounds`
        // the remaining side becomes 0 → `span` 0 → `thickness = rowArea/span`
        // = +infinity → `CGRect(height: .infinity)` reaches SwiftUI and the
        // window traps ("Invalid frame dimension (infinity)") on real scans
        // whose sizes sum to the parent's total.
        while nextIndex < items.count {
            guard bounds.width > 0, bounds.height > 0 else { break }
            // Each strip SPANS the shorter side; its thickness extends
            // along the longer side. Running strips the other way starves
            // the thickness of later (smaller) strips → slivers.
            let spanIsWidth = bounds.width <= bounds.height
            let span = spanIsWidth ? bounds.width : bounds.height
            let rowStart = nextIndex
            var rowArea: CGFloat = 0
            var smallest: CGFloat = .infinity
            var largest: CGFloat = 0
            var previousWorst: CGFloat = .infinity

            while nextIndex < items.count {
                let next = items[nextIndex]
                let nextArea = CGFloat(next.sizeBytes) * scale
                let candidateArea = rowArea + nextArea
                let candidateSmallest = min(smallest, nextArea)
                let candidateLargest = max(largest, nextArea)
                let withNext = worstRatio(smallest: candidateSmallest, largest: candidateLargest,
                                          totalArea: candidateArea, span: span)
                if nextIndex == rowStart || withNext <= previousWorst {
                    rowArea = candidateArea
                    smallest = candidateSmallest
                    largest = candidateLargest
                    previousWorst = withNext
                    nextIndex += 1
                } else {
                    break
                }
            }

            // Materialize the strip inside `bounds`.
            let thickness = min(rowArea / span, spanIsWidth ? bounds.height : bounds.width)
            guard span > 0, thickness > 0, thickness.isFinite else { break }
            var offset: CGFloat = 0
            for index in rowStart..<nextIndex {
                let item = items[index]
                let area = CGFloat(item.sizeBytes) * scale
                let length = min(area / thickness, max(0, span - offset))
                let cellRect = spanIsWidth
                    ? CGRect(x: bounds.minX + offset, y: bounds.minY, width: length, height: thickness)
                    : CGRect(x: bounds.minX, y: bounds.minY + offset, width: thickness, height: length)
                cells.append(Cell(node: item, rect: cellRect))
                offset += length
            }
            if spanIsWidth {
                // max(0, ...) because floating-point drift can push the remainder
                // slightly negative, which would feed SwiftUI a negative height.
                bounds = CGRect(x: bounds.minX, y: bounds.minY + thickness, width: bounds.width, height: max(0, bounds.height - thickness))
            } else {
                bounds = CGRect(x: bounds.minX + thickness, y: bounds.minY, width: max(0, bounds.width - thickness), height: bounds.height)
            }
        }
        return cells
    }

    /// Worst aspect ratio of a strip whose items sum to `totalArea`
    /// spanning a side of length `span` (thickness = totalArea / span).
    private static func worstRatio(smallest: CGFloat, largest: CGFloat, totalArea: CGFloat, span: CGFloat) -> CGFloat {
        guard totalArea > 0, span > 0, smallest > 0 else { return .infinity }
        let thickness = totalArea / span
        // The maximum can only occur at an endpoint; no row arrays or rescans.
        return max(thickness / (smallest / thickness), (largest / thickness) / thickness)
    }
}

/// A single bounded geometry entry. Display metadata is deliberately not cached:
/// same-ID scan updates must show fresh labels, counts, children and action safety.
final class TreemapGeometryCache {
    private struct Measurement: Equatable {
        let id: UUID
        let bytes: Int64
    }
    private var measurements: [Measurement] = []
    private var bounds: CGRect = .null
    private var geometry: [(index: Int, rect: CGRect)] = []
    private(set) var layoutCount = 0

    func cells(nodes: [ScanNode], in rect: CGRect) -> [TreemapLayout.Cell] {
        let key = nodes.map { Measurement(id: $0.id, bytes: $0.sizeBytes) }
        if key != measurements || bounds != rect {
            let cells = TreemapLayout.layout(nodes: nodes, in: rect)
            let indices = Dictionary(nodes.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            geometry = cells.compactMap { cell in indices[cell.node.id].map { (index: $0, rect: cell.rect) } }
            measurements = key
            bounds = rect
            layoutCount += 1
        }
        return geometry.map { TreemapLayout.Cell(node: nodes[$0.index], rect: $0.rect) }
    }
}

#Preview {
    TreemapView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
