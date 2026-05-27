import Foundation
import SQLite3

private let supporterSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SupporterDatasetStore {
    static let schemaVersion = "1"

    private var database: OpaquePointer?

    init() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("CRT", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("supporter-training.sqlite")
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw SupporterDatasetError.database(message: errorMessage)
        }
        try migrate()
        try installSeedQueueIfNeeded()
    }

    deinit {
        sqlite3_close(database)
    }

    func addCandidate(symbol: String, eventDate: String?, note: String) throws {
        let normalized = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let sql = """
            INSERT INTO candidate_events (id, symbol, event_date, note, status, created_at)
            VALUES (?, ?, ?, ?, 'pending', ?);
            """
        try withStatement(sql) { statement in
            bindText(UUID().uuidString, at: 1, statement: statement)
            bindText(normalized, at: 2, statement: statement)
            bindOptionalText(eventDate, at: 3, statement: statement)
            bindText(note, at: 4, statement: statement)
            sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        }
    }

    func saveVerification(_ result: SupporterVerificationResult, for id: String) throws {
        let sql = """
            UPDATE candidate_events SET
                status = ?,
                baseline_price = ?,
                peak_price = ?,
                change_percent = ?,
                verified_at = ?,
                verification_note = ?
            WHERE id = ?;
            """
        try withStatement(sql) { statement in
            bindText(result.qualifies ? SupporterCandidateStatus.qualifies.rawValue : SupporterCandidateStatus.comparison.rawValue, at: 1, statement: statement)
            sqlite3_bind_double(statement, 2, result.baselinePrice)
            sqlite3_bind_double(statement, 3, result.peakPrice)
            sqlite3_bind_double(statement, 4, result.changePercent)
            sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
            bindText(result.note, at: 6, statement: statement)
            bindText(id, at: 7, statement: statement)
        }
    }

    func markFailed(id: String, note: String) throws {
        let sql = """
            UPDATE candidate_events SET status = 'failed', verified_at = ?, verification_note = ?
            WHERE id = ?;
            """
        try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
            bindText(note, at: 2, statement: statement)
            bindText(id, at: 3, statement: statement)
        }
    }

    func fetchCandidates() throws -> [SupporterCandidate] {
        let sql = """
            SELECT id, symbol, event_date, note, status, baseline_price, peak_price,
                change_percent, verified_at, verification_note
            FROM candidate_events ORDER BY created_at DESC;
            """
        var candidates: [SupporterCandidate] = []
        try withRows(sql) { statement in
            candidates.append(SupporterCandidate(
                id: columnText(statement, at: 0),
                symbol: columnText(statement, at: 1),
                eventDate: optionalText(statement, at: 2),
                note: columnText(statement, at: 3),
                status: SupporterCandidateStatus(rawValue: columnText(statement, at: 4)) ?? .pending,
                baselinePrice: optionalDouble(statement, at: 5),
                peakPrice: optionalDouble(statement, at: 6),
                changePercent: optionalDouble(statement, at: 7),
                verifiedAt: optionalDouble(statement, at: 8).map(Date.init(timeIntervalSince1970:)),
                verificationNote: optionalText(statement, at: 9)
            ))
        }
        return candidates
    }

    private func installSeedQueueIfNeeded() throws {
        var count = 0
        try withRows("SELECT COUNT(*) FROM candidate_events;") { statement in
            count = Int(sqlite3_column_int(statement, 0))
        }
        guard count == 0 else { return }
        try addCandidate(symbol: "BIRD", eventDate: nil, note: "Allbirds / NewBird AI 관련 사용자 제시 후보")
        try addCandidate(symbol: "ASTC", eventDate: nil, note: "Astrotech 관련 사용자 제시 후보")
        try addCandidate(symbol: "AIXI", eventDate: nil, note: "Xiao-I 관련 사용자 제시 후보")
    }

    private func migrate() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS candidate_events (
                id TEXT PRIMARY KEY NOT NULL,
                symbol TEXT NOT NULL,
                event_date TEXT,
                note TEXT NOT NULL,
                status TEXT NOT NULL,
                baseline_price REAL,
                peak_price REAL,
                change_percent REAL,
                created_at REAL NOT NULL,
                verified_at REAL,
                verification_note TEXT
            );
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_supporter_date ON candidate_events(event_date DESC);")
        try withStatement("INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', ?);") { statement in
            bindText(Self.schemaVersion, at: 1, statement: statement)
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SupporterDatasetError.database(message: errorMessage)
        }
    }

    private func withStatement(_ sql: String, action: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SupporterDatasetError.database(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try action(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SupporterDatasetError.database(message: errorMessage)
        }
    }

    private func withRows(_ sql: String, action: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SupporterDatasetError.database(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            action(statement)
        }
    }

    private func bindText(_ value: String, at index: Int32, statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, supporterSQLiteTransient)
    }

    private func bindOptionalText(_ value: String?, at index: Int32, statement: OpaquePointer) {
        if let value {
            bindText(value, at: index, statement: statement)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, at index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : columnText(statement, at: index)
    }

    private func optionalDouble(_ statement: OpaquePointer, at index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }

    private var errorMessage: String {
        guard let database, let raw = sqlite3_errmsg(database) else { return "알 수 없는 저장 오류" }
        return String(cString: raw)
    }
}

enum SupporterDatasetError: LocalizedError {
    case database(message: String)

    var errorDescription: String? {
        switch self {
        case .database(let message):
            return "학습 데이터 저장소를 사용할 수 없습니다: \(message)"
        }
    }
}
