import Foundation
import FoundationModels

@Generable(description: "A trigger for a deterministic automation")
struct PKGeneratedAutomationTrigger {
    @Guide(description: "One of manual, schedule, webhook, accountEvent, webCondition, workflowCompleted, location")
    var kind: String

    @Guide(description: "Schedule cadence such as daily, weekdays, weekly, or an empty string")
    var cadence: String

    @Guide(description: "Local 24-hour time such as 08:00, or an empty string")
    var time: String

    @Guide(description: "IANA time-zone identifier, or an empty string to use the device time zone")
    var timeZoneIdentifier: String

    @Guide(description: "A concise account event, condition, webhook, workflow, or location description, otherwise empty")
    var eventDescription: String
}

@Generable(description: "One string input for a registered automation operation")
struct PKGeneratedAutomationInput {
    @Guide(description: "Operation input key")
    var key: String

    @Guide(description: "Literal value or a binding such as {{ previous.output }}")
    var value: String
}

@Generable(description: "One registered deterministic automation step")
struct PKGeneratedAutomationStep {
    @Guide(description: "Stable unique identifier using lowercase letters, numbers, and hyphens")
    var id: String

    @Guide(description: "Short human-readable step title")
    var title: String

    @Guide(description: "Exact registered service identifier")
    var service: String

    @Guide(description: "Exact registered operation identifier for that service")
    var operation: String

    @Guide(description: "Typed operation inputs", .count(0...12))
    var inputs: [PKGeneratedAutomationInput]

    @Guide(description: "Optional bounded condition expression, otherwise empty")
    var condition: String
}

@Generable(description: "A complete deterministic service automation blueprint")
struct PKGeneratedAutomationBlueprint {
    @Guide(description: "Short automation name")
    var name: String

    @Guide(description: "One sentence explaining the result")
    var summary: String

    var trigger: PKGeneratedAutomationTrigger

    @Guide(description: "One to thirty-two ordered registered steps", .count(1...32))
    var steps: [PKGeneratedAutomationStep]
}

struct PKFoundationAutomationGenerator: Sendable {
    func generate(_ request: String) async throws -> PKAutomation {
        let prompt = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count >= 8 else { throw PKFoundationAutomationError.invalidPrompt }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw PKFoundationAutomationError.unavailable(String(describing: model.availability))
        }

        let catalog = PKOperationCatalog.operations
            .map { "\($0.service.rawValue).\($0.operation)" }
            .joined(separator: ", ")
        let instructions = """
        Convert the request into a deterministic automation blueprint.
        Use only these registered service operations: \(catalog).
        Preserve the user's requested order and include only necessary steps.
        Reading, filtering, formatting, and classification steps may execute without approval.
        The host—not the model—assigns approval to every operation that mutates an external service.
        Bind later steps to prior output with {{ previous.output }} or {{ step-id.output }}.
        Never produce source code, JavaScript, shell commands, SQL, credentials, access tokens, private APIs, or undocumented operations.
        Do not claim an OAuth account is connected.
        Use a schedule trigger only when the request specifies recurrence or a time.
        Use accountEvent, webCondition, webhook, workflowCompleted, or location only when explicitly requested.
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: prompt, generating: PKGeneratedAutomationBlueprint.self)
        return try convert(response.content, originalPrompt: prompt)
    }

    private func convert(
        _ generated: PKGeneratedAutomationBlueprint,
        originalPrompt: String
    ) throws -> PKAutomation {
        var usedIDs = Set<String>()
        let steps = generated.steps.compactMap { generatedStep -> PKWorkflowStep? in
            guard let service = PKServiceKind(rawValue: generatedStep.service),
                  let definition = PKOperationCatalog.definition(service: service, operation: generatedStep.operation)
            else { return nil }

            var identifier = slug(generatedStep.id)
            if identifier.isEmpty { identifier = slug(generatedStep.title) }
            if identifier.isEmpty { identifier = "step" }
            var candidate = identifier
            var suffix = 2
            while !usedIDs.insert(candidate).inserted {
                candidate = "\(identifier)-\(suffix)"
                suffix += 1
            }

            let inputs = Dictionary(
                generatedStep.inputs.map { (slugKey($0.key), $0.value) },
                uniquingKeysWith: { _, replacement in replacement }
            )
            let condition = generatedStep.condition.trimmingCharacters(in: .whitespacesAndNewlines)
            return PKWorkflowStep(
                id: candidate,
                title: normalizedTitle(generatedStep.title, fallback: "Run \(definition.operation)"),
                service: service,
                operation: definition.operation,
                inputs: inputs,
                condition: condition.isEmpty ? nil : condition,
                approval: definition.mutation ? .externalMutation : .none,
                retryCount: 3,
                mutatesExternalState: definition.mutation
            )
        }

        guard !steps.isEmpty else { throw PKFoundationAutomationError.noSupportedSteps }

        let now = Date()
        let automation = PKAutomation(
            id: UUID(),
            name: normalizedTitle(generated.name, fallback: "New Automation"),
            summary: normalizedTitle(generated.summary, fallback: originalPrompt),
            state: .draft,
            trigger: trigger(from: generated.trigger),
            steps: steps,
            connections: connections(for: steps),
            createdAt: now,
            updatedAt: now
        )
        let issues = PKAutomationValidator().validate(automation)
        guard !issues.contains(where: { $0.severity == .error }) else {
            throw PKFoundationAutomationError.invalidGeneratedWorkflow(
                issues.filter { $0.severity == .error }.map(\.message).joined(separator: " ")
            )
        }
        return automation
    }

    private func trigger(from generated: PKGeneratedAutomationTrigger) -> PKTrigger {
        let kind = PKTriggerKind(rawValue: generated.kind) ?? .manual
        let zone = generated.timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        var configuration: [String: String] = [:]
        let cadence = generated.cadence.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = generated.time.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = generated.eventDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cadence.isEmpty { configuration["cadence"] = cadence }
        if !time.isEmpty { configuration["time"] = time }
        if !event.isEmpty { configuration["event"] = event }
        return PKTrigger(
            kind: kind,
            configuration: configuration,
            timeZoneIdentifier: zone.isEmpty ? TimeZone.current.identifier : zone
        )
    }

    private func connections(for steps: [PKWorkflowStep]) -> [PKConnectionRequirement] {
        let localServices: Set<PKServiceKind> = [.transform, .control, .intelligence, .notifications, .http, .rss]
        let services = Set(steps.map(\.service)).subtracting(localServices)
        return services.sorted { $0.rawValue < $1.rawValue }.map { service in
            let scopes = steps
                .filter { $0.service == service }
                .compactMap { PKOperationCatalog.definition(service: service, operation: $0.operation) }
                .flatMap(\.scopes)
            return PKConnectionRequirement(
                id: service.rawValue,
                service: service,
                scopes: Array(Set(scopes)).sorted(),
                reason: "Required by the generated workflow",
                connected: false
            )
        }
    }

    private func normalizedTitle(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(160))
    }

    private func slug(_ value: String) -> String {
        let mapped = value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(String(mapped).split(separator: "-").joined(separator: "-").prefix(80))
    }

    private func slugKey(_ value: String) -> String {
        let key = slug(value)
        return key.isEmpty ? "value" : key
    }
}

enum PKFoundationAutomationError: LocalizedError {
    case invalidPrompt
    case unavailable(String)
    case noSupportedSteps
    case invalidGeneratedWorkflow(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            "Describe the automation in at least a few words."
        case .unavailable(let reason):
            "Apple Intelligence is unavailable: \(reason)"
        case .noSupportedSteps:
            "Apple Intelligence did not select any registered automation operations."
        case .invalidGeneratedWorkflow(let detail):
            "The generated workflow failed validation. \(detail)"
        }
    }
}
