# Gamification

DiskBuddy's progress system is local, offline, and tied to real cleanup work.
It never awards XP for browsing, simulated measurements, or unconfirmed
actions. All state lives in one JSON profile:

`~/Library/Application Support/DiskBuddy/gamification.json`

The path can be overridden with `DISKBUDDY_GAMIFICATION_PATH` (used by UI tests).

## XP sources

| Action | Event | Base XP |
| --- | --- | --- |
| Successful scan | `.scan` | `10 + min(15, filesScanned / 20,000)` |
| Confirmed cleanup queue removal | `.cleanup` | `20 + min(80, GB × 10) + min(20, items / 10)` |
| Duplicate removal (direct or queue) | `.duplicateCleanup` | `15 + min(60, GB × 8) + min(20, items / 5)` |
| Similar-photo removal | `.similarCleanup` | `15 + min(60, GB × 8) + min(20, items / 5)` |
| Photos Library delete | `.photoCleanup` | `20 + min(60, GB × 8) + min(20, items / 5)` |
| Daily check-in | streak | `10 + min(30, streak × 2)` |
| Quest claim | quest reward | 25–300 XP |
| Achievement unlock | bonus | 50–2,000 XP |

Moving photos into the “Trash (DiskBuddy)” album does **not** award cleanup XP,
because the bytes are still in the library. Deleting from the library does.

The cleanup queue records one event per source group, so a single queue run can
advance duplicate, similar, and generic cleanup counters independently.

## Levels

Cumulative XP required to reach level `L`:

```
threshold(L) = 100 × (L − 1) + 25 × (L − 1) × (L − 2) / 2
```

- Level 2: 100 XP
- Level 3: 225 XP
- Level 5: 550 XP
- Level 10: 1,900 XP

Level-ups enqueue a celebration, play the system Glass sound (unless Reduce
Motion is on), and send a notification when enabled.

## Ranks

| Level | Rank |
| --- | --- |
| 1–2 | Storage Sprout |
| 3–4 | Byte Buddy |
| 5–7 | Disk Defender |
| 8–10 | Space Saver |
| 11–15 | Cache Crusher |
| 16–20 | Terabyte Tamer |
| 21–30 | Storage Sage |
| 31+ | Disk Legend |

The Progress page highlights the current rank from this single canonical list.

## Achievements

Achievements are evaluated after every event, in up to four passes so a bonus
XP award can unlock a level achievement in the same action.

- Cleanup: First Sweep (1), Tidy Ten (10), Century Club (100), Deep Clean (1,000)
- Space: Gigabyte Slayer (1 GB), Ten Gig Club (10 GB), Hundred Gig Hero (100 GB),
  Terabyte Tamer (1 TB)
- Scans: Eyes Open (1), Scan Veteran (25), Scan Legend (100)
- Duplicates: Dupe Destroyer (10), Dupe Dynamo (100), Duplicate Demolition (1,000)
- Similar: Lookalike Hunter (25), Curator (250)
- Photos: Pixel Purger (10), Album Architect (100)
- Streaks: Streak Starter (3), Week Warrior (7), Monthly Master (30)
- Levels: Rising Star (5), Double Digits (10), Elite Cleaner (25), Disk Legend (50)

Each unlock awards bonus XP exactly once, enqueues a celebration, and sends a
notification when enabled.

## Quests

Daily quests reset at local midnight; weekly quests reset at the start of the
calendar week. The Progress page shows a live countdown.

- Three daily quests are selected deterministically from a pool of eight
  (scan, bytes, items, duplicates, photos, check-in).
- Two weekly quests are selected from a pool of five.
- Progress is clamped to the target. Claiming is allowed once, only when the
  target is reached.
- A minute-level timer and app-activation refresh keep the quest set current
  even if the app stays open across midnight.

## Streaks

- A day counts when the app opens (`checkIn`) or any scan/cleanup event is
  recorded.
- Consecutive days increase the streak; a gap resets it to 1.
- The last 14 active days are shown as a calendar on the Progress page.
- Best streak is retained.

## UI surfaces

- Progress tab: hero level ring, stats, 14-day streak calendar, rank path,
  daily/weekly quests, filtered achievement grid, next achievement, activity
  feed, reset.
- Sidebar: compact Level/XP/streak card.
- Menu bar panel: Level/XP/streak row and Progress / Similar / Monitor buttons.
- Main window overlays: queued XP toasts and queued celebration banners with
  confetti.
- Settings → General → Gamification: XP toast toggle, achievement/level
  notification toggle, Open Progress, Reset Progress.
- Global search: “Progress” appears automatically as a section result.

## Reset

Reset clears XP, level, streak, active-day keys, achievements, and quest
progress, and drops any queued toasts/celebrations. Files, scans, snapshots, and
cleanup history are untouched.

## Testing

- `DiskBuddyTests/GamificationTests.swift` covers levels, XP, queues, streaks,
  daily/weekly rollover, double-claim prevention, source mapping, persistence
  migration, corrupt-profile recovery, and reset.
- `DiskBuddyUITests/GamificationUITests.swift` launches with
  `-uiTestMainWindow -uiTestTab progress` and an isolated profile, then verifies
  the hub, check-in, and Settings section.
