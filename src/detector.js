"use strict";

const DEFAULT_CONFIG = Object.freeze({
  windowSeconds: 60,
  thresholdPct: 10,
  minPrice: 1,
  minDollarVolume: 100000,
  cooldownSeconds: 180,
});

class RapidMoveDetector {
  constructor(config = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.history = new Map();
    this.lastAlertAt = new Map();
  }

  updateConfig(config = {}) {
    this.config = { ...this.config, ...config };
    return this.config;
  }

  reset() {
    this.history.clear();
    this.lastAlertAt.clear();
  }

  processTick(tick) {
    validateTick(tick);
    const current = {
      symbol: tick.symbol.toUpperCase(),
      price: Number(tick.price),
      size: Number(tick.size),
      timestamp: Number(tick.timestamp),
      session: tick.session || "regular",
    };
    const windowMs = this.config.windowSeconds * 1000;
    const startAt = current.timestamp - windowMs;
    const existing = this.history.get(current.symbol) || [];
    const points = existing.filter((point) => point.timestamp >= startAt);
    points.push(current);
    this.history.set(current.symbol, points);

    if (current.price < this.config.minPrice || points.length < 2) {
      return null;
    }

    const baseline = points[0];
    const pctChange = ((current.price - baseline.price) / baseline.price) * 100;
    const dollarVolume = points.reduce((total, point) => total + point.price * point.size, 0);
    const lastAlert = this.lastAlertAt.get(current.symbol) || 0;
    const inCooldown = current.timestamp - lastAlert < this.config.cooldownSeconds * 1000;

    if (
      pctChange < this.config.thresholdPct ||
      dollarVolume < this.config.minDollarVolume ||
      inCooldown
    ) {
      return null;
    }

    this.lastAlertAt.set(current.symbol, current.timestamp);
    return {
      id: `${current.symbol}-${current.timestamp}`,
      symbol: current.symbol,
      detectedAt: current.timestamp,
      session: current.session,
      price: current.price,
      baselinePrice: baseline.price,
      changePct: round(pctChange),
      dollarVolume: Math.round(dollarVolume),
      tradeCount: points.length,
      windowSeconds: this.config.windowSeconds,
      classification: "investigating",
    };
  }
}

function validateTick(tick) {
  if (!tick || typeof tick.symbol !== "string" || tick.symbol.trim() === "") {
    throw new Error("Tick must include a symbol.");
  }
  for (const field of ["price", "size", "timestamp"]) {
    if (!Number.isFinite(Number(tick[field])) || Number(tick[field]) <= 0) {
      throw new Error(`Tick ${field} must be a positive number.`);
    }
  }
}

function round(value) {
  return Math.round(value * 100) / 100;
}

module.exports = { RapidMoveDetector, DEFAULT_CONFIG };
