import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.018, green: 0.035, blue: 0.050), Color(red: 0.030, green: 0.063, blue: 0.071)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color.cyan.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 470
            )
            .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    liveQuotes
                    captureHistory
                    supporterAI
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
                .frame(width: 600, height: 585)
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
                Text("0.12")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(.secondary.opacity(0.5)))
            }
            Text("급등락을 포착하고\n근거를 즉시 교차 확인합니다")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .tracking(-1.5)
            Text("가격 경보 뒤 Alpaca 뉴스, SEC 제출 이력, 기업 규모와 외부 리서치 링크를 연결하고 이후 성적을 이 Mac에 저장합니다. 조사 결과는 매수 추천이나 자동매매 신호가 아닙니다.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                SignalChip(title: "LIVE", detail: model.isLiveRunning ? "CONNECTED" : "STANDBY", color: model.isLiveRunning ? .green : .secondary)
                SignalChip(title: "FEED", detail: model.liveMonitoringMode.feed.rawValue.uppercased(), color: .cyan)
                SignalChip(title: "EVIDENCE", detail: "NEWS + SEC", color: Color(red: 0.79, green: 0.97, blue: 0.38))
                SignalChip(title: "DATASET", detail: "ML v\(SupporterDatasetStore.schemaVersion)", color: .purple)
            }
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
                        Text("시작하면 연결을 유지하며 조건에 맞는 급등·급락 후보가 나올 때까지 계속 작동합니다.")
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
                    LabeledContent("포착 방향") {
                        Picker("", selection: $model.liveRules.directionFilter) {
                            ForEach(LiveDirectionFilter.allCases) { direction in
                                Text(direction.label).tag(direction)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    LabeledContent("감지 시간") {
                        Picker("", selection: $model.liveRules.windowSeconds) {
                            ForEach([1, 2, 5, 30, 60], id: \.self) { seconds in
                                Text("\(seconds)초").tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 86)
                    }
                    LabeledContent("변동률") {
                        HStack(spacing: 4) {
                            TextField("", value: $model.liveRules.thresholdPercent, format: .number)
                                .frame(width: 58)
                            Text("%")
                        }
                    }
                    Spacer()
                }
                HStack(spacing: 18) {
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
                            Text("제한 없음").tag(0)
                            Text("10초").tag(10)
                            Text("30초").tag(30)
                            Text("1분").tag(60)
                            Text("2분").tag(120)
                            Text("5분").tag(300)
                            Text("15분").tag(900)
                            Text("30분").tag(1800)
                        }
                        .labelsHidden()
                        .frame(width: 104)
                    }
                }
                Text("감시 중에도 조건과 재알림 제한을 바꾸면 다음 수신 체결부터 바로 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.cyan.opacity(0.85))
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

                intradayChart

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

                if !model.liveMovers.isEmpty {
                    HStack {
                        Text("현재 수신 급등락 TOP 20")
                            .font(.subheadline.bold())
                        Text("\(model.liveRules.windowSeconds)초 창")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(model.liveMonitoringMode.scansAllSymbols ? "전체시장 SIP 범위" : "입력한 관심종목 IEX 범위")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("현재 수신 스트림의 변동 순위입니다. 경보에는 별도로 최소 거래대금과 변동률 조건이 적용됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 6) {
                        ForEach(Array(model.liveMovers.enumerated()), id: \.element.id) { index, movement in
                            LiveMovementRow(rank: index + 1, movement: movement) {
                                model.showChart(for: movement.symbol)
                            }
                        }
                    }
                }

                if !model.liveAlerts.isEmpty {
                    HStack {
                        Text("급등락 포착 로그")
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
                        LiveAlertCard(alert: alert) {
                            model.showChart(for: alert.symbol)
                        }
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
                            .onTapGesture {
                                model.showChart(for: trade.symbol)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    private var intradayChart: some View {
        IntradayChartPanel()
            .environmentObject(model)
    }

    private var supporterAI: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Supporter ML 데이터셋")
                        .font(.title3.bold())
                    Text("0.12 · 근거 결합")
                        .font(.caption.bold())
                        .foregroundStyle(Color(red: 0.79, green: 0.97, blue: 0.38))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 0.79, green: 0.97, blue: 0.38).opacity(0.13)))
                    Spacer()
                }
                Text("과거 300% 이상 급등 사건과 유사하지만 급등하지 않은 대조 표본을 함께 축적합니다. 고점 시간, 거래대금, 이후 되돌림까지 저장하지만 검증 전 예측률은 표시하지 않습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Metric(title: "검증 대기열", value: "\(model.supporterCandidates.count)건")
                    Metric(title: "300% 확인", value: "\(model.supporterCandidates.filter { $0.status == .qualifies }.count)건")
                    Metric(title: "대조 표본", value: "\(model.supporterCandidates.filter { $0.status == .comparison }.count)건")
                    Metric(title: "위험 라벨", value: "\(model.supporterCandidates.filter { $0.riskLabel != nil }.count)건")
                    Metric(title: "저장소", value: "ML v\(SupporterDatasetStore.schemaVersion)")
                }

                HStack(spacing: 10) {
                    TextField("티커 (예: ASTC)", text: $model.supporterSymbolText)
                        .frame(width: 150)
                    TextField("거래일 YYYY-MM-DD", text: $model.supporterDateText)
                        .frame(width: 175)
                    Button("후보 추가") { model.addSupporterCandidate() }
                        .buttonStyle(.borderedProminent)
                    Button("CSV 내보내기") { model.exportSupporterDataset() }
                        .buttonStyle(.bordered)
                        .disabled(model.supporterCandidates.isEmpty)
                    Text("BIRD, ASTC, AIXI는 초기 확인 대기열에 포함되어 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .textFieldStyle(.roundedBorder)

                Text(model.supporterStatus)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.79, green: 0.97, blue: 0.38))

                ForEach(model.supporterCandidates.prefix(8)) { candidate in
                    SupporterCandidateRow(candidate: candidate) {
                        model.verifySupporterCandidate(candidate)
                    } onPrepare: {
                        model.prepareCandidateEntry(from: candidate)
                    }
                }

                Text("검증은 Alpaca IEX 분봉을 사용합니다. 0.12부터 가격 경로에 뉴스·SEC 공시 개수와 희석 가능 양식 요약을 함께 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private var captureHistory: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("포착 기록과 2차 조사 보고")
                            .font(.title3.bold())
                        Text("실시간 포착 뒤 후속 성적과 뉴스·공시·기업 규모를 Mac 내부에 누적합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("새로고침") { model.refreshCaptureHistory() }
                        .buttonStyle(.bordered)
                    Button("CSV 내보내기") { model.exportCaptureHistory() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.captureRecords.isEmpty)
                }

                HStack(spacing: 12) {
                    Metric(title: "저장 기록", value: "\(model.captureRecords.count)건")
                    Metric(
                        title: "추적 중",
                        value: "\(model.captureRecords.filter { $0.status == .tracking }.count)건"
                    )
                    Metric(
                        title: "15분 완료",
                        value: "\(model.captureRecords.filter { $0.status == .completed }.count)건"
                    )
                    Metric(
                        title: "수신 누락",
                        value: "\(model.captureRecords.filter { $0.status == .incomplete }.count)건"
                    )
                    Metric(title: "저장 방식", value: "Mac 로컬 DB v\(CaptureHistoryStore.schemaVersion)")
                }

                Text(model.captureHistoryStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.catalystStatusMessage)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.79, green: 0.97, blue: 0.38))

                if model.captureRecords.isEmpty {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .frame(height: 86)
                        .overlay {
                            Text("시장 감시에서 급등락이 포착되면 이후 결과가 이곳에 쌓입니다.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                } else {
                    Text("1·5·15분 결과는 해당 시점을 지난 뒤 처음 수신된 체결 가격 기준입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.captureRecords.prefix(10)) { record in
                        CaptureRecordRow(record: record) {
                            model.retryCatalystResearch(for: record)
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

private struct IntradayChartPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("실시간 차트")
                        .font(.headline.bold())
                    Text("분봉과 일봉을 전환하고 좌우 이동·확대 축소로 흐름을 확인합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("티커", text: $model.chartSymbolText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { model.applyChartSymbol() }
                Button("조회") { model.applyChartSymbol() }
                    .buttonStyle(.bordered)
                Picker("봉", selection: $model.chartInterval) {
                    ForEach(ChartInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 262)
                Button {
                    model.refreshIntradayChart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Metric(title: "종목", value: model.selectedChartSymbol)
                Metric(title: "현재 봉", value: latestPrice)
                Metric(title: "표시 구간 변화", value: displayedChange)
                Metric(title: "봉 간격", value: model.chartInterval.label)
                Metric(title: "표시 봉 수", value: "\(model.visibleChartCandles.count)개")
                if model.chartIsLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.shiftChart(left: true)
                } label: {
                    Label("이전", systemImage: "chevron.left")
                }
                Button {
                    model.shiftChart(left: false)
                } label: {
                    Label("최근", systemImage: "chevron.right")
                }
                Divider().frame(height: 20)
                Button {
                    model.zoomChart(inward: true)
                } label: {
                    Label("확대", systemImage: "plus.magnifyingglass")
                }
                Button {
                    model.zoomChart(inward: false)
                } label: {
                    Label("축소", systemImage: "minus.magnifyingglass")
                }
                Text("차트 위에서 좌우로 드래그해 이동할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            CandleCanvas(candles: model.visibleChartCandles, interval: model.chartInterval)
                .frame(height: 292)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.065)))
                )
                .gesture(
                    DragGesture(minimumDistance: 20).onEnded { value in
                        model.shiftChart(left: value.translation.width < 0)
                    }
                )
                .simultaneousGesture(
                    MagnificationGesture().onEnded { scale in
                        model.zoomChart(inward: scale > 1)
                    }
                )

            Text(model.chartStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cyan.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.13)))
        )
    }

    private var latestPrice: String {
        model.chartCandles.last.map { "$\(String(format: "%.2f", $0.close))" } ?? "--"
    }

    private var displayedChange: String {
        guard let first = model.visibleChartCandles.first, let last = model.visibleChartCandles.last, first.open > 0 else { return "--" }
        return String(format: "%+.2f%%", ((last.close - first.open) / first.open) * 100)
    }
}

private struct CandleCanvas: View {
    let candles: [PriceCandle]
    let interval: ChartInterval

    var body: some View {
        if candles.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                Text("분봉 자료를 불러오면 여기에 캔들 차트가 표시됩니다.")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Canvas { context, size in
                let plotRect = CGRect(x: 12, y: 12, width: size.width - 72, height: size.height - 86)
                let volumeRect = CGRect(x: plotRect.minX, y: plotRect.maxY + 10, width: plotRect.width, height: 42)
                let lowest = candles.map(\.low).min() ?? 0
                let highest = candles.map(\.high).max() ?? lowest + 1
                let range = max(highest - lowest, max(highest * 0.002, 0.01))
                let maxVolume = max(candles.map(\.volume).max() ?? 1, 1)
                let candleWidth = max(2, min(10, plotRect.width / CGFloat(candles.count) * 0.64))
                let step = plotRect.width / CGFloat(max(candles.count, 1))
                func y(_ price: Double) -> CGFloat {
                    plotRect.maxY - CGFloat((price - lowest) / range) * plotRect.height
                }

                for line in 0...4 {
                    let lineY = plotRect.minY + (plotRect.height / 4) * CGFloat(line)
                    var path = Path()
                    path.move(to: CGPoint(x: plotRect.minX, y: lineY))
                    path.addLine(to: CGPoint(x: plotRect.maxX, y: lineY))
                    context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
                    let price = highest - range * Double(line) / 4
                    context.draw(
                        Text("$\(String(format: "%.2f", price))").font(.caption2).foregroundStyle(.secondary),
                        at: CGPoint(x: plotRect.maxX + 7, y: lineY),
                        anchor: .leading
                    )
                }

                for (index, candle) in candles.enumerated() {
                    let centerX = plotRect.minX + step * (CGFloat(index) + 0.5)
                    let color: Color = candle.close >= candle.open ? .green : .red
                    let volumeHeight = max(1, CGFloat(candle.volume / maxVolume) * volumeRect.height)
                    let volumeBar = CGRect(
                        x: centerX - candleWidth / 2,
                        y: volumeRect.maxY - volumeHeight,
                        width: candleWidth,
                        height: volumeHeight
                    )
                    context.fill(Path(roundedRect: volumeBar, cornerRadius: 1), with: .color(color.opacity(0.24)))
                    var wick = Path()
                    wick.move(to: CGPoint(x: centerX, y: y(candle.high)))
                    wick.addLine(to: CGPoint(x: centerX, y: y(candle.low)))
                    context.stroke(wick, with: .color(color.opacity(0.8)), lineWidth: 1)
                    let top = min(y(candle.open), y(candle.close))
                    let height = max(abs(y(candle.open) - y(candle.close)), 1.5)
                    let body = CGRect(x: centerX - candleWidth / 2, y: top, width: candleWidth, height: height)
                    context.fill(Path(roundedRect: body, cornerRadius: 1), with: .color(color.opacity(0.92)))
                }

                if let latest = candles.last {
                    let currentY = y(latest.close)
                    var currentPath = Path()
                    currentPath.move(to: CGPoint(x: plotRect.minX, y: currentY))
                    currentPath.addLine(to: CGPoint(x: plotRect.maxX, y: currentY))
                    context.stroke(currentPath, with: .color(.cyan.opacity(0.42)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if let first = candles.first, let last = candles.last {
                    context.draw(Text(label(for: first.startedAt)).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: plotRect.minX, y: volumeRect.maxY + 16), anchor: .leading)
                    context.draw(Text(label(for: last.startedAt)).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: plotRect.maxX, y: volumeRect.maxY + 16), anchor: .trailing)
                }
            }
        }
    }

    private func label(for date: Date) -> String {
        interval.isDaily ? DateFormatter.chartDay.string(from: date) : DateFormatter.liveTime.string(from: date)
    }
}

private struct LiveAlertCard: View {
    let alert: LiveAlert
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(alert.symbol)
                .font(.headline.bold())
                .frame(width: 70, alignment: .leading)
            Text(String(format: "%+.2f%%", alert.changePercent))
                .font(.headline.monospacedDigit())
                .foregroundStyle(alert.direction == .rising ? .green : .red)
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
        .background(RoundedRectangle(cornerRadius: 9).fill(cardColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(cardColor.opacity(0.22)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var cardColor: Color {
        alert.direction == .rising ? .green : .red
    }
}

private struct LiveMovementRow: View {
    let rank: Int
    let movement: LiveMovement
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(movement.symbol)
                .font(.callout.bold())
                .frame(width: 72, alignment: .leading)
            Text(movement.direction.label)
                .font(.caption.bold())
                .foregroundStyle(color)
                .frame(width: 40, alignment: .leading)
            Text(String(format: "%+.2f%%", movement.changePercent))
                .font(.callout.monospacedDigit().bold())
                .foregroundStyle(color)
                .frame(width: 86, alignment: .trailing)
            Text("$\(movement.latestPrice, specifier: "%.2f")")
                .font(.callout.monospacedDigit())
                .frame(width: 86, alignment: .trailing)
            Text("체결대금 $\(movement.dollarVolume.formatted(.number.notation(.compactName)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(DateFormatter.liveTime.string(from: movement.observedAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.055)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var color: Color {
        movement.direction == .rising ? .green : .red
    }
}

private struct SupporterCandidateRow: View {
    let candidate: SupporterCandidate
    let onVerify: () -> Void
    let onPrepare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(candidate.symbol)
                    .font(.callout.bold())
                    .frame(width: 58, alignment: .leading)
                Text(candidate.eventDate ?? "거래일 필요")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(candidate.eventDate == nil ? .orange : .secondary)
                    .frame(width: 105, alignment: .leading)
                Text(candidate.status.label)
                    .font(.caption.bold())
                    .foregroundStyle(statusColor)
                    .frame(width: 92, alignment: .leading)
                if let change = candidate.changePercent {
                    Text(String(format: "%+.2f%%", change))
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(change >= 0 ? .green : .red)
                        .frame(width: 84, alignment: .trailing)
                } else {
                    Text("--")
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .trailing)
                }
                Text(candidate.outcomeLabel ?? candidate.verificationNote ?? candidate.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if candidate.eventDate == nil {
                    Button("날짜 입력", action: onPrepare)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("가격 검증", action: onVerify)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if candidate.peakAt != nil || candidate.riskLabel != nil {
                HStack(spacing: 8) {
                    MiniBadge(title: "고점", value: candidate.peakAt.map { DateFormatter.liveTime.string(from: $0) } ?? "--")
                    MiniBadge(title: "세션", value: candidate.marketSession ?? "--")
                    MiniBadge(title: "거래대금", value: candidate.eventDollarVolume.map { "$\($0.formatted(.number.notation(.compactName)))" } ?? "--")
                    MiniBadge(title: "15분", value: percent(candidate.performance15Minutes))
                    MiniBadge(title: "60분", value: percent(candidate.performance60Minutes))
                    MiniBadge(title: "종가/고점", value: percent(candidate.closeFromPeakPercent))
                    MiniBadge(title: "뉴스", value: "\(candidate.newsCount)")
                    MiniBadge(title: "SEC", value: "\(candidate.filingCount)")
                    MiniBadge(title: "위험", value: candidate.riskLabel ?? "--")
                }
            }
            if let evidence = candidate.evidenceSummary, !evidence.isEmpty {
                Text(evidence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.035)))
    }

    private var statusColor: Color {
        switch candidate.status {
        case .pending: return .orange
        case .qualifies: return .green
        case .comparison: return .cyan
        case .failed: return .red
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%+.1f%%", value)
    }
}

private struct MiniBadge: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.caption2.monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.045)))
    }
}

private struct CaptureRecordRow: View {
    let record: CaptureRecord
    let onRetryResearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(record.symbol)
                            .font(.headline.bold())
                        Text(record.direction.label)
                            .font(.caption.bold())
                            .foregroundStyle(directionColor)
                    }
                    Text("\(record.marketSession) · \(DateFormatter.displayEastern.string(from: record.detectedAt)) ET")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 152, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(format: "%+.2f%% 포착", record.changePercent))
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(directionColor)
                    Text("$\(record.detectedPrice, specifier: "%.2f") · \(record.feed.rawValue.uppercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 115, alignment: .leading)

                OutcomeMetric(label: "1분", value: record.performance1Minute)
                OutcomeMetric(label: "5분", value: record.performance5Minutes)
                OutcomeMetric(label: "15분", value: record.performance15Minutes)

                VStack(alignment: .leading, spacing: 4) {
                    Text("고점 \(signed(record.maxAdvancePercent))")
                        .foregroundStyle(.green)
                    Text("저점 \(signed(record.maxDrawdownPercent))")
                        .foregroundStyle(.red)
                }
                .font(.caption.monospacedDigit())
                .frame(width: 110, alignment: .leading)

                Spacer()
                Text(record.status.label)
                    .font(.caption.bold())
                    .foregroundStyle(record.status == .tracking ? Color(red: 0.79, green: 0.97, blue: 0.38) : .secondary)
            }
            Divider()
            if let report = record.catalystReport {
                CatalystReportDetail(symbol: record.symbol, report: report, onRetry: onRetryResearch)
            } else {
                HStack {
                    Text("0.7 이전 기록입니다. 뉴스·공시·기업 규모 2차 보고가 아직 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("2차 조사 실행", action: onRetryResearch)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.08)))
    }

    private var directionColor: Color {
        record.direction == .rising ? .green : .red
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.2f%%", value)
    }
}

private struct CatalystReportDetail: View {
    let symbol: String
    let report: CatalystResearchReport
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(report.status.label)
                    .font(.caption.bold())
                    .foregroundStyle(report.hasDilutionRisk ? .orange : .secondary)
                if report.hasDilutionRisk {
                    Text("희석 가능성 확인 필요: \(report.dilutionForms.joined(separator: ", "))")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                Spacer()
                if report.status == .failed || report.status == .partial {
                    Button("다시 조사", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Text(report.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if report.status != .checking {
                HStack(spacing: 9) {
                    ResearchValue(title: "시가총액", value: compactDollars(report.marketCap))
                    ResearchValue(title: "발행주식 수", value: compactShares(report.shareClassSharesOutstanding))
                    ResearchValue(title: "가중 발행주식", value: compactShares(report.weightedSharesOutstanding))
                    ResearchValue(title: "최근 뉴스", value: "\(report.news.count)건")
                    ResearchValue(title: "최근 SEC", value: "\(report.filings.count)건")
                }
            }

            ForEach(report.news.prefix(2)) { news in
                if let url = news.url {
                    Link(destination: url) {
                        Label(news.headline, systemImage: "newspaper")
                    }
                    .font(.caption)
                } else {
                    Label(news.headline, systemImage: "newspaper")
                        .font(.caption)
                }
            }
            ForEach(report.filings.filter(\.isDilutionRelated).prefix(3)) { filing in
                if let url = filing.url {
                    Link(destination: url) {
                        Label("SEC \(filing.form) · \(filing.date) · 희석 가능성 관련", systemImage: "exclamationmark.doc")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            ForEach(report.warnings.prefix(2), id: \.self) { warning in
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Link(destination: stockTitanURL) {
                    Label("Stock Titan 뉴스 확인", systemImage: "bolt.horizontal.circle")
                }
                Link(destination: googleNewsURL) {
                    Label("Google News 교차 검색", systemImage: "magnifyingglass")
                }
            }
            .font(.caption.bold())
        }
    }

    private var stockTitanURL: URL {
        URL(string: "https://www.stocktitan.net/news/\(symbol)")!
    }

    private var googleNewsURL: URL {
        var components = URLComponents(string: "https://news.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(symbol) stock")]
        return components.url!
    }

    private func compactDollars(_ value: Double?) -> String {
        value.map { "$\($0.formatted(.number.notation(.compactName).precision(.fractionLength(1))))" } ?? "자료 없음"
    }

    private func compactShares(_ value: Double?) -> String {
        value.map { $0.formatted(.number.notation(.compactName).precision(.fractionLength(1))) } ?? "자료 없음"
    }
}

private struct ResearchValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.035)))
    }
}

private struct OutcomeMetric: View {
    let label: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let value {
                Text(String(format: "%+.2f%%", value))
                    .foregroundStyle(value >= 0 ? .green : .red)
            } else {
                Text("계산 중")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .frame(width: 62, alignment: .leading)
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
                HStack(spacing: 14) {
                    Link(destination: stockTitanURL) {
                        Label("Stock Titan 최신 뉴스", systemImage: "bolt.horizontal.circle")
                    }
                    Link(destination: googleNewsURL) {
                        Label("Google News 검색", systemImage: "magnifyingglass")
                    }
                }
                .font(.caption.bold())
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

    private var stockTitanURL: URL {
        URL(string: "https://www.stocktitan.net/news/\(report.symbol)")!
    }

    private var googleNewsURL: URL {
        var components = URLComponents(string: "https://news.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(report.symbol) stock \(DateFormatter.easternDate.string(from: report.detectedAt))")]
        return components.url!
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
                Text("SEC 제출 이력은 Massive 종목 정보의 CIK를 우선 사용해 연결합니다. 이메일은 SEC 요청 식별 규칙을 지키기 위해 사용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            Divider()
            Toggle("급등락 포착 및 분석 완료 알림 받기", isOn: Binding(
                get: { model.notificationsEnabled },
                set: { model.setNotificationsEnabled($0) }
            ))
            HStack {
                Text("재알림 제한")
                Spacer()
                Picker("", selection: $model.liveRules.cooldownSeconds) {
                    Text("없음").tag(0)
                    Text("10초").tag(10)
                    Text("30초").tag(30)
                    Text("1분").tag(60)
                    Text("2분").tag(120)
                    Text("5분").tag(300)
                    Text("15분").tag(900)
                    Text("30분").tag(1800)
                }
                .labelsHidden()
                .frame(width: 120)
            }
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

private struct SignalChip: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.22)))
    }
}

extension DateFormatter {
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

    static let chartDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "MM/dd"
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
