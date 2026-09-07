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

final class SpaceBudgetEngine: ObservableObject {
    @Published private(set) var budgets: [SpaceBudget] = []
    @Published private(set) var statuses: [BudgetStatus] = []

    private let storageKey = "spaceBudgets"

    init() {
        load()
        if budgets.isEmpty {
            // Prototype defaults (spec example: "Caches: max 20 GB").
            budgets = [
                SpaceBudget(category: .caches, maxBytes: 20_000_000_000),
                SpaceBudget(category: .logs, maxBytes: 2_000_000_000),
            ]
        }
        evaluate()
    }

    func addBudget(category: BudgetCategory, maxGB: Double) {
        budgets.append(SpaceBudget(category: category, maxBytes: Int64(maxGB * 1_000_000_000)))
        save()
        evaluate()
    }

    func removeBudget(_ budget: SpaceBudget) {
        budgets.removeAll { $0.id == budget.id }
        save()
        evaluate()
    }

    /// Evaluate against mock category totals (production: real scan totals).
    func evaluate() {
        let totals: [BudgetCategory: Int64] = [
            .caches: 38_000_000_000, .logs: 2_300_000_000, .applications: 48_000_000_000,
            .userData: 72_000_000_000, .stale: 4_200_000_000, .duplicates: 18_400_000_000,
        ]
        statuses = budgets.map { BudgetStatus(budget: $0, currentBytes: totals[$0.category] ?? 0) }
    }

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
