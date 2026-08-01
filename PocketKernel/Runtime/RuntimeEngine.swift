import Foundation

struct PermissionRequest: Sendable, Equatable {
    var appID: UUID
    var appName: String
    var capability: PocketCapability
    var reason: String
}

enum RuntimeExecutionError: LocalizedError {
    case actionMissing, conditionFalse, capabilityUndeclared, permissionRequired(PermissionRequest), permissionDenied, invalidParameter(String), unsupported(ActionKind)
    var errorDescription: String? {
        switch self { case .actionMissing: "Action does not exist."; case .conditionFalse: "Action condition was false."; case .capabilityUndeclared: "The app did not declare this capability."; case .permissionRequired(let request): "Permission required: \(request.capability.rawValue)."; case .permissionDenied: "The user denied this capability."; case .invalidParameter(let key): "Invalid action parameter: \(key)."; case .unsupported(let kind): "Action is unavailable: \(kind.rawValue)." }
    }
}

actor PermissionBroker {
    private let store: PocketStore
    init(store: PocketStore) { self.store = store }
    func authorize(_ capability: PocketCapability, manifest: MicroAppManifest, reason: String) async throws {
        guard manifest.capabilities.contains(capability) else { throw RuntimeExecutionError.capabilityUndeclared }
        let decision = try await store.permission(appID: manifest.id, capability: capability)
        switch decision {
        case .alwaysAllow: return
        case .allowOnce: try await store.setPermission(.notRequested, appID: manifest.id, capability: capability)
        case .denied: throw RuntimeExecutionError.permissionDenied
        case .notRequested: throw RuntimeExecutionError.permissionRequired(.init(appID: manifest.id, appName: manifest.name, capability: capability, reason: reason))
        }
    }
    func decide(_ decision: PermissionDecision, request: PermissionRequest) async throws { try await store.setPermission(decision, appID: request.appID, capability: request.capability) }
}

enum HostRequest: Sendable, Equatable { case dismiss, sheet(String), share(String), importFile, exportFile, selectPhotos, openURL(String) }
enum ActionResult: Sendable, Equatable { case none, value(PocketValue), navigated(String), alert(String), record(PocketRecord), host(HostRequest) }

actor ActionExecutor {
    let store: PocketStore
    let broker: PermissionBroker
    init(store: PocketStore) { self.store = store; broker = PermissionBroker(store: store) }

    func execute(_ actionID: String, manifest: MicroAppManifest, context: [String: PocketValue]) async throws -> ActionResult {
        guard let action = manifest.actions.first(where: { $0.id == actionID }) else { throw RuntimeExecutionError.actionMissing }
        if let condition = action.condition, try ExpressionEvaluator().evaluate(condition, context: context) != .bool(true) { throw RuntimeExecutionError.conditionFalse }
        if let capability = action.requiredCapability { try await broker.authorize(capability, manifest: manifest, reason: action.reason ?? "Complete \(action.title ?? action.kind.rawValue)") }
        let result = try await perform(action, manifest: manifest, context: context)
        try await store.log(appID: manifest.id, level: .info, category: "action", message: "Executed \(action.kind.rawValue)")
        return result
    }

    func decide(_ decision: PermissionDecision, request: PermissionRequest) async throws { try await broker.decide(decision, request: request) }

    private func perform(_ action: ActionSpec, manifest: MicroAppManifest, context: [String: PocketValue]) async throws -> ActionResult {
        switch action.kind {
        case .setValue:
            guard let key = action.target, let value = action.value else { throw RuntimeExecutionError.invalidParameter("target/value") }
            try await store.setRuntimeValue(value, appID: manifest.id, key: key); return .value(value)
        case .clearValue:
            guard let key = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            try await store.setRuntimeValue(nil, appID: manifest.id, key: key); return .none
        case .createRecord:
            guard let collection = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            let now = Date(); let record = PocketRecord(id: UUID(), collectionID: collection, values: action.parameters, createdAt: now, updatedAt: now)
            try await store.save(record: record, appID: manifest.id); return .record(record)
        case .updateRecord:
            guard let collection = action.target, case .string(let idString) = action.parameters["recordID"], let id = UUID(uuidString: idString) else { throw RuntimeExecutionError.invalidParameter("recordID") }
            let existing = try await store.records(appID: manifest.id, collectionID: collection).first { $0.id == id }
            guard var record = existing else { throw RuntimeExecutionError.invalidParameter("recordID") }
            for (key, value) in action.parameters where key != "recordID" { record.values[key] = value }
            record.updatedAt = Date(); try await store.save(record: record, appID: manifest.id); return .record(record)
        case .deleteRecord:
            guard let collection = action.target, case .string(let idString) = action.parameters["recordID"], let id = UUID(uuidString: idString) else { throw RuntimeExecutionError.invalidParameter("recordID") }
            try await store.deleteRecord(appID: manifest.id, collectionID: collection, recordID: id); return .none
        case .sortRecords, .filterRecords:
            guard let target = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            let records = try await store.records(appID: manifest.id, collectionID: target)
            return .value(.array(records.map { .object($0.values) }))
        case .navigate: guard let target = action.target else { throw RuntimeExecutionError.invalidParameter("target") }; return .navigated(target)
        case .dismiss: return .host(.dismiss)
        case .showSheet: return .host(.sheet(action.target ?? action.title ?? "Details"))
        case .selectRecord:
            guard case .string(let id) = action.parameters["recordID"] else { throw RuntimeExecutionError.invalidParameter("recordID") }
            return .value(.string(id))
        case .showAlert, .showConfirmation: return .alert(action.title ?? "Done")
        case .copyToClipboard:
            guard case .string(let text) = action.value else { throw RuntimeExecutionError.invalidParameter("value") }
            await ClipboardService().write(text); return .none
        case .scheduleLocalNotification:
            let body = action.parameters["body"].flatMap { if case .string(let value) = $0 { value } else { nil } } ?? action.title ?? manifest.name
            let seconds = action.parameters["seconds"].flatMap { if case .number(let value) = $0 { value } else { nil } } ?? 1
            try await NotificationService().schedule(title: manifest.name, body: body, after: seconds); return .none
        case .httpGet, .httpPostJSON:
            guard let target = action.target else { throw RuntimeExecutionError.invalidParameter("target") }
            return .value(try await NetworkService().request(urlString: target, method: action.kind == .httpGet ? "GET" : "POST", body: action.value, allowedDomains: manifest.allowedDomains))
        case .generateText, .summarizeText, .extractFields, .classifyText, .rewriteText:
            guard case .string(let prompt) = action.value else { throw RuntimeExecutionError.invalidParameter("value") }
            let blueprint = try await FoundationModelBlueprintGenerator().generateBlueprint(from: prompt, context: .init(localeIdentifier: Locale.current.identifier, requestedCapabilities: []))
            return .value(.string(blueprint.summary))
        case .share:
            guard case .string(let text) = action.value else { throw RuntimeExecutionError.invalidParameter("value") }; return .host(.share(text))
        case .importFile: return .host(.importFile)
        case .exportFile: return .host(.exportFile)
        case .selectPhotos: return .host(.selectPhotos)
        case .openURL:
            guard let target = action.target, let url = URL(string: target), url.scheme == "https" else { throw RuntimeExecutionError.invalidParameter("target") }
            return .host(.openURL(target))
        }
    }
}
