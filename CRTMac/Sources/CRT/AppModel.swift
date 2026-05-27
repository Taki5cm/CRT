import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @Published var liveRules = LiveScanRules() {
        didSet {
            UserDefaults.standard.set(liveRules.cooldownSeconds, forKey: "liveCooldownSeconds")
            if isLiveRunning {
                liveQuoteService.updateRules(liveRules)
            }
        }
    }
    @Published var liveAlerts: [LiveAlert] = []
    @Published var liveStartedAt: Date?
    @Published var liveReceivedTradeCount = 0
    @Published var liveLastTradeAt: Date?
    @Published var liveMovers: [LiveMovement] = []
    @Published var captureRecords: [CaptureRecord] = []
    @Published var captureHistoryStatus = "포착 기록 저장소를 준비하고 있습니다..."
    @Published var catalystStatusMessage = "포착 후 뉴스·공시·기업 규모를 자동으로 조사합니다."
    @Published var chartSymbolText = "AAPL"
    @Published var selectedChartSymbol = "AAPL"
    @Published var chartInterval: ChartInterval = .oneMinute {
        didSet { rebuildDisplayedCandles() }
    }
    @Published var chartCandles: [PriceCandle] = []
    @Published var chartIsLoading = false
    @Published var chartStatus = "종목을 선택하면 오늘의 분봉 차트를 불러옵니다."
    @Published var supporterCandidates: [SupporterCandidate] = []
    @Published var supporterSymbolText = "BIRD"
    @Published var supporterDateText = ""
    @Published var supporterStatus = "300% 이상 급등 사례와 대조 표본을 검증해 저장합니다."

    @Published var massiveKey = ""
    @Published var alpacaKey = ""
    @Published var alpacaSecret = ""
    @Published var secEmail = ""

    private let keychain = KeychainStore()
    private let service = MarketService()
    private let notificationService = NotificationService()
    private let liveQuoteService = LiveQuoteService()
    private var captureHistoryStore: CaptureHistoryStore?
    private var supporterDatasetStore: SupporterDatasetStore?
    private var rawChartCandles: [PriceCandle] = []
    private var lastCaptureRefreshAt = Date.distantPast

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
        if UserDefaults.standard.object(forKey: "liveCooldownSeconds") != nil {
            liveRules.cooldownSeconds = UserDefaults.standard.integer(forKey: "liveCooldownSeconds")
        }
        supporterDateText = selectedDateString
        prepareCaptureHistory()
        prepareSupporterDataset()
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
                alpacaKey: alpacaKey.trimmingCharacters(in: .whitespacesAndNewlines),
                alpacaSecret: alpacaSecret.trimmingCharacters(in: .whitespacesAndNewlines),
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
                massiveKey: massiveKey.trimmingCharacters(in: .whitespacesAndNewlines),
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
        refreshCaptureHistory()
        errorMessage = nil
        liveTrades = []
        liveAlerts = []
        liveReceivedTradeCount = 0
        liveLastTradeAt = nil
        liveMovers = []
        isLiveRunning = true
        liveStartedAt = Date()
        liveStatusMessage = "\(liveMonitoringMode.label) 연결을 시작하고 있습니다..."
        refreshIntradayChart()
        liveQuoteService.connect(
            key: key,
            secret: secret,
            feed: liveMonitoringMode.feed,
            symbols: watchlist,
            allSymbols: liveMonitoringMode.scansAllSymbols,
            outcomeSymbols: Array(Set(captureRecords.filter { $0.status == .tracking }.map(\.symbol))),
            chartSymbol: selectedChartSymbol,
            rules: liveRules
        ) { [weak self] trade in
            Task { @MainActor in
                guard let self else { return }
                self.liveTrades.removeAll { $0.symbol == trade.symbol }
                self.liveTrades.append(trade)
                self.liveTrades.sort { $0.symbol < $1.symbol }
                self.appendChartTrade(trade)
            }
        } onAlert: { [weak self] alert in
            Task { @MainActor in
                guard let self else { return }
                self.liveAlerts.insert(alert, at: 0)
                self.liveAlerts = Array(self.liveAlerts.prefix(100))
                self.saveCapture(alert)
                self.liveStatusMessage = "\(alert.symbol) \(alert.direction.label) 후보를 감지했습니다. 뉴스·공시 확인 전 가격 경보입니다."
                self.beginCatalystResearch(for: alert)
                if self.notificationsEnabled {
                    await self.notificationService.sendLiveAlertNotification(alert)
                }
            }
        } onTrackedTrade: { [weak self] trade in
            Task { @MainActor in
                self?.trackCapturePerformance(with: trade)
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
        refreshCaptureHistory()
    }

    func clearLiveAlerts() {
        liveAlerts = []
    }

    func showChart(for symbol: String) {
        let normalized = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            errorMessage = "차트에서 확인할 종목 기호를 입력해주세요."
            return
        }
        selectedChartSymbol = normalized
        chartSymbolText = normalized
        liveQuoteService.updateChartSymbol(normalized)
        refreshIntradayChart()
    }

    func applyChartSymbol() {
        showChart(for: chartSymbolText)
    }

    func refreshIntradayChart() {
        let key = alpacaKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = alpacaSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = selectedChartSymbol
        guard !key.isEmpty, !secret.isEmpty else {
            chartStatus = "Alpaca 키를 설정하면 \(symbol)의 오늘 분봉을 조회합니다."
            return
        }
        chartIsLoading = true
        chartStatus = "\(symbol) \(chartInterval.label) 차트를 불러오고 있습니다..."
        Task {
            defer { chartIsLoading = false }
            do {
                let candles = try await service.loadIntradayChart(
                    symbol: symbol,
                    alpacaKey: key,
                    alpacaSecret: secret,
                    feed: liveMonitoringMode.feed
                )
                guard symbol == selectedChartSymbol else { return }
                rawChartCandles = candles
                rebuildDisplayedCandles()
                chartStatus = candles.isEmpty
                    ? "\(symbol)의 오늘 수신 가능한 분봉이 아직 없습니다."
                    : "\(symbol) · \(liveMonitoringMode.feed.rawValue.uppercased()) 분봉 \(candles.count)개 · 감시 중 체결은 현재 봉에 반영됩니다."
            } catch {
                chartStatus = error.localizedDescription
            }
        }
    }

    func addSupporterCandidate() {
        guard let supporterDatasetStore else { return }
        let symbol = supporterSymbolText.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let date = supporterDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbol.isEmpty, DateFormatter.isoDate.date(from: date) != nil else {
            errorMessage = "학습 후보 티커와 거래일을 입력해주세요. 날짜 형식은 2026-05-27입니다."
            return
        }
        do {
            try supporterDatasetStore.addCandidate(symbol: symbol, eventDate: date, note: "사용자 등록 검증 후보")
            refreshSupporterCandidates()
            supporterStatus = "\(symbol) \(date) 후보를 검증 대기열에 추가했습니다."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareCandidateEntry(from candidate: SupporterCandidate) {
        supporterSymbolText = candidate.symbol
        supporterDateText = candidate.eventDate ?? selectedDateString
    }

    func verifySupporterCandidate(_ candidate: SupporterCandidate) {
        guard let date = candidate.eventDate else {
            prepareCandidateEntry(from: candidate)
            supporterStatus = "\(candidate.symbol)의 급등 거래일을 입력해 새 검증 후보로 추가해주세요."
            return
        }
        supporterStatus = "\(candidate.symbol) \(date)의 가격 경로를 확인하고 있습니다..."
        Task {
            do {
                let result = try await service.verifySupporterCandidate(
                    symbol: candidate.symbol,
                    date: date,
                    alpacaKey: alpacaKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    alpacaSecret: alpacaSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try supporterDatasetStore?.saveVerification(result, for: candidate.id)
                refreshSupporterCandidates()
                supporterStatus = "\(candidate.symbol): \(String(format: "%+.2f", result.changePercent))% · \(result.qualifies ? "300% 사건 표본으로 확인" : "대조 표본으로 저장")"
            } catch {
                try? supporterDatasetStore?.markFailed(id: candidate.id, note: error.localizedDescription)
                refreshSupporterCandidates()
                supporterStatus = error.localizedDescription
            }
        }
    }

    func refreshCaptureHistory() {
        guard let captureHistoryStore else { return }
        do {
            try captureHistoryStore.expireStaleRecords()
            captureRecords = try captureHistoryStore.fetchRecords()
            captureHistoryStatus = captureRecords.isEmpty
                ? "포착되는 급등락부터 이 Mac에 저장됩니다."
                : "최근 포착 기록 \(captureRecords.count)건을 불러왔습니다. 데이터베이스 v\(CaptureHistoryStore.schemaVersion)"
        } catch {
            captureHistoryStatus = error.localizedDescription
        }
    }

    func exportCaptureHistory() {
        guard let captureHistoryStore else {
            errorMessage = "포착 기록 저장소가 아직 준비되지 않았습니다."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "CRT-Capture-History.csv"
        panel.title = "포착 기록 CSV 내보내기"
        panel.message = "저장할 위치를 선택하세요. API 키는 포함되지 않습니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try captureHistoryStore.exportCSV(to: url)
            captureHistoryStatus = "포착 기록을 CSV로 저장했습니다: \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryCatalystResearch(for record: CaptureRecord) {
        if let captureHistoryStore {
            do {
                try captureHistoryStore.saveCatalystReport(.checking(), captureID: record.id)
                refreshCaptureHistory()
            } catch {
                catalystStatusMessage = error.localizedDescription
            }
        }
        let alert = LiveAlert(
            symbol: record.symbol,
            detectedAt: record.detectedAt,
            baselinePrice: record.baselinePrice,
            latestPrice: record.detectedPrice,
            changePercent: record.changePercent,
            direction: record.direction,
            dollarVolume: record.dollarVolume,
            windowSeconds: record.windowSeconds,
            feed: record.feed
        )
        runCatalystResearch(for: alert, captureID: record.id)
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

    private func prepareCaptureHistory() {
        do {
            captureHistoryStore = try CaptureHistoryStore()
            refreshCaptureHistory()
        } catch {
            captureHistoryStatus = error.localizedDescription
        }
    }

    private func prepareSupporterDataset() {
        do {
            supporterDatasetStore = try SupporterDatasetStore()
            refreshSupporterCandidates()
        } catch {
            supporterStatus = error.localizedDescription
        }
    }

    private func refreshSupporterCandidates() {
        do {
            supporterCandidates = try supporterDatasetStore?.fetchCandidates() ?? []
        } catch {
            supporterStatus = error.localizedDescription
        }
    }

    private func rebuildDisplayedCandles() {
        chartCandles = PriceCandle.aggregated(rawChartCandles, interval: chartInterval)
    }

    private func appendChartTrade(_ trade: LiveTrade) {
        guard trade.symbol == selectedChartSymbol else { return }
        let minuteStart = Date(timeIntervalSince1970: floor(trade.occurredAt.timeIntervalSince1970 / 60) * 60)
        if let index = rawChartCandles.lastIndex(where: { $0.startedAt == minuteStart }) {
            let existing = rawChartCandles[index]
            rawChartCandles[index] = PriceCandle(
                startedAt: minuteStart,
                open: existing.open,
                high: max(existing.high, trade.price),
                low: min(existing.low, trade.price),
                close: trade.price,
                volume: existing.volume + Double(trade.size)
            )
        } else {
            rawChartCandles.append(PriceCandle(
                startedAt: minuteStart,
                open: trade.price,
                high: trade.price,
                low: trade.price,
                close: trade.price,
                volume: Double(trade.size)
            ))
            rawChartCandles.sort { $0.startedAt < $1.startedAt }
        }
        rebuildDisplayedCandles()
    }

    private func saveCapture(_ alert: LiveAlert) {
        guard let captureHistoryStore else { return }
        do {
            try captureHistoryStore.record(alert: alert, monitoringMode: liveMonitoringMode)
            refreshCaptureHistory()
        } catch {
            captureHistoryStatus = error.localizedDescription
        }
    }

    private func beginCatalystResearch(for alert: LiveAlert) {
        guard let captureHistoryStore else { return }
        do {
            try captureHistoryStore.saveCatalystReport(.checking(), captureID: alert.id.uuidString)
            refreshCaptureHistory()
        } catch {
            catalystStatusMessage = error.localizedDescription
        }
        runCatalystResearch(for: alert, captureID: alert.id.uuidString)
    }

    private func runCatalystResearch(for alert: LiveAlert, captureID: String) {
        catalystStatusMessage = "\(alert.symbol) 2차 조사를 진행하고 있습니다..."
        Task {
            let report = await service.investigateLiveCapture(
                alert: alert,
                alpacaKey: alpacaKey.trimmingCharacters(in: .whitespacesAndNewlines),
                alpacaSecret: alpacaSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                massiveKey: massiveKey.trimmingCharacters(in: .whitespacesAndNewlines),
                secEmail: secEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard let captureHistoryStore else { return }
            do {
                try captureHistoryStore.saveCatalystReport(report, captureID: captureID)
                refreshCaptureHistory()
                catalystStatusMessage = "\(alert.symbol) \(report.summary)"
                if notificationsEnabled {
                    await notificationService.sendCatalystReportNotification(symbol: alert.symbol, report: report)
                }
            } catch {
                catalystStatusMessage = error.localizedDescription
            }
        }
    }

    private func trackCapturePerformance(with trade: LiveTrade) {
        guard let captureHistoryStore else { return }
        do {
            guard try captureHistoryStore.updatePerformance(for: trade) else { return }
            if trade.receivedAt.timeIntervalSince(lastCaptureRefreshAt) >= 1 {
                lastCaptureRefreshAt = trade.receivedAt
                refreshCaptureHistory()
            }
        } catch {
            captureHistoryStatus = error.localizedDescription
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
