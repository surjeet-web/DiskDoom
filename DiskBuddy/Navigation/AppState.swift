import SwiftUI

// MARK: - Prototype app state (mock scan engine + navigation for all 37 spec sections)

final class AppState: ObservableObject {
    enum OnboardingStep { case welcome, fullDiskAccess, scanTarget }
    enum SidebarTab: String, CaseIterable {
        case explore, duplicates, applications, monitor, snapshots
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .explore: return "magnifyingglass"
            case .duplicates: return "doc.on.doc"
            case .applications: return "app.badge"
            case .monitor: return "chart.line.uptrend.xyaxis"
            case .snapshots: return "camera"
            }
        }
    }

    enum ExploreView: String, CaseIterable {
        case treemap, sunburst, flame, bubbles, mindMap, topSizes, ageMap, folderGrid
        var title: String {
            switch self {
            case .treemap: return "Treemap"
            case .sunburst: return "Sunburst"
            case .flame: return "Flame"
            case .bubbles: return "Bubbles"
            case .mindMap: return "MindMap"
            case .topSizes: return "Sizes"
            case .ageMap: return "Age"
            case .folderGrid: return "Grid"
            }
        }

        var symbol: String {
            switch self {
            case .treemap: return "square.grid.3x3.fill"
            case .sunburst: return "sun.max.fill"
            case .flame: return "flame.fill"
            case .bubbles: return "circle.dashed"
            case .mindMap: return "brain"
            case .topSizes: return "list.number"
            case .ageMap: return "calendar"
            case .folderGrid: return "square.grid.2x2.fill"
            }
        }
    }

    enum ScanPhase { case idle, scanning, done, failed }

    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let actionTitle: String
        static func == (l: Banner, r: Banner) -> Bool { l.id == r.id }
    }

    @Published var onboardingStep: OnboardingStep? = .welcome
    @Published var scanPhase: ScanPhase = .idle
    @Published var scanProgress: Double = 0
    @Published var scanPath: String = ""
    @Published var scanFiles: Int = 0
    @Published var scanTargetName = "Full Mac"
    @Published var limitedMode = false
    @Published var sidebarTab: SidebarTab = .explore
    @Published var exploreView: ExploreView = .treemap
    @Published var selectedNode: ScanNode? = nil
    @Published var inspectorVisible = true
    @Published var searchText = ""
    @Published var banner: Banner? = nil

    // Sheets / panels
    @Published var showCleanup = false
    @Published var showDeleteConfirm = false
    @Published var uninstallApp: AppEntry? = nil
    @Published var quickLookNode: ScanNode? = nil
    @Published var showLicense = false
    @Published var licenseActive = false

    // Data
    @Published var cleanupItems: [CleanupItem] = []
    @Published var duplicateKeeps: [UUID: UUID] = [:]
    @Published var snapshots: [Snapshot] = MockSnapshots.initial
    @Published var compareIDs: [UUID] = []
    @Published var failedCleanupIDs: Set<UUID> = []
    @Published var cleanupRequiresRetry = false
    @Published var freedBytes: Int64 = 0

    var cleanupTotal: Int64 { cleanupItems.reduce(0) { $0 + $1.bytes } }

    func finishOnboarding() { onboardingStep = nil }

    // MARK: Mock scan (§04)

    private var timer: Timer?

    func startScan(target: String? = nil) {
        if let target { scanTargetName = target }
        scanPhase = .scanning
        scanProgress = 0
        scanFiles = 0
        let paths = [
            "/System/Library/Extensions",
            "/Applications/Google Chrome.app",
            "/Users/you/Library/Caches",
            "/Users/you/Library/Application Support",
            "/Library/Logs",
            "/Users/you/Downloads",
        ]
        var tick = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            DispatchQueue.main.async {
                tick += 1
                self.scanProgress = min(1, self.scanProgress + 0.02)
                self.scanFiles = Int(Double(MockScanData.totalFiles) * self.scanProgress)
                self.scanPath = "Scanning \(paths[tick % paths.count])"
                if self.scanProgress >= 1 {
                    t.invalidate()
                    // Prototype rule to demo §31B: external targets fail.
                    if self.scanTargetName.hasPrefix("/Volumes") {
                        self.scanPhase = .failed
                    } else {
                        self.scanPhase = .done
                        self.selectedNode = MockScanData.topLevel.first
                        self.banner = Banner(message: "Scan complete · 1,892,341 files · 256 GB · 9.2s", actionTitle: "View Results")
                    }
                }
            }
        }
    }

    func cancelScan() {
        timer?.invalidate()
        scanPhase = scanProgress > 0.3 ? .done : .idle
    }

    // MARK: Cleanup queue (§22/§23/§31C/§34B)

    func stage(source: String, path: String, bytes: Int64) {
        guard !cleanupItems.contains(where: { $0.path == path }) else { return }
        cleanupItems.append(CleanupItem(source: source, path: path, bytes: bytes))
    }

    func executeCleanup() {
        // First execution demos §31C partial failure; retry succeeds.
        if cleanupRequiresRetry == false && cleanupItems.count >= 3 {
            failedCleanupIDs = Set(cleanupItems.prefix(3).map(\.id))
            cleanupRequiresRetry = true
            return
        }
        let okItems = cleanupItems.filter { !failedCleanupIDs.contains($0.id) }
        freedBytes += okItems.reduce(0) { $0 + $1.bytes }
        cleanupItems.removeAll()
        failedCleanupIDs.removeAll()
        cleanupRequiresRetry = false
        showDeleteConfirm = false
        showCleanup = false
        banner = Banner(message: "Moved items to Trash · \(freedBytes.fileSizeString) freed", actionTitle: "Show Trash")
    }

    func dismissBannerAfterDelay() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            banner = nil
        }
    }
}
