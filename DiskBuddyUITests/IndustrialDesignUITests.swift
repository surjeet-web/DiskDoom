import XCTest

final class IndustrialDesignUITests: XCTestCase {
    @MainActor
    func testShellSearchNavigationAndActivity() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMainWindow", "-uiTestTab", "explore"]
        app.launch()
        let window = mainWindow(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        let search = window.textFields["workspace.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.click()
        search.typeText("Progress")
        XCTAssertTrue(app.staticTexts["Progress"].firstMatch.waitForExistence(timeout: 10))
        window.buttons["Clear search"].firstMatch.click()
        let activity = window.buttons["workspace.activity"].firstMatch
        XCTAssertTrue(activity.exists)
        activity.click()
        XCTAssertTrue(app.staticTexts["Activity & Jobs"].waitForExistence(timeout: 5))
        app.buttons["Done"].click()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(window.staticTexts["Scan to find duplicates"].waitForExistence(timeout: 10) || window.staticTexts["Duplicates"].exists)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Industrial shell and duplicate review"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -3, dy: -3))
        let compactCorner = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 900, dy: 700))
        corner.press(forDuration: 0.1, thenDragTo: compactCorner)
        XCTAssertLessThan(window.frame.width, 1100)
        XCTAssertTrue(window.textFields["workspace.search"].firstMatch.isHittable)
        let compact = XCTAttachment(screenshot: window.screenshot())
        compact.name = "Compact industrial workspace"
        compact.lifetime = .keepAlways
        add(compact)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testAppearanceSettingsAreReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMainWindow", "-uiTestTab", "progress"]
        app.launch()
        let window = mainWindow(in: app)
        XCTAssertTrue(window.textFields["workspace.search"].firstMatch.waitForExistence(timeout: 20))
        window.click()
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'settings' OR title CONTAINS 'Settings'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.buttons["Appearance"].click()
        XCTAssertTrue(settings.descendants(matching: .any)["appearance.effects"].firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: settings.screenshot())
        screenshot.name = "Terraced appearance settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func mainWindow(in app: XCUIApplication) -> XCUIElement {
        let window = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-AppWindow'")).firstMatch
        if !window.waitForExistence(timeout: 5) { app.typeKey("n", modifierFlags: .command) }
        return window
    }
}
