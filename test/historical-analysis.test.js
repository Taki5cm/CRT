"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { analyzeHistoricalMarket, detectCandidates } = require("../src/historical-analysis");

test("detects a rapid historical one-minute candidate", () => {
  const reports = detectCandidates({
    TEST: [
      { t: "2026-05-22T14:30:00Z", l: 10, h: 11.25, c: 11, v: 20000, vw: 10.8 },
    ],
  }, {
    windowSeconds: 60,
    thresholdPct: 10,
    minPrice: 1,
    minDollarVolume: 10000,
    maxResults: 10,
  }, "2026-05-22");
  assert.equal(reports.length, 1);
  assert.equal(reports[0].symbol, "TEST");
  assert.equal(reports[0].changePct, 12.5);
});

test("enriches a candidate with real-source shaped news and SEC filings", async () => {
  const fetchImpl = async (url) => {
    if (url.includes("/v2/stocks/bars")) {
      return ok({
        bars: {
          TEST: [{ t: "2026-05-22T14:30:00Z", l: 10, h: 11.25, c: 11, v: 20000, vw: 10.8 }],
        },
      });
    }
    if (url.includes("/v1beta1/news")) {
      return ok({
        news: [{
          headline: "Test company announces material update",
          created_at: "2026-05-22T14:25:00Z",
          symbols: ["TEST"],
          source: "Benzinga",
          url: "https://example.com/news",
        }],
      });
    }
    if (url.includes("company_tickers.json")) {
      return ok({ 0: { ticker: "TEST", cik_str: 1234 } });
    }
    if (url.includes("CIK0000001234.json")) {
      return ok({
        filings: {
          recent: {
            filingDate: ["2026-05-22"],
            accessionNumber: ["0000001234-26-000001"],
            primaryDocument: ["form8k.htm"],
            form: ["8-K"],
          },
        },
      });
    }
    throw new Error(`Unexpected URL: ${url}`);
  };
  const result = await analyzeHistoricalMarket({
    apiKey: "key",
    apiSecret: "secret",
    secContact: "owner@example.com",
    date: "2026-05-22",
    symbols: "TEST",
    config: {
      windowSeconds: 60,
      thresholdPct: 10,
      minPrice: 1,
      minDollarVolume: 10000,
    },
  }, fetchImpl);
  assert.equal(result.reports.length, 1);
  assert.equal(result.reports[0].classification, "filing-found");
  assert.equal(result.reports[0].filings[0].form, "8-K");
  assert.equal(result.reports[0].news[0].headline, "Test company announces material update");
});

function ok(data) {
  return {
    ok: true,
    json: async () => data,
  };
}
