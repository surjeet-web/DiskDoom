import SwiftUI

// MARK: - D7 Space Budget view

struct SpaceBudgetView: View {
    @EnvironmentObject var engine: SpaceBudgetEngine
    @State private var showingAdd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Storage Budgets").font(.title2.weight(.semibold))
                Spacer()
                Button { showingAdd = true } label: {
                    Label("Add Budget", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            if engine.statuses.isEmpty {
                EmptyState(symbol: "gauge.with.dots.needle.33percent", title: "No budgets set", message: "Set limits for caches, logs, and other categories. DiskBuddy will alert you when they're exceeded.", actionTitle: "Add Your First Budget", action: { showingAdd = true })
            } else {
                ScrollView {
                    VStack(spacing: DesignTokens.Space.m) {
                        ForEach(engine.statuses) { status in
                            BudgetCard(status: status)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddBudgetSheet()
                .environmentObject(engine)
        }
    }
}

private struct BudgetCard: View {
    @EnvironmentObject var engine: SpaceBudgetEngine
    let status: BudgetStatus

    private var color: Color {
        if status.usagePercent > 100 { return .red }
        if status.usagePercent > 80 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Circle().fill(status.budget.category.nodeCategory.color).frame(width: 12, height: 12)
                Text(status.budget.category.label).font(.headline)
                Spacer()
                if status.isOverBudget {
                    Label("+\(ByteFormatting.format(status.currentBytes - status.budget.maxBytes)) over", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                Button { engine.removeBudget(status.budget) } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.2))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: min(geo.size.width, geo.size.width * CGFloat(status.usagePercent / 100)))
                    }
            }
            .frame(height: 12)
            HStack {
                Text("\(ByteFormatting.format(status.currentBytes)) used").monospacedDigit()
                Spacer()
                Text("Budget: \(ByteFormatting.format(status.budget.maxBytes)) (\(Int(status.usagePercent))%)")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.caption)
        }
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                .stroke(status.isOverBudget ? Color.red.opacity(0.3) : .clear, lineWidth: 1))
    }
}

private struct AddBudgetSheet: View {
    @EnvironmentObject var engine: SpaceBudgetEngine
    @Environment(\.dismiss) private var dismiss
    @State private var category: BudgetCategory = .caches
    @State private var maxGB = 20.0

    var body: some View {
        VStack(spacing: DesignTokens.Space.l) {
            Text("Add Storage Budget").font(.title2.weight(.semibold))
            Picker("Category", selection: $category) {
                ForEach(BudgetCategory.allCases, id: \.self) { cat in
                    Text(cat.label).tag(cat)
                }
            }
            HStack {
                Text("Maximum:")
                TextField("GB", value: $maxGB, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("GB")
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Budget") {
                    engine.addBudget(category: category, maxGB: maxGB)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

#Preview {
    SpaceBudgetView()
        .environmentObject(SpaceBudgetEngine())
        .frame(width: 700, height: 500)
}
