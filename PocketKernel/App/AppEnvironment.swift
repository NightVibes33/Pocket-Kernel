import Foundation
import FoundationModels
import Observation

enum ModelAvailabilityState: Sendable, Equatable {
    case available
    case unavailable(String)
    case mock
    case templates

    var title: String {
        switch self {
        case .available: "Apple Intelligence Ready"
        case .unavailable: "Apple Intelligence Unavailable"
        case .mock: "Deterministic Test Model"
        case .templates: "Local Blueprint Compiler"
        }
    }

    var detail: String {
        switch self {
        case .available: "Blueprints are generated privately on this device."
        case .unavailable(let reason): "\(reason) PocketKernel can still compile an editable app locally from your prompt."
        case .mock: "CI uses deterministic generated blueprints without executing Apple Intelligence."
        case .templates: "Prompt-driven local generation is active without a language model."
        }
    }
}

@MainActor @Observable final class AppEnvironment {
    private(set) var store: PocketStore?
    private(set) var lifecycle: AppLifecycleController
    private(set) var installed: [InstalledAppInfo] = []
    private(set) var builtInTemplates: [BundledTemplate] = []
    private(set) var activity: [ActivityEvent] = []
    private(set) var storageBytes: Int64 = 0
    private(set) var modelState: ModelAvailabilityState
    private(set) var startupError: String?

    var pendingOpenApp: MicroAppManifest?
    var draft: MicroAppManifest?
    var previousDraft: MicroAppManifest?
    var validationIssues: [ValidationIssue] = []
    var generationError: String?
    var isGenerating = false
    var lastExportedPackage: Data?

    private let generator: any BlueprintGenerating
    private let fallbackGenerator: any BlueprintGenerating = PromptBlueprintGenerator()
    let intelligence: any IntelligenceServicing
    private let launchArguments: [String]
    private var didApplyLaunchReset = false
    private var didApplyLaunchImport = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("-PKResetOnboarding") {
            UserDefaults.standard.set(false, forKey: "PKOnboardingComplete")
        }

        let storageLayout = AppEnvironment.makeLayout()
        let initialLifecycle = AppLifecycleController(layout: storageLayout, arguments: arguments)

        var initialStore: PocketStore?
        var initialStartupError: String?
        do {
            initialStore = try PocketStore(inMemory: arguments.contains("-PKInMemoryStore"))
        } catch {
            initialStore = nil
            initialStartupError = error.localizedDescription
        }

        var initialTemplates: [BundledTemplate] = []
        do {
            initialTemplates = try TemplatePackageLibrary().load()
        } catch where initialStartupError == nil {
            initialStartupError = "Built-in Pocket Apps could not be loaded: \(error.localizedDescription)"
        } catch {}

        let initialGenerator: any BlueprintGenerating
        let initialIntelligence: any IntelligenceServicing
        let initialModelState: ModelAvailabilityState
        switch AppEnvironment.argumentValue("-PKModelMode", arguments: arguments) {
        case "mock":
            initialGenerator = MockBlueprintGenerator()
            initialIntelligence = MockIntelligenceService()
            initialModelState = .mock
        case "template":
            initialGenerator = PromptBlueprintGenerator()
            initialIntelligence = MockIntelligenceService()
            initialModelState = .templates
        default:
            initialGenerator = FoundationModelBlueprintGenerator()
            initialIntelligence = FoundationModelsService()
            let availability = SystemLanguageModel.default.availability
            if case .available = availability {
                initialModelState = .available
            } else {
                initialModelState = .unavailable(String(describing: availability))
            }
        }

        launchArguments = arguments
        lifecycle = initialLifecycle
        store = initialStore
        builtInTemplates = initialTemplates
        startupError = initialStartupError
        generator = initialGenerator
        intelligence = initialIntelligence
        modelState = initialModelState
    }

    func load() async {
        guard let store else { return }
        do {
            if builtInTemplates.isEmpty { builtInTemplates = try TemplatePackageLibrary().load() }
            if launchArguments.contains("-PKResetDatabase"), !didApplyLaunchReset {
                try await store.reset()
                Self.clearAuxiliaryFiles()
                didApplyLaunchReset = true
            }
            if launchArguments.contains("-PKReimportLastExport"), !didApplyLaunchImport {
                let data = try Data(contentsOf: Self.lastExportURL())
                let package = try PackageCodec().decode(data)
                try await store.install(package)
                try await store.log(appID: package.manifest.id, level: .info, category: "import", message: "Reimported the last exported Pocket App package.")
                lastExportedPackage = data
                didApplyLaunchImport = true
            }
            installed = try await store.installedApps()
            activity = try await store.activity()
            storageBytes = try await store.storageBytes()
            syncIntentEntities()
            if let requested = UserDefaults.standard.string(forKey: "PKRequestedAppID"),
               let id = UUID(uuidString: requested),
               let app = installed.first(where: { $0.id == id && !$0.disabled }) {
                pendingOpenApp = app.manifest
                UserDefaults.standard.removeObject(forKey: "PKRequestedAppID")
            }
        } catch {
            startupError = error.localizedDescription
        }
    }

    func generate(_ prompt: String, capabilities: Set<PocketCapability>) async {
        guard let store else { generationError = startupError ?? "Database is unavailable."; return }
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { generationError = "Describe the app you want to create."; return }
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }

        do {
            try await store.log(appID: nil, level: .info, category: "generation", message: "Started blueprint generation for: \(normalized.prefix(180))")
            let context = BuilderContext(localeIdentifier: Locale.current.identifier, requestedCapabilities: capabilities, existingManifest: draft)

            let primaryBlueprint: MicroAppBlueprint
            var usedLocalCompiler = false
            do {
                primaryBlueprint = try await generator.generateBlueprint(from: normalized, context: context)
            } catch {
                usedLocalCompiler = true
                if let foundationError = error as? FoundationModelError {
                    modelState = .unavailable(foundationError.localizedDescription)
                }
                primaryBlueprint = try await fallbackGenerator.generateBlueprint(from: normalized, context: context)
                try await store.log(
                    appID: nil,
                    level: .warning,
                    category: "generation",
                    message: "The on-device model did not return a usable blueprint; the local prompt compiler completed generation instead.",
                    payload: .string(error.localizedDescription)
                )
            }

            var manifest = BlueprintConverter().convert(primaryBlueprint, capabilities: capabilities)
            var issues = ManifestValidator().validate(manifest)
            if issues.contains(where: { $0.severity == .error }), !usedLocalCompiler {
                let localBlueprint = try await fallbackGenerator.generateBlueprint(from: normalized, context: context)
                manifest = BlueprintConverter().convert(localBlueprint, capabilities: capabilities)
                issues = ManifestValidator().validate(manifest)
                usedLocalCompiler = true
                try await store.log(
                    appID: nil,
                    level: .warning,
                    category: "generation",
                    message: "The model blueprint failed validation; PocketKernel replaced it with a locally compiled blueprint."
                )
            }

            previousDraft = draft
            draft = manifest
            validationIssues = issues
            if issues.contains(where: { $0.severity == .error }) {
                throw PackageError.invalidManifest(issues.filter { $0.severity == .error })
            }
            let source = usedLocalCompiler ? "local prompt compiler" : "on-device model"
            try await store.log(appID: nil, level: .info, category: "generation", message: "Generated and validated \(manifest.name) using the \(source).")
            await load()
        } catch {
            generationError = error.localizedDescription
            try? await store.log(appID: nil, level: .error, category: "generation", message: error.localizedDescription)
            await load()
        }
    }

    func validateDraft() {
        guard let draft else { validationIssues = []; return }
        validationIssues = ManifestValidator().validate(draft)
    }

    func undoDraft() {
        let current = draft
        draft = previousDraft
        previousDraft = current
        validateDraft()
    }

    func installDraft() async {
        guard let store, let draft else { return }
        do {
            let package = try PackageCodec().makePackage(manifest: draft)
            try await store.install(package)
            try await store.log(appID: draft.id, level: .info, category: "install", message: "Installed \(draft.name).")
            self.draft = nil
            previousDraft = nil
            validationIssues = []
            await load()
        } catch { generationError = error.localizedDescription }
    }

    func installTemplate(_ template: BundledTemplate) async {
        guard let store else { return }
        do {
            try await store.install(template.package)
            try await store.log(appID: template.id, level: .info, category: "install", message: "Installed built-in package \(template.manifest.name).")
            try await store.markOpened(id: template.id)
            try await store.log(appID: template.id, level: .info, category: "runtime", message: "Opened \(template.manifest.name).")
            await load()
            pendingOpenApp = template.manifest
            lifecycle.markRuntimeOpen(appID: template.id)
        } catch { startupError = error.localizedDescription }
    }

    func importPackage(_ data: Data) async throws {
        guard let store else { throw StoreError.invalidData }
        let package = try PackageCodec().decode(data)
        try await store.install(package)
        try await store.log(appID: package.manifest.id, level: .info, category: "import", message: "Imported \(package.manifest.name).")
        await load()
    }

    func exportPackage(_ manifest: MicroAppManifest) async throws -> Data {
        guard let store else { throw StoreError.invalidData }
        let data = try await store.exportPackage(appID: manifest.id)
        lastExportedPackage = data
        try data.write(to: Self.lastExportURL(), options: .atomic)
        await load()
        return data
    }

    func importLastExportForTesting() async throws {
        guard launchArguments.contains("-PKUITesting") else { throw StoreError.invalidData }
        let data = try lastExportedPackage ?? Data(contentsOf: Self.lastExportURL())
        try await importPackage(data)
    }

    func open(_ app: InstalledAppInfo) async {
        guard !app.disabled, let store else { return }
        do {
            try await store.markOpened(id: app.id)
            try await store.log(appID: app.id, level: .info, category: "runtime", message: "Opened \(app.manifest.name).")
            await load()
            pendingOpenApp = app.manifest
            lifecycle.markRuntimeOpen(appID: app.id)
        } catch { startupError = error.localizedDescription }
    }

    func delete(_ id: UUID) async {
        guard let store else { return }
        do { try await store.delete(id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func duplicate(_ id: UUID) async {
        guard let store else { return }
        do { _ = try await store.duplicate(id: id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func rename(_ id: UUID, name: String) async {
        guard let store else { return }
        do { try await store.rename(id: id, name: name); await load() }
        catch { startupError = error.localizedDescription }
    }

    func toggleFavorite(_ app: InstalledAppInfo) async {
        guard let store else { return }
        do { try await store.setFavorite(!app.favorite, id: app.id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func setDisabled(_ disabled: Bool, id: UUID) async {
        guard let store else { return }
        do { try await store.setDisabled(disabled, id: id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func rollback(_ id: UUID) async {
        guard let store else { return }
        do { try await store.rollbackManifest(id); await load() }
        catch { startupError = error.localizedDescription }
    }

    func resetAllData() async {
        guard let store else { return }
        do {
            try await store.reset()
            Self.clearAuxiliaryFiles()
            draft = nil
            previousDraft = nil
            lastExportedPackage = nil
            lifecycle.dismissRecovery()
            await load()
        } catch { startupError = error.localizedDescription }
    }

    func assetData(appID: UUID, assetID: String) async -> Data? {
        guard let store else { return nil }
        return try? await store.asset(appID: appID, id: assetID)?.data
    }

    func clearError() { startupError = nil }

    private func syncIntentEntities() {
        struct Snapshot: Codable { var id: String; var name: String }
        let snapshots = installed.filter { !$0.disabled }.map { Snapshot(id: $0.id.uuidString, name: $0.manifest.name) }
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshots), forKey: "PKIntentEntities")
    }

    private static func argumentValue(_ key: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func lastExportURL() -> URL {
        makeLayout().exports.appending(path: "last-export.pocketapp")
    }

    private static func clearAuxiliaryFiles() {
        let layout = makeLayout()
        for directory in [layout.packages, layout.assets, layout.exports, layout.recovery] {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for url in contents { try? FileManager.default.removeItem(at: url) }
        }
    }

    private static func makeLayout() -> PocketStorageLayout {
        if let layout = try? PocketStorageLayout.make() { return layout }
        let root = FileManager.default.temporaryDirectory.appending(path: "PocketKernel", directoryHint: .isDirectory)
        let layout = PocketStorageLayout(
            root: root,
            packages: root.appending(path: "Packages", directoryHint: .isDirectory),
            assets: root.appending(path: "Assets", directoryHint: .isDirectory),
            exports: root.appending(path: "Exports", directoryHint: .isDirectory),
            recovery: root.appending(path: "Recovery", directoryHint: .isDirectory)
        )
        for directory in [layout.root, layout.packages, layout.assets, layout.exports, layout.recovery] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return layout
    }
}

private struct PromptBlueprintGenerator: BlueprintGenerating {
    func generateBlueprint(from request: String, context: BuilderContext) async throws -> MicroAppBlueprint {
        compile(request: request, capabilities: context.requestedCapabilities)
    }

    private func compile(request: String, capabilities: Set<PocketCapability>) -> MicroAppBlueprint {
        let normalized = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = appName(from: normalized)
        let entityName = primaryEntity(from: name)
        let collectionTitle = pluralized(entityName)
        let collectionID = uniqueSlug(collectionTitle, fallback: "records")
        let fields = inferredFields(from: normalized, entityName: entityName)
        let numericField = fields.first { $0.kind == .number }
        let labelField = fields.first { [.text, .choice].contains($0.kind) } ?? fields.first
        let wantsReminder = containsAny(normalized, ["remind", "reminder", "notification", "alert me"])
        let wantsExport = containsAny(normalized, ["export", "backup", "share file"])
        let wantsShare = containsAny(normalized, ["share", "send"])

        var actions: [GeneratedAction] = [
            .init(id: "open-records", title: "Browse \(collectionTitle)", kind: .navigate, target: "records"),
            .init(id: "add-record", title: "Add \(entityName)", kind: .createRecord, target: collectionID)
        ]

        if wantsReminder, capabilities.contains(.localNotifications) {
            actions.append(.init(
                id: "schedule-reminder",
                title: "Schedule Reminder",
                kind: .scheduleLocalNotification,
                requiredCapability: .localNotifications,
                reason: "Remind you about a saved \(entityName.lowercased()).",
                parameters: [
                    "body": .string("Review \(name)"),
                    "seconds": .number(3_600)
                ]
            ))
        }
        if wantsExport, capabilities.contains(.fileExport) {
            actions.append(.init(
                id: "export-app",
                title: "Export App",
                kind: .exportFile,
                requiredCapability: .fileExport,
                reason: "Export this Pocket App and its records."
            ))
        }
        if wantsShare {
            actions.append(.init(id: "share-summary", title: "Share Summary", kind: .share, value: .string("{{ count(collections.\(collectionID)) }} \(collectionTitle) in \(name)")))
        }

        var overviewComponents: [GeneratedComponent] = [
            .init(id: "app-heading", kind: .heading, text: name),
            .init(id: "app-summary", kind: .caption, text: conciseSummary(from: normalized, name: name)),
            .init(id: "record-count", kind: .metric, title: collectionTitle, text: "{{ count(collections.\(collectionID)) }}")
        ]
        if let numericField, let labelField {
            overviewComponents.append(.init(
                id: "record-chart",
                kind: .chart,
                title: numericField.title,
                collection: collectionID,
                labelField: labelField.id,
                valueField: numericField.id,
                chartStyle: .bar
            ))
        }
        overviewComponents.append(.init(id: "browse-records", kind: .button, title: "Browse \(collectionTitle)", actionID: "open-records"))
        overviewComponents.append(.init(id: "add-record-button", kind: .button, title: "Add \(entityName)", actionID: "add-record"))
        if actions.contains(where: { $0.id == "schedule-reminder" }) {
            overviewComponents.append(.init(id: "reminder-button", kind: .button, title: "Schedule Reminder", actionID: "schedule-reminder"))
        }
        if actions.contains(where: { $0.id == "export-app" }) {
            overviewComponents.append(.init(id: "export-button", kind: .fileExportButton, title: "Export App", actionID: "export-app"))
        }
        if actions.contains(where: { $0.id == "share-summary" }) {
            overviewComponents.append(.init(id: "share-button", kind: .shareButton, title: "Share Summary", actionID: "share-summary"))
        }

        let dateField = fields.first(where: { $0.kind == .date })?.id
        let screens = [
            GeneratedScreen(id: "overview", title: name, collectionID: collectionID, components: overviewComponents),
            GeneratedScreen(
                id: "records",
                title: collectionTitle,
                collectionID: collectionID,
                components: [
                    .init(id: "record-search", kind: .searchResults, title: "Search \(collectionTitle)", binding: "state.searchText", collection: collectionID, sortField: dateField, sortAscending: false),
                    .init(id: "record-list", kind: .list, title: collectionTitle, collection: collectionID, sortField: dateField, sortAscending: false),
                    .init(id: "record-form", kind: .recordForm, title: "New \(entityName)", collection: collectionID, actionID: "add-record")
                ]
            )
        ]

        return BlueprintRepairer().repair(.init(
            name: name,
            summary: conciseSummary(from: normalized, name: name),
            screens: screens,
            collections: [.init(id: collectionID, title: collectionTitle, fields: fields)],
            actions: actions
        ))
    }

    private func appName(from request: String) -> String {
        let lower = request.lowercased()
        let boundaryWords = [" with ", " including ", " that ", " where ", " which ", " for tracking ", " to track "]
        var core = request
        for boundary in boundaryWords {
            if let range = lower.range(of: boundary), range.lowerBound < core.endIndex {
                let distance = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let index = core.index(core.startIndex, offsetBy: min(distance, core.count))
                core = String(core[..<index])
                break
            }
        }

        let ignored: Set<String> = [
            "a", "an", "the", "app", "application", "please", "create", "make", "build", "generate", "i", "want", "need", "me", "my", "simple", "native", "pocket"
        ]
        let words = tokens(core).filter { !ignored.contains($0) }
        var chosen = Array(words.prefix(5))
        if chosen.isEmpty { chosen = ["custom", "workspace"] }
        let title = chosen.map(titleCased).joined(separator: " ")
        if chosen.contains(where: { ["tracker", "manager", "organizer", "planner", "journal", "log", "list", "board", "crm"].contains($0) }) {
            return title
        }
        return "\(title) Tracker"
    }

    private func primaryEntity(from appName: String) -> String {
        let suffixes = [" Tracker", " Manager", " Organizer", " Planner", " Journal", " Log", " List", " Board", " CRM", " App"]
        var result = appName
        for suffix in suffixes where result.hasSuffix(suffix) {
            result.removeLast(suffix.count)
            break
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Record" : singularized(trimmed)
    }

    private func inferredFields(from request: String, entityName: String) -> [GeneratedField] {
        var phrases = explicitFieldPhrases(from: request)
        if phrases.isEmpty {
            phrases = ["name", "notes", "created date"]
        }
        if !phrases.contains(where: { containsAny($0, ["name", "title", entityName.lowercased()]) }) {
            phrases.insert("name", at: 0)
        }

        var used = Set<String>()
        var fields: [GeneratedField] = []
        for phrase in phrases.prefix(12) {
            let cleaned = cleanFieldPhrase(phrase)
            guard !cleaned.isEmpty else { continue }
            let title = titleCasedPhrase(cleaned)
            let baseID = uniqueSlug(cleaned, fallback: "field")
            var id = baseID
            var suffix = 2
            while used.contains(id) {
                id = "\(baseID)-\(suffix)"
                suffix += 1
            }
            used.insert(id)
            let kind = inferredKind(for: cleaned)
            fields.append(.init(
                id: id,
                title: title,
                kind: kind,
                options: options(for: cleaned, kind: kind),
                required: fields.isEmpty || containsAny(cleaned, ["name", "title"])
            ))
        }
        if fields.isEmpty {
            fields = [.init(id: "name", title: "Name", kind: .text, required: true)]
        }
        return fields
    }

    private func explicitFieldPhrases(from request: String) -> [String] {
        let lower = request.lowercased()
        let markers = [" with ", " including ", " fields ", " containing ", " track "]
        var tail: String?
        for marker in markers {
            if let range = lower.range(of: marker) {
                let distance = lower.distance(from: lower.startIndex, to: range.upperBound)
                let index = request.index(request.startIndex, offsetBy: min(distance, request.count))
                tail = String(request[index...])
                break
            }
        }
        guard var tail else { return [] }
        for stop in [" so that ", " where ", " which ", " and remind", " and notify", "."] {
            if let range = tail.lowercased().range(of: stop) {
                let lowered = tail.lowercased()
                let distance = lowered.distance(from: lowered.startIndex, to: range.lowerBound)
                let index = tail.index(tail.startIndex, offsetBy: min(distance, tail.count))
                tail = String(tail[..<index])
            }
        }
        tail = tail.replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
        tail = tail.replacingOccurrences(of: ";", with: ",")
        return tail.split(separator: ",").map(String.init)
    }

    private func cleanFieldPhrase(_ value: String) -> String {
        let ignored: Set<String> = ["a", "an", "the", "their", "its", "my", "user", "users", "field", "fields", "track", "tracking", "store", "save"]
        return tokens(value).filter { !ignored.contains($0) }.joined(separator: " ")
    }

    private func inferredKind(for phrase: String) -> FieldKind {
        if containsAny(phrase, ["date", "day", "time", "deadline", "due", "birthday", "scheduled"]) { return .date }
        if containsAny(phrase, ["cost", "price", "amount", "total", "quantity", "count", "number", "score", "weight", "mileage", "distance", "duration", "hours", "minutes", "rating", "percent", "percentage"]) { return .number }
        if containsAny(phrase, ["done", "complete", "completed", "active", "enabled", "paid", "favorite", "archived", "yes no"]) { return .boolean }
        if containsAny(phrase, ["status", "priority", "category", "type", "stage", "level"]) { return .choice }
        if containsAny(phrase, ["notes", "description", "details", "journal", "body", "comments", "instructions"]) { return .multilineText }
        if containsAny(phrase, ["photo", "image", "picture", "receipt"]) { return .image }
        return .text
    }

    private func options(for phrase: String, kind: FieldKind) -> [String] {
        guard kind == .choice else { return [] }
        if containsAny(phrase, ["priority", "level"]) { return ["Low", "Medium", "High"] }
        if containsAny(phrase, ["status", "stage"]) { return ["Planned", "In Progress", "Done"] }
        return ["General", "Other"]
    }

    private func conciseSummary(from request: String, name: String) -> String {
        let cleaned = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "A private local workspace for \(name)." }
        let firstSentence = cleaned.split(separator: ".", maxSplits: 1).first.map(String.init) ?? cleaned
        let normalized = firstSentence.prefix(180)
        return normalized.last == "." ? String(normalized) : "\(normalized)."
    }

    private func tokens(_ value: String) -> [String] {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        let lower = value.lowercased()
        return needles.contains { lower.contains($0.lowercased()) }
    }

    private func titleCased(_ word: String) -> String {
        word.uppercased() == "CRM" ? "CRM" : word.prefix(1).uppercased() + String(word.dropFirst())
    }

    private func titleCasedPhrase(_ value: String) -> String {
        tokens(value).map(titleCased).joined(separator: " ")
    }

    private func singularized(_ value: String) -> String {
        if value.hasSuffix("ies"), value.count > 3 { return String(value.dropLast(3)) + "y" }
        if value.hasSuffix("s"), !value.hasSuffix("ss"), value.count > 1 { return String(value.dropLast()) }
        return value
    }

    private func pluralized(_ value: String) -> String {
        if value.hasSuffix("y"), value.count > 1 { return String(value.dropLast()) + "ies" }
        if value.hasSuffix("s") { return value }
        return value + "s"
    }

    private func uniqueSlug(_ value: String, fallback: String) -> String {
        let characters = value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let result = String(characters).split(separator: "-").joined(separator: "-")
        return result.isEmpty ? fallback : String(result.prefix(64))
    }
}
