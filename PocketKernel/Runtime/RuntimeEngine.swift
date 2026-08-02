import Foundation

struct PermissionRequest: Sendable, Equatable, Identifiable {
    var id: String { appID.uuidString + capability.rawValue }
    var appID: UUID
    var appName: String
    var capability: PocketCapability
    var reason: String
}

enum RuntimeExecutionError: LocalizedError {
    case actionMissing(String), conditionFalse, capabilityUndeclared(PocketCapability)
    case permissionRequired(PermissionRequest), permissionDenied(PocketCapability)
    case invalidParameter(String), unsupported(ActionKind), cancelled, chainLimit

    var errorDescription: String? {
        switch self {
        case .actionMissing(let id): "Action does not exist: \(id)."
        case .conditionFalse: "The action condition was false."
        case .capabilityUndeclared(let capability): "The app did not declare \(capability.rawValue)."
        case .permissionRequired(let request): "Permission required: \(request.capability.rawValue)."
        case .permissionDenied(let capability): "Permission denied: \(capability.rawValue)."
        case .invalidParameter(let key): "Invalid action parameter: \(key)."
        case .unsupported(let kind): "Action is unavailable: \(kind.rawValue)."
        case .cancelled: "The action was cancelled."
        case .chainLimit: "The action chain exceeded its safe limit."
        }
    }
}

actor PermissionBroker {
    private let store: PocketStore
    private let defaultDecision: PermissionDecision

    init(store: PocketStore, defaultDecision: PermissionDecision = .notRequested) {
        self.store = store
        self.defaultDecision = defaultDecision == .denied ? .denied : .notRequested
    }

    func authorize(_ capability: PocketCapability, manifest: MicroAppManifest, reason: String) async throws {
        guard manifest.capabilities.contains(capability) else { throw RuntimeExecutionError.capabilityUndeclared(capability) }
        switch try await store.permission(appID: manifest.id, capability: capability) {
        case .alwaysAllow:
            return
        case .allowOnce:
            try await store.setPermission(.notRequested, appID: manifest.id, capability: capability)
            return
        case .denied:
            throw RuntimeExecutionError.permissionDenied(capability)
        case .notRequested:
            if defaultDecision == .denied {
                try await store.setPermission(.denied, appID: manifest.id, capability: capability)
                throw RuntimeExecutionError.permissionDenied(capability)
            }
            throw RuntimeExecutionError.permissionRequired(
                .init(appID: manifest.id, appName: manifest.name, capability: capability, reason: reason)
            )
        }
    }

    func decide(_ decision: PermissionDecision, request: PermissionRequest) async throws {
        try await store.setPermission(decision, appID: request.appID, capability: request.capability)
    }
}

enum HostRequest: Sendable, Equatable {
    case dismiss
    case sheet(String)
    case share(String)
    case importFile
    case exportFile
    case selectPhotos(target: String, recognizeText: Bool)
    case openURL(String)
}

enum ActionResult: Sendable, Equatable {
    case none
    case value(PocketValue)
    case navigated(String)
    case alert(String)
    case record(PocketRecord)
    case records([PocketRecord])
    case selectedRecord(UUID)
    case host(HostRequest)
}

actor ActionExecutor {
    private enum UndoOperation: Sendable {
        case restoreRuntimeValue(appID: UUID, key: String, previous: PocketValue?)
        case deleteCreatedRecord(appID: UUID, collectionID: String, recordID: UUID)
        case restoreRecord(appID: UUID, record: PocketRecord)
    }

    private let store: PocketStore
    private let broker: PermissionBroker
    private let intelligence: any IntelligenceServicing
    private var undoStack: [UndoOperation] = []

    init(
        store: PocketStore,
        intelligence: any IntelligenceServicing = FoundationModelsService(),
        defaultPermission: PermissionDecision = .notRequested
    ) {
        self.store = store
        broker = PermissionBroker(store: store, defaultDecision: defaultPermission)
        self.intelligence = intelligence
    }

    func execute(_ actionID: String, manifest: MicroAppManifest, context: [String: PocketValue]) async throws -> ActionResult {
        do { try Task.checkCancellation() }
        catch { throw RuntimeExecutionError.cancelled }
        var visited = Set<String>()
        return try await execute(actionID, manifest: manifest, context: context, visited: &visited)
    }

    func decide(_ decision: PermissionDecision, request: PermissionRequest) async throws {
        try await broker.decide(decision, request: request)
    }

    func canUndo() -> Bool { !undoStack.isEmpty }

    func undoLast() async throws -> ActionResult {
        guard let operation = undoStack.popLast() else { return .none }
        switch operation {
        case .restoreRuntimeValue(let appID, let key, let previous):
            try await store.setRuntimeValue(previous, appID: appID, key: key)
            return .value(previous ?? .null)
        case .deleteCreatedRecord(let appID, let collectionID, let recordID):
            try await store.deleteRecord(appID: appID, collectionID: collectionID, recordID: recordID)
            return .none
        case .restoreRecord(let appID, let record):
            try await store.save(record: record, appID: appID)
            return .record(record)
        }
    }

    private func registerUndo(_ operation: UndoOperation) {
        undoStack.append(operation)
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
    }

    private func execute(
        _ actionID: String,
        manifest: MicroAppManifest,
        context: [String: PocketValue],
        visited: inout Set<String>
    ) async throws -> ActionResult {
        do { try Task.checkCancellation() }
        catch { throw RuntimeExecutionError.cancelled }
        guard visited.count < PocketLimits.actionChainDepth else { throw RuntimeExecutionError.chainLimit }
        guard visited.insert(actionID).inserted else { throw RuntimeExecutionError.chainLimit }
        guard let action = manifest.actions.first(where: { $0.id == actionID }) else {
            throw RuntimeExecutionError.actionMissing(actionID)
        }
        if let condition = action.condition,
           try ExpressionEvaluator().evaluate(condition, context: context) != .bool(true) {
            throw RuntimeExecutionError.conditionFalse
        }
        if let capability = action.requiredCapability {
            try await broker.authorize(
                capability,
                manifest: manifest,
                reason: action.reason ?? "Complete \(action.title ?? action.kind.rawValue)"
            )
        }

        let result = try await perform(action, manifest: manifest, context: context)
        let payload: PocketValue? = action.target.map { .object(["target": .string($0)]) }
        try await store.log(
            appID: manifest.id,
            level: .info,
            category: action.kind == .httpGet || action.kind == .httpPostJSON ? "network" : "action",
            message: "Executed \(action.kind.rawValue).",
            payload: payload
        )

        var nextContext = context
        switch result {
        case .value(let value): nextContext["lastResult"] = value
        case .record(let record): nextContext["record"] = .object(record.values)
        case .records(let records): nextContext["lastRecords"] = .array(records.map { .object($0.values) })
        case .selectedRecord(let id): nextContext["selectedRecordID"] = .string(id.uuidString)
        default: break
        }
        for nextID in action.nextActionIDs {
            _ = try await execute(nextID, manifest: manifest, context: nextContext, visited: &visited)
        }
        return result
    }

    private func perform(_ action: ActionSpec, manifest: MicroAppManifest, context: [String: PocketValue]) async throws -> ActionResult {
        switch action.kind {
        case .setValue:
            guard let key = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            let normalizedKey = normalizedStateKey(key)
            let previous = try await store.runtimeValue(appID: manifest.id, key: normalizedKey)
            let value = action.value ?? .null
            try await store.setRuntimeValue(value, appID: manifest.id, key: normalizedKey)
            registerUndo(.restoreRuntimeValue(appID: manifest.id, key: normalizedKey, previous: previous))
            return .value(value)

        case .clearValue:
            guard let key = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            let normalizedKey = normalizedStateKey(key)
            let previous = try await store.runtimeValue(appID: manifest.id, key: normalizedKey)
            try await store.setRuntimeValue(nil, appID: manifest.id, key: normalizedKey)
            registerUndo(.restoreRuntimeValue(appID: manifest.id, key: normalizedKey, previous: previous))
            return .none

        case .createRecord:
            guard let collectionID = action.target,
                  let collection = manifest.collections.first(where: { $0.id == collectionID })
            else { throw RuntimeExecutionError.invalidParameter("target") }
            let form = object(context["form"]) ?? [:]
            var values = action.parameters
            for field in collection.fields {
                values[field.id] = form[field.id] ?? values[field.id] ?? field.defaultValue
            }
            let now = Date()
            let record = PocketRecord(
                id: UUID(),
                collectionID: collectionID,
                values: values,
                createdAt: now,
                updatedAt: now
            )
            try await store.save(record: record, appID: manifest.id)
            registerUndo(.deleteCreatedRecord(appID: manifest.id, collectionID: collectionID, recordID: record.id))
            return .record(record)

        case .updateRecord:
            guard let collectionID = action.target,
                  let id = recordID(action: action, context: context)
            else { throw RuntimeExecutionError.invalidParameter("recordID") }
            guard var record = try await store.records(appID: manifest.id, collectionID: collectionID)
                .first(where: { $0.id == id })
            else { throw RuntimeExecutionError.invalidParameter("recordID") }
            let previous = record
            let form = object(context["form"]) ?? [:]
            for (key, value) in action.parameters where key != "recordID" { record.values[key] = value }
            for (key, value) in form { record.values[key] = value }
            record.updatedAt = Date()
            try await store.save(record: record, appID: manifest.id)
            registerUndo(.restoreRecord(appID: manifest.id, record: previous))
            return .record(record)

        case .deleteRecord:
            guard let collectionID = action.target,
                  let id = recordID(action: action, context: context)
            else { throw RuntimeExecutionError.invalidParameter("recordID") }
            guard let previous = try await store.records(appID: manifest.id, collectionID: collectionID)
                .first(where: { $0.id == id })
            else { throw RuntimeExecutionError.invalidParameter("recordID") }
            try await store.deleteRecord(appID: manifest.id, collectionID: collectionID, recordID: id)
            registerUndo(.restoreRecord(appID: manifest.id, record: previous))
            return .none

        case .sortRecords:
            guard let collectionID = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            let field = string(action.parameters["field"]) ?? ""
            let descending = bool(action.parameters["descending"]) ?? false
            let records = try await store.records(appID: manifest.id, collectionID: collectionID).sorted { lhs, rhs in
                let comparison = compare(lhs.values[field] ?? .null, rhs.values[field] ?? .null)
                return descending ? comparison > 0 : comparison < 0
            }
            return .records(records)

        case .filterRecords:
            guard let collectionID = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            let expression = string(action.parameters["expression"]) ?? action.condition ?? "true"
            let state = object(context["state"]) ?? [:]
            let records = try await store.records(appID: manifest.id, collectionID: collectionID).filter { record in
                let evaluationContext: [String: PocketValue] = [
                    "record": .object(record.values),
                    "state": .object(state),
                    "environment": context["environment"] ?? .object([:])
                ]
                return (try? ExpressionEvaluator().evaluate(expression, context: evaluationContext)) == .bool(true)
            }
            return .records(records)

        case .navigate:
            guard let target = action.target, manifest.screens.contains(where: { $0.id == target }) else {
                throw RuntimeExecutionError.invalidParameter("target")
            }
            return .navigated(target)
        case .dismiss:
            return .host(.dismiss)
        case .showSheet:
            return .host(.sheet(action.target ?? action.title ?? "Details"))
        case .showAlert, .showConfirmation:
            return .alert(action.title ?? string(action.value) ?? "Done")
        case .selectRecord:
            guard let id = recordID(action: action, context: context) else {
                throw RuntimeExecutionError.invalidParameter("recordID")
            }
            return .selectedRecord(id)

        case .copyToClipboard:
            let text = string(action.value) ?? string(context["value"]) ?? ""
            await ClipboardService().write(text)
            return .none
        case .share:
            return .host(.share(string(action.value) ?? string(context["value"]) ?? ""))
        case .importFile:
            return .host(.importFile)
        case .exportFile:
            return .host(.exportFile)
        case .selectPhotos:
            return .host(.selectPhotos(
                target: normalizedStateKey(action.target ?? "selectedPhoto"),
                recognizeText: bool(action.parameters["recognizeText"]) ?? false
            ))
        case .scheduleLocalNotification:
            let body = string(action.parameters["body"]) ?? action.title ?? manifest.name
            let seconds = number(action.parameters["seconds"]) ?? 1
            try await NotificationService().schedule(title: manifest.name, body: body, after: seconds)
            return .none
        case .openURL:
            guard let target = action.target,
                  let url = URL(string: target),
                  url.scheme?.lowercased() == "https"
            else { throw RuntimeExecutionError.invalidParameter("target") }
            return .host(.openURL(target))

        case .httpGet, .httpPostJSON:
            guard let target = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            let result = try await NetworkService().request(
                urlString: target,
                method: action.kind == .httpGet ? "GET" : "POST",
                body: action.value,
                allowedDomains: manifest.allowedDomains
            )
            return .value(result)

        case .generateText, .summarizeText, .extractFields, .classifyText, .rewriteText:
            let text = string(action.value) ?? string(context["value"]) ?? ""
            let instruction = string(action.parameters["instruction"])
            let operation: IntelligenceOperation
            switch action.kind {
            case .generateText: operation = .generate
            case .summarizeText: operation = .summarize
            case .extractFields: operation = .extract
            case .classifyText: operation = .classify
            case .rewriteText: operation = .rewrite
            default: throw RuntimeExecutionError.unsupported(action.kind)
            }
            return .value(try await intelligence.process(operation, text: text, instruction: instruction))
        }
    }

    private func normalizedStateKey(_ key: String) -> String {
        key.hasPrefix("state.") ? String(key.dropFirst("state.".count)) : key
    }

    private func recordID(action: ActionSpec, context: [String: PocketValue]) -> UUID? {
        let raw = string(action.parameters["recordID"])
            ?? string(context["selectedRecordID"])
            ?? string(object(context["state"])?["selectedRecordID"])
        return raw.flatMap(UUID.init(uuidString:))
    }

    private func object(_ value: PocketValue?) -> [String: PocketValue]? {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private func string(_ value: PocketValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }

    private func number(_ value: PocketValue?) -> Double? {
        guard case .number(let number) = value else { return nil }
        return number
    }

    private func bool(_ value: PocketValue?) -> Bool? {
        guard case .bool(let bool) = value else { return nil }
        return bool
    }

    private func compare(_ lhs: PocketValue, _ rhs: PocketValue) -> Int {
        switch (lhs, rhs) {
        case (.number(let left), .number(let right)): return left == right ? 0 : left < right ? -1 : 1
        case (.date(let left), .date(let right)): return left == right ? 0 : left < right ? -1 : 1
        default:
            let left = lhs.displayString.localizedLowercase
            let right = rhs.displayString.localizedLowercase
            return left == right ? 0 : left < right ? -1 : 1
        }
    }
}
