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
