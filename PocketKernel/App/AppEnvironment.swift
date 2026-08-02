import Foundation
import FoundationModels
import Observation

enum ModelAvailabilityState: Sendable, Equatable {
    case available
    case unavailable(String)
    case mock
    case templates

    var title: String {
        switch self {
        case .available: "Apple Intelligence Ready"
        case .unavailable: "Apple Intelligence Unavailable"
        case .mock: "Deterministic Mock Model"
        case .templates: "Template Generator"
        }
    }

    var detail: String {
        switch self {
        case .available: "Blueprints are generated privately on this device."
        case .unavailable(let reason): reason
        case .mock: "CI and UI tests use a fixed validated blueprint."
        case .templates: "Built-in templates remain available without AI."
        }
    }
}

@MainActor @Observable final class AppEnvironment {
    private(set) var store: PocketStore?
    private(set) var lifecycle: AppLifecycleController
    private(set) var installed: [InstalledAppInfo] = []
    private(set) var activity: [ActivityEvent] = []
    private(set) var storageBytes: Int64 = 0
    private(set) var modelState: ModelAvailabilityState
    private(set) var startupError: String?

    var pendingOpenApp: MicroAppManifest?
    var draft: MicroAppManifest?
    var previousDraft: MicroAppManifest?
    var validationIssues: [ValidationIssue] = []
    var generationError: String?
    var isGenerating = false
    var lastExportedPackage: Data?

    private let generator: any BlueprintGenerating
    private let fallbackGenerator: any BlueprintGenerating = TemplateBlueprintGenerator()
    let intelligence: any IntelligenceServicing
    private let launchArguments: [String]
    private var didApplyLaunchReset = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        launchArguments = arguments
        let storageLayout = AppEnvironment.makeLayout()
        lifecycle = AppLifecycleController(layout: storageLayout, arguments: arguments)
        do { store = try PocketStore(inMemory: arguments.contains("-PKInMemoryStore")) }
        catch { startupError = error.localizedDescription; store = nil }

        switch AppEnvironment.argumentValue("-PKModelMode", arguments: arguments) {
        case "mock":
            generator = MockBlueprintGenerator()
            intelligence = MockIntelligenceService()
            modelState = .mock
        case "template":
            generator = TemplateBlueprintGenerator()
            intelligence = MockIntelligenceService()
            modelState = .templates
        default:
            generator = FoundationModelBlueprintGenerator()
            intelligence = FoundationModelsService()
            let availability = SystemLanguageModel.default.availability
            if case .available = availability { modelState = .available }
            else { modelState = .unavailable(String(describing: availability)) }
        }
    }

    func load() async {
        guard let store else { return }
        do {
            if launchArguments.contains("-PKResetDatabase"), !didApplyLaunchReset {
                try await store.reset()
                didApplyLaunchReset = true
            }
            installed = try await store.installedApps()
            activity = try await store.activity()
            storageBytes = try await store.storageBytes()
            syncIntentEntities()
            if let requested = UserDefaults.standard.string(forKey: "PKRequestedAppID"), let id = UUID(uuidString: requested), let app = installed.first(where: { $0.id == id && !$0.disabled }) {
                pendingOpenApp = app.manifest
                UserDefaults.standard.removeObject(forKey: "PKRequestedAppID")
            }
        } catch {
            startupError = error.localizedDescription
        }
    }

    func generate(_ prompt: String, capabilities: Set<PocketCapability>) async {
        guard let store else { generationError = startupError ?? "Database is unavailable."; return }
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { generationError = "Describe the app you want to create."; return }
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }
        do {
            try await store.log(appID: nil, level: .info, category: "generation", message: "Started blueprint generation.")
            let context = BuilderContext(localeIdentifier: Locale.current.identifier, requestedCapabilities: capabilities, existingManifest: draft)
            let blueprint: MicroAppBlueprint
            do {
                blueprint = try await generator.generateBlueprint(from: normalized, context: context)
            } catch let error as FoundationModelError {
                modelState = .unavailable(error.localizedDescription)
                blueprint = try await fallbackGenerator.generateBlueprint(from: normalized, context: context)
                generationError = "Apple Intelligence was unavailable, so PocketKernel created a complete editable template instead. \(error.localizedDescription)"
            }
            let manifest = BlueprintConverter().convert(blueprint, capabilities: capabilities)
            let issues = ManifestValidator().validate(manifest)
            previousDraft = draft
            draft = manifest
            validationIssues = issues
            if issues.contains(where: { $0.severity == .error }) {
                throw PackageError.invalidManifest(issues.filter { $0.severity == .error })
            }
            try await store.log(appID: nil, level: .info, category: "generation", message: "Generated and validated \(manifest.name).")
            await load()
        } catch {
            generationError = error.localizedDescription
            try? await store.log(appID: nil, level: .error, category: "generation", message: error.localizedDescription)
            await load()
        }
    }

    func validateDraft() {
        guard let draft else { validationIssues = []; return }
        validationIssues = ManifestValidator().validate(draft)
    }

    func undoDraft() {
        let current = draft
        draft = previousDraft
        previousDraft = current
        validateDraft()
    }

    func installDraft() async {
        guard let store, let draft else { return }
        do {
            let package = try PackageCodec().makePackage(manifest: draft)
            try await store.install(package)
            try await store.log(appID: draft.id, level: .info, category: "install", message: "Installed \(draft.name).")
            self.draft = nil
            previousDraft = nil
            validationIssues = []
            await load()
        } catch { generationError = error.localizedDescription }
    }

    func installTemplate(_ blueprint: MicroAppBlueprint) async {
        guard let store else { return }
        do {
            let manifest = BlueprintConverter().convert(blueprint, capabilities: blueprint == TemplateCatalog.serviceLogBlueprint ? [.localNotifications] : [])
            try await store.install(PackageCodec().makePackage(manifest: manifest))
            try await store.log(appID: manifest.id, level: .info, category: "install", message: "Installed built-in template \(manifest.name).")
            await load()
        } catch { startupError = error.localizedDescription }
    }

    func importPackage(_ data: Data) async throws {
        guard let store else { throw StoreError.invalidData }
        let package = try PackageCodec().decode(data)
        try await store.install(package)
        try await store.log(appID: package.manifest.id, level: .info, category: "import", message: "Imported \(package.manifest.name).")
        await load()
    }

    func exportPackage(_ manifest: MicroAppManifest) async throws -> Data {
        guard let store else { throw StoreError.invalidData }
        let data = try await store.exportPackage(appID: manifest.id)
        lastExportedPackage = data
        await load()
        return data
    }

    func importLastExportForTesting() async throws {
        guard launchArguments.contains("-PKUITesting"), let data = lastExportedPackage else { throw StoreError.invalidData }
        try await importPackage(data)
    }

    func open(_ app: InstalledAppInfo) async {
        guard !app.disabled, let store else { return }
        do {
            try await store.markOpened(id: app.id)
            try await store.log(appID: app.id, level: .info, category: "runtime", message: "Opened \(app.manifest.name).")
            pendingOpenApp = app.manifest
            lifecycle.markRuntimeOpen(appID: app.id)
            await load()
        } catch { startupError = error.localizedDescription }
    }

    func delete(_ id: UUID) async {
        guard let store else { return }
        do { try await store.delete(id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func duplicate(_ id: UUID) async {
        guard let store else { return }
        do { _ = try await store.duplicate(id: id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func rename(_ id: UUID, name: String) async {
        guard let store else { return }
        do { try await store.rename(id: id, name: name); await load() }
        catch { startupError = error.localizedDescription }
    }

    func toggleFavorite(_ app: InstalledAppInfo) async {
        guard let store else { return }
        do { try await store.setFavorite(!app.favorite, id: app.id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func setDisabled(_ disabled: Bool, id: UUID) async {
        guard let store else { return }
        do { try await store.setDisabled(disabled, id: id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func rollback(_ id: UUID) async {
        guard let store else { return }
        do { try await store.rollbackManifest(id: id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func resetAllData() async {
        guard let store else { return }
        do {
            try await store.reset()
            draft = nil
            previousDraft = nil
            lastExportedPackage = nil
            lifecycle.dismissRecovery()
            await load()
        } catch { startupError = error.localizedDescription }
    }

    func assetData(appID: UUID, assetID: String) async -> Data? {
        guard let store else { return nil }
        return try? await store.asset(appID: appID, id: assetID)?.data
    }

    func clearError() { startupError = nil }

    private func syncIntentEntities() {
        struct Snapshot: Codable { var id: String; var name: String }
        let snapshots = installed.filter { !$0.disabled }.map { Snapshot(id: $0.id.uuidString, name: $0.manifest.name) }
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshots), forKey: "PKIntentEntities")
    }

    private static func argumentValue(_ key: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func makeLayout() -> PocketStorageLayout {
        if let layout = try? PocketStorageLayout.make() { return layout }
        let root = FileManager.default.temporaryDirectory.appending(path: "PocketKernel", directoryHint: .isDirectory)
        let layout = PocketStorageLayout(
            root: root,
            packages: root.appending(path: "Packages", directoryHint: .isDirectory),
            assets: root.appending(path: "Assets", directoryHint: .isDirectory),
            exports: root.appending(path: "Exports", directoryHint: .isDirectory),
            recovery: root.appending(path: "Recovery", directoryHint: .isDirectory)
        )
        for directory in [layout.root, layout.packages, layout.assets, layout.exports, layout.recovery] { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        return layout
    }
}
