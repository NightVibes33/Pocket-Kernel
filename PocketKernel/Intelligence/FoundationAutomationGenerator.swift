import Foundation
import FoundationModels

@Generable(description: "A key-value input for a registered automation operation")
struct PKFoundationGeneratedInput {
    @Guide(description: "The exact input key expected by the operation") var key: String
    @Guide(description: "A literal value or a binding such as {{ previous.output }}") var value: String
}

@Generable(description: "A configuration value for an automation trigger")
struct PKFoundationGeneratedTriggerConfiguration {
    @Guide(description: "A short configuration key such as cadence, time, event, or condition") var key: String
    @Guide(description: "The configuration value") var value: String
}

@Generable(description: "A deterministic trigger for an automation")
struct PKFoundationGeneratedTrigger {
    @Guide(description: "Exactly one of manual, schedule, webhook, accountEvent, webCondition, workflowCompleted, location") var kind: String
    @Guide(description: "Only configuration values needed by this trigger", .count(0...8)) var configuration: [PKFoundationGeneratedTriggerConfiguration]
}

@Generable(description: "One deterministic registered operation in an automation")
struct PKFoundationGeneratedStep {
    @Guide(description: "A stable short identifier unique within this workflow") var id: String
    @Guide(description: "A concise human-readable step title") var title: String
    @Guide(description: "The exact registered service identifier") var service: String
    @Guide(description: "The exact registered operation identifier for that service") var operation: String
    @Guide(description: "Typed operation inputs and bindings", .count(0...12)) var inputs: [PKFoundationGeneratedInput]
    @Guide(description: "An optional plain conditional expression, otherwise empty") var condition: String
    @Guide(description: "Retry attempts from zero through five") var retryCount: Int
}

@Generable(description: "A complete typed deterministic automation blueprint")
struct PKFoundationGeneratedAutomation {
    @Guide(description: "A concise automation name") var name: String
    @Guide(description: "One sentence explaining the automation outcome") var summary: String
    var trigger: PKFoundationGeneratedTrigger
    @Guide(description: "One to twenty ordered registered workflow steps", .count(1...20)) var steps: [PKFoundationGeneratedStep]
}

struct PKFoundationAutomationGenerator: Sendable {
    func generate(_ rawPrompt: String) async throws -> PKAutomation {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count >= 8 else { throw PKFoundationAutomationError.invalidPrompt }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw PKFoundationAutomationError.unavailable(String(describing: model.availability))
        }

        let operationList = PKOperationCatalog.operations
            .map { "\($0.service.rawValue).\($0.operation)" }
            .joined(separator: ", ")

        let instructions = """
        Convert the request into a small deterministic automation made only from registered operations.
        Registered operations: \(operationList).
        Trigger kinds: manual, schedule, webhook, accountEvent, webCondition, workflowCompleted, location.
        Use exact service and operation identifiers from the registered list.
        Put steps in execution order. Bind later steps to earlier output with {{ previous.output }} or {{ step-id.output }}.
        Use schedule configuration keys cadence and time with a 24-hour HH:mm value.
        Use location configuration key event with enter or exit.
        Never generate Swift, JavaScript, shell commands, SQL, credentials, tokens, private APIs, filesystem paths, or unregistered operations.
        Do not decide whether outbound actions need approval; PocketKernel derives that from its trusted operation catalog.
        Keep the workflow between one and twenty steps and include only steps required for the requested outcome.
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: prompt, generating: PKFoundationGeneratedAutomation.self)
        return try convert(response.content, originalPrompt: prompt)
    }

    private func convert(
        _ generated: PKFoundationGeneratedAutomation,
        originalPrompt: String
    ) throws -> PKAutomation {
        var usedIDs = Set<String>()
        let steps = generated.steps.compactMap { generatedStep -> PKWorkflowStep? in
            guard let service = PKServiceKind(rawValue: generatedStep.service),
                  let definition = PKOperationCatalog.definition(service: service, operation: generatedStep.operation)
            else { return nil }

            let baseID = slug(generatedStep.id.isEmpty ? generatedStep.operation : generatedStep.id)
            let id = uniqueID(baseID, used: &usedIDs)
            var inputs: [String: String] = [:]
            for input in generatedStep.inputs {
                let key = input.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                inputs[key] = input.value
            }
            let condition = nonempty(generatedStep.condition)
            let mutation = definition.mutation
            return PKWorkflowStep(
                id: id,
                title: nonempty(generatedStep.title) ?? definition.operation,
                service: service,
                operation: definition.operation,
                inputs: inputs,
                condition: condition,
                approval: mutation ? .externalMutation : .none,
                retryCount: min(max(generatedStep.retryCount, 0), 5),
                mutatesExternalState: mutation
            )
        }

        guard !steps.isEmpty else { throw PKFoundationAutomationError.noSupportedSteps }

        let triggerKind = PKTriggerKind(rawValue: generated.trigger.kind) ?? .manual
        var triggerConfiguration: [String: String] = [:]
        for item in generated.trigger.configuration {
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            triggerConfiguration[key] = item.value
        }

        let name = nonempty(generated.name) ?? inferredName(originalPrompt)
        let summary = nonempty(generated.summary) ?? originalPrompt
        let now = Date()
        let automation = PKAutomation(
            id: UUID(),
            name: name,
            summary: summary,
            state: .draft,
            trigger: PKTrigger(
                kind: triggerKind,
                configuration: triggerConfiguration,
                timeZoneIdentifier: TimeZone.current.identifier
            ),
            steps: steps,
            connections: makeConnections(for: steps),
            createdAt: now,
            updatedAt: now
        )

        if PKAutomationValidator().validate(automation).contains(where: { $0.severity == .error }) {
            throw PKFoundationAutomationError.invalidGeneratedWorkflow
        }
        return automation
    }

    private func makeConnections(for steps: [PKWorkflowStep]) -> [PKConnectionRequirement] {
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
                reason: "Required by one or more generated workflow steps",
                connected: false
            )
        }
    }

    private func uniqueID(_ base: String, used: inout Set<String>) -> String {
        var candidate = base
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }

    private func slug(_ value: String) -> String {
        let characters = value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let result = String(characters).split(separator: "-").joined(separator: "-")
        return result.isEmpty ? "step" : String(result.prefix(80))
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func inferredName(_ prompt: String) -> String {
        let words = prompt.split(separator: " ").prefix(6)
        let name = words.map { $0.capitalized }.joined(separator: " ")
        return name.isEmpty ? "New Automation" : name
    }
}

enum PKFoundationAutomationError: LocalizedError {
    case invalidPrompt
    case unavailable(String)
    case noSupportedSteps
    case invalidGeneratedWorkflow

    var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            "Describe the automation in at least a few words."
        case .unavailable(let reason):
            "Apple Intelligence is unavailable: \(reason)"
        case .noSupportedSteps:
            "Apple Intelligence did not select any registered workflow operations."
        case .invalidGeneratedWorkflow:
            "Apple Intelligence produced a workflow that did not pass PocketKernel validation."
        }
    }
}
