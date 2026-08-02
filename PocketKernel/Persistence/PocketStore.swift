import Foundation
import SQLite3

struct PocketStorageLayout: Sendable {
    var root: URL
    var packages: URL
    var assets: URL
    var exports: URL
    var recovery: URL

    static func make() throws -> PocketStorageLayout {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "PocketKernel", directoryHint: .isDirectory)
        let layout = PocketStorageLayout(
            root: base,
            packages: base.appending(path: "Packages", directoryHint: .isDirectory),
            assets: base.appending(path: "Assets", directoryHint: .isDirectory),
            exports: base.appending(path: "Exports", directoryHint: .isDirectory),
            recovery: base.appending(path: "Recovery", directoryHint: .isDirectory)
        )
        for directory in [layout.root, layout.packages, layout.assets, layout.exports, layout.recovery] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return layout
    }
}

enum StoreError: LocalizedError, Equatable {
    case open, query(String), limit, invalidData, missingApp, noPreviousVersion

    var errorDescription: String? {
        switch self {
        case .open: "PocketKernel could not open its local database."
        case .query(let message): "Database operation failed: \(message)"
        case .limit: "This collection already contains 5,000 records."
        case .invalidData: "The stored package data is invalid."
        case .missingApp: "The requested Pocket App does not exist."
        case .noPreviousVersion: "No previous valid version is available."
        }
    }
}

private final class SQLiteHandle: @unchecked Sendable {
    var pointer: OpaquePointer?
    deinit { sqlite3_close(pointer) }
}

actor PocketStore {
    private let handle: SQLiteHandle
    private let layout: PocketStorageLayout
    private var database: OpaquePointer? { handle.pointer }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool = false) throws {
        layout = try PocketStorageLayout.make()
        let handle = SQLiteHandle()
        self.handle = handle
        let path = inMemory ? ":memory:" : layout.root.appending(path: "pocketkernel.sqlite").path
        guard sqlite3_open(path, &handle.pointer) == SQLITE_OK else { throw StoreError.open }
        try Self.migrate(handle.pointer)
    }

    func installedApps() throws -> [InstalledAppInfo] {
        let sql = "SELECT manifest,favorite,disabled,created_at,updated_at,last_opened_at FROM installed_apps ORDER BY favorite DESC, COALESCE(last_opened_at,updated_at) DESC"
        var statement: OpaquePointer?
        try prepare(sql, into: &statement)
        defer { sqlite3_finalize(statement) }
        var result: [InstalledAppInfo] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let manifestData = blob(statement, column: 0), let manifest = try? decoder.decode(MicroAppManifest.self, from: manifestData) else { continue }
            result.append(.init(
                manifest: manifest,
                favorite: sqlite3_column_int(statement, 1) != 0,
                disabled: sqlite3_column_int(statement, 2) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                lastOpenedAt: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            ))
        }
        return result
    }

    func install(_ package: PocketPackage) throws {
        let issues = ManifestValidator().validate(package.manifest)
        guard !issues.contains(where: { $0.severity == .error }) else { throw StoreError.invalidData }
        let manifestData = try encoder.encode(package.manifest)
        let packageData = try PackageCodec().encode(package)
        let now = Date().timeIntervalSince1970
        try transaction {
            var statement: OpaquePointer?
            let sql = """
            INSERT INTO installed_apps(id,manifest,package,previous_manifest,favorite,disabled,created_at,updated_at,last_opened_at)
            VALUES(?,?,?,NULL,0,0,?,?,NULL)
            ON CONFLICT(id) DO UPDATE SET previous_manifest=installed_apps.manifest,manifest=excluded.manifest,package=excluded.package,updated_at=excluded.updated_at
            """
            try prepare(sql, into: &statement)
            defer { sqlite3_finalize(statement) }
            bind(package.manifest.id.uuidString, statement, 1)
            bind(manifestData, statement, 2)
            bind(packageData, statement, 3)
            sqlite3_bind_double(statement, 4, package.manifest.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 5, now)
            try stepDone(statement)

            try execute("DELETE FROM package_assets WHERE app_id=?", bindings: [.text(package.manifest.id.uuidString)])
            for asset in package.assets {
                guard let data = Data(base64Encoded: asset.base64Data) else { throw StoreError.invalidData }
                try execute("INSERT INTO package_assets(app_id,asset_id,media_type,data,sha256) VALUES(?,?,?,?,?)", bindings: [
                    .text(package.manifest.id.uuidString), .text(asset.id), .text(asset.mediaType), .data(data), .text(asset.sha256)
                ])
            }
        }
    }

    func exportPackage(appID: UUID) throws -> Data {
        var statement: OpaquePointer?
        try prepare("SELECT package FROM installed_apps WHERE id=?", into: &statement)
        defer { sqlite3_finalize(statement) }
        bind(appID.uuidString, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW, let data = blob(statement, column: 0) else { throw StoreError.missingApp }
        try log(appID: appID, level: .info, category: "export", message: "Exported Pocket App package.")
        return data
    }

    func asset(appID: UUID, id: String) throws -> StoredAsset? {
        var statement: OpaquePointer?
        try prepare("SELECT media_type,data FROM package_assets WHERE app_id=? AND asset_id=?", into: &statement)
        defer { sqlite3_finalize(statement) }
        bind(appID.uuidString, statement, 1)
        bind(id, statement, 2)
        guard sqlite3_step(statement) == SQLITE_ROW, let media = text(statement, column: 0), let data = blob(statement, column: 1) else { return nil }
        return .init(id: id, mediaType: media, data: data)
    }

    func markOpened(id: UUID) throws {
        try execute("UPDATE installed_apps SET last_opened_at=? WHERE id=?", bindings: [.double(Date().timeIntervalSince1970), .text(id.uuidString)])
    }

    func setFavorite(_ favorite: Bool, id: UUID) throws {
        try execute("UPDATE installed_apps SET favorite=?,updated_at=? WHERE id=?", bindings: [.int(favorite ? 1 : 0), .double(Date().timeIntervalSince1970), .text(id.uuidString)])
    }

    func setDisabled(_ disabled: Bool, id: UUID) throws {
        try execute("UPDATE installed_apps SET disabled=?,updated_at=? WHERE id=?", bindings: [.int(disabled ? 1 : 0), .double(Date().timeIntervalSince1970), .text(id.uuidString)])
        try log(appID: id, level: .warning, category: "recovery", message: disabled ? "Disabled Pocket App." : "Re-enabled Pocket App.")
    }

    func rename(id: UUID, name: String) throws {
        var package = try package(id: id)
        package.manifest.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        package.manifest.updatedAt = Date()
        package.integrity = try PackageCodec().integrity(for: package.manifest)
        try install(package)
    }

    func duplicate(id: UUID) throws -> UUID {
        var package = try package(id: id)
        let newID = UUID()
        package.manifest.id = newID
        package.manifest.name += " Copy"
        package.manifest.createdAt = Date()
        package.manifest.updatedAt = Date()
        package.integrity = try PackageCodec().integrity(for: package.manifest)
        try install(package)
        return newID
    }

    func rollbackManifest(id: UUID) throws {
        var statement: OpaquePointer?
        try prepare("SELECT previous_manifest,package FROM installed_apps WHERE id=?", into: &statement)
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreError.missingApp }
        guard let previousData = blob(statement, column: 0), let previous = try? decoder.decode(MicroAppManifest.self, from: previousData) else { throw StoreError.noPreviousVersion }
        var package = try PackageCodec().decode(blob(statement, column: 1) ?? Data())
        package.manifest = previous
        package.integrity = try PackageCodec().integrity(for: previous)
        try install(package)
    }

    func delete(_ id: UUID) throws {
        try transaction {
            for table in ["records", "runtime_values", "permission_decisions", "package_assets"] {
                try execute("DELETE FROM \(table) WHERE app_id=?", bindings: [.text(id.uuidString)])
            }
            try execute("DELETE FROM installed_apps WHERE id=?", bindings: [.text(id.uuidString)])
        }
    }

    func records(appID: UUID, collectionID: String) throws -> [PocketRecord] {
        var statement: OpaquePointer?
        try prepare("SELECT payload FROM records WHERE app_id=? AND collection_id=? ORDER BY updated_at DESC LIMIT 5000", into: &statement)
        defer { sqlite3_finalize(statement) }
        bind(appID.uuidString, statement, 1)
        bind(collectionID, statement, 2)
        var result: [PocketRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let data = blob(statement, column: 0), let record = try? decoder.decode(PocketRecord.self, from: data) { result.append(record) }
        }
        return result
    }

    func save(record: PocketRecord, appID: UUID) throws {
        var count: OpaquePointer?
        try prepare("SELECT COUNT(*) FROM records WHERE app_id=? AND collection_id=? AND record_id<>?", into: &count)
        defer { sqlite3_finalize(count) }
        bind(appID.uuidString, count, 1)
        bind(record.collectionID, count, 2)
        bind(record.id.uuidString, count, 3)
        guard sqlite3_step(count) == SQLITE_ROW, sqlite3_column_int(count, 0) < PocketLimits.recordsPerCollection else { throw StoreError.limit }
        let data = try encoder.encode(record)
        try execute("INSERT OR REPLACE INTO records(app_id,collection_id,record_id,payload,created_at,updated_at) VALUES(?,?,?,?,?,?)", bindings: [
            .text(appID.uuidString), .text(record.collectionID), .text(record.id.uuidString), .data(data),
            .double(record.createdAt.timeIntervalSince1970), .double(record.updatedAt.timeIntervalSince1970)
        ])
    }

    func deleteRecord(appID: UUID, collectionID: String, recordID: UUID) throws {
        try execute("DELETE FROM records WHERE app_id=? AND collection_id=? AND record_id=?", bindings: [.text(appID.uuidString), .text(collectionID), .text(recordID.uuidString)])
    }

    func runtimeValues(appID: UUID) throws -> [String: PocketValue] {
        var statement: OpaquePointer?
        try prepare("SELECT key,value FROM runtime_values WHERE app_id=?", into: &statement)
        defer { sqlite3_finalize(statement) }
        bind(appID.uuidString, statement, 1)
        var result: [String: PocketValue] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = text(statement, column: 0), let data = blob(statement, column: 1), let value = try? decoder.decode(PocketValue.self, from: data) else { continue }
            result[key] = value
        }
        return result
    }

    func runtimeValue(appID: UUID, key: String) throws -> PocketValue? {
        try runtimeValues(appID: appID)[key]
    }

    func setRuntimeValue(_ value: PocketValue?, appID: UUID, key: String) throws {
        if let value {
            try execute("INSERT OR REPLACE INTO runtime_values(app_id,key,value) VALUES(?,?,?)", bindings: [.text(appID.uuidString), .text(key), .data(try encoder.encode(value))])
        } else {
            try execute("DELETE FROM runtime_values WHERE app_id=? AND key=?", bindings: [.text(appID.uuidString), .text(key)])
        }
    }

    func permission(appID: UUID, capability: PocketCapability) throws -> PermissionDecision {
        var statement: OpaquePointer?
        try prepare("SELECT decision FROM permission_decisions WHERE app_id=? AND capability=?", into: &statement)
        defer { sqlite3_finalize(statement) }
        bind(appID.uuidString, statement, 1)
        bind(capability.rawValue, statement, 2)
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = text(statement, column: 0) else { return .notRequested }
        return PermissionDecision(rawValue: raw) ?? .notRequested
    }

    func setPermission(_ decision: PermissionDecision, appID: UUID, capability: PocketCapability) throws {
        try execute("INSERT OR REPLACE INTO permission_decisions(app_id,capability,decision) VALUES(?,?,?)", bindings: [.text(appID.uuidString), .text(capability.rawValue), .text(decision.rawValue)])
        try log(appID: appID, level: .info, category: "permission", message: "Set \(capability.rawValue) to \(decision.rawValue).")
    }

    func log(appID: UUID?, level: ActivityEvent.Level, category: String, message: String, payload: PocketValue? = nil) throws {
        let payloadData = try payload.map(encoder.encode)
        try execute("INSERT INTO activity_events(app_id,level,category,message,payload,created_at) VALUES(?,?,?,?,?,?)", bindings: [
            appID.map { .text($0.uuidString) } ?? .null, .text(level.rawValue), .text(category), .text(message),
            payloadData.map(Binding.data) ?? .null, .double(Date().timeIntervalSince1970)
        ])
    }

    func activity(limit: Int = 250) throws -> [ActivityEvent] {
        var statement: OpaquePointer?
        try prepare("SELECT id,app_id,level,category,message,payload,created_at FROM activity_events ORDER BY id DESC LIMIT ?", into: &statement)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(min(max(limit, 1), 1_000)))
        var result: [ActivityEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(.init(
                id: sqlite3_column_int64(statement, 0),
                appID: text(statement, column: 1).flatMap(UUID.init(uuidString:)),
                level: text(statement, column: 2).flatMap(ActivityEvent.Level.init(rawValue:)) ?? .info,
                category: text(statement, column: 3) ?? "runtime",
                message: text(statement, column: 4) ?? "",
                payload: blob(statement, column: 5).flatMap { try? decoder.decode(PocketValue.self, from: $0) },
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            ))
        }
        return result
    }

    func storageBytes() throws -> Int64 {
        let path = layout.root.appending(path: "pocketkernel.sqlite").path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    func reset() throws {
        try transaction {
            for table in ["records", "runtime_values", "permission_decisions", "activity_events", "package_assets", "installed_apps"] {
                try execute("DELETE FROM \(table)")
            }
        }
    }

    private func package(id: UUID) throws -> PocketPackage {
        var statement: OpaquePointer?
        try prepare("SELECT package FROM installed_apps WHERE id=?", into: &statement)
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW, let data = blob(statement, column: 0) else { throw StoreError.missingApp }
        return try PackageCodec().decode(data)
    }

    private static func migrate(_ database: OpaquePointer?) throws {
        func raw(_ sql: String) throws {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite migration error"
                throw StoreError.query(message)
            }
        }

        try raw("PRAGMA journal_mode=WAL")
        try raw("PRAGMA foreign_keys=ON")
        try raw("""
        CREATE TABLE IF NOT EXISTS installed_apps(
            id TEXT PRIMARY KEY NOT NULL, manifest BLOB NOT NULL, package BLOB NOT NULL,
            previous_manifest BLOB, favorite INTEGER NOT NULL DEFAULT 0, disabled INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL, updated_at REAL NOT NULL, last_opened_at REAL
        )
        """)
        try raw("CREATE TABLE IF NOT EXISTS package_assets(app_id TEXT NOT NULL,asset_id TEXT NOT NULL,media_type TEXT NOT NULL,data BLOB NOT NULL,sha256 TEXT NOT NULL,PRIMARY KEY(app_id,asset_id))")
        try raw("CREATE TABLE IF NOT EXISTS records(app_id TEXT NOT NULL,collection_id TEXT NOT NULL,record_id TEXT NOT NULL,payload BLOB NOT NULL,created_at REAL NOT NULL,updated_at REAL NOT NULL,PRIMARY KEY(app_id,collection_id,record_id))")
        try raw("CREATE TABLE IF NOT EXISTS runtime_values(app_id TEXT NOT NULL,key TEXT NOT NULL,value BLOB NOT NULL,PRIMARY KEY(app_id,key))")
        try raw("CREATE TABLE IF NOT EXISTS permission_decisions(app_id TEXT NOT NULL,capability TEXT NOT NULL,decision TEXT NOT NULL,PRIMARY KEY(app_id,capability))")
        try raw("CREATE TABLE IF NOT EXISTS activity_events(id INTEGER PRIMARY KEY AUTOINCREMENT,app_id TEXT,level TEXT NOT NULL,category TEXT NOT NULL,message TEXT NOT NULL,payload BLOB,created_at REAL NOT NULL)")
        try raw("PRAGMA user_version=1")
    }

    private enum Binding { case text(String), data(Data), double(Double), int(Int32), null }

    private func execute(_ sql: String, bindings: [Binding] = []) throws {
        var statement: OpaquePointer?
        try prepare(sql, into: &statement)
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() { bind(binding, statement, Int32(offset + 1)) }
        try stepDone(statement)
    }

    private func raw(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.query(lastError) }
    }

    private func transaction(_ work: () throws -> Void) throws {
        try raw("BEGIN IMMEDIATE")
        do { try work(); try raw("COMMIT") }
        catch { try? raw("ROLLBACK"); throw error }
    }

    private func prepare(_ sql: String, into statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.query(lastError) }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query(lastError) }
    }

    private var lastError: String { database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error" }

    private func bind(_ binding: Binding, _ statement: OpaquePointer?, _ index: Int32) {
        switch binding {
        case .text(let value): bind(value, statement, index)
        case .data(let value): bind(value, statement, index)
        case .double(let value): sqlite3_bind_double(statement, index, value)
        case .int(let value): sqlite3_bind_int(statement, index, value)
        case .null: sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: String, _ statement: OpaquePointer?, _ index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bind(_ value: Data, _ statement: OpaquePointer?, _ index: Int32) {
        _ = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), SQLITE_TRANSIENT) }
    }

    private func text(_ statement: OpaquePointer?, column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private func blob(_ statement: OpaquePointer?, column: Int32) -> Data? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL, let pointer = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
