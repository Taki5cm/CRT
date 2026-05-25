import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedDate: Date = AppModel.previousWeekday()
    @Published var rules = ScanRules()
    @Published var watchlistText = "AAPL, NVDA, TSLA, PLTR, IONQ, RGTI, QBTS"
    @Published var result: AnalysisResult?
    @Published var isLoading = false
    @Published var statusMessage = "설정에서 무료 API 키를 저장한 뒤 분석을 시작하세요."
    @Published var errorMessage: String?
    @Published var isShowingSettings = false

    @Published var massiveKey = ""
    @Published var alpacaKey = ""
    @Published var alpacaSecret = ""
    @Published var secEmail = ""

    private let keychain = KeychainStore()
    private let service = MarketService()

    init() {
        massiveKey = keychain.value(for: "massiveKey")
        alpacaKey = keychain.value(for: "alpacaKey")
        alpacaSecret = keychain.value(for: "alpacaSecret")
        secEmail = keychain.value(for: "secEmail")
    }

    var selectedDateString: String {
        DateFormatter.easternDate.string(from: selectedDate)
    }

    var watchlist: [String] {
        Array(Set(watchlistText.uppercased()
            .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .filter { !$0.isEmpty }))
            .sorted()
    }

    func saveCredentials() {
        do {
            try keychain.set(massiveKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "massiveKey")
            try keychain.set(alpacaKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "alpacaKey")
            try keychain.set(alpacaSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: "alpacaSecret")
            try keychain.set(secEmail.trimmingCharacters(in: .whitespacesAndNewlines), for: "secEmail")
            statusMessage = "설정이 Mac 키체인에 저장되었습니다."
            isShowingSettings = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scanWholeMarket() {
        beginAnalysis(message: "전체시장 후보를 확인하고 있습니다...") { [self] in
            try await service.scanWholeMarket(
                massiveKey: massiveKey.trimmingCharacters(in: .whitespacesAndNewlines),
                secEmail: secEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                date: selectedDateString,
                rules: rules
            )
        }
    }

    func analyzeWatchlist() {
        beginAnalysis(message: "관심종목의 분봉, 뉴스, 공시를 확인하고 있습니다...") { [self] in
            try await service.analyzeWatchlist(
                alpacaKey: alpacaKey.trimmingCharacters(in: .whitespacesAndNewlines),
                alpacaSecret: alpacaSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                secEmail: secEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                date: selectedDateString,
                symbols: watchlist,
                rules: rules
            )
        }
    }

    private func beginAnalysis(message: String, operation: @escaping () async throws -> AnalysisResult) {
        guard !isLoading else { return }
        guard selectedDate < Calendar.current.startOfDay(for: Date()) else {
            errorMessage = "지난 날짜를 선택해주세요. 실시간 분석은 아직 지원하지 않습니다."
            return
        }
        errorMessage = nil
        isLoading = true
        statusMessage = message
        Task {
            defer { isLoading = false }
            do {
                result = try await operation()
                statusMessage = result?.reports.isEmpty == true
                    ? "선택한 기준에 맞는 급변 후보가 발견되지 않았습니다."
                    : "실제 과거 데이터 분석이 완료되었습니다."
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "분석을 완료하지 못했습니다."
            }
        }
    }

    private static func previousWeekday() -> Date {
        var date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        while Calendar.current.isDateInWeekend(date) {
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return date
    }
}
