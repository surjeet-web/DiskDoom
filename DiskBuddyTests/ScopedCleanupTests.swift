import Foundation
import Testing
@testable import DiskDoom

@Suite
struct ScopedCleanupTests {
    @Test @MainActor func stagingUsesTrashBackstopForTraversal() {
        for path in ["/System/../System/Library", "/Library/../usr/bin", "/private/var/folders/"] {
            #expect(AppState.isProtectedFromDeletion(path) == TrashService.deletionRefusal(for: path))
            #expect(AppState.isProtectedFromDeletion(path) != nil)
        }
    }

    @Test @MainActor func emptyExplicitSelectionPreservesExistingQueue() {
        let state = AppState()
        let unrelated = CleanupItem(source: "Existing queue", path: "/nonexistent-unrelated-diskbuddy-file", bytes: 42)
        state.cleanupItems = [unrelated]
        let result = state.executeCleanup(onlyPaths: [])
        #expect(result.trashedCount == 0)
        #expect(result.failures.isEmpty)
        #expect(state.cleanupItems.count == 1)
        #expect(state.cleanupItems.first?.path == unrelated.path)
    }

    @Test @MainActor func simulatorWithoutSelectionDoesNotRunExistingQueue() async {
        let state = AppState()
        let unrelated = CleanupItem(source: "Existing queue", path: "/nonexistent-unrelated-diskbuddy-file", bytes: 42)
        state.cleanupItems = [unrelated]
        let simulator = WhatIfSimulator()
        let report = await simulator.executeSelected(state: state)
        #expect(report.attempted == 0)
        #expect(report.totalFreed == 0)
        #expect(state.trashFailures.isEmpty)
        #expect(state.cleanupItems.first?.path == unrelated.path)
    }
}
