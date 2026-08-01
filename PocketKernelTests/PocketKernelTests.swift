import XCTest
@testable import PocketKernel

final class PocketKernelTests: XCTestCase {
    func testPocketValueRoundTrip() throws {
        let source = PocketValue.object(["done": .bool(false), "cost": .number(42.5), "tags": .array([.string("car")])])
        XCTAssertEqual(source, try JSONDecoder().decode(PocketValue.self, from: JSONEncoder().encode(source)))
    }

    func testBlueprintIsDeterministicAndValid() async throws {
        let blueprint = try await MockBlueprintGenerator().generateBlueprint(from: "anything", context: .init(localeIdentifier: "en_US", requestedCapabilities: []))
        XCTAssertEqual(blueprint, .serviceLog)
        XCTAssertTrue(ManifestValidator().validate(BlueprintConverter().convert(blueprint, capabilities: [])).isEmpty)
    }

    func testRejectsMissingReferences() {
        var manifest = BlueprintConverter().convert(.serviceLog, capabilities: [])
        manifest.screens[0].components[0].collection = "missing"
        XCTAssertTrue(ManifestValidator().validate(manifest).contains { $0.code == "collection.missing" })
    }

    func testPackageRoundTripAndTamperDetection() throws {
        let codec = PackageCodec(); let manifest = BlueprintConverter().convert(.serviceLog, capabilities: [])
        let data = try codec.encode(codec.makePackage(manifest: manifest))
        XCTAssertEqual(try codec.decode(data).manifest, manifest)
        var package = try JSONDecoder.iso8601.decode(PocketPackage.self, from: data); package.manifest.name = "Tampered"
        XCTAssertThrowsError(try codec.decode(try JSONEncoder.iso8601.encode(package)))
    }

    func testSQLitePersistence() async throws {
        let store = try PocketStore(inMemory: true); let manifest = BlueprintConverter().convert(.serviceLog, capabilities: [])
        try await store.install(manifest)
        let installed = try await store.installedApps()
        XCTAssertEqual(installed.map(\.id), [manifest.id])
        try await store.delete(manifest.id)
        let remaining = try await store.installedApps()
        XCTAssertTrue(remaining.isEmpty)
    }
}

private extension JSONEncoder { static var iso8601: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value } }
private extension JSONDecoder { static var iso8601: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value } }
