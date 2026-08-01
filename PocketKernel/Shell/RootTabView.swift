import FoundationModels
import SwiftUI

struct RootTabView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house.fill") }
            CreateView().tabItem { Label("Create", systemImage: "sparkles") }
            LibraryView().tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
            ActivityView().tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

private struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View { NavigationStack { List { Section("Recently used") { if environment.apps.isEmpty { ContentUnavailableView("No Pocket Apps Yet", systemImage: "square.grid.2x2", description: Text("Create one or open a built-in template.")) } else { ForEach(environment.apps) { app in NavigationLink { RuntimeView(manifest: app, store: environment.store) } label: { Label(app.name, systemImage: app.icon.symbol) } } } } }.navigationTitle("PocketKernel") } }
}

private struct CreateView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prompt = "Create a car maintenance tracker with mileage, service date, cost, and notes."
    var body: some View {
        @Bindable var environment = environment
        NavigationStack { Form {
            Section("Describe your app") { TextEditor(text: $prompt).frame(minHeight: 120).accessibilityLabel("App description") }
            Button { Task { await environment.generate(prompt) } } label: { if environment.isGenerating { Label("Generating blueprint…", systemImage: "hourglass") } else { Label("Generate on device", systemImage: "sparkles") } }.disabled(environment.isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error = environment.generationError { Section("Fallback used") { Text(error).foregroundStyle(.secondary) } }
            if let draft = environment.draft { Section("Generated preview") { RuntimeView(manifest: draft, store: nil).frame(minHeight: 300); Button("Install \(draft.name)") { Task { await environment.installDraft() } }.buttonStyle(.borderedProminent) } }
        }.navigationTitle("Create") }
    }
}

private struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var importing = false
    var body: some View { NavigationStack { List { Section("Installed") { ForEach(environment.apps) { app in NavigationLink { RuntimeView(manifest: app, store: environment.store) } label: { VStack(alignment: .leading) { Text(app.name); Text(app.summary).font(.caption).foregroundStyle(.secondary) } }.swipeActions { Button(role: .destructive) { Task { await environment.delete(app.id) } } label: { Label("Delete", systemImage: "trash") } }.contextMenu { if let data = environment.exportPackage(app) { ShareLink(item: data, preview: SharePreview("\(app.name).pocketapp")) { Label("Export Pocket App", systemImage: "square.and.arrow.up") } } } } } Section("Built-in templates") { ForEach(["Task Board", "Habit Tracker", "Quick Journal", "Inventory List", "Service Log"], id: \.self) { name in Button { Task { await environment.installTemplate(named: name) } } label: { Label(name, systemImage: "square.dashed") } } } }.navigationTitle("Library").toolbar { Button("Import", systemImage: "square.and.arrow.down") { importing = true } }.fileImporter(isPresented: $importing, allowedContentTypes: [.pocketApp]) { result in guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }; if let data = try? Data(contentsOf: url) { Task { await environment.importPackage(data) } } } } }
}

private struct ActivityView: View { var body: some View { NavigationStack { ContentUnavailableView("No Activity Yet", systemImage: "clock", description: Text("Generation, imports, permission decisions, and recoverable errors appear here.")).navigationTitle("Activity") } } }

private struct SettingsView: View {
    var status: String { if case .available = SystemLanguageModel.default.availability { return "Available" }; return String(describing: SystemLanguageModel.default.availability) }
    var body: some View { NavigationStack { Form { Section("Apple Intelligence") { LabeledContent("On-device model", value: status) } Section("Runtime safety") { Label("Typed actions only", systemImage: "checkmark.shield"); Label("No JavaScript, WebAssembly, JIT, or native downloads", systemImage: "lock.fill") } }.navigationTitle("Settings") } }
}

struct RuntimeView: View {
    let manifest: MicroAppManifest
    var store: PocketStore?
    @State private var records: [PocketRecord] = []
    @State private var editingCollection: CollectionSpec?
    @State private var formValues: [String: String] = [:]
    @State private var runtimeError: String?

    init(manifest: MicroAppManifest, store: PocketStore? = nil) { self.manifest = manifest; self.store = store }

    var body: some View {
        List { ForEach(manifest.screens.first?.components ?? []) { component in componentView(component) } }
            .navigationTitle(manifest.name)
            .task { await reload() }
            .sheet(item: $editingCollection) { collection in recordForm(collection) }
            .alert("Action failed", isPresented: .constant(runtimeError != nil)) { Button("OK") { runtimeError = nil } } message: { Text(runtimeError ?? "Unknown error") }
    }
    @ViewBuilder private func componentView(_ component: ComponentSpec) -> some View {
        switch component.kind {
        case .heading: Text(component.text ?? component.title ?? "").font(.title2.bold())
        case .caption: Text(component.text ?? component.title ?? "").font(.caption).foregroundStyle(.secondary)
        case .button: Button(component.title ?? "Continue") { runAction(component.actionID) }
        case .list:
            if records.isEmpty { ContentUnavailableView(component.title ?? "No Records", systemImage: "list.bullet.rectangle", description: Text(store == nil ? "Preview: records appear here." : "Add your first record to this collection.")) }
            else { ForEach(records) { record in VStack(alignment: .leading) { ForEach(record.values.sorted(by: { $0.key < $1.key }), id: \.key) { pair in HStack { Text(pair.key.capitalized).foregroundStyle(.secondary); Spacer(); Text(display(pair.value)) } } } } }
        case .divider: Divider()
        default: Text(component.text ?? component.title ?? component.kind.rawValue)
        }
    }

    private func runAction(_ id: String?) {
        guard let action = manifest.actions.first(where: { $0.id == id }), action.kind == .createRecord,
              let collection = manifest.collections.first(where: { $0.id == action.target }) else { return }
        formValues = Dictionary(uniqueKeysWithValues: collection.fields.map { ($0.id, "") }); editingCollection = collection
    }

    private func recordForm(_ collection: CollectionSpec) -> some View {
        NavigationStack { Form { ForEach(collection.fields) { field in TextField(field.title, text: Binding(get: { formValues[field.id, default: ""] }, set: { formValues[field.id] = $0 })) } }
            .navigationTitle("Add \(collection.title)")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingCollection = nil } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save(collection) } } } } }
    }

    private func save(_ collection: CollectionSpec) async {
        guard let store else { editingCollection = nil; return }
        let now = Date(); let values = formValues.mapValues { PocketValue.string($0) }
        do { try await store.save(record: .init(id: UUID(), collectionID: collection.id, values: values, createdAt: now, updatedAt: now), appID: manifest.id); editingCollection = nil; await reload() }
        catch { runtimeError = error.localizedDescription }
    }

    private func reload() async {
        guard let store, let collection = manifest.collections.first else { return }
        records = (try? await store.records(appID: manifest.id, collectionID: collection.id)) ?? []
    }

    private func display(_ value: PocketValue) -> String {
        switch value { case .null: "—"; case .bool(let value): value ? "Yes" : "No"; case .number(let value): value.formatted(); case .string(let value): value; case .date(let value): value.formatted(date: .abbreviated, time: .omitted); case .array(let value): "\(value.count) items"; case .object(let value): "\(value.count) fields" }
    }
}
