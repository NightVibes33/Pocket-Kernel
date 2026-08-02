import Foundation

enum PocketLimits {
    static let screens = 20
    static let components = 100
    static let actions = 50
    static let collections = 20
    static let recordsPerCollection = 5_000
    static let nestingDepth = 8
    static let packageBytes = 25 * 1_024 * 1_024
    static let assetBytes = 10 * 1_024 * 1_024
    static let expressionCharacters = 2_000
    static let expressionDepth = 20
    static let expressionOperations = 5_000
    static let expressionArrayValues = 5_000
}

enum PocketValue: Codable, Sendable, Equatable {
    case null, bool(Bool), number(Double), string(String), date(Date)
    case array([PocketValue]), object([String: PocketValue])

    private enum Kind: String, Codable { case null, bool, number, string, date, array, object }
    private enum CodingKeys: String, CodingKey { case kind, value }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        switch try box.decode(Kind.self, forKey: .kind) {
        case .null: self = .null
        case .bool: self = .bool(try box.decode(Bool.self, forKey: .value))
        case .number: self = .number(try box.decode(Double.self, forKey: .value))
        case .string: self = .string(try box.decode(String.self, forKey: .value))
        case .date: self = .date(try box.decode(Date.self, forKey: .value))
        case .array: self = .array(try box.decode([PocketValue].self, forKey: .value))
        case .object: self = .object(try box.decode([String: PocketValue].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null: try box.encode(Kind.null, forKey: .kind)
        case .bool(let value): try box.encode(Kind.bool, forKey: .kind); try box.encode(value, forKey: .value)
        case .number(let value): try box.encode(Kind.number, forKey: .kind); try box.encode(value, forKey: .value)
        case .string(let value): try box.encode(Kind.string, forKey: .kind); try box.encode(value, forKey: .value)
        case .date(let value): try box.encode(Kind.date, forKey: .kind); try box.encode(value, forKey: .value)
        case .array(let value): try box.encode(Kind.array, forKey: .kind); try box.encode(value, forKey: .value)
        case .object(let value): try box.encode(Kind.object, forKey: .kind); try box.encode(value, forKey: .value)
        }
    }

    var displayString: String {
        switch self {
        case .null: ""
        case .bool(let value): value ? "Yes" : "No"
        case .number(let value): value.formatted()
        case .string(let value): value
        case .date(let value): value.formatted(date: .abbreviated, time: .shortened)
        case .array(let value): "\(value.count) items"
        case .object(let value): "\(value.count) fields"
        }
    }
}

enum PocketCapability: String, Codable, Sendable, CaseIterable {
    case clipboardRead, clipboardWrite, fileImport, fileExport, photoSelection, camera
    case localNotifications, network, onDeviceModel
}

enum FieldKind: String, Codable, Sendable, CaseIterable {
    case text, multilineText, number, boolean, date, choice, image
}

enum ComponentKind: String, Codable, Sendable, CaseIterable {
    case text, markdown, heading, caption, metric, progress, image, symbol, divider, spacer, badge
    case textField, secureField, multilineText, numberField, toggle, slider, stepper, datePicker, picker, segmentedPicker
    case list, grid, recordForm, detail, searchResults, chart, emptyState
    case button, menu, shareButton, fileImportButton, fileExportButton, photoPickerButton, confirmationButton
    case section, verticalStack, horizontalStack, lazyGrid, card, group, scrollContainer
}

struct ComponentSpec: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: ComponentKind
    var title: String?
    var text: String?
    var binding: String?
    var collection: String?
    var actionID: String?
    var children: [ComponentSpec] = []
    var options: [String] = []
    var minimum: Double?
    var maximum: Double?
    var visibilityExpression: String?
    var disabledExpression: String?
    var valueField: String?
    var labelField: String?
    var assetID: String?
}

struct ScreenSpec: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var components: [ComponentSpec]
}

enum ActionKind: String, Codable, Sendable, CaseIterable {
    case setValue, clearValue, createRecord, updateRecord, deleteRecord, sortRecords, filterRecords
    case navigate, dismiss, showAlert, showConfirmation, showSheet, selectRecord
    case copyToClipboard, share, importFile, exportFile, selectPhotos, scheduleLocalNotification, openURL
    case generateText, summarizeText, extractFields, classifyText, rewriteText, httpGet, httpPostJSON
}

struct ActionSpec: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: ActionKind
    var title: String?
    var target: String?
    var value: PocketValue?
    var requiredCapability: PocketCapability?
    var condition: String?
    var reason: String?
    var parameters: [String: PocketValue] = [:]
    var nextActionIDs: [String] = []
}

struct FieldSpec: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var kind: FieldKind = .text
    var defaultValue: PocketValue = .string("")
    var required: Bool = false
    var options: [String] = []
}

struct CollectionSpec: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var fields: [FieldSpec]
}

struct PocketRecord: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var collectionID: String
    var values: [String: PocketValue]
    var createdAt: Date
    var updatedAt: Date
}

enum PermissionDecision: String, Codable, Sendable, CaseIterable { case notRequested, allowOnce, alwaysAllow, denied }

struct ActivityEvent: Codable, Sendable, Identifiable, Equatable {
    enum Level: String, Codable, Sendable { case info, warning, error }
    var id: Int64
    var appID: UUID?
    var level: Level
    var category: String
    var message: String
    var payload: PocketValue?
    var createdAt: Date
}

struct PocketTheme: Codable, Sendable, Equatable {
    var accentHex = "#6C5CE7"
    var prefersDark = false
}

struct PocketIcon: Codable, Sendable, Equatable {
    var symbol = "square.grid.2x2.fill"
    var backgroundHex = "#6C5CE7"
}

struct MicroAppManifest: Codable, Sendable, Identifiable, Equatable {
    var formatVersion = 1
    var id: UUID
    var name: String
    var summary: String
    var icon = PocketIcon()
    var theme = PocketTheme()
    var entryScreenID: String
    var screens: [ScreenSpec]
    var actions: [ActionSpec]
    var collections: [CollectionSpec]
    var capabilities: Set<PocketCapability>
    var allowedDomains: [String] = []
    var createdAt: Date
    var updatedAt: Date
}

struct PackageAsset: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var mediaType: String
    var sha256: String
    var base64Data: String
}

struct PackageIntegrity: Codable, Sendable, Equatable {
    var algorithm = "sha256"
    var manifestHash: String
}

struct PocketPackage: Codable, Sendable, Equatable {
    var formatVersion = 1
    var manifest: MicroAppManifest
    var assets: [PackageAsset]
    var integrity: PackageIntegrity
}

struct InstalledAppInfo: Sendable, Identifiable, Equatable {
    var id: UUID { manifest.id }
    var manifest: MicroAppManifest
    var favorite: Bool
    var disabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
}

struct StoredAsset: Sendable, Equatable {
    var id: String
    var mediaType: String
    var data: Data
}
