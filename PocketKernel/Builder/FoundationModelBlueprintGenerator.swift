import Foundation
import FoundationModels

@Generable(description: "A field in a local declarative app collection")
struct FoundationGeneratedField {
    @Guide(description: "Stable short identifier using letters and numbers") var id: String
    @Guide(description: "Human-readable field label") var title: String
    @Guide(description: "One of text, multilineText, number, boolean, date, choice, image") var kind: String
    @Guide(description: "Whether the person must enter this field") var required: Bool
    @Guide(description: "Choice values, otherwise an empty list", .count(0...12)) var options: [String]
}

@Generable(description: "A persistent collection in a local declarative app")
struct FoundationGeneratedCollection {
    @Guide(description: "Stable short identifier") var id: String
    @Guide(description: "Plural human-readable collection name") var title: String
    @Guide(description: "One to twelve useful fields", .count(1...12)) var fields: [FoundationGeneratedField]
}

@Generable(description: "A typed native component on a declarative app screen")
struct FoundationGeneratedComponent {
    @Guide(description: "Stable unique component identifier") var id: String
    @Guide(description: "Exact supported component kind") var kind: String
    @Guide(description: "Optional parent component identifier, otherwise empty") var parentID: String
    @Guide(description: "Visible title, otherwise empty") var title: String
    @Guide(description: "Visible text or binding template, otherwise empty") var text: String
    @Guide(description: "State binding such as state.searchText, otherwise empty") var binding: String
    @Guide(description: "Collection identifier used by the component, otherwise empty") var collectionID: String
    @Guide(description: "Action identifier invoked by the component, otherwise empty") var actionID: String
    @Guide(description: "Picker or menu options, otherwise an empty list", .count(0...12)) var options: [String]
    @Guide(description: "Visibility expression, otherwise empty") var visibilityExpression: String
    @Guide(description: "Disabled expression, otherwise empty") var disabledExpression: String
    @Guide(description: "Record filter expression, otherwise empty") var filterExpression: String
    @Guide(description: "Field used for sorting, otherwise empty") var sortField: String
    @Guide(description: "Sort in ascending order") var sortAscending: Bool
    @Guide(description: "Field used as a chart or row label, otherwise empty") var labelField: String
    @Guide(description: "Numeric field used as a chart value, otherwise empty") var valueField: String
    @Guide(description: "One of bar, line, area, otherwise empty") var chartStyle: String
}

@Generable(description: "A native screen containing typed declarative components")
struct FoundationGeneratedScreen {
    @Guide(description: "Stable short identifier") var id: String
    @Guide(description: "Screen title") var title: String
    @Guide(description: "Primary collection identifier, or empty when not needed") var collectionID: String
    @Guide(description: "One to twenty useful components", .count(1...20)) var components: [FoundationGeneratedComponent]
}

@Generable(description: "A typed value parameter for a declarative action")
struct FoundationGeneratedParameter {
    @Guide(description: "Parameter key") var key: String
    @Guide(description: "One of string, number, bool") var valueType: String
    @Guide(description: "The value represented as text") var value: String
}

@Generable(description: "A bounded native action in a declarative app")
struct FoundationGeneratedAction {
    @Guide(description: "Stable unique action identifier") var id: String
    @Guide(description: "Human-readable action title") var title: String
    @Guide(description: "Exact supported action kind") var kind: String
    @Guide(description: "Screen, collection, URL, or state target; otherwise empty") var target: String
    @Guide(description: "Optional literal value, otherwise empty") var value: String
    @Guide(description: "One of string, number, bool, otherwise empty") var valueType: String
    @Guide(description: "Declared capability required by this action, otherwise empty") var requiredCapability: String
    @Guide(description: "Boolean condition expression, otherwise empty") var conditionExpression: String
    @Guide(description: "Plain-language permission reason, otherwise empty") var reason: String
    @Guide(description: "Bounded action parameters", .count(0...8)) var parameters: [FoundationGeneratedParameter]
    @Guide(description: "Action identifiers to run next", .count(0...6)) var nextActionIDs: [String]
}

@Generable(description: "A complete bounded native micro-app blueprint")
struct FoundationGeneratedBlueprint {
    @Guide(description: "Short application name") var name: String
    @Guide(description: "One sentence explaining the app") var summary: String
    @Guide(description: "One to eight useful screens", .count(1...8)) var screens: [FoundationGeneratedScreen]
    @Guide(description: "Zero to eight persistent collections", .count(0...8)) var collections: [FoundationGeneratedCollection]
    @Guide(description: "Zero to twelve typed actions", .count(0...12)) var actions: [FoundationGeneratedAction]
    @Guide(description: "Exact HTTPS hostnames needed by network actions, otherwise empty", .count(0...6)) var allowedDomains: [String]
}

struct FoundationModelBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw FoundationModelError.unavailable(String(describing: model.availability))
        }

        let existing = context.existingManifest.map { manifest in
            "The user is editing an app named \(manifest.name). Preserve useful concepts while applying the requested change. Existing screens: \(manifest.screens.map(\.title).joined(separator: ", "))."
        } ?? "Create a new app."
        let capabilities = context.requestedCapabilities.map(\.rawValue).sorted().joined(separator: ", ")
        let componentKinds = ComponentKind.allCases.map(\.rawValue).joined(separator: ", ")
        let actionKinds = ActionKind.allCases.map(\.rawValue).joined(separator: ", ")

        let instructions = """
        Fill a typed declarative blueprint for a useful native personal micro-app.
        Design the actual screens and components needed for the request; do not force every app into the same tracker layout.
        Supported component kinds: \(componentKinds).
        Supported action kinds: \(actionKinds).
        Use parentID to nest components inside layout components. Parent IDs must be on the same screen.
        Component collectionID and actionID references must match generated collections and actions.
        Navigation targets must match generated screen IDs. Record action targets must match collection IDs.
        Only use these approved capabilities: \(capabilities.isEmpty ? "none" : capabilities).
        Use an exact HTTPS hostname in allowedDomains only when a requested network action needs it. Never use wildcards.
        Never produce source code, JavaScript, WebAssembly, SQL, executable content, credentials, private APIs, or filesystem paths.
        Keep text concise and make the result useful without network or AI when those capabilities were not approved.
        \(existing)
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: request, generating: FoundationGeneratedBlueprint.self)
        return BlueprintRepairer().repair(convert(response.content))
    }

    private func convert(_ generated: FoundationGeneratedBlueprint) -> MicroAppBlueprint {
        let collections = generated.collections.map { collection in
            GeneratedCollection(
                id: slug(collection.id),
                title: collection.title,
                fields: collection.fields.map { field in
                    GeneratedField(
                        id: slug(field.id),
                        title: field.title,
                        kind: FieldKind(rawValue: field.kind) ?? .text,
                        options: field.options,
                        required: field.required
                    )
                }
            )
        }
        let actions = generated.actions.compactMap { action -> GeneratedAction? in
            guard let kind = ActionKind(rawValue: action.kind) else { return nil }
            let parameters = Dictionary(uniqueKeysWithValues: action.parameters.map { parameter in
                (slug(parameter.key), typedValue(parameter.value, type: parameter.valueType))
            })
            return GeneratedAction(
                id: slug(action.id),
                title: action.title,
                kind: kind,
                target: emptyToNil(action.target).map(slugReference),
                value: emptyToNil(action.value).map { typedValue($0, type: action.valueType) },
                requiredCapability: PocketCapability(rawValue: action.requiredCapability),
                condition: emptyToNil(action.conditionExpression),
                reason: emptyToNil(action.reason),
                parameters: parameters,
                nextActionIDs: action.nextActionIDs.map(slug)
            )
        }
        let screens = generated.screens.map { screen in
            GeneratedScreen(
                id: slug(screen.id),
                title: screen.title,
                collectionID: emptyToNil(screen.collectionID).map(slug),
                components: componentTree(screen.components)
            )
        }
        return MicroAppBlueprint(
            name: generated.name,
            summary: generated.summary,
            screens: screens,
            collections: collections,
            actions: actions,
            allowedDomains: generated.allowedDomains
        )
    }

    private func componentTree(_ flat: [FoundationGeneratedComponent]) -> [GeneratedComponent] {
        let normalized = flat.map { source in
            FlatComponent(
                parentID: emptyToNil(source.parentID).map(slug),
                component: GeneratedComponent(
                    id: slug(source.id),
                    kind: ComponentKind(rawValue: source.kind) ?? .text,
                    title: emptyToNil(source.title),
                    text: emptyToNil(source.text),
                    binding: emptyToNil(source.binding),
                    collection: emptyToNil(source.collectionID).map(slug),
                    actionID: emptyToNil(source.actionID).map(slug),
                    options: source.options,
                    visibilityExpression: emptyToNil(source.visibilityExpression),
                    disabledExpression: emptyToNil(source.disabledExpression),
                    filterExpression: emptyToNil(source.filterExpression),
                    sortField: emptyToNil(source.sortField).map(slug),
                    sortAscending: source.sortAscending,
                    labelField: emptyToNil(source.labelField).map(slug),
                    valueField: emptyToNil(source.valueField).map(slug),
                    chartStyle: ChartStyle(rawValue: source.chartStyle)
                )
            )
        }
        let ids = Set(normalized.map(\.component.id))
        let children = Dictionary(grouping: normalized.filter { $0.parentID.map(ids.contains) == true }, by: { $0.parentID! })
        let roots = normalized.filter { $0.parentID == nil || !ids.contains($0.parentID!) }
        var visited = Set<String>()
        return roots.compactMap { build($0.component, children: children, visited: &visited, depth: 1) }
    }

    private func build(
        _ source: GeneratedComponent,
        children: [String: [FlatComponent]],
        visited: inout Set<String>,
        depth: Int
    ) -> GeneratedComponent? {
        guard depth <= PocketLimits.nestingDepth, visited.insert(source.id).inserted else { return nil }
        var result = source
        result.children = (children[source.id] ?? []).compactMap {
            build($0.component, children: children, visited: &visited, depth: depth + 1)
        }
        return result
    }

    private struct FlatComponent {
        var parentID: String?
        var component: GeneratedComponent
    }

    private func typedValue(_ value: String, type: String) -> PocketValue {
        switch type {
        case "number": .number(Double(value) ?? 0)
        case "bool": .bool(["true", "1", "yes"].contains(value.lowercased()))
        default: .string(value)
        }
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func slugReference(_ value: String) -> String {
        if value.hasPrefix("https://") || value.hasPrefix("state.") { return value }
        return slug(value)
    }

    private func slug(_ value: String) -> String {
        let characters = value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let result = String(characters).split(separator: "-").joined(separator: "-")
        return result.isEmpty ? "item" : String(result.prefix(80))
    }
}

enum FoundationModelError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Apple Intelligence unavailable: \(reason)"
        }
    }
}
