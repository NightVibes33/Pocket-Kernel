import XCTest

@MainActor
final class PocketKernelUITests: XCTestCase {
    func testOnboardingExplainsAutomationProduct() {
        let app = launch(uiTesting: false, reset: true, resetOnboarding: true)
        XCTAssertTrue(app.staticTexts["PocketKernel"].waitForExistence(timeout: 12))
        let productDescription = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@",
            "Describe work in plain English."
        )).firstMatch
        XCTAssertTrue(productDescription.exists)
        scrollAndTap(app.buttons["Get Started"], in: app, timeout: 10)
        XCTAssertTrue(app.buttons["Describe an automation"].waitForExistence(timeout: 8))
    }

    func testBuildReviewSaveAndPersistTypedWorkflow() {
        let prompt = "Every weekday at 8 AM, summarize unread customer emails and post the digest to Slack"
        let app = launch(startTab: "create", reset: true)
        scrollAndTap(app.buttons[prompt], in: app, timeout: 12)
        scrollAndTap(app.buttons["Build workflow"], in: app, timeout: 12)

        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Workflow"].exists)
        XCTAssertTrue(app.staticTexts["Gmail · searchMessages"].exists)
        XCTAssertTrue(app.staticTexts["Apple Intelligence · summarize"].exists)
        XCTAssertTrue(app.staticTexts["Slack · postMessage"].exists)
        XCTAssertTrue(app.staticTexts["Approval required"].exists)
        scrollAndTap(app.buttons["Save automation"], in: app, timeout: 12)

        tap(app.tabBars.buttons["Automations"], timeout: 8)
        XCTAssertTrue(app.staticTexts[prompt].waitForExistence(timeout: 10))

        app.terminate()
        let relaunched = launch(startTab: "automations")
        XCTAssertTrue(relaunched.staticTexts[prompt].waitForExistence(timeout: 10))
    }

    func testOAuthConnectionIsNeverFaked() {
        let app = launch(startTab: "connections", reset: true)
        tap(app.buttons["Gmail"], timeout: 10)
        XCTAssertTrue(app.staticTexts["OAuth service not configured"].waitForExistence(timeout: 8))
        let connect = app.buttons["Connect Gmail"]
        XCTAssertTrue(connect.exists)
        XCTAssertFalse(connect.isEnabled)
    }

    private func launch(
        startTab: String? = nil,
        uiTesting: Bool = true,
        reset: Bool = false,
        resetOnboarding: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PKModelMode", "mock", "-PKDisableAnimations", "1"]
        if uiTesting { app.launchArguments += ["-PKUITesting", "1"] }
        if let startTab { app.launchArguments += ["-PKStartTab", startTab] }
        if reset { app.launchArguments += ["-PKResetDatabase", "1"] }
        if resetOnboarding { app.launchArguments += ["-PKResetOnboarding", "1"] }
        app.launch()
        return app
    }

    private func scrollAndTap(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.waitForExistence(timeout: 0.5), element.isHittable {
                element.tap()
                return
            }
            app.swipeUp()
        }
        XCTFail("Element did not become hittable: \(element)")
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)")
        XCTAssertTrue(element.isHittable, "Element is not hittable: \(element)")
        element.tap()
    }
}
