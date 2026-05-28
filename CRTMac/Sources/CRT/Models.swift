import Foundation

struct ScanRules {
    var windowMinutes: Int = 1
    var thresholdPercent: Double = 10
    var minimumPrice: Double = 1
    var minimumDollarVolume: Double = 100_000

    var windowSeconds: Int { windowMinutes * 60 }
}

struct AnalysisReport: Identifiable {
    enum Classification {
        case filingFound
        case newsFound
        case unexplained

        var label: String {
            switch self {
            case .filingFound: return "공시 확인"
            case .newsFound: return "뉴스 확인"
            case .unexplained: return "원인 미확인"
            }
        }
    }

    let id = UUID()
    let symbol: String
    let session: String
    let detectedAt: Date
    let baselinePrice: Double
    let peakPrice: Double
    let changePercent: Double
    let dollarVolume: Double
    let classification: Classification
    let filings: [FilingEvidence]
    let news: [NewsEvidence]
}

struct FilingEvidence: Identifiable {
    let id = UUID()
    let form: String
    let date: String
    let url: URL
}

struct NewsEvidence: Identifiable {
    let id = UUID()
    let headline: String
    let createdAt: Date
    let url: URL?
}

struct LiveTrade: Identifiable {
    var id: String { symbol }
    let symbol: String
    let price: Double
    let size: Int
    let occurredAt: Date
    let receivedAt: Date
}

enum ChartInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 1
    case threeMinutes = 3
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case oneDay = 1440

    var id: Int { rawValue }
    var label: String { self == .oneDay ? "일봉" : "\(rawValue)분" }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    var alpacaTimeframe: String { self == .oneDay ? "1Day" : "1Min" }
    var isDaily: Bool { self == .oneDay }
}

struct PriceCandle: Identifiable {
    var id: Date { startedAt }
    let startedAt: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    var changePercent: Double {
        guard open > 0 else { return 0 }
        return ((close - open) / open) * 100
    }

    static func aggregated(_ candles: [PriceCandle], interval: ChartInterval) -> [PriceCandle] {
        guard interval != .oneMinute, interval != .oneDay else { return candles.sorted { $0.startedAt < $1.startedAt } }
        let seconds = interval.seconds
        let grouped = Dictionary(grouping: candles) { candle in
            Date(timeIntervalSince1970: floor(candle.startedAt.timeIntervalSince1970 / seconds) * seconds)
        }
        return grouped.map { startedAt, values in
            let ordered = values.sorted { $0.startedAt < $1.startedAt }
            return PriceCandle(
                startedAt: startedAt,
                open: ordered.first?.open ?? 0,
                high: ordered.map(\.high).max() ?? 0,
                low: ordered.map(\.low).min() ?? 0,
                close: ordered.last?.close ?? 0,
                volume: ordered.reduce(0) { $0 + $1.volume }
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
    }
}

enum LiveDataFeed: String, CaseIterable, Identifiable {
    case iex
    case sip

    var id: Self { self }

    var label: String {
        switch self {
        case .iex: return "IEX 무료 시험"
        case .sip: return "SIP 전체시장 (유료 시험)"
        }
    }

    var explanation: String {
        switch self {
        case .iex: return "무료 계정용: 입력한 관심종목만 감지합니다."
        case .sip: return "Alpaca Algo Trader Plus용: 전체 상장주 감지는 고수신량 시험 모드입니다."
        }
    }
}

enum LiveMonitoringMode: String, CaseIterable, Identifiable {
    case watchlistIEX
    case wholeMarketSIP

    var id: Self { self }

    var title: String {
        switch self {
        case .watchlistIEX: return "관심종목 감시"
        case .wholeMarketSIP: return "전체시장 감시"
        }
    }

    var label: String {
        switch self {
        case .watchlistIEX: return "관심종목 · 무료 IEX"
        case .wholeMarketSIP: return "전체시장 · 유료 SIP"
        }
    }

    var explanation: String {
        switch self {
        case .watchlistIEX:
            return "무료 시험 모드입니다. 입력한 관심종목 최대 30개를 앱이 꺼질 때까지 계속 감시합니다."
        case .wholeMarketSIP:
            return "실전 검증용 모드입니다. 본인의 Alpaca SIP 권한으로 전체 상장주 체결을 계속 감시합니다."
        }
    }

    var feed: LiveDataFeed {
        switch self {
        case .watchlistIEX: return .iex
        case .wholeMarketSIP: return .sip
        }
    }

    var scansAllSymbols: Bool {
        self == .wholeMarketSIP
    }
}

struct LiveScanRules {
    var windowSeconds: Int = 2
    var thresholdPercent: Double = 10
    var minimumPrice: Double = 1
    var minimumDollarVolume: Double = 10_000
    var cooldownSeconds: Int = 300
    var directionFilter: LiveDirectionFilter = .both
}

enum LiveDirectionFilter: String, CaseIterable, Identifiable {
    case both
    case rising
    case falling

    var id: Self { self }

    var label: String {
        switch self {
        case .both: return "급등·급락"
        case .rising: return "급등만"
        case .falling: return "급락만"
        }
    }

    func includes(_ direction: LiveMoveDirection) -> Bool {
        switch self {
        case .both: return true
        case .rising: return direction == .rising
        case .falling: return direction == .falling
        }
    }
}

enum LiveMoveDirection: String {
    case rising
    case falling

    var label: String {
        switch self {
        case .rising: return "급등"
        case .falling: return "급락"
        }
    }
}

struct LiveMovement: Identifiable {
    var id: String { symbol }
    let symbol: String
    let direction: LiveMoveDirection
    let changePercent: Double
    let latestPrice: Double
    let dollarVolume: Double
    let observedAt: Date
    let windowSeconds: Int
    let feed: LiveDataFeed
}

struct LiveDetectionUpdate {
    let movement: LiveMovement?
    let alert: LiveAlert?
}

struct LiveAlert: Identifiable {
    let id = UUID()
    let symbol: String
    let detectedAt: Date
    let baselinePrice: Double
    let latestPrice: Double
    let changePercent: Double
    let direction: LiveMoveDirection
    let dollarVolume: Double
    let windowSeconds: Int
    let feed: LiveDataFeed
}

enum CaptureTrackingStatus: String {
    case tracking
    case completed
    case incomplete

    var label: String {
        switch self {
        case .tracking: return "추적 중"
        case .completed: return "15분 기록 완료"
        case .incomplete: return "후속 수신 누락"
        }
    }
}

enum CatalystResearchStatus: String, Codable {
    case checking
    case complete
    case partial
    case failed

    var label: String {
        switch self {
        case .checking: return "2차 조사 중"
        case .complete: return "2차 보고 완료"
        case .partial: return "일부 자료 확인"
        case .failed: return "조사 실패"
        }
    }
}

struct CatalystNewsItem: Codable, Identifiable {
    var id: String { "\(createdAt.timeIntervalSince1970)-\(headline)" }
    let headline: String
    let createdAt: Date
    let urlString: String?

    var url: URL? {
        urlString.flatMap(URL.init(string:))
    }
}

struct CatalystFilingItem: Codable, Identifiable {
    var id: String { "\(date)-\(form)-\(urlString)" }
    let form: String
    let date: String
    let urlString: String
    let isDilutionRelated: Bool

    var url: URL? {
        URL(string: urlString)
    }
}

struct CatalystResearchReport: Codable {
    let status: CatalystResearchStatus
    let checkedAt: Date
    let summary: String
    let marketCap: Double?
    let shareClassSharesOutstanding: Double?
    let weightedSharesOutstanding: Double?
    let companyName: String?
    let industryDescription: String?
    let news: [CatalystNewsItem]
    let filings: [CatalystFilingItem]
    let dilutionForms: [String]
    let warnings: [String]

    var hasDilutionRisk: Bool {
        !dilutionForms.isEmpty
    }

    static func checking(at date: Date = Date()) -> CatalystResearchReport {
        CatalystResearchReport(
            status: .checking,
            checkedAt: date,
            summary: "뉴스·SEC 공시·기업 규모를 확인하고 있습니다.",
            marketCap: nil,
            shareClassSharesOutstanding: nil,
            weightedSharesOutstanding: nil,
            companyName: nil,
            industryDescription: nil,
            news: [],
            filings: [],
            dilutionForms: [],
            warnings: []
        )
    }
}

struct CaptureRecord: Identifiable {
    let id: String
    let symbol: String
    let detectedAt: Date
    let direction: LiveMoveDirection
    let baselinePrice: Double
    let detectedPrice: Double
    let changePercent: Double
    let dollarVolume: Double
    let windowSeconds: Int
    let feed: LiveDataFeed
    let monitoringMode: LiveMonitoringMode
    let marketSession: String
    let endPrice: Double
    let maxPrice: Double
    let minPrice: Double
    let latestObservedAt: Date?
    let performance1Minute: Double?
    let performance5Minutes: Double?
    let performance15Minutes: Double?
    let status: CaptureTrackingStatus
    let catalystReport: CatalystResearchReport?

    var maxAdvancePercent: Double {
        guard detectedPrice > 0 else { return 0 }
        return ((maxPrice - detectedPrice) / detectedPrice) * 100
    }

    var maxDrawdownPercent: Double {
        guard detectedPrice > 0 else { return 0 }
        return ((minPrice - detectedPrice) / detectedPrice) * 100
    }
}

enum SupporterCandidateStatus: String {
    case pending
    case qualifies
    case comparison
    case failed

    var label: String {
        switch self {
        case .pending: return "검증 대기"
        case .qualifies: return "300% 사건 확인"
        case .comparison: return "대조 표본"
        case .failed: return "검증 실패"
        }
    }
}

struct SupporterCandidate: Identifiable {
    let id: String
    let symbol: String
    let eventDate: String?
    let note: String
    let status: SupporterCandidateStatus
    let baselinePrice: Double?
    let peakPrice: Double?
    let changePercent: Double?
    let eventOpen: Double?
    let eventClose: Double?
    let eventVolume: Double?
    let eventDollarVolume: Double?
    let peakAt: Date?
    let marketSession: String?
    let minutesToPeak: Double?
    let performance1Minute: Double?
    let performance5Minutes: Double?
    let performance15Minutes: Double?
    let performance60Minutes: Double?
    let closeFromBaselinePercent: Double?
    let closeFromPeakPercent: Double?
    let outcomeLabel: String?
    let riskLabel: String?
    let newsCount: Int
    let filingCount: Int
    let dilutionForms: String?
    let evidenceSummary: String?
    let verifiedAt: Date?
    let verificationNote: String?
}

struct SupporterVerificationResult {
    let baselinePrice: Double
    let peakPrice: Double
    let changePercent: Double
    let eventOpen: Double
    let eventClose: Double
    let eventVolume: Double
    let eventDollarVolume: Double
    let peakAt: Date
    let marketSession: String
    let minutesToPeak: Double
    let performance1Minute: Double?
    let performance5Minutes: Double?
    let performance15Minutes: Double?
    let performance60Minutes: Double?
    let closeFromBaselinePercent: Double
    let closeFromPeakPercent: Double
    let outcomeLabel: String
    let riskLabel: String
    let newsCount: Int
    let filingCount: Int
    let dilutionForms: String?
    let evidenceSummary: String
    let qualifies: Bool
    let note: String
}

struct AnalysisResult {
    enum Mode {
        case wholeMarket
        case watchlist

        var title: String {
            switch self {
            case .wholeMarket: return "전체시장 사후 스캔"
            case .watchlist: return "관심종목 뉴스·공시 분석"
            }
        }
    }

    let mode: Mode
    let date: String
    let reports: [AnalysisReport]
    let checkedSymbols: Int
    let minuteBarsChecked: Int
    let shortlistedSymbols: Int?
    let warnings: [String]
    let methodology: String
}

enum ReportFilter: String, CaseIterable, Identifiable {
    case all
    case filing
    case news
    case unexplained

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "전체"
        case .filing: return "공시"
        case .news: return "뉴스"
        case .unexplained: return "원인 미확인"
        }
    }

    func includes(_ report: AnalysisReport) -> Bool {
        switch self {
        case .all:
            return true
        case .filing:
            return report.classification == .filingFound
        case .news:
            return report.classification == .newsFound
        case .unexplained:
            return report.classification == .unexplained
        }
    }
}

enum AnalysisError: LocalizedError {
    case missingCredential(String)
    case invalidInput(String)
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let message),
             .invalidInput(let message),
             .remote(let message):
            return message
        }
    }
}
