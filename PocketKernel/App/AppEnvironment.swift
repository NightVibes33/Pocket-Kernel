import Foundation
import Observation

@MainActor @Observable
final class AppEnvironment {
    var apps: [MicroAppManifest] = []
    var draft: MicroAppManifest?
    var generationError: String?
    var isGenerating = false
    let store: PocketStore?
    let generator: any BlueprintGenerating

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        generator = arguments.contains("mock") || arguments.contains("-PKModelMode") ? MockBlueprintGenerator() : FoundationModelBlueprintGenerator()
        store = try? PocketStore(inMemory: arguments.contains("-PKResetDatabase"))
    }

    func load() async { guard let store else { apps = []; return }; apps = (try? await store.installedApps()) ?? [] }

    func generate(_ prompt: String) async {
        isGenerating = true; generationError = nil
        defer { isGenerating = false }
        do {
            let blueprint: MicroAppBlueprint
            do { blueprint = try await generator.generateBlueprint(from: prompt, context: .init(localeIdentifier: Locale.current.identifier, requestedCapabilities: [])) }
            catch { blueprint = try await TemplateBlueprintGenerator().generateBlueprint(from: prompt, context: .init(localeIdentifier: Locale.current.identifier, requestedCapabilities: [])); generationError = error.localizedDescription }
            let candidate = BlueprintConverter().convert(blueprint, capabilities: [])
            let issues = ManifestValidator().validate(candidate).filter { $0.severity == .error }
            guard issues.isEmpty else { generationError = issues.map(\.message).joined(separator: " "); return }
            draft = candidate
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
        do { let package = try PackageCodec().decode(data); try await store.install(package.manifest); await load() }
        catch { generationError = error.localizedDescription }
    }

    func exportPackage(_ manifest: MicroAppManifest) -> Data? {
        let codec = PackageCodec()
        return try? codec.encode(codec.makePackage(manifest: manifest))
    }
}
