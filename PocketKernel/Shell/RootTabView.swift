import FoundationModels
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum RootTab: Hashable { case home, create, library, activity, settings }

struct RootTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("PKOnboardingComplete") private var onboardingComplete = false
    @State private var selectedTab: RootTab = .home

    var body: some View {
        @Bindable var environment = environment
        TabView(selection: $selectedTab) {
            HomeView(create: { selectedTab = .create }).tag(RootTab.home).tabItem { Label("Home", systemImage: "house.fill") }
            CreateView().tag(RootTab.create).tabItem { Label("Create", systemImage: "sparkles") }
            LibraryView().tag(RootTab.library).tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
            ActivityView().tag(RootTab.activity).tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            SettingsView().tag(RootTab.settings).tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboardingComplete && !ProcessInfo.processInfo.arguments.contains("-PKUITesting") }, set: { if !$0 { onboardingComplete = true } })) { OnboardingView { onboardingComplete = true } }
        .sheet(item: $environment.pendingOpenApp) { RuntimeView(manifest: $0, store: environment.store) }
        .confirmationDialog("PocketKernel recovered from an interrupted session", isPresented: Binding(get: { environment.lifecycle.recoveryRequired }, set: { environment.lifecycle.recoveryRequired = $0 }), titleVisibility: .visible) {
            if let id = environment.lifecycle.affectedAppID, let app = environment.apps.first(where: { $0.id == id }) { Button("Reopen \(app.name)") { environment.pendingOpenApp = app; environment.lifecycle.resumeSession() }; Button("Export \(app.name)") { environment.pendingOpenApp = app; environment.lifecycle.dismissRecovery() }; Button("Delete \(app.name)", role: .destructive) { Task { await environment.delete(app.id); environment.lifecycle.dismissRecovery() } } }
            Button("Continue Safely") { environment.lifecycle.dismissRecovery() }
        } message: { Text("The last micro-app may have been closed unexpectedly. Your records were preserved.") }
    }
}

private struct OnboardingView: View {
    var complete: () -> Void
    var body: some View {
        NavigationStack { VStack(spacing: 24) { Spacer(); Image(systemName: "square.grid.3x3.square").font(.system(size: 72)).foregroundStyle(.tint); Text("PocketKernel").font(.largeTitle.bold()); Text("Describe small apps, preview the generated blueprint, and run them safely as native SwiftUI interfaces.").multilineTextAlignment(.center).foregroundStyle(.secondary); VStack(alignment: .leading, spacing: 12) { Label("On-device generation when Apple Intelligence is available", systemImage: "apple.intelligence"); Label("Typed actions—no downloaded code or JIT", systemImage: "checkmark.shield"); Label("Your apps and records stay on this device", systemImage: "lock.fill") }.frame(maxWidth: 420, alignment: .leading); Spacer(); Button("Get Started", action: complete).buttonStyle(.borderedProminent).controlSize(.large) }.padding(28).navigationTitle("Welcome") }
    }
}

private struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var search = ""
    var create: () -> Void
    private var filtered: [MicroAppManifest] { search.isEmpty ? environment.apps : environment.apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationStack { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) { Button(action: create) { VStack(spacing: 12) { Image(systemName: "plus.circle.fill").font(.largeTitle); Text("Create App").font(.headline) }.frame(maxWidth: .infinity, minHeight: 130).background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain).accessibilityHint("Opens the AI and template app builder"); ForEach(filtered) { app in NavigationLink { RuntimeView(manifest: app, store: environment.store) } label: { VStack(alignment: .leading, spacing: 10) { Image(systemName: app.icon.symbol).font(.title); Text(app.name).font(.headline); Text(app.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }.frame(maxWidth: .infinity, minHeight: 130, alignment: .leading).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain) } }.padding() }.searchable(text: $search, prompt: "Search Pocket Apps").navigationTitle("PocketKernel").toolbar { ToolbarItem(placement: .topBarTrailing) { ModelStatusLabel() } } }
    }
}

private struct ModelStatusLabel: View {
    private var available: Bool { if case .available = SystemLanguageModel.default.availability { true } else { false } }
    var body: some View { Label(available ? "AI Ready" : "Templates Ready", systemImage: available ? "apple.intelligence" : "square.grid.2x2").font(.caption).foregroundStyle(available ? .green : .secondary).accessibilityLabel(available ? "Apple Intelligence available" : "Apple Intelligence unavailable; templates available") }
}

private struct CreateView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prompt = "Create a car maintenance tracker with mileage, service date, cost, notes, and next-service reminders."
    @State private var selectedCapabilities: Set<PocketCapability> = []
    private let suggestions = ["Habit tracker with daily streaks", "Inventory list with quantities", "Quick private journal", "Task board with status"]
    var body: some View {
        @Bindable var environment = environment
        NavigationStack { Form {
            Section("Describe your app") { TextEditor(text: $prompt).frame(minHeight: 120).accessibilityLabel("App description"); ScrollView(.horizontal) { HStack { ForEach(suggestions, id: \.self) { suggestion in Button(suggestion) { prompt = suggestion }.buttonStyle(.bordered) } } }.scrollIndicators(.hidden) }
            Section("Capabilities") { ForEach(PocketCapability.allCases, id: \.self) { capability in Toggle(capability.rawValue, isOn: Binding(get: { selectedCapabilities.contains(capability) }, set: { enabled in if enabled { selectedCapabilities.insert(capability) } else { selectedCapabilities.remove(capability) } })) } }
            Button { Task { await environment.generate(prompt, capabilities: selectedCapabilities) } } label: { if environment.isGenerating { Label("Generating typed blueprint…", systemImage: "hourglass") } else { Label("Generate on device", systemImage: "sparkles") } }.disabled(environment.isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error = environment.generationError { Section("Generation status") { Text(error).foregroundStyle(.secondary); Button("Retry") { Task { await environment.generate(prompt, capabilities: selectedCapabilities) } } } }
            if let draft = environment.draft { Section("Validation") { let issues = ManifestValidator().validate(draft); if issues.isEmpty { Label("Blueprint passed every manifest gate", systemImage: "checkmark.shield.fill").foregroundStyle(.green) } else { ForEach(issues) { Label($0.message, systemImage: $0.severity == .error ? "xmark.octagon" : "exclamationmark.triangle") } } }; Section("Generated Preview") { Text("AI-generated blueprint—review before installing.").font(.caption).foregroundStyle(.secondary); RuntimeView(manifest: draft, store: nil).frame(minHeight: 320); Button("Install \(draft.name)") { Task { await environment.installDraft() } }.buttonStyle(.borderedProminent) } }
        }.navigationTitle("Create") }
    }
}

private struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var importing = false
    @State private var errorMessage: String?
    private let templates = ["Task Board", "Habit Tracker", "Quick Journal", "Inventory List", "Service Log"]
    var body: some View {
        NavigationStack { List {
            Section("Installed") { if environment.apps.isEmpty { Text("No installed apps").foregroundStyle(.secondary) }; ForEach(environment.apps) { app in NavigationLink { RuntimeView(manifest: app, store: environment.store) } label: { Label { VStack(alignment: .leading) { Text(app.name); Text(app.summary).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: app.icon.symbol) } }.swipeActions { Button(role: .destructive) { Task { await environment.delete(app.id) } } label: { Label("Delete", systemImage: "trash") }; Button { Task { await environment.duplicate(app) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.blue) }.contextMenu { if let data = environment.exportPackage(app) { ShareLink(item: data, preview: SharePreview("\(app.name).pocketapp")) { Label("Export Pocket App", systemImage: "square.and.arrow.up") } } } } }
            Section("Built-in Templates") { ForEach(templates, id: \.self) { name in Button { Task { await environment.installTemplate(named: name) } } label: { Label(name, systemImage: "square.dashed") } } }
        }.navigationTitle("Library").toolbar { Button("Import", systemImage: "square.and.arrow.down") { importing = true } }.fileImporter(isPresented: $importing, allowedContentTypes: [.pocketApp]) { result in do { let url = try result.get(); guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }; defer { url.stopAccessingSecurityScopedResource() }; let data = try Data(contentsOf: url); Task { await environment.importPackage(data) } } catch { errorMessage = error.localizedDescription } }.alert("Import Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unknown import error") } }
    }
}

private struct ActivityView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        NavigationStack {
            List {
                if environment.activity.isEmpty {
                    ContentUnavailableView("No Activity Yet", systemImage: "clock", description: Text("Actions, permission decisions, imports, exports, and recoverable errors appear here."))
                }
                ForEach(environment.activity) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(event.category.capitalized, systemImage: event.level == .error ? "xmark.octagon" : event.level == .warning ? "exclamationmark.triangle" : "checkmark.circle")
                            Spacer()
                            Text(event.createdAt, style: .relative).font(.caption)
                        }
                        Text(event.message).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .refreshable { await environment.load() }
            .navigationTitle("Activity")
        }
    }
}

private struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var confirmReset = false
    private var modelStatus: String { if case .available = SystemLanguageModel.default.availability { "Available" } else { String(describing: SystemLanguageModel.default.availability) } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Intelligence") {
                    LabeledContent("On-device model", value: modelStatus)
                    Text("When unavailable, PocketKernel keeps the manual builder, imports, and five templates enabled.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Accessibility") {
                    LabeledContent("Reduce Motion", value: reduceMotion ? "Enabled" : "Disabled")
                    LabeledContent("Contrast", value: contrast == .increased ? "Increased" : "Standard")
                }
                Section("Storage") {
                    LabeledContent("Installed Apps", value: "\(environment.apps.count)")
                    Button("Reset All Local Data", role: .destructive) { confirmReset = true }
                }
                Section("Runtime Safety") {
                    Label("Typed actions only", systemImage: "checkmark.shield")
                    Label("HTTPS allowlists and permission broker", systemImage: "network.badge.shield.half.filled")
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
    var store: PocketStore?
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedScreenID: String
    @State private var recordsByCollection: [String: [PocketRecord]] = [:]
    @State private var runtimeValues: [String: PocketValue] = [:]
    @State private var executor: ActionExecutor?
    @State private var editingCollection: CollectionSpec?
    @State private var formValues: [String: String] = [:]
    @State private var runtimeError: String?
    @State private var runtimeAlert: String?
    @State private var permissionRequest: PermissionRequest?
    @State private var pendingActionID: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument: PocketAppDocument?
    @State private var shareText: String?
    @Environment(\.dismiss) private var dismiss

    init(manifest: MicroAppManifest, store: PocketStore? = nil) { self.manifest = manifest; self.store = store; _selectedScreenID = State(initialValue: manifest.entryScreenID) }
    private var screen: ScreenSpec? { manifest.screens.first { $0.id == selectedScreenID } ?? manifest.screens.first }

    var body: some View {
        List { if let screen { ForEach(screen.components) { component in ComponentRenderer(component: component, recordsByCollection: recordsByCollection, runtimeValues: $runtimeValues, runAction: runAction, importFile: { importing = true }, exportFile: prepareExport) } } else { ContentUnavailableView("Invalid Screen", systemImage: "exclamationmark.triangle", description: Text("The entry screen is missing.")) } }
            .navigationTitle(screen?.title ?? manifest.name)
            .task { if let store { executor = ActionExecutor(store: store); environment.lifecycle.markRuntimeOpen(appID: manifest.id) }; await reload() }
            .onChange(of: runtimeValues) { _, values in guard let store else { return }; Task { for (key, value) in values { try? await store.setRuntimeValue(value, appID: manifest.id, key: key) } } }
            .sheet(item: $editingCollection) { collection in recordForm(collection) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pocketApp]) { result in if case .success(let url) = result, url.startAccessingSecurityScopedResource() { defer { url.stopAccessingSecurityScopedResource() }; if let data = try? Data(contentsOf: url) { Task { await environment.importPackage(data) } } } }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .pocketApp, defaultFilename: manifest.name) { result in if case .failure(let error) = result { runtimeError = error.localizedDescription } }
            .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) { ShareSheet(text: shareText ?? "") }
            .alert("Runtime Error", isPresented: Binding(get: { runtimeError != nil }, set: { if !$0 { runtimeError = nil } })) { Button("Retry") { if let id = pendingActionID { runAction(id) } }; Button("Dismiss", role: .cancel) { runtimeError = nil } } message: { Text(runtimeError ?? "Unknown error") }
            .alert("Pocket App", isPresented: Binding(get: { runtimeAlert != nil }, set: { if !$0 { runtimeAlert = nil } })) { Button("OK") { runtimeAlert = nil } } message: { Text(runtimeAlert ?? "") }
            .confirmationDialog(permissionTitle, isPresented: Binding(get: { permissionRequest != nil }, set: { if !$0 { permissionRequest = nil } }), titleVisibility: .visible) { Button("Allow Once") { decidePermission(.allowOnce) }; Button("Always Allow") { decidePermission(.alwaysAllow) }; Button("Don't Allow", role: .destructive) { decidePermission(.denied) } } message: { Text(permissionRequest?.reason ?? "This action requires permission.") }
    }

    private var permissionTitle: String { guard let request = permissionRequest else { return "Permission Request" }; return "\(request.appName) wants \(request.capability.rawValue)" }
    private func runAction(_ id: String) {
        pendingActionID = id
        guard let action = manifest.actions.first(where: { $0.id == id }) else { runtimeError = "Action not found."; return }
        if action.kind == .createRecord, let collection = manifest.collections.first(where: { $0.id == action.target }) { formValues = Dictionary(uniqueKeysWithValues: collection.fields.map { ($0.id, "") }); editingCollection = collection; return }
        guard let executor else { runtimeError = store == nil ? "Preview mode does not execute actions." : "Runtime is still starting."; return }
        let context: [String: PocketValue] = ["state": .object(runtimeValues), "environment": .object(["currentDate": .date(Date())])]
        Task { do { let result = try await executor.execute(id, manifest: manifest, context: context); apply(result); await reload(); await environment.load() } catch RuntimeExecutionError.permissionRequired(let request) { permissionRequest = request } catch RuntimeExecutionError.conditionFalse { } catch { runtimeError = error.localizedDescription } }
    }

    @MainActor private func apply(_ result: ActionResult) {
        switch result { case .none, .record: break; case .value(let value): runtimeValues["lastResult"] = value; case .navigated(let screenID): if manifest.screens.contains(where: { $0.id == screenID }) { selectedScreenID = screenID }; case .alert(let message): runtimeAlert = message; case .host(let request): handle(request) }
    }

    @MainActor private func handle(_ request: HostRequest) {
        switch request { case .dismiss: dismiss(); case .sheet(let title): runtimeAlert = title; case .share(let text): shareText = text; case .importFile: importing = true; case .exportFile: prepareExport(); case .selectPhotos: runtimeAlert = "Use the photo picker component to select an image."; case .openURL(let value): if let url = URL(string: value) { UIApplication.shared.open(url) } }
    }

    private func decidePermission(_ decision: PermissionDecision) {
        guard let request = permissionRequest, let executor else { permissionRequest = nil; return }
        permissionRequest = nil
        Task { do { try await executor.decide(decision, request: request); if let store { try? await store.log(appID: manifest.id, level: decision == .denied ? .warning : .info, category: "permission", message: "\(decision.rawValue): \(request.capability.rawValue)") }; if decision != .denied, let id = pendingActionID { runAction(id) } } catch { runtimeError = error.localizedDescription } }
    }

    private func recordForm(_ collection: CollectionSpec) -> some View {
        NavigationStack { Form { ForEach(collection.fields) { field in TextField(field.title, text: Binding(get: { formValues[field.id, default: ""] }, set: { formValues[field.id] = $0 })) } }.navigationTitle("Add \(collection.title)").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingCollection = nil } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save(collection) } } } } }
    }

    private func save(_ collection: CollectionSpec) async {
        guard let store else { editingCollection = nil; return }
        let now = Date(); let values = formValues.mapValues { PocketValue.string($0) }
        do { try await store.save(record: .init(id: UUID(), collectionID: collection.id, values: values, createdAt: now, updatedAt: now), appID: manifest.id); try await store.log(appID: manifest.id, level: .info, category: "record", message: "Created record in \(collection.title)"); editingCollection = nil; await reload() } catch { runtimeError = error.localizedDescription }
    }

    private func reload() async { guard let store else { return }; for collection in manifest.collections { recordsByCollection[collection.id] = (try? await store.records(appID: manifest.id, collectionID: collection.id)) ?? [] } }
    private func prepareExport() { guard let data = environment.exportPackage(manifest) else { runtimeError = "Package export failed."; return }; exportDocument = PocketAppDocument(data: data); exporting = true }
}

struct PocketAppDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pocketApp] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }; self.data = data }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
