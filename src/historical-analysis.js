"use strict";

const DEFAULT_ANALYSIS_CONFIG = Object.freeze({
  windowSeconds: 60,
  thresholdPct: 10,
  minPrice: 1,
  minDollarVolume: 100000,
  maxResults: 30,
});
const NEW_YORK_TIME = new Intl.DateTimeFormat("en-CA", {
  timeZone: "America/New_York",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

async function analyzeHistoricalMarket(input, fetchImpl = fetch) {
  const request = validateInput(input);
  const bars = await fetchAlpacaBars(request, fetchImpl);
  const candidates = detectCandidates(bars, request.config, request.date);
  const symbols = [...new Set(candidates.map((candidate) => candidate.symbol))];

  if (!symbols.length) {
    return resultEnvelope(request, [], {
      barsExamined: countBars(bars),
      newsRetrieved: 0,
      filingsRetrieved: 0,
    }, []);
  }

  const warnings = [];
  const [news, filings] = await Promise.all([
    fetchAlpacaNews(request, symbols, fetchImpl).catch((error) => {
      warnings.push(`뉴스 조회: ${error.message}`);
      return Object.fromEntries(symbols.map((symbol) => [symbol, []]));
    }),
    fetchSecFilings(request, symbols, fetchImpl).catch((error) => {
      warnings.push(`SEC 공시 조회: ${error.message}`);
      return Object.fromEntries(symbols.map((symbol) => [symbol, []]));
    }),
  ]);
  const reports = candidates.map((candidate) =>
    enrichCandidate(candidate, news[candidate.symbol] || [], filings[candidate.symbol] || [])
  );

  return resultEnvelope(request, reports, {
    barsExamined: countBars(bars),
    newsRetrieved: Object.values(news).reduce((count, entries) => count + entries.length, 0),
    filingsRetrieved: Object.values(filings).reduce((count, entries) => count + entries.length, 0),
  }, warnings);
}

function validateInput(input = {}) {
  const apiKey = String(input.apiKey || "").trim();
  const apiSecret = String(input.apiSecret || "").trim();
  const secContact = String(input.secContact || "").trim();
  if (!apiKey || !apiSecret) {
    throw new Error("Alpaca API 키와 Secret Key를 입력해주세요.");
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(secContact)) {
    throw new Error("SEC 조회용 연락 이메일을 입력해주세요.");
  }
  const symbols = [...new Set(String(input.symbols || "")
    .toUpperCase()
    .split(/[\s,]+/)
    .filter(Boolean)
    .map((symbol) => symbol.replace(/[^A-Z0-9.-]/g, ""))
    .filter(Boolean))];
  if (!symbols.length || symbols.length > 30) {
    throw new Error("분석 종목을 1개 이상 30개 이하로 입력해주세요.");
  }
  const date = String(input.date || "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error("분석 날짜를 선택해주세요.");
  }
  if (date >= todayInNewYork()) {
    throw new Error("무료 사후 분석은 미국 동부시간 기준 지난 날짜만 선택할 수 있습니다.");
  }
  const config = { ...DEFAULT_ANALYSIS_CONFIG };
  for (const field of ["windowSeconds", "thresholdPct", "minPrice", "minDollarVolume"]) {
    const value = Number(input.config && input.config[field]);
    if (Number.isFinite(value)) config[field] = value;
  }
  if (config.windowSeconds < 60 || config.windowSeconds > 1800) {
    throw new Error("실제 분봉 분석의 시간 창은 60초에서 1800초 사이여야 합니다.");
  }
  if (config.thresholdPct <= 0 || config.minPrice < 0 || config.minDollarVolume < 0) {
    throw new Error("감지 기준을 확인해주세요.");
  }
  return { apiKey, apiSecret, secContact, symbols, date, config };
}

async function fetchAlpacaBars(request, fetchImpl) {
  const query = new URLSearchParams({
    symbols: request.symbols.join(","),
    timeframe: "1Min",
    start: `${request.date}T00:00:00Z`,
    end: `${addDays(request.date, 2)}T00:00:00Z`,
    limit: "10000",
    adjustment: "split",
    feed: "sip",
  });
  const collected = Object.fromEntries(request.symbols.map((symbol) => [symbol, []]));
  let url = `https://data.alpaca.markets/v2/stocks/bars?${query}`;
  let pages = 0;
  while (url && pages < 40) {
    const data = await getJson(url, alpacaHeaders(request), fetchImpl, "Alpaca 시세");
    Object.entries(data.bars || {}).forEach(([symbol, entries]) => {
      if (collected[symbol]) collected[symbol].push(...entries);
    });
    pages += 1;
    if (!data.next_page_token) break;
    const next = new URL(url);
    next.searchParams.set("page_token", data.next_page_token);
    url = next.toString();
  }
  return collected;
}

async function fetchAlpacaNews(request, symbols, fetchImpl) {
  const query = new URLSearchParams({
    symbols: symbols.join(","),
    start: `${request.date}T00:00:00Z`,
    end: `${addDays(request.date, 2)}T00:00:00Z`,
    limit: "50",
    sort: "asc",
  });
  const data = await getJson(
    `https://data.alpaca.markets/v1beta1/news?${query}`,
    alpacaHeaders(request),
    fetchImpl,
    "Alpaca 뉴스"
  );
  const grouped = Object.fromEntries(symbols.map((symbol) => [symbol, []]));
  (data.news || []).forEach((article) => {
    (article.symbols || []).forEach((symbol) => {
      if (grouped[symbol]) {
        grouped[symbol].push({
          headline: article.headline,
          createdAt: article.created_at,
          source: article.source || "Benzinga via Alpaca",
          url: article.url,
        });
      }
    });
  });
  return grouped;
}

async function fetchSecFilings(request, symbols, fetchImpl) {
  const headers = {
    "User-Agent": `CRT personal-research ${request.secContact}`,
    Accept: "application/json",
  };
  const tickers = await getJson(
    "https://www.sec.gov/files/company_tickers.json",
    headers,
    fetchImpl,
    "SEC 종목 목록"
  );
  const lookup = {};
  Object.values(tickers).forEach((entry) => {
    lookup[String(entry.ticker).toUpperCase()] = String(entry.cik_str).padStart(10, "0");
  });
  const output = Object.fromEntries(symbols.map((symbol) => [symbol, []]));
  for (const symbol of symbols) {
    const cik = lookup[symbol];
    if (!cik) continue;
    const submissions = await getJson(
      `https://data.sec.gov/submissions/CIK${cik}.json`,
      headers,
      fetchImpl,
      `SEC ${symbol} 공시`
    );
    const recent = submissions.filings && submissions.filings.recent;
    if (!recent) continue;
    recent.filingDate.forEach((filingDate, index) => {
      if (filingDate !== request.date) return;
      const accession = recent.accessionNumber[index];
      const document = recent.primaryDocument[index];
      output[symbol].push({
        form: recent.form[index],
        filingDate,
        accession,
        url: `https://www.sec.gov/Archives/edgar/data/${Number(cik)}/${accession.replace(/-/g, "")}/${document}`,
      });
    });
    await delay(125);
  }
  return output;
}

function detectCandidates(barsBySymbol, config, selectedDate) {
  const results = [];
  Object.entries(barsBySymbol).forEach(([symbol, rawBars]) => {
    const bars = rawBars
      .map((bar) => ({ ...bar, timestamp: Date.parse(bar.t) }))
      .filter((bar) => getEasternDayAndSession(bar.t, selectedDate))
      .sort((left, right) => left.timestamp - right.timestamp);
    let cooldownUntil = 0;
    bars.forEach((bar, index) => {
      if (bar.timestamp < cooldownUntil || bar.h < config.minPrice) return;
      const startAt = bar.timestamp - config.windowSeconds * 1000 + 60000;
      const window = bars.slice(0, index + 1).filter((point) => point.timestamp >= startAt);
      if (!window.length) return;
      const baselinePrice = Math.min(...window.map((point) => point.l));
      const peakPrice = Math.max(...window.map((point) => point.h));
      const changePct = ((peakPrice - baselinePrice) / baselinePrice) * 100;
      const dollarVolume = window.reduce((sum, point) => sum + Number(point.v) * Number(point.vw || point.c), 0);
      if (changePct < config.thresholdPct || dollarVolume < config.minDollarVolume) return;
      const session = getEasternDayAndSession(bar.t, selectedDate).session;
      results.push({
        symbol,
        detectedAt: bar.t,
        session,
        baselinePrice: round(baselinePrice),
        peakPrice: round(peakPrice),
        changePct: round(changePct),
        dollarVolume: Math.round(dollarVolume),
        volume: window.reduce((sum, point) => sum + Number(point.v), 0),
        windowSeconds: config.windowSeconds,
      });
      cooldownUntil = bar.timestamp + 5 * 60 * 1000;
    });
  });
  return results
    .sort((left, right) => right.changePct - left.changePct || left.detectedAt.localeCompare(right.detectedAt))
    .slice(0, config.maxResults);
}

function enrichCandidate(candidate, news, filings) {
  const detectedAt = Date.parse(candidate.detectedAt);
  const nearbyNews = news.filter((article) => {
    const articleAt = Date.parse(article.createdAt);
    return articleAt >= detectedAt - 24 * 60 * 60 * 1000 && articleAt <= detectedAt + 60 * 60 * 1000;
  }).slice(0, 3);
  let classification = "unexplained";
  let headline = "직접 촉매 미확인";
  if (filings.length) {
    classification = "filing-found";
    headline = `당일 SEC 공시 ${filings.length}건 확인`;
  } else if (nearbyNews.length) {
    classification = "news-found";
    headline = `급등 시점 주변 뉴스 ${nearbyNews.length}건 확인`;
  }
  return { ...candidate, classification, headline, news: nearbyNews, filings };
}

function resultEnvelope(request, reports, totals, warnings) {
  return {
    date: request.date,
    symbols: request.symbols,
    config: request.config,
    feed: "Alpaca SIP historical 1-minute bars",
    methodology:
      "분봉의 저가에서 고가까지의 움직임으로 후보를 찾습니다. 실제 체결 순서나 해당 시점 매매 가능성을 보장하지 않습니다.",
    reports,
    totals,
    warnings,
  };
}

async function getJson(url, headers, fetchImpl, label) {
  const response = await fetchImpl(url, { headers });
  if (!response.ok) {
    const body = await response.text();
    const detail = response.status === 401 || response.status === 403
      ? "API 키 또는 접근 권한을 확인해주세요."
      : body.slice(0, 120);
    throw new Error(`${label} 조회 실패 (${response.status}). ${detail}`);
  }
  return response.json();
}

function alpacaHeaders(request) {
  return {
    "APCA-API-KEY-ID": request.apiKey,
    "APCA-API-SECRET-KEY": request.apiSecret,
    Accept: "application/json",
  };
}

function getEasternDayAndSession(isoTime, selectedDate) {
  const parts = Object.fromEntries(
    NEW_YORK_TIME.formatToParts(new Date(isoTime))
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value])
  );
  const date = `${parts.year}-${parts.month}-${parts.day}`;
  if (date !== selectedDate) return null;
  const minutes = Number(parts.hour) * 60 + Number(parts.minute);
  if (minutes < 240 || minutes >= 1200) return null;
  const session = minutes < 570 ? "pre-market" : minutes < 960 ? "regular" : "after-hours";
  return { date, session };
}

function todayInNewYork() {
  const parts = Object.fromEntries(
    NEW_YORK_TIME.formatToParts(new Date())
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value])
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function addDays(date, days) {
  const calendar = new Date(`${date}T00:00:00Z`);
  calendar.setUTCDate(calendar.getUTCDate() + days);
  return calendar.toISOString().slice(0, 10);
}

function countBars(bars) {
  return Object.values(bars).reduce((count, entries) => count + entries.length, 0);
}

function round(value) {
  return Math.round(value * 100) / 100;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

module.exports = {
  DEFAULT_ANALYSIS_CONFIG,
  analyzeHistoricalMarket,
  detectCandidates,
  enrichCandidate,
  fetchSecFilings,
  validateInput,
};
