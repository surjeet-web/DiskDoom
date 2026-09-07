import Foundation
import SQLite3

// MARK: - T8 SQLite scan index (actor-isolated, transactional, batched)
//
// Persistence map (existing layers untouched):
//   UserDefaults → settings/preferences
//   Keychain     → license/secrets
//   Snapshots/   → user-facing historical scan JSON
//   Cache.sqlite → expensive, queryable scan/cache data (THIS FILE)
//
// Acceptance mapping:
// - DB under Application Support ✓, schema_version + migrations ✓
// - scans + scan_files tables, indexes on scans(root_path) and
//   scan_files(scan_id) ✓, file_hashes + metadata ✓
// - latest scan retrievable without touching the filesystem ✓
// - files load in LIMIT/OFFSET batches, never one giant blob ✓
// - writes inside transactions (chunked commits) ✓
// - actor isolation; ScanEngine never imports SQLite ✓ (it doesn't)
// - failed writes never break scans (callers use try?) ✓
// - delete/rebuild safe (deleteAllScans + deleteDatabaseFile) ✓
// - apps/app_artifacts/query_results tables exist as reserved schemas.

private let SQLITE_TRANSIENT_VALUE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct CachedScan: Sendable {
    let id: String
    let rootPath: String
    let label: String
    let date: Date
    let totalBytes: Int64
    let fileCount: Int
    let elapsed: Double
    let tree: ScanNode?
}

enum ScanDatabaseError: Error {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case decodeFailed
}

actor ScanDatabase {
    static let shared = ScanDatabase()

    // Handle is only ever touched from actor-isolated methods or deinit-after-
    // last-use, so unchecked sharing out of deinit is sound.
    nonisolated(unsafe) private var db: OpaquePointer?
    private let dbURL: URL
    private let schemaVersion = 1

    init(dbURL: URL? = nil) {
        if let dbURL {
            self.dbURL = dbURL
        } else {
            self.dbURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/DiskBuddy/Cache.sqlite", isDirectory: false)
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: Open + migrate

    private func open() throws {
        if db != nil { return }
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw ScanDatabaseError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
        try migrate()
    }

    private func migrate() throws {
        let current = (try? queryScalarInt("PRAGMA user_version")) ?? 0
        if current < 1 {
            try execBatch([
                """
                CREATE TABLE IF NOT EXISTS scans(
                    id TEXT PRIMARY KEY,
                    root_path TEXT NOT NULL,
                    label TEXT NOT NULL,
                    date REAL NOT NULL,
                    total_bytes INTEGER NOT NULL,
                    file_count INTEGER NOT NULL,
                    elapsed REAL NOT NULL,
                    tree_json TEXT
                )
                """,
                "CREATE INDEX IF NOT EXISTS idx_scans_root ON scans(root_path)",
                """
                CREATE TABLE IF NOT EXISTS scan_files(
                    scan_id TEXT NOT NULL,
                    path TEXT NOT NULL,
                    bytes INTEGER NOT NULL,
                    physical INTEGER NOT NULL,
                    modified REAL NOT NULL,
                    is_dir INTEGER NOT NULL,
                    category TEXT NOT NULL
                )
                """,
                "CREATE INDEX IF NOT EXISTS idx_files_scan ON scan_files(scan_id)",
                """
                CREATE TABLE IF NOT EXISTS file_hashes(
                    path TEXT PRIMARY KEY,
                    size INTEGER NOT NULL,
                    sha256 TEXT NOT NULL,
                    updated REAL NOT NULL
                )
                """,
                "CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)",
                // Reserved schemas for the future repository split (unused in T8).
                "CREATE TABLE IF NOT EXISTS apps(bundle_id TEXT PRIMARY KEY, name TEXT NOT NULL, bundle_bytes INTEGER NOT NULL, artifact_bytes INTEGER NOT NULL, updated REAL NOT NULL)",
                "CREATE TABLE IF NOT EXISTS app_artifacts(bundle_id TEXT NOT NULL, path TEXT NOT NULL, bytes INTEGER NOT NULL, kind TEXT NOT NULL)",
                "CREATE INDEX IF NOT EXISTS idx_artifacts_bundle ON app_artifacts(bundle_id)",
                "CREATE TABLE IF NOT EXISTS query_results(id TEXT PRIMARY KEY, kind TEXT NOT NULL, created REAL NOT NULL, payload TEXT NOT NULL)",
                "PRAGMA user_version = 1",
            ])
        }
    }

    // MARK: Writes (transactional, chunked)

    func saveScan(root: ScanNode, records: [ScannedRecord], label: String, elapsed: Double) throws {
        try open()
        let id = UUID().uuidString
        let treeData = try JSONEncoder().encode(root)
        let treeJSON = String(data: treeData, encoding: .utf8) ?? "{}"
        try exec("BEGIN IMMEDIATE")
        do {
            try run(
                "INSERT INTO scans(id, root_path, label, date, total_bytes, file_count, elapsed, tree_json) VALUES(?,?,?,?,?,?,?,?)",
                bind: { stmt in
                    self.bindText(stmt, 1, id)
                    self.bindText(stmt, 2, root.path)
                    self.bindText(stmt, 3, label)
                    self.bindInt(stmt, 4, Int64(Date().timeIntervalSince1970))
                    self.bindInt(stmt, 5, root.sizeBytes)
                    self.bindInt(stmt, 6, Int64(root.fileCount))
                    self.bindDouble(stmt, 7, elapsed)
                    self.bindText(stmt, 8, treeJSON)
                })
            let insert = "INSERT INTO scan_files(scan_id, path, bytes, physical, modified, is_dir, category) VALUES(?,?,?,?,?,?,?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                throw ScanDatabaseError.prepareFailed(lastError())
            }
            defer { sqlite3_finalize(stmt) }
            var sinceCommit = 0
            for record in records {
                sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
                sqlite3_bind_text(stmt, 2, (record.path as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
                sqlite3_bind_int64(stmt, 3, record.bytes)
                sqlite3_bind_int64(stmt, 4, record.physical)
                sqlite3_bind_double(stmt, 5, record.modified.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 6, record.isDirectory ? 1 : 0)
                sqlite3_bind_text(stmt, 7, (record.category.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw ScanDatabaseError.execFailed(lastError())
                }
                sqlite3_reset(stmt)
                sinceCommit += 1
                if sinceCommit >= 5000 {
                    try exec("COMMIT")
                    try exec("BEGIN IMMEDIATE")
                    sinceCommit = 0
                }
            }
            try run("INSERT OR REPLACE INTO metadata(key, value) VALUES('last_scan_id', ?)", bind: { self.bindText($0, 1, id) })
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    func storeHash(path: String, size: Int64, sha256: String) throws {
        try open()
        try run("INSERT OR REPLACE INTO file_hashes(path, size, sha256, updated) VALUES(?,?,?,?)", bind: {
            self.bindText($0, 1, path)
            self.bindInt($0, 2, size)
            self.bindText($0, 3, sha256)
            self.bindDouble($0, 4, Date().timeIntervalSince1970)
        })
    }

    func cachedHash(path: String) throws -> String? {
        try open()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT sha256 FROM file_hashes WHERE path = ?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ScanDatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, path)
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }

    // MARK: Reads (batched, no giant blobs)

    func latestScan() throws -> CachedScan? {
        try open()
        var stmt: OpaquePointer?
        let sql = "SELECT id, root_path, label, date, total_bytes, file_count, elapsed, tree_json FROM scans ORDER BY date DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ScanDatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let tree: ScanNode?
        if let text = sqlite3_column_text(stmt, 7) {
            let json = String(cString: text)
            tree = try? JSONDecoder().decode(ScanNode.self, from: Data(json.utf8))
        } else {
            tree = nil
        }
        return CachedScan(
            id: columnText(stmt, 0), rootPath: columnText(stmt, 1), label: columnText(stmt, 2),
            date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
            totalBytes: sqlite3_column_int64(stmt, 4), fileCount: Int(sqlite3_column_int64(stmt, 5)),
            elapsed: sqlite3_column_double(stmt, 6), tree: tree)
    }

    func fileCount(scanID: String) throws -> Int {
        try open()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM scan_files WHERE scan_id = ?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ScanDatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, scanID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func loadFiles(scanID: String, limit: Int, offset: Int) throws -> [ScannedRecord] {
        try open()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT path, bytes, physical, modified, is_dir, category FROM scan_files WHERE scan_id = ? ORDER BY rowid LIMIT ? OFFSET ?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ScanDatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, scanID)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        sqlite3_bind_int(stmt, 3, Int32(offset))
        var records: [ScannedRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let category = NodeCategory(rawValue: columnText(stmt, 5)) else { continue }
            records.append(ScannedRecord(
                path: columnText(stmt, 0),
                bytes: sqlite3_column_int64(stmt, 1),
                physical: sqlite3_column_int64(stmt, 2),
                modified: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                isDirectory: sqlite3_column_int(stmt, 4) != 0,
                category: category))
        }
        return records
    }

    // MARK: Delete / rebuild (always safe)

    func deleteScan(id: String) throws {
        try open()
        try exec("BEGIN IMMEDIATE")
        do {
            try run("DELETE FROM scan_files WHERE scan_id = ?", bind: { self.bindText($0, 1, id) })
            try run("DELETE FROM scans WHERE id = ?", bind: { self.bindText($0, 1, id) })
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    func deleteAllScans() throws {
        try open()
        try exec("DELETE FROM scan_files")
        try exec("DELETE FROM scans")
        try exec("DELETE FROM metadata WHERE key = 'last_scan_id'")
    }

    func deleteDatabaseFile() throws {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
        try FileManager.default.removeItem(at: dbURL)
    }

    // MARK: Low-level helpers

    private func lastError() -> String {
        guard let db else { return "no database" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errMsg) }
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            throw ScanDatabaseError.execFailed(errMsg.map { String(cString: $0) } ?? lastError())
        }
    }

    private func execBatch(_ statements: [String]) throws {
        for sql in statements { try exec(sql) }
    }

    private func run(_ sql: String, bind: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ScanDatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw ScanDatabaseError.execFailed(lastError())
        }
    }

    private func queryScalarInt(_ sql: String) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ScanDatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
    }

    private func bindInt(_ stmt: OpaquePointer, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }

    private func bindDouble(_ stmt: OpaquePointer, _ index: Int32, _ value: Double) {
        sqlite3_bind_double(stmt, index, value)
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: text)
    }
}
