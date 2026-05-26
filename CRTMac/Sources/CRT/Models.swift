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

enum LiveDataFeed: String, CaseIterable, Identifiable {
    case iex
    case sip

    var id: Self { self }

    var label: String {
        switch self {
        case .iex: return "IEX 무료 시험"
        case .sip: return "SIP 전체시장 (유료·실험)"
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
}

struct LiveAlert: Identifiable {
    let id = UUID()
    let symbol: String
    let detectedAt: Date
    let baselinePrice: Double
    let latestPrice: Double
    let changePercent: Double
    let dollarVolume: Double
    let windowSeconds: Int
    let feed: LiveDataFeed
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
