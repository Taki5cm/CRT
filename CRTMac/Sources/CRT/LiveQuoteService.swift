import Foundation

final class LiveQuoteService {
    private var task: URLSessionWebSocketTask?
    private var requestedSymbols: [String] = []
    private var onTrade: ((LiveTrade) -> Void)?
    private var onStatus: ((String, Bool) -> Void)?

    func connect(
        key: String,
        secret: String,
        symbols: [String],
        onTrade: @escaping (LiveTrade) -> Void,
        onStatus: @escaping (String, Bool) -> Void
    ) {
        disconnect()
        requestedSymbols = symbols
        self.onTrade = onTrade
        self.onStatus = onStatus

        guard let url = URL(string: "wss://stream.data.alpaca.markets/v2/iex") else {
            onStatus("실시간 연결 주소를 만들지 못했습니다.", false)
            return
        }
        let webSocket = URLSession.shared.webSocketTask(with: url)
        task = webSocket
        webSocket.resume()
        send(["action": "auth", "key": key, "secret": secret])
        receiveNext()
    }

    func disconnect() {
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
                self?.onStatus?("Alpaca 실시간 연결에 메시지를 보내지 못했습니다.", false)
            }
        }
    }

    private func receiveNext() {
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self, self.task != nil else { return }
            switch result {
            case .failure:
                self.onStatus?("Alpaca 실시간 연결이 끊어졌습니다. 다시 연결해주세요.", false)
                self.disconnect()
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
                onStatus?("인증 완료. 관심종목 가격 구독을 시작합니다...", true)
                subscribe()
            case "subscription":
                onStatus?("IEX 실시간 가격 수신 중: \(requestedSymbols.joined(separator: ", "))", true)
            case "t":
                guard let symbol = packet.symbol, let price = packet.price else { continue }
                onTrade?(LiveTrade(
                    symbol: symbol,
                    price: price,
                    size: packet.size ?? 0,
                    receivedAt: Date()
                ))
            case "error":
                let message = packet.message ?? "알 수 없는 오류"
                onStatus?("Alpaca 실시간 연결 실패: \(message). API Key와 Secret을 확인해주세요.", false)
                disconnect()
            default:
                continue
            }
        }
    }
}

private struct AlpacaStreamPacket: Decodable {
    let type: String
    let message: String?
    let symbol: String?
    let price: Double?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case type = "T"
        case message = "msg"
        case symbol = "S"
        case price = "p"
        case size = "s"
    }
}
