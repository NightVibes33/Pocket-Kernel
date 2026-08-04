import Combine
import Foundation

// MARK: - Typed automation domain

enum PKAutomationState: String, Codable, CaseIterable, Sendable {
    case draft, active, paused, failed
}

enum PKTriggerKind: String, Codable, CaseIterable, Sendable {
    case manual, schedule, webhook, accountEvent, webCondition, workflowCompleted, location
}

enum PKServiceKind: String, Codable, CaseIterable, Sendable {
    case gmail, outlook, googleCalendar, googleDrive, googleDocs, googleSheets, googleSlides
    case slack, discord, reddit, linkedIn, rss, http, transform, control, intelligence, notifications

    var title: String {
        switch self {
        case .gmail: "Gmail"
        case .outlook: "Outlook"
        case .googleCalendar: "Google Calendar"
        case .googleDrive: "Google Drive"
        case .googleDocs: "Google Docs"
        case .googleSheets: "Google Sheets"
        case .googleSlides: "Google Slides"
        case .slack: "Slack"
        case .discord: "Discord"
        case .reddit: "Reddit"
        case .linkedIn: "LinkedIn"
        case .rss: "RSS"
        case .http: "HTTP"
        case .transform: "Transform"
        case .control: "Control"
        case .intelligence: "Apple Intelligence"
        case .notifications: "Notifications"
        }
    }

    var symbol: String {
        switch self {
        case .gmail, .outlook: "envelope.fill"
        case .googleCalendar: "calendar"
        case .googleDrive, .googleDocs, .googleSheets, .googleSlides: "doc.fill"
        case .slack, .discord: "bubble.left.and.bubble.right.fill"
        case .reddit, .linkedIn: "person.2.fill"
        case .rss: "dot.radiowaves.left.and.right"
        case .http: "network"
        case .transform: "arrow.triangle.branch"
        case .control: "point.3.connected.trianglepath.dotted"
        case .intelligence: "apple.intelligence"
        case .notifications: "bell.fill"
        }
    }
}

enum PKApprovalRule: String, Codable, CaseIterable, Sendable {
    case none, firstRun, everyRun, externalMutation
}

struct PKTrigger: Codable, Equatable, Sendable {
    var kind: PKTriggerKind
    var configuration: [String: String]
    var timeZoneIdentifier: String
}

struct PKConnectionRequirement: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var service: PKServiceKind
    var scopes: [String]
    var reason: String
    var connected: Bool
}

struct PKWorkflowStep: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var service: PKServiceKind
    var operation: String
    var inputs: [String: String]
    var condition: String?
    var approval: PKApprovalRule
    var retryCount: Int
    var mutatesExternalState: Bool
}

struct PKAutomation: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var state: PKAutomationState
    var trigger: PKTrigger
    var steps: [PKWorkflowStep]
    var connections: [PKConnectionRequirement]
    var createdAt: Date
    var updatedAt: Date
}

enum PKRunState: String, Codable, Sendable {
    case running, waitingForApproval, succeeded, failed
}

struct PKRunEvent: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var automationID: UUID
    var automationName: String
    var state: PKRunState
    var message: String
    var createdAt: Date
}

struct PKValidationIssue: Identifiable, Equatable, Sendable {
    enum Severity: Sendable { case warning, error }
    var id: String { code + message }
    var code: String
    var message: String
    var severity: Severity
}

// MARK: - Catalog

struct PKOperationDefinition: Sendable {
    var service: PKServiceKind
    var operation: String
    var scopes: [String]
    var mutation: Bool
}

enum PKOperationCatalog {
    static let operations: [PKOperationDefinition] = [
        .init(service: .gmail, operation: "searchMessages", scopes: ["gmail.readonly"], mutation: false),
        .init(service: .gmail, operation: "draftReply", scopes: ["gmail.compose"], mutation: true),
        .init(service: .gmail, operation: "sendMessage", scopes: ["gmail.send"], mutation: true),
        .init(service: .outlook, operation: "searchMessages", scopes: ["Mail.Read"], mutation: false),
        .init(service: .outlook, operation: "draftReply", scopes: ["Mail.ReadWrite"], mutation: true),
        .init(service: .googleCalendar, operation: "findAvailability", scopes: ["calendar.readonly"], mutation: false),
        .init(service: .googleCalendar, operation: "createEvent", scopes: ["calendar.events"], mutation: true),
        .init(service: .googleDrive, operation: "findFiles", scopes: ["drive.readonly"], mutation: false),
        .init(service: .googleDocs, operation: "createDocument", scopes: ["documents"], mutation: true),
        .init(service: .googleSheets, operation: "appendRows", scopes: ["spreadsheets"], mutation: true),
        .init(service: .slack, operation: "searchMessages", scopes: ["search:read"], mutation: false),
        .init(service: .slack, operation: "postMessage", scopes: ["chat:write"], mutation: true),
        .init(service: .discord, operation: "postMessage", scopes: ["webhook.incoming"], mutation: true),
        .init(service: .reddit, operation: "submitPost", scopes: ["submit"], mutation: true),
        .init(service: .linkedIn, operation: "createPost", scopes: ["w_member_social"], mutation: true),
        .init(service: .rss, operation: "readFeed", scopes: [], mutation: false),
        .init(service: .http, operation: "getJSON", scopes: [], mutation: false),
        .init(service: .http, operation: "postJSON", scopes: [], mutation: true),
        .init(service: .transform, operation: "filter", scopes: [], mutation: false),
        .init(service: .transform, operation: "formatDigest", scopes: [], mutation: false),
        .init(service: .intelligence, operation: "summarize", scopes: [], mutation: false),
        .init(service: .intelligence, operation: "classify", scopes: [], mutation: false),
        .init(service: .notifications, operation: "sendPush", scopes: [], mutation: true)
    ]

    static func definition(service: PKServiceKind, operation: String) -> PKOperationDefinition? {
        operations.first { $0.service == service && $0.operation == operation }
    }
}

// MARK: - Prompt compiler

struct PKAutomationCompiler: Sendable {
    func compile(_ rawPrompt: String) throws -> PKAutomation {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count >= 8 else { throw PKAutomationError.invalidPrompt }
        let lowered = prompt.lowercased()
        let trigger = inferTrigger(lowered)
        var steps: [PKWorkflowStep] = []

        if lowered.contains("gmail") || lowered.contains("email") || lowered.contains("inbox") {
            steps.append(step("read-email", "Find matching email", .gmail, "searchMessages", ["query": inferEmailQuery(lowered)]))
        } else if lowered.contains("outlook") {
            steps.append(step("read-outlook", "Find matching Outlook email", .outlook, "searchMessages", ["query": inferEmailQuery(lowered)]))
        }

        if lowered.contains("calendar") || lowered.contains("meeting") || lowered.contains("availability") {
            if lowered.contains("create") || lowered.contains("schedule") || lowered.contains("book") {
                steps.append(step("calendar-create", "Prepare calendar event", .googleCalendar, "createEvent", ["request": prompt], mutation: true))
            } else {
                steps.append(step("calendar-read", "Check calendar availability", .googleCalendar, "findAvailability", [:]))
            }
        }

        if lowered.contains("summar") || lowered.contains("digest") || lowered.contains("brief") {
            steps.append(step("summarize", "Summarize the collected context", .intelligence, "summarize", ["source": "{{ previous.output }}"]))
        }
        if lowered.contains("urgent") || lowered.contains("classif") || lowered.contains("categor") || lowered.contains("triage") {
            steps.append(step("classify", "Classify and prioritize", .intelligence, "classify", ["source": "{{ previous.output }}"]))
        }
        if lowered.contains("sheet") || lowered.contains("spreadsheet") {
            steps.append(step("append-sheet", "Append results to Google Sheets", .googleSheets, "appendRows", ["rows": "{{ previous.output }}"], mutation: true))
        }
        if lowered.contains("document") || lowered.contains("google doc") || lowered.contains("prepare a doc") {
            steps.append(step("create-document", "Prepare a Google document", .googleDocs, "createDocument", ["content": "{{ previous.output }}"], mutation: true))
        }
        if lowered.contains("slack") {
            steps.append(step("post-slack", "Post to Slack", .slack, "postMessage", ["text": "{{ previous.output }}"], mutation: true))
        }
        if lowered.contains("discord") {
            steps.append(step("post-discord", "Post to Discord", .discord, "postMessage", ["text": "{{ previous.output }}"], mutation: true))
        }
        if lowered.contains("reddit") {
            steps.append(step("post-reddit", "Prepare Reddit post", .reddit, "submitPost", ["body": "{{ previous.output }}"], mutation: true))
        }
        if lowered.contains("linkedin") {
            steps.append(step("post-linkedin", "Prepare LinkedIn post", .linkedIn, "createPost", ["body": "{{ previous.output }}"], mutation: true))
        }
        if lowered.contains("rss") || lowered.contains("feed") {
            steps.insert(step("read-rss", "Read RSS feed", .rss, "readFeed", ["url": inferURL(prompt)]), at: 0)
        }
        if lowered.contains("http") || lowered.contains("api") || lowered.contains("endpoint") || lowered.contains("price") || lowered.contains("weather") {
            let mutation = lowered.contains("post ") || lowered.contains("send to api")
            steps.insert(step("request-api", mutation ? "Send API request" : "Read API data", .http, mutation ? "postJSON" : "getJSON", ["url": inferURL(prompt)], mutation: mutation), at: 0)
        }
        if lowered.contains("notify") || lowered.contains("alert me") || lowered.contains("remind me") {
            steps.append(step("notify", "Send a notification", .notifications, "sendPush", ["message": "{{ previous.output }}"], mutation: true))
        }
        if lowered.contains("reply") || lowered.contains("respond") {
            steps.append(step("draft-reply", "Draft an email reply for approval", .gmail, "draftReply", ["thread": "{{ read-email.output }}", "instructions": prompt], mutation: true))
        }

        if steps.isEmpty {
            steps = [
                step("fetch", "Fetch data from the requested service", .http, "getJSON", ["url": inferURL(prompt)]),
                step("transform", "Transform the result", .transform, "formatDigest", ["source": "{{ fetch.output }}"])
            ]
        }

        let connections = makeConnections(steps)
        let now = Date()
        return PKAutomation(
            id: UUID(),
            name: inferName(prompt),
            summary: prompt,
            state: .draft,
            trigger: trigger,
            steps: steps,
            connections: connections,
            createdAt: now,
            updatedAt: now
        )
    }

    private func step(
        _ id: String,
        _ title: String,
        _ service: PKServiceKind,
        _ operation: String,
        _ inputs: [String: String],
        mutation: Bool = false
    ) -> PKWorkflowStep {
        PKWorkflowStep(
            id: id,
            title: title,
            service: service,
            operation: operation,
            inputs: inputs,
            condition: nil,
            approval: mutation ? .externalMutation : .none,
            retryCount: 3,
            mutatesExternalState: mutation
        )
    }

    private func inferTrigger(_ prompt: String) -> PKTrigger {
        let zone = TimeZone.current.identifier
        if prompt.contains("webhook") { return .init(kind: .webhook, configuration: [:], timeZoneIdentifier: zone) }
        if prompt.contains("when i arrive") || prompt.contains("when i leave") || prompt.contains("location") {
            return .init(kind: .location, configuration: ["event": prompt.contains("leave") ? "exit" : "enter"], timeZoneIdentifier: zone)
        }
        if prompt.contains("when another automation") || prompt.contains("after workflow") {
            return .init(kind: .workflowCompleted, configuration: [:], timeZoneIdentifier: zone)
        }
        if prompt.contains("when i get") || prompt.contains("when an email") || prompt.contains("whenever") {
            return .init(kind: .accountEvent, configuration: [:], timeZoneIdentifier: zone)
        }
        if prompt.contains("price") || prompt.contains("drops below") || prompt.contains("rises above") {
            return .init(kind: .webCondition, configuration: ["condition": prompt], timeZoneIdentifier: zone)
        }
        if prompt.contains("daily") || prompt.contains("every day") || prompt.contains("weekday") || prompt.contains("weekly") || prompt.contains("every morning") {
            let cadence = prompt.contains("weekday") ? "weekdays" : prompt.contains("weekly") ? "weekly" : "daily"
            return .init(kind: .schedule, configuration: ["cadence": cadence, "time": inferTime(prompt)], timeZoneIdentifier: zone)
        }
        return .init(kind: .manual, configuration: [:], timeZoneIdentifier: zone)
    }

    private func inferTime(_ prompt: String) -> String {
        let pattern = #"\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let hourRange = Range(match.range(at: 1), in: prompt)
        else { return "08:00" }
        var hour = Int(prompt[hourRange]) ?? 8
        let minute = match.range(at: 2).location == NSNotFound ? 0 : Range(match.range(at: 2), in: prompt).flatMap { Int(prompt[$0]) } ?? 0
        let suffix = Range(match.range(at: 3), in: prompt).map { String(prompt[$0]) } ?? "am"
        if suffix == "pm" && hour < 12 { hour += 12 }
        if suffix == "am" && hour == 12 { hour = 0 }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func inferEmailQuery(_ prompt: String) -> String {
        var terms: [String] = []
        if prompt.contains("unread") { terms.append("is:unread") }
        if prompt.contains("today") { terms.append("newer_than:1d") }
        if prompt.contains("customer") { terms.append("customer") }
        if prompt.contains("urgent") { terms.append("urgent") }
        return terms.isEmpty ? "newer_than:1d" : terms.joined(separator: " ")
    }

    private func inferURL(_ prompt: String) -> String {
        let parts = prompt.split(separator: " ")
        return parts.first(where: { $0.hasPrefix("https://") }).map(String.init) ?? "https://configure-in-editor.invalid"
    }

    private func inferName(_ prompt: String) -> String {
        let cleaned = prompt
            .replacingOccurrences(of: "Create an automation that ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Create an automation to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Every weekday ", with: "", options: .caseInsensitive)
        let words = cleaned.split(separator: " ").prefix(6)
        let result = words.map { $0.capitalized }.joined(separator: " ")
        return result.isEmpty ? "New Automation" : result
    }

    private func makeConnections(_ steps: [PKWorkflowStep]) -> [PKConnectionRequirement] {
        let services = Set(steps.map(\.service)).filter { ![.transform, .control, .intelligence, .notifications, .http, .rss].contains($0) }
        return services.sorted { $0.rawValue < $1.rawValue }.map { service in
            let scopes = steps
                .filter { $0.service == service }
                .compactMap { PKOperationCatalog.definition(service: service, operation: $0.operation) }
                .flatMap(\.scopes)
            return PKConnectionRequirement(
                id: service.rawValue,
                service: service,
                scopes: Array(Set(scopes)).sorted(),
                reason: "Required by one or more workflow steps",
                connected: false
            )
        }
    }
}

// MARK: - Validation and deterministic execution

struct PKAutomationValidator: Sendable {
    func validate(_ automation: PKAutomation) -> [PKValidationIssue] {
        var issues: [PKValidationIssue] = []
        if automation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(code: "name.empty", message: "Automation name is required.", severity: .error))
        }
        if automation.steps.isEmpty {
            issues.append(.init(code: "steps.empty", message: "At least one workflow step is required.", severity: .error))
        }
        if automation.steps.count > 100 {
            issues.append(.init(code: "steps.limit", message: "A workflow can contain at most 100 steps.", severity: .error))
        }
        let ids = automation.steps.map(\.id)
        if Set(ids).count != ids.count {
            issues.append(.init(code: "steps.duplicate", message: "Workflow step identifiers must be unique.", severity: .error))
        }
        for step in automation.steps {
            guard let definition = PKOperationCatalog.definition(service: step.service, operation: step.operation) else {
                issues.append(.init(code: "operation.unsupported", message: "Unsupported operation: \(step.service.rawValue).\(step.operation).", severity: .error))
                continue
            }
            if definition.mutation && step.approval == .none {
                issues.append(.init(code: "approval.required", message: "\(step.title) changes an external service and must require approval.", severity: .error))
            }
            if step.retryCount < 0 || step.retryCount > 5 {
                issues.append(.init(code: "retry.invalid", message: "\(step.title) has an invalid retry count.", severity: .error))
            }
            for value in step.inputs.values where value.contains("configure-in-editor.invalid") {
                issues.append(.init(code: "input.configure", message: "\(step.title) needs a real endpoint before it can be enabled.", severity: .warning))
            }
        }
        return issues
    }
}

actor PKDeterministicExecutor {
    func execute(_ automation: PKAutomation, approved: Bool) async -> PKRunEvent {
        let validator = PKAutomationValidator()
        if validator.validate(automation).contains(where: { $0.severity == .error }) {
            return event(automation, .failed, "Validation failed before execution.")
        }
        if automation.connections.contains(where: { !$0.connected }) {
            return event(automation, .failed, "Connect every required service before running this automation.")
        }
        if automation.steps.contains(where: { $0.mutatesExternalState && $0.approval != .none }) && !approved {
            return event(automation, .waitingForApproval, "Review and approve the outbound actions before execution.")
        }
        for step in automation.steps {
            try? await Task.sleep(for: .milliseconds(80))
            guard PKOperationCatalog.definition(service: step.service, operation: step.operation) != nil else {
                return event(automation, .failed, "The operation catalog no longer contains \(step.operation).")
            }
        }
        return event(automation, .succeeded, "Executed \(automation.steps.count) deterministic steps.")
    }

    private func event(_ automation: PKAutomation, _ state: PKRunState, _ message: String) -> PKRunEvent {
        .init(id: UUID(), automationID: automation.id, automationName: automation.name, state: state, message: message, createdAt: Date())
    }
}

enum PKAutomationError: LocalizedError {
    case invalidPrompt

    var errorDescription: String? {
        switch self {
        case .invalidPrompt: "Describe the automation in at least a few words."
        }
    }
}

// MARK: - App workspace

@MainActor
final class PKAutomationWorkspace: ObservableObject {
    @Published var automations: [PKAutomation] = []
    @Published var draft: PKAutomation?
    @Published var validationIssues: [PKValidationIssue] = []
    @Published var runs: [PKRunEvent] = []
    @Published var prompt = ""
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let compiler = PKAutomationCompiler()
    private let foundationGenerator = PKFoundationAutomationGenerator()
    private let validator = PKAutomationValidator()
    private let executor = PKDeterministicExecutor()
    private let storageURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appending(path: "PocketKernelAutomation", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appending(path: "workspace.json")
        if ProcessInfo.processInfo.arguments.contains("-PKResetDatabase") {
            try? FileManager.default.removeItem(at: storageURL)
        }
        load()
    }

    func compilePrompt() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result: PKAutomation
            if modelMode == "mock" || modelMode == "local" {
                result = try compiler.compile(prompt)
            } else {
                do {
                    result = try await foundationGenerator.generate(prompt)
                } catch {
                    result = try compiler.compile(prompt)
                }
            }
            draft = result
            validationIssues = validator.validate(result)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var modelMode: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PKModelMode"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1].lowercased()
    }

    func saveDraft() {
        guard var draft else { return }
        validationIssues = validator.validate(draft)
        guard !validationIssues.contains(where: { $0.severity == .error }) else { return }
        draft.state = .paused
        draft.updatedAt = Date()
        automations.removeAll { $0.id == draft.id }
        automations.insert(draft, at: 0)
        self.draft = nil
        persist()
    }

    func toggle(_ automation: PKAutomation) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[index].state = automation.state == .active ? .paused : .active
        automations[index].updatedAt = Date()
        persist()
    }

    func setConnected(_ service: PKServiceKind, connected: Bool) {
        for automationIndex in automations.indices {
            for connectionIndex in automations[automationIndex].connections.indices where automations[automationIndex].connections[connectionIndex].service == service {
                automations[automationIndex].connections[connectionIndex].connected = connected
            }
        }
        if draft != nil {
            for index in draft!.connections.indices where draft!.connections[index].service == service {
                draft!.connections[index].connected = connected
            }
        }
        persist()
    }

    func run(_ automation: PKAutomation, approved: Bool = false) async {
        isWorking = true
        let result = await executor.execute(automation, approved: approved)
        runs.insert(result, at: 0)
        isWorking = false
        persist()
    }

    func delete(_ automation: PKAutomation) {
        automations.removeAll { $0.id == automation.id }
        persist()
    }

    var requiredServices: [PKServiceKind] {
        Array(Set(automations.flatMap(\.connections).map(\.service) + (draft?.connections.map(\.service) ?? [])))
            .sorted { $0.rawValue < $1.rawValue }
    }

    private struct Snapshot: Codable {
        var automations: [PKAutomation]
        var runs: [PKRunEvent]
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        automations = snapshot.automations
        runs = snapshot.runs
    }

    private func persist() {
        let snapshot = Snapshot(automations: automations, runs: runs)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
