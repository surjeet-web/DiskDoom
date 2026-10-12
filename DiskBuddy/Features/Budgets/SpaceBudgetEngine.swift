import Foundation

// MARK: - D7 Space Budget System (UserDefaults persistence; Foundation only)

struct SpaceBudget: Identifiable, Codable {
    let id: UUID
    var category: BudgetCategory
    var maxBytes: Int64

    init(id: UUID = UUID(), category: BudgetCategory, maxBytes: Int64) {
        self.id = id
        self.category = category
        self.maxBytes = maxBytes
    }
}

enum BudgetCategory: String, CaseIterable, Codable {
    case caches, logs, applications, userData, stale, duplicates

    var label: String {
        switch self {
        case .caches: return "Caches"
        case .logs: return "Logs"
        case .applications: return "Applications"
        case .userData: return "User Data"
        case .stale: return "Stale Files"
        case .duplicates: return "Duplicates"
        }
    }

    var nodeCategory: NodeCategory {
        switch self {
        case .caches: return .caches
        case .logs: return .logs
        case .applications: return .applications
        case .userData: return .userData
        case .stale: return .stale
        case .duplicates: return .duplicates
        }
    }
}

struct BudgetStatus: Identifiable {
    let id = UUID()
    let budget: SpaceBudget
    let currentBytes: Int64

    var usagePercent: Double { Double(currentBytes) / Double(max(budget.maxBytes, 1)) * 100 }
    var isOverBudget: Bool { currentBytes > budget.maxBytes }
}

// Main-confined in practice (driven from UI/main thread), hence Sendable.
final class SpaceBudgetEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var budgets: [SpaceBudget] = []
    @Published private(set) var statuses: [BudgetStatus] = []

    private let storageKey = "spaceBudgets"

    /// Last index handed to `evaluate(records:)`. Cached so `addBudget` /
    /// `removeBudget` can re-derive `statuses` without being handed the whole
    /// record array again — without it "Add Budget" persisted and did nothing
    /// visible (statuses were never rebuilt) until a full rescan.
    private var lastRecords: [ScannedRecord] = []
    private var lastDuplicateBytes: Int64 = 0

    init() {
        load()
        if budgets.isEmpty {
            // Sensible defaults (spec example: "Caches: max 20 GB").
            budgets = [
                SpaceBudget(category: .caches, maxBytes: 20_000_000_000),
                SpaceBudget(category: .logs, maxBytes: 2_000_000_000),
            ]
        }
        evaluate(records: [])
    }

    func addBudget(category: BudgetCategory, maxGB: Double) {
        budgets.append(SpaceBudget(category: category, maxBytes: Int64(maxGB * 1_000_000_000)))
        save()
        reevaluate()   // so the new budget actually shows a status
    }

    func removeBudget(_ budget: SpaceBudget) {
        budgets.removeAll { $0.id == budget.id }
        save()
        reevaluate()   // so the deleted budget actually disappears
    }

    /// Re-derive statuses from the cached index (no re-read of records).
    private func reevaluate() {
        evaluate(records: lastRecords, duplicateBytes: lastDuplicateBytes)
    }

    /// Evaluate against the REAL scan index (category totals from records).
    /// No scan yet → statuses report currentBytes 0 with a "scan needed" hint
    /// surfaced by the view — never fabricated totals.
    func evaluate(records: [ScannedRecord]) {
        lastRecords = records
        var totals: [BudgetCategory: Int64] = [:]
        for record in records where !record.isDirectory {
            switch record.category {
            case .caches: totals[.caches, default: 0] += record.bytes
            case .logs: totals[.logs, default: 0] += record.bytes
            case .stale: totals[.stale, default: 0] += record.bytes
            case .applications: totals[.applications, default: 0] += record.bytes
            case .userData: totals[.userData, default: 0] += record.bytes
            default: break
            }
        }
        statuses = budgets.map { BudgetStatus(budget: $0, currentBytes: totals[$0.category] ?? 0) }
    }

    /// Duplicates aren't a scan category — pass measured duplicate bytes in.
    func evaluate(records: [ScannedRecord], duplicateBytes: Int64) {
        lastDuplicateBytes = duplicateBytes
        evaluate(records: records)
        if let i = budgets.firstIndex(where: { $0.category == .duplicates }) {
            let dup = budgets[i]
            statuses.removeAll { $0.budget.id == dup.id }
            statuses.append(BudgetStatus(budget: dup, currentBytes: duplicateBytes))
        }
    }

    var hasRealData: Bool { !statuses.isEmpty && statuses.contains { $0.currentBytes > 0 } }

    private func save() {
        if let data = try? JSONEncoder().encode(budgets) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SpaceBudget].self, from: data)
        else { return }
        budgets = decoded
    }
}
