import Foundation

// MARK: - Launch job registration, adapted to this codebase's engines
//
// Foreground = fast + main-confined (license, permissions, persisted index).
// Background = self-backgrounding engines, 2 at a time. No duplicate walks:
// analysis jobs consume the in-memory scan or run once; pruning reuses the
// retention logic already in ScanStore.

enum LaunchJobs {
    @MainActor
    static func registerAll(
        on coordinator: LaunchCoordinator,
        state: AppState,
        litter: LitterScoreEngine,
        health: DiskHealthEngine,
        forecast: DiskForecastEngine,
        lifecycle: AppLifecycleEngine,
        devcaches: DevCacheEngine,
        budgets: SpaceBudgetEngine,
        compression: SmartCompressionEngine,
        privacy: PrivacyScannerEngine,
        topology: DiskTopologyService
    ) {
        // ── Foreground: hydrate before first meaningful paint ──
        coordinator.registerForeground(name: "Refresh license state") {
            state.license.refresh()
        }
        coordinator.registerForeground(name: "Check permissions") {
            state.permissions.checkAll()
        }
        coordinator.registerForeground(name: "Reload snapshot index") {
            state.snapshots = ScanStore.loadSnapshots(retention: state.snapshotRetention)
        }
        coordinator.registerForeground(name: "Restore cached scan") {
            await state.restoreCachedScan()
        }
        coordinator.registerForeground(name: "Verify cache freshness", priority: .high) {
            if let last = state.lastScanDate, Date().timeIntervalSince(last) > 86_400 {
                coordinator.markCacheStale()
            } else if state.scanRoot == nil {
                coordinator.markCacheStale()
            }
        }

        // ── Background: precompute + probe (bounded to 2 workers) ──
        coordinator.registerBackground(name: "Precompute litter scores") {
            await MainActor.run { litter.compute() }
        }
        coordinator.registerBackground(name: "Precompute health score") {
            await MainActor.run { health.compute() }
        }
        coordinator.registerBackground(name: "Precompute forecast") {
            await MainActor.run { forecast.compute() }
        }
        coordinator.registerBackground(name: "Track app lifecycle") {
            await MainActor.run {
                lifecycle.compute()
                lifecycle.startLaunchWatcher()
            }
        }
        coordinator.registerBackground(name: "Scan dev caches") {
            await MainActor.run { devcaches.scan() }
        }
        coordinator.registerBackground(name: "Evaluate budgets") {
            await MainActor.run { budgets.evaluate() }
        }
        coordinator.registerBackground(name: "Analyze compression") {
            await MainActor.run { compression.analyze() }
        }
        coordinator.registerBackground(name: "Scan privacy") {
            await MainActor.run { privacy.scan() }
        }
        coordinator.registerBackground(name: "Load storage topology") {
            await topology.loadTopology()
            await topology.loadCapacity()
        }
    }
}
