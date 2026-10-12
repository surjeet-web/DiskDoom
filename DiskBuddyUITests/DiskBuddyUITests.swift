//
//  DiskBuddyUITests.swift
//  DiskBuddyUITests
//
//  Launch smoke tests. These are the only tests that exercise the real
//  SwiftUI scene graph, so they exist to catch the failures unit tests
//  structurally cannot see — most importantly the Settings scene crash,
//  which happened because the `Settings` scene does not inherit the
//  `WindowGroup` environment and `SettingsView` was missing its
//  `@EnvironmentObject`s.
//

import XCTest

final class DiskBuddyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Stop at the first failure: everything here is a smoke test, and a
        // later assertion is meaningless if the app did not even launch.
        continueAfterFailure = true
    }

    @MainActor
    func testLaunchShowsAWindow() throws {
        let app = XCUIApplication()
        app.launch()

        // A window must exist. On a fresh account the onboarding wizard is
        // the first thing shown; otherwise the main window. Either way the
        // app must not come up windowless (which is what a scene-injection
        // crash looks like from the outside).
        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 20),
            "App launched without any window — likely a missing @EnvironmentObject in a scene")
        XCTAssertTrue(app.state == .runningForeground, "App is not in the foreground")
    }

    @MainActor
    func testSettingsSceneDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 20) else {
            XCTFail("No window to open Settings from")
            return
        }
        window.click()

        // ⌘, is bound to `openSettings`. Before the fix this terminated the
        // process because SettingsView's environment objects were only
        // injected in the WindowGroup.
        app.typeKey(",", modifierFlags: .command)

        // Give the Settings scene a moment to materialise.
        let appeared = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH 'settings' OR title CONTAINS 'Settings'"))
            .firstMatch.waitForExistence(timeout: 10)

        XCTAssertEqual(app.state, .runningForeground,
                       "App crashed after ⌘, — the Settings scene is missing environment objects")
        XCTAssertTrue(appeared, "Settings scene did not present after ⌘,")
    }

    @MainActor
    func testSidebarNavigationDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 20) else {
            XCTFail("No window to navigate")
            return
        }
        window.click()

        // Walk a few sidebar destinations. Several views compute charts from
        // an empty index, which is where the historical NaN frame crashes
        // (sqrt(0/0) into `.frame(width:)`) showed up.
        for _ in 0..<3 {
            app.typeKey("]", modifierFlags: [.command, .shift])
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTAssertEqual(app.state, .runningForeground,
                       "App crashed while navigating tabs")
    }
}
