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

        for name in ["Task Board", "Habit Tracker", "Quick Journal", "Inventory List", "Service Log"] {
            let installButton = templatePocketAppButton(named: name, in: app)
            scrollToElement(installButton, app: app, timeout: 12)
            tap(installButton, timeout: 10)
            XCTAssertTrue(app.staticTexts["Installed \(name)."].waitForExistence(timeout: 15), name)

            let installedButton = installedPocketAppButton(named: name, in: app)
            scrollToElement(installedButton, app: app, timeout: 15, direction: .down)
            tap(installedButton, timeout: 8)

            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 12), name)
            XCTAssertTrue(app.staticTexts[expectedHeadings[name] ?? name].firstMatch.exists, name)
            tap(done, timeout: 5)
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
        XCTAssertTrue(app.staticTexts["Installed Service Log."].waitForExistence(timeout: 15))

        tap(app.tabBars.buttons["Library"], timeout: 5)
        let installed = installedPocketAppButton(named: "Service Log", in: app)
        scrollToElement(installed, app: app, timeout: 15, direction: .down)
        tap(installed, timeout: 10)

        tap(app.buttons["Add Service"], timeout: 8)
        let service = app.textFields["Service"]
        tap(service, timeout: 8)
        service.typeText("Oil Change")
        tap(app.buttons["Save"], timeout: 5)

        app.terminate()
        let persisted = launch(startTab: "library")
        dismissRecoveryIfNeeded(persisted)
        let persistedApp = installedPocketAppButton(named: "Service Log", in: persisted)
        scrollToElement(persistedApp, app: persisted, timeout: 12, direction: .down)
        tap(persistedApp, timeout: 10)
        let record = persisted.descendants(matching: .any)["record-field-serviceType"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(record.label.localizedCaseInsensitiveContains("Oil Change"))
        tap(persisted.buttons["Done"], timeout: 5)

        let exportApp = installedPocketAppButton(named: "Service Log", in: persisted)
        scrollToElement(exportApp, app: persisted, timeout: 10, direction: .down)
        pressAndHold(exportApp)
        tap(persisted.buttons["Export"], timeout: 5)
        dismissFileExporter(in: persisted)

        let deleteApp = installedPocketAppButton(named: "Service Log", in: persisted)
        pressAndHold(deleteApp)
        tap(persisted.buttons["Delete"], timeout: 5)
        XCTAssertFalse(installedPocketAppButton(named: "Service Log", in: persisted).waitForExistence(timeout: 8))
        persisted.terminate()

        let reimported = launch(startTab: "library", reimportLastExport: true)
        let reimportedApp = installedPocketAppButton(named: "Service Log", in: reimported)
        scrollToElement(reimportedApp, app: reimported, timeout: 15, direction: .down)
        tap(reimportedApp, timeout: 10)
        XCTAssertTrue(reimported.buttons["Done"].waitForExistence(timeout: 8))
        tap(reimported.buttons["Done"], timeout: 5)
        reimported.terminate()

        let relaunched = launch(startTab: "library")
        let relaunchedApp = installedPocketAppButton(named: "Service Log", in: relaunched)
        scrollToElement(relaunchedApp, app: relaunched, timeout: 15, direction: .down)
        tap(relaunchedApp, timeout: 10)
        XCTAssertTrue(relaunched.buttons["Done"].waitForExistence(timeout: 8))
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

    private func installedPocketAppButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["installed-app-\(name)"]
    }

    private func templatePocketAppButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["template-app-\(name)"]
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

    private func scrollToElement(
        _ element: XCUIElement,
        app: XCUIApplication,
        timeout: TimeInterval,
        direction: ScrollDirection = .up
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.waitForExistence(timeout: 0.5), element.isHittable { return }
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func pressAndHold(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
    }
}
