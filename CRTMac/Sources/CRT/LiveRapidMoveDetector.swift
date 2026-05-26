import Foundation

final class LiveRapidMoveDetector {
    private var ticksBySymbol: [String: [LiveTrade]] = [:]
    private var cooldownUntil: [String: Date] = [:]

    func reset() {
        ticksBySymbol = [:]
        cooldownUntil = [:]
    }

    func process(trade: LiveTrade, rules: LiveScanRules, feed: LiveDataFeed) -> LiveDetectionUpdate {
        let cutoff = trade.occurredAt.addingTimeInterval(TimeInterval(-rules.windowSeconds))
        var ticks = ticksBySymbol[trade.symbol, default: []].filter { $0.occurredAt >= cutoff }
        ticks.append(trade)
        ticksBySymbol[trade.symbol] = ticks

        let windowStart = trade.occurredAt.addingTimeInterval(TimeInterval(-rules.windowSeconds))
        let window = ticks.filter { $0.occurredAt >= windowStart }
        guard window.count >= 2,
              let low = window.map(\.price).min(),
              let high = window.map(\.price).max(),
              low > 0,
              high > 0,
              trade.price >= rules.minimumPrice else {
            return LiveDetectionUpdate(movement: nil, alert: nil)
        }

        let rise = (trade.price - low) / low * 100
        let fall = (trade.price - high) / high * 100
        let direction: LiveMoveDirection
        let change: Double
        let baseline: Double
        if abs(fall) > abs(rise) {
            direction = .falling
            change = fall
            baseline = high
        } else {
            direction = .rising
            change = rise
            baseline = low
        }
        let dollars = window.reduce(0) { $0 + $1.price * Double($1.size) }
        let movement = LiveMovement(
            symbol: trade.symbol,
            direction: direction,
            changePercent: change,
            latestPrice: trade.price,
            dollarVolume: dollars,
            observedAt: trade.receivedAt,
            windowSeconds: rules.windowSeconds,
            feed: feed
        )
        let cooldownKey = "\(trade.symbol)-\(direction.label)"
        guard rules.directionFilter.includes(direction),
              abs(change) >= rules.thresholdPercent,
              dollars >= rules.minimumDollarVolume,
              !(cooldownUntil[cooldownKey].map { trade.occurredAt < $0 } ?? false) else {
            return LiveDetectionUpdate(movement: movement, alert: nil)
        }

        cooldownUntil[cooldownKey] = trade.occurredAt.addingTimeInterval(TimeInterval(rules.cooldownSeconds))
        let alert = LiveAlert(
            symbol: trade.symbol,
            detectedAt: trade.receivedAt,
            baselinePrice: baseline,
            latestPrice: trade.price,
            changePercent: change,
            direction: direction,
            dollarVolume: dollars,
            windowSeconds: rules.windowSeconds,
            feed: feed
        )
        return LiveDetectionUpdate(movement: movement, alert: alert)
    }
}
