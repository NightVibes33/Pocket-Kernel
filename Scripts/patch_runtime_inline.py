from pathlib import Path
import subprocess


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old in source:
        return source.replace(old, new, 1)
    if new in source:
        return source
    raise SystemExit(f"{label} not found")

# Expose a visible, observable completion state for template installs.
environment_path = Path("PocketKernel/App/AppEnvironment.swift")
environment = environment_path.read_text()
environment = replace_once(
    environment,
    "    var generationError: String?\n    var isGenerating = false\n",
    "    var generationError: String?\n    var installStatus: String?\n    var isGenerating = false\n",
    "installStatus property",
)
environment = replace_once(
    environment,
    '''    func installTemplate(_ template: BundledTemplate) async {
        guard let store else { return }
        do {
            try await store.install(template.package)
            try await store.log(appID: template.id, level: .info, category: "install", message: "Installed built-in package \\(template.manifest.name).")
            await load()
        } catch { startupError = error.localizedDescription }
    }
''',
    '''    func installTemplate(_ template: BundledTemplate) async {
        guard let store else { return }
        installStatus = nil
        do {
            try await store.install(template.package)
            try await store.log(appID: template.id, level: .info, category: "install", message: "Installed built-in package \\(template.manifest.name).")
            await load()
            installStatus = "Installed \\(template.manifest.name)."
        } catch { startupError = error.localizedDescription }
    }
''',
    "template install completion",
)
environment_path.write_text(environment)

# Give installed and template rows stable accessibility identities and surface completion.
root_path = Path("PocketKernel/Shell/RootTabView.swift")
root = root_path.read_text()
root = replace_once(
    root,
    '''            List {
                Section("Installed") {
''',
    '''            List {
                if let installStatus = environment.installStatus {
                    Section {
                        Label(installStatus, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Section("Installed") {
''',
    "library install status",
)
root = replace_once(
    root,
    '''                        Button { Task { await environment.installTemplate(template) } } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(template.manifest.name)
                                    Text(template.manifest.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: template.manifest.icon.symbol) }
                        }
''',
    '''                        Button { Task { await environment.installTemplate(template) } } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(template.manifest.name)
                                    Text(template.manifest.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: template.manifest.icon.symbol) }
                        }
                        .accessibilityIdentifier("template-app-\\(template.manifest.name)")
''',
    "template accessibility identifier",
)
root = replace_once(
    root,
    '''        .buttonStyle(.plain)
        .swipeActions {
''',
    '''        .buttonStyle(.plain)
        .accessibilityIdentifier("installed-app-\\(app.manifest.name)")
        .swipeActions {
''',
    "installed accessibility identifier",
)

# Route create-record actions to an existing declarative record-form screen when available.
old_run_action = '''    private func runAction(_ id: String) {
        guard !previewOnly, let action = manifest.actions.first(where: { $0.id == id }) else { return }
        pendingActionID = id
        if action.kind == .createRecord,
           let target = action.target,
           let collection = manifest.collections.first(where: { $0.id == target }) {
            formValues = Dictionary(uniqueKeysWithValues: collection.fields.map { ($0.id, $0.defaultValue) })
            editingCollection = collection
            return
        }
        execute(id, form: [:])
    }
'''
new_run_action = '''    private func runAction(_ id: String) {
        guard !previewOnly, let action = manifest.actions.first(where: { $0.id == id }) else { return }
        pendingActionID = id
        if action.kind == .createRecord,
           let target = action.target,
           let collection = manifest.collections.first(where: { $0.id == target }) {
            formValues = Dictionary(uniqueKeysWithValues: collection.fields.map { ($0.id, $0.defaultValue) })
            if screen.map({ containsRecordForm($0.components, actionID: id) }) == true {
                execute(id, form: [:])
                return
            }
            if let formScreen = manifest.screens.first(where: { containsRecordForm($0.components, actionID: id) }) {
                for field in collection.fields {
                    runtimeValues["form.\\(field.id)"] = field.defaultValue
                }
                selectedScreenID = formScreen.id
                return
            }
            editingCollection = collection
            return
        }
        execute(id, form: [:])
    }

    private func containsRecordForm(_ components: [ComponentSpec], actionID: String) -> Bool {
        components.contains { component in
            (component.kind == .recordForm && component.actionID == actionID)
                || containsRecordForm(component.children, actionID: actionID)
        }
    }
'''
root = replace_once(root, old_run_action, new_run_action, "declarative form routing")
root_path.write_text(root)

# A recordForm component with an action now owns its Save button.
renderer_path = Path("PocketKernel/Runtime/ComponentRenderer.swift")
renderer = renderer_path.read_text()
renderer = replace_once(
    renderer,
    '''            VStack(alignment: .leading, spacing: 12) {
                ForEach(collection.fields) { field in fieldEditor(field) }
                ForEach(component.children) { childRenderer($0) }
            }
''',
    '''            VStack(alignment: .leading, spacing: 12) {
                ForEach(collection.fields) { field in fieldEditor(field) }
                ForEach(component.children) { childRenderer($0) }
                if let actionID = component.actionID {
                    Button("Save") { runAction(actionID) }
                        .buttonStyle(.borderedProminent)
                }
            }
''',
    "record form Save button",
)
renderer_path.write_text(renderer)

# Tests wait in-place for completion and use stable identifiers instead of lazy label counts.
tests_path = Path("PocketKernelUITests/PocketKernelUITests.swift")
tests = tests_path.read_text()
old_built_in = '''        for name in ["Task Board", "Habit Tracker", "Quick Journal", "Inventory List", "Service Log"] {
            let installButton = lastPocketAppButton(named: name, in: app)
            scrollToElement(installButton, app: app, timeout: 12)
            tap(installButton, timeout: 10)

            tap(app.tabBars.buttons["Activity"], timeout: 5)
            XCTAssertTrue(
                app.staticTexts["Installed built-in package \\(name)."].waitForExistence(timeout: 15),
                name
            )
            tap(app.tabBars.buttons["Library"], timeout: 5)

            let installedButton = installedPocketAppButton(named: name, in: app)
            scrollToElement(installedButton, app: app, timeout: 15, direction: .down)
            tap(installedButton, timeout: 8)
'''
new_built_in = '''        for name in ["Task Board", "Habit Tracker", "Quick Journal", "Inventory List", "Service Log"] {
            let installButton = templatePocketAppButton(named: name, in: app)
            scrollToElement(installButton, app: app, timeout: 12)
            tap(installButton, timeout: 10)
            XCTAssertTrue(app.staticTexts["Installed \\(name)."].waitForExistence(timeout: 15), name)

            let installedButton = installedPocketAppButton(named: name, in: app)
            scrollToElement(installedButton, app: app, timeout: 15, direction: .down)
            tap(installedButton, timeout: 8)
'''
tests = replace_once(tests, old_built_in, new_built_in, "built-in completion wait")
tests = replace_once(
    tests,
    '''    private func pocketAppButtons(named name: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", name))
    }

    private func installedPocketAppButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", name, "v1 •")
        ).firstMatch
    }

    private func lastPocketAppButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        let query = pocketAppButtons(named: name, in: app)
        return query.element(boundBy: max(query.count - 1, 0))
    }
''',
    '''    private func installedPocketAppButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["installed-app-\\(name)"]
    }

    private func templatePocketAppButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["template-app-\\(name)"]
    }
''',
    "stable app queries",
)
tests_path.write_text(tests)

subprocess.run(
    [
        "git",
        "add",
        str(environment_path),
        str(renderer_path),
        str(tests_path),
    ],
    check=True,
)
