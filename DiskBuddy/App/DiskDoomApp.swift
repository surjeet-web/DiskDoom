import SwiftUI

@main
struct DiskDoomApp: App {
    @Environment(\.openWindow) private var openWindow

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
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
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
                .environmentObject(topology)
                .environmentObject(coordinator)
                .environmentObject(overlays)
                    .task {
                        // Window is already visible here — jobs hydrate progressively.
                        LaunchJobs.registerAll(
                            on: coordinator, state: state,
                            litter: litterEngine, health: healthEngine,
                            forecast: forecastEngine, lifecycle: lifecycleEngine,
                            devcaches: devCacheEngine, budgets: budgetEngine,
                            compression: compressionEngine, privacy: privacyEngine,
                            topology: topology)
                        await coordinator.runAll()
                    }
                if showSplash {
                    SplashScreen { showSplash = false }
                        .transition(.opacity)
                }
            }
        }
        .defaultSize(width: 1100, height: 700)
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
            SettingsView()
        }
    }
}
