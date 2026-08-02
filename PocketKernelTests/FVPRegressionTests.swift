import XCTest
@testable import PocketKernel

extension Array where Element == ScreenSpec {
    func flatMap(_ keyPath: KeyPath<ScreenSpec, [ComponentSpec]>) -> [ComponentSpec] {
        func flatten(_ components: [ComponentSpec]) -> [ComponentSpec] {
            components + components.flatMap { flatten($0.children) }
        }

        return reduce(into: []) { result, screen in
            result += flatten(screen[keyPath: keyPath])
        }
    }
}

final class FVPRegressionTests: XCTestCase {
    func testGeneratedBlueprintPreservesCustomLayoutAndActionMetadata() {
        let blueprint = MicroAppBlueprint(
            name: "Flexible App",
            summary: "A custom generated layout.",
            screens: [
                .init(
                    id: "dashboard",
                    title: "Dashboard",
                    components: [
                        .init(
                            id: "custom-card",
                            kind: .card,
                            children: [
                                .init(
                                    id: "custom-metric",
                                    kind: .metric,
                                    title: "Total",
                                    text: "{{ count(collections.entries) }}"
                                )
                            ]
                        ),
                        .init(id: "custom-button", kind: .button, title: "Next", actionID: "go-next")
                    ]
                ),
                .init(
                    id: "details",
                    title: "Details",
                    components: [
                        .init(
                            id: "entry-grid",
                            kind: .grid,
                            collection: "entries",
                            sortField: "amount",
                            sortAscending: false
                        )
                    ]
                )
            ],
            collections: [
                .init(
                    id: "entries",
                    title: "Entries",
                    fields: [
                        .init(id: "amount", title: "Amount", kind: .number, required: true)
                    ]
                )
            ],
            actions: [
                .init(
                    id: "go-next",
                    title: "Next",
                    kind: .navigate,
                    target: "details",
                    condition: "count(collections.entries) >= 0",
                    parameters: ["source": .string("dashboard")]
                )
            ]
        )

        let manifest = BlueprintConverter().convert(blueprint, capabilities: [])

        XCTAssertEqual(manifest.screens[0].components[0].kind, .card)
        XCTAssertEqual(manifest.screens[0].components[0].children.first?.id, "custom-metric")
        XCTAssertEqual(manifest.screens[1].components.first?.kind, .grid)
        XCTAssertEqual(manifest.screens[1].components.first?.sortField, "amount")
        XCTAssertEqual(manifest.actions.first?.condition, "count(collections.entries) >= 0")
        XCTAssertEqual(manifest.actions.first?.parameters["source"], .string("dashboard"))
    }

    @MainActor
    func testSessionUndoRestoresStateAndRecords() async throws {
        let store = try PocketStore(inMemory: true)
        let template = try XCTUnwrap(
            TemplatePackageLibrary().load().first { $0.manifest.name == "Inventory List" }
        )
        try await store.install(template.package)

        var manifest = template.manifest
        manifest.actions.append(
            .init(id: "set-filter", kind: .setValue, target: "state.filter", value: .string("active"))
        )
        manifest.actions.append(
            .init(id: "delete-item", kind: .deleteRecord, target: "items")
        )
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())

        _ = try await executor.execute("set-filter", manifest: manifest, context: [:])
        let activeFilter = try await store.runtimeValue(appID: manifest.id, key: "filter")
        XCTAssertEqual(activeFilter, .string("active"))

        _ = try await executor.undoLast()
        let clearedFilter = try await store.runtimeValue(appID: manifest.id, key: "filter")
        XCTAssertNil(clearedFilter)

        let createAction = try XCTUnwrap(manifest.actions.first { $0.kind == .createRecord })
        guard case .record(let record) = try await executor.execute(
            createAction.id,
            manifest: manifest,
            context: [
                "form": .object([
                    "name": .string("Undo Item"),
                    "quantity": .number(1)
                ])
            ]
        ) else {
            return XCTFail("Expected a created record.")
        }

        _ = try await executor.execute(
            "delete-item",
            manifest: manifest,
            context: ["selectedRecordID": .string(record.id.uuidString)]
        )
        let deletedRecords = try await store.records(appID: manifest.id, collectionID: "items")
        XCTAssertTrue(deletedRecords.isEmpty)

        _ = try await executor.undoLast()
        let restoredRecords = try await store.records(appID: manifest.id, collectionID: "items")
        XCTAssertEqual(restoredRecords, [record])

        _ = try await executor.undoLast()
        let removedCreatedRecord = try await store.records(appID: manifest.id, collectionID: "items")
        XCTAssertTrue(removedCreatedRecord.isEmpty)
        let canUndo = await executor.canUndo()
        XCTAssertFalse(canUndo)
    }
}
