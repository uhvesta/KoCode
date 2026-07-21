import CSQLite
import Foundation

public enum SQLiteDatabaseError: Error, LocalizedError, Equatable {
    case open(String)
    case execute(String)
    case prepare(String)
    case bind(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message): return "Could not open AvestaCode database: \(message)"
        case .execute(let message): return "SQLite execution failed: \(message)"
        case .prepare(let message): return "SQLite statement preparation failed: \(message)"
        case .bind(let message): return "SQLite value binding failed: \(message)"
        }
    }
}

public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    var string: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var int: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    var double: Double? {
        switch self {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    var data: Data? {
        if case .blob(let value) = self { return value }
        return nil
    }
}

public struct SQLiteRow: Sendable {
    private let values: [String: SQLiteValue]

    init(values: [String: SQLiteValue]) { self.values = values }

    public subscript(_ column: String) -> SQLiteValue { values[column] ?? .null }
}

public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw SQLiteDatabaseError.open(message)
        }
        handle = database
        sqlite3_busy_timeout(database, 5_000)
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    public func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteDatabaseError.execute(errorMessage)
        }
    }

    public func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw SQLiteDatabaseError.execute(errorMessage) }

            var values: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    values[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    values[name] = .real(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    values[name] = sqlite3_column_text(statement, index).map { .text(String(cString: $0)) } ?? .null
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, index))
                    values[name] = sqlite3_column_blob(statement, index).map { .blob(Data(bytes: $0, count: count)) } ?? .blob(Data())
                default:
                    values[name] = .null
                }
            }
            rows.append(SQLiteRow(values: values))
        }
    }

    public func scalarInt(_ sql: String, bindings: [SQLiteValue] = []) throws -> Int64? {
        try query(sql, bindings: bindings).first?["value"].int
    }

    public func transaction<T>(_ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try operation()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle else { throw SQLiteDatabaseError.prepare("database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteDatabaseError.prepare(errorMessage)
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .real(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, transient)
            case .blob(let data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), transient)
                }
            }
            guard result == SQLITE_OK else { throw SQLiteDatabaseError.bind(errorMessage) }
        }
    }

    private var errorMessage: String {
        handle.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "unknown error"
    }
}

public enum AvestaSchema {
    public static let currentVersion = 3

    public static func migrate(_ database: SQLiteDatabase) throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            )
            """)
        try database.transaction {
            var version = Int(try database.scalarInt("SELECT COALESCE(MAX(version), 0) AS value FROM schema_migrations") ?? 0)
            if version < 1 {
                try createVersionOne(database)
                try database.execute("INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)", bindings: [.integer(1), .real(Date().timeIntervalSince1970)])
                version = 1
            }
            if version < 2 {
                try database.execute("ALTER TABLE repository_sources ADD COLUMN default_base_branch TEXT NOT NULL DEFAULT 'origin/main'")
                try database.execute("INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)", bindings: [.integer(2), .real(Date().timeIntervalSince1970)])
                version = 2
            }
            if version < 3 {
                try database.execute("ALTER TABLE repository_sources ADD COLUMN sort_index INTEGER NOT NULL DEFAULT 0")
                try database.execute("UPDATE repository_sources SET sort_index = rowid - 1")
                try database.execute("INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)", bindings: [.integer(3), .real(Date().timeIntervalSince1970)])
            }
        }
    }

    private static func createVersionOne(_ database: SQLiteDatabase) throws {
        let statements = [
            """
            CREATE TABLE workspaces (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE,
                sort_index INTEGER NOT NULL, created_at REAL NOT NULL, active_activity_session_id TEXT
            )
            """,
            """
            CREATE TABLE repository_sources (
                id TEXT PRIMARY KEY, canonical_remote_url TEXT NOT NULL UNIQUE,
                display_remote_url TEXT NOT NULL, cache_path TEXT NOT NULL UNIQUE,
                created_at REAL NOT NULL, last_fetched_at REAL
            )
            """,
            """
            CREATE TABLE workspace_repositories (
                id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                source_id TEXT NOT NULL REFERENCES repository_sources(id) ON DELETE RESTRICT,
                name TEXT NOT NULL, worktree_path TEXT NOT NULL UNIQUE, branch TEXT NOT NULL,
                base_branch TEXT, sort_index INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE workspace_activity_sessions (
                id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                started_at REAL NOT NULL, ended_at REAL, baseline_snapshot_id TEXT
            )
            """,
            """
            CREATE TABLE tabs (
                id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                kind TEXT NOT NULL CHECK(kind IN ('terminal','review')), title TEXT NOT NULL,
                sort_index INTEGER NOT NULL, repository_id TEXT REFERENCES workspace_repositories(id) ON DELETE SET NULL,
                working_directory TEXT, created_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE workspace_layouts (
                workspace_id TEXT PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
                primary_tab_id TEXT REFERENCES tabs(id) ON DELETE SET NULL,
                companion_tab_id TEXT REFERENCES tabs(id) ON DELETE SET NULL,
                focused_tab_id TEXT REFERENCES tabs(id) ON DELETE SET NULL,
                split_ratio REAL NOT NULL DEFAULT 0.5
            )
            """,
            """
            CREATE TABLE terminal_sessions (
                tab_id TEXT PRIMARY KEY REFERENCES tabs(id) ON DELETE CASCADE,
                working_directory TEXT NOT NULL, startup_input TEXT, resume_provider TEXT,
                resume_identifier TEXT, scrollback_kind TEXT NOT NULL, scrollback_lines INTEGER
            )
            """,
            """
            CREATE TABLE terminal_events (
                id TEXT PRIMARY KEY, tab_id TEXT NOT NULL REFERENCES tabs(id) ON DELETE CASCADE,
                kind TEXT NOT NULL, summary TEXT NOT NULL, metadata TEXT, created_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE review_sessions (
                id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                activity_session_id TEXT NOT NULL REFERENCES workspace_activity_sessions(id) ON DELETE CASCADE,
                started_at REAL NOT NULL, completed_at REAL, final_snapshot_id TEXT
            )
            """,
            """
            CREATE TABLE review_snapshots (
                id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                activity_session_id TEXT NOT NULL REFERENCES workspace_activity_sessions(id) ON DELETE CASCADE,
                review_session_id TEXT REFERENCES review_sessions(id) ON DELETE SET NULL,
                fingerprint TEXT NOT NULL, reason TEXT NOT NULL, created_at REAL NOT NULL,
                UNIQUE(workspace_id, fingerprint)
            )
            """,
            """
            CREATE TABLE snapshot_blobs (
                content_hash TEXT PRIMARY KEY, codec TEXT NOT NULL, original_size INTEGER NOT NULL,
                content BLOB NOT NULL
            )
            """,
            """
            CREATE TABLE review_snapshot_repositories (
                snapshot_id TEXT NOT NULL REFERENCES review_snapshots(id) ON DELETE CASCADE,
                repository_id TEXT NOT NULL REFERENCES workspace_repositories(id) ON DELETE CASCADE,
                head_oid TEXT, branch TEXT NOT NULL,
                PRIMARY KEY(snapshot_id, repository_id)
            )
            """,
            """
            CREATE TABLE review_snapshot_files (
                snapshot_id TEXT NOT NULL, repository_id TEXT NOT NULL, path TEXT NOT NULL,
                status TEXT NOT NULL, old_path TEXT, old_blob_hash TEXT NOT NULL REFERENCES snapshot_blobs(content_hash),
                new_blob_hash TEXT NOT NULL REFERENCES snapshot_blobs(content_hash),
                patch_blob_hash TEXT NOT NULL REFERENCES snapshot_blobs(content_hash), fingerprint TEXT NOT NULL,
                PRIMARY KEY(snapshot_id, repository_id, path),
                FOREIGN KEY(snapshot_id, repository_id) REFERENCES review_snapshot_repositories(snapshot_id, repository_id) ON DELETE CASCADE
            )
            """,
            """
            CREATE TABLE review_annotations (
                id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                activity_session_id TEXT NOT NULL REFERENCES workspace_activity_sessions(id),
                review_session_id TEXT NOT NULL REFERENCES review_sessions(id),
                repository_id TEXT NOT NULL REFERENCES workspace_repositories(id),
                snapshot_id TEXT NOT NULL REFERENCES review_snapshots(id), kind TEXT NOT NULL,
                file_path TEXT NOT NULL, side TEXT NOT NULL, start_line INTEGER NOT NULL, end_line INTEGER NOT NULL,
                anchor_fingerprint TEXT NOT NULL, selected_code TEXT NOT NULL, surrounding_context TEXT NOT NULL,
                user_text TEXT NOT NULL, response TEXT, created_at REAL NOT NULL, resolved_at REAL, is_outdated INTEGER NOT NULL DEFAULT 0
            )
            """,
            """
            CREATE TABLE assistant_threads (
                id TEXT PRIMARY KEY, annotation_id TEXT NOT NULL REFERENCES review_annotations(id) ON DELETE CASCADE,
                provider TEXT NOT NULL, provider_session_id TEXT, model TEXT, created_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE assistant_messages (
                id TEXT PRIMARY KEY, thread_id TEXT NOT NULL REFERENCES assistant_threads(id) ON DELETE CASCADE,
                role TEXT NOT NULL, content TEXT NOT NULL, is_streaming INTEGER NOT NULL,
                error_code TEXT, created_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE notifications (
                id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                tab_id TEXT REFERENCES tabs(id) ON DELETE CASCADE, title TEXT NOT NULL, body TEXT NOT NULL,
                created_at REAL NOT NULL, read_at REAL
            )
            """,
            """
            CREATE TABLE settings (
                key TEXT PRIMARY KEY, value BLOB NOT NULL, updated_at REAL NOT NULL
            )
            """,
            "CREATE INDEX review_snapshots_timeline ON review_snapshots(workspace_id, created_at DESC)",
            "CREATE INDEX annotations_by_file ON review_annotations(workspace_id, repository_id, file_path)",
            "CREATE INDEX tabs_in_workspace ON tabs(workspace_id, sort_index)",
            "CREATE INDEX repositories_in_workspace ON workspace_repositories(workspace_id, sort_index)"
        ]
        for statement in statements { try database.execute(statement) }
    }
}
