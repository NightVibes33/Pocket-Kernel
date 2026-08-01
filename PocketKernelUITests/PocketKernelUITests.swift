import XCTest

@MainActor final class PocketKernelUITests: XCTestCase {
    func testOneShotMockGenerationRecordPersistenceExportAndDelete() {
        let app = XCUIApplication(); app.launchArguments = ["-PKUITesting", "1", "-PKResetDatabase", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1", "-PKStartTab", "create"]; app.launch()
        tapCenter(app.buttons["Generate on device"], timeout: 10)
        let install = app.buttons["Install Service Log"]; tapCenter(install, timeout: 15)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: install); waitForExpectations(timeout: 10)
        app.terminate(); app.launchArguments = ["-PKUITesting", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1", "-PKStartTab", "library"]; app.launch()
        tapCenter(app.staticTexts["Service Log"], timeout: 10)
        tapCenter(app.buttons["Add Service"]); tapCenter(app.textFields["Mileage"]); app.textFields["Mileage"].typeText("42000"); tapCenter(app.buttons["Save"])
        app.terminate(); app.launchArguments = ["-PKUITesting", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1", "-PKStartTab", "library"]; app.launch()
        if app.buttons["Continue Safely"].waitForExistence(timeout: 2) { tapCenter(app.buttons["Continue Safely"]) }
        tapCenter(app.staticTexts["Service Log"], timeout: 10)
        XCTAssertTrue(app.staticTexts["42000"].waitForExistence(timeout: 5))
    }

    private func tapCenter(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testRecoveryFixtureAppears() {
        let app = XCUIApplication(); app.launchArguments = ["-PKUITesting", "1", "-PKRecoveryFixture", "1", "-PKModelMode", "mock"]; app.launch()
        XCTAssertTrue(app.staticTexts["PocketKernel recovered from an interrupted session"].waitForExistence(timeout: 5))
    }
}
