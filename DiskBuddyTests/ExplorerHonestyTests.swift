//
//  ExplorerHonestyTests.swift
//  DiskBuddyTests
//
//  Regression tests for the "never display a fabricated or over-confident
//  number" rule, scoped to the Explorer inspector and the LiveFeed
//  events/min rate.
//

import Testing
import Foundation
@testable import DiskDoom

// MARK: - Explorer: unreadable nodes must not claim measured sizes

struct ExplorerUnreadableNodeTests {
    private func makeNode(size: Int64, isUnreadable: Bool) -> FolderNode {
        FolderNode(
            path: "/Users/test/Library/Mail", name: "Mail", size: size,
            isDirectory: true, isPackage: false, isSymlink: false,
            childCount: nil, fileCount: nil, modified: nil, fileExtension: nil,
            percentageOfParent: 0,
            isUnreadable: isUnreadable, measuredAt: Date())
    }

    @Test func unreadableNodeShowsUnknownNotZero() {
        let node = makeNode(size: 0, isUnreadable: true)
        // The placeholder 0 must never surface as a definite "0 bytes".
        #expect(node.sizeDisplay == "Unknown (permission denied)")
        #expect(node.sizeDisplay != node.sizeFormatted)
    }

    @Test func readableNodeShowsMeasuredSize() {
        let node = makeNode(size: 1_048_576, isUnreadable: false)
        #expect(node.sizeDisplay == node.sizeFormatted)
        #expect(node.sizeDisplay != "Unknown (permission denied)")
    }

    @Test func unreadableFlagSurvivesNodeConstruction() {
        // FolderRow/FolderInspector branch on this flag; it must round-trip.
        let node = makeNode(size: 0, isUnreadable: true)
        #expect(node.isUnreadable)
    }
}

// MARK: - LiveFeed: events/min is a rolling window, not a frozen high-water mark

struct FileFeedRateWindowTests {
    private func event(secondsAgo: Double, now: Date) -> FileFeedEvent {
        FileFeedEvent(date: now.addingTimeInterval(-secondsAgo),
                      path: "/tmp/x", isCreated: true, attributedApp: nil)
    }

    @Test func countsOnlyEventsInsideTheWindow() {
        let now = Date()
        let events = [
            event(secondsAgo: 5, now: now),
            event(secondsAgo: 30, now: now),
            event(secondsAgo: 59, now: now),
            event(secondsAgo: 61, now: now), // just outside the window
            event(secondsAgo: 300, now: now),
        ]
        #expect(FileFeedMonitor.rollingWindowCount(events: events, now: now) == 3)
    }

    @Test func rateDecaysToZeroAfterActivityStops() {
        // The bug this guards: the rate was only recomputed on new batches,
        // so it froze at its last value forever. A pure window over stale
        // events must return 0 — the decay the timer now drives.
        let now = Date()
        let stale = (0..<10).map { event(secondsAgo: 120 + Double($0), now: now) }
        #expect(FileFeedMonitor.rollingWindowCount(events: stale, now: now) == 0)
    }

    @Test func emptyEventListRatesZero() {
        #expect(FileFeedMonitor.rollingWindowCount(events: [], now: Date()) == 0)
    }

    @Test func boundaryEventExactlyOnCutoffIsExcluded() {
        let now = Date()
        let events = [event(secondsAgo: 60, now: now)]
        #expect(FileFeedMonitor.rollingWindowCount(events: events, now: now) == 0)
    }
}
