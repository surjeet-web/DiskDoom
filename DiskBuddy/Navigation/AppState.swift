import SwiftUI

// MARK: - Prototype app state (mock scan engine + navigation for all 37 spec sections)

@MainActor
final class AppState: ObservableObject {
    enum OnboardingStep { case welcome, fullDiskAccess, scanTarget }
    enum SidebarTab: String, CaseIterable {
        case explore, duplicates, applications, monitor, snapshots
        case litterScore, forecast, simulator, devCaches, health, budgets, liveFeed
        case lifecycle, provenance, compression, containers, privacy, photos
        var title: String {
            switch self {
            case .explore: return "Explore"
            case .duplicates: return "Duplicates"
            case .applications: return "Applications"
            case .monitor: return "Monitor"
            case .snapshots: return "Snapshots"
            case .litterScore: return "Litter Score"
            case .forecast: return "Forecast"
            case .simulator: return "What If?"
            case .devCaches: return "Dev Caches"
            case .health: return "Health"
            case .budgets: return "Budgets"
            case .liveFeed: return "Live Feed"
            case .lifecycle: return "Lifecycle"
            case .provenance: return "Provenance"
            case .compression: return "Compression"
            case .containers: return "Containers"
            case .privacy: return "Privacy"
            case .photos: return "Photos"
            }
        }

        var symbol: String {
            switch self {
            case .explore: return "magnifyingglass"
            case .duplicates: return "doc.on.doc"
            case .applications: return "app.badge"
            case .monitor: return "chart.line.uptrend.xyaxis"
            case .snapshots: return "camera"
            case .litterScore: return "gauge.with.dots.needle.67percent"
            case .forecast: return "chart.line.uptrend.xyaxis"
            case .simulator: return "arrow.triangle.2.circlepath"
            case .devCaches: return "hammer.fill"
            case .health: return "heart.text.square"
            case .budgets: return "gauge.with.dots.needle.33percent"
            case .liveFeed: return "antenna.radiowaves.left.and.right"
            case .lifecycle: return "clock.arrow.circlepath"
            case .provenance: return "magnifyingglass.circle"
            case .compression: return "archivebox.fill"
            case .containers: return "square.grid.3x3.fill.square"
            case .privacy: return "lock.shield.fill"
            case .photos: return "photo.on.rectangle.angled"
            }
        }

        /// Tabs shown in the main Navigate section (spec §37: ⌘1–⌘5).
        static var primary: [SidebarTab] {
            [.explore, .duplicates, .applications, .monitor, .snapshots]
        }

        /// Differentiation tabs (D1–D13), no global shortcuts to avoid clashes.
        static var insights: [SidebarTab] {
            [.litterScore, .forecast, .simulator, .devCaches, .health, .budgets, .liveFeed,
             .lifecycle, .provenance, .compression, .containers, .privacy, .photos]
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
        scanTickCount = 0
        timer?.invalidate()
        // Timer fires on the main runloop; hop into a @MainActor task so no
        // non-Sendable state crosses into the @Sendable timer closure.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.scanTick() }
        }
    }

    private var scanTickCount = 0

    private func scanTick() {
        scanTickCount += 1
        scanProgress = min(1, scanProgress + 0.02)
        scanFiles = Int(Double(MockScanData.totalFiles) * scanProgress)
        scanPath = "Scanning \(scanPaths[scanTickCount % scanPaths.count])"
        if scanProgress >= 1 {
            timer?.invalidate()
            // Prototype rule to demo §31B: external targets fail.
            if scanTargetName.hasPrefix("/Volumes") {
                scanPhase = .failed
            } else {
                scanPhase = .done
                selectedNode = MockScanData.topLevel.first
                banner = Banner(message: "Scan complete · 1,892,341 files · 256 GB · 9.2s", actionTitle: "View Results")
            }
        }
    }

    private let scanPaths = [
        "/System/Library/Extensions",
        "/Applications/Google Chrome.app",
        "/Users/you/Library/Caches",
        "/Users/you/Library/Application Support",
        "/Library/Logs",
        "/Users/you/Downloads",
    ]

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
