import XCTest

@MainActor final class PocketKernelUITests: XCTestCase {
    private enum ScrollDirection { case up, down }

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

        for name in ["Habit Tracker", "Inventory List", "Quick Journal", "Service Log", "Task Board"] {
            let installButton = lastPocketAppButton(named: name, in: app)
            scrollToElement(installButton, app: app, timeout: 10)
            tap(installButton, timeout: 10)
            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 15), name)
            XCTAssertTrue(app.staticTexts[expectedHeadings[name] ?? name].firstMatch.exists, name)
            tap(done)
        }
    }

    func testGenerateInstallPersistExportDeleteReimportAndRelaunch() {
        let app = launch(startTab: "create", reset: true)
        let generate = app.buttons["Generate on Device"]
        scrollToElement(generate, app: app, timeout: 15)
        tap(generate, timeout: 15)

        let install = app.buttons["Install Service Log"]
        scrollToElement(install, app: app, timeout: 25)
        tap(install)
        XCTAssertFalse(install.waitForExistence(timeout: 3))

        tap(app.tabBars.buttons["Library"], timeout: 5)
        waitForButtonCount(named: "Service Log", minimum: 2, in: app, timeout: 10)
        tap(generatedServiceLogButton(in: app), timeout: 10)

        tap(app.buttons["Add Service"], timeout: 8)
        let service = app.textFields["Service"]
        tap(service, timeout: 8)
        service.typeText("Oil Change")
        tap(app.buttons["Save"], timeout: 5)
        tap(app.buttons["Service History"], timeout: 8)

        let committedRecord = serviceTypeRecord(in: app)
        XCTAssertTrue(committedRecord.waitForExistence(timeout: 15))
        XCTAssertTrue(committedRecord.label.localizedCaseInsensitiveContains("Oil Change"))

        app.terminate()
        let persisted = launch(startTab: "library")
        dismissRecoveryIfNeeded(persisted)
        tap(generatedServiceLogButton(in: persisted), timeout: 10)
        tap(persisted.buttons["Service History"], timeout: 8)
        let record = serviceTypeRecord(in: persisted)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(record.label.localizedCaseInsensitiveContains("Oil Change"))
        tap(persisted.buttons["Done"], timeout: 5)

        pressAndHold(generatedServiceLogButton(in: persisted))
        tap(persisted.buttons["Export"], timeout: 5)
        dismissFileExporter(in: persisted)

        swipeToDelete(generatedServiceLogButton(in: persisted), app: persisted)
        waitForButtonCount(named: "Service Log", exactly: 1, in: persisted, timeout: 8)
        persisted.terminate()

        let reimported = launch(startTab: "library", reimportLastExport: true)
        waitForButtonCount(named: "Service Log", minimum: 2, in: reimported, timeout: 12)
        tap(generatedServiceLogButton(in: reimported), timeout: 10)
        XCTAssertTrue(reimported.staticTexts["Service Log"].firstMatch.waitForExistence(timeout: 8))
        tap(reimported.buttons["Done"], timeout: 5)
        reimported.terminate()

        let relaunched = launch(startTab: "library")
        waitForButtonCount(named: "Service Log", minimum: 2, in: relaunched, timeout: 10)
        tap(generatedServiceLogButton(in: relaunched), timeout: 10)
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

    private func generatedServiceLogButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@",
            "Service Log",
            "Track vehicle maintenance, mileage, cost, and notes."
        )).firstMatch
    }

    private func serviceTypeRecord(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS[c] %@",
            "component-history-list",
            "Oil Change"
        )).firstMatch
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
        XCTAssertTrue(element.isHittable, "Element is not hittable: \(element)")
        element.tap()
    }

    private func scrollToElement(
        _ element: XCUIElement,
        app: XCUIApplication,
        timeout: TimeInterval,
        direction: ScrollDirection = .up
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let windowFrame = app.windows.firstMatch.frame
        let topLimit = windowFrame.minY + 100
        let bottomLimit = windowFrame.maxY - 150

        while Date() < deadline {
            if element.waitForExistence(timeout: 0.5) {
                let middle = element.frame.midY
                if element.isHittable, middle >= topLimit, middle <= bottomLimit { return }
                if middle > bottomLimit {
                    app.swipeUp()
                } else if middle < topLimit {
                    app.swipeDown()
                } else {
                    switch direction {
                    case .up: app.swipeUp()
                    case .down: app.swipeDown()
                    }
                }
            } else {
                switch direction {
                case .up: app.swipeUp()
                case .down: app.swipeDown()
                }
            }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func pressAndHold(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        XCTAssertTrue(element.isHittable)
        element.press(forDuration: 1.2)
    }

    private func swipeToDelete(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        XCTAssertTrue(element.isHittable)
        element.swipeLeft()
        tap(app.buttons["Delete"], timeout: 5)
    }
}
