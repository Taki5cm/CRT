"use strict";

const {
  DEFAULT_ANALYSIS_CONFIG,
  detectCandidates,
  enrichCandidate,
  fetchSecFilings,
} = require("./historical-analysis");

const MAX_DETAIL_SYMBOLS = 4;

async function scanHistoricalMarket(input, fetchImpl = fetch) {
  const request = validateScanInput(input);
  const dailyBars = await fetchGroupedDaily(request, fetchImpl);
  const shortlisted = shortlistDailyCandidates(dailyBars, request.config);
  const detailSymbols = shortlisted.slice(0, MAX_DETAIL_SYMBOLS).map((candidate) => candidate.symbol);
  if (!detailSymbols.length) {
    return envelope(request, [], dailyBars.length, 0, shortlisted, []);
  }
  const barsBySymbol = {};
  for (const symbol of detailSymbols) {
    barsBySymbol[symbol] = await fetchMinuteBars(request, symbol, fetchImpl);
  }
  const candidates = detectCandidates(barsBySymbol, request.config, request.date);
  const minuteBarsExamined = Object.values(barsBySymbol).reduce((count, bars) => count + bars.length, 0);
  if (!candidates.length) {
    return envelope(request, [], dailyBars.length, minuteBarsExamined, shortlisted, []);
  }
  const warnings = [];
  const filings = await fetchSecFilings(
    { date: request.date, secContact: request.secContact },
    [...new Set(candidates.map((candidate) => candidate.symbol))],
    fetchImpl
  ).catch((error) => {
    warnings.push(`SEC 공시 조회: ${error.message}`);
    return {};
  });
  const reports = candidates.map((candidate) =>
    enrichCandidate(candidate, [], filings[candidate.symbol] || [])
  );
  return envelope(request, reports, dailyBars.length, minuteBarsExamined, shortlisted, warnings);
}

function validateScanInput(input = {}) {
  const massiveApiKey = String(input.massiveApiKey || "").trim();
  const secContact = String(input.secContact || "").trim();
  const date = String(input.date || "");
  if (!massiveApiKey) throw new Error("Massive API 키를 입력해주세요.");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(secContact)) {
    throw new Error("SEC 조회용 연락 이메일을 입력해주세요.");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("분석 날짜를 선택해주세요.");
  if (date >= new Date().toISOString().slice(0, 10)) {
    throw new Error("전체시장 스캔은 지난 날짜만 선택할 수 있습니다.");
  }
  const config = { ...DEFAULT_ANALYSIS_CONFIG };
  for (const field of ["windowSeconds", "thresholdPct", "minPrice", "minDollarVolume"]) {
    const value = Number(input.config && input.config[field]);
    if (Number.isFinite(value)) config[field] = value;
  }
  if (config.windowSeconds < 60 || config.windowSeconds > 1800 || config.thresholdPct <= 0) {
    throw new Error("감지 기준을 확인해주세요.");
  }
  return { massiveApiKey, secContact, date, config };
}

async function fetchGroupedDaily(request, fetchImpl) {
  const url = new URL(
    `https://api.massive.com/v2/aggs/grouped/locale/us/market/stocks/${request.date}`
  );
  url.searchParams.set("adjusted", "true");
  url.searchParams.set("apiKey", request.massiveApiKey);
  const data = await getJson(url, fetchImpl, "Massive 전체시장 일봉");
  return data.results || [];
}

function shortlistDailyCandidates(dailyBars, config) {
  return dailyBars
    .filter((bar) => !bar.otc && Number(bar.h) >= config.minPrice)
    .map((bar) => {
      const changePct = ((Number(bar.h) - Number(bar.l)) / Number(bar.l)) * 100;
      const dollarVolume = Number(bar.v) * Number(bar.vw || bar.c);
      return { symbol: bar.T, changePct, dollarVolume };
    })
    .filter((bar) => bar.changePct >= config.thresholdPct && bar.dollarVolume >= config.minDollarVolume)
    .sort((left, right) => right.changePct - left.changePct || right.dollarVolume - left.dollarVolume);
}

async function fetchMinuteBars(request, symbol, fetchImpl) {
  const url = new URL(
    `https://api.massive.com/v2/aggs/ticker/${encodeURIComponent(symbol)}/range/1/minute/${request.date}/${request.date}`
  );
  url.searchParams.set("adjusted", "true");
  url.searchParams.set("sort", "asc");
  url.searchParams.set("limit", "50000");
  url.searchParams.set("apiKey", request.massiveApiKey);
  const data = await getJson(url, fetchImpl, `Massive ${symbol} 분봉`);
  return (data.results || []).map((bar) => ({
    ...bar,
    t: new Date(Number(bar.t)).toISOString(),
  }));
}

function envelope(request, reports, marketCount, minuteBarsExamined = 0, shortlisted, warnings) {
  return {
    date: request.date,
    symbols: shortlisted.slice(0, MAX_DETAIL_SYMBOLS).map((candidate) => candidate.symbol),
    config: request.config,
    feed: "Massive historical market scan",
    methodology:
      `전체시장 일봉의 당일 저가-고가 변동으로 후보를 좁힌 뒤 상위 ${MAX_DETAIL_SYMBOLS}개만 1분봉으로 재검사합니다. 무료 호출 한도에 맞춘 베타 방식이며 모든 장중 급등을 보장하지 않습니다.`,
    reports,
    totals: {
      barsExamined: minuteBarsExamined,
      marketSymbolsScanned: marketCount,
      newsRetrieved: 0,
      filingsRetrieved: reports.reduce((count, report) => count + report.filings.length, 0),
    },
    shortlistCount: shortlisted.length,
    warnings,
  };
}

async function getJson(url, fetchImpl, label) {
  const response = await fetchImpl(url.toString(), { headers: { Accept: "application/json" } });
  if (!response.ok) {
    const body = await response.text();
    const detail = response.status === 401 || response.status === 403
      ? "API 키 또는 접근 권한을 확인해주세요."
      : body.slice(0, 120);
    throw new Error(`${label} 조회 실패 (${response.status}). ${detail}`);
  }
  return response.json();
}

module.exports = { MAX_DETAIL_SYMBOLS, scanHistoricalMarket, shortlistDailyCandidates };
