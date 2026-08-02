import XCTest

@MainActor final class PocketKernelUITests: XCTestCase {
    func testOnboardingCompletesIntoHome() {
        let app = launch(reset: true, uiTesting: false, resetOnboarding: true)
        XCTAssertTrue(app.staticTexts["PocketKernel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Describe, preview, install, and run multiple private native micro-apps without writing code."].exists)
        tap(app.buttons["Get Started"])
        XCTAssertTrue(app.buttons["Create a Pocket App"].waitForExistence(timeout: 8))
    }

    func testEveryBuiltInPocketAppInstallsAndOpens() {
        let app = launch(startTab: "library", reset: true)
        let expectedHeadings = [
            "Task Board": "Task Board",
            "Habit Tracker": "Habit Tracker",
            "Quick Journal": "Quick Journal",
            "Inventory List": "Inventory",
            "Service Log": "Service Log"
        ]

        for name in ["Task Board", "Habit Tracker", "Quick Journal", "Inventory List", "Service Log"] {
            let before = pocketAppButtons(named: name, in: app).count
            tap(lastPocketAppButton(named: name, in: app), timeout: 10)
            waitForButtonCount(named: name, minimum: before + 1, in: app, timeout: 10)
            tap(pocketAppButtons(named: name, in: app).firstMatch, timeout: 8)
            XCTAssertTrue(app.staticTexts[expectedHeadings[name] ?? name].firstMatch.waitForExistence(timeout: 8), name)
            tap(app.buttons["Done"], timeout: 5)
        }
    }

    func testGenerateInstallPersistExportDeleteReimportAndRelaunch() {
        let app = launch(startTab: "create", reset: true)
        tap(app.buttons["Generate on Device"], timeout: 15)

        let install = app.buttons["Install Service Log"]
        scrollToElement(install, app: app, timeout: 25)
        tap(install)
        XCTAssertFalse(install.waitForExistence(timeout: 3))

        tap(app.tabBars.buttons["Library"], timeout: 5)
        waitForButtonCount(named: "Service Log", minimum: 2, in: app, timeout: 10)
        tap(pocketAppButtons(named: "Service Log", in: app).firstMatch, timeout: 10)

        tap(app.buttons["Add Service"], timeout: 8)
        let service = app.textFields["Service"]
        tap(service, timeout: 8)
        service.typeText("Oil Change")
        tap(app.buttons["Save"], timeout: 5)

        app.terminate()
        let persisted = launch(startTab: "library")
        dismissRecoveryIfNeeded(persisted)
        tap(pocketAppButtons(named: "Service Log", in: persisted).firstMatch, timeout: 10)
        let record = persisted.descendants(matching: .any)["record-field-serviceType"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(record.label.localizedCaseInsensitiveContains("Oil Change"))
        tap(persisted.buttons["Done"], timeout: 5)

        pressAndHold(pocketAppButtons(named: "Service Log", in: persisted).firstMatch)
        tap(persisted.buttons["Export"], timeout: 5)
        dismissFileExporter(in: persisted)

        pressAndHold(pocketAppButtons(named: "Service Log", in: persisted).firstMatch)
        tap(persisted.buttons["Delete"], timeout: 5)
        waitForButtonCount(named: "Service Log", exactly: 1, in: persisted, timeout: 8)
        persisted.terminate()

        let reimported = launch(startTab: "library", reimportLastExport: true)
        waitForButtonCount(named: "Service Log", minimum: 2, in: reimported, timeout: 12)
        tap(pocketAppButtons(named: "Service Log", in: reimported).firstMatch, timeout: 10)
        XCTAssertTrue(reimported.staticTexts["Service Log"].firstMatch.waitForExistence(timeout: 8))
        tap(reimported.buttons["Done"], timeout: 5)
        reimported.terminate()

        let relaunched = launch(startTab: "library")
        waitForButtonCount(named: "Service Log", minimum: 2, in: relaunched, timeout: 10)
        tap(pocketAppButtons(named: "Service Log", in: relaunched).firstMatch, timeout: 10)
        XCTAssertTrue(relaunched.staticTexts["Service Log"].firstMatch.waitForExistence(timeout: 8))
        tap(relaunched.buttons["Done"], timeout: 5)
    }

    func testRecoveryFixtureOffersSafeContinuation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PKUITesting", "1",
            "-PKRecoveryFixture", "1",
            "-PKModelMode", "mock",
            "-PKDisableAnimations", "1"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["PocketKernel recovered an interrupted app"].waitForExistence(timeout: 10))
        tap(app.buttons["Continue Safely"], timeout: 5)
        XCTAssertFalse(app.staticTexts["PocketKernel recovered an interrupted app"].waitForExistence(timeout: 2))
    }

    private func launch(
        startTab: String? = nil,
        reset: Bool = false,
        reimportLastExport: Bool = false,
        uiTesting: Bool = true,
        resetOnboarding: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PKModelMode", "mock", "-PKDisableAnimations", "1"]
        if uiTesting { app.launchArguments += ["-PKUITesting", "1"] }
        if let startTab { app.launchArguments += ["-PKStartTab", startTab] }
        if reset { app.launchArguments += ["-PKResetDatabase", "1"] }
        if reimportLastExport { app.launchArguments += ["-PKReimportLastExport", "1"] }
        if resetOnboarding { app.launchArguments += ["-PKResetOnboarding", "1"] }
        app.launch()
        return app
    }

    private func pocketAppButtons(named name: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", name))
    }

    private func lastPocketAppButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        let query = pocketAppButtons(named: name, in: app)
        return query.element(boundBy: max(query.count - 1, 0))
    }

    private func waitForButtonCount(
        named name: String,
        minimum: Int? = nil,
        exactly: Int? = nil,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let count = pocketAppButtons(named: name, in: app).count
            if let exactly, count == exactly { return }
            if let minimum, count >= minimum { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let actual = pocketAppButtons(named: name, in: app).count
        if let exactly { XCTAssertEqual(actual, exactly, "Unexpected button count for \(name)") }
        if let minimum { XCTAssertGreaterThanOrEqual(actual, minimum, "Missing installed \(name)") }
    }

    private func dismissRecoveryIfNeeded(_ app: XCUIApplication) {
        if app.buttons["Continue Safely"].waitForExistence(timeout: 3) {
            tap(app.buttons["Continue Safely"])
        }
    }

    private func dismissFileExporter(in app: XCUIApplication) {
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 8) {
            tap(cancel)
            return
        }
        let navigationCancel = app.navigationBars.buttons["Cancel"].firstMatch
        tap(navigationCancel, timeout: 5)
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
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
    }
}
