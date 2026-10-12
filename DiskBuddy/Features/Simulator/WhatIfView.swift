import SwiftUI

// MARK: - What-If view: dual gauge + toggleable grouped targets + execute bar

struct WhatIfView: View {
    @EnvironmentObject var simulator: WhatIfSimulator
    @EnvironmentObject var state: AppState
    @EnvironmentObject var devCacheEngine: DevCacheEngine
    @EnvironmentObject var inventory: AppInventoryService
    @EnvironmentObject var lifecycleEngine: AppLifecycleEngine

    @State private var showExecuteConfirmation = false
    @State private var report: SimReport?

    var body: some View {
        VStack(spacing: 0) {
            storageGauge
            Divider()
            if simulator.isBuilding {
                buildingView
            } else if simulator.items.isEmpty {
                emptyView
            } else {
                controlBar
                Divider()
                itemList
                Divider()
                executeBar
            }
        }
        .task {
            if simulator.items.isEmpty, !simulator.isBuilding {
                await simulator.build(
                    state: state,
                    devCache: devCacheEngine,
                    inventory: inventory,
                    lifecycle: lifecycleEngine)
            }
        }
        .alert("Execute \(simulator.selectedIDs.count) Actions?", isPresented: $showExecuteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Execute", role: .destructive) {
                report = simulator.executeSelected(state: state)
            }
        } message: {
            Text("This will free \(ByteFormatting.format(simulator.selectedSavings)). Filesystem items go to the Trash first — the only permanent action is Empty Trash. Inspect-first items may need review.")
        }
        .sheet(item: $report) { report in
            SimReportSheet(report: report)
        }
    }

    // MARK: - Dual gauge (current → projected)

    private var storageGauge: some View {
        HStack(spacing: DesignTokens.Space.xl) {
            gaugeColumn(
                title: "Current",
                free: simulator.currentFree,
                percent: simulator.currentFreePercent,
                tint: .blue)

            VStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(ByteFormatting.format(simulator.selectedSavings))
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(.green)
                Text("freed")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            gaugeColumn(
                title: "After Cleanup",
                free: simulator.projectedFree,
                percent: simulator.projectedFreePercent,
                tint: simulator.projectedFreePercent > 30 ? .green : simulator.projectedFreePercent > 15 ? .yellow : .orange)

            Divider().frame(height: 80)

            VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive.fill").foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("Used: \(ByteFormatting.format(simulator.currentUsed))").font(.callout.monospacedDigit())
                        Text("→ \(ByteFormatting.format(simulator.projectedUsed))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "percent").foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text("\(String(format: "%.1f", 100 - simulator.currentFreePercent))% used").font(.callout.monospacedDigit())
                        Text("→ \(String(format: "%.1f", 100 - simulator.projectedFreePercent))% used")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                Text("\(simulator.selectedIDs.count) of \(simulator.items.count) items selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, DesignTokens.Space.s)
            Spacer()
        }
        .padding(DesignTokens.Space.m)
        .animation(.easeOut(duration: 0.2), value: simulator.selectedIDs)
    }

    private func gaugeColumn(title: String, free: Int64, percent: Double, tint: Color) -> some View {
        VStack(spacing: DesignTokens.Space.s) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(2)
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 12)
                    .frame(width: 104, height: 104)
                Circle()
                    .trim(from: 0, to: min(max(CGFloat(percent) / 100, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 104, height: 104)
                VStack(spacing: 2) {
                    Text(ByteFormatting.format(free))
                        .font(.callout.weight(.bold).monospacedDigit())
                    Text("free")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: DesignTokens.Space.m) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter…", text: $simulator.filterText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(width: 120)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Menu {
                Button("All Sources") { simulator.filterSource = nil }
                Divider()
                ForEach(SimSource.allCases) { source in
                    Button(source.rawValue) { simulator.filterSource = source }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: simulator.filterSource?.icon ?? "line.3.horizontal.decrease.circle")
                    Text(simulator.filterSource?.rawValue ?? "All Sources").font(.caption)
                }
            }
            .frame(width: 150)

            Menu {
                Button("All Risk Levels") { simulator.filterRisk = nil }
                Divider()
                ForEach([SimRisk.safe, .safeSlow, .caution, .dangerous], id: \.self) { risk in
                    Button(risk.label) { simulator.filterRisk = risk }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "shield")
                    Text("Risk").font(.caption)
                }
            }
            .frame(width: 70)

            Picker("", selection: $simulator.sortBy) {
                ForEach(WhatIfSimulator.SortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Spacer()

            HStack(spacing: DesignTokens.Space.xs) {
                Button("All") { simulator.selectAll() }.controlSize(.mini)
                Button("None") { simulator.selectNone() }.controlSize(.mini)
                Button("Safe Only") { simulator.selectSafeOnly() }.controlSize(.mini)
            }
            .buttonStyle(.bordered)

            Text("\(simulator.filteredItems.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
        .background(Color.secondary.opacity(0.03))
    }

    // MARK: - Grouped item list

    private var itemList: some View {
        List {
            let grouped = Dictionary(grouping: simulator.sortedFilteredItems, by: \.source)
            ForEach(SimSource.allCases) { source in
                if let groupItems = grouped[source], !groupItems.isEmpty {
                    let sourceTotal = groupItems.reduce(Int64(0)) { $0 + $1.savings }
                    let allSelected = groupItems.allSatisfy { simulator.selectedIDs.contains($0.id) }
                    Section {
                        ForEach(groupItems) { item in
                            SimItemRow(
                                item: item,
                                isSelected: simulator.selectedIDs.contains(item.id)) {
                                simulator.toggle(item.id)
                            }
                        }
                    } header: {
                        HStack(spacing: DesignTokens.Space.s) {
                            Image(systemName: source.icon)
                                .foregroundStyle(source.color)
                                .font(.caption)
                            Text(source.rawValue)
                                .font(.caption.weight(.semibold))
                            Text(ByteFormatting.format(sourceTotal))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(allSelected ? "Deselect" : "Select All") {
                                simulator.selectBySource(source)
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Execute bar

    private var executeBar: some View {
        HStack(spacing: DesignTokens.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(simulator.selectedIDs.count) items selected")
                    .font(.callout.weight(.medium))
                Text("\(ByteFormatting.format(simulator.selectedSavings)) will be freed")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            Spacer()
            HStack(spacing: DesignTokens.Space.s) {
                ForEach(riskCounts.sorted(by: { $0.key.sortOrder < $1.key.sortOrder }), id: \.key) { risk, count in
                    if count > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: risk.icon).font(.caption2)
                            Text("\(count)").font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(risk.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(risk.color)
                    }
                }
            }
            Button {
                showExecuteConfirmation = true
            } label: {
                Label("Execute Cleanup", systemImage: "bolt.fill")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(simulator.selectedIDs.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
        .background(.quaternary.opacity(0.4))
    }

    private var riskCounts: [SimRisk: Int] {
        var counts: [SimRisk: Int] = [:]
        for item in simulator.items where simulator.selectedIDs.contains(item.id) {
            counts[item.risk, default: 0] += 1
        }
        return counts
    }

    // MARK: - Building / empty

    private var buildingView: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Collecting cleanup targets…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Your Mac is clean").font(.title3.weight(.medium))
            Text("No significant cleanup targets found. Run a scan and come back — targets are built from your real scan data, duplicates, dev caches and downloads.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Item row

private struct SimItemRow: View {
    let item: SimItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: DesignTokens.Space.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
                    .font(.body)
                Image(systemName: item.icon)
                    .foregroundStyle(item.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.risk.label)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(item.risk.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(item.risk.color)
                Text(item.savingsFormatted)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.green)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Report sheet

private struct SimReportSheet: View {
    let report: SimReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignTokens.Space.l) {
            Image(systemName: report.failed == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(report.failed == 0 ? .green : .orange)
            Text(report.failed == 0 ? "Cleanup Complete" : "Cleanup Partially Complete")
                .font(.title2.weight(.semibold))

            HStack(spacing: DesignTokens.Space.xl) {
                VStack {
                    Text("\(report.succeeded)").font(.title.weight(.bold)).foregroundStyle(.green)
                    Text("Cleaned").font(.caption).foregroundStyle(.secondary)
                }
                VStack {
                    Text("\(report.failed)").font(.title.weight(.bold)).foregroundStyle(report.failed > 0 ? .red : .secondary)
                    Text("Failed").font(.caption).foregroundStyle(.secondary)
                }
                if report.skipped > 0 {
                    VStack {
                        Text("\(report.skipped)").font(.title.weight(.bold)).foregroundStyle(.orange)
                        Text("Manual").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack {
                    Text(ByteFormatting.format(report.totalFreed)).font(.title.weight(.bold)).foregroundStyle(.green)
                    Text("Freed").font(.caption).foregroundStyle(.secondary)
                }
            }

            if !report.failures.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                    Text("Failures").font(.headline)
                    ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
                        HStack(alignment: .top) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(failure.item).font(.callout)
                                Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !report.skips.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                    Text("Needs Your Action").font(.headline)
                    ForEach(Array(report.skips.enumerated()), id: \.offset) { _, skip in
                        HStack(alignment: .top) {
                            Image(systemName: "hand.point.right.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(skip.item).font(.callout)
                                Text(skip.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 460)
    }
}

#Preview {
    WhatIfView()
        .environmentObject(WhatIfSimulator())
        .environmentObject(AppState())
        .environmentObject(DevCacheEngine())
        .environmentObject(AppInventoryService())
        .environmentObject(AppLifecycleEngine())
        .frame(width: 900, height: 620)
}
