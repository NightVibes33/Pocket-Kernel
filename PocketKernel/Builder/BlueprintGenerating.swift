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
        return MicroAppBlueprint(
            name: manifest.name,
            summary: manifest.summary,
            screens: manifest.screens.map { screen in
                GeneratedScreen(id: screen.id, title: screen.title, collectionID: firstCollection(in: screen.components))
            },
            collections: manifest.collections.map { collection in
                GeneratedCollection(
                    id: collection.id,
                    title: collection.title,
                    fields: collection.fields.map { GeneratedField(id: $0.id, title: $0.title, kind: $0.kind) }
                )
            },
            actions: allowedActions.map { action in
                GeneratedAction(id: action.id, title: action.title ?? action.kind.rawValue, kind: action.kind, target: action.target)
            }
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
            .init(id: "overview", title: "Service Overview", collectionID: "services"),
            .init(id: "history", title: "Service History", collectionID: "services")
        ],
        collections: [
            .init(id: "services", title: "Services", fields: [
                .init(id: "serviceType", title: "Service", kind: .text),
                .init(id: "mileage", title: "Mileage", kind: .number),
                .init(id: "serviceDate", title: "Service Date", kind: .date),
                .init(id: "cost", title: "Cost", kind: .number),
                .init(id: "notes", title: "Notes", kind: .multilineText)
            ])
        ],
        actions: [.init(id: "add-service", title: "Add Service", kind: .createRecord, target: "services")]
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
                if let numericField = collections.first(where: { $0.id == collection })?.fields.first(where: { $0.kind == .number }) {
                    components.append(.init(id: "\(screen.id)-chart", kind: .chart, title: "Overview", collection: collection, valueField: numericField.id, chartStyle: .bar))
                }
            } else {
                components.append(.init(id: "\(screen.id)-empty", kind: .emptyState, title: "No collection configured"))
            }
            return ScreenSpec(id: screen.id, title: screen.title, components: components)
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
            createdAt: now,
            updatedAt: now
        )
    }
}

struct BlueprintRepairer: Sendable {
    func repair(_ source: MicroAppBlueprint) -> MicroAppBlueprint {
        var result = source
        result.name = cleanTitle(result.name, fallback: "Pocket App")
        result.summary = cleanTitle(result.summary, fallback: "A locally generated Pocket App")
        result.collections = uniqueCollections(Array(result.collections.prefix(8)).enumerated().map { index, collection in
            let fields = uniqueFields(Array(collection.fields.prefix(12)).enumerated().map { fieldIndex, field in
                GeneratedField(
                    id: cleanID(field.id, fallback: "field-\(fieldIndex + 1)"),
                    title: cleanTitle(field.title, fallback: "Field \(fieldIndex + 1)"),
                    kind: field.kind
                )
            })
            return GeneratedCollection(
                id: cleanID(collection.id, fallback: "collection-\(index + 1)"),
                title: cleanTitle(collection.title, fallback: "Records"),
                fields: fields.isEmpty ? [.init(id: "title", title: "Title")] : fields
            )
        })
        if result.collections.isEmpty {
            result.collections = [.init(id: "records", title: "Records", fields: [.init(id: "title", title: "Title")])]
        }
        let collectionIDs = Set(result.collections.map(\.id))
        result.screens = uniqueScreens(Array(result.screens.prefix(8)).enumerated().map { index, screen in
            GeneratedScreen(
                id: cleanID(screen.id, fallback: "screen-\(index + 1)"),
                title: cleanTitle(screen.title, fallback: "Screen \(index + 1)"),
                collectionID: screen.collectionID.flatMap { collectionIDs.contains($0) ? $0 : nil } ?? result.collections.first?.id
            )
        })
        if result.screens.isEmpty {
            result.screens = [.init(id: "home", title: result.name, collectionID: result.collections.first?.id)]
        }
        result.actions = uniqueActions(Array(result.actions.prefix(12)).enumerated().map { index, action in
            let target = action.target.flatMap { collectionIDs.contains($0) ? $0 : nil }
            return GeneratedAction(
                id: cleanID(action.id, fallback: "action-\(index + 1)"),
                title: cleanTitle(action.title, fallback: "Action"),
                kind: action.kind,
                target: target ?? (action.kind == .createRecord ? result.collections.first?.id : action.target)
            )
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
