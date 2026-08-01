import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let pocketApp = UTType(exportedAs: "com.nightvibes33.pocketapp", conformingTo: .data)
}

enum PackageError: LocalizedError, Equatable {
    case oversized, malformed, invalidHash, invalidAsset(String), invalidManifest([ValidationIssue])
    var errorDescription: String? {
        switch self {
        case .oversized: "Package exceeds the 25 MB limit."
        case .malformed: "Package data is malformed."
        case .invalidHash: "Manifest integrity check failed."
        case .invalidAsset(let id): "Asset integrity check failed: \(id)."
        case .invalidManifest(let issues): issues.map(\.message).joined(separator: " ")
        }
    }
}

struct PackageCodec: Sendable {
    func makePackage(manifest: MicroAppManifest, assets: [PackageAsset] = []) throws -> PocketPackage {
        let hash = sha256(try makeEncoder().encode(manifest))
        return PocketPackage(manifest: manifest, assets: assets, integrity: .init(manifestHash: hash))
    }

    func encode(_ package: PocketPackage) throws -> Data { try makeEncoder().encode(package) }

    func decode(_ data: Data) throws -> PocketPackage {
        guard data.count <= PocketLimits.packageBytes else { throw PackageError.oversized }
        let package: PocketPackage
        do { package = try makeDecoder().decode(PocketPackage.self, from: data) } catch { throw PackageError.malformed }
        guard package.formatVersion == 1, package.integrity.algorithm == "sha256" else { throw PackageError.malformed }
        guard sha256(try makeEncoder().encode(package.manifest)) == package.integrity.manifestHash.lowercased() else { throw PackageError.invalidHash }
        var decodedTotal = 0
        var assetIDs = Set<String>()
        for asset in package.assets {
            guard assetIDs.insert(asset.id).inserted, !asset.id.contains(".."), !asset.id.contains("/") else { throw PackageError.invalidAsset(asset.id) }
            guard let decoded = Data(base64Encoded: asset.base64Data) else { throw PackageError.invalidAsset(asset.id) }
            decodedTotal += decoded.count
            guard decodedTotal <= PocketLimits.packageBytes, sha256(decoded) == asset.sha256.lowercased() else { throw PackageError.invalidAsset(asset.id) }
        }
        let issues = ManifestValidator().validate(package.manifest).filter { $0.severity == .error }
        guard issues.isEmpty else { throw PackageError.invalidManifest(issues) }
        return package
    }

    private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func makeEncoder() -> JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value }
    private func makeDecoder() -> JSONDecoder { JSONDecoder() }
}
