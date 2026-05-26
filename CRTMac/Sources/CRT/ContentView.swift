import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.067, blue: 0.071).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    liveQuotes
                    historicalAnalysis
                }
                .padding(28)
                .frame(maxWidth: 1120)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.isShowingSettings) {
            SettingsView()
                .environmentObject(model)
                .frame(width: 580, height: 515)
        }
        .sheet(isPresented: $model.isShowingDatePicker) {
            TradingDatePickerView()
                .environmentObject(model)
                .frame(width: 500, height: 635)
        }
        .alert("확인 필요", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("확인") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CRT")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color(red: 0.79, green: 0.97, blue: 0.38))
                Text("0.5")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(.secondary.opacity(0.5)))
            }
            Text("시장을 계속 감시하고\n급등 순간을 포착합니다")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .tracking(-1.5)
            Text("감시 시작 후 중지할 때까지 체결 흐름을 확인합니다. 감지 결과는 매수 추천이나 자동매매 신호가 아닙니다.")
                .foregroundStyle(.secondary)
        }
    }

    private var historicalAnalysis: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("사후 분석")
                    .font(.title3.bold())
                Text("지난 날짜의 자료를 한 번 조회해 움직임과 근거를 돌아보는 기능입니다. 실시간 감시와는 별도로 실행됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            controls
            actions
            status
            results
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.022)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07)))
    }

    private var controls: some View {
        GroupBox {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    LabeledContent("분석 날짜") {
                        Button {
                            model.isShowingDatePicker = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "calendar")
                                Text(DateFormatter.selectedDate.string(from: model.selectedDate))
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    LabeledContent("시간 창") {
                        Picker("", selection: $model.rules.windowMinutes) {
                            Text("1분").tag(1)
                            Text("2분").tag(2)
                            Text("5분").tag(5)
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    LabeledContent("상승률") {
                        HStack(spacing: 4) {
                            TextField("", value: $model.rules.thresholdPercent, format: .number)
                                .frame(width: 55)
                            Text("% 이상")
                        }
                    }
                    LabeledContent("최소 거래대금") {
                        HStack(spacing: 4) {
                            TextField("", value: $model.rules.minimumDollarVolume, format: .number.grouping(.automatic))
                                .frame(width: 122)
                            Text("USD")
                        }
                    }
                }
                Divider()
                HStack {
                    Text("관심종목")
                        .foregroundStyle(.secondary)
                    TextField("AAPL, NVDA, TSLA", text: $model.watchlistText)
                    Text("최대 30개")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(10)
        } label: {
            Text("지난 날짜 분석 조건")
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                model.scanWholeMarket()
            } label: {
                Label("1회 분석: 전체시장 후보", systemImage: "waveform.path.ecg.magnifyingglass")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.50, green: 0.78, blue: 0.36))
            .disabled(model.isLoading)

            Button {
                model.analyzeWatchlist()
            } label: {
                Label("1회 분석: 관심종목 근거", systemImage: "newspaper")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading)

            Button {
                model.isShowingSettings = true
            } label: {
                Label("설정", systemImage: "gearshape")
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }

    private var status: some View {
        HStack(spacing: 12) {
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Text(model.statusMessage)
                .foregroundStyle(model.isLoading ? Color(red: 0.79, green: 0.97, blue: 0.38) : .secondary)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08)))
    }

    private var liveQuotes: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("시장 감시")
                            .font(.title3.bold())
                        Text("시작하면 연결을 유지하며 조건에 맞는 급등 후보가 나올 때까지 계속 작동합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isLiveRunning {
                        Button("감시 중지") { model.stopLiveQuotes() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("시장 감시 시작") { model.startLiveQuotes() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                Picker("감시 모드", selection: $model.liveMonitoringMode) {
                    ForEach(LiveMonitoringMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isLiveRunning)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.liveMonitoringMode.title)
                            .font(.subheadline.bold())
                        Text(model.liveMonitoringMode.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isLiveRunning, let startedAt = model.liveStartedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("감시 실행 중")
                                    .fontWeight(.semibold)
                                Text(context.date.timeIntervalSince(startedAt).elapsedString)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }

                if !model.liveMonitoringMode.scansAllSymbols {
                    HStack {
                        Text("감시할 관심종목")
                            .foregroundStyle(.secondary)
                        TextField("AAPL, NVDA, TSLA", text: $model.watchlistText)
                            .disabled(model.isLiveRunning)
                        Text("최대 30개")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } else {
                    Text("이 모드는 Alpaca SIP 유료 권한이 없는 계정에서는 연결되지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 18) {
                    LabeledContent("감지 시간") {
                        Picker("", selection: $model.liveRules.windowSeconds) {
                            ForEach([1, 2, 5, 30, 60], id: \.self) { seconds in
                                Text("\(seconds)초").tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 86)
                    }
                    LabeledContent("상승률") {
                        HStack(spacing: 4) {
                            TextField("", value: $model.liveRules.thresholdPercent, format: .number)
                                .frame(width: 58)
                            Text("%")
                        }
                    }
                    LabeledContent("최소 주가") {
                        HStack(spacing: 4) {
                            Text("$")
                            TextField("", value: $model.liveRules.minimumPrice, format: .number)
                                .frame(width: 62)
                        }
                    }
                    LabeledContent("시간창 거래대금") {
                        HStack(spacing: 4) {
                            Text("$")
                            TextField("", value: $model.liveRules.minimumDollarVolume, format: .number.grouping(.automatic))
                                .frame(width: 120)
                        }
                    }
                    LabeledContent("재알림 제한") {
                        Picker("", selection: $model.liveRules.cooldownSeconds) {
                            Text("1분").tag(60)
                            Text("5분").tag(300)
                            Text("15분").tag(900)
                        }
                        .labelsHidden()
                        .frame(width: 72)
                    }
                }
                .disabled(model.isLiveRunning)
                HStack {
                    Text("포착은 감시 시작 후 수신된 체결 사이의 움직임을 계산합니다. 이미 오른 구간은 포착 대상이 아닙니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !model.isLiveRunning {
                        Button("수신 확인용 기준 적용") { model.applyReceptionTestRules() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                Text(model.liveStatusMessage)
                    .font(.caption)
                    .foregroundStyle(model.isLiveRunning ? Color(red: 0.79, green: 0.97, blue: 0.38) : .secondary)

                if model.isLiveRunning {
                    HStack(spacing: 12) {
                        Metric(title: "수신 체결", value: "\(model.liveReceivedTradeCount.formatted())건")
                        Metric(
                            title: "마지막 수신",
                            value: model.liveLastTradeAt.map(DateFormatter.liveTime.string(from:)) ?? "아직 없음"
                        )
                        Metric(title: "감시 범위", value: model.liveMonitoringMode.scansAllSymbols ? "전체시장 SIP" : "관심종목 IEX")
                    }
                    if model.liveReceivedTradeCount == 0 {
                        Text("아직 선택한 피드에서 체결이 들어오지 않았습니다. 무료 IEX는 미국 전체 거래가 아니라 한 거래소 자료이므로, 프리마켓 화면에 움직임이 보여도 수신되지 않을 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if !model.liveAlerts.isEmpty {
                    HStack {
                        Text("감지 로그")
                            .font(.subheadline.bold())
                        Text("\(model.liveAlerts.count)건")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("로그 지우기") { model.clearLiveAlerts() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.liveAlerts.prefix(8)) { alert in
                        LiveAlertCard(alert: alert)
                    }
                }

                if model.liveMonitoringMode.scansAllSymbols, model.isLiveRunning {
                    Text("전체시장 모드는 수신량이 많아 일반 체결을 화면에 계속 표시하지 않고, 조건을 충족한 감지 로그만 갱신합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !model.liveTrades.isEmpty {
                    Text("수신 중인 관심종목 가격")
                        .font(.subheadline.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(model.liveTrades) { trade in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(trade.symbol).font(.caption.bold()).foregroundStyle(.secondary)
                                Text("$\(trade.price, specifier: "%.2f")").font(.headline.monospacedDigit())
                                Text("수신 \(DateFormatter.liveTime.string(from: trade.receivedAt))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var results: some View {
        if let result = model.result {
            VStack(alignment: .leading, spacing: 12) {
                Text(result.mode.title)
                    .font(.title3.bold())
                HStack(spacing: 20) {
                    Metric(title: "날짜", value: result.date)
                    Metric(title: "확인 종목", value: "\(result.checkedSymbols)")
                    Metric(title: "확인 분봉", value: "\(result.minuteBarsChecked)")
                    Metric(title: "급변 후보", value: "\(result.reports.count)")
                }
                if !result.reports.isEmpty {
                    Picker("결과 필터", selection: $model.reportFilter) {
                        ForEach(ReportFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                }
                Text(result.methodology)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(result.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                let filteredReports = result.reports.filter(model.reportFilter.includes)
                if result.reports.isEmpty {
                    emptyResult
                } else if filteredReports.isEmpty {
                    Text("선택한 분류에 해당하는 후보가 없습니다.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                } else {
                    ForEach(filteredReports) { ReportCard(report: $0) }
                }
            }
        } else {
            emptyResult
        }
    }

    private var emptyResult: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
            .foregroundStyle(.secondary.opacity(0.35))
            .frame(height: 135)
            .overlay {
                Text("분석을 실행하면 실제 과거 데이터 결과가 여기에 나타납니다.")
                    .foregroundStyle(.secondary)
            }
    }
}

private struct TradingDatePickerView: View {
    @EnvironmentObject private var model: AppModel

    private var selection: Binding<Date> {
        Binding(
            get: { model.selectedDate },
            set: { model.selectDate($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("분석 날짜 선택")
                .font(.title2.bold())
            Text("지난 미국 거래일을 선택하세요. 주말을 고르면 직전 평일로 자동 조정됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("YYYY-MM-DD", text: $model.dateInputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.applyTypedDate() }
                Button("입력 날짜 적용") { model.applyTypedDate() }
                    .buttonStyle(.bordered)
            }

            HStack {
                Button {
                    model.shiftSelectedYear(by: -1)
                } label: {
                    Label("이전 해", systemImage: "chevron.left")
                }
                Spacer()
                Text(DateFormatter.year.string(from: model.selectedDate))
                    .font(.headline.monospacedDigit())
                Spacer()
                Button {
                    model.shiftSelectedYear(by: 1)
                } label: {
                    Label("다음 해", systemImage: "chevron.right")
                }
            }
            .buttonStyle(.bordered)

            DatePicker(
                "분석 날짜",
                selection: selection,
                in: ...model.latestAnalysisDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button("직전 거래일") { model.chooseRecentTradingDay(offset: 0) }
                Button("1주 전") { model.chooseRecentTradingDay(offset: 5) }
                Button("1개월 전") { model.chooseRecentTradingDay(offset: 20) }
            }
            .buttonStyle(.bordered)

            HStack {
                Text("선택됨: \(DateFormatter.selectedDate.string(from: model.selectedDate))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("적용") { model.isShowingDatePicker = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }
}

private struct Metric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.04)))
    }
}

private struct LiveAlertCard: View {
    let alert: LiveAlert

    var body: some View {
        HStack(spacing: 16) {
            Text(alert.symbol)
                .font(.headline.bold())
                .frame(width: 70, alignment: .leading)
            Text("+\(alert.changePercent.formatted(.number.precision(.fractionLength(2))))%")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.green)
                .frame(width: 92, alignment: .leading)
            Text("\(alert.windowSeconds)초")
                .foregroundStyle(.secondary)
            Text("$\(alert.baselinePrice, specifier: "%.2f") → $\(alert.latestPrice, specifier: "%.2f")")
                .monospacedDigit()
            Text("거래대금 $\(alert.dollarVolume.formatted(.number.notation(.compactName)))")
                .foregroundStyle(.secondary)
            Text(alert.feed == .iex ? "IEX" : "SIP")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Text(DateFormatter.liveTime.string(from: alert.detectedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.green.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.green.opacity(0.22)))
    }
}

private struct ReportCard: View {
    let report: AnalysisReport

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(report.classification.label)
                    .font(.caption.bold())
                    .foregroundStyle(badgeColor)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(report.symbol).font(.title3.bold())
                    Text("+\(report.changePercent.formatted(.number.precision(.fractionLength(2))))%")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                Text("\(report.session) · \(DateFormatter.displayEastern.string(from: report.detectedAt)) ET")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("$\(report.baselinePrice, specifier: "%.2f") → $\(report.peakPrice, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 210, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                if report.filings.isEmpty && report.news.isEmpty {
                    Text("직접 연결되는 당일 공시 또는 시점 주변 뉴스가 발견되지 않았습니다.")
                        .foregroundStyle(.secondary)
                }
                ForEach(report.filings) { filing in
                    Link(destination: filing.url) {
                        Label("SEC \(filing.form) · \(filing.date)", systemImage: "doc.text")
                    }
                }
                ForEach(report.news) { item in
                    if let url = item.url {
                        Link(destination: url) {
                            Label(item.headline, systemImage: "newspaper")
                        }
                    } else {
                        Label(item.headline, systemImage: "newspaper")
                    }
                }
            }
            .font(.callout)
            Spacer()
        }
        .padding(17)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }

    private var badgeColor: Color {
        switch report.classification {
        case .filingFound: return .green
        case .newsFound: return Color(red: 0.79, green: 0.97, blue: 0.38)
        case .unexplained: return .orange
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("데이터 연결 설정")
                .font(.title2.bold())
            Text("사용자 본인의 데이터 키를 입력하면 Mac 키체인에 안전하게 저장됩니다. 무료 Alpaca IEX로 관심종목 감지를 시험하고, 유료 SIP 구독 시 전체 상장주 감지를 선택할 수 있습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Group {
                SecureField("Massive API Key", text: $model.massiveKey)
                Text("Massive Stocks에서 발급한 API Key를 입력하세요. 로그인 암호나 Alpaca 키는 사용할 수 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Alpaca API Key", text: $model.alpacaKey)
                SecureField("Alpaca Secret Key", text: $model.alpacaSecret)
                TextField("SEC 조회용 이메일", text: $model.secEmail)
            }
            .textFieldStyle(.roundedBorder)
            Divider()
            Toggle("급등 포착 및 분석 완료 알림 받기", isOn: Binding(
                get: { model.notificationsEnabled },
                set: { model.setNotificationsEnabled($0) }
            ))
            HStack {
                Text(model.notificationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.notificationsEnabled {
                    Button("알림 권한 요청") { model.requestNotifications() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            HStack {
                Text("키는 외부 서버에 저장하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("저장") { model.saveCredentials() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .preferredColorScheme(.dark)
    }
}

private extension DateFormatter {
    static let selectedDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy년 M월 d일 (E)"
        return formatter
    }()

    static let displayEastern: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    static let year: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy년"
        return formatter
    }()

    static let liveTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private extension TimeInterval {
    var elapsedString: String {
        let seconds = max(0, Int(self))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
