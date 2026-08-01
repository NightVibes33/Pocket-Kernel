import XCTest

final class PocketKernelUITests: XCTestCase {
    func testMockGenerationInstallAndRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["-PKUITesting", "1", "-PKResetDatabase", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1"]; app.launch()
        app.tabBars.buttons["Create"].tap(); app.buttons["Generate on device"].tap()
        XCTAssertTrue(app.buttons["Install Service Log"].waitForExistence(timeout: 10)); app.buttons["Install Service Log"].tap()
        app.tabBars.buttons["Library"].tap(); XCTAssertTrue(app.staticTexts["Service Log"].waitForExistence(timeout: 5))
    }
}

