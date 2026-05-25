"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { RapidMoveDetector } = require("../src/detector");

test("creates an alert for a qualifying rapid move", () => {
  const detector = new RapidMoveDetector({
    windowSeconds: 60,
    thresholdPct: 10,
    minPrice: 1,
    minDollarVolume: 10000,
  });
  const start = Date.now();
  assert.equal(detector.processTick({ symbol: "TEST", price: 2, size: 4000, timestamp: start }), null);
  const alert = detector.processTick({ symbol: "TEST", price: 2.25, size: 4000, timestamp: start + 30000 });
  assert.equal(alert.symbol, "TEST");
  assert.equal(alert.changePct, 12.5);
});

test("does not alert on an illiquid move", () => {
  const detector = new RapidMoveDetector({
    thresholdPct: 10,
    minDollarVolume: 100000,
  });
  const start = Date.now();
  detector.processTick({ symbol: "THIN", price: 1, size: 10, timestamp: start });
  const alert = detector.processTick({ symbol: "THIN", price: 1.3, size: 10, timestamp: start + 20000 });
  assert.equal(alert, null);
});

test("honors the cooldown between repeated alerts", () => {
  const detector = new RapidMoveDetector({
    thresholdPct: 5,
    minDollarVolume: 1,
    cooldownSeconds: 180,
  });
  const start = Date.now();
  detector.processTick({ symbol: "FAST", price: 10, size: 100, timestamp: start });
  assert.ok(detector.processTick({ symbol: "FAST", price: 11, size: 100, timestamp: start + 1000 }));
  assert.equal(
    detector.processTick({ symbol: "FAST", price: 12, size: 100, timestamp: start + 2000 }),
    null
  );
});
