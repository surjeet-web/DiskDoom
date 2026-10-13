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
        topology: DiskTopologyService,
        inventory: AppInventoryService,
        devWorkspace: DeveloperWorkspaceScanner
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
        coordinator.registerBackground(name: "Scan app inventory") {
            await inventory.scan()
        }
        coordinator.registerBackground(name: "Precompute litter scores") {
            await MainActor.run { litter.compute(apps: inventory.apps, launchDays: lifecycle.trackedDaysSinceLaunch) }
        }
        coordinator.registerBackground(name: "Precompute health score") {
            // Records stream in asynchronously from restoreCachedScan, so this
            // may see an empty index. DiskHealthEngine now refuses to score
            // below a minimum record count rather than inventing a grade, and
            // DiskHealthView recomputes when records land.
            await MainActor.run { health.compute(records: state.records, apps: inventory.apps) }
        }
        coordinator.registerBackground(name: "Record usage snapshot") {
            // Forecast history: one capacity measurement per launch.
            if let capacity = StorageCapacityReader.read().availableValue {
                await MainActor.run {
                    forecast.recordSnapshot(
                        totalCapacity: capacity.totalBytes, usedSize: capacity.usedBytes, freeSize: capacity.freeBytes,
                        source: .launch)
                }
            }
            await forecast.compute()
        }
        coordinator.registerBackground(name: "Track app lifecycle") {
            await MainActor.run {
                lifecycle.compute(apps: inventory.apps)
                lifecycle.startLaunchWatcher()
            }
        }
        coordinator.registerBackground(name: "Scan dev caches") {
            await MainActor.run { devcaches.scan() }
        }
        coordinator.registerBackground(name: "Scan developer workspaces") {
            await MainActor.run { devWorkspace.scan() }
        }
        coordinator.registerBackground(name: "Evaluate budgets") {
            await MainActor.run { budgets.evaluate(records: state.records) }
        }
        coordinator.registerBackground(name: "Analyze compression") {
            await MainActor.run { compression.analyze(records: state.records) }
        }
        coordinator.registerBackground(name: "Scan privacy") {
            await MainActor.run { privacy.scan() }
        }
        coordinator.registerBackground(name: "Load storage topology") {
            await topology.loadTopology()
            await topology.loadCapacity()
            await topology.startCapacityMonitoring()
        }
    }
}
