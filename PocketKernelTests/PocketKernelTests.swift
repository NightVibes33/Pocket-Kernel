import XCTest
@testable import PocketKernel

private func bundledPackage(named name: String) throws -> PocketPackage {
    let template = try XCTUnwrap(TemplatePackageLibrary().load().first { $0.manifest.name == name })
    return template.package
}

private func errorCodes(_ manifest: MicroAppManifest) -> Set<String> {
    Set(ManifestValidator().validate(manifest).filter { $0.severity == .error }.map(\.code))
}

final class DomainAndValidationTests: XCTestCase {
    func testPocketValueRoundTripForEveryRecursiveCase() throws {
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

    func testManifestAndUnknownEnums() throws {
        let manifest = try bundledPackage(named: "Service Log").manifest
        let encoded = try JSONEncoder().encode(manifest)
        XCTAssertEqual(manifest, try JSONDecoder().decode(MicroAppManifest.self, from: encoded))
        XCTAssertThrowsError(try JSONDecoder().decode(ActionKind.self, from: Data("\"futureAction\"".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ComponentKind.self, from: Data("\"futureComponent\"".utf8)))
    }

    func testEveryBundledPackageIsCompleteAndValid() throws {
        let templates = try TemplatePackageLibrary().load()
        XCTAssertEqual(templates.count, 5)
        XCTAssertEqual(Set(templates.map { $0.manifest.name }), Set(["Task Board", "Habit Tracker", "Quick Journal", "Inventory List", "Service Log"]))
        for template in templates {
            XCTAssertGreaterThanOrEqual(template.manifest.screens.count, 2, template.manifest.name)
            XCTAssertFalse(template.manifest.collections.isEmpty, template.manifest.name)
            XCTAssertFalse(template.manifest.actions.isEmpty, template.manifest.name)
            XCTAssertTrue(errorCodes(template.manifest).isEmpty, "\(template.manifest.name): \(ManifestValidator().validate(template.manifest))")
            let roundTrip = try PackageCodec().decode(PackageCodec().encode(template.package))
            XCTAssertEqual(roundTrip, template.package)
        }
    }

    func testBlueprintConverterCreatesMultipleScreensTypedFieldsAndChart() async throws {
        let context = BuilderContext(localeIdentifier: "en_US", requestedCapabilities: [])
        let blueprint = try await MockBlueprintGenerator().generateBlueprint(from: "anything", context: context)
        let manifest = BlueprintConverter().convert(blueprint, capabilities: [])
        XCTAssertEqual(manifest.screens.count, 2)
        XCTAssertTrue(manifest.collections.flatMap(\.fields).contains { $0.kind == .number })
        XCTAssertTrue(manifest.screens.flatMap(\.components).contains { $0.kind == .chart })
        XCTAssertTrue(errorCodes(manifest).isEmpty)
    }

    func testValidatorRejectsVersionsDuplicatesReferencesTypesCapabilitiesAndDomains() throws {
        var manifest = try bundledPackage(named: "Inventory List").manifest
        manifest.formatVersion = 2
        XCTAssertEqual(errorCodes(manifest), ["format.unsupported"])

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
        let codes = errorCodes(manifest)
        XCTAssertTrue(codes.contains("identifier.duplicate"))
        XCTAssertTrue(codes.contains("action.missing"))
        XCTAssertTrue(codes.contains("field.defaultType"))
        XCTAssertTrue(codes.contains("capability.undeclared"))
        XCTAssertTrue(codes.contains("network.https"))
        XCTAssertTrue(codes.contains("domain.invalid"))
    }

    func testValidatorEnforcesLimitsAndNesting() throws {
        var manifest = try bundledPackage(named: "Task Board").manifest
        manifest.screens = (0...PocketLimits.screens).map { index in
            .init(id: "screen-\(index)", title: "Screen \(index)", components: [])
        }
        manifest.entryScreenID = manifest.screens[0].id
        XCTAssertTrue(errorCodes(manifest).contains("limit.screens"))

        manifest = try bundledPackage(named: "Task Board").manifest
        var nested = ComponentSpec(id: "depth-0", kind: .group)
        for index in 1...(PocketLimits.nestingDepth + 1) {
            nested = .init(id: "depth-\(index)", kind: .group, children: [nested])
        }
        manifest.screens[0].components = [nested]
        XCTAssertTrue(errorCodes(manifest).contains("limit.depth"))
    }

    func testRepairerProducesStableReferencesWithoutHardcodedAppTypes() {
        let source = MicroAppBlueprint(
            name: "  ",
            summary: "",
            screens: [.init(id: "../bad", title: "", collectionID: "missing")],
            collections: [.init(id: "My Records", title: "", fields: [.init(id: "Bad/Field", title: "")])],
            actions: []
        )
        let repaired = BlueprintRepairer().repair(source)
        XCTAssertEqual(repaired.name, "Pocket App")
        XCTAssertFalse(repaired.screens[0].id.contains("/"))
        XCTAssertEqual(repaired.screens[0].collectionID, repaired.collections[0].id)
        XCTAssertTrue(repaired.actions.contains { $0.kind == .createRecord })
    }

    func testMockIsDeterministicAndTemplateFallbackIsDataDriven() async throws {
        let context = BuilderContext(localeIdentifier: "en_US", requestedCapabilities: [])
        let first = try await MockBlueprintGenerator().generateBlueprint(from: "anything", context: context)
        let second = try await MockBlueprintGenerator().generateBlueprint(from: "different", context: context)
        XCTAssertEqual(first, second)

        let inventory = try await TemplateBlueprintGenerator().generateBlueprint(
            from: "inventory quantities and storage locations",
            context: context
        )
        XCTAssertEqual(inventory.name, "Inventory List")
    }
}

final class ExpressionTests: XCTestCase {
    private let evaluator = ExpressionEvaluator()

    func testArithmeticComparisonBooleanParenthesesAndBindingResolution() throws {
        let context: [String: PocketValue] = [
            "record": .object(["cost": .number(40), "complete": .bool(false)]),
            "environment": .object(["limit": .number(20)])
        ]
        XCTAssertEqual(try evaluator.evaluate("(record.cost + 2) >= environment.limit and not record.complete", context: context), .bool(true))
    }

    func testStringAggregatesCoalesceAndFormatting() throws {
        let context: [String: PocketValue] = [
            "record": .object(["title": .string("Service Log"), "code": .string("A19")]),
            "values": .array([.number(2), .number(4), .number(6)]),
            "empty": .null
        ]
        XCTAssertEqual(try evaluator.evaluate("contains(record.title, \"Service\") and startsWith(record.code, \"A\")", context: context), .bool(true))
        XCTAssertEqual(try evaluator.evaluate("sum(values) / count(values)", context: context), .number(4))
        XCTAssertEqual(try evaluator.evaluate("min(values)", context: context), .number(2))
        XCTAssertEqual(try evaluator.evaluate("max(values)", context: context), .number(6))
        XCTAssertEqual(try evaluator.evaluate("coalesce(empty, \"fallback\")", context: context), .string("fallback"))
        XCTAssertEqual(try evaluator.evaluate("formatNumber(42)", context: context), .string(42.0.formatted()))
    }

    func testMalformedOversizedDepthOperationAndDivisionErrorsAreTyped() {
        XCTAssertThrowsError(try evaluator.evaluate("(true and", context: [:])) { XCTAssertTrue($0 is ExpressionError) }
        XCTAssertThrowsError(try evaluator.evaluate(String(repeating: "1", count: PocketLimits.expressionCharacters + 1), context: [:])) {
            XCTAssertEqual($0 as? ExpressionError, .tooLong)
        }
        XCTAssertThrowsError(try evaluator.evaluate("1 / 0", context: [:])) {
            XCTAssertEqual($0 as? ExpressionError, .divisionByZero)
        }
        let deeplyNested = String(repeating: "(", count: PocketLimits.expressionDepth + 2) + "1" + String(repeating: ")", count: PocketLimits.expressionDepth + 2)
        XCTAssertThrowsError(try evaluator.evaluate(deeplyNested, context: [:])) { XCTAssertEqual($0 as? ExpressionError, .tooDeep) }
    }
}

final class PackageTests: XCTestCase {
    func testEveryBundledPackageRoundTripsWithIntegrity() throws {
        for template in try TemplatePackageLibrary().load() {
            let data = try PackageCodec().encode(template.package)
            XCTAssertLessThan(data.count, PocketLimits.packageBytes)
            XCTAssertEqual(try PackageCodec().decode(data), template.package)
        }
    }

    func testTamperedManifestInvalidHashMalformedBase64DuplicateAndTraversalAssetsAreRejected() throws {
        let codec = PackageCodec()
        var package = try bundledPackage(named: "Inventory List")
        package.manifest.name = "Tampered"
        XCTAssertThrowsError(try codec.decode(codec.encode(package))) { XCTAssertEqual($0 as? PackageError, .invalidHash) }

        package = try bundledPackage(named: "Inventory List")
        package.assets = [.init(id: "bad", mediaType: "image/png", sha256: "00", base64Data: "%%%")]
        XCTAssertThrowsError(try codec.decode(codec.encode(package))) { XCTAssertEqual($0 as? PackageError, .invalidAsset("bad")) }

        package = try bundledPackage(named: "Inventory List")
        let asset = PackageAsset(id: "same", mediaType: "text/plain", sha256: "00", base64Data: Data("a".utf8).base64EncodedString())
        package.assets = [asset, asset]
        XCTAssertThrowsError(try codec.decode(codec.encode(package)))

        package = try bundledPackage(named: "Inventory List")
        package.assets = [.init(id: "../escape", mediaType: "text/plain", sha256: "00", base64Data: "")]
        XCTAssertThrowsError(try codec.decode(codec.encode(package)))
    }

    func testOversizedAndMalformedPackageAreRejected() {
        XCTAssertThrowsError(try PackageCodec().decode(Data(repeating: 0, count: PocketLimits.packageBytes + 1))) {
            XCTAssertEqual($0 as? PackageError, .oversized)
        }
        XCTAssertThrowsError(try PackageCodec().decode(Data("not-json".utf8))) {
            XCTAssertEqual($0 as? PackageError, .malformed)
        }
    }
}

final class PersistenceTests: XCTestCase {
    func testFreshDatabaseInstallMetadataRecordCRUDRuntimePermissionsExportRollbackAndCleanup() async throws {
        let store = try PocketStore(inMemory: true)
        var package = try bundledPackage(named: "Service Log")
        let manifestID = package.manifest.id
        try await store.install(package)

        var installed = try await store.installedApps()
        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(installed[0].manifest.id, manifestID)

        try await store.setFavorite(true, id: manifestID)
        try await store.setDisabled(true, id: manifestID)
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
        try await store.save(record: record, appID: manifestID)
        var records = try await store.records(appID: manifestID, collectionID: "services")
        XCTAssertEqual(records, [record])

        record.values["cost"] = .number(30)
        record.updatedAt = Date()
        try await store.save(record: record, appID: manifestID)
        records = try await store.records(appID: manifestID, collectionID: "services")
        XCTAssertEqual(records.first?.values["cost"], .number(30))

        try await store.setRuntimeValue(.string("oil"), appID: manifestID, key: "search")
        let runtimeValue = try await store.runtimeValue(appID: manifestID, key: "search")
        XCTAssertEqual(runtimeValue, .string("oil"))
        try await store.setPermission(.alwaysAllow, appID: manifestID, capability: .localNotifications)
        let permission = try await store.permission(appID: manifestID, capability: .localNotifications)
        XCTAssertEqual(permission, .alwaysAllow)

        let exported = try await store.exportPackage(appID: manifestID)
        XCTAssertEqual(try PackageCodec().decode(exported).manifest.id, manifestID)

        package.manifest.name = "Updated Service Log"
        package.manifest.updatedAt = Date()
        package.integrity = try PackageCodec().integrity(for: package.manifest)
        try await store.install(package)
        try await store.rollbackManifest(id: manifestID)
        installed = try await store.installedApps()
        XCTAssertEqual(installed[0].manifest.name, "Service Log")

        try await store.deleteRecord(appID: manifestID, collectionID: "services", recordID: record.id)
        records = try await store.records(appID: manifestID, collectionID: "services")
        XCTAssertTrue(records.isEmpty)

        try await store.delete(manifestID)
        installed = try await store.installedApps()
        XCTAssertTrue(installed.isEmpty)
        records = try await store.records(appID: manifestID, collectionID: "services")
        XCTAssertTrue(records.isEmpty)
        let values = try await store.runtimeValues(appID: manifestID)
        XCTAssertTrue(values.isEmpty)
        let deletedPermission = try await store.permission(appID: manifestID, capability: .localNotifications)
        XCTAssertEqual(deletedPermission, .notRequested)
    }

    func testDuplicateAppAndConcurrentActorWritesRemainConsistent() async throws {
        let store = try PocketStore(inMemory: true)
        let package = try bundledPackage(named: "Inventory List")
        try await store.install(package)
        let duplicateID = try await store.duplicate(id: package.manifest.id)
        let installed = try await store.installedApps()
        XCTAssertEqual(installed.count, 2)
        XCTAssertTrue(installed.contains { $0.id == duplicateID && $0.manifest.name.hasSuffix("Copy") })

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let now = Date()
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
        let itemCount = try await store.records(appID: package.manifest.id, collectionID: "items").count
        XCTAssertEqual(itemCount, 40)
    }

    func testRecordLimitRejectsAdditionalWriteWithoutRemovingExistingRecords() async throws {
        let store = try PocketStore(inMemory: true)
        let package = try bundledPackage(named: "Inventory List")
        try await store.install(package)
        let now = Date()
        for index in 0..<PocketLimits.recordsPerCollection {
            try await store.save(
                record: .init(id: UUID(), collectionID: "items", values: ["name": .string("\(index)")], createdAt: now, updatedAt: now),
                appID: package.manifest.id
            )
        }
        await assertThrowsAsync {
            try await store.save(
                record: .init(id: UUID(), collectionID: "items", values: ["name": .string("overflow")], createdAt: now, updatedAt: now),
                appID: package.manifest.id
            )
        } verify: { error in
            XCTAssertEqual(error as? StoreError, .limit)
        }
        let records = try await store.records(appID: package.manifest.id, collectionID: "items")
        XCTAssertEqual(records.count, PocketLimits.recordsPerCollection)
    }
}

final class RuntimeTests: XCTestCase {
    func testPermissionBrokerPromptsAndDenyByDefaultPersistsDecision() async throws {
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

        let askingExecutor = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        await assertThrowsAsync {
            try await askingExecutor.execute("copy-value", manifest: manifest, context: [:])
        } verify: { error in
            guard case RuntimeExecutionError.permissionRequired(let request) = error else {
                return XCTFail("Expected permission request, received \(error)")
            }
            XCTAssertEqual(request.capability, .clipboardWrite)
            XCTAssertEqual(request.reason, "Copy the generated value.")
        }

        let denyingExecutor = ActionExecutor(store: store, intelligence: MockIntelligenceService(), defaultPermission: .denied)
        await assertThrowsAsync {
            try await denyingExecutor.execute("copy-value", manifest: manifest, context: [:])
        } verify: { error in
            guard case RuntimeExecutionError.permissionDenied(.clipboardWrite) = error else {
                return XCTFail("Expected denied permission, received \(error)")
            }
        }
        let decision = try await store.permission(appID: manifest.id, capability: .clipboardWrite)
        XCTAssertEqual(decision, .denied)
    }

    func testCreateUpdateDeleteSortFilterSelectAndAIActionSequence() async throws {
        let store = try PocketStore(inMemory: true)
        var package = try bundledPackage(named: "Inventory List")
        package.manifest.capabilities.insert(.onDeviceModel)
        package.manifest.actions.append(.init(id: "sort-items", kind: .sortRecords, target: "items", parameters: ["field": .string("quantity")]))
        package.manifest.actions.append(.init(id: "filter-items", kind: .filterRecords, target: "items", parameters: ["expression": .string("record.quantity > 1")]))
        package.manifest.actions.append(.init(id: "select-item", kind: .selectRecord, parameters: ["recordID": .string("00000000-0000-0000-0000-000000000010")]))
        package.manifest.actions.append(.init(id: "summary", kind: .summarizeText, value: .string("Long local text"), requiredCapability: .onDeviceModel))
        package.integrity = try PackageCodec().integrity(for: package.manifest)
        try await store.install(package)
        try await store.setPermission(.alwaysAllow, appID: package.manifest.id, capability: .onDeviceModel)
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        let create = try XCTUnwrap(package.manifest.actions.first { $0.kind == .createRecord })

        guard case .record(let first) = try await executor.execute(
            create.id,
            manifest: package.manifest,
            context: ["form": .object(["name": .string("Two"), "quantity": .number(2)])]
        ) else { return XCTFail("Expected first created record") }
        guard case .record = try await executor.execute(
            create.id,
            manifest: package.manifest,
            context: ["form": .object(["name": .string("One"), "quantity": .number(1)])]
        ) else { return XCTFail("Expected second created record") }

        package.manifest.actions.append(.init(
            id: "update-item",
            kind: .updateRecord,
            target: "items",
            parameters: ["recordID": .string(first.id.uuidString), "quantity": .number(3)]
        ))
        package.manifest.actions.append(.init(
            id: "delete-item",
            kind: .deleteRecord,
            target: "items",
            parameters: ["recordID": .string(first.id.uuidString)]
        ))

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
            return XCTFail("Expected selected record ID")
        }
        XCTAssertEqual(selected.uuidString, "00000000-0000-0000-0000-000000000010")

        guard case .value(.string(let summary)) = try await executor.execute("summary", manifest: package.manifest, context: [:]) else {
            return XCTFail("Expected AI text")
        }
        XCTAssertFalse(summary.isEmpty)

        _ = try await executor.execute("delete-item", manifest: package.manifest, context: [:])
        let records = try await store.records(appID: package.manifest.id, collectionID: "items")
        XCTAssertEqual(records.count, 1)
    }

    func testPhotoActionCarriesTargetAndOCRFlag() async throws {
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
        let result = try await executor.execute("choose-receipt", manifest: manifest, context: [:])
        XCTAssertEqual(result, .host(.selectPhotos(target: "receiptImage", recognizeText: true)))
    }

    func testConditionsActionCyclesCancellationAndNetworkBoundaries() async throws {
        let store = try PocketStore(inMemory: true)
        var manifest = try bundledPackage(named: "Inventory List").manifest
        manifest.actions = [.init(id: "conditional", kind: .showAlert, title: "Hidden", condition: "false")]
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        await assertThrowsAsync { try await executor.execute("conditional", manifest: manifest, context: [:]) } verify: { error in
            guard case RuntimeExecutionError.conditionFalse = error else { return XCTFail("Expected false condition") }
        }

        manifest.actions = [.init(id: "loop", kind: .showAlert, title: "Loop", nextActionIDs: ["loop"])]
        await assertThrowsAsync { try await executor.execute("loop", manifest: manifest, context: [:]) } verify: { error in
            guard case RuntimeExecutionError.chainLimit = error else { return XCTFail("Expected chain limit") }
        }

        let cancelled = Task { try await executor.execute("loop", manifest: manifest, context: [:]) }
        cancelled.cancel()
        await assertThrowsAsync { try await cancelled.value } verify: { error in
            guard case RuntimeExecutionError.cancelled = error else { return XCTFail("Expected cancellation") }
        }

        await assertThrowsAsync {
            try await NetworkService().request(urlString: "http://api.example.test", method: "GET", body: nil, allowedDomains: ["api.example.test"])
        } verify: { error in
            guard case HostServiceError.insecureURL = error else { return XCTFail("Expected HTTPS enforcement") }
        }
        await assertThrowsAsync {
            try await NetworkService().request(urlString: "https://other.example.test", method: "GET", body: nil, allowedDomains: ["api.example.test"])
        } verify: { error in
            guard case HostServiceError.domainDenied = error else { return XCTFail("Expected domain denial") }
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
