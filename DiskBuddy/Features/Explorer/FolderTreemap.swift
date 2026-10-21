import SwiftUI

// MARK: - Explorer treemap (squarified, FNV-1a stable colors per path)

struct FolderTreemap: View {
    let nodes: [FolderNode]
    let totalSize: Int64
    let onSelect: (FolderNode) -> Void

    @State private var hoveredNodeID: String?

    var body: some View {
        GeometryReader { geometry in
            let items = nodes
                .filter { $0.size > 0 }
                .prefix(40)
                .map { TreemapItem(size: Double($0.size), node: $0) }
            let rectangles = squarify(items: Array(items), in: CGRect(origin: .zero, size: geometry.size))
            ZStack {
                ForEach(rectangles, id: \.node.id) { item in
                    let node = item.node
                    let rect = item.rect
                    Button { onSelect(node) } label: {
                    Rectangle()
                        .fill(deterministicColor(for: node, opacity: hoveredNodeID == node.id ? 0.65 : 0.4))
                        .overlay { Rectangle().stroke(deterministicColor(for: node, opacity: 0.9)) }
                        .frame(width: max(0, rect.width - 2), height: max(0, rect.height - 2))
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(node.name), \(node.sizeDisplay)")
                        .position(x: rect.midX, y: rect.midY)
                        .onHover { hoveredNodeID = $0 ? node.id : nil }
                    if rect.width > 70 && rect.height > 38 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                             Text(node.sizeDisplay)
                                 .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .frame(width: max(1, rect.width - 16), height: max(1, rect.height - 12), alignment: .center)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                    }
                }
            }
            .background(DesignTokens.Palette.app)
        }
    }

    private func deterministicColor(for node: FolderNode, opacity: Double) -> Color {
        let palette: [Color] = [.categoryApplications, .categoryUserData, .categorySystem,
                                .categoryCaches, .categoryDuplicates, .categoryOther]
        return palette[Int(stableHash(node.path) % UInt64(palette.count))].opacity(opacity)
    }

    private func stableHash(_ string: String) -> UInt64 {
        // FNV-1a: stable across launches (unlike Swift's hashValue).
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

private struct TreemapItem {
    let size: Double
    let node: FolderNode
    var rect: CGRect = .zero
}

private func squarify(items: [TreemapItem], in bounds: CGRect) -> [TreemapItem] {
    guard !items.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }
    let totalSize = items.reduce(0) { $0 + max(0, $1.size) }
    guard totalSize > 0 else { return [] }
    let area = bounds.width * bounds.height
    let normalized = items
        .filter { $0.size > 0 }
        .map { TreemapItem(size: $0.size / totalSize * Double(area), node: $0.node) }
        .sorted { $0.size > $1.size }
    var result: [TreemapItem] = []
    squarifyRecursive(items: normalized, rect: bounds, result: &result)
    return result
}

private func squarifyRecursive(items: [TreemapItem], rect: CGRect, result: inout [TreemapItem]) {
    guard !items.isEmpty, rect.width > 0, rect.height > 0 else { return }
    if items.count == 1 {
        var item = items[0]
        item.rect = rect
        result.append(item)
        return
    }
    let isHorizontal = rect.width >= rect.height
    let side = max(min(rect.width, rect.height), 0.0001)
    var row: [TreemapItem] = []
    var remaining = items
    while !remaining.isEmpty {
        let candidate = remaining[0]
        let candidateRatio = worstAspectRatio(row: row + [candidate], side: side)
        let currentRatio = worstAspectRatio(row: row, side: side)
        if row.isEmpty || candidateRatio <= currentRatio {
            row.append(candidate)
            remaining.removeFirst()
        } else {
            break
        }
    }
    let rowSum = row.reduce(0) { $0 + $1.size }
    guard rowSum > 0 else { return }
    let rowLength = rowSum / Double(side)
    var offset: CGFloat = 0
    for var item in row {
        let itemLength = item.size / rowLength
        guard itemLength.isFinite, itemLength >= 0 else { continue }
        if isHorizontal {
            item.rect = CGRect(x: rect.minX, y: rect.minY + offset, width: rowLength, height: itemLength)
        } else {
            item.rect = CGRect(x: rect.minX + offset, y: rect.minY, width: itemLength, height: rowLength)
        }
        result.append(item)
        offset += itemLength
    }
    let remainingRect: CGRect
    if isHorizontal {
        remainingRect = CGRect(x: rect.minX + rowLength, y: rect.minY, width: max(0, rect.width - rowLength), height: rect.height)
    } else {
        remainingRect = CGRect(x: rect.minX, y: rect.minY + rowLength, width: rect.width, height: max(0, rect.height - rowLength))
    }
    if !remaining.isEmpty && remainingRect.width > 0 && remainingRect.height > 0 {
        squarifyRecursive(items: remaining, rect: remainingRect, result: &result)
    }
}

private func worstAspectRatio(row: [TreemapItem], side: CGFloat) -> Double {
    guard !row.isEmpty, side > 0 else { return .infinity }
    let totalSize = row.reduce(0) { $0 + max(0, $1.size) }
    guard totalSize > 0 else { return .infinity }
    let rowLength = totalSize / Double(side)
    guard rowLength > 0 else { return .infinity }
    var worst = 0.0
    for item in row where item.size > 0 {
        let itemLength = item.size / rowLength
        guard itemLength > 0 else { continue }
        worst = max(worst, max(rowLength / itemLength, itemLength / rowLength))
    }
    return worst
}
