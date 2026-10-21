import SwiftUI

// MARK: - Progress hub: level, streak, quests, achievements, activity

struct GamificationView: View {
    @EnvironmentObject private var game: GamificationEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmReset = false
    @State private var achievementFilter: AchievementFilter = .all

    private enum AchievementFilter: String, CaseIterable, Identifiable {
        case all, unlocked, locked
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .unlocked: return "Unlocked"
            case .locked: return "Locked"
            }
        }
    }

    private var sortedAchievements: [GameAchievement] {
        let filtered = GamificationEngine.achievements.filter { achievement in
            switch achievementFilter {
            case .all: return true
            case .unlocked: return game.isUnlocked(achievement)
            case .locked: return !game.isUnlocked(achievement)
            }
        }
        return filtered.sorted { left, right in
            let leftUnlocked = game.isUnlocked(left)
            let rightUnlocked = game.isUnlocked(right)
            if leftUnlocked != rightUnlocked { return leftUnlocked }
            if left.tier != right.tier { return tierRank(left.tier) < tierRank(right.tier) }
            return left.target < right.target
        }
    }

    private func tierRank(_ tier: GameAchievement.Tier) -> Int {
        switch tier {
        case .bronze: return 0
        case .silver: return 1
        case .gold: return 2
        case .platinum: return 3
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.l) {
                hero
                stats
                streakCalendar
                rankLadder
                questSection(title: "Daily Quests", subtitle: "Resets at midnight", quests: game.dailyQuests)
                questSection(title: "Weekly Quests", subtitle: "Resets every Monday", quests: game.weeklyQuests)
                achievementsSection
                activitySection
                footer
            }
            .padding(DesignTokens.Space.l)
        }
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset XP, quests and achievements", role: .destructive) {
                game.resetProgress()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only clears the local gamification profile. Your cleanup history and files are untouched.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: DesignTokens.Space.xl) {
            levelRing
            VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                HStack(spacing: DesignTokens.Space.s) {
                    Text("Level \(game.level)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(game.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text("\(game.xpIntoLevel.formatted()) / \(game.xpForNextLevel.formatted()) XP · \(game.xpToNextLevel.formatted()) to level \(game.level + 1)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                ProgressView(value: game.progressToNextLevel)
                    .tint(.white)
                    .frame(maxWidth: 340)
                HStack(spacing: DesignTokens.Space.m) {
                    Label("\(game.streak)-day streak", systemImage: "flame.fill")
                    Label("\(game.bestStreak) best", systemImage: "crown.fill")
                    Label("\(game.unlockedCount)/\(GamificationEngine.achievements.count) achievements", systemImage: "rosette")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(ByteFormatting.format(game.profile.totalBytes))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("reclaimed lifetime")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(game.profile.totalItems.formatted()) items cleaned")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                Button {
                    game.checkIn()
                } label: {
                    Label(game.hasCheckedInToday ? "Checked In" : "Check In Today",
                          systemImage: game.hasCheckedInToday ? "checkmark.circle.fill" : "hand.wave.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(game.hasCheckedInToday)
            }
        }
        .foregroundStyle(.white)
        .padding(DesignTokens.Space.xl)
        .background(
            LinearGradient(colors: [Color(hex: 0x3A1C71), Color(hex: 0x6A38C2), Color(hex: 0x2B5876)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .stroke(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: Color(hex: 0x3A1C71).opacity(0.35), radius: 18, y: 8)
    }

    private var levelRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: game.progressToNextLevel)
                .stroke(
                    AngularGradient(colors: [.white, Color(hex: 0x50E3C2), .white],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6),
                           value: game.progressToNextLevel)
            VStack(spacing: 0) {
                Text("LVL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(game.level)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
            }
        }
        .frame(width: 116, height: 116)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(game.level), \(game.title)")
        .accessibilityValue("\(game.xpIntoLevel) of \(game.xpForNextLevel) XP toward level \(game.level + 1)")
    }

    private var stats: some View {
        HStack(spacing: DesignTokens.Space.m) {
            stat("Scans", "\(game.profile.totalScans.formatted())", "magnifyingglass", .blue)
            stat("Items cleaned", "\(game.profile.totalItems.formatted())", "trash.fill", .orange)
            stat("Duplicates", "\(game.profile.totalDuplicateItems.formatted())", "doc.on.doc.fill", .purple)
            stat("Photos", "\(game.profile.totalPhotoItems.formatted())", "photo.stack.fill", .pink)
            stat("Best streak", "\(game.bestStreak)d", "flame.fill", .red)
        }
    }

    private func stat(_ label: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
    }

    // MARK: Streak calendar + rank path

    private var streakCalendar: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text("Activity Streak").font(.headline)
                Spacer()
                Text("Last 14 days")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                ForEach(-13...0, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                    let active = game.isActive(on: date)
                    let isToday = offset == 0
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(active ? Color.orange : Color.secondary.opacity(0.14))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if active {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isToday ? Color.orange.opacity(0.7) : .clear, lineWidth: 1.5))
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 8, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.orange : Color.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label("\(game.streak) days", systemImage: "flame.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Best: \(game.bestStreak) days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(game.hasCheckedInToday ? "Checked in today" : "Check in to keep the streak")
                        .font(.caption2)
                        .foregroundStyle(game.hasCheckedInToday ? .green : .orange)
                }
            }
        }
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
    }

    private var rankLadder: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text("Rank Path").font(.headline)
                Spacer()
                Text("Current: \(game.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(GamificationEngine.ranks.enumerated()), id: \.offset) { index, rank in
                        let reached = game.level >= rank.minLevel
                        let current = game.currentRankIndex == index
                        VStack(spacing: 4) {
                            Image(systemName: rank.symbol)
                                .font(.title3)
                                .foregroundStyle(reached ? Color.yellow : Color.secondary)
                                .frame(width: 38, height: 38)
                                .background((reached ? Color.yellow : Color.secondary).opacity(0.12),
                                            in: Circle())
                                .overlay(
                                    Circle().stroke(current ? Color.yellow : .clear, lineWidth: 2))
                            Text(rank.title)
                                .font(.caption2.weight(current ? .bold : .regular))
                                .foregroundStyle(reached ? .primary : .secondary)
                            Text("Lv \(rank.minLevel)")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(width: 92)
                        if index < GamificationEngine.ranks.count - 1 {
                            Rectangle()
                                .fill(reached ? Color.yellow.opacity(0.5) : Color.secondary.opacity(0.2))
                                .frame(width: 22, height: 2)
                                .offset(y: -8)
                        }
                    }
                }
            }
        }
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
    }

    // MARK: Quests

    @ViewBuilder
    private func questSection(title: String, subtitle: String, quests: [GameQuest]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(resetLabel(quests: quests, fallback: subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if quests.isEmpty {
                Text("Quests refresh automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(quests.sorted { $0.claimed == $1.claimed ? $0.id < $1.id : !$0.claimed }) { quest in
                    QuestRow(quest: quest) {
                        game.claim(quest)
                    }
                }
            }
        }
    }

    private func resetLabel(quests: [GameQuest], fallback: String) -> String {
        guard let expiry = quests.map(\.expiresAt).min() else { return fallback }
        let interval = expiry.timeIntervalSinceNow
        guard interval > 0 else { return "Refreshing…" }
        let minutes = Int(interval) / 60
        if minutes >= 60 {
            return "Resets in \(minutes / 60)h \(minutes % 60)m"
        }
        return "Resets in \(max(1, minutes))m"
    }

    // MARK: Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text("Achievements").font(.headline)
                Text("\(game.unlockedCount) of \(GamificationEngine.achievements.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Filter achievements", selection: $achievementFilter) {
                    ForEach(AchievementFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            if let next = game.nextAchievement {
                HStack(spacing: DesignTokens.Space.m) {
                    Image(systemName: "scope")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next up: \(next.achievement.title)")
                            .font(.callout.weight(.semibold))
                        Text(next.achievement.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: next.progress)
                            .tint(.purple)
                    }
                    Spacer()
                    Text("\(Int(next.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("+\(next.achievement.rewardXP) XP")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .padding(DesignTokens.Space.m)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            }
            if sortedAchievements.isEmpty {
                Text(achievementFilter == .unlocked
                     ? "No achievements unlocked yet — run a scan or clean something."
                     : "Everything unlocked. Legend status.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(DesignTokens.Space.m)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: DesignTokens.Space.m)],
                      spacing: DesignTokens.Space.m) {
                ForEach(sortedAchievements) { achievement in
                    AchievementCard(
                        achievement: achievement,
                        unlocked: game.isUnlocked(achievement),
                        progress: game.progress(for: achievement),
                        unlockedAt: game.unlockedDate(achievement))
                }
            }
        }
    }

    // MARK: Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text("Recent Activity").font(.headline)
                Spacer()
                Text("Last \(min(12, game.activities.count)) events")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if game.activities.isEmpty {
                Text("Scan or clean something to start earning XP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(game.activities.prefix(12)) { activity in
                        HStack(spacing: DesignTokens.Space.s) {
                            Image(systemName: activity.symbol)
                                .foregroundStyle(.purple)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(activity.title).font(.caption.weight(.medium))
                                Text(activity.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+\(activity.xp) XP")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.green)
                            Text(activity.date.formatted(.relative(presentation: .named)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("XP comes from real scans and confirmed cleanup. Balances persist locally in Application Support.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Reset Progress…", role: .destructive) { confirmReset = true }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Quest row

private struct QuestRow: View {
    let quest: GameQuest
    let onClaim: () -> Void

    private var progressLabel: String {
        if quest.metric == .bytes {
            return "\(ByteFormatting.format(min(quest.progress, quest.target))) / \(ByteFormatting.format(quest.target))"
        }
        return "\(min(quest.progress, quest.target).formatted()) / \(quest.target.formatted())"
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Image(systemName: quest.isComplete ? "checkmark.seal.fill" : "target")
                .font(.title3)
                .foregroundStyle(quest.claimed ? Color.secondary : quest.isComplete ? Color.green : Color.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(quest.title).font(.callout.weight(.semibold))
                    Text(quest.period == .daily ? "DAILY" : "WEEKLY")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background((quest.period == .daily ? Color.blue : Color.purple).opacity(0.12),
                                    in: .capsule)
                        .foregroundStyle(quest.period == .daily ? .blue : .purple)
                }
                Text(quest.detail).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: quest.fraction)
                    .tint(quest.isComplete ? .green : .blue)
                Text(progressLabel).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("+\(quest.rewardXP) XP")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.green)
                if quest.claimed {
                    Label("Claimed", systemImage: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Claim") { onClaim() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!quest.isComplete)
                        .accessibilityLabel("Claim \(quest.title), \(quest.rewardXP) XP")
                }
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
        .opacity(quest.claimed ? 0.65 : 1)
    }
}

// MARK: - Achievement card

private struct AchievementCard: View {
    let achievement: GameAchievement
    let unlocked: Bool
    let progress: Double
    let unlockedAt: Date?

    private var tint: Color {
        switch achievement.tier {
        case .bronze: return Color(hex: 0xC07A3A)
        case .silver: return Color(hex: 0x9AA4B2)
        case .gold: return Color(hex: 0xE0A800)
        case .platinum: return Color(hex: 0x4FC3F7)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack(spacing: DesignTokens.Space.s) {
                Image(systemName: achievement.symbol)
                    .font(.title2)
                    .foregroundStyle(unlocked ? tint : Color.secondary.opacity(0.5))
                    .frame(width: 42, height: 42)
                    .background((unlocked ? tint : Color.secondary).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
                VStack(alignment: .leading, spacing: 1) {
                    Text(achievement.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(unlocked ? .primary : .secondary)
                    Text(achievement.tier.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                }
                Spacer()
                if unlocked {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            }
            Text(achievement.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if unlocked {
                HStack {
                    Text(unlockedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unlocked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+\(achievement.rewardXP) XP")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            } else {
                ProgressView(value: progress)
                    .tint(tint)
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+\(achievement.rewardXP) XP")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(DesignTokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(unlocked ? 0.35 : 0.2),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                .stroke(unlocked ? tint.opacity(0.45) : .clear, lineWidth: 1))
        .shadow(color: unlocked ? tint.opacity(0.15) : .clear, radius: 8, y: 3)
    }
}

#Preview {
    GamificationView()
        .environmentObject(GamificationEngine(fileURL: URL(fileURLWithPath: "/tmp/diskbuddy-game-preview.json")))
        .frame(width: 1000, height: 760)
}
