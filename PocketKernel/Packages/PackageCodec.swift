import CryptoKit
import Foundation
import SwiftUI
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
        PocketPackage(manifest: manifest, assets: assets, integrity: try integrity(for: manifest))
    }

    func integrity(for manifest: MicroAppManifest) throws -> PackageIntegrity {
        let encoded = try makeEncoder().encode(manifest)
        return .init(manifestHash: sha256(try canonicalJSON(encoded)))
    }

    func encode(_ package: PocketPackage) throws -> Data {
        let data = try makeEncoder().encode(package)
        guard data.count <= PocketLimits.packageBytes else { throw PackageError.oversized }
        return data
    }

    func decode(_ data: Data) throws -> PocketPackage {
        guard data.count <= PocketLimits.packageBytes else { throw PackageError.oversized }

        let canonicalManifest: Data
        do { canonicalManifest = try canonicalManifestJSON(in: data) }
        catch { throw PackageError.malformed }

        let package: PocketPackage
        do { package = try makeDecoder().decode(PocketPackage.self, from: data) }
        catch { throw PackageError.malformed }

        guard package.formatVersion == 1, package.integrity.algorithm == "sha256" else {
            throw PackageError.malformed
        }
        guard sha256(canonicalManifest) == package.integrity.manifestHash.lowercased() else {
            throw PackageError.invalidHash
        }

        var decodedTotal = 0
        var assetIDs = Set<String>()
        for asset in package.assets {
            guard assetIDs.insert(asset.id).inserted,
                  !asset.id.isEmpty,
                  !asset.id.contains(".."),
                  !asset.id.contains("/"),
                  !asset.id.contains("\\")
            else { throw PackageError.invalidAsset(asset.id) }
            guard let decoded = Data(base64Encoded: asset.base64Data),
                  decoded.count <= PocketLimits.assetBytes
            else { throw PackageError.invalidAsset(asset.id) }
            decodedTotal += decoded.count
            guard decodedTotal <= PocketLimits.packageBytes,
                  sha256(decoded) == asset.sha256.lowercased()
            else { throw PackageError.invalidAsset(asset.id) }
        }

        let issues = ManifestValidator().validate(package.manifest).filter { $0.severity == .error }
        guard issues.isEmpty else { throw PackageError.invalidManifest(issues) }
        return package
    }

    private func canonicalManifestJSON(in packageData: Data) throws -> Data {
        guard let package = try JSONSerialization.jsonObject(with: packageData) as? [String: Any],
              let manifest = package["manifest"]
        else { throw PackageError.malformed }
        return try canonicalJSON(manifest)
    }

    private func canonicalJSON(_ data: Data) throws -> Data {
        try canonicalJSON(JSONSerialization.jsonObject(with: data))
    }

    private func canonicalJSON(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw PackageError.malformed }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder { JSONDecoder() }
}

struct PocketAppDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pocketApp] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw PackageError.malformed }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
