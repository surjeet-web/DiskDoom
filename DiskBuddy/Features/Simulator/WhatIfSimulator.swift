import Foundation

// MARK: - D3 "What If" Simulator (stage → preview impact → commit routes to CleanupQueue)

struct SimulatedAction: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let bytes: Int64
    let risk: CleanupRisk // single source of truth (see CleanupRisk)
}

final class WhatIfSimulator: ObservableObject {
    @Published private(set) var staged: [SimulatedAction] = []

    var totalBytes: Int64 { staged.reduce(0) { $0 + $1.bytes } }
    var safeBytes: Int64 { staged.filter { $0.risk == .safe }.reduce(0) { $0 + $1.bytes } }
    var cautionBytes: Int64 { staged.filter { $0.risk == .caution }.reduce(0) { $0 + $1.bytes } }
    var riskyBytes: Int64 { staged.filter { $0.risk == .dangerous }.reduce(0) { $0 + $1.bytes } }

    /// Stage a scan node. Risk comes from the shared category mapping.
    func stage(_ node: ScanNode) {
        guard !staged.contains(where: { $0.path == node.path }) else { return }
        staged.append(SimulatedAction(
            name: node.name, path: node.path,
            bytes: node.sizeBytes, risk: CleanupRisk.forCategory(node.category)))
    }

    func remove(_ action: SimulatedAction) {
        staged.removeAll { $0.id == action.id }
    }

    func clear() { staged.removeAll() }

    /// Commit routes through the shared cleanup queue — never deletes directly.
    /// @MainActor because AppState is main-actor-isolated (call sites are UI actions).
    @MainActor
    func commit(to state: AppState) {
        for action in staged {
            state.stage(source: "What If?", path: action.path, bytes: action.bytes)
        }
        clear()
        state.showCleanup = true
    }
}
