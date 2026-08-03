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
    var defaultValue: PocketValue? = nil
    var options: [String] = []
    var required: Bool = false
}

struct GeneratedCollection: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var fields: [GeneratedField]
}

struct GeneratedComponent: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var kind: ComponentKind
    var title: String? = nil
    var text: String? = nil
    var binding: String? = nil
    var collection: String? = nil
    var actionID: String? = nil
    var children: [GeneratedComponent] = []
    var options: [String] = []
    var minimum: Double? = nil
    var maximum: Double? = nil
    var visibilityExpression: String? = nil
    var disabledExpression: String? = nil
    var filterExpression: String? = nil
    var sortField: String? = nil
    var sortAscending: Bool? = nil
    var labelField: String? = nil
    var valueField: String? = nil
    var assetID: String? = nil
    var chartStyle: ChartStyle? = nil
}

struct GeneratedScreen: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var collectionID: String? = nil
    var components: [GeneratedComponent] = []
}

struct GeneratedAction: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var kind: ActionKind
    var target: String? = nil
    var value: PocketValue? = nil
    var requiredCapability: PocketCapability? = nil
    var condition: String? = nil
    var reason: String? = nil
    var parameters: [String: PocketValue] = [:]
    var nextActionIDs: [String] = []
}

struct MicroAppBlueprint: Codable, Sendable, Equatable {
    var name: String
    var summary: String
    var screens: [GeneratedScreen]
    var collections: [GeneratedCollection]
    var actions: [GeneratedAction]
    var allowedDomains: [String] = []
}

protocol BlueprintGenerating: Sendable {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint
}

struct BundledTemplate: Sendable, Identifiable, Equatable {
    var id: UUID { package.manifest.id }
    let package: PocketPackage

    var manifest: MicroAppManifest { package.manifest }
}

struct TemplatePackageLibrary: Sendable {
    func load(bundle: Bundle = .main) throws -> [BundledTemplate] {
        let urls = bundle.urls(forResourcesWithExtension: "pocketapp", subdirectory: "Templates") ?? []
        let packages = try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            BundledTemplate(package: try PackageCodec().decode(Data(contentsOf: url)))
        }
        guard !packages.isEmpty else { throw PackageError.malformed }
        return packages.sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
    }

    func blueprint(from manifest: MicroAppManifest, allowedCapabilities: Set<PocketCapability>? = nil) -> MicroAppBlueprint {
        let allowedActions = manifest.actions.filter { action in
            guard let capability = action.requiredCapability, let allowedCapabilities else { return true }
            return allowedCapabilities.contains(capability)
        }
        let actionIDs = Set(allowedActions.map(\.id))
        return MicroAppBlueprint(
            name: manifest.name,
            summary: manifest.summary,
            screens: manifest.screens.map { screen in
                GeneratedScreen(
                    id: screen.id,
                    title: screen.title,
                    collectionID: firstCollection(in: screen.components),
                    components: screen.components.map { generatedComponent(from: $0, allowedActionIDs: actionIDs) }
                )
            },
            collections: manifest.collections.map { collection in
                GeneratedCollection(
                    id: collection.id,
                    title: collection.title,
                    fields: collection.fields.map { field in
                        GeneratedField(
                            id: field.id,
                            title: field.title,
                            kind: field.kind,
                            defaultValue: field.defaultValue,
                            options: field.options,
                            required: field.required
                        )
                    }
                )
            },
            actions: allowedActions.map { action in
                GeneratedAction(
                    id: action.id,
                    title: action.title ?? action.kind.rawValue,
                    kind: action.kind,
                    target: action.target,
                    value: action.value,
                    requiredCapability: action.requiredCapability,
                    condition: action.condition,
                    reason: action.reason,
                    parameters: action.parameters,
                    nextActionIDs: action.nextActionIDs
                )
            },
            allowedDomains: manifest.allowedDomains
        )
    }

    private func generatedComponent(from component: ComponentSpec, allowedActionIDs: Set<String>) -> GeneratedComponent {
        GeneratedComponent(
            id: component.id,
            kind: component.kind,
            title: component.title,
            text: component.text,
            binding: component.binding,
            collection: component.collection,
            actionID: component.actionID.flatMap { allowedActionIDs.contains($0) ? $0 : nil },
            children: component.children.map { generatedComponent(from: $0, allowedActionIDs: allowedActionIDs) },
            options: component.options,
            minimum: component.minimum,
            maximum: component.maximum,
            visibilityExpression: component.visibilityExpression,
            disabledExpression: component.disabledExpression,
            filterExpression: component.filterExpression,
            sortField: component.sortField,
            sortAscending: component.sortAscending,
            labelField: component.labelField,
            valueField: component.valueField,
            assetID: component.assetID,
            chartStyle: component.chartStyle
        )
    }

    private func firstCollection(in components: [ComponentSpec]) -> String? {
        for component in components {
            if let collection = component.collection { return collection }
            if let nested = firstCollection(in: component.children) { return nested }
        }
        return nil
    }
}

struct MockBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        MockBlueprintFixture.blueprint
    }
}

private enum MockBlueprintFixture {
    static let blueprint = MicroAppBlueprint(
        name: "Service Log",
        summary: "Track vehicle maintenance, mileage, cost, and notes.",
        screens: [
            GeneratedScreen(
                id: "overview",
                title: "Service Overview",
                collectionID: "services",
                components: [
                    .init(id: "overview-title", kind: .heading, text: "Service Log"),
                    .init(
                        id: "overview-grid",
                        kind: .lazyGrid,
                        children: [
                            .init(id: "service-count", kind: .metric, title: "Services", text: "{{ count(collections.services) }}"),
                            .init(id: "service-cost", kind: .chart, title: "Service Cost", collection: "services", labelField: "serviceType", valueField: "cost", chartStyle: .bar)
                        ]
                    ),
                    .init(id: "open-history", kind: .button, title: "View History", actionID: "open-history"),
                    .init(id: "add-service-button", kind: .button, title: "Add Service", actionID: "add-service")
                ]
            ),
            GeneratedScreen(
                id: "history",
                title: "Service History",
                collectionID: "services",
                components: [
                    .init(id: "history-search", kind: .searchResults, title: "Search Services", binding: "state.serviceSearch", collection: "services", sortField: "serviceDate", sortAscending: false),
                    .init(id: "history-list", kind: .list, title: "All Services", collection: "services", sortField: "serviceDate", sortAscending: false),
                    .init(id: "service-form", kind: .recordForm, title: "New Service", collection: "services", actionID: "add-service")
                ]
            )
        ],
        collections: [
            .init(id: "services", title: "Services", fields: [
                .init(id: "serviceType", title: "Service", kind: .text, required: true),
                .init(id: "mileage", title: "Mileage", kind: .number),
                .init(id: "serviceDate", title: "Service Date", kind: .date),
                .init(id: "cost", title: "Cost", kind: .number),
                .init(id: "notes", title: "Notes", kind: .multilineText)
            ])
        ],
        actions: [
            .init(id: "open-history", title: "View History", kind: .navigate, target: "history"),
            .init(id: "add-service", title: "Add Service", kind: .createRecord, target: "services")
        ]
    )
}

struct TemplateBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        let templates = try TemplatePackageLibrary().load()
        let requestTokens = Self.tokens(request)
        let best = templates.max { lhs, rhs in
            score(lhs.manifest, tokens: requestTokens) < score(rhs.manifest, tokens: requestTokens)
        } ?? templates[0]
        return TemplatePackageLibrary().blueprint(from: best.manifest, allowedCapabilities: context.requestedCapabilities)
    }

    private func score(_ manifest: MicroAppManifest, tokens: Set<String>) -> Int {
        let searchable = [manifest.name, manifest.summary]
            + manifest.screens.map(\.title)
            + manifest.collections.map(\.title)
            + manifest.collections.flatMap { $0.fields.map(\.title) }
        return tokens.intersection(Self.tokens(searchable.joined(separator: " "))).count
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }
}

struct BlueprintConverter: Sendable {
    func convert(_ source: MicroAppBlueprint, capabilities: Set<PocketCapability>) -> MicroAppManifest {
        let blueprint = BlueprintRepairer().repair(source)
        let now = Date()
        let collections = blueprint.collections.map { collection in
            CollectionSpec(id: collection.id, title: collection.title, fields: collection.fields.map { field in
                FieldSpec(
                    id: field.id,
                    title: field.title,
                    kind: field.kind,
                    defaultValue: field.defaultValue ?? Self.defaultValue(for: field.kind, now: now, options: field.options),
                    options: field.options,
                    required: field.required
                )
            })
        }
        let actions = blueprint.actions.compactMap { action -> ActionSpec? in
            if let required = action.requiredCapability, !capabilities.contains(required) { return nil }
            return ActionSpec(
                id: action.id,
                kind: action.kind,
                title: action.title,
                target: action.target,
                value: action.value,
                requiredCapability: action.requiredCapability,
                condition: action.condition,
                reason: action.reason,
                parameters: action.parameters,
                nextActionIDs: action.nextActionIDs
            )
        }
        let allowedActionIDs = Set(actions.map(\.id))
        let screens = blueprint.screens.map { screen in
            ScreenSpec(
                id: screen.id,
                title: screen.title,
                components: screen.components.map { Self.component(from: $0, allowedActionIDs: allowedActionIDs) }
            )
        }
        return MicroAppManifest(
            id: UUID(),
            name: blueprint.name,
            summary: blueprint.summary,
            entryScreenID: screens.first?.id ?? "home",
            screens: screens,
            actions: actions,
            collections: collections,
            capabilities: capabilities,
            allowedDomains: Self.validDomains(blueprint.allowedDomains),
            createdAt: now,
            updatedAt: now
        )
    }

    private static func component(from source: GeneratedComponent, allowedActionIDs: Set<String>) -> ComponentSpec {
        ComponentSpec(
            id: source.id,
            kind: source.kind,
            title: source.title,
            text: source.text,
            binding: source.binding,
            collection: source.collection,
            actionID: source.actionID.flatMap { allowedActionIDs.contains($0) ? $0 : nil },
            children: source.children.map { component(from: $0, allowedActionIDs: allowedActionIDs) },
            options: source.options,
            minimum: source.minimum,
            maximum: source.maximum,
            visibilityExpression: source.visibilityExpression,
            disabledExpression: source.disabledExpression,
            filterExpression: source.filterExpression,
            sortField: source.sortField,
            sortAscending: source.sortAscending,
            labelField: source.labelField,
            valueField: source.valueField,
            assetID: source.assetID,
            chartStyle: source.chartStyle
        )
    }

    private static func defaultValue(for kind: FieldKind, now: Date, options: [String]) -> PocketValue {
        switch kind {
        case .number: .number(0)
        case .boolean: .bool(false)
        case .date: .date(now)
        case .choice: .string(options.first ?? "")
        case .text, .multilineText, .image: .string("")
        }
    }

    private static func validDomains(_ values: [String]) -> [String] {
        Array(Set(values.compactMap { value in
            let domain = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !domain.isEmpty,
                  !domain.contains("*"),
                  !domain.contains("/"),
                  !domain.contains(":"),
                  domain.split(separator: ".").allSatisfy({ !$0.isEmpty })
            else { return nil }
            return domain
        })).sorted()
    }
}

struct BlueprintRepairer: Sendable {
    func repair(_ source: MicroAppBlueprint) -> MicroAppBlueprint {
        var result = source
        result.name = cleanTitle(result.name, fallback: "Pocket App")
        result.summary = cleanTitle(result.summary, fallback: "A locally generated Pocket App")
        result.collections = repairCollections(result.collections)
        if result.collections.isEmpty {
            result.collections = [.init(id: "records", title: "Records", fields: [.init(id: "title", title: "Title")])]
        }

        let collectionIDs = Set(result.collections.map(\.id))
        result.screens = repairScreens(result.screens, collectionIDs: collectionIDs, fallbackCollectionID: result.collections.first?.id)
        if result.screens.isEmpty {
            result.screens = [fallbackScreen(id: "home", title: result.name, collectionID: result.collections.first?.id)]
        }

        let screenIDs = Set(result.screens.map(\.id))
        result.actions = repairActions(result.actions, collectionIDs: collectionIDs, screenIDs: screenIDs)
        if !result.collections.isEmpty && !result.actions.contains(where: { $0.kind == .createRecord }) {
            result.actions.append(.init(id: "add-record", title: "Add Record", kind: .createRecord, target: result.collections[0].id))
        }
        let actionIDs = Set(result.actions.map(\.id))
        var remainingComponents = PocketLimits.components
        result.screens = result.screens.map { screen in
            var updated = screen
            let repaired = repairComponents(
                screen.components,
                collectionIDs: collectionIDs,
                actionIDs: actionIDs,
                depth: 1,
                remaining: &remainingComponents
            )
            updated.components = repaired.isEmpty
                ? fallbackComponents(screenID: screen.id, title: screen.title, collectionID: screen.collectionID, actions: result.actions)
                : repaired
            return updated
        }
        return result
    }

    private func repairCollections(_ values: [GeneratedCollection]) -> [GeneratedCollection] {
        unique(Array(values.prefix(PocketLimits.collections)).enumerated().map { index, collection in
            let fields = unique(Array(collection.fields.prefix(24)).enumerated().map { fieldIndex, field in
                GeneratedField(
                    id: cleanID(field.id, fallback: "field-\(fieldIndex + 1)"),
                    title: cleanTitle(field.title, fallback: "Field \(fieldIndex + 1)"),
                    kind: field.kind,
                    defaultValue: field.defaultValue,
                    options: Array(field.options.prefix(40)).map { cleanTitle($0, fallback: "Option") },
                    required: field.required
                )
            }, key: \.id)
            return GeneratedCollection(
                id: cleanID(collection.id, fallback: "collection-\(index + 1)"),
                title: cleanTitle(collection.title, fallback: "Records"),
                fields: fields.isEmpty ? [.init(id: "title", title: "Title")] : fields
            )
        }, key: \.id)
    }

    private func repairScreens(
        _ values: [GeneratedScreen],
        collectionIDs: Set<String>,
        fallbackCollectionID: String?
    ) -> [GeneratedScreen] {
        unique(Array(values.prefix(PocketLimits.screens)).enumerated().map { index, screen in
            let collectionID = screen.collectionID.flatMap { collectionIDs.contains($0) ? $0 : nil }
            return GeneratedScreen(
                id: cleanID(screen.id, fallback: "screen-\(index + 1)"),
                title: cleanTitle(screen.title, fallback: "Screen \(index + 1)"),
                collectionID: collectionID ?? inferredCollection(in: screen.components, validIDs: collectionIDs) ?? fallbackCollectionID,
                components: screen.components
            )
        }, key: \.id)
    }

    private func repairActions(
        _ values: [GeneratedAction],
        collectionIDs: Set<String>,
        screenIDs: Set<String>
    ) -> [GeneratedAction] {
        unique(Array(values.prefix(PocketLimits.actions)).enumerated().map { index, action in
            let target: String?
            switch action.kind {
            case .createRecord, .updateRecord, .deleteRecord, .sortRecords, .filterRecords:
                target = action.target.flatMap { collectionIDs.contains($0) ? $0 : nil } ?? collectionIDs.sorted().first
            case .navigate:
                target = action.target.flatMap { screenIDs.contains($0) ? $0 : nil } ?? screenIDs.sorted().first
            default:
                target = action.target
            }
            return GeneratedAction(
                id: cleanID(action.id, fallback: "action-\(index + 1)"),
                title: cleanTitle(action.title, fallback: action.kind.rawValue),
                kind: action.kind,
                target: target,
                value: action.value,
                requiredCapability: action.requiredCapability,
                condition: boundedExpression(action.condition),
                reason: action.reason.map { cleanTitle($0, fallback: "Complete the requested action") },
                parameters: action.parameters,
                nextActionIDs: Array(action.nextActionIDs.prefix(12)).map { cleanID($0, fallback: "") }.filter { !$0.isEmpty }
            )
        }, key: \.id)
    }

    private func repairComponents(
        _ values: [GeneratedComponent],
        collectionIDs: Set<String>,
        actionIDs: Set<String>,
        depth: Int,
        remaining: inout Int
    ) -> [GeneratedComponent] {
        guard depth <= PocketLimits.nestingDepth, remaining > 0 else { return [] }
        var output: [GeneratedComponent] = []
        var seen = Set<String>()
        for (index, component) in values.enumerated() where remaining > 0 {
            var repaired = component
            repaired.id = cleanID(component.id, fallback: "component-\(index + 1)")
            guard seen.insert(repaired.id).inserted else { continue }
            repaired.title = component.title.map { cleanTitle($0, fallback: component.kind.rawValue) }
            repaired.text = component.text.map { String($0.prefix(2_000)) }
            repaired.binding = component.binding.map { String($0.prefix(200)) }
            repaired.collection = component.collection.flatMap { collectionIDs.contains($0) ? $0 : nil }
            repaired.actionID = component.actionID.flatMap { actionIDs.contains($0) ? $0 : nil }
            repaired.options = Array(component.options.prefix(40)).map { cleanTitle($0, fallback: "Option") }
            repaired.visibilityExpression = boundedExpression(component.visibilityExpression)
            repaired.disabledExpression = boundedExpression(component.disabledExpression)
            repaired.filterExpression = boundedExpression(component.filterExpression)
            remaining -= 1
            repaired.children = repairComponents(
                component.children,
                collectionIDs: collectionIDs,
                actionIDs: actionIDs,
                depth: depth + 1,
                remaining: &remaining
            )
            output.append(repaired)
        }
        return output
    }

    private func fallbackScreen(id: String, title: String, collectionID: String?) -> GeneratedScreen {
        GeneratedScreen(
            id: id,
            title: title,
            collectionID: collectionID,
            components: fallbackComponents(screenID: id, title: title, collectionID: collectionID, actions: [])
        )
    }

    private func fallbackComponents(
        screenID: String,
        title: String,
        collectionID: String?,
        actions: [GeneratedAction]
    ) -> [GeneratedComponent] {
        var components: [GeneratedComponent] = [.init(id: "\(screenID)-heading", kind: .heading, text: title)]
        if let collectionID {
            components.append(.init(id: "\(screenID)-list", kind: .list, collection: collectionID))
            if let action = actions.first(where: { $0.kind == .createRecord && $0.target == collectionID }) {
                components.append(.init(id: "\(screenID)-create", kind: .button, title: action.title, actionID: action.id))
            }
        } else {
            components.append(.init(id: "\(screenID)-empty", kind: .emptyState, title: "Nothing to show yet"))
        }
        return components
    }

    private func inferredCollection(in components: [GeneratedComponent], validIDs: Set<String>) -> String? {
        for component in components {
            if let collection = component.collection, validIDs.contains(collection) { return collection }
            if let nested = inferredCollection(in: component.children, validIDs: validIDs) { return nested }
        }
        return nil
    }

    private func boundedExpression(_ value: String?) -> String? {
        value.map { String($0.prefix(PocketLimits.expressionCharacters)) }
    }

    private func cleanID(_ value: String, fallback: String) -> String {
        let cleaned = value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let result = String(cleaned).split(separator: "-").joined(separator: "-")
        return result.isEmpty ? fallback : String(result.prefix(80))
    }

    private func cleanTitle(_ value: String, fallback: String) -> String {
        let result = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return result.isEmpty ? fallback : result
    }

    private func unique<T>(_ values: [T], key: KeyPath<T, String>) -> [T] {
        var seen = Set<String>()
        return values.filter { seen.insert($0[keyPath: key]).inserted }
    }
}
