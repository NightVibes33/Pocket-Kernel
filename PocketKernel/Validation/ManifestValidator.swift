import Foundation

struct ValidationIssue: Codable, Sendable, Identifiable, Equatable {
    enum Severity: String, Codable, Sendable { case warning, error }
    var id: String { code + path }
    let severity: Severity
    let code: String
    let path: String
    let message: String
}

struct ManifestValidator: Sendable {
    func validate(_ manifest: MicroAppManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func error(_ code: String, _ path: String, _ message: String) {
            issues.append(.init(severity: .error, code: code, path: path, message: message))
        }
        guard manifest.formatVersion == 1 else {
            return [.init(severity: .error, code: "format.unsupported", path: "formatVersion", message: "Only format version 1 is supported.")]
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error("name.empty", "name", "Name is required.") }
        if manifest.screens.isEmpty || manifest.screens.count > PocketLimits.screens { error("screens.limit", "screens", "Screen count must be 1...20.") }
        if manifest.actions.count > PocketLimits.actions { error("actions.limit", "actions", "At most 50 actions are allowed.") }
        if manifest.collections.count > PocketLimits.collections { error("collections.limit", "collections", "At most 20 collections are allowed.") }

        let screenIDs = manifest.screens.map(\.id)
        let actionIDs = manifest.actions.map(\.id)
        let collectionIDs = manifest.collections.map(\.id)
        checkUnique(screenIDs, path: "screens", error: error)
        checkUnique(actionIDs, path: "actions", error: error)
        checkUnique(collectionIDs, path: "collections", error: error)
        if !Set(screenIDs).contains(manifest.entryScreenID) { error("entry.missing", "entryScreenID", "Entry screen does not exist.") }

        var componentIDs: [String] = []
        var componentCount = 0
        for (screenIndex, screen) in manifest.screens.enumerated() {
            walk(screen.components, depth: 1) { component, depth in
                componentCount += 1
                componentIDs.append(component.id)
                let path = "screens[\(screenIndex)].components.\(component.id)"
                if depth > PocketLimits.nestingDepth { error("components.depth", path, "Component nesting exceeds 8 levels.") }
                if let actionID = component.actionID, !Set(actionIDs).contains(actionID) { error("action.missing", path, "Referenced action does not exist.") }
                if let collection = component.collection, !Set(collectionIDs).contains(collection) { error("collection.missing", path, "Referenced collection does not exist.") }
                if hasTraversal(component.id) { error("identifier.traversal", path, "Traversal strings are forbidden.") }
            }
        }
        if componentCount > PocketLimits.components { error("components.limit", "screens", "At most 100 components are allowed.") }
        checkUnique(componentIDs, path: "components", error: error)

        for action in manifest.actions {
            if let capability = action.requiredCapability, !manifest.capabilities.contains(capability) {
                error("capability.undeclared", "actions.\(action.id)", "Action requires undeclared capability \(capability.rawValue).")
            }
        }
        for domain in manifest.allowedDomains {
            if domain.contains("*") || domain.contains("://") || domain.contains("/") || domain.isEmpty {
                error("domain.invalid", "allowedDomains", "Domains must be exact host names without schemes, paths, or wildcards.")
            }
        }
        return issues
    }

    private func walk(_ components: [ComponentSpec], depth: Int, visit: (ComponentSpec, Int) -> Void) {
        for component in components { visit(component, depth); walk(component.children, depth: depth + 1, visit: visit) }
    }

    private func checkUnique(_ values: [String], path: String, error: (String, String, String) -> Void) {
        if Set(values).count != values.count { error("identifier.duplicate", path, "Identifiers must be unique.") }
        for value in values where value.isEmpty || hasTraversal(value) { error("identifier.invalid", path, "Identifiers cannot be empty or contain traversal strings.") }
    }

    private func hasTraversal(_ value: String) -> Bool { value.contains("..") || value.contains("/") || value.contains("\\") }
}

