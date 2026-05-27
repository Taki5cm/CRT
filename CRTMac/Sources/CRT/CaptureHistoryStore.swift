import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class CaptureHistoryStore {
    static let schemaVersion = "2"

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
        let databaseURL = directory.appendingPathComponent("capture-history.sqlite")

        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw CaptureHistoryError.database(message: errorMessage)
        }
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func record(alert: LiveAlert, monitoringMode: LiveMonitoringMode) throws {
        let sql = """
            INSERT OR IGNORE INTO capture_events (
                id, symbol, detected_at, direction, baseline_price, detected_price,
                change_percent, dollar_volume, window_seconds, feed, monitoring_mode,
                market_session, end_price, max_price, min_price, latest_observed_at, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'tracking');
            """
        try withStatement(sql) { statement in
            bindText(alert.id.uuidString, at: 1, statement: statement)
            bindText(alert.symbol, at: 2, statement: statement)
            sqlite3_bind_double(statement, 3, alert.detectedAt.timeIntervalSince1970)
            bindText(alert.direction.rawValue, at: 4, statement: statement)
            sqlite3_bind_double(statement, 5, alert.baselinePrice)
            sqlite3_bind_double(statement, 6, alert.latestPrice)
            sqlite3_bind_double(statement, 7, alert.changePercent)
            sqlite3_bind_double(statement, 8, alert.dollarVolume)
            sqlite3_bind_int(statement, 9, Int32(alert.windowSeconds))
            bindText(alert.feed.rawValue, at: 10, statement: statement)
            bindText(monitoringMode.rawValue, at: 11, statement: statement)
            bindText(marketSession(for: alert.detectedAt), at: 12, statement: statement)
            sqlite3_bind_double(statement, 13, alert.latestPrice)
            sqlite3_bind_double(statement, 14, alert.latestPrice)
            sqlite3_bind_double(statement, 15, alert.latestPrice)
            sqlite3_bind_double(statement, 16, alert.detectedAt.timeIntervalSince1970)
        }
    }

    @discardableResult
    func updatePerformance(for trade: LiveTrade) throws -> Bool {
        let time = trade.occurredAt.timeIntervalSince1970
        let sql = """
            UPDATE capture_events SET
                end_price = ?,
                latest_observed_at = ?,
                max_price = MAX(max_price, ?),
                min_price = MIN(min_price, ?),
                performance_1m = CASE
                    WHEN performance_1m IS NULL AND ? - detected_at >= 60
                    THEN ((? - detected_price) / detected_price) * 100
                    ELSE performance_1m END,
                performance_5m = CASE
                    WHEN performance_5m IS NULL AND ? - detected_at >= 300
                    THEN ((? - detected_price) / detected_price) * 100
                    ELSE performance_5m END,
                performance_15m = CASE
                    WHEN performance_15m IS NULL AND ? - detected_at >= 900
                    THEN ((? - detected_price) / detected_price) * 100
                    ELSE performance_15m END,
                status = CASE
                    WHEN ? - detected_at >= 900 THEN 'completed'
                    ELSE status END
            WHERE symbol = ?
                AND status = 'tracking'
                AND detected_at <= ?
                AND detected_at >= ?;
            """
        try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, trade.price)
            sqlite3_bind_double(statement, 2, time)
            sqlite3_bind_double(statement, 3, trade.price)
            sqlite3_bind_double(statement, 4, trade.price)
            sqlite3_bind_double(statement, 5, time)
            sqlite3_bind_double(statement, 6, trade.price)
            sqlite3_bind_double(statement, 7, time)
            sqlite3_bind_double(statement, 8, trade.price)
            sqlite3_bind_double(statement, 9, time)
            sqlite3_bind_double(statement, 10, trade.price)
            sqlite3_bind_double(statement, 11, time)
            bindText(trade.symbol, at: 12, statement: statement)
            sqlite3_bind_double(statement, 13, time)
            sqlite3_bind_double(statement, 14, time - (30 * 60))
        }
        return sqlite3_changes(database) > 0
    }

    func expireStaleRecords(asOf date: Date = Date()) throws {
        let sql = """
            UPDATE capture_events
            SET status = 'incomplete'
            WHERE status = 'tracking' AND detected_at < ?;
            """
        try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970 - (30 * 60))
        }
    }

    func saveCatalystReport(_ report: CatalystResearchReport, captureID: String) throws {
        let data = try JSONEncoder.captureHistory.encode(report)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CaptureHistoryError.database(message: "2차 보고를 저장 가능한 형태로 바꾸지 못했습니다.")
        }
        let sql = "UPDATE capture_events SET catalyst_report_json = ? WHERE id = ?;"
        try withStatement(sql) { statement in
            bindText(json, at: 1, statement: statement)
            bindText(captureID, at: 2, statement: statement)
        }
    }

    func fetchRecords(limit: Int? = 200) throws -> [CaptureRecord] {
        let limitClause = limit.map { " LIMIT \($0)" } ?? ""
        let sql = """
            SELECT id, symbol, detected_at, direction, baseline_price, detected_price,
                change_percent, dollar_volume, window_seconds, feed, monitoring_mode,
                market_session, end_price, max_price, min_price, latest_observed_at,
                performance_1m, performance_5m, performance_15m, status, catalyst_report_json
            FROM capture_events
            ORDER BY detected_at DESC\(limitClause);
            """
        var records: [CaptureRecord] = []
        try withRows(sql) { statement in
            records.append(CaptureRecord(
                id: columnText(statement, at: 0),
                symbol: columnText(statement, at: 1),
                detectedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                direction: LiveMoveDirection(rawValue: columnText(statement, at: 3)) ?? .rising,
                baselinePrice: sqlite3_column_double(statement, 4),
                detectedPrice: sqlite3_column_double(statement, 5),
                changePercent: sqlite3_column_double(statement, 6),
                dollarVolume: sqlite3_column_double(statement, 7),
                windowSeconds: Int(sqlite3_column_int(statement, 8)),
                feed: LiveDataFeed(rawValue: columnText(statement, at: 9)) ?? .iex,
                monitoringMode: LiveMonitoringMode(rawValue: columnText(statement, at: 10)) ?? .watchlistIEX,
                marketSession: columnText(statement, at: 11),
                endPrice: sqlite3_column_double(statement, 12),
                maxPrice: sqlite3_column_double(statement, 13),
                minPrice: sqlite3_column_double(statement, 14),
                latestObservedAt: optionalDate(statement, at: 15),
                performance1Minute: optionalDouble(statement, at: 16),
                performance5Minutes: optionalDouble(statement, at: 17),
                performance15Minutes: optionalDouble(statement, at: 18),
                status: CaptureTrackingStatus(rawValue: columnText(statement, at: 19)) ?? .tracking,
                catalystReport: catalystReport(statement, at: 20)
            ))
        }
        return records
    }

    func exportCSV(to url: URL) throws {
        let records = try fetchRecords(limit: nil)
        let header = "symbol,detected_at_et,direction,session,feed,monitoring_mode,window_seconds,detected_price,trigger_percent,dollar_volume,performance_1m,performance_5m,performance_15m,max_advance_percent,max_drawdown_percent,status,research_status,market_cap,share_class_shares_outstanding,weighted_shares_outstanding,dilution_forms,news_headlines,filing_forms"
        let rows = records.map(csvRow)
        try ([header] + rows).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvRow(for record: CaptureRecord) -> String {
        let report = record.catalystReport
        var fields: [String] = []
        fields.append(record.symbol)
        fields.append(DateFormatter.captureExport.string(from: record.detectedAt))
        fields.append(record.direction.label)
        fields.append(record.marketSession)
        fields.append(record.feed.rawValue.uppercased())
        fields.append(record.monitoringMode.label)
        fields.append(String(record.windowSeconds))
        fields.append(decimal(record.detectedPrice))
        fields.append(decimal(record.changePercent))
        fields.append(decimal(record.dollarVolume))
        fields.append(optionalDecimal(record.performance1Minute))
        fields.append(optionalDecimal(record.performance5Minutes))
        fields.append(optionalDecimal(record.performance15Minutes))
        fields.append(decimal(record.maxAdvancePercent))
        fields.append(decimal(record.maxDrawdownPercent))
        fields.append(record.status.label)
        fields.append(report?.status.label ?? "")
        fields.append(optionalDecimal(report?.marketCap))
        fields.append(optionalDecimal(report?.shareClassSharesOutstanding))
        fields.append(optionalDecimal(report?.weightedSharesOutstanding))
        fields.append(report?.dilutionForms.joined(separator: " | ") ?? "")
        fields.append(report?.news.map(\.headline).joined(separator: " | ") ?? "")
        fields.append(report?.filings.map(\.form).joined(separator: " | ") ?? "")
        return fields.map(csvEscape).joined(separator: ",")
    }

    private func migrate() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS capture_events (
                id TEXT PRIMARY KEY NOT NULL,
                symbol TEXT NOT NULL,
                detected_at REAL NOT NULL,
                direction TEXT NOT NULL,
                baseline_price REAL NOT NULL,
                detected_price REAL NOT NULL,
                change_percent REAL NOT NULL,
                dollar_volume REAL NOT NULL,
                window_seconds INTEGER NOT NULL,
                feed TEXT NOT NULL,
                monitoring_mode TEXT NOT NULL,
                market_session TEXT NOT NULL,
                end_price REAL NOT NULL,
                max_price REAL NOT NULL,
                min_price REAL NOT NULL,
                latest_observed_at REAL,
                performance_1m REAL,
                performance_5m REAL,
                performance_15m REAL,
                status TEXT NOT NULL,
                catalyst_report_json TEXT
            );
            """)
        if try hasColumn("catalyst_report_json", in: "capture_events") == false {
            try execute("ALTER TABLE capture_events ADD COLUMN catalyst_report_json TEXT;")
        }
        try execute("CREATE INDEX IF NOT EXISTS idx_capture_symbol_status ON capture_events(symbol, status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_capture_detected_at ON capture_events(detected_at DESC);")
        let sql = "INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', ?);"
        try withStatement(sql) { statement in
            bindText(Self.schemaVersion, at: 1, statement: statement)
        }
    }

    private func marketSession(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        switch minutes {
        case 240..<570: return "프리마켓"
        case 570..<960: return "정규장"
        case 960..<1200: return "애프터마켓"
        default: return "장외 시간"
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw CaptureHistoryError.database(message: errorMessage)
        }
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

    private func withStatement(_ sql: String, action: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CaptureHistoryError.database(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try action(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CaptureHistoryError.database(message: errorMessage)
        }
    }

    private func withRows(_ sql: String, action: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CaptureHistoryError.database(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            action(statement)
        }
    }

    private func bindText(_ value: String, at index: Int32, statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String {
        guard let characters = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: characters)
    }

    private func optionalDouble(_ statement: OpaquePointer, at index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }

    private func optionalDate(_ statement: OpaquePointer, at index: Int32) -> Date? {
        optionalDouble(statement, at: index).map(Date.init(timeIntervalSince1970:))
    }

    private func catalystReport(_ statement: OpaquePointer, at index: Int32) -> CatalystResearchReport? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let json = columnText(statement, at: index)
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder.captureHistory.decode(CatalystResearchReport.self, from: data)
    }

    private var errorMessage: String {
        guard let database, let raw = sqlite3_errmsg(database) else { return "알 수 없는 저장 오류" }
        return String(cString: raw)
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func optionalDecimal(_ value: Double?) -> String {
        value.map(decimal) ?? ""
    }

    private func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum CaptureHistoryError: LocalizedError {
    case database(message: String)

    var errorDescription: String? {
        switch self {
        case .database(let message):
            return "포착 기록 저장소를 사용할 수 없습니다: \(message)"
        }
    }
}

extension DateFormatter {
    static let captureExport: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension JSONEncoder {
    static let captureHistory: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let captureHistory: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
