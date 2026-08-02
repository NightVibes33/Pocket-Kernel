import Foundation

struct ValidationIssue: Codable, Sendable, Identifiable, Equatable {
    enum Severity: String, Codable, Sendable { case warning, error }
    var id: String { "\(code):\(path)" }
    let severity: Severity
    let code: String
    let path: String
    let message: String
}

struct ManifestValidator: Sendable {
    func validate(_ manifest: MicroAppManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        guard manifest.formatVersion == 1 else {
            return [error("format.unsupported", "formatVersion", "Only Pocket App format version 1 is supported.")]
        }

        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(error("name.empty", "name", "App name cannot be empty."))
        }
        if manifest.screens.isEmpty { issues.append(error("screens.empty", "screens", "At least one screen is required.")) }
        if manifest.screens.count > PocketLimits.screens { issues.append(error("limit.screens", "screens", "Maximum \(PocketLimits.screens) screens.")) }
        if manifest.actions.count > PocketLimits.actions { issues.append(error("limit.actions", "actions", "Maximum \(PocketLimits.actions) actions.")) }
        if manifest.collections.count > PocketLimits.collections { issues.append(error("limit.collections", "collections", "Maximum \(PocketLimits.collections) collections.")) }

        issues += duplicateIssues(manifest.screens.map(\.id), path: "screens")
        issues += duplicateIssues(manifest.actions.map(\.id), path: "actions")
        issues += duplicateIssues(manifest.collections.map(\.id), path: "collections")
        issues += identifierIssues(manifest.screens.map(\.id), path: "screens")
        issues += identifierIssues(manifest.actions.map(\.id), path: "actions")
        issues += identifierIssues(manifest.collections.map(\.id), path: "collections")

        let screenIDs = Set(manifest.screens.map(\.id))
        let actionIDs = Set(manifest.actions.map(\.id))
        let collectionIDs = Set(manifest.collections.map(\.id))
        if !screenIDs.contains(manifest.entryScreenID) {
            issues.append(error("entry.missing", "entryScreenID", "The entry screen does not exist."))
        }

        for (collectionIndex, collection) in manifest.collections.enumerated() {
            let base = "collections[\(collectionIndex)]"
            if collection.fields.isEmpty {
                issues.append(error("fields.empty", "\(base).fields", "A collection requires at least one field."))
            }
            issues += duplicateIssues(collection.fields.map(\.id), path: "\(base).fields")
            issues += identifierIssues(collection.fields.map(\.id), path: "\(base).fields")
            for (fieldIndex, field) in collection.fields.enumerated() {
                let path = "\(base).fields[\(fieldIndex)]"
                if !defaultValue(field.defaultValue, matches: field.kind) {
                    issues.append(error("field.defaultType", "\(path).defaultValue", "The default value does not match \(field.kind.rawValue)."))
                }
                if field.kind == .choice {
                    if field.options.isEmpty {
                        issues.append(error("field.options", "\(path).options", "Choice fields require at least one option."))
                    }
                    if let value = field.defaultValue.stringValue, !field.options.contains(value) {
                        issues.append(error("field.defaultOption", "\(path).defaultValue", "The choice default must be one of its options."))
                    }
                } else if !field.options.isEmpty {
                    issues.append(warning("field.unusedOptions", "\(path).options", "Options are only used by choice fields."))
                }
            }
        }

        var componentIDs: [String] = []
        var componentCount = 0
        for (screenIndex, screen) in manifest.screens.enumerated() {
            validateComponents(
                screen.components,
                path: "screens[\(screenIndex)].components",
                depth: 1,
                actionIDs: actionIDs,
                collectionIDs: collectionIDs,
                componentIDs: &componentIDs,
                count: &componentCount,
                issues: &issues
            )
        }
        issues += duplicateIssues(componentIDs, path: "components")
        issues += identifierIssues(componentIDs, path: "components")
        if componentCount > PocketLimits.components {
            issues.append(error("limit.components", "screens", "Maximum \(PocketLimits.components) components."))
        }

        for (index, action) in manifest.actions.enumerated() {
            let path = "actions[\(index)]"
            if let required = action.requiredCapability {
                if !manifest.capabilities.contains(required) {
                    issues.append(error("capability.undeclared", "\(path).requiredCapability", "Action \(action.id) requires undeclared capability \(required.rawValue)."))
                }
                if let expected = expectedCapability(action.kind), expected != required {
                    issues.append(error("capability.mismatch", "\(path).requiredCapability", "Action \(action.kind.rawValue) must use \(expected.rawValue)."))
                }
            } else if let expected = expectedCapability(action.kind) {
                issues.append(error("capability.missing", "\(path).requiredCapability", "Action \(action.kind.rawValue) must declare \(expected.rawValue)."))
            }
            for next in action.nextActionIDs where !actionIDs.contains(next) {
                issues.append(error("action.nextMissing", "\(path).nextActionIDs", "Next action \(next) does not exist."))
            }
            if action.nextActionIDs.contains(action.id) {
                issues.append(error("action.selfCycle", "\(path).nextActionIDs", "An action cannot directly call itself."))
            }
            validateActionTarget(action, path: path, screens: screenIDs, collections: collectionIDs, issues: &issues)
            if let condition = action.condition { validateExpression(condition, path: "\(path).condition", issues: &issues) }
            if action.kind == .httpGet || action.kind == .httpPostJSON {
                validateNetworkAction(action, path: path, allowedDomains: manifest.allowedDomains, issues: &issues)
            }
        }

        for (index, domain) in manifest.allowedDomains.enumerated() {
            let path = "allowedDomains[\(index)]"
            if domain.isEmpty || domain.contains("*") || domain.contains("/") || domain.contains(":") || domain.contains("..") || domain != domain.lowercased() {
                issues.append(error("domain.invalid", path, "Domains must be exact lowercase host names without schemes, paths, ports, or wildcards."))
            }
        }
        if Set(manifest.allowedDomains).count != manifest.allowedDomains.count {
            issues.append(error("domain.duplicate", "allowedDomains", "Allowed domains must be unique."))
        }
        return issues
    }

    private func validateComponents(
        _ components: [ComponentSpec],
        path: String,
        depth: Int,
        actionIDs: Set<String>,
        collectionIDs: Set<String>,
        componentIDs: inout [String],
        count: inout Int,
        issues: inout [ValidationIssue]
    ) {
        if depth > PocketLimits.nestingDepth {
            issues.append(error("limit.depth", path, "Maximum UI nesting depth is \(PocketLimits.nestingDepth)."))
            return
        }
        for (index, component) in components.enumerated() {
            let itemPath = "\(path)[\(index)]"
            count += 1
            componentIDs.append(component.id)
            if let actionID = component.actionID, !actionIDs.contains(actionID) {
                issues.append(error("action.missing", "\(itemPath).actionID", "Component references missing action \(actionID)."))
            }
            if let collection = component.collection, !collectionIDs.contains(collection) {
                issues.append(error("collection.missing", "\(itemPath).collection", "Component references missing collection \(collection)."))
            }
            if actionComponentRequiresAction(component.kind), component.actionID == nil {
                issues.append(error("action.required", "\(itemPath).actionID", "\(component.kind.rawValue) requires a permission-checked action."))
            }
            if component.kind == .recordForm, component.collection == nil {
                issues.append(error("collection.required", "\(itemPath).collection", "Record forms require a collection."))
            }
            if component.kind == .picker || component.kind == .segmentedPicker, component.options.isEmpty {
                issues.append(error("component.options", "\(itemPath).options", "Pickers require at least one option."))
            }
            if let expression = component.visibilityExpression { validateExpression(expression, path: "\(itemPath).visibilityExpression", issues: &issues) }
            if let expression = component.disabledExpression { validateExpression(expression, path: "\(itemPath).disabledExpression", issues: &issues) }
            if let expression = component.filterExpression { validateExpression(expression, path: "\(itemPath).filterExpression", issues: &issues) }
            validateComponents(
                component.children,
                path: "\(itemPath).children",
                depth: depth + 1,
                actionIDs: actionIDs,
                collectionIDs: collectionIDs,
                componentIDs: &componentIDs,
                count: &count,
                issues: &issues
            )
        }
    }

    private func validateActionTarget(
        _ action: ActionSpec,
        path: String,
        screens: Set<String>,
        collections: Set<String>,
        issues: inout [ValidationIssue]
    ) {
        switch action.kind {
        case .createRecord, .updateRecord, .deleteRecord, .sortRecords, .filterRecords:
            guard let target = action.target, collections.contains(target) else {
                issues.append(error("action.collectionTarget", "\(path).target", "\(action.kind.rawValue) requires an existing collection target."))
                return
            }
        case .navigate:
            guard let target = action.target, screens.contains(target) else {
                issues.append(error("action.screenTarget", "\(path).target", "Navigate requires an existing screen target."))
                return
            }
        case .httpGet, .httpPostJSON, .openURL:
            if action.target?.isEmpty != false {
                issues.append(error("action.urlTarget", "\(path).target", "This action requires a URL target."))
            }
        default: break
        }
    }

    private func validateNetworkAction(_ action: ActionSpec, path: String, allowedDomains: [String], issues: inout [ValidationIssue]) {
        guard let target = action.target,
              let url = URL(string: target),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else {
            issues.append(error("network.https", "\(path).target", "Network actions require a valid HTTPS URL."))
            return
        }
        if !allowedDomains.contains(host) {
            issues.append(error("network.domain", "\(path).target", "Network host \(host) is not in the exact allowed-domain list."))
        }
        if url.user != nil || url.password != nil {
            issues.append(error("network.credentials", "\(path).target", "Credentials cannot be embedded in package URLs."))
        }
    }

    private func validateExpression(_ expression: String, path: String, issues: inout [ValidationIssue]) {
        do { try ExpressionEvaluator().validateSyntax(expression) }
        catch let error as ExpressionError { issues.append(self.error("expression.invalid", path, error.localizedDescription)) }
        catch { issues.append(self.error("expression.invalid", path, "The expression is invalid.")) }
    }

    private func expectedCapability(_ kind: ActionKind) -> PocketCapability? {
        switch kind {
        case .copyToClipboard: .clipboardWrite
        case .share, .exportFile: .fileExport
        case .importFile: .fileImport
        case .selectPhotos: .photoSelection
        case .scheduleLocalNotification: .localNotifications
        case .generateText, .summarizeText, .extractFields, .classifyText, .rewriteText: .onDeviceModel
        case .httpGet, .httpPostJSON: .network
        default: nil
        }
    }

    private func actionComponentRequiresAction(_ kind: ComponentKind) -> Bool {
        switch kind {
        case .shareButton, .fileImportButton, .fileExportButton, .photoPickerButton, .confirmationButton: true
        default: false
        }
    }

    private func defaultValue(_ value: PocketValue, matches kind: FieldKind) -> Bool {
        switch (kind, value) {
        case (.text, .string(_)), (.multilineText, .string(_)), (.choice, .string(_)), (.image, .string(_)):
            true
        case (.number, .number(_)), (.boolean, .bool(_)), (.date, .date(_)):
            true
        default:
            false
        }
    }

    private func duplicateIssues(_ values: [String], path: String) -> [ValidationIssue] {
        Dictionary(grouping: values, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
            .map { error("identifier.duplicate", path, "Duplicate identifier: \($0).") }
    }

    private func identifierIssues(_ values: [String], path: String) -> [ValidationIssue] {
        values.compactMap { value in
            isIdentifier(value) ? nil : error("identifier.invalid", path, "Invalid identifier: \(value). Use lowercase letters, numbers, and hyphens.")
        }
    }

    private func isIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 80, value.first?.isLetter == true else { return false }
        return value.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
            && !value.contains("..")
            && !value.contains("/")
            && !value.contains("\\")
    }

    private func error(_ code: String, _ path: String, _ message: String) -> ValidationIssue {
        .init(severity: .error, code: code, path: path, message: message)
    }

    private func warning(_ code: String, _ path: String, _ message: String) -> ValidationIssue {
        .init(severity: .warning, code: code, path: path, message: message)
    }
}
