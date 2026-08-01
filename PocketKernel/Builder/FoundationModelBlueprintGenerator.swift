import Foundation
import FoundationModels

@Generable(description: "A compact declarative micro-app blueprint")
struct FoundationBlueprint {
    @Guide(description: "Short application name") var name: String
    @Guide(description: "One-sentence purpose") var summary: String
    @Guide(description: "Title of the main screen") var screenTitle: String
    @Guide(description: "Plural collection name") var collectionName: String
    @Guide(description: "Two to six short field names", .count(2...6)) var fieldNames: [String]
}

struct FoundationModelBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw FoundationModelError.unavailable(String(describing: model.availability)) }
        let session = LanguageModelSession(model: model, instructions: "Convert requests into small personal database apps. Never add networking or executable code.")
        let response = try await session.respond(to: request, generating: FoundationBlueprint.self)
        let value = response.content
        let collectionID = slug(value.collectionName)
        let fields = value.fieldNames.map { GeneratedField(id: slug($0), title: $0) }
        return MicroAppBlueprint(name: value.name, summary: value.summary,
                                 screens: [.init(id: "home", title: value.screenTitle, collectionID: collectionID)],
                                 collections: [.init(id: collectionID, title: value.collectionName, fields: fields)],
                                 actions: [.init(id: "add-record", title: "Add", kind: .createRecord, target: collectionID)])
    }

    private func slug(_ value: String) -> String {
        let allowed = value.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "-" }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }
}

enum FoundationModelError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let reason) = self { return "Apple Intelligence unavailable: \(reason)" }; return nil }
}

