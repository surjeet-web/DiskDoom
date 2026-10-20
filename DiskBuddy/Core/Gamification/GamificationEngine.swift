import Foundation
import Combine

// MARK: - Gamification: XP, levels, streaks, quests, achievements
//
// Local, offline progression for real cleanup work. Every value is derived
// from actions the app actually performed (scans, bytes reclaimed, items
// removed). Nothing is randomized into the numbers, and all state persists
// to a single JSON profile.

enum GameEventKind: String, Codable, Sendable {
    case scan
    case cleanup
    case duplicateCleanup
    case similarCleanup
    case photoCleanup

    var title: String {
        switch self {
        case .scan: return "Scan complete"
        case .cleanup: return "Cleanup complete"
        case .duplicateCleanup: return "Duplicates removed"
        case .similarCleanup: return "Similar photos removed"
        case .photoCleanup: return "Photos cleaned"
        }
    }

    var symbol: String {
        switch self {
        case .scan: return "magnifyingglass"
        case .cleanup: return "trash.fill"
        case .duplicateCleanup: return "doc.on.doc.fill"
        case .similarCleanup: return "photo.on.rectangle.angled"
        case .photoCleanup: return "photo.stack.fill"
        }
    }
}

struct GameEvent: Sendable {
    var kind: GameEventKind
    var bytes: Int64 = 0
    var items: Int = 0
    var filesScanned: Int = 0

    init(kind: GameEventKind, bytes: Int64 = 0, items: Int = 0, filesScanned: Int = 0) {
        self.kind = kind
        self.bytes = max(0, bytes)
        self.items = max(0, items)
        self.filesScanned = max(0, filesScanned)
    }
}

struct GameAchievement: Identifiable, Sendable {
    enum Metric: String, Sendable {
        case bytes, items, scans, duplicateItems, similarItems, photoItems, streak, level
    }
    enum Tier: String, Sendable {
        case bronze, silver, gold, platinum
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let metric: Metric
    let target: Int64
    let rewardXP: Int
    let tier: Tier
}

enum QuestMetric: String, Codable, Sendable {
    case scans, bytes, items, duplicateItems, photoItems, checkIns
}

enum QuestPeriod: String, Codable, Sendable {
    case daily, weekly
}

struct GameQuest: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let metric: QuestMetric
    let target: Int64
    var progress: Int64
    let rewardXP: Int
    let period: QuestPeriod
    var claimed: Bool
    let expiresAt: Date

    var fraction: Double {
        guard target > 0 else { return 1 }
        return min(1, Double(progress) / Double(target))
    }
    var isComplete: Bool { progress >= target }
}

struct GameActivity: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String
    let xp: Int
    let symbol: String
}

struct GameProfile: Codable, Sendable {
    var xp: Int = 0
    var level: Int = 1
    var streak: Int = 0
    var bestStreak: Int = 0
    var lastActiveDay: Date?
    /// Optional so profiles written before the streak calendar still decode.
    var activeDays: [String]?
    var questAnchorDay: Date?
    var questAnchorWeek: Date?
    var totalBytes: Int64 = 0
    var totalItems: Int = 0
    var totalScans: Int = 0
    var totalDuplicateItems: Int = 0
    var totalSimilarItems: Int = 0
    var totalPhotoItems: Int = 0
    var unlocked: [String: Date] = [:]
    var quests: [GameQuest] = []
    var recent: [GameActivity] = []
}

struct GameCelebration: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    let isLevelUp: Bool
}

struct GameReward: Identifiable, Equatable {
    let id = UUID()
    let amount: Int
    let reason: String
}

@MainActor
final class GamificationEngine: ObservableObject {
    @Published private(set) var profile: GameProfile
    @Published private(set) var celebrationQueue: [GameCelebration] = []
    @Published private(set) var rewardQueue: [GameReward] = []

    var currentCelebration: GameCelebration? { celebrationQueue.first }
    var currentReward: GameReward? { rewardQueue.first }

    private let fileURL: URL
    private let nowProvider: () -> Date
    private var rolloverTimer: Timer?

    private static let maxQueuedCelebrations = 8
    private static let maxQueuedRewards = 8

    init(fileURL: URL? = nil, nowProvider: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.nowProvider = nowProvider
        self.profile = Self.load(from: self.fileURL)
        refreshQuestsIfNeeded(now: nowProvider())
        if profile.level != Self.level(forXP: profile.xp) {
            profile.level = Self.level(forXP: profile.xp)
        }
        save()
    }

    // MARK: Lifecycle + queues

    /// Keeps daily/weekly quests and the streak calendar fresh while the app
    /// stays open. Safe to call repeatedly.
    func start() {
        stop()
        refresh(now: nowProvider())
        rolloverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        rolloverTimer?.tolerance = 15
    }

    func stop() {
        rolloverTimer?.invalidate()
        rolloverTimer = nil
    }

    private func tick() {
        let changed = refresh(now: nowProvider())
        if changed {
            NSLog("DiskDoom gamification: quests rolled over")
        }
    }

    /// Rebuilds daily/weekly quests when the calendar day or week changed.
    /// Returns true when the quest set changed.
    @discardableResult
    func refresh(now: Date = Date()) -> Bool {
        let previousIDs = profile.quests.map(\.id)
        refreshQuestsIfNeeded(now: now)
        let changed = profile.quests.map(\.id) != previousIDs
        if changed { save() }
        return changed
    }

    func dismissCurrentCelebration() {
        guard !celebrationQueue.isEmpty else { return }
        celebrationQueue.removeFirst()
    }

    func dismissCurrentReward() {
        guard !rewardQueue.isEmpty else { return }
        rewardQueue.removeFirst()
    }

    private func enqueueCelebration(_ celebration: GameCelebration) {
        if let last = celebrationQueue.last,
           last.title == celebration.title, last.detail == celebration.detail {
            return
        }
        celebrationQueue.append(celebration)
        if celebrationQueue.count > Self.maxQueuedCelebrations {
            celebrationQueue.removeFirst(celebrationQueue.count - Self.maxQueuedCelebrations)
        }
    }

    private func enqueueReward(_ reward: GameReward) {
        rewardQueue.append(reward)
        if rewardQueue.count > Self.maxQueuedRewards {
            rewardQueue.removeFirst(rewardQueue.count - Self.maxQueuedRewards)
        }
    }

    // MARK: Level math

    static func xpThreshold(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        let n = level - 1
        return 100 * n + 25 * n * (n - 1) / 2
    }

    static func level(forXP xp: Int) -> Int {
        var level = 1
        while level < 100, xp >= xpThreshold(forLevel: level + 1) {
            level += 1
        }
        return level
    }

    var level: Int { profile.level }
    var xp: Int { profile.xp }
    var xpIntoLevel: Int { max(0, profile.xp - Self.xpThreshold(forLevel: profile.level)) }
    var xpForNextLevel: Int {
        max(1, Self.xpThreshold(forLevel: profile.level + 1) - Self.xpThreshold(forLevel: profile.level))
    }
    var progressToNextLevel: Double {
        min(1, Double(xpIntoLevel) / Double(xpForNextLevel))
    }
    var xpToNextLevel: Int { max(0, xpForNextLevel - xpIntoLevel) }

    var title: String {
        switch profile.level {
        case 1...2: return "Storage Sprout"
        case 3...4: return "Byte Buddy"
        case 5...7: return "Disk Defender"
        case 8...10: return "Space Saver"
        case 11...15: return "Cache Crusher"
        case 16...20: return "Terabyte Tamer"
        case 21...30: return "Storage Sage"
        default: return "Disk Legend"
        }
    }

    var streak: Int { profile.streak }
    var bestStreak: Int { profile.bestStreak }
    var dailyQuests: [GameQuest] { profile.quests.filter { $0.period == .daily } }
    var weeklyQuests: [GameQuest] { profile.quests.filter { $0.period == .weekly } }
    var activities: [GameActivity] { profile.recent }
    var unlockedCount: Int { profile.unlocked.count }
    var recentActiveDays: [String] { profile.activeDays ?? [] }

    var hasCheckedInToday: Bool {
        guard let last = profile.lastActiveDay else { return false }
        return Calendar.current.isDate(last, inSameDayAs: nowProvider())
    }

    func isActive(on date: Date) -> Bool {
        recentActiveDays.contains(Self.dayKey(date))
    }

    nonisolated static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The locked achievement closest to completion — a concrete next goal.
    var nextAchievement: (achievement: GameAchievement, progress: Double)? {
        let locked = Self.achievements.filter { !isUnlocked($0) }
        guard let best = locked.max(by: { progress(for: $0) < progress(for: $1) }) else { return nil }
        return (best, progress(for: best))
    }

    /// Canonical rank ladder. Titles must match `title` exactly so the
    /// current-rank highlight and the hero card never disagree.
    static let ranks: [(title: String, minLevel: Int, symbol: String)] = [
        ("Storage Sprout", 1, "leaf.fill"),
        ("Byte Buddy", 3, "circle.grid.2x2.fill"),
        ("Disk Defender", 5, "shield.fill"),
        ("Space Saver", 8, "internaldrive.fill"),
        ("Cache Crusher", 11, "hammer.fill"),
        ("Terabyte Tamer", 16, "externaldrive.fill"),
        ("Storage Sage", 21, "brain"),
        ("Disk Legend", 31, "trophy.fill"),
    ]

    /// Current rank index for the ladder highlight.
    var currentRankIndex: Int {
        var result = 0
        for (index, rank) in Self.ranks.enumerated() where profile.level >= rank.minLevel {
            result = index
        }
        return result
    }

    // MARK: Achievements

    static let achievements: [GameAchievement] = [
        .init(id: "first-clean", title: "First Sweep", detail: "Remove your first item.",
              symbol: "sparkles", metric: .items, target: 1, rewardXP: 50, tier: .bronze),
        .init(id: "tidy-ten", title: "Tidy Ten", detail: "Remove 10 items.",
              symbol: "square.stack.3d.up.fill", metric: .items, target: 10, rewardXP: 75, tier: .bronze),
        .init(id: "century-clean", title: "Century Club", detail: "Remove 100 items.",
              symbol: "100.circle.fill", metric: .items, target: 100, rewardXP: 150, tier: .silver),
        .init(id: "deep-clean", title: "Deep Clean", detail: "Remove 1,000 items.",
              symbol: "wand.and.stars", metric: .items, target: 1_000, rewardXP: 400, tier: .gold),
        .init(id: "first-gig", title: "Gigabyte Slayer", detail: "Reclaim 1 GB.",
              symbol: "internaldrive.fill", metric: .bytes, target: 1_000_000_000, rewardXP: 75, tier: .bronze),
        .init(id: "ten-gig", title: "Ten Gig Club", detail: "Reclaim 10 GB.",
              symbol: "internaldrive.fill", metric: .bytes, target: 10_000_000_000, rewardXP: 150, tier: .silver),
        .init(id: "hundred-gig", title: "Hundred Gig Hero", detail: "Reclaim 100 GB.",
              symbol: "externaldrive.fill", metric: .bytes, target: 100_000_000_000, rewardXP: 400, tier: .gold),
        .init(id: "terabyte", title: "Terabyte Tamer", detail: "Reclaim 1 TB.",
              symbol: "server.rack", metric: .bytes, target: 1_000_000_000_000, rewardXP: 1_000, tier: .platinum),
        .init(id: "first-scan", title: "Eyes Open", detail: "Complete your first scan.",
              symbol: "magnifyingglass", metric: .scans, target: 1, rewardXP: 50, tier: .bronze),
        .init(id: "scan-25", title: "Scan Veteran", detail: "Complete 25 scans.",
              symbol: "binoculars.fill", metric: .scans, target: 25, rewardXP: 150, tier: .silver),
        .init(id: "scan-100", title: "Scan Legend", detail: "Complete 100 scans.",
              symbol: "scope", metric: .scans, target: 100, rewardXP: 400, tier: .gold),
        .init(id: "dupe-10", title: "Dupe Destroyer", detail: "Remove 10 duplicate files.",
              symbol: "doc.on.doc.fill", metric: .duplicateItems, target: 10, rewardXP: 75, tier: .bronze),
        .init(id: "dupe-100", title: "Dupe Dynamo", detail: "Remove 100 duplicate files.",
              symbol: "doc.on.doc.fill", metric: .duplicateItems, target: 100, rewardXP: 200, tier: .silver),
        .init(id: "dupe-1000", title: "Duplicate Demolition", detail: "Remove 1,000 duplicate files.",
              symbol: "rectangle.stack.badge.minus", metric: .duplicateItems, target: 1_000, rewardXP: 500, tier: .gold),
        .init(id: "similar-25", title: "Lookalike Hunter", detail: "Remove 25 similar photos.",
              symbol: "photo.on.rectangle.angled", metric: .similarItems, target: 25, rewardXP: 75, tier: .bronze),
        .init(id: "similar-250", title: "Curator", detail: "Remove 250 similar photos.",
              symbol: "photo.stack", metric: .similarItems, target: 250, rewardXP: 400, tier: .gold),
        .init(id: "photo-10", title: "Pixel Purger", detail: "Clean 10 Photos Library items.",
              symbol: "photo.stack.fill", metric: .photoItems, target: 10, rewardXP: 75, tier: .bronze),
        .init(id: "photo-100", title: "Album Architect", detail: "Clean 100 Photos Library items.",
              symbol: "photo.on.rectangle.angled", metric: .photoItems, target: 100, rewardXP: 200, tier: .silver),
        .init(id: "streak-3", title: "Streak Starter", detail: "Stay active for 3 days.",
              symbol: "flame.fill", metric: .streak, target: 3, rewardXP: 100, tier: .bronze),
        .init(id: "streak-7", title: "Week Warrior", detail: "Stay active for 7 days.",
              symbol: "flame.fill", metric: .streak, target: 7, rewardXP: 250, tier: .silver),
        .init(id: "streak-30", title: "Monthly Master", detail: "Stay active for 30 days.",
              symbol: "flame.circle.fill", metric: .streak, target: 30, rewardXP: 750, tier: .gold),
        .init(id: "level-5", title: "Rising Star", detail: "Reach level 5.",
              symbol: "star.fill", metric: .level, target: 5, rewardXP: 100, tier: .bronze),
        .init(id: "level-10", title: "Double Digits", detail: "Reach level 10.",
              symbol: "star.circle.fill", metric: .level, target: 10, rewardXP: 250, tier: .silver),
        .init(id: "level-25", title: "Elite Cleaner", detail: "Reach level 25.",
              symbol: "crown.fill", metric: .level, target: 25, rewardXP: 750, tier: .gold),
        .init(id: "level-50", title: "Disk Legend", detail: "Reach level 50.",
              symbol: "trophy.fill", metric: .level, target: 50, rewardXP: 2_000, tier: .platinum),
    ]

    func isUnlocked(_ achievement: GameAchievement) -> Bool {
        profile.unlocked[achievement.id] != nil
    }

    func unlockedDate(_ achievement: GameAchievement) -> Date? {
        profile.unlocked[achievement.id]
    }

    func progress(for achievement: GameAchievement) -> Double {
        guard achievement.target > 0 else { return 1 }
        return min(1, Double(currentValue(for: achievement.metric)) / Double(achievement.target))
    }

    func currentValue(for metric: GameAchievement.Metric) -> Int64 {
        switch metric {
        case .bytes: return profile.totalBytes
        case .items: return Int64(profile.totalItems)
        case .scans: return Int64(profile.totalScans)
        case .duplicateItems: return Int64(profile.totalDuplicateItems)
        case .similarItems: return Int64(profile.totalSimilarItems)
        case .photoItems: return Int64(profile.totalPhotoItems)
        case .streak: return Int64(profile.bestStreak)
        case .level: return Int64(profile.level)
        }
    }

    // MARK: Recording actions

    func record(_ event: GameEvent, now: Date = Date()) {
        refreshQuestsIfNeeded(now: now)
        let newDay = registerActiveDay(now)
        if newDay {
            award(10 + min(profile.streak * 2, 30),
                  reason: "Daily check-in",
                  detail: profile.streak > 1 ? "\(profile.streak)-day streak" : "First check-in",
                  symbol: "flame.fill", now: now)
            bumpQuests(metric: .checkIns, delta: 1)
        }

        switch event.kind {
        case .scan:
            profile.totalScans += 1
        case .cleanup:
            profile.totalItems += event.items
            profile.totalBytes = add(profile.totalBytes, event.bytes)
        case .duplicateCleanup:
            profile.totalItems += event.items
            profile.totalDuplicateItems += event.items
            profile.totalBytes = add(profile.totalBytes, event.bytes)
        case .similarCleanup:
            profile.totalItems += event.items
            profile.totalSimilarItems += event.items
            profile.totalBytes = add(profile.totalBytes, event.bytes)
        case .photoCleanup:
            profile.totalItems += event.items
            profile.totalPhotoItems += event.items
            profile.totalBytes = add(profile.totalBytes, event.bytes)
        }

        let xp = baseXP(for: event)
        if xp > 0 {
            award(xp, reason: event.kind.title, detail: detail(for: event),
                  symbol: event.kind.symbol, now: now)
        }
        bumpQuests(for: event)
        checkAchievements(now: now)
        save()
    }

    /// Called at launch so the streak and daily check-in advance even when the
    /// user only opens the app to browse.
    func checkIn(now: Date = Date()) {
        refreshQuestsIfNeeded(now: now)
        let newDay = registerActiveDay(now)
        if newDay {
            award(10 + min(profile.streak * 2, 30),
                  reason: "Daily check-in",
                  detail: profile.streak > 1 ? "\(profile.streak)-day streak" : "First check-in",
                  symbol: "flame.fill", now: now)
            bumpQuests(metric: .checkIns, delta: 1)
            checkAchievements(now: now)
        }
        save()
    }

    func claim(_ quest: GameQuest, now: Date = Date()) {
        guard let index = profile.quests.firstIndex(where: { $0.id == quest.id }),
              !profile.quests[index].claimed,
              profile.quests[index].isComplete else { return }
        profile.quests[index].claimed = true
        award(profile.quests[index].rewardXP,
              reason: "Quest complete",
              detail: profile.quests[index].title,
              symbol: "rosette", now: now)
        enqueueCelebration(GameCelebration(
            title: "Quest complete",
            detail: profile.quests[index].title,
            symbol: "rosette",
            isLevelUp: false))
        checkAchievements(now: now)
        save()
    }

    func resetProgress(now: Date = Date()) {
        profile = GameProfile()
        celebrationQueue.removeAll()
        rewardQueue.removeAll()
        refreshQuestsIfNeeded(now: now)
        save()
    }

    // MARK: Streak

    private func registerActiveDay(_ now: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        defer { profile.lastActiveDay = today }
        guard let last = profile.lastActiveDay else {
            profile.streak = 1
            profile.bestStreak = max(profile.bestStreak, 1)
            recordActiveDay(today)
            return true
        }
        let lastDay = calendar.startOfDay(for: last)
        if calendar.isDate(lastDay, inSameDayAs: today) { return false }
        let gap = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        profile.streak = gap == 1 ? profile.streak + 1 : 1
        profile.bestStreak = max(profile.bestStreak, profile.streak)
        recordActiveDay(today)
        return true
    }

    private func recordActiveDay(_ day: Date) {
        var days = profile.activeDays ?? []
        let key = Self.dayKey(day)
        if days.last != key { days.append(key) }
        if days.count > 60 { days.removeFirst(days.count - 60) }
        profile.activeDays = days
    }

    // MARK: Quests

    private struct QuestTemplate {
        let id: String
        let title: String
        let detail: String
        let metric: QuestMetric
        let target: Int64
        let reward: Int
    }

    private static let dailyTemplates: [QuestTemplate] = [
        .init(id: "scan-once", title: "Warm-Up Scan", detail: "Run a scan today.", metric: .scans, target: 1, reward: 25),
        .init(id: "scan-three", title: "Triple Check", detail: "Run 3 scans today.", metric: .scans, target: 3, reward: 60),
        .init(id: "half-gig", title: "Half-Gig Haul", detail: "Reclaim 500 MB.", metric: .bytes, target: 500_000_000, reward: 40),
        .init(id: "two-gig", title: "Two-Gig Tuesday", detail: "Reclaim 2 GB.", metric: .bytes, target: 2_000_000_000, reward: 70),
        .init(id: "tidy-ten", title: "Ten-Piece Tidy", detail: "Remove 10 items.", metric: .items, target: 10, reward: 35),
        .init(id: "tidy-twentyfive", title: "Quarter Century", detail: "Remove 25 items.", metric: .items, target: 25, reward: 60),
        .init(id: "dupe-five", title: "Duplicate Sweep", detail: "Remove 5 duplicates.", metric: .duplicateItems, target: 5, reward: 40),
        .init(id: "photo-ten", title: "Photo Purge", detail: "Clean 10 photos.", metric: .photoItems, target: 10, reward: 45),
    ]

    private static let weeklyTemplates: [QuestTemplate] = [
        .init(id: "weekly-scan", title: "Weekly Recon", detail: "Run 5 scans this week.", metric: .scans, target: 5, reward: 120),
        .init(id: "weekly-bytes", title: "Five-Gig Week", detail: "Reclaim 5 GB this week.", metric: .bytes, target: 5_000_000_000, reward: 200),
        .init(id: "weekly-items", title: "Century Clean", detail: "Remove 100 items this week.", metric: .items, target: 100, reward: 250),
        .init(id: "weekly-dupes", title: "Dupe Marathon", detail: "Remove 50 duplicates this week.", metric: .duplicateItems, target: 50, reward: 250),
        .init(id: "weekly-photos", title: "Photo Studio", detail: "Clean 50 photos this week.", metric: .photoItems, target: 50, reward: 300),
    ]

    private func refreshQuestsIfNeeded(now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        if profile.questAnchorDay == nil ||
            !calendar.isDate(profile.questAnchorDay!, inSameDayAs: today) {
            profile.quests.removeAll { $0.period == .daily }
            let seed = Int(today.timeIntervalSince1970 / 86_400)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            for index in 0..<3 {
                let template = Self.dailyTemplates[(seed + index * 3) % Self.dailyTemplates.count]
                profile.quests.append(GameQuest(
                    id: "daily-\(seed)-\(template.id)",
                    title: template.title, detail: template.detail,
                    metric: template.metric, target: template.target,
                    progress: 0, rewardXP: template.reward, period: .daily,
                    claimed: false, expiresAt: endOfDay))
            }
            profile.questAnchorDay = today
        }

        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            if profile.questAnchorWeek == nil || profile.questAnchorWeek! < week.start {
                profile.quests.removeAll { $0.period == .weekly }
                let seed = Int(week.start.timeIntervalSince1970 / 86_400)
                for index in 0..<2 {
                    let template = Self.weeklyTemplates[(seed + index * 2) % Self.weeklyTemplates.count]
                    profile.quests.append(GameQuest(
                        id: "weekly-\(seed)-\(template.id)",
                        title: template.title, detail: template.detail,
                        metric: template.metric, target: template.target,
                        progress: 0, rewardXP: template.reward, period: .weekly,
                        claimed: false, expiresAt: week.end))
                }
                profile.questAnchorWeek = week.start
            }
        }
    }

    private func bumpQuests(for event: GameEvent) {
        for index in profile.quests.indices where !profile.quests[index].claimed {
            let delta: Int64
            switch profile.quests[index].metric {
            case .scans: delta = event.kind == .scan ? 1 : 0
            case .bytes: delta = event.bytes
            case .items: delta = Int64(event.items)
            case .duplicateItems: delta = event.kind == .duplicateCleanup ? Int64(event.items) : 0
            case .photoItems: delta = event.kind == .photoCleanup ? Int64(event.items) : 0
            case .checkIns: delta = 0
            }
            guard delta > 0 else { continue }
            profile.quests[index].progress = min(profile.quests[index].target,
                                                profile.quests[index].progress + delta)
        }
    }

    private func bumpQuests(metric: QuestMetric, delta: Int64) {
        guard delta > 0 else { return }
        for index in profile.quests.indices where !profile.quests[index].claimed
            && profile.quests[index].metric == metric {
            profile.quests[index].progress = min(profile.quests[index].target,
                                                profile.quests[index].progress + delta)
        }
    }

    // MARK: XP + achievements

    private func baseXP(for event: GameEvent) -> Int {
        switch event.kind {
        case .scan:
            return 10 + min(15, event.filesScanned / 20_000)
        case .cleanup:
            return 20 + min(80, Int(event.bytes / 1_000_000_000) * 10) + min(20, event.items / 10)
        case .duplicateCleanup:
            return 15 + min(60, Int(event.bytes / 1_000_000_000) * 8) + min(20, event.items / 5)
        case .similarCleanup:
            return 15 + min(60, Int(event.bytes / 1_000_000_000) * 8) + min(20, event.items / 5)
        case .photoCleanup:
            return 20 + min(60, Int(event.bytes / 1_000_000_000) * 8) + min(20, event.items / 5)
        }
    }

    private func detail(for event: GameEvent) -> String {
        switch event.kind {
        case .scan:
            return event.filesScanned > 0 ? "\(event.filesScanned.formatted()) files mapped" : "Scan finished"
        case .cleanup, .duplicateCleanup, .similarCleanup, .photoCleanup:
            if event.items > 0 && event.bytes > 0 {
                return "\(event.items) items · \(ByteFormatting.format(event.bytes))"
            }
            if event.items > 0 { return "\(event.items) items" }
            return event.bytes > 0 ? ByteFormatting.format(event.bytes) : "Cleanup finished"
        }
    }

    private func award(_ amount: Int, reason: String, detail: String,
                       symbol: String, now: Date) {
        guard amount > 0 else { return }
        let oldLevel = profile.level
        profile.xp += amount
        profile.level = Self.level(forXP: profile.xp)
        enqueueReward(GameReward(amount: amount, reason: reason))
        profile.recent.insert(GameActivity(
            id: UUID(), date: now, title: reason, detail: detail,
            xp: amount, symbol: symbol), at: 0)
        if profile.recent.count > 30 { profile.recent.removeLast(profile.recent.count - 30) }
        if profile.level > oldLevel {
            enqueueCelebration(GameCelebration(
                title: "Level \(profile.level)",
                detail: "\(title) — \(xpToNextLevel) XP to the next level",
                symbol: "arrow.up.circle.fill",
                isLevelUp: true))
            notifyUser(title: "Level \(profile.level) reached",
                       body: "\(title) — keep going to unlock the next rank.")
        }
    }

    private func checkAchievements(now: Date) {
        var rounds = 0
        var changed = true
        while changed && rounds < 4 {
            changed = false
            for achievement in Self.achievements where profile.unlocked[achievement.id] == nil {
                guard currentValue(for: achievement.metric) >= achievement.target else { continue }
                profile.unlocked[achievement.id] = now
                award(achievement.rewardXP,
                      reason: "Achievement: \(achievement.title)",
                      detail: achievement.detail,
                      symbol: achievement.symbol, now: now)
                enqueueCelebration(GameCelebration(
                    title: achievement.title,
                    detail: achievement.detail,
                    symbol: achievement.symbol,
                    isLevelUp: false))
                notifyUser(title: "Achievement unlocked",
                           body: "\(achievement.title) — \(achievement.detail)")
                changed = true
            }
            rounds += 1
        }
    }

    nonisolated static func sourceEventKind(forCleanupSource source: String) -> GameEventKind {
        switch source {
        case "Duplicates": return .duplicateCleanup
        case "Similar Files": return .similarCleanup
        default: return .cleanup
        }
    }

    private func notifyUser(title: String, body: String) {
        let enabled = UserDefaults.standard.object(forKey: "gamificationNotifications") as? Bool ?? true
        guard enabled else { return }
        NotificationService.shared.postGamification(title: title, body: body)
    }

    // MARK: Persistence

    private static var defaultFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["DISKBUDDY_GAMIFICATION_PATH"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DiskBuddy/gamification.json")
    }

    private static func load(from url: URL) -> GameProfile {
        guard FileManager.default.fileExists(atPath: url.path) else { return GameProfile() }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(GameProfile.self, from: data)
        } catch {
            // Preserve the corrupt file for diagnosis instead of silently
            // overwriting a user's progress with a blank profile.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("gamification.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("DiskDoom gamification: profile unreadable, archived to \(backup.lastPathComponent) — \(error.localizedDescription)")
            return GameProfile()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profile).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("DiskDoom gamification: could not save — \(error.localizedDescription)")
        }
    }

    private func add(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}
