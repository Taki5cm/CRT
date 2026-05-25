"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { scanHistoricalMarket, shortlistDailyCandidates } = require("../src/market-scan");

test("shortlists high-range daily candidates for detailed inspection", () => {
  const candidates = shortlistDailyCandidates([
    { T: "FAST", l: 2, h: 2.4, c: 2.3, v: 100000, vw: 2.2 },
    { T: "SLOW", l: 10, h: 10.2, c: 10.1, v: 100000, vw: 10.1 },
    { T: "OTCX", l: 1, h: 3, c: 2, v: 100000, vw: 2, otc: true },
  ], { thresholdPct: 10, minPrice: 1, minDollarVolume: 10000 });
  assert.deepEqual(candidates.map((candidate) => candidate.symbol), ["FAST"]);
});

test("scans daily market candidates and checks detailed minute bars", async () => {
  const fetchImpl = async (url) => {
    if (url.includes("/aggs/grouped/")) {
      return ok({ results: [{ T: "FAST", l: 10, h: 12, c: 11, v: 500000, vw: 11 }] });
    }
    if (url.includes("/aggs/ticker/FAST/")) {
      return ok({ results: [{ t: Date.parse("2026-05-22T14:30:00Z"), l: 10, h: 11.5, c: 11, v: 50000, vw: 10.8 }] });
    }
    if (url.includes("company_tickers.json")) {
      return ok({ 0: { ticker: "FAST", cik_str: 777 } });
    }
    if (url.includes("CIK0000000777.json")) {
      return ok({
        filings: {
          recent: {
            filingDate: ["2026-05-22"],
            accessionNumber: ["0000000777-26-000001"],
            primaryDocument: ["report.htm"],
            form: ["8-K"],
          },
        },
      });
    }
    throw new Error(`Unexpected URL: ${url}`);
  };
  const result = await scanHistoricalMarket({
    massiveApiKey: "massive-key",
    secContact: "owner@example.com",
    date: "2026-05-22",
    config: { windowSeconds: 60, thresholdPct: 10, minPrice: 1, minDollarVolume: 10000 },
  }, fetchImpl);
  assert.equal(result.reports.length, 1);
  assert.equal(result.reports[0].symbol, "FAST");
  assert.equal(result.reports[0].classification, "filing-found");
  assert.equal(result.totals.marketSymbolsScanned, 1);
});

function ok(data) {
  return {
    ok: true,
    json: async () => data,
  };
}
