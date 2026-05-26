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
    @Published var isShowingDatePicker = false
    @Published var dateInputText = ""
    @Published var reportFilter: ReportFilter = .all
    @Published var notificationsEnabled: Bool
    @Published var notificationStatus = "알림 상태 확인 중..."
    @Published var liveTrades: [LiveTrade] = []
    @Published var isLiveRunning = false
    @Published var liveStatusMessage = "모드를 선택하고 시장 감시를 시작하세요."
    @Published var liveMonitoringMode: LiveMonitoringMode {
        didSet {
            UserDefaults.standard.set(liveMonitoringMode.rawValue, forKey: "liveMonitoringMode")
        }
    }
    @Published var liveRules = LiveScanRules()
    @Published var liveAlerts: [LiveAlert] = []
    @Published var liveStartedAt: Date?
    @Published var liveReceivedTradeCount = 0
    @Published var liveLastTradeAt: Date?
    @Published var liveMovers: [LiveMovement] = []

    @Published var massiveKey = ""
    @Published var alpacaKey = ""
    @Published var alpacaSecret = ""
    @Published var secEmail = ""

    private let keychain = KeychainStore()
    private let service = MarketService()
    private let notificationService = NotificationService()
    private let liveQuoteService = LiveQuoteService()

    init() {
        notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        liveMonitoringMode = LiveMonitoringMode(
            rawValue: UserDefaults.standard.string(forKey: "liveMonitoringMode") ?? ""
        ) ?? .watchlistIEX
        dateInputText = DateFormatter.easternDate.string(from: selectedDate)
        massiveKey = keychain.value(for: "massiveKey")
        alpacaKey = keychain.value(for: "alpacaKey")
        alpacaSecret = keychain.value(for: "alpacaSecret")
        secEmail = keychain.value(for: "secEmail")
        Task { await refreshNotificationStatus() }
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

    var latestAnalysisDate: Date {
        AppModel.previousWeekday()
    }

    func selectDate(_ date: Date) {
        let adjusted = AppModel.weekday(onOrBefore: min(date, latestAnalysisDate))
        selectedDate = adjusted
        dateInputText = DateFormatter.easternDate.string(from: adjusted)
        if Calendar.current.isDateInWeekend(date) {
            statusMessage = "주말을 선택해 직전 평일로 조정했습니다. 미국 휴장일은 분석 시 확인됩니다."
        }
    }

    func chooseRecentTradingDay(offset: Int) {
        var date = latestAnalysisDate
        for _ in 0..<offset {
            guard let prior = Calendar.current.date(byAdding: .day, value: -1, to: date) else { break }
            date = AppModel.weekday(onOrBefore: prior)
        }
        selectDate(date)
    }

    func applyTypedDate() {
        let input = dateInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: input) {
                errorMessage = nil
                selectDate(date)
                return
            }
        }
        errorMessage = "날짜는 2026-05-22 형식으로 입력해주세요."
    }

    func shiftSelectedYear(by years: Int) {
        guard let shifted = Calendar.current.date(byAdding: .year, value: years, to: selectedDate) else { return }
        selectDate(shifted)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
        guard enabled else {
            notificationStatus = "앱 알림 꺼짐"
            return
        }
        requestNotifications()
    }

    func requestNotifications() {
        Task {
            do {
                let state = try await notificationService.requestPermission()
                notificationStatus = state.label
            } catch {
                notificationStatus = "알림 허용을 완료하지 못했습니다."
            }
        }
    }

    func refreshNotificationStatus() async {
        guard notificationsEnabled else {
            notificationStatus = "앱 알림 꺼짐"
            return
        }
        notificationStatus = await notificationService.permissionState().label
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

    func startLiveQuotes() {
        let key = alpacaKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = alpacaSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !secret.isEmpty else {
            errorMessage = "설정에서 Alpaca API Key와 Secret Key를 먼저 입력해주세요."
            return
        }
        if !liveMonitoringMode.scansAllSymbols {
            guard !watchlist.isEmpty, watchlist.count <= 30 else {
                errorMessage = "관심종목 실시간 감지는 1개 이상 30개 이하로 입력해주세요."
                return
            }
        }
        errorMessage = nil
        liveTrades = []
        liveAlerts = []
        liveReceivedTradeCount = 0
        liveLastTradeAt = nil
        liveMovers = []
        isLiveRunning = true
        liveStartedAt = Date()
        liveStatusMessage = "\(liveMonitoringMode.label) 연결을 시작하고 있습니다..."
        liveQuoteService.connect(
            key: key,
            secret: secret,
            feed: liveMonitoringMode.feed,
            symbols: watchlist,
            allSymbols: liveMonitoringMode.scansAllSymbols,
            rules: liveRules
        ) { [weak self] trade in
            Task { @MainActor in
                guard let self else { return }
                self.liveTrades.removeAll { $0.symbol == trade.symbol }
                self.liveTrades.append(trade)
                self.liveTrades.sort { $0.symbol < $1.symbol }
            }
        } onAlert: { [weak self] alert in
            Task { @MainActor in
                guard let self else { return }
                self.liveAlerts.insert(alert, at: 0)
                self.liveAlerts = Array(self.liveAlerts.prefix(100))
                self.liveStatusMessage = "\(alert.symbol) \(alert.direction.label) 후보를 감지했습니다. 뉴스·공시 확인 전 가격 경보입니다."
                if self.notificationsEnabled {
                    await self.notificationService.sendLiveAlertNotification(alert)
                }
            }
        } onActivity: { [weak self] count, latestAt in
            Task { @MainActor in
                self?.liveReceivedTradeCount = count
                self?.liveLastTradeAt = latestAt
            }
        } onMovers: { [weak self] movers in
            Task { @MainActor in
                self?.liveMovers = movers
            }
        } onStatus: { [weak self] status, isConnected in
            Task { @MainActor in
                self?.liveStatusMessage = status
                self?.isLiveRunning = isConnected
            }
        }
    }

    func stopLiveQuotes() {
        liveQuoteService.disconnect()
        isLiveRunning = false
        liveStartedAt = nil
        liveStatusMessage = "시장 감시를 중지했습니다."
    }

    func clearLiveAlerts() {
        liveAlerts = []
    }

    func applyReceptionTestRules() {
        liveRules.windowSeconds = 60
        liveRules.thresholdPercent = 0.1
        liveRules.minimumPrice = 0.01
        liveRules.minimumDollarVolume = 1
        liveRules.cooldownSeconds = 60
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
                reportFilter = .all
                statusMessage = result?.reports.isEmpty == true
                    ? "선택한 기준에 맞는 급변 후보가 발견되지 않았습니다."
                    : "실제 과거 데이터 분석이 완료되었습니다."
                if notificationsEnabled, let result {
                    await notificationService.sendCompletionNotification(for: result)
                }
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "분석을 완료하지 못했습니다."
            }
        }
    }

    private static func previousWeekday() -> Date {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return weekday(onOrBefore: date)
    }

    private static func weekday(onOrBefore date: Date) -> Date {
        var date = date
        while Calendar.current.isDateInWeekend(date) {
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return date
    }
}
