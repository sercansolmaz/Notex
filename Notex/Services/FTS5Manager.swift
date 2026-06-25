import Foundation
import SQLite3

/// Thread-safe FTS5 full-text search manager.
/// Reads: queue.sync (need result immediately, FTS5 is sub-ms).
/// Writes: queue.async (non-blocking, fire-and-forget).
final class FTS5Manager: @unchecked Sendable {
    static let shared = FTS5Manager()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.sercansolmaz.notex.fts", qos: .utility)

    // SQLite transient destructor constant — tells SQLite to copy the bound string.
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        openDatabase()
        createTable()
    }

    // MARK: - Setup

    private func openDatabase() {
        let dbPath = ftsDatabasePath()
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("⚠️ FTS5: Failed to open database at \(dbPath)")
            db = nil
        }
    }

    private func createTable() {
        let sql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
            uuid UNINDEXED,
            title,
            content,
            tokenize='unicode61'
        );
        """
        executeWrite(sql)
    }

    private func ftsDatabasePath() -> String {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent("Notex", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("fts.sqlite").path
    }

    // MARK: - Low-level

    private func executeWrite(_ sql: String) {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Public API

    func indexNote(uuid: String, title: String, content: String) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            self.deleteNoteSync(uuid: uuid)

            let sql = "INSERT INTO notes_fts (uuid, title, content) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, uuid, -1, self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, title, -1, self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, content, -1, self.SQLITE_TRANSIENT)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func deleteNote(uuid: String) {
        queue.async { [weak self] in
            self?.deleteNoteSync(uuid: uuid)
        }
    }

    private func deleteNoteSync(uuid: String) {
        guard let db = db else { return }
        let sql = "DELETE FROM notes_fts WHERE uuid = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, uuid, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func search(_ query: String) -> Set<String> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Set<String>() }

        return queue.sync {
            guard let db = self.db else { return Set<String>() }
            var results = Set<String>()
            let escaped = trimmed.replacingOccurrences(of: "\"", with: "")
            let sql = "SELECT uuid FROM notes_fts WHERE notes_fts MATCH ? ORDER BY rank;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let matchQuery = "\"\(escaped)\"*"
                sqlite3_bind_text(stmt, 1, matchQuery, -1, self.SQLITE_TRANSIENT)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(stmt, 0) {
                        results.insert(String(cString: cString))
                    }
                }
            }
            sqlite3_finalize(stmt)
            return results
        }
    }

    func reindexAll(notes: [(uuid: String, title: String, content: String)]) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            self.executeWrite("DELETE FROM notes_fts;")
            for note in notes {
                let sql = "INSERT INTO notes_fts (uuid, title, content) VALUES (?, ?, ?);"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, note.uuid, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, note.title, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 3, note.content, -1, self.SQLITE_TRANSIENT)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
        }
    }
}
