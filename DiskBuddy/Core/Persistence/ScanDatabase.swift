import Foundation
import SQLite3

// MARK: - T8 SQLite scan index (actor-isolated, transactional, batched reads)
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
// - writes inside one atomic transaction per scan ✓
// - actor isolation; ScanEngine never imports SQLite ✓ (it doesn't)
// - failed writes never break scans (callers use try?) ✓
// - delete/rebuild safe (deleteAllScans + deleteDatabaseFile) ✓
// - retention: newest 5 scans / ≤14 days, pruned on save + load ✓
//   (one scan writes ~166 MB of scan_files rows on a 400k-record index and
//    nothing ever called deleteAllScans, so history grew without bound)
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
    private let schemaVersion = 2

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
                    mtime REAL NOT NULL DEFAULT 0,
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
                "PRAGMA user_version = 2",
            ])
            return
        }
        if current < 2 {
            // v1 file_hashes lacked mtime: add it (defaults 0 = always stale
            // until re-hashed — safe direction).
            try exec("ALTER TABLE file_hashes ADD COLUMN mtime REAL NOT NULL DEFAULT 0")
            try exec("PRAGMA user_version = 2")
        }
    }

    // MARK: Writes (transactional, cancellable)

    func saveScan(root: ScanNode, records: [ScannedRecord], label: String, elapsed: Double) throws {
        try Task.checkCancellation()
        try open()
        let id = UUID().uuidString
        let treeData = try JSONEncoder().encode(root)
        let treeJSON = String(data: treeData, encoding: .utf8) ?? "{}"
        try Task.checkCancellation()
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
            // The scan ID never changes. Reset retains bindings, so bind it
            // once instead of allocating/copying it for every record.
            bindText(stmt, 1, id)
            for (index, record) in records.enumerated() {
                if index % 256 == 0 { try Task.checkCancellation() }
                bindText(stmt, 2, record.path)
                sqlite3_bind_int64(stmt, 3, record.bytes)
                sqlite3_bind_int64(stmt, 4, record.physical)
                sqlite3_bind_double(stmt, 5, record.modified.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 6, record.isDirectory ? 1 : 0)
                bindText(stmt, 7, record.category.rawValue)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw ScanDatabaseError.execFailed(lastError())
                }
                sqlite3_reset(stmt)
            }
            // Avoid repeated durable commits every 5,000 rows. More
            // importantly, cancellation/failure rolls back the whole scan,
            // rather than leaving a cached tree with an incomplete index.
            try Task.checkCancellation()
            try run("INSERT OR REPLACE INTO metadata(key, value) VALUES('last_scan_id', ?)", bind: { self.bindText($0, 1, id) })
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
        // Retention on save, outside the transaction: a pruning failure must
        // never roll back or mask the scan that was just written (callers
        // treat any throw as "save failed"). The next save retries the prune.
        try? pruneExpiredScans()
    }

    func storeHash(path: String, size: Int64, mtime: Date, sha256: String) throws {
        try open()
        try run("INSERT OR REPLACE INTO file_hashes(path, size, mtime, sha256, updated) VALUES(?,?,?,?,?)", bind: {
            self.bindText($0, 1, path)
            self.bindInt($0, 2, size)
            self.bindDouble($0, 3, mtime.timeIntervalSince1970)
            self.bindText($0, 4, sha256)
            self.bindDouble($0, 5, Date().timeIntervalSince1970)
        })
    }

    /// Validated lookup: path + size + mtime must all match, otherwise the
    /// file changed and the hash is stale (caller re-hashes; REPLACE on store
    /// lazily evicts the stale row).
    func cachedHash(path: String, size: Int64, mtime: Date) throws -> String? {
        try open()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT sha256, size, mtime FROM file_hashes WHERE path = ?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ScanDatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, path)
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        guard sqlite3_column_int64(stmt, 1) == size,
              abs(sqlite3_column_double(stmt, 2) - mtime.timeIntervalSince1970) < 1.0
        else { return nil }
        return String(cString: text)
    }

    // MARK: Reads (batched, no giant blobs)

    func latestScan() throws -> CachedScan? {
        try open()
        // Retention on load: an install that never scans again must not keep
        // carrying dead scan blobs, and the rows read below must be ones that
        // survived the prune (the newest scan is always exempt, so hydration
        // in AppState.restoreCachedScan still finds a scan here).
        try? pruneExpiredScans()
        var stmt: OpaquePointer?
        // `id DESC` breaks same-second ties deterministically so this query
        // and `pruneExpiredScans` agree on which scan is "the newest" —
        // otherwise hydration could ask for a scan the prune just removed.
        let sql = "SELECT id, root_path, label, date, total_bytes, file_count, elapsed, tree_json FROM scans ORDER BY date DESC, id DESC LIMIT 1"
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
        try Task.checkCancellation()
        guard limit > 0, offset >= 0 else { return [] }
        try open()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT path, bytes, physical, modified, is_dir, category FROM scan_files WHERE scan_id = ? ORDER BY rowid LIMIT ? OFFSET ?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ScanDatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, scanID)
        sqlite3_bind_int64(stmt, 2, Int64(limit))
        sqlite3_bind_int64(stmt, 3, Int64(offset))
        var records: [ScannedRecord] = []
        var rowsRead = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            if rowsRead % 256 == 0 { try Task.checkCancellation() }
            rowsRead += 1
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

    // MARK: Retention (bounded disk growth)

    /// Why this exists: each scan appends its full record set to `scan_files`
    /// (~166 MB per scan on this machine's 4 scans → a 665 MB Cache.sqlite),
    /// and `deleteAllScans()` has no callers — without a policy the database
    /// grew by one whole scan's worth of rows for every scan, forever.
    private static let maxRetainedScans = 5
    /// Scans older than this are dropped even when they rank inside
    /// `maxRetainedScans` — "5 most recent OR 14 days, whichever is fewer".
    private static let maxScanAge: TimeInterval = 14 * 86_400

    /// Keeps only the intersection of the two rules — the newest
    /// `maxRetainedScans` scans AND those younger than `maxScanAge`, i.e.
    /// "5 most recent OR 14 days, whichever is fewer" — except the single
    /// newest scan, which is kept unconditionally: launch hydration reads it
    /// and must never come back empty just because the user hasn't rescanned
    /// in two weeks.
    private func pruneExpiredScans() throws {
        try open()
        guard ((try? queryScalarInt("SELECT COUNT(*) FROM scans")) ?? 0) > 1 else { return }
        let cutoff = Date().timeIntervalSince1970 - Self.maxScanAge
        // `id DESC` is the deterministic same-second tiebreak (scans.date has
        // one-second resolution); latestScan() uses the same order so both
        // sides always agree on which row is "the newest".
        let newest = "(SELECT id FROM scans ORDER BY date DESC, id DESC LIMIT 1)"
        let top = "(SELECT id FROM scans ORDER BY date DESC, id DESC LIMIT \(Self.maxRetainedScans))"
        let victims = """
            SELECT id FROM scans
            WHERE id <> \(newest)
              AND (date < ? OR id NOT IN \(top))
            """
        try exec("BEGIN IMMEDIATE")
        do {
            // Blob rows first: both statements re-evaluate the same predicate
            // against an unchanged `scans` table, so no scan_files rows are
            // left behind for a scan this transaction deletes, and none are
            // removed for a scan that survives.
            try run("DELETE FROM scan_files WHERE scan_id IN (\(victims))", bind: { self.bindDouble($0, 1, cutoff) })
            try run("DELETE FROM scans WHERE id IN (\(victims))", bind: { self.bindDouble($0, 1, cutoff) })
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
        // No VACUUM on purpose: freed pages are reused by the next scan, so
        // the file plateaus at the retained set's size instead of growing.
        // VACUUM would rewrite the whole (multi-hundred-MB) file on the actor.
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
        // SQLite copies before withCString returns; no autoreleased NSString
        // bridge is kept alive across a large insertion loop.
        _ = value.withCString { sqlite3_bind_text(stmt, index, $0, -1, SQLITE_TRANSIENT_VALUE) }
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
