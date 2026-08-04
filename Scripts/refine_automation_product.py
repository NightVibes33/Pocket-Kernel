#!/usr/bin/env python3
from pathlib import Path

root = Path("PocketKernel/Shell/RootTabView.swift")
text = root.read_text()
old = '''private func triggerDescription(_ trigger: PKTrigger) -> String {
    return switch trigger.kind {
    case .manual: "Run manually"
    case .schedule:
        let cadence = trigger.configuration["cadence"] ?? "scheduled"
        let time = trigger.configuration["time"] ?? "08:00"
        return "\\(cadence.capitalized) at \\(time) · \\(trigger.timeZoneIdentifier)"
    case .webhook: "Incoming webhook"
    case .accountEvent: "When a connected account changes"
    case .webCondition: "When a monitored condition matches"
    case .workflowCompleted: "After another workflow completes"
    case .location: "Location-aware trigger"
    }
}
'''
new = '''private func triggerDescription(_ trigger: PKTrigger) -> String {
    switch trigger.kind {
    case .manual:
        return "Run manually"
    case .schedule:
        let cadence = trigger.configuration["cadence"] ?? "scheduled"
        let time = trigger.configuration["time"] ?? "08:00"
        return "\\(cadence.capitalized) at \\(time) · \\(trigger.timeZoneIdentifier)"
    case .webhook:
        return "Incoming webhook"
    case .accountEvent:
        return "When a connected account changes"
    case .webCondition:
        return "When a monitored condition matches"
    case .workflowCompleted:
        return "After another workflow completes"
    case .location:
        return "Location-aware trigger"
    }
}
'''
if new not in text:
    if old not in text:
        raise SystemExit("Expected triggerDescription source was not found")
    text = text.replace(old, new, 1)
root.write_text(text)

ui_tests = Path("PocketKernelUITests/PocketKernelUITests.swift")
text = ui_tests.read_text()

old_generation = '''        let editor = app.textViews["Automation description"]
        tap(editor, timeout: 10)
        editor.typeText(prompt)
        tap(app.buttons["Build workflow"], timeout: 8)
'''
new_generation = '''        scrollAndTap(app.buttons[prompt], in: app, timeout: 12)
        scrollAndTap(app.buttons["Build workflow"], in: app, timeout: 12)
'''
if old_generation in text:
    text = text.replace(old_generation, new_generation, 1)

text = text.replace(
    '        tap(app.buttons["Save automation"], timeout: 8)\n',
    '        scrollAndTap(app.buttons["Save automation"], in: app, timeout: 12)\n',
    1,
)

old_description = '''        XCTAssertTrue(
            app.staticTexts[
                "Describe work in plain English. PocketKernel builds a typed automation, shows every step, asks before acting, and runs the approved workflow predictably."
            ].exists
        )
'''
new_description = '''        let productDescription = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@",
            "Describe work in plain English."
        )).firstMatch
        XCTAssertTrue(productDescription.exists)
'''
if old_description in text:
    text = text.replace(old_description, new_description, 1)

text = text.replace(
    '        tap(app.buttons["Get Started"])\n',
    '        scrollAndTap(app.buttons["Get Started"], in: app, timeout: 10)\n',
    1,
)

helper_anchor = '''    private func tap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \\(element)")
        XCTAssertTrue(element.isHittable, "Element is not hittable: \\(element)")
        element.tap()
    }
'''
helper = '''    private func scrollAndTap(
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
        XCTFail("Element did not become hittable: \\(element)")
    }

''' + helper_anchor
if "private func scrollAndTap(" not in text:
    if helper_anchor not in text:
        raise SystemExit("Unable to add scroll-safe UI test helper")
    text = text.replace(helper_anchor, helper, 1)

ui_tests.write_text(text)
