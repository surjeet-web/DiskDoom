import SwiftUI
import AppKit

/// Native counterpart of the cinematic HTML's right-hand panel.
struct CinematicInspectorView: View {
    let compact: Bool
    var stacked: Bool = false
    @EnvironmentObject private var state: AppState
    @State private var mode: Mode = .contents
    @State private var showsMetadata = false

    private enum Mode: String, CaseIterable {
        case contents = "Contents", types = "File Types", largest = "Largest", oldest = "Oldest"
    }

    private static let cyan = color(0x14c0ff)
    private static let ink = color(0xe3e9ee)
    private static let muted = color(0x9ca8b2)
    private static let chartColors = [color(0x1cb9ff), color(0xd78eff), color(0xeaa83e), color(0x728395)]

    var body: some View {
        VStack(spacing: 0) {
            if let node = state.selectedNode {
                header(node)
                tabs
                contents(node)
                footer(node)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder").font(.system(size: 52)).foregroundStyle(Self.cyan)
                    Text("No selection").font(.system(size: 19, weight: .heavy))
                    Text("Select an item to see its details.")
                        .font(.system(size: 11)).foregroundStyle(Self.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Self.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let (start, end) = CinematicCSS.endpoints(degrees: 110, in: rect)
                context.fill(Path(rect), with: .linearGradient(Gradient(stops: [
                    .init(color: Self.color(0x11171b), location: 0),
                    .init(color: Self.color(0x14181b), location: 0.6),
                    .init(color: Self.color(0x080b0e), location: 1)
                ]), startPoint: start, endPoint: end))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.black.opacity(0.44), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 18)
            }
            .overlay(alignment: .trailing) {
                Self.color(0xf98e31).opacity(0.07).frame(width: 12)
            }
        }
        .overlay(alignment: .leading) { Self.color(0x58778c).opacity(0.61).frame(width: 1).allowsHitTesting(false) }
        .overlay(alignment: .top) { Self.color(0x526a7c).frame(height: 1).allowsHitTesting(false) }
        .overlay(alignment: .trailing) { Self.color(0x748b99).opacity(0.64).frame(width: 1).allowsHitTesting(false) }
        .popover(isPresented: $showsMetadata) {
            if let node = state.selectedNode {
                metadata(node).environmentObject(state)
            }
        }
    }

    private func header(_ node: ScanNode) -> some View {
        let shares = categoryShares(node)
        return Group {
            if stacked {
                HStack(alignment: .center, spacing: 15) {
                    pathHeader(node)
                    selectionStats(node, shares: shares)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    pathHeader(node)
                    selectionStats(node, shares: shares)
                }
            }
        }
        .padding(.top, stacked ? 18 : compact ? 24 : 30)
        .padding(.horizontal, stacked ? 24 : compact ? 19 : 29)
        .padding(.bottom, stacked || compact ? 13 : 14)
        .frame(minHeight: stacked ? 153 : 220, alignment: stacked ? .center : .top)
    }

    private func pathHeader(_ node: ScanNode) -> some View {
        HStack(spacing: 17) {
            Image(systemName: node.category == .applications ? "app.fill" : "folder.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Self.cyan)
                .shadow(color: Self.color(0x009dfc).opacity(0.33), radius: 6, y: 5)
                .frame(width: 55, height: 53)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name).font(.system(size: 19, weight: .heavy)).lineLimit(2)
                Text(node.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Self.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectionStats(_ node: ScanNode, shares: [CinematicInspectorShare]) -> some View {
        HStack(alignment: .bottom, spacing: 7) {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.isPartial ? "≥ \(node.sizeString)" : node.sizeString)
                    .font(.system(size: compact ? 27 : 31, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(node.fileCount.formatted()) files")
                    .font(.system(size: 10)).foregroundStyle(Self.color(0xb6bdc5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: compact ? 5 : 10) {
                CinematicCategoryDonut(shares: shares, colors: Self.chartColors, diameter: compact ? 61 : 76)
                if !shares.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(shares) { share in
                            HStack(spacing: 6) {
                                Circle().fill(Self.chartColors[share.colorIndex]).frame(width: 6, height: 6)
                                Text(share.label).font(.system(size: 9)).lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(Self.color(0xbecbd4))
                }
            }
            .help(shares.isEmpty ? "No complete child-category measurements available" : "Byte shares of measured immediate children; not a file-extension analysis")
        }
    }

    private var tabs: some View {
        HStack(spacing: 3) {
            ForEach(Mode.allCases, id: \.self) { item in
                Button { mode = item } label: {
                    Text(item.rawValue)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(mode == item ? Color.white : Self.color(0xb7c0c7))
                        .background {
                            if mode == item {
                                Capsule().fill(LinearGradient(colors: [Self.color(0xff9c38), Self.color(0xf45e20)], startPoint: .top, endPoint: .bottom))
                                    .shadow(color: Self.color(0xf96528).opacity(0.6), radius: 7)
                            }
                        }
                        .overlay { Capsule().stroke(mode == item ? Self.color(0xffa250) : .clear, lineWidth: 1) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .frame(height: 55)
        .overlay(alignment: .top) { Self.color(0x5d6a74).opacity(0.48).frame(height: 1) }
        .overlay(alignment: .bottom) { Self.color(0x455562).opacity(0.5).frame(height: 1) }
        .padding(.horizontal, compact ? 9 : 20)
    }

    private func contents(_ node: ScanNode) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if mode == .types {
                    ForEach(NodeCategory.allCases, id: \.self) { category in
                        let members = node.children.filter { $0.category == category }
                        if !members.isEmpty {
                            categoryRow(category, members: members)
                        }
                    }
                } else {
                    if mode == .oldest && node.children.contains(where: { $0.modified == nil }) {
                        note("Items with unknown modification dates are omitted.")
                    }
                    ForEach(sortedChildren(node)) { child in
                        Button { state.selectedNode = child } label: {
                            HStack(spacing: 10) {
                                Image(systemName: child.category.symbol)
                                    .font(.system(size: 17)).foregroundStyle(Self.cyan).frame(width: 17)
                                Text(child.name).font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                                Text(child.isPartial ? "≥ \(child.sizeString)" : child.sizeString)
                                    .font(.system(size: 11)).foregroundStyle(Self.color(0xb2bac1))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .light)).foregroundStyle(Self.color(0x698194))
                            }
                            .padding(.horizontal, 5).frame(height: 41).contentShape(Rectangle())
                        }
                        .buttonStyle(CinematicInspectorRowStyle())
                        .overlay(alignment: .bottom) { Color.white.opacity(0.047).frame(height: 1) }
                        .help(child.path)
                    }
                }
                if node.children.isEmpty {
                    note(node.isCollapsed ? "Contents are collapsed. Expand this item from the actions menu." : "No indexed child entries available.")
                } else if mode == .oldest && sortedChildren(node).isEmpty {
                    note("No known modification dates.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 7).padding(.bottom, 12)
        .padding(.leading, compact ? 11 : 23).padding(.trailing, compact ? 9 : 18)
    }

    private func categoryRow(_ category: NodeCategory, members: [ScanNode]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.symbol).font(.system(size: 17)).foregroundStyle(Self.cyan).frame(width: 17)
            Text(category.label).font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(members.count.formatted()) items")
                Text("\(members.contains(where: \.isPartial) ? "≥ " : "")\(ByteFormatting.format(members.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }))")
            }
            .font(.system(size: 11)).foregroundStyle(Self.color(0xb2bac1))
        }
        .padding(.horizontal, 5).frame(height: 41)
        .overlay(alignment: .bottom) { Color.white.opacity(0.047).frame(height: 1) }
    }

    private func footer(_ node: ScanNode) -> some View {
        HStack(spacing: 10) {
            Text(node.isSyntheticAggregate ? "GROUPED RESULT" : node.isPartial ? "PARTIAL SCAN" : "LOCAL / INDEXED")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Self.color(0x7e909d))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Menu {
                Button("Metadata & App Artifacts…") { showsMetadata = true }
                Divider()
                if node.isActionable {
                    Button("Preview") { state.quickLookNode = node }
                    Button("Reveal in Finder") { reveal(node.path) }
                    Button("Copy Path") { copy(node.path) }
                    Button("Stage for Cleanup") {
                        state.stage(source: "Inspector", path: node.path, bytes: node.isPartial ? -1 : node.sizeBytes)
                    }
                    if node.isCollapsed {
                        Button("Expand Contents") { state.expandNode(path: node.path) }
                    }
                }
                if let app = matchingApp(node) {
                    Divider()
                    Button(app.isStale ? "Remove Leftovers…" : "Uninstall…") { state.uninstallApp = app }
                    Button("Clean Artifacts") { stageArtifacts(app) }.disabled(app.artifacts.isEmpty)
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 22, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Inspector actions and metadata").accessibilityLabel("Inspector actions and metadata")
            Button {
                // ScanNode does not carry a directory flag. Finder opens the
                // real directory, or reveals a selected file in its parent.
                let url = URL(fileURLWithPath: (node.path as NSString).expandingTildeInPath)
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    NSWorkspace.shared.open(url)
                } else {
                    reveal(node.path)
                }
            } label: {
                Text("OPEN FOLDER ↗").font(.system(size: 9))
                    .padding(.vertical, 6).padding(.horizontal, 9)
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(Self.color(0x465969), lineWidth: 1) }
            }
            .buttonStyle(.plain).foregroundStyle(Self.color(0xb1c5d4)).disabled(!node.isActionable)
        }
        .padding(.horizontal, 7).frame(height: 51)
        .overlay(alignment: .top) { Self.color(0x39454e).frame(height: 1) }
        .padding(.horizontal, 20)
    }

    private func metadata(_ node: ScanNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Metadata").font(.headline)
                Text(node.path).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                LabeledContent("Total Size", value: node.sizeString)
                LabeledContent("Files", value: node.fileCount.formatted())
                LabeledContent("Category", value: node.category.label)
                LabeledContent("Modified", value: node.modified?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                if let physical = node.physicalBytes {
                    LabeledContent("On Disk", value: physical.fileSizeString)
                    if node.sizeBytes > physical {
                        LabeledContent("APFS Savings", value: (node.sizeBytes - physical).fileSizeString)
                    }
                }
                if node.isSyntheticAggregate {
                    Text("Grouped scan result, not a real folder. Open its parent to inspect individual files.")
                }
                if node.isPartial {
                    Label("Size is a lower bound; some contents could not be measured.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if node.isCollapsed {
                    Text("Collapsed: \(node.collapseReason ?? "Contents not indexed")").foregroundStyle(.orange)
                    if node.isActionable {
                        Button("Expand Contents") { state.expandNode(path: node.path); showsMetadata = false }
                    }
                }
                if let app = matchingApp(node) {
                    Divider()
                    LabeledContent("Bundle Size", value: app.bundleBytes.fileSizeString)
                    LabeledContent("Artifacts Size", value: app.artifactBytes.fileSizeString)
                    DisclosureGroup("Artifacts (\(app.artifacts.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(app.artifacts, id: \.path) { artifact in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artifact.path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    HStack {
                                        Text("\(artifact.kind) · \(artifact.bytes.fileSizeString)").foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Stage") { state.stage(source: "Inspector", path: artifact.path, bytes: artifact.bytes) }
                                    }
                                }
                            }
                        }.padding(.top, 8)
                    }
                    HStack {
                        Button(app.isStale ? "Remove Leftovers…" : "Uninstall…") { state.uninstallApp = app; showsMetadata = false }
                        Button("Clean Artifacts") { stageArtifacts(app); showsMetadata = false }.disabled(app.artifacts.isEmpty)
                    }
                }
            }
            .font(.caption).padding(20)
        }
        .frame(width: 400, height: 480)
    }

    private func sortedChildren(_ node: ScanNode) -> [ScanNode] {
        switch mode {
        case .contents, .types: return node.children
        case .largest: return node.children.sorted { $0.sizeBytes > $1.sizeBytes }
        case .oldest:
            return node.children.filter { $0.modified != nil }.sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
        }
    }

    private func matchingApp(_ node: ScanNode) -> AppEntry? {
        guard let app = state.selectedApp, app.name == node.name || app.bundlePath == node.path else { return nil }
        return app
    }

    private func stageArtifacts(_ app: AppEntry) {
        for artifact in app.artifacts {
            state.stage(source: "Inspector", path: artifact.path, bytes: artifact.bytes)
        }
        state.showCleanup = true
    }

    private func categoryShares(_ node: ScanNode) -> [CinematicInspectorShare] {
        // A complete donut must not imply that lower-bound data is complete.
        guard !node.isPartial, !node.children.isEmpty,
              node.children.allSatisfy({ !$0.isPartial && $0.sizeBytes >= 0 }) else { return [] }
        let groups = NodeCategory.allCases.compactMap { category -> (String, Double)? in
            let bytes = node.children.filter { $0.category == category }.reduce(0.0) { $0 + Double($1.sizeBytes) }
            return bytes > 0 ? (category.label, bytes) : nil
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        let displayed: [(String, Double)]
        if groups.count > 4 {
            displayed = Array(groups.prefix(3)) + [("Other categories", groups.dropFirst(3).reduce(0) { $0 + $1.1 })]
        } else {
            displayed = groups
        }
        let total = displayed.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        var start = 0.0
        return displayed.enumerated().map { index, group in
            let end = start + group.1 / total
            defer { start = end }
            return CinematicInspectorShare(label: group.0, start: start, end: end, colorIndex: index)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Self.color(0x879aa8))
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 15).padding(.vertical, 30)
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.selectFile((path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
    }

    private func copy(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

private struct CinematicInspectorShare: Identifiable {
    var id: String { label }
    let label: String
    let start: Double
    let end: Double
    let colorIndex: Int
}

private struct CinematicCategoryDonut: View {
    let shares: [CinematicInspectorShare]
    let colors: [Color]
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.06), lineWidth: diameter * 0.224)
            ForEach(shares) { share in
                Circle().trim(from: CGFloat(share.start), to: CGFloat(share.end))
                    .stroke(colors[share.colorIndex], style: StrokeStyle(lineWidth: diameter * 0.224, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(diameter * 0.112)
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.cyan.opacity(0.13), radius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Measured child category byte shares")
        .accessibilityValue(shares.isEmpty ? "Unavailable" : shares.map { "\($0.label): \(Int((($0.end - $0.start) * 100).rounded())) percent" }.joined(separator: ", "))
    }
}

private struct CinematicInspectorRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CinematicInspectorRowBody(configuration: configuration)
    }
}

private struct CinematicInspectorRowBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovered = false

    var body: some View {
        configuration.label
            .background(Color(red: 37 / 255, green: 56 / 255, blue: 71 / 255).opacity(hovered || configuration.isPressed ? 0.61 : 0))
            .onHover { hovered = $0 }
    }
}
