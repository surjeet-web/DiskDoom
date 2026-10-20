import Foundation
import AppKit
import SwiftUI
import Testing
@testable import DiskDoom

@Suite(.serialized)
struct GamificationTests {
    private func profileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("diskbuddy-game-\(UUID().uuidString).json")
    }

    @MainActor
    private func makeEngine(_ url: URL, now: Date) -> GamificationEngine {
        GamificationEngine(fileURL: url, nowProvider: { now })
    }

    @MainActor
    @Test func levelCurveIsMonotonic() {
        #expect(GamificationEngine.xpThreshold(forLevel: 1) == 0)
        #expect(GamificationEngine.xpThreshold(forLevel: 2) == 100)
        #expect(GamificationEngine.xpThreshold(forLevel: 3) == 225)
        #expect(GamificationEngine.level(forXP: 0) == 1)
        #expect(GamificationEngine.level(forXP: 99) == 1)
        #expect(GamificationEngine.level(forXP: 100) == 2)
        #expect(GamificationEngine.level(forXP: 224) == 2)
        #expect(GamificationEngine.level(forXP: 225) == 3)
    }

    @MainActor
    @Test func cleanupAwardsXPAndUnlocksFirstAchievement() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)

        #expect(engine.xp == 0)
        engine.record(GameEvent(kind: .cleanup, bytes: 1_200_000_000, items: 3), now: now)

        #expect(engine.xp > 0)
        #expect(engine.profile.totalBytes == 1_200_000_000)
        #expect(engine.profile.totalItems == 3)
        #expect(engine.isUnlocked(GamificationEngine.achievements.first { $0.id == "first-clean" }!))
        #expect(engine.isUnlocked(GamificationEngine.achievements.first { $0.id == "first-gig" }!))
        #expect(engine.streak == 1)
    }

    @MainActor
    @Test func achievementRewardIsPaidOnlyOnce() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)

        engine.record(GameEvent(kind: .cleanup, bytes: 2_000_000_000, items: 1), now: now)
        let firstGain = engine.xp
        engine.record(GameEvent(kind: .cleanup, bytes: 2_000_000_000, items: 1), now: now)
        let secondGain = engine.xp - firstGain

        #expect(firstGain > secondGain)
        let firstSweep = GamificationEngine.achievements.first { $0.id == "first-clean" }!
        #expect(engine.unlockedDate(firstSweep) != nil)
    }

    @MainActor
    @Test func streakAdvancesAndResetsAfterGap() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let engine = makeEngine(url, now: day)

        engine.checkIn(now: day)
        #expect(engine.streak == 1)

        engine.checkIn(now: day.addingTimeInterval(86_400))
        #expect(engine.streak == 2)

        engine.checkIn(now: day.addingTimeInterval(4 * 86_400))
        #expect(engine.streak == 1)
        #expect(engine.bestStreak == 2)
    }

    @MainActor
    @Test func questsProgressAndClaim() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)

        let quest = try #require(engine.dailyQuests.first)
        switch quest.metric {
        case .bytes:
            engine.record(GameEvent(kind: .cleanup, bytes: quest.target, items: 1), now: now)
        case .items:
            engine.record(GameEvent(kind: .cleanup, bytes: 0, items: Int(quest.target)), now: now)
        case .scans:
            for _ in 0..<quest.target {
                engine.record(GameEvent(kind: .scan, filesScanned: 100), now: now)
            }
        case .duplicateItems:
            engine.record(GameEvent(kind: .duplicateCleanup, bytes: 0,
                                    items: Int(quest.target)), now: now)
        case .photoItems:
            engine.record(GameEvent(kind: .photoCleanup, bytes: 0,
                                    items: Int(quest.target)), now: now)
        case .checkIns:
            engine.checkIn(now: now)
        }

        let refreshed = try #require(engine.dailyQuests.first { $0.id == quest.id })
        #expect(refreshed.isComplete)
        let xpBefore = engine.xp
        engine.claim(refreshed, now: now)
        let claimed = try #require(engine.dailyQuests.first { $0.id == quest.id })
        #expect(claimed.claimed)
        #expect(engine.xp >= xpBefore + quest.rewardXP)
    }

    @MainActor
    @Test func profilePersistsAcrossInstances() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let first = makeEngine(url, now: now)
        first.record(GameEvent(kind: .scan, filesScanned: 50_000), now: now)
        first.record(GameEvent(kind: .cleanup, bytes: 3_000_000_000, items: 12), now: now)
        let xp = first.xp
        let unlocks = first.unlockedCount

        let second = makeEngine(url, now: now)
        #expect(second.xp == xp)
        #expect(second.unlockedCount == unlocks)
        #expect(second.profile.totalScans == 1)
        #expect(second.profile.totalBytes == 3_000_000_000)
    }

    @MainActor
    @Test func scanAndPhotoEventsUseTheirOwnCounters() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)

        engine.record(GameEvent(kind: .scan, filesScanned: 10_000), now: now)
        engine.record(GameEvent(kind: .duplicateCleanup, bytes: 1_000, items: 4), now: now)
        engine.record(GameEvent(kind: .similarCleanup, bytes: 2_000, items: 5), now: now)
        engine.record(GameEvent(kind: .photoCleanup, bytes: 3_000, items: 6), now: now)

        #expect(engine.profile.totalScans == 1)
        #expect(engine.profile.totalDuplicateItems == 4)
        #expect(engine.profile.totalSimilarItems == 5)
        #expect(engine.profile.totalPhotoItems == 6)
        #expect(engine.profile.totalItems == 15)
        #expect(engine.profile.totalBytes == 6_000)
    }

    @MainActor
    @Test func resetClearsProfileButKeepsQuests() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)
        engine.record(GameEvent(kind: .cleanup, bytes: 1_000, items: 1), now: now)
        #expect(engine.xp > 0)

        engine.resetProgress(now: now)
        #expect(engine.xp == 0)
        #expect(engine.level == 1)
        #expect(engine.profile.unlocked.isEmpty)
        #expect(!engine.dailyQuests.isEmpty)
        #expect(engine.rewardQueue.isEmpty)
        #expect(engine.celebrationQueue.isEmpty)
    }

    @MainActor
    @Test func rewardQueueDrainsInOrder() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)

        engine.record(GameEvent(kind: .scan, filesScanned: 1_000), now: now)
        engine.record(GameEvent(kind: .cleanup, bytes: 500_000_000, items: 4), now: now)
        #expect(engine.rewardQueue.count >= 2)

        let first = try #require(engine.currentReward)
        engine.dismissCurrentReward()
        let second = try #require(engine.currentReward)
        #expect(first.id != second.id)
        engine.dismissCurrentReward()
        #expect(engine.currentReward != nil || engine.rewardQueue.isEmpty)
    }

    @MainActor
    @Test func celebrationQueueDrainsInOrder() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)

        engine.record(GameEvent(kind: .cleanup, bytes: 20_000_000_000, items: 200), now: now)
        #expect(engine.celebrationQueue.count >= 1)
        let first = try #require(engine.currentCelebration)
        engine.dismissCurrentCelebration()
        if let next = engine.currentCelebration {
            #expect(first.id != next.id)
        }
    }

    @MainActor
    @Test func dailyAndWeeklyQuestsRollOver() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let engine = makeEngine(url, now: day)

        let firstDaily = engine.dailyQuests.map(\.id)
        let firstWeekly = engine.weeklyQuests.map(\.id)
        #expect(!firstDaily.isEmpty)
        #expect(!firstWeekly.isEmpty)

        #expect(engine.refresh(now: day.addingTimeInterval(86_400)))
        #expect(engine.dailyQuests.map(\.id) != firstDaily)
        #expect(engine.weeklyQuests.map(\.id) == firstWeekly)

        #expect(engine.refresh(now: day.addingTimeInterval(8 * 86_400)))
        #expect(engine.weeklyQuests.map(\.id) != firstWeekly)
    }

    @MainActor
    @Test func questCannotBeClaimedTwice() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)

        let quest = try #require(engine.dailyQuests.first)
        switch quest.metric {
        case .bytes:
            engine.record(GameEvent(kind: .cleanup, bytes: quest.target, items: 1), now: now)
        case .items:
            engine.record(GameEvent(kind: .cleanup, bytes: 0, items: Int(quest.target)), now: now)
        case .scans:
            for _ in 0..<quest.target {
                engine.record(GameEvent(kind: .scan, filesScanned: 10), now: now)
            }
        case .duplicateItems:
            engine.record(GameEvent(kind: .duplicateCleanup, bytes: 0,
                                    items: Int(quest.target)), now: now)
        case .photoItems:
            engine.record(GameEvent(kind: .photoCleanup, bytes: 0,
                                    items: Int(quest.target)), now: now)
        case .checkIns:
            engine.checkIn(now: now)
        }
        let complete = try #require(engine.dailyQuests.first { $0.id == quest.id && $0.isComplete })
        engine.claim(complete, now: now)
        let xpAfterFirst = engine.xp
        engine.claim(complete, now: now)
        #expect(engine.xp == xpAfterFirst)
    }

    @MainActor
    @Test func cleanupSourceMappingIsStable() {
        #expect(GamificationEngine.sourceEventKind(forCleanupSource: "Duplicates") == .duplicateCleanup)
        #expect(GamificationEngine.sourceEventKind(forCleanupSource: "Similar Files") == .similarCleanup)
        #expect(GamificationEngine.sourceEventKind(forCleanupSource: "Inspector") == .cleanup)
        #expect(GamificationEngine.sourceEventKind(forCleanupSource: "Uninstall") == .cleanup)
    }

    @MainActor
    @Test func profileWithoutActiveDaysStillDecodes() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = """
        {"xp":123,"level":2,"streak":3,"bestStreak":4,"totalBytes":100,
         "totalItems":2,"totalScans":1,"totalDuplicateItems":0,"totalSimilarItems":0,
         "totalPhotoItems":0,"unlocked":{},"quests":[],"recent":[]}
        """
        try Data(legacy.utf8).write(to: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)
        #expect(engine.xp == 123)
        #expect(engine.profile.activeDays == nil || engine.profile.activeDays?.isEmpty == true)
    }

    @MainActor
    @Test func progressViewBuildsWithoutAScan() throws {
        let url = profileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)
        engine.checkIn(now: now)

        let host = NSHostingView(rootView: GamificationView().environmentObject(engine))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 760)
        host.layoutSubtreeIfNeeded()
        #expect(host.frame.width == 1000)
        #expect(!engine.dailyQuests.isEmpty)
    }

    @MainActor
    @Test func settingsGamificationSectionBuilds() throws {
        let url = profileURL()
        setenv("DISKBUDDY_GAMIFICATION_PATH", url.path, 1)
        defer {
            unsetenv("DISKBUDDY_GAMIFICATION_PATH")
            try? FileManager.default.removeItem(at: url)
        }
        let state = AppState()
        let host = NSHostingView(rootView: SettingsView()
            .environmentObject(state)
            .environmentObject(state.permissions)
            .environmentObject(state.license)
            .environmentObject(state.ignoreRules)
            .environmentObject(state.priorities)
            .environmentObject(state.gamification)
            .environmentObject(MenuBarMonitor()))
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 600)
        host.layoutSubtreeIfNeeded()
        #expect(host.frame.width == 560)
    }

    @MainActor
    @Test func corruptProfileIsArchivedAndRecovered() throws {
        let url = profileURL()
        let directory = url.deletingLastPathComponent()
        defer {
            try? FileManager.default.removeItem(at: url)
            if let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
                for file in files where file.hasPrefix("gamification.corrupt-") {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
                }
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = makeEngine(url, now: now)
        #expect(engine.xp == 0)
        #expect(engine.level == 1)
        let archived = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .contains { $0.hasPrefix("gamification.corrupt-") } ?? false
        #expect(archived)
    }
}
