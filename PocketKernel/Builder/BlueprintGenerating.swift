import Foundation

struct BuilderContext: Sendable {
    var localeIdentifier: String
    var requestedCapabilities: Set<PocketCapability>
    var existingManifest: MicroAppManifest? = nil
}

struct GeneratedField: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var kind: FieldKind = .text
}

struct GeneratedCollection: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var fields: [GeneratedField]
}

struct GeneratedScreen: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var collectionID: String?
}

struct GeneratedAction: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var kind: ActionKind
    var target: String?
}

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
        TemplateCatalog.serviceLogBlueprint
    }
}

struct TemplateBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        let words = Set(request.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let scored = TemplateCatalog.all.map { blueprint -> (MicroAppBlueprint, Int) in
            let haystack = Set((blueprint.name + " " + blueprint.summary + " " + blueprint.collections.map(\.title).joined(separator: " ")).lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            return (blueprint, words.intersection(haystack).count)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0 ?? TemplateCatalog.serviceLogBlueprint
    }
}

enum TemplateCatalog {
    static let all = [taskBoardBlueprint, habitTrackerBlueprint, quickJournalBlueprint, inventoryBlueprint, serviceLogBlueprint]

    static let taskBoardBlueprint = MicroAppBlueprint(
        name: "Task Board", summary: "Plan work, track status, and review completed tasks.",
        screens: [.init(id: "dashboard", title: "Task Board", collectionID: "tasks"), .init(id: "all-tasks", title: "All Tasks", collectionID: "tasks")],
        collections: [.init(id: "tasks", title: "Tasks", fields: [
            .init(id: "title", title: "Title", kind: .text), .init(id: "status", title: "Status", kind: .choice),
            .init(id: "dueDate", title: "Due Date", kind: .date), .init(id: "notes", title: "Notes", kind: .multilineText)
        ])],
        actions: [.init(id: "add-task", title: "Add Task", kind: .createRecord, target: "tasks")]
    )

    static let habitTrackerBlueprint = MicroAppBlueprint(
        name: "Habit Tracker", summary: "Track daily habits and completed check-ins.",
        screens: [.init(id: "habits", title: "Habits", collectionID: "habits")],
        collections: [.init(id: "habits", title: "Habits", fields: [
            .init(id: "name", title: "Habit", kind: .text), .init(id: "completed", title: "Completed", kind: .boolean),
            .init(id: "checkInDate", title: "Check-in Date", kind: .date)
        ])],
        actions: [.init(id: "add-habit", title: "Add Habit", kind: .createRecord, target: "habits")]
    )

    static let quickJournalBlueprint = MicroAppBlueprint(
        name: "Quick Journal", summary: "Keep private dated journal entries on device.",
        screens: [.init(id: "journal", title: "Journal", collectionID: "entries")],
        collections: [.init(id: "entries", title: "Entries", fields: [
            .init(id: "date", title: "Date", kind: .date), .init(id: "title", title: "Title", kind: .text),
            .init(id: "entry", title: "Entry", kind: .multilineText)
        ])],
        actions: [.init(id: "add-entry", title: "New Entry", kind: .createRecord, target: "entries")]
    )

    static let inventoryBlueprint = MicroAppBlueprint(
        name: "Inventory List", summary: "Track items, quantities, locations, and notes.",
        screens: [.init(id: "inventory", title: "Inventory", collectionID: "items")],
        collections: [.init(id: "items", title: "Items", fields: [
            .init(id: "name", title: "Item", kind: .text), .init(id: "quantity", title: "Quantity", kind: .number),
            .init(id: "location", title: "Location", kind: .text), .init(id: "notes", title: "Notes", kind: .multilineText)
        ])],
        actions: [.init(id: "add-item", title: "Add Item", kind: .createRecord, target: "items")]
    )

    static let serviceLogBlueprint = MicroAppBlueprint(
        name: "Service Log", summary: "Track vehicle maintenance, cost, mileage, and reminders.",
        screens: [.init(id: "overview", title: "Service Overview", collectionID: "services"), .init(id: "history", title: "Service History", collectionID: "services")],
        collections: [.init(id: "services", title: "Services", fields: [
            .init(id: "mileage", title: "Mileage", kind: .number), .init(id: "serviceDate", title: "Service Date", kind: .date),
            .init(id: "cost", title: "Cost", kind: .number), .init(id: "notes", title: "Notes", kind: .multilineText),
            .init(id: "nextService", title: "Next Service", kind: .date)
        ])],
        actions: [.init(id: "add-service", title: "Add Service", kind: .createRecord, target: "services")]
    )
}

struct BlueprintConverter: Sendable {
    func convert(_ source: MicroAppBlueprint, capabilities: Set<PocketCapability>) -> MicroAppManifest {
        let blueprint = BlueprintRepairer().repair(source)
        let now = Date()
        let collections = blueprint.collections.map { collection in
            CollectionSpec(id: collection.id, title: collection.title, fields: collection.fields.map { field in
                let defaultValue: PocketValue
                switch field.kind {
                case .number: defaultValue = .number(0)
                case .boolean: defaultValue = .bool(false)
                case .date: defaultValue = .date(now)
                default: defaultValue = .string("")
                }
                return FieldSpec(id: field.id, title: field.title, kind: field.kind, defaultValue: defaultValue)
            })
        }
        let actions = blueprint.actions.map { ActionSpec(id: $0.id, kind: $0.kind, title: $0.title, target: $0.target) }
        let screens = blueprint.screens.enumerated().map { index, screen in
            let collection = screen.collectionID
            var components: [ComponentSpec] = [
                .init(id: "\(screen.id)-heading", kind: .heading, title: screen.title, text: screen.title)
            ]
            if let collection {
                if index == 0 {
                    components.append(.init(id: "\(screen.id)-metric", kind: .metric, title: "Records", text: "{{ count(collections.\(collection)) }}"))
                }
                components.append(.init(id: "\(screen.id)-search", kind: .searchResults, title: "Search", binding: "state.searchText", collection: collection))
                if let action = actions.first(where: { $0.target == collection && $0.kind == .createRecord }) {
                    components.append(.init(id: "\(screen.id)-create", kind: .button, title: action.title, actionID: action.id))
                }
                components.append(.init(id: "\(screen.id)-chart", kind: .chart, title: "Overview", collection: collection, valueField: collections.first(where: { $0.id == collection })?.fields.first(where: { $0.kind == .number })?.id))
            } else {
                components.append(.init(id: "\(screen.id)-empty", kind: .emptyState, title: "No collection configured"))
            }
            return ScreenSpec(id: screen.id, title: screen.title, components: components)
        }
        return MicroAppManifest(id: UUID(), name: blueprint.name, summary: blueprint.summary,
                                entryScreenID: screens.first?.id ?? "home", screens: screens, actions: actions,
                                collections: collections, capabilities: capabilities, createdAt: now, updatedAt: now)
    }
}

struct BlueprintRepairer: Sendable {
    func repair(_ source: MicroAppBlueprint) -> MicroAppBlueprint {
        var result = source
        result.name = cleanTitle(result.name, fallback: "Pocket App")
        result.summary = cleanTitle(result.summary, fallback: "A locally generated Pocket App")
        result.collections = uniqueCollections(Array(result.collections.prefix(8)).enumerated().map { index, collection in
            let fields = uniqueFields(Array(collection.fields.prefix(12)).enumerated().map { fieldIndex, field in
                GeneratedField(id: cleanID(field.id, fallback: "field-\(fieldIndex + 1)"), title: cleanTitle(field.title, fallback: "Field \(fieldIndex + 1)"), kind: field.kind)
            })
            return GeneratedCollection(id: cleanID(collection.id, fallback: "collection-\(index + 1)"), title: cleanTitle(collection.title, fallback: "Records"), fields: fields.isEmpty ? [.init(id: "title", title: "Title")] : fields)
        })
        if result.collections.isEmpty { result.collections = [.init(id: "records", title: "Records", fields: [.init(id: "title", title: "Title")])] }
        let collectionIDs = Set(result.collections.map(\.id))
        result.screens = uniqueScreens(Array(result.screens.prefix(8)).enumerated().map { index, screen in
            GeneratedScreen(id: cleanID(screen.id, fallback: "screen-\(index + 1)"), title: cleanTitle(screen.title, fallback: "Screen \(index + 1)"), collectionID: screen.collectionID.flatMap { collectionIDs.contains($0) ? $0 : nil } ?? result.collections.first?.id)
        })
        if result.screens.isEmpty { result.screens = [.init(id: "home", title: result.name, collectionID: result.collections.first?.id)] }
        result.actions = uniqueActions(Array(result.actions.prefix(12)).enumerated().map { index, action in
            GeneratedAction(id: cleanID(action.id, fallback: "action-\(index + 1)"), title: cleanTitle(action.title, fallback: "Action"), kind: action.kind, target: action.target.flatMap { collectionIDs.contains($0) ? $0 : nil } ?? (action.kind == .createRecord ? result.collections.first?.id : action.target))
        })
        if !result.collections.isEmpty && !result.actions.contains(where: { $0.kind == .createRecord }) {
            result.actions.append(.init(id: "add-record", title: "Add Record", kind: .createRecord, target: result.collections[0].id))
        }
        return result
    }

    private func cleanID(_ value: String, fallback: String) -> String {
        let cleaned = value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let result = String(cleaned).split(separator: "-").joined(separator: "-")
        return result.isEmpty ? fallback : result
    }

    private func cleanTitle(_ value: String, fallback: String) -> String {
        let result = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return result.isEmpty ? fallback : result
    }

    private func uniqueFields(_ values: [GeneratedField]) -> [GeneratedField] { unique(values, key: \.id) }
    private func uniqueCollections(_ values: [GeneratedCollection]) -> [GeneratedCollection] { unique(values, key: \.id) }
    private func uniqueScreens(_ values: [GeneratedScreen]) -> [GeneratedScreen] { unique(values, key: \.id) }
    private func uniqueActions(_ values: [GeneratedAction]) -> [GeneratedAction] { unique(values, key: \.id) }

    private func unique<T>(_ values: [T], key: KeyPath<T, String>) -> [T] {
        var seen = Set<String>()
        return values.filter { seen.insert($0[keyPath: key]).inserted }
    }
}
