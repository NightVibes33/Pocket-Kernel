import Foundation

struct BuilderContext: Sendable { var localeIdentifier: String; var requestedCapabilities: Set<PocketCapability> }

struct GeneratedField: Codable, Sendable, Equatable { var id: String; var title: String }
struct GeneratedCollection: Codable, Sendable, Equatable { var id: String; var title: String; var fields: [GeneratedField] }
struct GeneratedScreen: Codable, Sendable, Equatable { var id: String; var title: String; var collectionID: String? }
struct GeneratedAction: Codable, Sendable, Equatable { var id: String; var title: String; var kind: ActionKind; var target: String? }
struct MicroAppBlueprint: Codable, Sendable, Equatable {
    var name: String
    var summary: String
    var screens: [GeneratedScreen]
    var collections: [GeneratedCollection]
    var actions: [GeneratedAction]
}

protocol BlueprintGenerating: Sendable {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint
}

struct MockBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        .serviceLog
    }
}

struct TemplateBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        let normalized = request.lowercased()
        if normalized.contains("habit") { return .habitTracker }
        if normalized.contains("inventory") { return .inventory }
        return .serviceLog
    }
}

extension MicroAppBlueprint {
    static let serviceLog = MicroAppBlueprint(
        name: "Service Log", summary: "Track maintenance and upcoming service",
        screens: [.init(id: "home", title: "Service Log", collectionID: "services")],
        collections: [.init(id: "services", title: "Services", fields: [
            .init(id: "mileage", title: "Mileage"), .init(id: "serviceDate", title: "Service Date"),
            .init(id: "cost", title: "Cost"), .init(id: "notes", title: "Notes")
        ])],
        actions: [.init(id: "add-service", title: "Add Service", kind: .createRecord, target: "services")]
    )
    static let habitTracker = MicroAppBlueprint(
        name: "Habit Tracker", summary: "Build consistent daily routines",
        screens: [.init(id: "home", title: "Habits", collectionID: "habits")],
        collections: [.init(id: "habits", title: "Habits", fields: [.init(id: "name", title: "Habit"), .init(id: "completed", title: "Completed")])],
        actions: [.init(id: "add-habit", title: "Add Habit", kind: .createRecord, target: "habits")]
    )
    static let inventory = MicroAppBlueprint(
        name: "Inventory List", summary: "Keep count of important items",
        screens: [.init(id: "home", title: "Inventory", collectionID: "items")],
        collections: [.init(id: "items", title: "Items", fields: [.init(id: "name", title: "Item"), .init(id: "quantity", title: "Quantity")])],
        actions: [.init(id: "add-item", title: "Add Item", kind: .createRecord, target: "items")]
    )
    static let taskBoard = MicroAppBlueprint(
        name: "Task Board", summary: "Capture and complete tasks",
        screens: [.init(id: "home", title: "Tasks", collectionID: "tasks")],
        collections: [.init(id: "tasks", title: "Tasks", fields: [.init(id: "title", title: "Title"), .init(id: "status", title: "Status")])],
        actions: [.init(id: "add-task", title: "Add Task", kind: .createRecord, target: "tasks")]
    )
    static let quickJournal = MicroAppBlueprint(
        name: "Quick Journal", summary: "Keep private daily notes",
        screens: [.init(id: "home", title: "Journal", collectionID: "entries")],
        collections: [.init(id: "entries", title: "Entries", fields: [.init(id: "date", title: "Date"), .init(id: "entry", title: "Entry")])],
        actions: [.init(id: "add-entry", title: "Add Entry", kind: .createRecord, target: "entries")]
    )
}

struct BlueprintConverter: Sendable {
    func convert(_ blueprint: MicroAppBlueprint, capabilities: Set<PocketCapability>) -> MicroAppManifest {
        let now = Date()
        let actions = blueprint.actions.map { ActionSpec(id: $0.id, kind: $0.kind, title: $0.title, target: $0.target) }
        let screens = blueprint.screens.map { screen in
            let list = ComponentSpec(id: "\(screen.id)-content", kind: screen.collectionID == nil ? .emptyState : .list,
                                     title: screen.title, collection: screen.collectionID)
            let matching = blueprint.actions.first { $0.target == screen.collectionID }
            let button = matching.map { ComponentSpec(id: "\(screen.id)-primary", kind: .button, title: $0.title, actionID: $0.id) }
            return ScreenSpec(id: screen.id, title: screen.title, components: [list] + [button].compactMap { $0 })
        }
        let collections = blueprint.collections.map { collection in
            CollectionSpec(id: collection.id, title: collection.title,
                           fields: collection.fields.map { FieldSpec(id: $0.id, title: $0.title, defaultValue: .string("")) })
        }
        return MicroAppManifest(id: UUID(), name: blueprint.name, summary: blueprint.summary,
                                entryScreenID: screens.first?.id ?? "home", screens: screens, actions: actions,
                                collections: collections, capabilities: capabilities, createdAt: now, updatedAt: now)
    }
}

struct BlueprintRepairer: Sendable {
    func repair(_ source: MicroAppBlueprint) -> MicroAppBlueprint {
        var blueprint = source
        blueprint.name = cleanTitle(blueprint.name, fallback: "Pocket App")
        blueprint.summary = cleanTitle(blueprint.summary, fallback: "A locally generated Pocket App")
        blueprint.collections = Array(blueprint.collections.prefix(8)).enumerated().map { index, collection in
            let id = cleanID(collection.id, fallback: "collection-\(index + 1)")
            let fields = Array(collection.fields.prefix(12)).enumerated().map { fieldIndex, field in GeneratedField(id: cleanID(field.id, fallback: "field-\(fieldIndex + 1)"), title: cleanTitle(field.title, fallback: "Field \(fieldIndex + 1)")) }
            return GeneratedCollection(id: id, title: cleanTitle(collection.title, fallback: "Records"), fields: fields.isEmpty ? [.init(id: "title", title: "Title")] : uniqueFields(fields))
        }
        if blueprint.collections.isEmpty { blueprint.collections = [.init(id: "records", title: "Records", fields: [.init(id: "title", title: "Title")])] }
        let collectionIDs = Set(blueprint.collections.map(\.id))
        blueprint.screens = Array(blueprint.screens.prefix(8)).enumerated().map { index, screen in
            let collectionID = screen.collectionID.flatMap { collectionIDs.contains($0) ? $0 : nil } ?? blueprint.collections.first?.id
            return GeneratedScreen(id: cleanID(screen.id, fallback: "screen-\(index + 1)"), title: cleanTitle(screen.title, fallback: "Screen \(index + 1)"), collectionID: collectionID)
        }
        if blueprint.screens.isEmpty { blueprint.screens = [.init(id: "home", title: blueprint.name, collectionID: blueprint.collections.first?.id)] }
        blueprint.actions = Array(blueprint.actions.prefix(12)).enumerated().map { index, action in
            let target = action.target.flatMap { collectionIDs.contains($0) ? $0 : nil } ?? (action.kind == .createRecord ? blueprint.collections.first?.id : action.target)
            return GeneratedAction(id: cleanID(action.id, fallback: "action-\(index + 1)"), title: cleanTitle(action.title, fallback: "Action"), kind: action.kind, target: target)
        }
        return blueprint
    }

    private func cleanID(_ value: String, fallback: String) -> String {
        let result = String(value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.split(separator: "-").joined(separator: "-"))
        return result.isEmpty ? fallback : result
    }
    private func cleanTitle(_ value: String, fallback: String) -> String { String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)).isEmpty ? fallback : String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
    private func uniqueFields(_ fields: [GeneratedField]) -> [GeneratedField] { var seen = Set<String>(); return fields.compactMap { field in seen.insert(field.id).inserted ? field : nil } }
}
