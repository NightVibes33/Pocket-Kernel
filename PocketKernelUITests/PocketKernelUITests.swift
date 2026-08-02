import XCTest

@MainActor final class PocketKernelUITests: XCTestCase {
    func testGenerateInstallCreatePersistAndDelete() {
        let app = launch(startTab: "create", reset: true)
        tap(app.buttons["Generate on Device"], timeout: 15)

        let install = app.buttons["Install Service Log"]
        scrollToElement(install, app: app, timeout: 20)
        tap(install)
        XCTAssertFalse(install.waitForExistence(timeout: 2))

        app.terminate()
        let library = launch(startTab: "library")
        let serviceLog = library.staticTexts["Service Log"].firstMatch
        tap(serviceLog, timeout: 10)

        let addService = library.buttons["Add Service"]
        tap(addService, timeout: 10)
        let mileage = library.textFields["Mileage"]
        tap(mileage, timeout: 10)
        mileage.typeText("42000")
        let cost = library.textFields["Cost"]
        tap(cost, timeout: 5)
        cost.typeText("79.99")
        tap(library.buttons["Save"], timeout: 5)

        library.terminate()
        let relaunched = launch(startTab: "library")
        if relaunched.buttons["Continue Safely"].waitForExistence(timeout: 2) { tap(relaunched.buttons["Continue Safely"]) }
        tap(relaunched.staticTexts["Service Log"].firstMatch, timeout: 10)
        let persisted = relaunched.descendants(matching: .any)["record-field-mileage"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 8))
        XCTAssertTrue(persisted.label.contains("42000"))

        tap(relaunched.buttons["Done"], timeout: 5)
        pressAndHold(relaunched.staticTexts["Service Log"].firstMatch)
        tap(relaunched.buttons["Delete"], timeout: 5)
        XCTAssertFalse(relaunched.staticTexts["Service Log"].firstMatch.waitForExistence(timeout: 2))
    }

    func testBuiltInTemplateAndRecoveryFixture() {
        let app = launch(startTab: "library", reset: true)
        tap(app.buttons["Task Board"], timeout: 10)
        XCTAssertTrue(app.staticTexts["Task Board"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()

        let recovery = XCUIApplication()
        recovery.launchArguments = ["-PKUITesting", "1", "-PKRecoveryFixture", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1"]
        recovery.launch()
        XCTAssertTrue(recovery.staticTexts["PocketKernel recovered an interrupted app"].waitForExistence(timeout: 8))
        tap(recovery.buttons["Continue Safely"], timeout: 5)
    }

    private func launch(startTab: String, reset: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PKUITesting", "1", "-PKModelMode", "mock", "-PKDisableAnimations", "1", "-PKStartTab", startTab]
        if reset { app.launchArguments += ["-PKResetDatabase", "1"] }
        app.launch()
        return app
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func scrollToElement(_ element: XCUIElement, app: XCUIApplication, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !element.exists && Date() < deadline { app.swipeUp() }
        XCTAssertTrue(element.exists)
    }

    private func pressAndHold(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
    }
}
