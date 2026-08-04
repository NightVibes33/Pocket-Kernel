import Foundation

enum AutomationLimits {
    static let steps = 100
    static let branches = 20
    static let variables = 100
    static let expressionCharacters = 4_000
    static let operationTimeoutSeconds = 30
    static let maximumAttempts = 5
    static let maximumResponseBytes = 1_048_576
}

enum AutomationState: String, Codable, Sendable, CaseIterable {
    case draft
    case testing
    case active
    case paused
    case failed
    case archived
}

enum TriggerKind: String, Codable, Sendable, CaseIterable {
    case manual
    case schedule
    case webhook
    case workflowCompleted
    case accountEvent
    case webCondition
    case location
    case approvalCompleted
}

struct AutomationTrigger: Codable, Sendable, Equatable {
    var kind: TriggerKind
    var configuration: [String: PocketValue]
    var timeZoneIdentifier: String?
    var deduplicationWindowSeconds: Int?
}

enum ServiceKind: String, Codable, Sendable, CaseIterable {
    case gmail
    case outlook
    case googleCalendar
    case googleDrive
    case googleDocs
    case googleSheets
    case googleSlides
    case slack
    case discord
    case reddit
    case linkedIn
    case rss
    case http
    case transform
    case control
    case intelligence
    case notifications
}

struct OperationReference: Codable, Sendable, Equatable, Hashable {
    var service: ServiceKind
    var operation: String
    var version: Int
}

struct ConnectionRequirement: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var service: ServiceKind
    var connectionID: UUID?
    var requiredScopes: Set<String>
    var reason: String
}

enum ApprovalRequirement: String, Codable, Sendable, CaseIterable {
    case never
    case firstRun
    case everyRun
    case whenChanged
    case alwaysForExternalMutation
}

struct ApprovalPolicy: Codable, Sendable, Equatable {
    var requirement: ApprovalRequirement
    var expiresAfterSeconds: Int?
    var allowedDestination: String?
    var maximumItems: Int?
}

struct RetryPolicy: Codable, Sendable, Equatable {
    var maximumAttempts: Int
    var initialDelaySeconds: Double
    var backoffMultiplier: Double
    var retryableStatusCodes: Set<Int>

    static let standard = RetryPolicy(
        maximumAttempts: 3,
        initialDelaySeconds: 1,
        backoffMultiplier: 2,
        retryableStatusCodes: [408, 425, 429, 500, 502, 503, 504]
    )
}

struct WorkflowStep: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var operation: OperationReference
    var connectionRequirementID: String?
    var inputs: [String: PocketValue]
    var inputBindings: [String: String]
    var outputBindings: [String: String]
    var condition: String?
    var retryPolicy: RetryPolicy
    var approvalPolicy: ApprovalPolicy
    var continueOnFailure: Bool
}

struct AutomationManifest: Codable, Sendable, Identifiable, Equatable {
    var formatVersion: Int
    var id: UUID
    var name: String
    var summary: String
    var state: AutomationState
    var trigger: AutomationTrigger
    var steps: [WorkflowStep]
    var connections: [ConnectionRequirement]
    var variables: [String: PocketValue]
    var createdAt: Date
    var updatedAt: Date
    var version: Int
}

enum RunState: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case waitingForApproval
    case succeeded
    case failed
    case cancelled
    case skippedDuplicate
}

struct StepRun: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var stepID: String
    var state: RunState
    var attempt: Int
    var startedAt: Date?
    var finishedAt: Date?
    var redactedInput: PocketValue?
    var redactedOutput: PocketValue?
    var errorCode: String?
    var errorMessage: String?
}

struct WorkflowRun: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var automationID: UUID
    var automationVersion: Int
    var triggerKind: TriggerKind
    var state: RunState
    var idempotencyKey: String
    var steps: [StepRun]
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
}

enum TaskSourceKind: String, Codable, Sendable, CaseIterable {
    case email
    case calendar
    case chat
    case document
    case user
    case automation
}

struct TaskSourceReference: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: TaskSourceKind
    var service: ServiceKind?
    var externalID: String?
    var title: String
}

enum ActionableTaskState: String, Codable, Sendable, CaseIterable {
    case proposed
    case accepted
    case inProgress
    case awaitingApproval
    case completed
    case dismissed
}

struct ActionableTask: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var summary: String
    var categoryID: UUID
    var state: ActionableTaskState
    var priority: Int
    var dueAt: Date?
    var sources: [TaskSourceReference]
    var proposedAutomationID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct TaskCategory: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var order: Int
    var isInferred: Bool
}

struct AutomationTemplate: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var summary: String
    var manifest: AutomationManifest
    var sourceVersion: Int
    var requiredServices: Set<ServiceKind>
    var createdAt: Date
    var updatedAt: Date
}
