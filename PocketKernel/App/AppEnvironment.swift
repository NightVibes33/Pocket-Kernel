import Foundation
import Observation

@MainActor @Observable
final class AppEnvironment {
    var apps: [MicroAppManifest] = []
    var draft: MicroAppManifest?
    var generationError: String?
    var isGenerating = false
    var activity: [ActivityEvent] = []
    var pendingOpenApp: MicroAppManifest?
    let store: PocketStore?
    let generator: any BlueprintGenerating
    let lifecycle = AppLifecycleController()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PKUITesting") { UserDefaults.standard.set(true, forKey: "PKOnboardingComplete") }
        if arguments.contains("-PKResetDatabase") {
            let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "PocketKernel")
            for name in ["pocketkernel.sqlite", "pocketkernel.sqlite-wal", "pocketkernel.sqlite-shm"] { if let url = root?.appending(path: name) { try? FileManager.default.removeItem(at: url) } }
        }
        generator = arguments.contains("mock") || arguments.contains("-PKModelMode") ? MockBlueprintGenerator() : FoundationModelBlueprintGenerator()
        store = try? PocketStore()
    }

    func load() async {
        guard let store else { apps = []; activity = []; return }
        apps = (try? await store.installedApps()) ?? []; activity = (try? await store.activity()) ?? []
        let snapshots = apps.map { ["id": $0.id.uuidString, "name": $0.name] }
        if let data = try? JSONSerialization.data(withJSONObject: snapshots) { UserDefaults.standard.set(data, forKey: "PKIntentEntities") }
        if let requested = UserDefaults.standard.string(forKey: "PKRequestedAppID"), let id = UUID(uuidString: requested) { pendingOpenApp = apps.first { $0.id == id }; UserDefaults.standard.removeObject(forKey: "PKRequestedAppID") }
    }

    func generate(_ prompt: String, capabilities: Set<PocketCapability> = []) async {
        isGenerating = true; generationError = nil
        defer { isGenerating = false }
        do {
            let normalized = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
            let blueprint: MicroAppBlueprint
            do { blueprint = try await generator.generateBlueprint(from: normalized, context: .init(localeIdentifier: Locale.current.identifier, requestedCapabilities: capabilities)) }
            catch { blueprint = try await TemplateBlueprintGenerator().generateBlueprint(from: normalized, context: .init(localeIdentifier: Locale.current.identifier, requestedCapabilities: capabilities)); generationError = error.localizedDescription }
            var candidate = BlueprintConverter().convert(BlueprintRepairer().repair(blueprint), capabilities: capabilities)
            var issues = ManifestValidator().validate(candidate).filter { $0.severity == .error }
            if !issues.isEmpty {
                let repairPrompt = normalized + "\nRepair these blueprint problems: " + issues.map(\.message).joined(separator: "; ")
                do {
                    let retry = try await generator.generateBlueprint(from: repairPrompt, context: .init(localeIdentifier: Locale.current.identifier, requestedCapabilities: capabilities))
                    candidate = BlueprintConverter().convert(BlueprintRepairer().repair(retry), capabilities: capabilities); issues = ManifestValidator().validate(candidate).filter { $0.severity == .error }
                } catch {}
            }
            guard issues.isEmpty else { generationError = issues.map(\.message).joined(separator: " "); return }
            draft = candidate
            if let store { try? await store.log(appID: nil, level: .info, category: "generation", message: "Generated \(candidate.name)") }
        } catch { generationError = error.localizedDescription }
    }

    func installDraft() async {
        guard let draft else { return }
        guard let store else { generationError = "Local database could not be opened."; return }
        try? await store.install(draft); self.draft = nil; await load()
    }

    func delete(_ id: UUID) async { guard let store else { return }; try? await store.delete(id); await load() }

    func installTemplate(named name: String) async {
        let blueprint: MicroAppBlueprint
        switch name {
        case "Task Board": blueprint = .taskBoard
        case "Habit Tracker": blueprint = .habitTracker
        case "Quick Journal": blueprint = .quickJournal
        case "Inventory List": blueprint = .inventory
        default: blueprint = .serviceLog
        }
        guard let store else { generationError = "Local database could not be opened."; return }
        let manifest = BlueprintConverter().convert(blueprint, capabilities: [])
        try? await store.install(manifest); await load()
    }

    func importPackage(_ data: Data) async {
        guard let store else { generationError = "Local database could not be opened."; return }
        do { let package = try PackageCodec().decode(data); try await store.install(package.manifest); try await store.log(appID: package.manifest.id, level: .info, category: "package", message: "Imported package"); await load() }
        catch { generationError = error.localizedDescription }
    }

    func exportPackage(_ manifest: MicroAppManifest) -> Data? {
        let codec = PackageCodec()
        return try? codec.encode(codec.makePackage(manifest: manifest))
    }

    func duplicate(_ manifest: MicroAppManifest) async {
        guard let store else { return }
        var copy = manifest; copy.id = UUID(); copy.name += " Copy"; copy.createdAt = Date(); copy.updatedAt = copy.createdAt
        try? await store.install(copy); try? await store.log(appID: copy.id, level: .info, category: "library", message: "Duplicated \(manifest.name)"); await load()
    }

    func resetAllData() async { guard let store else { return }; try? await store.reset(); draft = nil; pendingOpenApp = nil; await load() }
}
