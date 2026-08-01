import AppIntents
import Foundation

struct MicroAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pocket App")
    static let defaultQuery = MicroAppEntityQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct MicroAppEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MicroAppEntity] { allEntities.filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [MicroAppEntity] { allEntities.filter { $0.name.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [MicroAppEntity] { allEntities }
    private var allEntities: [MicroAppEntity] {
        guard let data = UserDefaults.standard.data(forKey: "PKIntentEntities") else { return [] }
        return (try? JSONDecoder().decode([MicroAppEntitySnapshot].self, from: data))?.map { MicroAppEntity(id: $0.id, name: $0.name) } ?? []
    }
}

private struct MicroAppEntitySnapshot: Codable { let id: String; let name: String }

struct OpenMicroAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Pocket App"
    static let description = IntentDescription("Open an installed declarative app in PocketKernel.")
    static let openAppWhenRun = true
    @Parameter(title: "Pocket App") var app: MicroAppEntity
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(app.id, forKey: "PKRequestedAppID")
        return .result()
    }
}

struct PocketKernelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenMicroAppIntent(), phrases: ["Open \(.$app) in \(.applicationName)", "Run \(.$app) in \(.applicationName)"], shortTitle: "Open Pocket App", systemImageName: "square.grid.2x2.fill")
    }
}
