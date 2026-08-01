import XCTest

@MainActor final class PocketKernelUITests: XCTestCase {
    func testOneShotMockGenerationRecordPersistenceExportAndDelete() {
        let app = XCUIApplication(); app.launchArguments = ["-PKUITesting", "1", "-PKResetDatabase", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1"]; app.launch()
        app.tabBars.buttons["Create"].tap(); app.buttons["Generate on device"].tap()
        XCTAssertTrue(app.buttons["Install Service Log"].waitForExistence(timeout: 15)); app.buttons["Install Service Log"].tap()
        app.tabBars.buttons["Library"].tap(); XCTAssertTrue(app.staticTexts["Service Log"].waitForExistence(timeout: 5)); app.staticTexts["Service Log"].tap()
        XCTAssertTrue(app.buttons["Add Service"].waitForExistence(timeout: 5)); app.buttons["Add Service"].tap(); app.textFields["Mileage"].tap(); app.textFields["Mileage"].typeText("42000"); app.buttons["Save"].tap()
        app.terminate(); app.launchArguments = ["-PKUITesting", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1"]; app.launch()
        if app.buttons["Continue Safely"].waitForExistence(timeout: 2) { app.buttons["Continue Safely"].tap() }
        app.tabBars.buttons["Library"].tap(); app.staticTexts["Service Log"].tap()
        XCTAssertTrue(app.staticTexts["42000"].waitForExistence(timeout: 5))
    }

    func testRecoveryFixtureAppears() {
        let app = XCUIApplication(); app.launchArguments = ["-PKUITesting", "1", "-PKRecoveryFixture", "1", "-PKModelMode", "mock"]; app.launch()
        XCTAssertTrue(app.staticTexts["PocketKernel recovered from an interrupted session"].waitForExistence(timeout: 5))
    }
}
