import Foundation
import FoundationModels

@Generable(description: "A field in a local declarative app collection")
struct FoundationGeneratedField {
    @Guide(description: "Stable short identifier using letters and numbers") var id: String
    @Guide(description: "Human-readable field label") var title: String
    @Guide(description: "One of text, multilineText, number, boolean, date, choice, image") var kind: String
}

@Generable(description: "A persistent collection in a local declarative app")
struct FoundationGeneratedCollection {
    @Guide(description: "Stable short identifier") var id: String
    @Guide(description: "Plural human-readable collection name") var title: String
    @Guide(description: "Two to eight useful fields", .count(2...8)) var fields: [FoundationGeneratedField]
}

@Generable(description: "A native screen backed by an optional collection")
struct FoundationGeneratedScreen {
    @Guide(description: "Stable short identifier") var id: String
    @Guide(description: "Screen title") var title: String
    @Guide(description: "Collection identifier shown by this screen, or empty when not needed") var collectionID: String
}

@Generable(description: "A complete bounded micro-app blueprint")
struct FoundationGeneratedBlueprint {
    @Guide(description: "Short application name") var name: String
    @Guide(description: "One sentence explaining the app") var summary: String
    @Guide(description: "One to five useful screens", .count(1...5)) var screens: [FoundationGeneratedScreen]
    @Guide(description: "One to five persistent collections", .count(1...5)) var collections: [FoundationGeneratedCollection]
}

struct FoundationModelBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw FoundationModelError.unavailable(String(describing: model.availability))
        }

        let existing = context.existingManifest.map { manifest in
            "The user is editing an app named \(manifest.name) with screens: \(manifest.screens.map(\.title).joined(separator: ", ")). Preserve useful existing concepts while applying the requested change."
        } ?? "Create a new app."

        let instructions = """
        Build a useful personal productivity micro-app as a typed declarative blueprint.
        Produce multiple screens when the request benefits from separate overview, list, or history views.
        Use persistent collections and meaningful fields. Never generate source code, URLs, JavaScript, executable content, or private APIs.
        Field kind must be exactly text, multilineText, number, boolean, date, choice, or image.
        Every screen collectionID must match one generated collection ID.
        \(existing)
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: request, generating: FoundationGeneratedBlueprint.self)
        let generated = response.content

        let collections = generated.collections.map { collection in
            GeneratedCollection(
                id: slug(collection.id),
                title: collection.title,
                fields: collection.fields.map { field in
                    GeneratedField(id: slug(field.id), title: field.title, kind: FieldKind(rawValue: field.kind) ?? .text)
                }
            )
        }
        let fallbackCollection = collections.first?.id
        let screens = generated.screens.map { screen in
            GeneratedScreen(id: slug(screen.id), title: screen.title, collectionID: screen.collectionID.isEmpty ? fallbackCollection : slug(screen.collectionID))
        }
        let actions = collections.map { collection in
            GeneratedAction(id: "add-\(collection.id)", title: "Add \(singular(collection.title))", kind: .createRecord, target: collection.id)
        }
        return BlueprintRepairer().repair(.init(name: generated.name, summary: generated.summary, screens: screens, collections: collections, actions: actions))
    }

    private func slug(_ value: String) -> String {
        let characters = value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let result = String(characters).split(separator: "-").joined(separator: "-")
        return result.isEmpty ? "item" : result
    }

    private func singular(_ value: String) -> String {
        value.hasSuffix("s") && value.count > 1 ? String(value.dropLast()) : value
    }
}

enum FoundationModelError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Apple Intelligence unavailable: \(reason)"
        }
    }
}
