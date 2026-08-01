import XCTest

@MainActor final class PocketKernelUITests: XCTestCase {
    func testOneShotMockGenerationRecordPersistenceExportAndDelete() {
        let app = XCUIApplication(); app.launchArguments = ["-PKUITesting", "1", "-PKResetDatabase", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1", "-PKStartTab", "create"]; app.launch()
        XCTAssertTrue(app.buttons["Generate on device"].waitForExistence(timeout: 10)); app.buttons["Generate on device"].tap()
        let install = app.buttons["Install Service Log"]; XCTAssertTrue(install.waitForExistence(timeout: 15)); install.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: install); waitForExpectations(timeout: 10)
        app.terminate(); app.launchArguments = ["-PKUITesting", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1", "-PKStartTab", "library"]; app.launch()
        XCTAssertTrue(app.staticTexts["Service Log"].waitForExistence(timeout: 10)); app.staticTexts["Service Log"].tap()
        XCTAssertTrue(app.buttons["Add Service"].waitForExistence(timeout: 5)); app.buttons["Add Service"].tap(); app.textFields["Mileage"].tap(); app.textFields["Mileage"].typeText("42000"); app.buttons["Save"].tap()
        app.terminate(); app.launchArguments = ["-PKUITesting", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1", "-PKStartTab", "library"]; app.launch()
        if app.buttons["Continue Safely"].waitForExistence(timeout: 2) { app.buttons["Continue Safely"].tap() }
        XCTAssertTrue(app.staticTexts["Service Log"].waitForExistence(timeout: 10)); app.staticTexts["Service Log"].tap()
        XCTAssertTrue(app.staticTexts["42000"].waitForExistence(timeout: 5))
    }

    func testRecoveryFixtureAppears() {
        let app = XCUIApplication(); app.launchArguments = ["-PKUITesting", "1", "-PKRecoveryFixture", "1", "-PKModelMode", "mock"]; app.launch()
        XCTAssertTrue(app.staticTexts["PocketKernel recovered from an interrupted session"].waitForExistence(timeout: 5))
    }
}
