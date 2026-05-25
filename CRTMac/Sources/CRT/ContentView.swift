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
                    controls
                    actions
                    status
                    results
                }
                .padding(28)
                .frame(maxWidth: 1120)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.isShowingSettings) {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 390)
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
                Text("v0.1 BETA")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(.secondary.opacity(0.5)))
            }
            Text("지난 거래일의 급등 이유를\n실제 자료로 추적합니다")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .tracking(-1.5)
            Text("실시간 매매 도구가 아닌 사후 조사 베타입니다. 결과는 투자 추천이나 매매 신호가 아닙니다.")
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        GroupBox {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    LabeledContent("분석 날짜") {
                        DatePicker("", selection: $model.selectedDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
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
                            TextField("", value: $model.rules.minimumDollarVolume, format: .number)
                                .frame(width: 100)
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
            Text("분석 조건")
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                model.scanWholeMarket()
            } label: {
                Label("전체시장 급변 후보 스캔", systemImage: "waveform.path.ecg.magnifyingglass")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.50, green: 0.78, blue: 0.36))
            .disabled(model.isLoading)

            Button {
                model.analyzeWatchlist()
            } label: {
                Label("관심종목 뉴스·공시 분석", systemImage: "newspaper")
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
                Text(result.methodology)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(result.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if result.reports.isEmpty {
                    emptyResult
                } else {
                    ForEach(result.reports) { ReportCard(report: $0) }
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
            Text("무료 계정의 키를 입력하면 Mac 키체인에 안전하게 저장됩니다. 처음에는 Massive 키만 입력해 전체시장 스캔부터 시험할 수 있습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Group {
                SecureField("Massive API Key", text: $model.massiveKey)
                SecureField("Alpaca API Key", text: $model.alpacaKey)
                SecureField("Alpaca Secret Key", text: $model.alpacaSecret)
                TextField("SEC 조회용 이메일", text: $model.secEmail)
            }
            .textFieldStyle(.roundedBorder)
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
    static let displayEastern: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()
}
