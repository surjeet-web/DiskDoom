import XCTest

// MARK: - Gamification UI wiring
//
// Proves the Progress hub renders without a scan, the check-in control works,
// and the Settings gamification section is reachable. Uses an isolated profile
// so the test never touches the developer's real XP.

final class GamificationUITests: XCTestCase {
    private var profilePath = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        profilePath = NSTemporaryDirectory()
            .appending("diskbuddy-ui-gamification-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: profilePath)
    }

    @MainActor
    func testProgressHubRendersAndCheckInWorks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMainWindow", "-uiTestTab", "progress"]
        app.launchEnvironment["DISKBUDDY_GAMIFICATION_PATH"] = profilePath
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20),
                      "App launched without a window")

        XCTAssertTrue(app.staticTexts["Daily Quests"].waitForExistence(timeout: 15),
                      "Progress hub did not render; gamification is not wired to the sidebar tab")
        XCTAssertTrue(app.staticTexts["Achievements"].exists)
        XCTAssertTrue(app.staticTexts["Activity Streak"].exists)

        let checkIn = app.buttons["Check In Today"].firstMatch
        if checkIn.waitForExistence(timeout: 5) {
            checkIn.click()
            XCTAssertTrue(app.buttons["Checked In"].waitForExistence(timeout: 5),
                          "Check-in did not update the hero button")
        }

        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testSettingsShowsGamificationControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMainWindow", "-uiTestTab", "progress"]
        app.launchEnvironment["DISKBUDDY_GAMIFICATION_PATH"] = profilePath
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        app.typeKey(",", modifierFlags: .command)

        let settings = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH 'settings' OR title CONTAINS 'Settings'"))
            .firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10),
                      "Settings scene did not present")
        settings.click()

        let section = app.staticTexts["Gamification"]
        if !section.exists {
            settings.swipeUp()
        }
        XCTAssertTrue(section.waitForExistence(timeout: 5),
                      "Gamification settings section is missing")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
