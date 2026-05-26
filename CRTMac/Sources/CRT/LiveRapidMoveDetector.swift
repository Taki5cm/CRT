import Foundation

final class LiveRapidMoveDetector {
    private var ticksBySymbol: [String: [LiveTrade]] = [:]
    private var cooldownUntil: [String: Date] = [:]

    func reset() {
        ticksBySymbol = [:]
        cooldownUntil = [:]
    }

    func process(trade: LiveTrade, rules: LiveScanRules, feed: LiveDataFeed) -> LiveAlert? {
        let cutoff = trade.occurredAt.addingTimeInterval(TimeInterval(-rules.windowSeconds))
        var ticks = ticksBySymbol[trade.symbol, default: []].filter { $0.occurredAt >= cutoff }
        ticks.append(trade)
        ticksBySymbol[trade.symbol] = ticks

        if let cooldown = cooldownUntil[trade.symbol], trade.occurredAt < cooldown {
            return nil
        }

        let windowStart = trade.occurredAt.addingTimeInterval(TimeInterval(-rules.windowSeconds))
        let window = ticks.filter { $0.occurredAt >= windowStart }
        guard window.count >= 2,
              let baseline = window.map(\.price).min(),
              baseline > 0,
              trade.price >= rules.minimumPrice else { return nil }

        let change = (trade.price - baseline) / baseline * 100
        let dollars = window.reduce(0) { $0 + $1.price * Double($1.size) }
        guard change >= rules.thresholdPercent, dollars >= rules.minimumDollarVolume else { return nil }

        cooldownUntil[trade.symbol] = trade.occurredAt.addingTimeInterval(TimeInterval(rules.cooldownSeconds))
        return LiveAlert(
            symbol: trade.symbol,
            detectedAt: trade.receivedAt,
            baselinePrice: baseline,
            latestPrice: trade.price,
            changePercent: change,
            dollarVolume: dollars,
            windowSeconds: rules.windowSeconds,
            feed: feed
        )
    }
}
