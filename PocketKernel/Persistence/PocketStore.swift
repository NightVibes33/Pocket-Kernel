import Foundation
import SQLite3

private final class SQLiteHandle: @unchecked Sendable {
    var pointer: OpaquePointer?
    deinit { sqlite3_close(pointer) }
}

actor PocketStore {
    private let handle: SQLiteHandle
    private var database: OpaquePointer? { handle.pointer }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool = false) throws {
        let handle = SQLiteHandle()
        self.handle = handle
        let path: String
        if inMemory { path = ":memory:" } else {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "PocketKernel", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            path = root.appending(path: "pocketkernel.sqlite").path
        }
        guard sqlite3_open(path, &handle.pointer) == SQLITE_OK else { throw StoreError.open }
        let migration = "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; CREATE TABLE IF NOT EXISTS installed_apps (id TEXT PRIMARY KEY NOT NULL, manifest BLOB NOT NULL, previous_manifest BLOB, favorite INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL, updated_at REAL NOT NULL); CREATE TABLE IF NOT EXISTS records (app_id TEXT NOT NULL, collection_id TEXT NOT NULL, record_id TEXT NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL, PRIMARY KEY(app_id, collection_id, record_id)); CREATE TABLE IF NOT EXISTS runtime_values (app_id TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY(app_id,key)); CREATE TABLE IF NOT EXISTS permission_decisions (app_id TEXT NOT NULL, capability TEXT NOT NULL, decision TEXT NOT NULL, PRIMARY KEY(app_id,capability)); CREATE TABLE IF NOT EXISTS activity_events (id INTEGER PRIMARY KEY AUTOINCREMENT, app_id TEXT, level TEXT NOT NULL, category TEXT NOT NULL, message TEXT NOT NULL, payload BLOB, created_at REAL NOT NULL); PRAGMA user_version=1;"
        guard sqlite3_exec(handle.pointer, migration, nil, nil, nil) == SQLITE_OK else { throw StoreError.query }
    }

    func installedApps() throws -> [MicroAppManifest] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT manifest FROM installed_apps ORDER BY updated_at DESC", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }
        var apps: [MicroAppManifest] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            if let app = try? decoder.decode(MicroAppManifest.self, from: data) { apps.append(app) }
        }
        return apps
    }

    func install(_ manifest: MicroAppManifest) throws {
        let data = try encoder.encode(manifest)
        var statement: OpaquePointer?
        let sql = "INSERT INTO installed_apps(id,manifest,previous_manifest,favorite,created_at,updated_at) VALUES(?,?,NULL,0,?,?) ON CONFLICT(id) DO UPDATE SET previous_manifest=installed_apps.manifest,manifest=excluded.manifest,updated_at=excluded.updated_at"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }
        let id = manifest.id.uuidString
        bind(id, to: statement, at: 1); data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        sqlite3_bind_double(statement, 3, manifest.createdAt.timeIntervalSince1970); sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
    }

    func delete(_ id: UUID) throws {
        try transaction {
            for table in ["records", "runtime_values", "permission_decisions", "installed_apps"] {
                var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "DELETE FROM \(table) WHERE \(table == "installed_apps" ? "id" : "app_id")=?", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
                bind(id.uuidString, to: statement, at: 1); defer { sqlite3_finalize(statement) }
                guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
            }
        }
    }

    func records(appID: UUID, collectionID: String) throws -> [PocketRecord] {
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM records WHERE app_id=? AND collection_id=? ORDER BY updated_at DESC LIMIT 5000"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }
        bind(appID.uuidString, to: statement, at: 1); bind(collectionID, to: statement, at: 2)
        var records: [PocketRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            if let record = try? decoder.decode(PocketRecord.self, from: data) { records.append(record) }
        }
        return records
    }

    func save(record: PocketRecord, appID: UUID) throws {
        let countSQL = "SELECT COUNT(*) FROM records WHERE app_id=? AND collection_id=?"
        var countStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, countSQL, -1, &countStatement, nil) == SQLITE_OK else { throw StoreError.query }
        bind(appID.uuidString, to: countStatement, at: 1); bind(record.collectionID, to: countStatement, at: 2)
        defer { sqlite3_finalize(countStatement) }
        guard sqlite3_step(countStatement) == SQLITE_ROW else { throw StoreError.query }
        guard sqlite3_column_int(countStatement, 0) < PocketLimits.recordsPerCollection else { throw StoreError.limit }

        let data = try encoder.encode(record)
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO records(app_id,collection_id,record_id,payload,created_at,updated_at) VALUES(?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }
        bind(appID.uuidString, to: statement, at: 1); bind(record.collectionID, to: statement, at: 2); bind(record.id.uuidString, to: statement, at: 3)
        data.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        sqlite3_bind_double(statement, 5, record.createdAt.timeIntervalSince1970); sqlite3_bind_double(statement, 6, record.updatedAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
    }

    func deleteRecord(appID: UUID, collectionID: String, recordID: UUID) throws {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "DELETE FROM records WHERE app_id=? AND collection_id=? AND record_id=?", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }; bind(appID.uuidString, to: statement, at: 1); bind(collectionID, to: statement, at: 2); bind(recordID.uuidString, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
    }

    func runtimeValue(appID: UUID, key: String) throws -> PocketValue? {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "SELECT value FROM runtime_values WHERE app_id=? AND key=?", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }; bind(appID.uuidString, to: statement, at: 1); bind(key, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return try decoder.decode(PocketValue.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }

    func setRuntimeValue(_ value: PocketValue?, appID: UUID, key: String) throws {
        if let value {
            let data = try encoder.encode(value); var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO runtime_values(app_id,key,value) VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
            defer { sqlite3_finalize(statement) }; bind(appID.uuidString, to: statement, at: 1); bind(key, to: statement, at: 2); data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
        } else {
            var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "DELETE FROM runtime_values WHERE app_id=? AND key=?", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
            defer { sqlite3_finalize(statement) }; bind(appID.uuidString, to: statement, at: 1); bind(key, to: statement, at: 2); guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
        }
    }

    func permission(appID: UUID, capability: PocketCapability) throws -> PermissionDecision {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "SELECT decision FROM permission_decisions WHERE app_id=? AND capability=?", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }; bind(appID.uuidString, to: statement, at: 1); bind(capability.rawValue, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return .notRequested }
        return PermissionDecision(rawValue: String(cString: raw)) ?? .notRequested
    }

    func setPermission(_ decision: PermissionDecision, appID: UUID, capability: PocketCapability) throws {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO permission_decisions(app_id,capability,decision) VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }; bind(appID.uuidString, to: statement, at: 1); bind(capability.rawValue, to: statement, at: 2); bind(decision.rawValue, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
    }

    func log(appID: UUID?, level: ActivityEvent.Level, category: String, message: String, payload: PocketValue? = nil) throws {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "INSERT INTO activity_events(app_id,level,category,message,payload,created_at) VALUES(?,?,?,?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }; if let appID { bind(appID.uuidString, to: statement, at: 1) } else { sqlite3_bind_null(statement, 1) }
        bind(level.rawValue, to: statement, at: 2); bind(category, to: statement, at: 3); bind(message, to: statement, at: 4)
        if let payload { let data = try encoder.encode(payload); data.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) } } else { sqlite3_bind_null(statement, 5) }
        sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970); guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
    }

    func activity(limit: Int = 250) throws -> [ActivityEvent] {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, "SELECT id,app_id,level,category,message,payload,created_at FROM activity_events ORDER BY id DESC LIMIT ?", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }; sqlite3_bind_int(statement, 1, Int32(min(max(limit, 1), 1_000))); var events: [ActivityEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0); let appID = sqlite3_column_text(statement, 1).flatMap { UUID(uuidString: String(cString: $0)) }
            let level = sqlite3_column_text(statement, 2).flatMap { ActivityEvent.Level(rawValue: String(cString: $0)) } ?? .info
            let category = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "runtime"; let message = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            var payload: PocketValue?; if let bytes = sqlite3_column_blob(statement, 5) { payload = try? decoder.decode(PocketValue.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 5)))) }
            events.append(.init(id: id, appID: appID, level: level, category: category, message: message, payload: payload, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))))
        }
        return events
    }

    func reset() throws {
        try transaction { for table in ["records", "runtime_values", "permission_decisions", "activity_events", "installed_apps"] { guard sqlite3_exec(database, "DELETE FROM \(table)", nil, nil, nil) == SQLITE_OK else { throw StoreError.query } } }
    }

    private func transaction(_ work: () throws -> Void) throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw StoreError.query }
        do { try work(); guard sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw StoreError.query } }
        catch { sqlite3_exec(database, "ROLLBACK", nil, nil, nil); throw error }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) { sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
enum StoreError: Error { case open, query, limit }
