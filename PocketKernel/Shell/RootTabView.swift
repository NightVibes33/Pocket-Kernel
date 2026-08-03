import FoundationModels
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum RootTab: Hashable { case home, create, library, activity, settings }

struct RootTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("PKOnboardingComplete") private var onboardingComplete = false
    @State private var selectedTab: RootTab
    @State private var recoveryExportDocument: PocketAppDocument?
    @State private var exportingRecoveryApp = false
    @State private var recoveryError: String?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requested = Self.argumentValue("-PKStartTab", arguments: arguments)
        _selectedTab = State(initialValue: requested == "create" ? .create : requested == "library" ? .library : .home)
    }

    var body: some View {
        @Bindable var environment = environment
        TabView(selection: $selectedTab) {
            HomeView(create: { selectedTab = .create }).tag(RootTab.home).tabItem { Label("Home", systemImage: "house.fill") }
            CreateView().tag(RootTab.create).tabItem { Label("Create", systemImage: "sparkles") }
            LibraryView().tag(RootTab.library).tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
            ActivityView().tag(RootTab.activity).tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            SettingsView().tag(RootTab.settings).tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .fullScreenCover(isPresented: Binding(get: {
            !onboardingComplete && !ProcessInfo.processInfo.arguments.contains("-PKUITesting")
        }, set: { if !$0 { onboardingComplete = true } })) {
            OnboardingView { onboardingComplete = true }
        }
        .sheet(item: $environment.pendingOpenApp) { manifest in NavigationStack { RuntimeView(manifest: manifest) } }
        .fileExporter(
            isPresented: $exportingRecoveryApp,
            document: recoveryExportDocument,
            contentType: .pocketApp,
            defaultFilename: "Recovered-Pocket-App"
        ) { result in
            if case .failure(let error) = result { recoveryError = error.localizedDescription }
        }
        .alert("PocketKernel Error", isPresented: Binding(get: { environment.startupError != nil }, set: { if !$0 { environment.clearError() } })) {
            Button("OK") { environment.clearError() }
        } message: { Text(environment.startupError ?? "Unknown error") }
        .alert("Recovery Export Error", isPresented: Binding(get: { recoveryError != nil }, set: { if !$0 { recoveryError = nil } })) {
            Button("OK") { recoveryError = nil }
        } message: { Text(recoveryError ?? "Unknown error") }
        .confirmationDialog(
            "PocketKernel recovered an interrupted app",
            isPresented: Binding(get: { environment.lifecycle.recoveryRequired }, set: { if !$0 { environment.lifecycle.dismissRecovery() } }),
            titleVisibility: .visible
        ) {
            recoveryActions
        } message: { Text(environment.lifecycle.lastRuntimeEvent) }
    }

    @ViewBuilder private var recoveryActions: some View {
        if let id = environment.lifecycle.affectedAppID, let app = environment.installed.first(where: { $0.id == id }) {
            Button("Reopen \(app.manifest.name)") { Task { environment.lifecycle.resumeSession(); await environment.open(app) } }
            Button("Export App and Records") { prepareRecoveryExport(app.manifest) }
            Button(app.disabled ? "Re-enable App" : "Disable App") { Task { await environment.setDisabled(!app.disabled, id: id); environment.lifecycle.dismissRecovery() } }
            Button("Roll Back App") { Task { await environment.rollback(id); environment.lifecycle.dismissRecovery() } }
            Button("Delete App", role: .destructive) { Task { await environment.delete(id); environment.lifecycle.dismissRecovery() } }
        }
        Button("Continue Safely") { environment.lifecycle.dismissRecovery() }
    }

    private func prepareRecoveryExport(_ manifest: MicroAppManifest) {
        Task {
            do {
                recoveryExportDocument = PocketAppDocument(data: try await environment.exportPackage(manifest))
                exportingRecoveryApp = true
            } catch { recoveryError = error.localizedDescription }
        }
    }

    private static func argumentValue(_ key: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

private struct OnboardingView: View {
    var complete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "square.grid.3x3.square").font(.system(size: 76)).foregroundStyle(.tint)
                Text("PocketKernel").font(.largeTitle.bold())
                Text("Describe, preview, install, and run multiple private native micro-apps without writing code.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Label("On-device generation with Apple Intelligence", systemImage: "apple.intelligence")
                    Label("Typed native SwiftUI components and actions", systemImage: "checkmark.shield")
                    Label("No JavaScript, JIT, downloaded binaries, or private APIs", systemImage: "lock.fill")
                    Label("Local packages, records, permissions, export, and recovery", systemImage: "internaldrive")
                }.frame(maxWidth: 460, alignment: .leading)
                Spacer()
                Button("Get Started", action: complete).buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(28).navigationTitle("Welcome")
        }
    }
}

private struct ModelStatusView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Label(environment.modelState.title, systemImage: environment.modelState == .available ? "apple.intelligence" : "square.grid.2x2")
            .font(.caption)
            .foregroundStyle(environment.modelState == .available ? .green : .secondary)
            .accessibilityLabel("\(environment.modelState.title). \(environment.modelState.detail)")
    }
}

private struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var search = ""
    var create: () -> Void

    private var visibleApps: [InstalledAppInfo] {
        let apps = environment.installed.filter { !$0.disabled }
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.manifest.name.localizedCaseInsensitiveContains(search)
                || $0.manifest.summary.localizedCaseInsensitiveContains(search)
        }
    }

    private var favorites: [InstalledAppInfo] { visibleApps.filter(\.favorite) }
    private var recent: [InstalledAppInfo] { Array(visibleApps.filter { !$0.favorite }.prefix(8)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusCard
                    Button(action: create) {
                        Label("Create a Pocket App", systemImage: "plus.circle.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                    }.buttonStyle(.borderedProminent)
                    if !favorites.isEmpty { appSection("Favorites", apps: favorites) }
                    appSection(search.isEmpty ? "Recently Used" : "Search Results", apps: search.isEmpty ? recent : visibleApps)
                }.padding()
            }
            .searchable(text: $search, prompt: "Search Pocket Apps")
            .navigationTitle("PocketKernel")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ModelStatusView() } }
            .refreshable { await environment.load() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(environment.modelState.title).font(.headline)
            Text(environment.modelState.detail).font(.caption).foregroundStyle(.secondary)
            HStack {
                Label("\(environment.installed.count) apps", systemImage: "square.grid.2x2")
                Spacer()
                Label(ByteCountFormatter.string(fromByteCount: environment.storageBytes, countStyle: .file), systemImage: "internaldrive")
            }.font(.caption)
        }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private func appSection(_ title: String, apps: [InstalledAppInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            if apps.isEmpty {
                ContentUnavailableView("No Pocket Apps", systemImage: "square.grid.2x2", description: Text("Create or install an app to see it here."))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                    ForEach(apps) { app in
                        Button { Task { await environment.open(app) } } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: app.manifest.icon.symbol).font(.title)
                                    Spacer()
                                    if app.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                                }
                                Text(app.manifest.name).font(.headline).lineLimit(1)
                                Text(app.manifest.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 125, alignment: .leading)
                            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(app.manifest.name), \(app.manifest.summary)")
                    }
                }
            }
        }
    }
}

private struct CreateView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prompt = "Create a car maintenance tracker with mileage, service date, cost, notes, and reminders for the next service."
    @State private var selectedCapabilities: Set<PocketCapability> = []
    @State private var showingManualEditor = false
    private let suggestions = [
        "Habit tracker with daily check-ins",
        "Inventory manager with quantities and locations",
        "Private journal with dated entries",
        "Task board with status and due dates"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Describe your app") {
                    TextEditor(text: $prompt).frame(minHeight: 120).accessibilityLabel("App description")
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { prompt = suggestion }.buttonStyle(.bordered)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                Section("Capabilities") {
                    ForEach(PocketCapability.allCases, id: \.self) { capability in
                        Toggle(capability.displayName, isOn: Binding(
                            get: { selectedCapabilities.contains(capability) },
                            set: { enabled in
                                if enabled { selectedCapabilities.insert(capability) }
                                else { selectedCapabilities.remove(capability) }
                            }
                        ))
                    }
                }
                Section {
                    Button { Task { await environment.generate(prompt, capabilities: selectedCapabilities) } } label: {
                        if environment.isGenerating { Label("Generating and validating…", systemImage: "hourglass") }
                        else { Label("Generate on Device", systemImage: "apple.intelligence") }
                    }.disabled(environment.isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Open Manual Builder", systemImage: "slider.horizontal.3") { ensureManualDraft(); showingManualEditor = true }
                }
                if let message = environment.generationError {
                    Section("Generation Status") {
                        Text(message).foregroundStyle(.secondary)
                        Button("Retry") { Task { await environment.generate(prompt, capabilities: selectedCapabilities) } }
                    }
                }
                if let draft = environment.draft { draftSections(draft) }
            }
            .navigationTitle("Create")
            .sheet(isPresented: $showingManualEditor) { ManualBlueprintEditor() }
        }
    }

    @ViewBuilder private func draftSections(_ draft: MicroAppManifest) -> some View {
        Section("Validation") {
            if environment.validationIssues.isEmpty {
                Label("Blueprint passed every validation gate", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            } else {
                ForEach(environment.validationIssues) { issue in
                    Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                }
            }
        }
        Section("Generated Preview") {
            Text("AI-generated blueprint—review before installing.").font(.caption).foregroundStyle(.secondary)
            NavigationLink("Open Full Preview") { RuntimeView(manifest: draft, previewOnly: true) }
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") { environment.undoDraft() }.disabled(environment.previousDraft == nil)
                Button("Edit", systemImage: "pencil") { showingManualEditor = true }
            }
            Button("Install \(draft.name)") { Task { await environment.installDraft() } }
                .buttonStyle(.borderedProminent)
                .disabled(environment.validationIssues.contains { $0.severity == .error })
        }
    }

    private func ensureManualDraft() {
        guard environment.draft == nil else { return }
        environment.draft = BlueprintConverter().convert(
            .init(
                name: "My Pocket App",
                summary: "A custom local app",
                screens: [.init(id: "home", title: "Home", collectionID: "records")],
                collections: [.init(id: "records", title: "Records", fields: [.init(id: "title", title: "Title")])],
                actions: [.init(id: "add-record", title: "Add Record", kind: .createRecord, target: "records")]
            ),
            capabilities: selectedCapabilities
        )
        environment.validateDraft()
    }
}

private struct ManualBlueprintEditor: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var newFieldTitle = ""
    @State private var newFieldKind: FieldKind = .text
    @State private var newActionKind: ActionKind = .createRecord

    var body: some View {
        NavigationStack {
            Form {
                if environment.draft != nil {
                    Section("App") {
                        TextField("Name", text: binding(\.name))
                        TextField("Summary", text: binding(\.summary), axis: .vertical)
                    }
                    Section("Capabilities") {
                        ForEach(PocketCapability.allCases, id: \.self) { capability in
                            Toggle(capability.displayName, isOn: capabilityBinding(capability))
                        }
                    }
                    Section("Collections") {
                        ForEach(environment.draft?.collections ?? []) { collection in
                            DisclosureGroup(collection.title) {
                                ForEach(collection.fields) { field in
                                    HStack { Label(field.title, systemImage: icon(field.kind)); Spacer(); Text(field.kind.rawValue).font(.caption).foregroundStyle(.secondary) }
                                }
                                TextField("New field", text: $newFieldTitle)
                                Picker("Type", selection: $newFieldKind) { ForEach(FieldKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                                Button("Add Field") { addField(to: collection.id) }.disabled(newFieldTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        Button("Add Collection", systemImage: "plus") { addCollection() }
                    }
                    Section("Screens") {
                        ForEach(environment.draft?.screens ?? []) { screen in Label(screen.title, systemImage: "rectangle") }
                        Button("Add Screen", systemImage: "plus") { addScreen() }
                    }
                    Section("Actions") {
                        ForEach(environment.draft?.actions ?? []) { action in
                            HStack { Text(action.title ?? action.kind.rawValue); Spacer(); Text(action.kind.rawValue).font(.caption).foregroundStyle(.secondary) }
                        }
                        Picker("New Action", selection: $newActionKind) { ForEach(ActionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        Button("Add Action", systemImage: "plus") { addAction() }
                    }
                    Section("Validation") {
                        if environment.validationIssues.isEmpty { Label("Valid", systemImage: "checkmark.shield.fill").foregroundStyle(.green) }
                        ForEach(environment.validationIssues) { Text($0.message) }
                    }
                }
            }
            .navigationTitle("Blueprint Editor")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { environment.validateDraft(); dismiss() } } }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<MicroAppManifest, String>) -> Binding<String> {
        Binding(get: { environment.draft?[keyPath: keyPath] ?? "" }, set: { environment.draft?[keyPath: keyPath] = $0; environment.validateDraft() })
    }

    private func capabilityBinding(_ capability: PocketCapability) -> Binding<Bool> {
        Binding(get: { environment.draft?.capabilities.contains(capability) == true }, set: { enabled in
            if enabled { environment.draft?.capabilities.insert(capability) }
            else { environment.draft?.capabilities.remove(capability) }
            environment.validateDraft()
        })
    }

    private func addField(to collectionID: String) {
        guard var draft = environment.draft, let index = draft.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        let id = uniqueID(slug(newFieldTitle), existing: Set(draft.collections[index].fields.map(\.id)))
        draft.collections[index].fields.append(.init(id: id, title: newFieldTitle, kind: newFieldKind, defaultValue: defaultValue(newFieldKind)))
        environment.draft = draft
        newFieldTitle = ""
        environment.validateDraft()
    }

    private func addCollection() {
        guard var draft = environment.draft else { return }
        let id = uniqueID("collection-\(draft.collections.count + 1)", existing: Set(draft.collections.map(\.id)))
        draft.collections.append(.init(id: id, title: "Collection \(draft.collections.count + 1)", fields: [.init(id: "title", title: "Title", defaultValue: .string(""))]))
        environment.draft = draft
        environment.validateDraft()
    }

    private func addScreen() {
        guard var draft = environment.draft, let collection = draft.collections.last else { return }
        let id = uniqueID("screen-\(draft.screens.count + 1)", existing: Set(draft.screens.map(\.id)))
        draft.screens.append(.init(id: id, title: collection.title, components: [.init(id: "\(id)-list", kind: .list, title: collection.title, collection: collection.id)]))
        environment.draft = draft
        environment.validateDraft()
    }

    private func addAction() {
        guard var draft = environment.draft else { return }
        let id = uniqueID(newActionKind.rawValue, existing: Set(draft.actions.map(\.id)))
        let target = actionNeedsCollection(newActionKind) ? draft.collections.first?.id : newActionKind == .navigate ? draft.screens.first?.id : nil
        let capability = requiredCapability(newActionKind)
        if let capability { draft.capabilities.insert(capability) }
        draft.actions.append(.init(id: id, kind: newActionKind, title: newActionKind.rawValue, target: target, requiredCapability: capability, reason: capability.map { "Allow \($0.displayName.lowercased()) for this action." }))
        environment.draft = draft
        environment.validateDraft()
    }

    private func defaultValue(_ kind: FieldKind) -> PocketValue {
        switch kind { case .number: .number(0); case .boolean: .bool(false); case .date: .date(Date()); default: .string("") }
    }

    private func actionNeedsCollection(_ kind: ActionKind) -> Bool {
        [.createRecord, .updateRecord, .deleteRecord, .sortRecords, .filterRecords].contains(kind)
    }

    private func requiredCapability(_ kind: ActionKind) -> PocketCapability? {
        switch kind {
        case .copyToClipboard: .clipboardWrite
        case .importFile: .fileImport
        case .exportFile, .share: .fileExport
        case .selectPhotos: .photoSelection
        case .scheduleLocalNotification: .localNotifications
        case .httpGet, .httpPostJSON: .network
        case .generateText, .summarizeText, .extractFields, .classifyText, .rewriteText: .onDeviceModel
        default: nil
        }
    }

    private func icon(_ kind: FieldKind) -> String {
        switch kind { case .number: "number"; case .boolean: "checkmark.circle"; case .date: "calendar"; case .image: "photo"; case .choice: "list.bullet"; default: "textformat" }
    }

    private func slug(_ value: String) -> String {
        String(value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }).split(separator: "-").joined(separator: "-")
    }

    private func uniqueID(_ base: String, existing: Set<String>) -> String {
        let safe = base.isEmpty ? "item" : base
        if !existing.contains(safe) { return safe }
        var index = 2
        while existing.contains("\(safe)-\(index)") { index += 1 }
        return "\(safe)-\(index)"
    }
}

private struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var renameApp: InstalledAppInfo?
    @State private var renameText = ""
    @State private var exportDocument: PocketAppDocument?
    @State private var exportFilename = "Pocket-App"
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("Installed") {
                    if environment.installed.isEmpty {
                        ContentUnavailableView("No Installed Apps", systemImage: "square.grid.2x2", description: Text("Install a built-in app, generate an app, or import a .pocketapp file."))
                    }
                    ForEach(environment.installed) { app in appRow(app) }
                }
                Section("Built-in Pocket Apps") {
                    ForEach(environment.builtInTemplates) { template in
                        Button {
                            Task {
                                await environment.installTemplate(template)
                                if let app = environment.installed.first(where: { $0.id == template.id }) {
                                    await environment.open(app)
                                }
                            }
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(template.manifest.name)
                                    Text(template.manifest.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: template.manifest.icon.symbol) }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar { Button("Import", systemImage: "square.and.arrow.down") { importing = true } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pocketApp]) { result in importResult(result) }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .pocketApp, defaultFilename: exportFilename) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .alert("Library Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "Unknown error") }
            .alert("Rename Pocket App", isPresented: Binding(get: { renameApp != nil }, set: { if !$0 { renameApp = nil } })) {
                TextField("Name", text: $renameText)
                Button("Rename") { if let renameApp { Task { await environment.rename(renameApp.id, name: renameText) } } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func appRow(_ app: InstalledAppInfo) -> some View {
        Button { Task { await environment.open(app) } } label: {
            Label {
                VStack(alignment: .leading) {
                    HStack { Text(app.manifest.name); if app.disabled { Text("Disabled").font(.caption).foregroundStyle(.orange) } }
                    Text(app.manifest.summary).font(.caption).foregroundStyle(.secondary)
                    Text("v\(app.manifest.formatVersion) • \(app.manifest.capabilities.count) permissions").font(.caption2).foregroundStyle(.tertiary)
                }
            } icon: { Image(systemName: app.manifest.icon.symbol) }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) { Task { await environment.delete(app.id) } } label: { Label("Delete", systemImage: "trash") }
            Button { Task { await environment.toggleFavorite(app) } } label: { Label(app.favorite ? "Unfavorite" : "Favorite", systemImage: app.favorite ? "star.slash" : "star") }.tint(.yellow)
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renameApp = app; renameText = app.manifest.name }
            Button("Duplicate", systemImage: "plus.square.on.square") { Task { await environment.duplicate(app.id) } }
            Button(app.disabled ? "Enable" : "Disable", systemImage: "power") { Task { await environment.setDisabled(!app.disabled, id: app.id) } }
            Button("Roll Back", systemImage: "clock.arrow.circlepath") { Task { await environment.rollback(app.id) } }
            Button("Export", systemImage: "square.and.arrow.up") { prepareExport(app.manifest) }
        }
    }

    private func prepareExport(_ manifest: MicroAppManifest) {
        Task {
            do {
                exportDocument = .init(data: try await environment.exportPackage(manifest))
                exportFilename = manifest.name
                exporting = true
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func importResult(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            Task { do { try await environment.importPackage(data) } catch { errorMessage = error.localizedDescription } }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ActivityView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var filter = "All"
    private let filters = ["All", "generation", "action", "network", "permission", "import", "export", "runtime", "recovery"]
    private var events: [ActivityEvent] { filter == "All" ? environment.activity : environment.activity.filter { $0.category == filter } }

    var body: some View {
        NavigationStack {
            List {
                Picker("Filter", selection: $filter) { ForEach(filters, id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.menu)
                if events.isEmpty {
                    ContentUnavailableView("No Activity Yet", systemImage: "clock", description: Text("Actions, permissions, generations, imports, exports, network requests, and recoverable errors appear here."))
                }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(event.category.capitalized, systemImage: event.level == .error ? "xmark.octagon" : event.level == .warning ? "exclamationmark.triangle" : "checkmark.circle")
                            Spacer()
                            Text(event.createdAt, style: .relative).font(.caption)
                        }
                        Text(event.message).font(.subheadline).foregroundStyle(.secondary)
                        if let payload = event.payload { Text(payload.displayString).font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
            }.navigationTitle("Activity").refreshable { await environment.load() }
        }
    }
}

private struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("PKPreferReducedMotion") private var preferReducedMotion = false
    @AppStorage("PKDefaultPermission") private var defaultPermission = PermissionDecision.notRequested.rawValue
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Intelligence") {
                    LabeledContent("Status", value: environment.modelState.title)
                    Text(environment.modelState.detail).font(.caption).foregroundStyle(.secondary)
                }
                Section("Data and Storage") {
                    LabeledContent("Installed Apps", value: "\(environment.installed.count)")
                    LabeledContent("Built-in Apps", value: "\(environment.builtInTemplates.count)")
                    LabeledContent("Local Storage", value: ByteCountFormatter.string(fromByteCount: environment.storageBytes, countStyle: .file))
                    Button("Reset All Local Data", role: .destructive) { confirmReset = true }
                }
                Section("Permissions") {
                    Picker("Default decision", selection: $defaultPermission) {
                        Text("Ask Every Time").tag(PermissionDecision.notRequested.rawValue)
                        Text("Deny by Default").tag(PermissionDecision.denied.rawValue)
                    }
                    Text("This controls the first request from newly installed Pocket Apps. Apps can never grant themselves access.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Accessibility") {
                    Toggle("Prefer Reduced Motion", isOn: $preferReducedMotion)
                    LabeledContent("System Reduce Motion", value: systemReduceMotion ? "Enabled" : "Disabled")
                    LabeledContent("Contrast", value: contrast == .increased ? "Increased" : "Standard")
                }
                Section("Developer Diagnostics") {
                    LabeledContent("Model", value: environment.modelState.title)
                    LabeledContent("Activity Events", value: "\(environment.activity.count)")
                    LabeledContent("Recovery", value: environment.lifecycle.recoveryRequired ? "Required" : "Clear")
                    Text("Swift 6 • iOS 26 • typed actions • SQLite • no executable packages").font(.caption).foregroundStyle(.secondary)
                }
                Section("Runtime Safety") {
                    Label("Typed actions only", systemImage: "checkmark.shield")
                    Label("HTTPS allowlists and explicit permission broker", systemImage: "network.badge.shield.half.filled")
                    Label("No JavaScript, WebAssembly, JIT, or native downloads", systemImage: "lock.fill")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete every Pocket App and record?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete All Local Data", role: .destructive) { Task { await environment.resetAllData() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct RuntimeView: View {
    let manifest: MicroAppManifest
    var previewOnly = false
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreenID: String
    @State private var recordsByCollection: [String: [PocketRecord]] = [:]
    @State private var runtimeValues: [String: PocketValue] = [:]
    @State private var assetData: [String: Data] = [:]
    @State private var executor: ActionExecutor?
    @State private var editingCollection: CollectionSpec?
    @State private var formValues: [String: PocketValue] = [:]
    @State private var pendingActionID: String?
    @State private var permissionRequest: PermissionRequest?
    @State private var runtimeError: String?
    @State private var runtimeAlert: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument: PocketAppDocument?
    @State private var sharingText: String?
    @State private var selectingActionPhoto = false
    @State private var actionPhotoItem: PhotosPickerItem?
    @State private var actionPhotoTarget = "selectedPhoto"
    @State private var actionPhotoRecognizeText = false
    @State private var canUndo = false

    init(manifest: MicroAppManifest, previewOnly: Bool = false) {
        self.manifest = manifest
        self.previewOnly = previewOnly
        _selectedScreenID = State(initialValue: manifest.entryScreenID)
    }

    private var screen: ScreenSpec? { manifest.screens.first { $0.id == selectedScreenID } ?? manifest.screens.first }
    private var collectionSpecs: [String: CollectionSpec] { Dictionary(uniqueKeysWithValues: manifest.collections.map { ($0.id, $0) }) }
    private var permissionDialogTitle: String {
        guard let request = permissionRequest else { return "Permission" }
        return request.appName + " requests " + request.capability.displayName
    }

    var body: some View {
        List {
            if manifest.screens.count > 1 {
                Picker("Screen", selection: $selectedScreenID) { ForEach(manifest.screens) { Text($0.title).tag($0.id) } }.pickerStyle(.segmented)
            }
            if let screen {
                ForEach(screen.components) { component in
                    ComponentRenderer(
                        component: component,
                        recordsByCollection: recordsByCollection,
                        collectionSpecs: collectionSpecs,
                        assetData: assetData,
                        runtimeValues: $runtimeValues,
                        runAction: runAction,
                        importFile: { importing = true },
                        exportFile: prepareExport
                    )
                }
            } else {
                ContentUnavailableView("Invalid Screen", systemImage: "exclamationmark.triangle", description: Text("The entry screen is missing."))
            }
        }
        .navigationTitle(screen?.title ?? manifest.name)
        .toolbar {
            if !previewOnly {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(!canUndo)
                    Button("Done") { environment.lifecycle.markRuntimeClosed(); dismiss() }
                }
            }
        }
        .task { await startRuntime() }
        .onDisappear { if !previewOnly { environment.lifecycle.markRuntimeClosed() } }
        .onChange(of: runtimeValues) { _, values in persist(values) }
        .overlay {
            if let collection = editingCollection {
                recordForm(collection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                    .ignoresSafeArea()
                    .zIndex(1)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pocketApp]) { result in importRuntimeFile(result) }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .pocketApp, defaultFilename: manifest.name) { result in
            if case .failure(let error) = result { runtimeError = error.localizedDescription }
        }
        .photosPicker(isPresented: $selectingActionPhoto, selection: $actionPhotoItem, matching: .images)
        .task(id: actionPhotoItem) { await loadActionPhoto() }
        .sheet(isPresented: Binding(get: { sharingText != nil }, set: { if !$0 { sharingText = nil } })) {
            ShareLink(item: sharingText ?? "") { Label("Share", systemImage: "square.and.arrow.up") }.padding()
        }
        .alert("Pocket App", isPresented: Binding(get: { runtimeAlert != nil }, set: { if !$0 { runtimeAlert = nil } })) {
            Button("OK") {}
        } message: { Text(runtimeAlert ?? "") }
        .alert("Runtime Error", isPresented: Binding(get: { runtimeError != nil }, set: { if !$0 { runtimeError = nil } })) {
            Button("Retry") { if let pendingActionID { runAction(pendingActionID) } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(runtimeError ?? "") }
        .confirmationDialog(
            permissionDialogTitle,
            isPresented: Binding(get: { permissionRequest != nil }, set: { if !$0 { permissionRequest = nil } }),
            titleVisibility: .visible
        ) { permissionButtons } message: { Text(permissionRequest?.reason ?? "") }
    }

    @ViewBuilder private var permissionButtons: some View {
        Button("Don’t Allow", role: .destructive) { decide(.denied) }
        Button("Allow Once") { decide(.allowOnce) }
        Button("Always Allow") { decide(.alwaysAllow) }
        Button("Cancel", role: .cancel) { permissionRequest = nil }
    }

    private func startRuntime() async {
        guard !previewOnly, let store = environment.store else { return }
        let configured = PermissionDecision(rawValue: UserDefaults.standard.string(forKey: "PKDefaultPermission") ?? "") ?? .notRequested
        executor = ActionExecutor(store: store, intelligence: environment.intelligence, defaultPermission: configured)
        canUndo = false
        environment.lifecycle.markRuntimeOpen(appID: manifest.id)
        await reload()
    }

    private func reload() async {
        guard !previewOnly, let store = environment.store else { return }
        for collection in manifest.collections {
            recordsByCollection[collection.id] = (try? await store.records(appID: manifest.id, collectionID: collection.id)) ?? []
        }
        runtimeValues = (try? await store.runtimeValues(appID: manifest.id)) ?? [:]
        for assetID in manifestAssetIDs {
            if let data = await environment.assetData(appID: manifest.id, assetID: assetID) { assetData[assetID] = data }
        }
    }

    private func runAction(_ id: String) {
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

    private func execute(_ id: String, form: [String: PocketValue]) {
        guard let executor else { return }
        Task {
            do {
                let collections = recordsByCollection.mapValues { PocketValue.array($0.map { .object($0.values) }) }
                let inlineForm = Dictionary(uniqueKeysWithValues: runtimeValues.compactMap { key, value in
                    key.hasPrefix("form.") ? (String(key.dropFirst(5)), value) : nil
                })
                let mergedForm = inlineForm.merging(form) { _, explicit in explicit }
                let context: [String: PocketValue] = [
                    "state": .object(runtimeValues),
                    "form": .object(mergedForm),
                    "selectedRecordID": runtimeValues["selectedRecordID"] ?? .null,
                    "collections": .object(collections),
                    "environment": .object(["currentDate": .date(Date())])
                ]
                let result = try await executor.execute(id, manifest: manifest, context: context)
                await apply(result)
                await reload()
                canUndo = await executor.canUndo()
            } catch RuntimeExecutionError.permissionRequired(let request) {
                permissionRequest = request
            } catch { runtimeError = error.localizedDescription }
        }
    }

    private func undoLast() {
        guard let executor else { return }
        Task {
            do {
                let result = try await executor.undoLast()
                await apply(result)
                await reload()
                canUndo = await executor.canUndo()
            } catch { runtimeError = error.localizedDescription }
        }
    }

    @MainActor private func apply(_ result: ActionResult) async {
        switch result {
        case .none: break
        case .value(let value): runtimeValues["lastResult"] = value
        case .navigated(let id): selectedScreenID = id
        case .alert(let text): runtimeAlert = text
        case .record: break
        case .records(let records): if let collection = records.first?.collectionID { recordsByCollection[collection] = records }
        case .selectedRecord(let id): runtimeValues["selectedRecordID"] = .string(id.uuidString)
        case .host(let request):
            switch request {
            case .dismiss: dismiss()
            case .sheet(let title): runtimeAlert = title
            case .share(let text): sharingText = text
            case .importFile: importing = true
            case .exportFile: prepareExport()
            case .selectPhotos(let target, let recognizeText):
                actionPhotoTarget = target
                actionPhotoRecognizeText = recognizeText
                actionPhotoItem = nil
                selectingActionPhoto = true
            case .openURL(let value): if let url = URL(string: value) { await UIApplication.shared.open(url) }
            }
        }
    }

    private var manifestAssetIDs: Set<String> {
        func collect(_ components: [ComponentSpec]) -> Set<String> {
            components.reduce(into: Set<String>()) { result, component in
                if let assetID = component.assetID { result.insert(assetID) }
                result.formUnion(collect(component.children))
            }
        }
        return manifest.screens.reduce(into: Set<String>()) { $0.formUnion(collect($1.components)) }
    }

    private func loadActionPhoto() async {
        guard let item = actionPhotoItem else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), data.count <= PocketLimits.assetBytes else {
                throw HostServiceError.invalidInput
            }
            let encoded = PocketValue.string(data.base64EncodedString())
            runtimeValues[actionPhotoTarget] = encoded
            if let store = environment.store { try await store.setRuntimeValue(encoded, appID: manifest.id, key: actionPhotoTarget) }
            if actionPhotoRecognizeText {
                let text = try await VisionTextService().recognizeText(in: data)
                let textKey = "\(actionPhotoTarget).recognizedText"
                runtimeValues[textKey] = .string(text)
                if let store = environment.store { try await store.setRuntimeValue(.string(text), appID: manifest.id, key: textKey) }
            }
        } catch { runtimeError = error.localizedDescription }
        actionPhotoItem = nil
    }

    private func formPhotoBinding(for fieldID: String) -> Binding<PhotosPickerItem?> {
        Binding(get: { nil }, set: { item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), data.count <= PocketLimits.assetBytes else {
                        throw HostServiceError.invalidInput
                    }
                    formValues[fieldID] = .string(data.base64EncodedString())
                } catch { runtimeError = error.localizedDescription }
            }
        })
    }

    private func decide(_ decision: PermissionDecision) {
        guard let request = permissionRequest, let executor, let actionID = pendingActionID else { return }
        Task {
            do {
                try await executor.decide(decision, request: request)
                permissionRequest = nil
                if decision != .denied { execute(actionID, form: [:]) }
            } catch { runtimeError = error.localizedDescription }
        }
    }

    private func recordForm(_ collection: CollectionSpec) -> some View {
        NavigationStack {
            Form { ForEach(collection.fields) { field in fieldEditor(field) } }
                .navigationTitle("Add \(collection.title)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingCollection = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let action = manifest.actions.first(where: { $0.kind == .createRecord && $0.target == collection.id }) {
                                editingCollection = nil
                                execute(action.id, form: formValues)
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder private func fieldEditor(_ field: FieldSpec) -> some View {
        switch field.kind {
        case .text:
            TextField(field.title, text: Binding(get: { formValues[field.id]?.displayString ?? "" }, set: { formValues[field.id] = .string($0) }))
        case .multilineText:
            TextField(field.title, text: Binding(get: { formValues[field.id]?.displayString ?? "" }, set: { formValues[field.id] = .string($0) }), axis: .vertical).lineLimit(3...8)
        case .number:
            TextField(field.title, value: Binding(get: { if case .number(let value) = formValues[field.id] { value } else { 0 } }, set: { formValues[field.id] = .number($0) }), format: .number).keyboardType(.decimalPad)
        case .boolean:
            Toggle(field.title, isOn: Binding(get: { if case .bool(let value) = formValues[field.id] { value } else { false } }, set: { formValues[field.id] = .bool($0) }))
        case .date:
            DatePicker(field.title, selection: Binding(get: { if case .date(let value) = formValues[field.id] { value } else { Date() } }, set: { formValues[field.id] = .date($0) }))
        case .choice:
            Picker(field.title, selection: Binding(get: { formValues[field.id]?.stringValue ?? field.options.first ?? "" }, set: { formValues[field.id] = .string($0) })) {
                ForEach(field.options, id: \.self) { Text($0).tag($0) }
            }
        case .image:
            let hasImage = formValues[field.id] != nil
            PhotosPicker(selection: formPhotoBinding(for: field.id), matching: .images) {
                Label(hasImage ? "Replace \(field.title)" : "Choose \(field.title)", systemImage: "photo.on.rectangle")
            }
        }
    }

    private func persist(_ values: [String: PocketValue]) {
        guard !previewOnly, let store = environment.store else { return }
        Task { for (key, value) in values { try? await store.setRuntimeValue(value, appID: manifest.id, key: key) } }
    }

    private func prepareExport() {
        guard !previewOnly else { return }
        Task {
            do {
                let data = try await environment.exportPackage(manifest)
                exportDocument = .init(data: data)
                exporting = true
            } catch { runtimeError = error.localizedDescription }
        }
    }

    private func importRuntimeFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            Task { do { try await environment.importPackage(data) } catch { runtimeError = error.localizedDescription } }
        } catch { runtimeError = error.localizedDescription }
    }
}
