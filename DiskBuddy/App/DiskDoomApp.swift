import SwiftUI
import WidgetKit

@main
struct DiskDoomApp: App {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var state = AppState()
    @StateObject private var recommendationsEngine = RecommendationsEngine()
    @StateObject private var litterEngine = LitterScoreEngine()
    @StateObject private var forecastEngine = DiskForecastEngine()
    @StateObject private var simulator = WhatIfSimulator()
    @StateObject private var devCacheEngine = DevCacheEngine()
    @StateObject private var healthEngine = DiskHealthEngine()
    @StateObject private var budgetEngine = SpaceBudgetEngine()
    @StateObject private var feedMonitor = FileFeedMonitor()
    @StateObject private var lifecycleEngine = AppLifecycleEngine()
    @StateObject private var provenanceEngine = FileProvenanceEngine()
    @StateObject private var compressionEngine = SmartCompressionEngine()
    @StateObject private var containerScanner = ContainerScanner()
    @StateObject private var privacyEngine = PrivacyScannerEngine()
    @StateObject private var photoAnalyzer = PhotoLibraryAnalyzer()
    @StateObject private var topology = DiskTopologyService()
    @StateObject private var coordinator = LaunchCoordinator()
    @StateObject private var overlays = OverlayStack()
    @StateObject private var inventory = AppInventoryService()
    @StateObject private var menuBarMonitor = MenuBarMonitor()
    @StateObject private var devWorkspaceScanner = DeveloperWorkspaceScanner()
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup(id: "main") {
            ZStack {
                ContentView()
                    .environmentObject(state)
                    .environmentObject(litterEngine)
                    .environmentObject(forecastEngine)
                    .environmentObject(simulator)
                    .environmentObject(devCacheEngine)
                    .environmentObject(healthEngine)
                    .environmentObject(budgetEngine)
                    .environmentObject(feedMonitor)
                    .environmentObject(lifecycleEngine)
                    .environmentObject(provenanceEngine)
                    .environmentObject(compressionEngine)
                    .environmentObject(containerScanner)
                    .environmentObject(privacyEngine)
                    .environmentObject(photoAnalyzer)
                    .environmentObject(recommendationsEngine)
                    .environmentObject(state.permissions)
                    .environmentObject(state.notifications)
                    .environmentObject(state.license)
                    .environmentObject(state.dupFinder)
                    .environmentObject(state.similarFinder)
                    .environmentObject(state.photoDuplicates)
                    .environmentObject(state.duplicateMonitor)
                    .environmentObject(state.ignoreRules)
                    .environmentObject(state.priorities)
                    .environmentObject(state.gamification)
                .environmentObject(topology)
                .environmentObject(coordinator)
                .environmentObject(overlays)
                .environmentObject(inventory)
                .environmentObject(menuBarMonitor)
                .environmentObject(devWorkspaceScanner)
                    .task {
                        // Window is already visible here — jobs hydrate progressively.
                        LaunchJobs.registerAll(
                            on: coordinator, state: state,
                            litter: litterEngine, health: healthEngine,
                            forecast: forecastEngine, lifecycle: lifecycleEngine,
                            devcaches: devCacheEngine, budgets: budgetEngine,
                            compression: compressionEngine, privacy: privacyEngine,
                            topology: topology, inventory: inventory,
                            devWorkspace: devWorkspaceScanner)
                        await coordinator.runAll()
                    }
                    .task {
                        // Gamification runs from the scene, not from the main
                        // window, so onboarding and the menu bar cannot starve
                        // the daily check-in or quest rollover.
                        state.gamification.start()
                        state.gamification.checkIn()
                        // Menu bar monitor: live free space + threshold alerts.
                        menuBarMonitor.startMonitoring(notifications: state.notifications)
                        state.duplicateMonitor.start()
                        // Weekly digest: keep the schedule in sync with the setting.
                        // NOTE: must be the shared instance — constructing a
                        // throwaway NotificationService re-points (and then
                        // drops) the UNUserNotificationCenter delegate.
                        if UserDefaults.standard.object(forKey: "weeklyDigestEnabled") as? Bool == true {
                            NotificationService.shared.scheduleWeeklyDigest()
                        }
                    }
                    .onReceive(state.$scanRoot) { root in
                        // Scan finished (or cached scan restored) → refresh
                        // menu bar space hogs + score badges, and record a
                        // usage snapshot (with category breakdown) for the
                        // forecast history.
                        guard root != nil else { return }
                        // WHY: `$scanRoot` publishes in the MIDDLE of AppState's
                        // assignment — `records`/`lastScanDate` are set on the
                        // following lines of a fresh scan, and after `scanRoot`
                        // for a launch-time cache restore. Reading them here
                        // stamped the menu bar with the wrong date (a week-old
                        // cached tree got "· 2 minutes ago"). Defer one turn so
                        // the real scan date is visible to every reader below.
                        Task { @MainActor in
                            menuBarMonitor.updateFromScan(
                                records: state.records,
                                apps: inventory.apps,
                                litterScore: litterEngine.entries.isEmpty ? nil : litterEngine.averageScore,
                                healthGrade: healthEngine.score?.grade,
                                scanDate: state.lastScanDate)
                            // Forecast: category breakdown from the fresh records.
                            var breakdown: [String: Int64] = [:]
                            // A partial folder/index or old hydrated scan is not
                            // a current, whole-volume category measurement.
                            if let root = state.scanRoot, root.path == "/", !root.isPartial,
                               state.skippedPaths.isEmpty, state.records.count >= root.fileCount,
                               let date = state.lastScanDate,
                               (0...60).contains(Date().timeIntervalSince(date)) {
                                for record in state.records where !record.isDirectory {
                                    let previous = breakdown[record.category.rawValue, default: 0]
                                    let sum = previous.addingReportingOverflow(max(0, record.bytes))
                                    breakdown[record.category.rawValue] = sum.overflow ? Int64.max : sum.partialValue
                                }
                            }
                            if let capacity = StorageCapacityReader.read().availableValue {
                                forecastEngine.recordSnapshot(
                                    totalCapacity: capacity.totalBytes, usedSize: capacity.usedBytes, freeSize: capacity.freeBytes,
                                    categoryBreakdown: breakdown, source: .scan)
                                Task { await forecastEngine.compute() }
                            }
                            // Desktop widget: refresh the shared snapshot.
                            WidgetDataBridge.write(
                                healthGrade: healthEngine.score?.grade,
                                lastScanDate: state.lastScanDate,
                                daysUntilFull: forecastEngine.forecast?.daysUntilFull,
                                topHogs: menuBarMonitor.topSpaceHogs.map { ($0.name, $0.size) })
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                    .onReceive(state.dupFinder.$sets) { sets in
                        // Duplicate results landed → publish the index the
                        // Quick Look extension reads (path → copy count).
                        WidgetDataBridge.writeDuplicateIndex(sets: sets)
                    }
                    .onReceive(inventory.$apps) { apps in
                        // Inventory finished (also runs at launch) → refresh
                        // app space hogs even before any scan.
                        guard !apps.isEmpty else { return }
                        menuBarMonitor.updateFromScan(
                            records: state.records,
                            apps: apps,
                            litterScore: litterEngine.entries.isEmpty ? nil : litterEngine.averageScore,
                            healthGrade: healthEngine.score?.grade,
                            // Real scan timestamp (nil until one has run) — never `Date()`.
                            scanDate: state.lastScanDate)
                    }
                if showSplash {
                    SplashScreen { showSplash = false }
                        .transition(.opacity)
                }
            }
        }
        .defaultSize(width: 1100, height: 700)
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            state.gamification.refresh()
            state.gamification.checkIn()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DiskDoom") { openWindow(id: "about") }
            }
            // §37 menu bar structure (prototype subset).
            CommandGroup(replacing: .newItem) {
                Button("New Scan") { state.startScan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Save Snapshot") {
                    state.saveSnapshotFromCurrentScan(label: "Manual")
                    state.sidebarTab = .snapshots
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state.scanRoot == nil)
            }
            CommandMenu("Edit") {
                Button("Copy Path") {
                    if let node = state.selectedNode {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(node.path, forType: .string)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(state.selectedNode == nil)
            }
            CommandMenu("View") {
                Button(state.inspectorVisible ? "Hide Inspector" : "Show Inspector") {
                    state.inspectorVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Open Cleanup Queue") { state.showCleanup = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                // First 8 viz modes: ⌥⌘1–8. (Views 9–12 have no shortcut:
                // KeyEquivalent traps on multi-char strings like "10".)
                ForEach(Array(AppState.ExploreView.allCases.prefix(8).enumerated()), id: \.element) { index, view in
                    Button("Show \(view.title)") {
                        state.sidebarTab = .explore
                        state.exploreView = view
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                }
                ForEach(AppState.ExploreView.allCases.dropFirst(8), id: \.self) { view in
                    Button("Show \(view.title)") {
                        state.sidebarTab = .explore
                        state.exploreView = view
                    }
                }
            }
            CommandMenu("Go") {
                Button("Explore") { state.sidebarTab = .explore }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Duplicates") { state.sidebarTab = .duplicates }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Similar Files") { state.sidebarTab = .similar }
                Button("Duplicate Monitor") { state.sidebarTab = .dupMonitor }
                Button("Progress") { state.sidebarTab = .progress }
                Button("Applications") { state.sidebarTab = .applications }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Monitor") { state.sidebarTab = .monitor }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Snapshots") { state.sidebarTab = .snapshots }
                    .keyboardShortcut("5", modifiers: .command)
                Divider()
                Button("Litter Score") { state.sidebarTab = .litterScore }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Forecast") { state.sidebarTab = .forecast }
                    .keyboardShortcut("7", modifiers: .command)
                Button("What If?") { state.sidebarTab = .simulator }
                    .keyboardShortcut("8", modifiers: .command)
                Button("Dev Caches") { state.sidebarTab = .devCaches }
                    .keyboardShortcut("9", modifiers: .command)
                Button("Health") { state.sidebarTab = .health }
                Button("Budgets") { state.sidebarTab = .budgets }
                Button("Live Feed") { state.sidebarTab = .liveFeed }
                Divider()
                Button("Lifecycle") { state.sidebarTab = .lifecycle }
                Button("Provenance") { state.sidebarTab = .provenance }
                Button("Compression") { state.sidebarTab = .compression }
                Button("Containers") { state.sidebarTab = .containers }
                Button("Privacy") { state.sidebarTab = .privacy }
                Button("Photos") { state.sidebarTab = .photos }
                Button("Smart Clean") { state.sidebarTab = .smartClean }
                Button("Storage") { state.sidebarTab = .storage }
                Button("Folders") { state.sidebarTab = .folders }
            }
        }

        Window("About DiskDoom", id: "about") {
            AboutView()
                .background(Color(red: 0.06, green: 0.06, blue: 0.1))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 360, height: 520)

        Settings {
            // NOTE: the Settings scene does NOT inherit the WindowGroup
            // environment, so every object SettingsView needs must be
            // injected here explicitly. Missing these crashed the app on ⌘,.
            SettingsView()
                .environmentObject(state)
                .environmentObject(state.permissions)
                .environmentObject(state.license)
                .environmentObject(state.ignoreRules)
                .environmentObject(state.priorities)
                .environmentObject(state.gamification)
                .environmentObject(menuBarMonitor)
        }

        // ── Feature 6: Menu Bar Widget (always-visible free space) ──
        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarExtraPanel()
                .environmentObject(menuBarMonitor)
                .environmentObject(state)
                .environmentObject(forecastEngine)
                .environmentObject(inventory)
                .environmentObject(litterEngine)
                .environmentObject(healthEngine)
                .environmentObject(state.gamification)
        } label: {
            MenuBarLabel(monitor: menuBarMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The always-visible menu bar item: icon + compact free-space text,
/// colored by current disk state.
private struct MenuBarLabel: View {
    @ObservedObject var monitor: MenuBarMonitor
    @AppStorage("menuBarStyle") private var style = "iconAndText"

    var body: some View {
        switch style {
        case "textOnly":
            text
        case "compact":
            text
                .foregroundStyle(.secondary)
        case "iconAndText":
            HStack(spacing: 3) {
                Image(systemName: monitor.spaceState.icon)
                    .foregroundStyle(monitor.spaceState.color)
                    .font(.system(size: 11))
                text
            }
        default: // iconOnly
            Image(systemName: monitor.spaceState.icon)
                .foregroundStyle(monitor.spaceState.color)
                .font(.system(size: 13))
        }
    }

    private var text: some View {
        Text(monitor.menuBarTitle)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
    }
}
