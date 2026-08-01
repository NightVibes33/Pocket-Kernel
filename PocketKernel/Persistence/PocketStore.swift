import Foundation
import SQLite3

actor PocketStore {
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool = false) throws {
        let path: String
        if inMemory { path = ":memory:" } else {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "PocketKernel", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            path = root.appending(path: "pocketkernel.sqlite").path
        }
        guard sqlite3_open(path, &database) == SQLITE_OK else { throw StoreError.open }
        let migration = "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; CREATE TABLE IF NOT EXISTS installed_apps (id TEXT PRIMARY KEY NOT NULL, manifest BLOB NOT NULL, favorite INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL, updated_at REAL NOT NULL); CREATE TABLE IF NOT EXISTS records (app_id TEXT NOT NULL, collection_id TEXT NOT NULL, record_id TEXT NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL, PRIMARY KEY(app_id, collection_id, record_id)); PRAGMA user_version=1;"
        guard sqlite3_exec(database, migration, nil, nil, nil) == SQLITE_OK else { throw StoreError.query }
    }

    deinit { sqlite3_close(database) }

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
        let sql = "INSERT OR REPLACE INTO installed_apps(id,manifest,favorite,created_at,updated_at) VALUES(?,?,COALESCE((SELECT favorite FROM installed_apps WHERE id=?),0),?,?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }
        let id = manifest.id.uuidString
        bind(id, to: statement, at: 1); data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        bind(id, to: statement, at: 3); sqlite3_bind_double(statement, 4, manifest.createdAt.timeIntervalSince1970); sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
    }

    func delete(_ id: UUID) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM installed_apps WHERE id=?", -1, &statement, nil) == SQLITE_OK else { throw StoreError.query }
        defer { sqlite3_finalize(statement) }; bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.query }
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

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) { sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
enum StoreError: Error { case open, query, limit }
