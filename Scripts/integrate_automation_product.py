#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"Unable to patch {label}: expected source block was not found")
    return text.replace(old, new, 1)


def patch_root_view() -> None:
    path = Path("PocketKernel/Shell/RootTabView.swift")
    text = path.read_text()

    text = replace_once(
        text,
        '    @StateObject private var workspace = PKAutomationWorkspace()\n    @State private var selectedTab: RootTab\n',
        '    @StateObject private var workspace = PKAutomationWorkspace()\n    @State private var selectedTab: RootTab\n    @State private var forceOnboarding: Bool\n',
        "RootTabView state",
    )

    old_init = '''    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requested = Self.argumentValue("-PKStartTab", arguments: arguments)
        _selectedTab = State(initialValue: requested == "create" ? .create : requested == "connections" ? .connections : .today)
    }
'''
    new_init = '''    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requested = Self.argumentValue("-PKStartTab", arguments: arguments)
        let initialTab: RootTab = switch requested {
        case "create": .create
        case "automations": .automations
        case "activity": .activity
        case "connections": .connections
        default: .today
        }
        _selectedTab = State(initialValue: initialTab)
        _forceOnboarding = State(initialValue: arguments.contains("-PKResetOnboarding"))
    }
'''
    text = replace_once(text, old_init, new_init, "RootTabView initialization")

    old_cover = '''        .fullScreenCover(isPresented: Binding(
            get: { !onboardingComplete && !ProcessInfo.processInfo.arguments.contains("-PKUITesting") },
            set: { if !$0 { onboardingComplete = true } }
        )) {
            AutomationOnboardingView { onboardingComplete = true }
        }
'''
    new_cover = '''        .fullScreenCover(isPresented: Binding(
            get: {
                forceOnboarding
                    || (!onboardingComplete && !ProcessInfo.processInfo.arguments.contains("-PKUITesting"))
            },
            set: {
                if !$0 {
                    onboardingComplete = true
                    forceOnboarding = false
                }
            }
        )) {
            AutomationOnboardingView {
                onboardingComplete = true
                forceOnboarding = false
            }
        }
'''
    text = replace_once(text, old_cover, new_cover, "automation onboarding")

    old_button = '''                    Button {
                        workspace.compilePrompt()
                        showingDraft = workspace.draft != nil
                    } label: {
'''
    new_button = '''                    Button {
                        Task {
                            await workspace.compilePrompt()
                            showingDraft = workspace.draft != nil
                        }
                    } label: {
'''
    text = replace_once(text, old_button, new_button, "async automation generation button")

    text = replace_once(
        text,
        '                    .disabled(workspace.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)\n',
        '                    .disabled(\n                        workspace.isWorking\n                            || workspace.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty\n                    )\n',
        "generation button state",
    )

    text = replace_once(
        text,
        'private func triggerDescription(_ trigger: PKTrigger) -> String {\n    switch trigger.kind {',
        'private func triggerDescription(_ trigger: PKTrigger) -> String {\n    return switch trigger.kind {',
        "trigger description return",
    )

    path.write_text(text)


def patch_automation_core() -> None:
    path = Path("PocketKernel/Runtime/AutomationCore.swift")
    text = path.read_text()

    text = replace_once(
        text,
        '    private let compiler = PKAutomationCompiler()\n    private let validator = PKAutomationValidator()\n',
        '    private let compiler = PKAutomationCompiler()\n    private let foundationGenerator = PKFoundationAutomationGenerator()\n    private let validator = PKAutomationValidator()\n',
        "Foundation automation generator dependency",
    )

    text = replace_once(
        text,
        '        storageURL = directory.appending(path: "workspace.json")\n        load()\n',
        '        storageURL = directory.appending(path: "workspace.json")\n        if ProcessInfo.processInfo.arguments.contains("-PKResetDatabase") {\n            try? FileManager.default.removeItem(at: storageURL)\n        }\n        load()\n',
        "automation workspace reset",
    )

    old_compile = '''    func compilePrompt() {
        do {
            let result = try compiler.compile(prompt)
            draft = result
            validationIssues = validator.validate(result)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
'''
    new_compile = '''    func compilePrompt() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result: PKAutomation
            if modelMode == "mock" || modelMode == "local" {
                result = try compiler.compile(prompt)
            } else {
                do {
                    result = try await foundationGenerator.generate(prompt)
                } catch {
                    result = try compiler.compile(prompt)
                }
            }
            draft = result
            validationIssues = validator.validate(result)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var modelMode: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PKModelMode"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1].lowercased()
    }
'''
    text = replace_once(text, old_compile, new_compile, "async Foundation Models workflow compilation")

    path.write_text(text)


def patch_project() -> None:
    path = Path("PocketKernel.xcodeproj/project.pbxproj")
    text = path.read_text()

    build = (
        'B10000000000000000000026 /* FoundationAutomationGenerator.swift in Sources */ = '
        '{isa = PBXBuildFile; fileRef = F10000000000000000000031; };'
    )
    reference = (
        'F10000000000000000000031 = {isa = PBXFileReference; '
        'lastKnownFileType = sourcecode.swift; path = FoundationAutomationGenerator.swift; '
        'sourceTree = "<group>"; };'
    )
    if build not in text:
        text = text.replace("/* End PBXBuildFile section */", f"\t\t{build}\n/* End PBXBuildFile section */")
    if reference not in text:
        text = text.replace("/* End PBXFileReference section */", f"\t\t{reference}\n/* End PBXFileReference section */")

    old_group = (
        'G10000000000000000000013 = {isa = PBXGroup; path = Builder; sourceTree = "<group>"; '
        'children = (F10000000000000000000004,F10000000000000000000005,); };'
    )
    new_group = (
        'G10000000000000000000013 = {isa = PBXGroup; path = Builder; sourceTree = "<group>"; '
        'children = (F10000000000000000000004,F10000000000000000000005,F10000000000000000000031,); };'
    )
    text = replace_once(text, old_group, new_group, "Foundation automation generator project group")

    old_sources = (
        'B10000000000000000000022,B10000000000000000000025,); '
        'runOnlyForDeploymentPostprocessing = 0; };'
    )
    new_sources = (
        'B10000000000000000000022,B10000000000000000000025,'
        'B10000000000000000000026,); runOnlyForDeploymentPostprocessing = 0; };'
    )
    text = replace_once(text, old_sources, new_sources, "Foundation automation generator source phase")

    path.write_text(text)


def replace_ui_tests() -> None:
    Path("PocketKernelUITests/PocketKernelUITests.swift").write_text(r'''import XCTest

@MainActor
final class PocketKernelUITests: XCTestCase {
    func testOnboardingExplainsAutomationProduct() {
        let app = launch(uiTesting: false, reset: true, resetOnboarding: true)
        XCTAssertTrue(app.staticTexts["PocketKernel"].waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.staticTexts[
                "Describe work in plain English. PocketKernel builds a typed automation, shows every step, asks before acting, and runs the approved workflow predictably."
            ].exists
        )
        tap(app.buttons["Get Started"])
        XCTAssertTrue(app.buttons["Describe an automation"].waitForExistence(timeout: 8))
    }

    func testBuildReviewSaveAndPersistTypedWorkflow() {
        let prompt = "Every weekday at 8 AM, summarize unread customer emails and post the digest to Slack"
        let app = launch(startTab: "create", reset: true)
        let editor = app.textViews["Automation description"]
        tap(editor, timeout: 10)
        editor.typeText(prompt)
        tap(app.buttons["Build workflow"], timeout: 8)

        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Workflow"].exists)
        XCTAssertTrue(app.staticTexts["Gmail · searchMessages"].exists)
        XCTAssertTrue(app.staticTexts["Apple Intelligence · summarize"].exists)
        XCTAssertTrue(app.staticTexts["Slack · postMessage"].exists)
        XCTAssertTrue(app.staticTexts["Approval required"].exists)
        tap(app.buttons["Save automation"], timeout: 8)

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

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)")
        XCTAssertTrue(element.isHittable, "Element is not hittable: \(element)")
        element.tap()
    }
}
''')


def append_unit_tests() -> None:
    path = Path("PocketKernelTests/PocketKernelTests.swift")
    text = path.read_text()
    if "final class AutomationPlatformTests: XCTestCase" in text:
        return
    text += r'''

final class AutomationPlatformTests: XCTestCase {
    func testCompilerCreatesDifferentRegisteredWorkflows() throws {
        let compiler = PKAutomationCompiler()
        let digest = try compiler.compile(
            "Every weekday at 8 AM, summarize unread customer emails and post the digest to Slack"
        )
        let alert = try compiler.compile(
            "Monitor https://api.example.org/price and alert me when the price drops below 20"
        )

        XCTAssertEqual(digest.trigger.kind, .schedule)
        XCTAssertEqual(digest.trigger.configuration["time"], "08:00")
        XCTAssertTrue(digest.steps.contains { $0.service == .gmail && $0.operation == "searchMessages" })
        XCTAssertTrue(digest.steps.contains { $0.service == .intelligence && $0.operation == "summarize" })
        XCTAssertTrue(digest.steps.contains { $0.service == .slack && $0.operation == "postMessage" })
        XCTAssertEqual(alert.trigger.kind, .webCondition)
        XCTAssertTrue(alert.steps.contains { $0.service == .http && $0.operation == "getJSON" })
        XCTAssertNotEqual(digest.steps.map(\.operation), alert.steps.map(\.operation))
        XCTAssertFalse(PKAutomationValidator().validate(digest).contains { $0.severity == .error })
        XCTAssertFalse(PKAutomationValidator().validate(alert).contains { $0.severity == .error })
    }

    func testExternalMutationsAlwaysRequireApproval() throws {
        let automation = try PKAutomationCompiler().compile(
            "When an urgent Gmail arrives, draft a reply and notify me"
        )
        let mutations = automation.steps.filter(\.mutatesExternalState)
        XCTAssertFalse(mutations.isEmpty)
        XCTAssertTrue(mutations.allSatisfy { $0.approval == .externalMutation })
    }

    func testValidatorRejectsUnknownOperationsAndUnapprovedMutations() throws {
        var automation = try PKAutomationCompiler().compile("Post a digest to Slack")
        automation.steps[0].operation = "inventedOperation"
        XCTAssertTrue(
            PKAutomationValidator().validate(automation).contains { $0.code == "operation.unsupported" }
        )

        automation = try PKAutomationCompiler().compile("Notify me with the result")
        let mutationIndex = try XCTUnwrap(automation.steps.firstIndex(where: \.mutatesExternalState))
        automation.steps[mutationIndex].approval = .none
        XCTAssertTrue(
            PKAutomationValidator().validate(automation).contains { $0.code == "approval.required" }
        )
    }

    func testDeterministicExecutorStopsForApproval() async throws {
        let automation = try PKAutomationCompiler().compile("Notify me with a daily summary")
        let executor = PKDeterministicExecutor()
        let waiting = await executor.execute(automation, approved: false)
        XCTAssertEqual(waiting.state, .waitingForApproval)
        let approved = await executor.execute(automation, approved: true)
        XCTAssertEqual(approved.state, .succeeded)
    }
}
'''
    path.write_text(text)


def main() -> None:
    patch_root_view()
    patch_automation_core()
    patch_project()
    replace_ui_tests()
    append_unit_tests()


if __name__ == "__main__":
    main()
