import XCTest
@testable import PocketKernel

final class DomainAndValidationTests: XCTestCase {
    func testPocketValueRoundTrip() throws {
        let value = PocketValue.object(["done": .bool(false), "cost": .number(42.5), "tags": .array([.string("car")]), "date": .date(Date(timeIntervalSince1970: 100))])
        XCTAssertEqual(value, try JSONDecoder().decode(PocketValue.self, from: JSONEncoder().encode(value)))
    }

    func testManifestRoundTrip() throws {
        let manifest = BlueprintConverter().convert(TemplateCatalog.serviceLogBlueprint, capabilities: [.localNotifications])
        XCTAssertEqual(manifest, try JSONDecoder().decode(MicroAppManifest.self, from: JSONEncoder().encode(manifest)))
    }

    func testBlueprintConverterCreatesMultipleScreensAndTypedFields() {
        let manifest = BlueprintConverter().convert(TemplateCatalog.serviceLogBlueprint, capabilities: [])
        XCTAssertEqual(manifest.screens.count, 2)
        XCTAssertEqual(manifest.collections.first?.fields.first?.kind, .number)
        XCTAssertTrue(manifest.screens.flatMap(\.components).contains { $0.kind == .chart })
    }

    func testRejectsUnsupportedVersionDuplicatesAndBrokenReferences() {
        var manifest = BlueprintConverter().convert(TemplateCatalog.serviceLogBlueprint, capabilities: [])
        manifest.formatVersion = 2
        XCTAssertTrue(ManifestValidator().validate(manifest).contains { $0.code == "format.unsupported" })
        manifest.formatVersion = 1
        manifest.screens.append(manifest.screens[0])
        manifest.screens[0].components[0].actionID = "missing"
        let issues = ManifestValidator().validate(manifest)
        XCTAssertTrue(issues.contains { $0.code == "identifier.duplicate" })
        XCTAssertTrue(issues.contains { $0.code == "action.missing" })
    }

    func testCapabilityAndDomainValidation() {
        var manifest = BlueprintConverter().convert(TemplateCatalog.inventoryBlueprint, capabilities: [])
        manifest.actions.append(.init(id: "get", kind: .httpGet, target: "https://api.example.test", requiredCapability: .network))
        manifest.allowedDomains = ["*.example.test"]
        let issues = ManifestValidator().validate(manifest)
        XCTAssertTrue(issues.contains { $0.code == "capability.undeclared" })
        XCTAssertTrue(issues.contains { $0.code == "domain.invalid" })
    }

    func testRepairerProducesStableValidIdentifiers() {
        let source = MicroAppBlueprint(name: "  ", summary: "", screens: [.init(id: "../bad", title: "", collectionID: "missing")], collections: [.init(id: "My Records", title: "", fields: [.init(id: "Bad/Field", title: "")])], actions: [])
        let repaired = BlueprintRepairer().repair(source)
        XCTAssertFalse(repaired.name.isEmpty)
        XCTAssertFalse(repaired.screens[0].id.contains("/"))
        XCTAssertEqual(repaired.screens[0].collectionID, repaired.collections[0].id)
        XCTAssertTrue(repaired.actions.contains { $0.kind == .createRecord })
    }

    func testMockBlueprintIsDeterministic() async throws {
        let context = BuilderContext(localeIdentifier: "en_US", requestedCapabilities: [])
        let first = try await MockBlueprintGenerator().generateBlueprint(from: "anything", context: context)
        let second = try await MockBlueprintGenerator().generateBlueprint(from: "different", context: context)
        XCTAssertEqual(first, second)
    }
}

final class ExpressionTests: XCTestCase {
    private let evaluator = ExpressionEvaluator()

    func testArithmeticComparisonBooleanAndParentheses() throws {
        XCTAssertEqual(try evaluator.evaluate("(2 + 3 * 4) >= 14 and not false", context: [:]), .bool(true))
    }

    func testBindingAndStringFunctions() throws {
        let context: [String: PocketValue] = ["record": .object(["title": .string("Service Log"), "code": .string("A19")])]
        XCTAssertEqual(try evaluator.evaluate("contains(record.title, \"Service\") and startsWith(record.code, \"A\")", context: context), .bool(true))
    }

    func testAggregatesCoalesceAndFormatting() throws {
        let context: [String: PocketValue] = ["values": .array([.number(2), .number(4), .number(6)]), "empty": .null]
        XCTAssertEqual(try evaluator.evaluate("sum(values) / count(values)", context: context), .number(4))
        XCTAssertEqual(try evaluator.evaluate("coalesce(empty, \"fallback\")", context: context), .string("fallback"))
        XCTAssertEqual(try evaluator.evaluate("formatNumber(42)", context: context), .string(42.0.formatted()))
    }

    func testMalformedAndOversizedExpressionsReturnTypedErrors() {
        XCTAssertThrowsError(try evaluator.evaluate("(true and", context: [:])) { XCTAssertTrue($0 is ExpressionError) }
        XCTAssertThrowsError(try evaluator.evaluate(String(repeating: "1", count: PocketLimits.expressionCharacters + 1), context: [:])) { XCTAssertEqual($0 as? ExpressionError, .tooLong) }
        XCTAssertThrowsError(try evaluator.evaluate("1 / 0", context: [:])) { XCTAssertEqual($0 as? ExpressionError, .divisionByZero) }
    }
}

final class PackageTests: XCTestCase {
    func testPackageRoundTripAndIntegrity() throws {
        let codec = PackageCodec()
        let manifest = BlueprintConverter().convert(TemplateCatalog.serviceLogBlueprint, capabilities: [])
        let package = try codec.makePackage(manifest: manifest)
        XCTAssertEqual(try codec.decode(codec.encode(package)), package)
    }

    func testTamperedManifestInvalidHashAndMalformedAssetAreRejected() throws {
        let codec = PackageCodec()
        var package = try codec.makePackage(manifest: BlueprintConverter().convert(TemplateCatalog.inventoryBlueprint, capabilities: []))
        package.manifest.name = "Tampered"
        XCTAssertThrowsError(try codec.decode(codec.encode(package))) { XCTAssertEqual($0 as? PackageError, .invalidHash) }

        var assetPackage = try codec.makePackage(manifest: BlueprintConverter().convert(TemplateCatalog.inventoryBlueprint, capabilities: []))
        assetPackage.assets = [.init(id: "bad", mediaType: "image/png", sha256: "00", base64Data: "%%%")]
        XCTAssertThrowsError(try codec.decode(codec.encode(assetPackage)))
    }

    func testOversizedPackageRejected() {
        XCTAssertThrowsError(try PackageCodec().decode(Data(repeating: 0, count: PocketLimits.packageBytes + 1))) { XCTAssertEqual($0 as? PackageError, .oversized) }
    }
}

final class PersistenceTests: XCTestCase {
    func testInstallMetadataRecordsRuntimePermissionsExportRollbackAndCleanup() async throws {
        let store = try PocketStore(inMemory: true)
        var manifest = BlueprintConverter().convert(TemplateCatalog.serviceLogBlueprint, capabilities: [.localNotifications])
        try await store.install(PackageCodec().makePackage(manifest: manifest))
        let installedCount = try await store.installedApps().count
        XCTAssertEqual(installedCount, 1)

        try await store.setFavorite(true, id: manifest.id)
        try await store.setDisabled(true, id: manifest.id)
        var info = try await store.installedApps()[0]
        XCTAssertTrue(info.favorite)
        XCTAssertTrue(info.disabled)

        let now = Date()
        let record = PocketRecord(id: UUID(), collectionID: "services", values: ["cost": .number(20)], createdAt: now, updatedAt: now)
        try await store.save(record: record, appID: manifest.id)
        let serviceRecords = try await store.records(appID: manifest.id, collectionID: "services")
        XCTAssertEqual(serviceRecords, [record])

        try await store.setRuntimeValue(.string("query"), appID: manifest.id, key: "search")
        let runtimeValue = try await store.runtimeValue(appID: manifest.id, key: "search")
        XCTAssertEqual(runtimeValue, .string("query"))
        try await store.setPermission(.alwaysAllow, appID: manifest.id, capability: .localNotifications)
        let permission = try await store.permission(appID: manifest.id, capability: .localNotifications)
        XCTAssertEqual(permission, .alwaysAllow)

        let exported = try await store.exportPackage(appID: manifest.id)
        XCTAssertEqual(try PackageCodec().decode(exported).manifest.id, manifest.id)

        manifest.name = "Updated"
        manifest.updatedAt = Date()
        try await store.install(PackageCodec().makePackage(manifest: manifest))
        try await store.rollbackManifest(id: manifest.id)
        info = try await store.installedApps()[0]
        XCTAssertNotEqual(info.manifest.name, "Updated")

        try await store.delete(manifest.id)
        let installedAfterDelete = try await store.installedApps()
        XCTAssertTrue(installedAfterDelete.isEmpty)
        let recordsAfterDelete = try await store.records(appID: manifest.id, collectionID: "services")
        XCTAssertTrue(recordsAfterDelete.isEmpty)
    }

    func testConcurrentActorWritesRemainConsistent() async throws {
        let store = try PocketStore(inMemory: true)
        let manifest = BlueprintConverter().convert(TemplateCatalog.inventoryBlueprint, capabilities: [])
        try await store.install(PackageCodec().makePackage(manifest: manifest))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let now = Date()
                    try await store.save(record: .init(id: UUID(), collectionID: "items", values: ["name": .string("Item \(index)")], createdAt: now, updatedAt: now), appID: manifest.id)
                }
            }
            try await group.waitForAll()
        }
        let itemCount = try await store.records(appID: manifest.id, collectionID: "items").count
        XCTAssertEqual(itemCount, 40)
    }
}

final class RuntimeTests: XCTestCase {
    func testPermissionBrokerRequiresExplicitDecision() async throws {
        let store = try PocketStore(inMemory: true)
        var manifest = BlueprintConverter().convert(TemplateCatalog.inventoryBlueprint, capabilities: [.clipboardWrite])
        manifest.actions.append(.init(id: "copy", kind: .copyToClipboard, value: .string("value"), requiredCapability: .clipboardWrite, reason: "Copy the result"))
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        do {
            _ = try await executor.execute("copy", manifest: manifest, context: [:])
            XCTFail("Expected permission request")
        } catch RuntimeExecutionError.permissionRequired(let request) {
            XCTAssertEqual(request.capability, .clipboardWrite)
        }
    }

    func testCreateSortFilterAndAIAction() async throws {
        let store = try PocketStore(inMemory: true)
        var manifest = BlueprintConverter().convert(TemplateCatalog.inventoryBlueprint, capabilities: [.onDeviceModel])
        manifest.actions.append(.init(id: "sort", kind: .sortRecords, target: "items", parameters: ["field": .string("quantity")]))
        manifest.actions.append(.init(id: "filter", kind: .filterRecords, target: "items", parameters: ["expression": .string("record.quantity > 1")]))
        manifest.actions.append(.init(id: "summary", kind: .summarizeText, value: .string("Long local text"), requiredCapability: .onDeviceModel))
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        try await store.setPermission(.alwaysAllow, appID: manifest.id, capability: .onDeviceModel)

        let create = manifest.actions.first { $0.kind == .createRecord }!
        _ = try await executor.execute(create.id, manifest: manifest, context: ["form": .object(["name": .string("Two"), "quantity": .number(2)])])
        _ = try await executor.execute(create.id, manifest: manifest, context: ["form": .object(["name": .string("One"), "quantity": .number(1)])])

        guard case .records(let sorted) = try await executor.execute("sort", manifest: manifest, context: [:]) else { return XCTFail("Expected sorted records") }
        XCTAssertEqual(sorted.first?.values["quantity"], .number(1))
        guard case .records(let filtered) = try await executor.execute("filter", manifest: manifest, context: [:]) else { return XCTFail("Expected filtered records") }
        XCTAssertEqual(filtered.count, 1)
        guard case .value(.string(let summary)) = try await executor.execute("summary", manifest: manifest, context: [:]) else { return XCTFail("Expected AI text") }
        XCTAssertFalse(summary.isEmpty)
    }

    func testActionChainLoopIsRejected() async throws {
        let store = try PocketStore(inMemory: true)
        var manifest = BlueprintConverter().convert(TemplateCatalog.inventoryBlueprint, capabilities: [])
        manifest.actions = [.init(id: "loop", kind: .showAlert, title: "Loop", nextActionIDs: ["loop"])]
        let executor = ActionExecutor(store: store, intelligence: MockIntelligenceService())
        await XCTAssertThrowsErrorAsync(try await executor.execute("loop", manifest: manifest, context: [:]))
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
        catch { }
    }
}
