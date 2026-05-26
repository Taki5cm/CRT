import Foundation

final class LiveQuoteService {
    private var task: URLSessionWebSocketTask?
    private var requestedSymbols: [String] = []
    private var allSymbols = false
    private var feed: LiveDataFeed = .iex
    private var rules = LiveScanRules()
    private var key = ""
    private var secret = ""
    private var shouldStayConnected = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var receivedTradeCount = 0
    private var lastActivityPublishedAt = Date.distantPast
    private var onTrade: ((LiveTrade) -> Void)?
    private var onAlert: ((LiveAlert) -> Void)?
    private var onActivity: ((Int, Date) -> Void)?
    private var onStatus: ((String, Bool) -> Void)?
    private let detector = LiveRapidMoveDetector()
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func connect(
        key: String,
        secret: String,
        feed: LiveDataFeed,
        symbols: [String],
        allSymbols: Bool,
        rules: LiveScanRules,
        onTrade: @escaping (LiveTrade) -> Void,
        onAlert: @escaping (LiveAlert) -> Void,
        onActivity: @escaping (Int, Date) -> Void,
        onStatus: @escaping (String, Bool) -> Void
    ) {
        disconnect()
        self.key = key
        self.secret = secret
        requestedSymbols = allSymbols ? ["*"] : symbols
        self.allSymbols = allSymbols
        self.feed = feed
        self.rules = rules
        self.onTrade = onTrade
        self.onAlert = onAlert
        self.onActivity = onActivity
        self.onStatus = onStatus
        detector.reset()
        receivedTradeCount = 0
        lastActivityPublishedAt = .distantPast
        shouldStayConnected = true
        openConnection()
    }

    private func openConnection() {
        guard let url = URL(string: "wss://stream.data.alpaca.markets/v2/\(feed.rawValue)") else {
            onStatus?("실시간 연결 주소를 만들지 못했습니다.", false)
            return
        }
        let webSocket = URLSession.shared.webSocketTask(with: url)
        task = webSocket
        webSocket.resume()
        send(["action": "auth", "key": key, "secret": secret])
        receiveNext()
    }

    func disconnect() {
        shouldStayConnected = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func subscribe() {
        send(["action": "subscribe", "trades": requestedSymbols])
    }

    private func send(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            if error != nil {
                self?.scheduleReconnect()
            }
        }
    }

    private func receiveNext() {
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self, self.task != nil else { return }
            switch result {
            case .failure:
                self.scheduleReconnect()
            case .success(let message):
                let data: Data?
                switch message {
                case .string(let text): data = text.data(using: .utf8)
                case .data(let bytes): data = bytes
                @unknown default: data = nil
                }
                if let data {
                    self.handle(data)
                }
                self.receiveNext()
            }
        }
    }

    private func handle(_ data: Data) {
        guard let packets = try? JSONDecoder().decode([AlpacaStreamPacket].self, from: data) else { return }
        for packet in packets {
            switch packet.type {
            case "success" where packet.message == "authenticated":
                onStatus?("인증 완료. 실시간 체결 구독을 시작합니다...", true)
                subscribe()
            case "subscription":
                let target = requestedSymbols == ["*"] ? "전체 상장주" : requestedSymbols.joined(separator: ", ")
                onStatus?("실시간 체결 감지 중: \(target)", true)
            case "t":
                guard let symbol = packet.symbol, let price = packet.price else { continue }
                let receivedAt = Date()
                let trade = LiveTrade(
                    symbol: symbol,
                    price: price,
                    size: packet.size ?? 0,
                    occurredAt: packet.timestamp.flatMap(timestampFormatter.date(from:)) ?? receivedAt,
                    receivedAt: receivedAt
                )
                receivedTradeCount += 1
                if !allSymbols || receivedAt.timeIntervalSince(lastActivityPublishedAt) >= 1 {
                    lastActivityPublishedAt = receivedAt
                    onActivity?(receivedTradeCount, receivedAt)
                }
                if !allSymbols {
                    onTrade?(trade)
                }
                if let alert = detector.process(trade: trade, rules: rules, feed: feed) {
                    onAlert?(alert)
                }
            case "error":
                let message = packet.message ?? "알 수 없는 오류"
                shouldStayConnected = false
                onStatus?("Alpaca 실시간 연결 실패: \(message). 키 또는 선택한 피드 구독 권한을 확인해주세요.", false)
                disconnect()
            default:
                continue
            }
        }
    }

    private func scheduleReconnect() {
        guard shouldStayConnected, reconnectWorkItem == nil else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onStatus?("연결이 끊어졌습니다. 3초 후 시장 감시를 자동으로 다시 연결합니다...", true)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.shouldStayConnected else { return }
            self.reconnectWorkItem = nil
            self.onStatus?("시장 감시를 다시 연결하고 있습니다...", true)
            self.openConnection()
        }
        reconnectWorkItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: item)
    }
}

private struct AlpacaStreamPacket: Decodable {
    let type: String
    let message: String?
    let symbol: String?
    let price: Double?
    let size: Int?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case type = "T"
        case message = "msg"
        case symbol = "S"
        case price = "p"
        case size = "s"
        case timestamp = "t"
    }
}
