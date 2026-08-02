import XCTest
@testable import PocketKernel

private func bundledPackage(named name: String) throws -> PocketPackage {
    try XCTUnwrap(TemplatePackageLibrary().load().first { $0.manifest.name == name }).package
}

private func validationErrorCodes(_ manifest: MicroAppManifest) -> Set<String> {
    Set(ManifestValidator().validate(manifest).filter { $0.severity == .error }.map(\.code))
}

final class DomainAndValidationTests: XCTestCase {
    func testPocketValueRoundTripsEveryRecursiveCase() throws {
        let value = PocketValue.object([
            "null": .null,
            "done": .bool(false),
            "cost": .number(42.5),
            "title": .string("Service"),
            "date": .date(Date(timeIntervalSinceReferenceDate: 100)),
            "tags": .array([.string("car"), .number(2)]),
            "nested": .object(["enabled": .bool(true)])
        ])
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(value, try JSONDecoder().decode(PocketValue.self, from: encoded))
    }

    func testManifestRoundTripAndUnknownEnums() throws {
        let manifest = try bundledPackage(named: "Service Log").manifest
        let encoded = try JSONEncoder().encode(manifest)
        XCTAssertEqual(manifest, try JSONDecoder().decode(MicroAppManifest.self, from: encoded))
        XCTAssertThrowsError(try JSONDecoder().decode(ActionKind.self, from: Data("\"futureAction\"".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ComponentKind.self, from: Data("\"futureComponent\"".utf8)))
    }

    func testEveryBundledPackageIsCompleteValidAndHashVerified() throws {
        let templates = try TemplatePackageLibrary().load()
        XCTAssertEqual(templates.count, 5)
        XCTAssertEqual(
            Set(templates.map { $0.manifest.name }),
            Set(["Task Board", "Habit Tracker", "Quick Journal", "Inventory List", "Service Log"])
        )
        for template in templates {
            XCTAssertGreaterThanOrEqual(template.manifest.screens.count, 2, template.manifest.name)
            XCTAssertFalse(template.manifest.collections.isEmpty, template.manifest.name)
            XCTAssertFalse(template.manifest.actions.isEmpty, template.manifest.name)
            XCTAssertTrue(validationErrorCodes(template.manifest).isEmpty, template.manifest.name)
            XCTAssertEqual(
                try PackageCodec().decode(PackageCodec().encode(template.package)),
                template.package
            )
        }
    }

    func testBlueprintConversionRepairMockAndDataDrivenFallback() async throws {
        let context = BuilderContext(localeIdentifier: "en_US", requestedCapabilities: [])
        let first = try await MockBlueprintGenerator().generateBlueprint(from: "anything", context: context)
        let second = try await MockBlueprintGenerator().generateBlueprint(from: "different", context: context)
        XCTAssertEqual(first, second)

        let manifest = BlueprintConverter().convert(first, capabilities: [])
        XCTAssertEqual(manifest.screens.count, 2)
        XCTAssertTrue(manifest.collections.flatMap(\.fields).contains { $0.kind == .number })
        func containsChart(_ components: [ComponentSpec]) -> Bool {
            components.contains { component in
                component.kind == .chart || containsChart(component.children)
            }
        }
        XCTAssertTrue(manifest.screens.contains { containsChart($0.components) })
        XCTAssertTrue(validationErrorCodes(manifest).isEmpty)

        let repaired = BlueprintRepairer().repair(.init(
            name: "  ",
            summary: "",
            screens: [.init(id: "../bad", title: "", collectionID: "missing")],
            collections: [.init(id: "My Records", title: "", fields: [.init(id: "Bad/Field", title: "")])],
            actions: []
        ))
        XCTAssertEqual(repaired.name, "Pocket App")
        XCTAssertFalse(repaired.screens[0].id.contains("/"))
        XCTAssertEqual(repaired.screens[0].collectionID, repaired.collections[0].id)
        XCTAssertTrue(repaired.actions.contains { $0.kind == .createRecord })

        let fallback = try await TemplateBlueprintGenerator().generateBlueprint(
            from: "inventory quantities and storage locations",
            context: context
        )
        XCTAssertEqual(fallback.name, "Inventory List")
    }

    func testValidatorRejectsInvalidVersionReferencesTypesCapabilitiesDomainsAndLimits() throws {
        var manifest = try bundledPackage(named: "Inventory List").manifest
        manifest.formatVersion = 2
        XCTAssertEqual(validationErrorCodes(manifest), Set(["format.unsupported"]))

        manifest = try bundledPackage(named: "Inventory List").manifest
        manifest.screens.append(manifest.screens[0])
        manifest.screens[0].components[0].actionID = "missing-action"
        manifest.collections[0].fields[0].defaultValue = .number(1)
        manifest.actions.append(.init(
            id: "network-test",
            kind: .httpGet,
            target: "http://api.example.test/data",
            requiredCapability: .network
        ))
        manifest.allowedDomains = ["*.example.test"]
        let codes = validationErrorCodes(manifest)
        for expected in ["identifier.duplicate", "action.missing", "field.defaultType", "capability.undeclared", "network.https", "domain.invalid"] {
            XCTAssertTrue(codes.contains(expected), expected)
        }

        manifest = try bundledPackage(named: "Task Board").manifest
        manifest.screens = (0...PocketLimits.screens).map {
            .init(id: "screen-\($0)", title: "Screen \($0)", components: [])
        }
        manifest.entryScreenID = manifest.screens[0].id
        XCTAssertTrue(validationErrorCodes(manifest).contains("limit.screens"))

        manifest = try bundledPackage(named: "Task Board").manifest
        var nested = ComponentSpec(id: "depth-0", kind: .group)
        for index in 1...(PocketLimits.nestingDepth + 1) {
            nested = .init(id: "depth-\(index)", kind: .group, children: [nested])
        }
        manifest.screens[0].components = [nested]
        XCTAssertTrue(validationErrorCodes(manifest).contains("limit.depth"))
    }
}

final class ExpressionTests: XCTestCase {
    private let evaluator = ExpressionEvaluator()

    func testBindingsArithmeticBooleanStringsAggregatesAndFormatting() throws {
        let context: [String: PocketValue] = [
            "record": .object(["cost": .number(40), "complete": .bool(false), "title": .string("Service Log"), "code": .string("A19")]),
            "environment": .object(["limit": .number(20)]),
            "values": .array([.number(2), .number(4), .number(6)]),
            "empty": .null
        ]
        XCTAssertEqual(try evaluator.evaluate("(record.cost + 2) >= environment.limit and not record.complete", context: context), .bool(true))
        XCTAssertEqual(try evaluator.evaluate("contains(record.title, \"Service\") and startsWith(record.code, \"A\")", context: context), .bool(true))
        XCTAssertEqual(try evaluator.evaluate("sum(values) / count(values)", context: context), .number(4))
        XCTAssertEqual(try evaluator.evaluate("min(values)", context: context), .number(2))
        XCTAssertEqual(try evaluator.evaluate("max(values)", context: context), .number(6))
        XCTAssertEqual(try evaluator.evaluate("coalesce(empty, \"fallback\")", context: context), .string("fallback"))
        XCTAssertEqual(try evaluator.evaluate("formatNumber(42)", context: context), .string(42.0.formatted()))
    }

    func testMalformedLengthDepthAndDivisionErrorsAreTyped() {
        XCTAssertThrowsError(try evaluator.evaluate("(true and", context: [:])) { XCTAssertTrue($0 is ExpressionError) }
        XCTAssertThrowsError(try evaluator.evaluate(String(repeating: "1", count: PocketLimits.expressionCharacters + 1), context: [:])) {
            XCTAssertEqual($0 as? ExpressionError, .tooLong)
        }
        XCTAssertThrowsError(try evaluator.evaluate("1 / 0", context: [:])) {
            XCTAssertEqual($0 as? ExpressionError, .divisionByZero)
        }
        let nested = String(repeating: "(", count: PocketLimits.expressionDepth + 2) + "1" + String(repeating: ")", count: PocketLimits.expressionDepth + 2)
        XCTAssertThrowsError(try evaluator.evaluate(nested, context: [:])) {
            XCTAssertEqual($0 as? ExpressionError, .tooDeep)
        }
    }
}

final class PackageTests: XCTestCase {
    func testPackageRoundTripTamperingAssetsTraversalAndSizeLimits() throws {
        let codec = PackageCodec()
        for template in try TemplatePackageLibrary().load() {
            XCTAssertEqual(try codec.decode(codec.encode(template.package)), template.package)
        }

        var package = try bundledPackage(named: "Inventory List")
        package.manifest.name = "Tampered"
        XCTAssertThrowsError(try codec.decode(codec.encode(package))) {
            XCTAssertEqual($0 as? PackageError, .invalidHash)
        }

        package = try bundledPackage(named: "Inventory List")
        package.assets = [.init(id: "bad", mediaType: "image/png", sha256: "00", base64Data: "%%%")]
        XCTAssertThrowsError(try codec.decode(codec.encode(package))) {
            XCTAssertEqual($0 as? PackageError, .invalidAsset("bad"))
        }

        package = try bundledPackage(named: "Inventory List")
        let asset = PackageAsset(id: "same", mediaType: "text/plain", sha256: "00", base64Data: Data("a".utf8).base64EncodedString())
        package.assets = [asset, asset]
        XCTAssertThrowsError(try codec.decode(codec.encode(package)))

        package = try bundledPackage(named: "Inventory List")
        package.assets = [.init(id: "../escape", mediaType: "text/plain", sha256: "00", base64Data: "")]
        XCTAssertThrowsError(try codec.decode(codec.encode(package)))

        XCTAssertThrowsError(try codec.decode(Data(repeating: 0, count: PocketLimits.packageBytes + 1))) {
            XCTAssertEqual($0 as? PackageError, .oversized)
        }
        XCTAssertThrowsError(try codec.decode(Data("not-json".utf8))) {
            XCTAssertEqual($0 as? PackageError, .malformed)
        }
    }
}

final class PersistenceTests: XCTestCase {
    func testDatabaseCRUDMetadataExportRollbackAndDeletionCleanup() async throws {
        let store = try PocketStore(inMemory: true)
        var package = try bundledPackage(named: "Service Log")
        let appID = package.manifest.id
        try await store.install(package)

        var installed = try await store.installedApps()
        XCTAssertEqual(installed.count, 1)
        try await store.setFavorite(true, id: appID)
        try await store.setDisabled(true, id: appID)
        installed = try await store.installedApps()
        XCTAssertTrue(installed[0].favorite)
        XCTAssertTrue(installed[0].disabled)

        let now = Date()
        var record = PocketRecord(
            id: UUID(),
            collectionID: "services",
            values: ["serviceType": .string("Oil Change"), "cost": .number(20)],
            createdAt: now,
            updatedAt: now
        )
        try await store.save(record: record, appID: appID)
        var records = try await store.records(appID: appID, collectionID: "services")
        XCTAssertEqual(records, [record])

        record.values["cost"] = .number(30)
        record.updatedAt = Date()
        try await store.save(record: record, appID: appID)
        records = try await store.records(appID: appID, collectionID: "services")
        XCTAssertEqual(records.first?.values["cost"], .number(30))

        try await store.setRuntimeValue(.string("oil"), appID: appID, key: "search")
        let runtimeValue = try await store.runtimeValue(appID: appID, key: "search")
        XCTAssertEqual(runtimeValue, .string("oil"))
        try await store.setPermission(.alwaysAllow, appID: appID, capability: .localNotifications)
        let permission = try await store.permission(appID: appID, capability: .localNotifications)
        XCTAssertEqual(permission, .alwaysAllow)

        let exported = try await store.exportPackage(appID: appID)
        XCTAssertEqual(try PackageCodec().decode(exported).manifest.id, appID)

        package.manifest.name = "Updated Service Log"
        package.manifest.updatedAt = Date()
        package.integrity = try PackageCodec().integrity(for: package.manifest)
        try await store.install(package)
        try await store.rollbackManifest(id: appID)
        installed = try await store.installedApps()
        XCTAssertEqual(installed[0].manifest.name, "Service Log")

        try await store.deleteRecord(appID: appID, collectionID: "services", recordID: record.id)
        records = try await store.records(appID: appID, collectionID: "services")
        XCTAssertTrue(records.isEmpty)

        try await store.delete(appID)
        let appsAfterDelete = try await store.installedApps()
        let recordsAfterDelete = try await store.records(appID: appID, collectionID: "services")
        let valuesAfterDelete = try await store.runtimeValues(appID: appID)
        let permissionAfterDelete = try await store.permission(appID: appID, capability: .localNotifications)
        XCTAssertTrue(appsAfterDelete.isEmpty)
        XCTAssertTrue(recordsAfterDelete.isEmpty)
        XCTAssertTrue(valuesAfterDelete.isEmpty)
        XCTAssertEqual(permissionAfterDelete, .notRequested)
    }

    func testMigrationCorruptRowsRollbackRecordLimitDuplicateAndConcurrency() async throws {
        let store = try PocketStore(inMemory: true, recordLimit: 3)
        let package = try bundledPackage(named: "Inventory List")
        try await store.install(package)

        let version = try await store.databaseUserVersionForTesting()
        XCTAssertEqual(version, 1)
        try await store.insertCorruptRecordForTesting(appID: package.manifest.id, collectionID: "items")
        let corruptRows = try await store.records(appID: package.manifest.id, collectionID: "items")
        XCTAssertTrue(corruptRows.isEmpty)

        await assertThrowsAsync {
            try await store.insertRuntimeValueThenRollbackForTesting(appID: package.manifest.id, key: "rollback-probe")
        } verify: { XCTAssertEqual($0 as? StoreError, .invalidData) }
        let rolledBackValue = try await store.runtimeValue(appID: package.manifest.id, key: "rollback-probe")
        XCTAssertNil(rolledBackValue)

        let duplicateID = try await store.duplicate(id: package.manifest.id)
        let installed = try await store.installedApps()
        XCTAssertTrue(installed.contains { $0.id == duplicateID && $0.manifest.name.hasSuffix("Copy") })

        let now = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<3 {
                group.addTask {
                    try await store.save(
                        record: .init(
                            id: UUID(),
                            collectionID: "items",
                            values: ["name": .string("Item \(index)"), "quantity": .number(Double(index))],
                            createdAt: now,
                            updatedAt: now
                        ),
                        appID: package.manifest.id
                    )
                }
            }
            try await group.waitForAll()
        }
        await assertThrowsAsync {
            try await store.save(
                record: .init(id: UUID(), collectionID: "items", values: ["name": .string("overflow")], createdAt: now, updatedAt: now),
                appID: package.manifest.id
            )
        } verify: { XCTAssertEqual($0 as? StoreError, .limit) }
        let finalRecords = try await store.records(appID: package.manifest.id, collectionID: "items")
        XCTAssertEqual(finalRecords.count, 3)
    }
}

final class RuntimeTests: XCTestCase {
    func testPermissionPromptAndDenyByDefault() async throws {
        let store = try PocketStore(inMemory: true)
        var manifest = try bundledPackage(named: "Inventory List").manifest
        manifest.capabilities.insert(.clipboardWrite)
        manifest.actions.append(.init(
            id: "copy-value",
            kind: .copyToClipboard,
            value: .string("value"),
            requiredCapability: .clipboardWrite,
            reason: "Copy the generated value."
        ))

        let asking = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        await assertThrowsAsync {
            try await asking.execute("copy-value", manifest: manifest, context: [:])
        } verify: { error in
            guard case RuntimeExecutionError.permissionRequired(let request) = error else {
                return XCTFail("Expected permission request")
            }
            XCTAssertEqual(request.capability, .clipboardWrite)
            XCTAssertEqual(request.reason, "Copy the generated value.")
        }

        let denying = ActionExecutor(store: store, intelligence: MockIntelligenceService(), defaultPermission: .denied)
        await assertThrowsAsync {
            try await denying.execute("copy-value", manifest: manifest, context: [:])
        } verify: { error in
            guard case RuntimeExecutionError.permissionDenied(.clipboardWrite) = error else {
                return XCTFail("Expected denied permission")
            }
        }
        let decision = try await store.permission(appID: manifest.id, capability: .clipboardWrite)
        XCTAssertEqual(decision, .denied)
    }

    func testRecordSortFilterSelectDeleteAndIntelligenceActions() async throws {
        let store = try PocketStore(inMemory: true)
        var package = try bundledPackage(named: "Inventory List")
        package.manifest.capabilities.insert(.onDeviceModel)
        package.manifest.actions += [
            .init(id: "sort-items", kind: .sortRecords, target: "items", parameters: ["field": .string("quantity")]),
            .init(id: "filter-items", kind: .filterRecords, target: "items", parameters: ["expression": .string("record.quantity > 1")]),
            .init(id: "select-item", kind: .selectRecord, parameters: ["recordID": .string("00000000-0000-0000-0000-000000000010")]),
            .init(id: "summary", kind: .summarizeText, value: .string("Long local text"), requiredCapability: .onDeviceModel)
        ]
        package.integrity = try PackageCodec().integrity(for: package.manifest)
        try await store.install(package)
        try await store.setPermission(.alwaysAllow, appID: package.manifest.id, capability: .onDeviceModel)
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        let create = try XCTUnwrap(package.manifest.actions.first { $0.kind == .createRecord })

        guard case .record(let first) = try await executor.execute(
            create.id,
            manifest: package.manifest,
            context: ["form": .object(["name": .string("Two"), "quantity": .number(2)])]
        ) else { return XCTFail("Expected created record") }
        _ = try await executor.execute(
            create.id,
            manifest: package.manifest,
            context: ["form": .object(["name": .string("One"), "quantity": .number(1)])]
        )

        package.manifest.actions += [
            .init(id: "update-item", kind: .updateRecord, target: "items", parameters: ["recordID": .string(first.id.uuidString), "quantity": .number(3)]),
            .init(id: "delete-item", kind: .deleteRecord, target: "items", parameters: ["recordID": .string(first.id.uuidString)])
        ]

        guard case .record(let updated) = try await executor.execute("update-item", manifest: package.manifest, context: [:]) else {
            return XCTFail("Expected updated record")
        }
        XCTAssertEqual(updated.values["quantity"], .number(3))

        guard case .records(let sorted) = try await executor.execute("sort-items", manifest: package.manifest, context: [:]) else {
            return XCTFail("Expected sorted records")
        }
        XCTAssertEqual(sorted.first?.values["quantity"], .number(1))

        guard case .records(let filtered) = try await executor.execute("filter-items", manifest: package.manifest, context: [:]) else {
            return XCTFail("Expected filtered records")
        }
        XCTAssertEqual(filtered.count, 1)

        guard case .selectedRecord(let selected) = try await executor.execute("select-item", manifest: package.manifest, context: [:]) else {
            return XCTFail("Expected selected record")
        }
        XCTAssertEqual(selected.uuidString, "00000000-0000-0000-0000-000000000010")

        guard case .value(.string(let summary)) = try await executor.execute("summary", manifest: package.manifest, context: [:]) else {
            return XCTFail("Expected AI result")
        }
        XCTAssertFalse(summary.isEmpty)

        _ = try await executor.execute("delete-item", manifest: package.manifest, context: [:])
        let remaining = try await store.records(appID: package.manifest.id, collectionID: "items")
        XCTAssertEqual(remaining.count, 1)
    }

    func testSessionUndoRestoresStateAndRecords() async throws {
        let store = try PocketStore(inMemory: true)
        var package = try bundledPackage(named: "Inventory List")
        try await store.install(package)
        package.manifest.actions += [
            .init(id: "set-filter", kind: .setValue, target: "state.filter", value: .string("active")),
            .init(id: "delete-item-for-undo", kind: .deleteRecord, target: "items")
        ]
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())

        _ = try await executor.execute("set-filter", manifest: package.manifest, context: [:])
        let activeFilter = try await store.runtimeValue(appID: package.manifest.id, key: "filter")
        XCTAssertEqual(activeFilter, .string("active"))
        let canUndoState = await executor.canUndo()
        XCTAssertTrue(canUndoState)

        _ = try await executor.undoLast()
        let clearedFilter = try await store.runtimeValue(appID: package.manifest.id, key: "filter")
        XCTAssertNil(clearedFilter)

        let create = try XCTUnwrap(package.manifest.actions.first { $0.kind == .createRecord })
        guard case .record(let record) = try await executor.execute(
            create.id,
            manifest: package.manifest,
            context: ["form": .object(["name": .string("Undo Item"), "quantity": .number(1)])]
        ) else { return XCTFail("Expected created record") }

        _ = try await executor.execute(
            "delete-item-for-undo",
            manifest: package.manifest,
            context: ["selectedRecordID": .string(record.id.uuidString)]
        )
        let deletedRecords = try await store.records(appID: package.manifest.id, collectionID: "items")
        XCTAssertTrue(deletedRecords.isEmpty)

        _ = try await executor.undoLast()
        let restoredRecords = try await store.records(appID: package.manifest.id, collectionID: "items")
        XCTAssertEqual(restoredRecords, [record])
    }

    func testPhotoConditionsCyclesCancellationAndNetworkBoundaries() async throws {
        let store = try PocketStore(inMemory: true)
        var manifest = try bundledPackage(named: "Quick Journal").manifest
        manifest.capabilities.insert(.photoSelection)
        manifest.actions.append(.init(
            id: "choose-receipt",
            kind: .selectPhotos,
            target: "receiptImage",
            requiredCapability: .photoSelection,
            reason: "Choose a receipt image.",
            parameters: ["recognizeText": .bool(true)]
        ))
        try await store.setPermission(.alwaysAllow, appID: manifest.id, capability: .photoSelection)
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        let photoResult = try await executor.execute("choose-receipt", manifest: manifest, context: [:])
        XCTAssertEqual(photoResult, .host(.selectPhotos(target: "receiptImage", recognizeText: true)))

        manifest.actions = [.init(id: "conditional", kind: .showAlert, title: "Hidden", condition: "false")]
        await assertThrowsAsync { try await executor.execute("conditional", manifest: manifest, context: [:]) } verify: {
            guard case RuntimeExecutionError.conditionFalse = $0 else { return XCTFail("Expected false condition") }
        }

        manifest.actions = [.init(id: "loop", kind: .showAlert, title: "Loop", nextActionIDs: ["loop"])]
        await assertThrowsAsync { try await executor.execute("loop", manifest: manifest, context: [:]) } verify: {
            guard case RuntimeExecutionError.chainLimit = $0 else { return XCTFail("Expected chain limit") }
        }

        let cancelled = Task { try await executor.execute("loop", manifest: manifest, context: [:]) }
        cancelled.cancel()
        await assertThrowsAsync { try await cancelled.value } verify: {
            guard case RuntimeExecutionError.cancelled = $0 else { return XCTFail("Expected cancellation") }
        }

        await assertThrowsAsync {
            try await NetworkService().request(urlString: "http://api.example.test", method: "GET", body: nil, allowedDomains: ["api.example.test"])
        } verify: {
            guard case HostServiceError.insecureURL = $0 else { return XCTFail("Expected HTTPS enforcement") }
        }
        await assertThrowsAsync {
            try await NetworkService().request(urlString: "https://other.example.test", method: "GET", body: nil, allowedDomains: ["api.example.test"])
        } verify: {
            guard case HostServiceError.domainDenied = $0 else { return XCTFail("Expected exact-domain enforcement") }
        }
    }
}

private extension XCTestCase {
    func assertThrowsAsync<T>(
        _ operation: () async throws -> T,
        verify: (Error) -> Void = { _ in },
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            verify(error)
        }
    }
}
