import Foundation

actor MarketService {
    private let session: URLSession
    private let easternTimeZone = TimeZone(identifier: "America/New_York")!
    private let detailLimit = 4

    init(session: URLSession = .shared) {
        self.session = session
    }

    func scanWholeMarket(
        massiveKey: String,
        secEmail: String,
        date: String,
        rules: ScanRules
    ) async throws -> AnalysisResult {
        guard !massiveKey.isEmpty else {
            throw AnalysisError.missingCredential("설정에서 Massive API Key를 먼저 저장해주세요.")
        }
        let daily = try await massiveGroupedDaily(apiKey: massiveKey, date: date)
        let shortlist = daily.compactMap { bar -> DailyCandidate? in
            guard bar.otc != true, bar.low >= rules.minimumPrice, bar.low > 0 else { return nil }
            let move = (bar.high - bar.low) / bar.low * 100
            let dollars = bar.volume * (bar.vwap ?? bar.close)
            guard move >= rules.thresholdPercent, dollars >= rules.minimumDollarVolume else { return nil }
            return DailyCandidate(symbol: bar.ticker, move: move, dollars: dollars)
        }
        .sorted { $0.move > $1.move }

        var minuteBars: [String: [MinuteBar]] = [:]
        for candidate in shortlist.prefix(detailLimit) {
            minuteBars[candidate.symbol] = try await massiveMinuteBars(
                apiKey: massiveKey,
                symbol: candidate.symbol,
                date: date
            )
        }
        let candidates = detectMinuteCandidates(barsBySymbol: minuteBars, date: date, rules: rules)
        var warnings: [String] = []
        let filings: [String: [FilingEvidence]]
        do {
            filings = try await fetchFilings(
                symbols: Array(Set(candidates.map(\.symbol))),
                date: date,
                email: secEmail
            )
        } catch {
            warnings.append("SEC 공시를 불러오지 못했습니다: \(error.localizedDescription)")
            filings = [:]
        }
        let reports = candidates.map {
            report(candidate: $0, filings: filings[$0.symbol] ?? [], news: [])
        }
        return AnalysisResult(
            mode: .wholeMarket,
            date: date,
            reports: reports,
            checkedSymbols: daily.count,
            minuteBarsChecked: minuteBars.values.reduce(0) { $0 + $1.count },
            shortlistedSymbols: shortlist.count,
            warnings: warnings,
            methodology: "전체시장 일봉으로 후보를 좁힌 뒤 상위 \(detailLimit)개만 1분봉으로 재검사합니다. 무료 호출 한도에 맞춘 방식이라 모든 장중 급등을 복원하지는 않습니다."
        )
    }

    func analyzeWatchlist(
        alpacaKey: String,
        alpacaSecret: String,
        secEmail: String,
        date: String,
        symbols: [String],
        rules: ScanRules
    ) async throws -> AnalysisResult {
        guard !alpacaKey.isEmpty, !alpacaSecret.isEmpty else {
            throw AnalysisError.missingCredential("설정에서 Alpaca API Key와 Secret Key를 먼저 저장해주세요.")
        }
        guard !symbols.isEmpty, symbols.count <= 30 else {
            throw AnalysisError.invalidInput("관심종목은 1개 이상 30개 이하로 입력해주세요.")
        }
        let bars = try await alpacaMinuteBars(
            key: alpacaKey,
            secret: alpacaSecret,
            symbols: symbols,
            date: date
        )
        let candidates = detectMinuteCandidates(barsBySymbol: bars, date: date, rules: rules)
        let candidateSymbols = Array(Set(candidates.map(\.symbol)))
        var warnings: [String] = []
        let news: [String: [NewsEvidence]]
        do {
            news = try await alpacaNews(
                key: alpacaKey,
                secret: alpacaSecret,
                symbols: candidateSymbols,
                date: date
            )
        } catch {
            warnings.append("과거 뉴스를 불러오지 못했습니다: \(error.localizedDescription)")
            news = [:]
        }
        let filings: [String: [FilingEvidence]]
        do {
            filings = try await fetchFilings(symbols: candidateSymbols, date: date, email: secEmail)
        } catch {
            warnings.append("SEC 공시를 불러오지 못했습니다: \(error.localizedDescription)")
            filings = [:]
        }
        let reports = candidates.map {
            report(candidate: $0, filings: filings[$0.symbol] ?? [], news: nearbyNews(news[$0.symbol] ?? [], candidate: $0))
        }
        return AnalysisResult(
            mode: .watchlist,
            date: date,
            reports: reports,
            checkedSymbols: symbols.count,
            minuteBarsChecked: bars.values.reduce(0) { $0 + $1.count },
            shortlistedSymbols: nil,
            warnings: warnings,
            methodology: "입력한 종목의 SIP 과거 1분봉에서 저가-고가 변동을 검사하고, 급변 시점 주변 뉴스와 당일 SEC 공시를 연결합니다. 체결 순서나 당시 매수 가능성을 의미하지 않습니다."
        )
    }

    private func report(candidate: MinuteCandidate, filings: [FilingEvidence], news: [NewsEvidence]) -> AnalysisReport {
        let classification: AnalysisReport.Classification = !filings.isEmpty ? .filingFound : (!news.isEmpty ? .newsFound : .unexplained)
        return AnalysisReport(
            symbol: candidate.symbol,
            session: candidate.session,
            detectedAt: candidate.detectedAt,
            baselinePrice: candidate.baselinePrice,
            peakPrice: candidate.peakPrice,
            changePercent: candidate.move,
            dollarVolume: candidate.dollarVolume,
            classification: classification,
            filings: filings,
            news: news
        )
    }

    private func detectMinuteCandidates(
        barsBySymbol: [String: [MinuteBar]],
        date: String,
        rules: ScanRules
    ) -> [MinuteCandidate] {
        var output: [MinuteCandidate] = []
        for (symbol, bars) in barsBySymbol {
            let sameDay = bars.filter { easternDate($0.timestamp) == date }.sorted { $0.timestamp < $1.timestamp }
            var cooldownUntil = Date.distantPast
            for (index, bar) in sameDay.enumerated() where bar.timestamp >= cooldownUntil {
                guard let sessionName = marketSession(bar.timestamp), bar.high >= rules.minimumPrice else { continue }
                let start = bar.timestamp.addingTimeInterval(TimeInterval(-rules.windowSeconds + 60))
                let window = sameDay[0...index].filter { $0.timestamp >= start }
                guard let low = window.map(\.low).min(), low > 0,
                      let high = window.map(\.high).max() else { continue }
                let move = (high - low) / low * 100
                let dollars = window.reduce(0) { $0 + $1.volume * ($1.vwap ?? $1.close) }
                guard move >= rules.thresholdPercent, dollars >= rules.minimumDollarVolume else { continue }
                output.append(MinuteCandidate(
                    symbol: symbol,
                    session: sessionName,
                    detectedAt: bar.timestamp,
                    baselinePrice: low,
                    peakPrice: high,
                    move: move,
                    dollarVolume: dollars
                ))
                cooldownUntil = bar.timestamp.addingTimeInterval(300)
            }
        }
        return output.sorted { $0.move > $1.move }
    }

    private func nearbyNews(_ news: [NewsEvidence], candidate: MinuteCandidate) -> [NewsEvidence] {
        let lower = candidate.detectedAt.addingTimeInterval(-86_400)
        let upper = candidate.detectedAt.addingTimeInterval(3_600)
        return news.filter { $0.createdAt >= lower && $0.createdAt <= upper }.prefix(3).map { $0 }
    }

    private func massiveGroupedDaily(apiKey: String, date: String) async throws -> [MassiveDailyBar] {
        var components = URLComponents(string: "https://api.massive.com/v2/aggs/grouped/locale/us/market/stocks/\(date)")!
        components.queryItems = [
            URLQueryItem(name: "adjusted", value: "true"),
            URLQueryItem(name: "apiKey", value: apiKey)
        ]
        let data: MassiveResponse<MassiveDailyBar> = try await json(url: components.url!, headers: [:], name: "Massive 전체시장 자료")
        return data.results ?? []
    }

    private func massiveMinuteBars(apiKey: String, symbol: String, date: String) async throws -> [MinuteBar] {
        var components = URLComponents(string: "https://api.massive.com/v2/aggs/ticker/\(symbol)/range/1/minute/\(date)/\(date)")!
        components.queryItems = [
            URLQueryItem(name: "adjusted", value: "true"),
            URLQueryItem(name: "sort", value: "asc"),
            URLQueryItem(name: "limit", value: "50000"),
            URLQueryItem(name: "apiKey", value: apiKey)
        ]
        let data: MassiveResponse<MassiveMinuteBar> = try await json(url: components.url!, headers: [:], name: "Massive \(symbol) 분봉")
        return (data.results ?? []).map { $0.minuteBar }
    }

    private func alpacaMinuteBars(key: String, secret: String, symbols: [String], date: String) async throws -> [String: [MinuteBar]] {
        var components = URLComponents(string: "https://data.alpaca.markets/v2/stocks/bars")!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
            URLQueryItem(name: "timeframe", value: "1Min"),
            URLQueryItem(name: "start", value: "\(date)T00:00:00Z"),
            URLQueryItem(name: "end", value: "\(addDays(date, 2))T00:00:00Z"),
            URLQueryItem(name: "limit", value: "10000"),
            URLQueryItem(name: "adjustment", value: "split"),
            URLQueryItem(name: "feed", value: "sip")
        ]
        let headers = ["APCA-API-KEY-ID": key, "APCA-API-SECRET-KEY": secret]
        var output = Dictionary(uniqueKeysWithValues: symbols.map { ($0, [MinuteBar]()) })
        var nextURL: URL? = components.url
        var pages = 0
        while let url = nextURL, pages < 40 {
            let page: AlpacaBarsResponse = try await json(url: url, headers: headers, name: "Alpaca 과거 분봉")
            for (symbol, values) in page.bars {
                output[symbol, default: []].append(contentsOf: values.map(\.minuteBar))
            }
            pages += 1
            if let token = page.nextPageToken {
                var next = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                var items = next.queryItems ?? []
                items.removeAll { $0.name == "page_token" }
                items.append(URLQueryItem(name: "page_token", value: token))
                next.queryItems = items
                nextURL = next.url
            } else {
                nextURL = nil
            }
        }
        return output
    }

    private func alpacaNews(key: String, secret: String, symbols: [String], date: String) async throws -> [String: [NewsEvidence]] {
        guard !symbols.isEmpty else { return [:] }
        var components = URLComponents(string: "https://data.alpaca.markets/v1beta1/news")!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
            URLQueryItem(name: "start", value: "\(date)T00:00:00Z"),
            URLQueryItem(name: "end", value: "\(addDays(date, 2))T00:00:00Z"),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "sort", value: "asc")
        ]
        let data: AlpacaNewsResponse = try await json(
            url: components.url!,
            headers: ["APCA-API-KEY-ID": key, "APCA-API-SECRET-KEY": secret],
            name: "Alpaca 과거 뉴스"
        )
        var output = Dictionary(uniqueKeysWithValues: symbols.map { ($0, [NewsEvidence]()) })
        for item in data.news {
            for symbol in item.symbols where output[symbol] != nil {
                output[symbol, default: []].append(NewsEvidence(
                    headline: item.headline,
                    createdAt: item.createdAt,
                    url: item.url.flatMap(URL.init(string:))
                ))
            }
        }
        return output
    }

    private func fetchFilings(symbols: [String], date: String, email: String) async throws -> [String: [FilingEvidence]] {
        guard !symbols.isEmpty else { return [:] }
        guard email.contains("@") else {
            throw AnalysisError.invalidInput("SEC 조회를 위해 설정에 연락 이메일을 입력해주세요.")
        }
        let headers = ["User-Agent": "CRT personal-research \(email)"]
        let tickers: [String: SECTicker] = try await json(
            url: URL(string: "https://www.sec.gov/files/company_tickers.json")!,
            headers: headers,
            name: "SEC 종목 목록"
        )
        let cikByTicker = Dictionary(uniqueKeysWithValues: tickers.values.map { ($0.ticker.uppercased(), String(format: "%010d", $0.cik)) })
        var output = Dictionary(uniqueKeysWithValues: symbols.map { ($0, [FilingEvidence]()) })
        for symbol in symbols {
            guard let cik = cikByTicker[symbol] else { continue }
            let submission: SECSubmission = try await json(
                url: URL(string: "https://data.sec.gov/submissions/CIK\(cik).json")!,
                headers: headers,
                name: "SEC \(symbol) 공시"
            )
            for index in submission.filings.recent.filingDate.indices where submission.filings.recent.filingDate[index] == date {
                let accession = submission.filings.recent.accessionNumber[index]
                let document = submission.filings.recent.primaryDocument[index]
                guard let url = URL(string: "https://www.sec.gov/Archives/edgar/data/\(Int(cik) ?? 0)/\(accession.replacingOccurrences(of: "-", with: ""))/\(document)") else { continue }
                output[symbol, default: []].append(FilingEvidence(
                    form: submission.filings.recent.form[index],
                    date: date,
                    url: url
                ))
            }
            try? await Task.sleep(for: .milliseconds(125))
        }
        return output
    }

    private func json<T: Decodable>(url: URL, headers: [String: String], name: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AnalysisError.remote("\(name) 조회에 실패했습니다. 상태 코드: \(status)")
        }
        do {
            return try JSONDecoder.marketDecoder.decode(T.self, from: data)
        } catch {
            throw AnalysisError.remote("\(name) 응답을 해석하지 못했습니다.")
        }
    }

    private func easternDate(_ date: Date) -> String {
        DateFormatter.easternDate.string(from: date)
    }

    private func marketSession(_ date: Date) -> String? {
        let calendar = Calendar(identifier: .gregorian)
        var eastern = calendar
        eastern.timeZone = easternTimeZone
        let components = eastern.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if minute >= 240 && minute < 570 { return "프리마켓" }
        if minute >= 570 && minute < 960 { return "정규장" }
        if minute >= 960 && minute < 1200 { return "애프터마켓" }
        return nil
    }

    private func addDays(_ date: String, _ count: Int) -> String {
        let start = DateFormatter.isoDate.date(from: date) ?? Date()
        let result = Calendar(identifier: .gregorian).date(byAdding: .day, value: count, to: start) ?? start
        return DateFormatter.isoDate.string(from: result)
    }
}

private struct DailyCandidate {
    let symbol: String
    let move: Double
    let dollars: Double
}

private struct MinuteCandidate {
    let symbol: String
    let session: String
    let detectedAt: Date
    let baselinePrice: Double
    let peakPrice: Double
    let move: Double
    let dollarVolume: Double
}

private struct MinuteBar {
    let timestamp: Date
    let low: Double
    let high: Double
    let close: Double
    let volume: Double
    let vwap: Double?
}

private struct MassiveResponse<T: Decodable>: Decodable {
    let results: [T]?
}

private struct MassiveDailyBar: Decodable {
    let ticker: String
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let vwap: Double?
    let otc: Bool?

    enum CodingKeys: String, CodingKey {
        case ticker = "T", high = "h", low = "l", close = "c", volume = "v", vwap = "vw", otc
    }
}

private struct MassiveMinuteBar: Decodable {
    let timestamp: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let vwap: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp = "t", high = "h", low = "l", close = "c", volume = "v", vwap = "vw"
    }

    var minuteBar: MinuteBar {
        MinuteBar(
            timestamp: Date(timeIntervalSince1970: timestamp / 1000),
            low: low,
            high: high,
            close: close,
            volume: volume,
            vwap: vwap
        )
    }
}

private struct AlpacaBarsResponse: Decodable {
    let bars: [String: [AlpacaMinuteBar]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case bars
        case nextPageToken = "next_page_token"
    }
}

private struct AlpacaMinuteBar: Decodable {
    let timestamp: Date
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let vwap: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp = "t", high = "h", low = "l", close = "c", volume = "v", vwap = "vw"
    }

    var minuteBar: MinuteBar {
        MinuteBar(timestamp: timestamp, low: low, high: high, close: close, volume: volume, vwap: vwap)
    }
}

private struct AlpacaNewsResponse: Decodable {
    let news: [AlpacaNewsItem]
}

private struct AlpacaNewsItem: Decodable {
    let headline: String
    let createdAt: Date
    let symbols: [String]
    let url: String?

    enum CodingKeys: String, CodingKey {
        case headline, symbols, url
        case createdAt = "created_at"
    }
}

private struct SECTicker: Decodable {
    let cik: Int
    let ticker: String

    enum CodingKeys: String, CodingKey {
        case cik = "cik_str", ticker
    }
}

private struct SECSubmission: Decodable {
    let filings: SECFilings
}

private struct SECFilings: Decodable {
    let recent: SECRecentFilings
}

private struct SECRecentFilings: Decodable {
    let filingDate: [String]
    let accessionNumber: [String]
    let primaryDocument: [String]
    let form: [String]
}

private extension JSONDecoder {
    static var marketDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension DateFormatter {
    static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let easternDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
