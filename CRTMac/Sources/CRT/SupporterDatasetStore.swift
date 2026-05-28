import Foundation
import SQLite3

private let supporterSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SupporterDatasetStore {
    static let schemaVersion = "3"

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
                event_open = ?,
                event_close = ?,
                event_volume = ?,
                event_dollar_volume = ?,
                peak_at = ?,
                market_session = ?,
                minutes_to_peak = ?,
                performance_1m = ?,
                performance_5m = ?,
                performance_15m = ?,
                performance_60m = ?,
                close_from_baseline_percent = ?,
                close_from_peak_percent = ?,
                outcome_label = ?,
                risk_label = ?,
                news_count = ?,
                filing_count = ?,
                dilution_forms = ?,
                evidence_summary = ?,
                verified_at = ?,
                verification_note = ?
            WHERE id = ?;
            """
        try withStatement(sql) { statement in
            bindText(result.qualifies ? SupporterCandidateStatus.qualifies.rawValue : SupporterCandidateStatus.comparison.rawValue, at: 1, statement: statement)
            sqlite3_bind_double(statement, 2, result.baselinePrice)
            sqlite3_bind_double(statement, 3, result.peakPrice)
            sqlite3_bind_double(statement, 4, result.changePercent)
            sqlite3_bind_double(statement, 5, result.eventOpen)
            sqlite3_bind_double(statement, 6, result.eventClose)
            sqlite3_bind_double(statement, 7, result.eventVolume)
            sqlite3_bind_double(statement, 8, result.eventDollarVolume)
            sqlite3_bind_double(statement, 9, result.peakAt.timeIntervalSince1970)
            bindText(result.marketSession, at: 10, statement: statement)
            sqlite3_bind_double(statement, 11, result.minutesToPeak)
            bindOptionalDouble(result.performance1Minute, at: 12, statement: statement)
            bindOptionalDouble(result.performance5Minutes, at: 13, statement: statement)
            bindOptionalDouble(result.performance15Minutes, at: 14, statement: statement)
            bindOptionalDouble(result.performance60Minutes, at: 15, statement: statement)
            sqlite3_bind_double(statement, 16, result.closeFromBaselinePercent)
            sqlite3_bind_double(statement, 17, result.closeFromPeakPercent)
            bindText(result.outcomeLabel, at: 18, statement: statement)
            bindText(result.riskLabel, at: 19, statement: statement)
            sqlite3_bind_int(statement, 20, Int32(result.newsCount))
            sqlite3_bind_int(statement, 21, Int32(result.filingCount))
            bindOptionalText(result.dilutionForms, at: 22, statement: statement)
            bindText(result.evidenceSummary, at: 23, statement: statement)
            sqlite3_bind_double(statement, 24, Date().timeIntervalSince1970)
            bindText(result.note, at: 25, statement: statement)
            bindText(id, at: 26, statement: statement)
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
                change_percent, event_open, event_close, event_volume, event_dollar_volume,
                peak_at, market_session, minutes_to_peak, performance_1m, performance_5m,
                performance_15m, performance_60m, close_from_baseline_percent,
                close_from_peak_percent, outcome_label, risk_label, news_count, filing_count,
                dilution_forms, evidence_summary, verified_at, verification_note
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
                eventOpen: optionalDouble(statement, at: 8),
                eventClose: optionalDouble(statement, at: 9),
                eventVolume: optionalDouble(statement, at: 10),
                eventDollarVolume: optionalDouble(statement, at: 11),
                peakAt: optionalDouble(statement, at: 12).map(Date.init(timeIntervalSince1970:)),
                marketSession: optionalText(statement, at: 13),
                minutesToPeak: optionalDouble(statement, at: 14),
                performance1Minute: optionalDouble(statement, at: 15),
                performance5Minutes: optionalDouble(statement, at: 16),
                performance15Minutes: optionalDouble(statement, at: 17),
                performance60Minutes: optionalDouble(statement, at: 18),
                closeFromBaselinePercent: optionalDouble(statement, at: 19),
                closeFromPeakPercent: optionalDouble(statement, at: 20),
                outcomeLabel: optionalText(statement, at: 21),
                riskLabel: optionalText(statement, at: 22),
                newsCount: Int(sqlite3_column_int(statement, 23)),
                filingCount: Int(sqlite3_column_int(statement, 24)),
                dilutionForms: optionalText(statement, at: 25),
                evidenceSummary: optionalText(statement, at: 26),
                verifiedAt: optionalDouble(statement, at: 27).map(Date.init(timeIntervalSince1970:)),
                verificationNote: optionalText(statement, at: 28)
            ))
        }
        return candidates
    }

    func exportCSV(to url: URL) throws {
        let header = "symbol,event_date,status,baseline_price,peak_price,change_percent,event_open,event_close,event_volume,event_dollar_volume,peak_at_et,market_session,minutes_to_peak,performance_1m,performance_5m,performance_15m,performance_60m,close_from_baseline_percent,close_from_peak_percent,outcome_label,risk_label,news_count,filing_count,dilution_forms,evidence_summary,note,verification_note"
        let rows = try fetchCandidates().map(csvRow)
        try ([header] + rows).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvRow(for candidate: SupporterCandidate) -> String {
        var fields: [String] = []
        fields.append(candidate.symbol)
        fields.append(candidate.eventDate ?? "")
        fields.append(candidate.status.rawValue)
        fields.append(csvDouble(candidate.baselinePrice))
        fields.append(csvDouble(candidate.peakPrice))
        fields.append(csvDouble(candidate.changePercent))
        fields.append(csvDouble(candidate.eventOpen))
        fields.append(csvDouble(candidate.eventClose))
        fields.append(csvDouble(candidate.eventVolume))
        fields.append(csvDouble(candidate.eventDollarVolume))
        fields.append(candidate.peakAt.map { DateFormatter.displayEastern.string(from: $0) } ?? "")
        fields.append(candidate.marketSession ?? "")
        fields.append(csvDouble(candidate.minutesToPeak))
        fields.append(csvDouble(candidate.performance1Minute))
        fields.append(csvDouble(candidate.performance5Minutes))
        fields.append(csvDouble(candidate.performance15Minutes))
        fields.append(csvDouble(candidate.performance60Minutes))
        fields.append(csvDouble(candidate.closeFromBaselinePercent))
        fields.append(csvDouble(candidate.closeFromPeakPercent))
        fields.append(candidate.outcomeLabel ?? "")
        fields.append(candidate.riskLabel ?? "")
        fields.append(String(candidate.newsCount))
        fields.append(String(candidate.filingCount))
        fields.append(candidate.dilutionForms ?? "")
        fields.append(candidate.evidenceSummary ?? "")
        fields.append(candidate.note)
        fields.append(candidate.verificationNote ?? "")
        return fields.map(csvEscape).joined(separator: ",")
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
                event_open REAL,
                event_close REAL,
                event_volume REAL,
                event_dollar_volume REAL,
                peak_at REAL,
                market_session TEXT,
                minutes_to_peak REAL,
                performance_1m REAL,
                performance_5m REAL,
                performance_15m REAL,
                performance_60m REAL,
                close_from_baseline_percent REAL,
                close_from_peak_percent REAL,
                outcome_label TEXT,
                risk_label TEXT,
                news_count INTEGER DEFAULT 0,
                filing_count INTEGER DEFAULT 0,
                dilution_forms TEXT,
                evidence_summary TEXT,
                created_at REAL NOT NULL,
                verified_at REAL,
                verification_note TEXT
            );
            """)
        try addColumnIfNeeded("event_open", definition: "REAL")
        try addColumnIfNeeded("event_close", definition: "REAL")
        try addColumnIfNeeded("event_volume", definition: "REAL")
        try addColumnIfNeeded("event_dollar_volume", definition: "REAL")
        try addColumnIfNeeded("peak_at", definition: "REAL")
        try addColumnIfNeeded("market_session", definition: "TEXT")
        try addColumnIfNeeded("minutes_to_peak", definition: "REAL")
        try addColumnIfNeeded("performance_1m", definition: "REAL")
        try addColumnIfNeeded("performance_5m", definition: "REAL")
        try addColumnIfNeeded("performance_15m", definition: "REAL")
        try addColumnIfNeeded("performance_60m", definition: "REAL")
        try addColumnIfNeeded("close_from_baseline_percent", definition: "REAL")
        try addColumnIfNeeded("close_from_peak_percent", definition: "REAL")
        try addColumnIfNeeded("outcome_label", definition: "TEXT")
        try addColumnIfNeeded("risk_label", definition: "TEXT")
        try addColumnIfNeeded("news_count", definition: "INTEGER DEFAULT 0")
        try addColumnIfNeeded("filing_count", definition: "INTEGER DEFAULT 0")
        try addColumnIfNeeded("dilution_forms", definition: "TEXT")
        try addColumnIfNeeded("evidence_summary", definition: "TEXT")
        try execute("CREATE INDEX IF NOT EXISTS idx_supporter_date ON candidate_events(event_date DESC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_supporter_status ON candidate_events(status);")
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

    private func addColumnIfNeeded(_ column: String, definition: String) throws {
        guard try !hasColumn(column, in: "candidate_events") else { return }
        try execute("ALTER TABLE candidate_events ADD COLUMN \(column) \(definition);")
    }

    private func hasColumn(_ column: String, in table: String) throws -> Bool {
        var found = false
        try withRows("PRAGMA table_info(\(table));") { statement in
            if columnText(statement, at: 1) == column {
                found = true
            }
        }
        return found
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

    private func bindOptionalDouble(_ value: Double?, at index: Int32, statement: OpaquePointer) {
        if let value {
            sqlite3_bind_double(statement, index, value)
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

    private func csvDouble(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.4f", value)
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
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
