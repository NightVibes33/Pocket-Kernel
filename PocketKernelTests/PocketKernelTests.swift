import XCTest
@testable import PocketKernel

@MainActor final class DomainAndValidationTests: XCTestCase {
    func testPocketValueRoundTrip() throws {
        let source = PocketValue.object(["done": .bool(false), "cost": .number(42.5), "tags": .array([.string("car")]), "date": .date(Date(timeIntervalSince1970: 100))])
        XCTAssertEqual(source, try JSONDecoder().decode(PocketValue.self, from: JSONEncoder().encode(source)))
    }

    func testManifestRoundTrip() throws {
        let manifest = BlueprintConverter().convert(.serviceLog, capabilities: [])
        XCTAssertEqual(manifest, try JSONDecoder().decode(MicroAppManifest.self, from: JSONEncoder().encode(manifest)))
    }

    func testRejectsUnsupportedVersionAndDuplicateIDs() {
        var manifest = BlueprintConverter().convert(.serviceLog, capabilities: []); manifest.formatVersion = 2
        XCTAssertTrue(ManifestValidator().validate(manifest).contains { $0.code == "format.unsupported" })
        manifest.formatVersion = 1; manifest.screens.append(manifest.screens[0])
        XCTAssertTrue(ManifestValidator().validate(manifest).contains { $0.code == "identifier.duplicate" })
    }

    func testRejectsMissingReferencesAndUndeclaredCapabilities() {
        var manifest = BlueprintConverter().convert(.serviceLog, capabilities: [])
        manifest.screens[0].components[0].collection = "missing"
        manifest.actions.append(.init(id: "network", kind: .httpGet, target: "https://api.apple.com", requiredCapability: .network))
        let issues = ManifestValidator().validate(manifest)
        XCTAssertTrue(issues.contains { $0.code == "collection.missing" }); XCTAssertTrue(issues.contains { $0.code == "capability.undeclared" })
    }

    func testMockBlueprintIsDeterministicAndValid() async throws {
        let first = try await MockBlueprintGenerator().generateBlueprint(from: "one", context: .init(localeIdentifier: "en_US", requestedCapabilities: []))
        let second = try await MockBlueprintGenerator().generateBlueprint(from: "two", context: .init(localeIdentifier: "en_US", requestedCapabilities: []))
        XCTAssertEqual(first, second); XCTAssertTrue(ManifestValidator().validate(BlueprintConverter().convert(first, capabilities: [])).isEmpty)
    }
}

@MainActor final class ExpressionTests: XCTestCase {
    let evaluator = ExpressionEvaluator()
    func testArithmeticComparisonAndBooleanLogic() throws { XCTAssertEqual(try evaluator.evaluate("(2 + 3 * 4) >= 14 and not false", context: [:]), .bool(true)) }
    func testBindingsAndStringFunctions() throws { XCTAssertEqual(try evaluator.evaluate("contains(record.title, \"Service\") and startsWith(record.code, \"A\")", context: ["record": .object(["title": .string("Service Log"), "code": .string("A19")])]), .bool(true)) }
    func testAggregateFunctions() throws { XCTAssertEqual(try evaluator.evaluate("sum(values) / count(values)", context: ["values": .array([.number(2), .number(4), .number(6)])]), .number(4)) }
    func testMalformedExpressionReturnsTypedError() { XCTAssertThrowsError(try evaluator.evaluate("(true and", context: [:])) { XCTAssertTrue($0 is ExpressionError) } }
    func testExpressionLengthLimit() { XCTAssertThrowsError(try evaluator.evaluate(String(repeating: "1", count: 2_001), context: [:])) { XCTAssertEqual($0 as? ExpressionError, .tooLong) } }
}

@MainActor final class PackageTests: XCTestCase {
    func testPackageRoundTrip() throws { let codec = PackageCodec(); let manifest = BlueprintConverter().convert(.serviceLog, capabilities: []); XCTAssertEqual(try codec.decode(codec.encode(codec.makePackage(manifest: manifest))).manifest, manifest) }
    func testTamperedManifestIsRejected() throws { let codec = PackageCodec(); var package = try codec.makePackage(manifest: BlueprintConverter().convert(.serviceLog, capabilities: [])); package.manifest.name = "Tampered"; XCTAssertThrowsError(try codec.decode(codec.encode(package))) }
    func testMalformedBase64AssetIsRejected() throws { let codec = PackageCodec(); let manifest = BlueprintConverter().convert(.serviceLog, capabilities: []); var package = try codec.makePackage(manifest: manifest); package.assets = [.init(id: "bad", mediaType: "image/png", sha256: "00", base64Data: "%%%")]; XCTAssertThrowsError(try codec.decode(codec.encode(package))) }
    func testOversizedPackageIsRejected() { XCTAssertThrowsError(try PackageCodec().decode(Data(repeating: 0, count: PocketLimits.packageBytes + 1))) { XCTAssertEqual($0 as? PackageError, .oversized) } }
}

@MainActor final class PersistenceAndRuntimeTests: XCTestCase {
    func testSQLiteCRUDRuntimePermissionsAndCleanup() async throws {
        let store = try PocketStore(inMemory: true); let manifest = BlueprintConverter().convert(.serviceLog, capabilities: [.localNotifications]); try await store.install(manifest)
        let now = Date(); let record = PocketRecord(id: UUID(), collectionID: "services", values: ["cost": .number(20)], createdAt: now, updatedAt: now); try await store.save(record: record, appID: manifest.id)
        let records = try await store.records(appID: manifest.id, collectionID: "services"); XCTAssertEqual(records, [record])
        try await store.setRuntimeValue(.string("query"), appID: manifest.id, key: "search"); let runtimeValue = try await store.runtimeValue(appID: manifest.id, key: "search"); XCTAssertEqual(runtimeValue, .string("query"))
        try await store.setPermission(.alwaysAllow, appID: manifest.id, capability: .localNotifications); let permission = try await store.permission(appID: manifest.id, capability: .localNotifications); XCTAssertEqual(permission, .alwaysAllow)
        try await store.log(appID: manifest.id, level: .info, category: "test", message: "passed"); let activity = try await store.activity(); XCTAssertEqual(activity.first?.message, "passed")
        try await store.delete(manifest.id); let remaining = try await store.records(appID: manifest.id, collectionID: "services"); XCTAssertTrue(remaining.isEmpty)
    }

    func testTransactionRollbackOnRecordLimit() async throws {
        let store = try PocketStore(inMemory: true); let manifest = BlueprintConverter().convert(.serviceLog, capabilities: []); try await store.install(manifest)
        let now = Date(); let record = PocketRecord(id: UUID(), collectionID: "services", values: [:], createdAt: now, updatedAt: now); try await store.save(record: record, appID: manifest.id)
        let records = try await store.records(appID: manifest.id, collectionID: "services"); XCTAssertEqual(records.count, 1)
    }

    func testPermissionBrokerRequiresExplicitDecision() async throws {
        let store = try PocketStore(inMemory: true); var manifest = BlueprintConverter().convert(.serviceLog, capabilities: [.clipboardWrite]); manifest.actions.append(.init(id: "copy", kind: .copyToClipboard, value: .string("value"), requiredCapability: .clipboardWrite, reason: "Copy the result"))
        let executor = ActionExecutor(store: store)
        do { _ = try await executor.execute("copy", manifest: manifest, context: [:]); XCTFail("Expected permission request") } catch RuntimeExecutionError.permissionRequired(let request) { XCTAssertEqual(request.capability, .clipboardWrite) }
    }
}
