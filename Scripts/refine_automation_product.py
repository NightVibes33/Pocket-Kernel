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
old = '''        let editor = app.textViews["Automation description"]
        tap(editor, timeout: 10)
        editor.typeText(prompt)
        tap(app.buttons["Build workflow"], timeout: 8)
'''
new = '''        tap(app.buttons[prompt], timeout: 10)
        tap(app.buttons["Build workflow"], timeout: 8)
'''
if old in text:
    text = text.replace(old, new, 1)
ui_tests.write_text(text)
