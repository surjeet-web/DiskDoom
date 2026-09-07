import Foundation

// MARK: - Single source of truth for cleanup risk (safe/caution/dangerous)

enum CleanupRisk: String {
    case safe, caution, dangerous

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .caution: return "Caution"
        case .dangerous: return "Risky"
        }
    }

    /// Risk for a scan category. One mapping used by Simulator, What-If, and recommendations.
    static func forCategory(_ category: NodeCategory) -> CleanupRisk {
        switch category {
        case .caches, .logs, .stale, .duplicates:
            return .safe
        case .userData, .other:
            return .caution
        case .applications, .system:
            return .dangerous
        }
    }
}
