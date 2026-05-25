"use strict";

const DEFAULT_CONFIG = Object.freeze({
  windowSeconds: 60,
  thresholdPct: 10,
  minPrice: 1,
  minDollarVolume: 100000,
  cooldownSeconds: 180,
});
const SCENARIOS = {
  BNVA: {
    name: "Bionova Therapeutics",
    session: "pre-market",
    prices: [2.08, 2.1, 2.13, 2.19, 2.24, 2.31, 2.38],
    size: 19000,
    primary: {
      classification: "confirmed",
      headline: "회사 임상 시험 결과 발표 자료가 확인됨",
      detail: "공식 보도자료 후보와 SEC 공시 후보가 가격 변동 시점 주변에서 발견된 데모 상황입니다.",
    },
  },
  QNTM: {
    name: "Quantum Vector Systems",
    session: "regular",
    prices: [3.42, 3.44, 3.5, 3.59, 3.68, 3.81, 3.96],
    size: 16000,
    primary: {
      classification: "unexplained",
      headline: "직접 촉매 미확인",
      detail: "새 공시와 회사 공식 발표가 즉시 확인되지 않은 데모 상황입니다.",
    },
    followUp: {
      classification: "theme-possible",
      headline: "양자컴퓨팅 테마 동반 움직임 가능성",
      detail: "동일 테마 후보 6개 중 4개가 동반 상승했습니다. 기업 고유 촉매는 확인되지 않았습니다.",
      confidence: "중간",
    },
  },
  DRNE: {
    name: "Drone Horizon",
    session: "after-hours",
    prices: [1.3, 1.31, 1.34, 1.36, 1.41, 1.47, 1.5],
    size: 900,
    primary: {
      classification: "filtered",
      headline: "거래대금 기준 미달",
      detail: "급등률은 높지만 유동성이 부족해 경보에서 제외되는 데모 상황입니다.",
    },
  },
};
const labels = {
  idle: "대기 중",
  "demo-running": "데모 감시 중",
  "demo-complete": "데모 완료",
};
const fields = ["windowSeconds", "thresholdPct", "minPrice", "minDollarVolume"];
const state = {
  config: { ...DEFAULT_CONFIG },
  mode: "idle",
  reports: [],
  ticksReceived: 0,
};
const history = new Map();
const lastAlertAt = new Map();
const timers = new Set();
const form = document.querySelector("#config-form");
const historicalForm = document.querySelector("#historical-form");
const scanForm = document.querySelector("#scan-form");
const reportList = document.querySelector("#report-list");
const actualResults = document.querySelector("#actual-results");
const analysisStatus = document.querySelector("#analysis-status");
const scanResults = document.querySelector("#scan-results");
const scanStatus = document.querySelector("#scan-status");

setDefaultAnalysisDate();
render();

historicalForm.addEventListener("submit", runHistoricalAnalysis);
scanForm.addEventListener("submit", runMarketScan);

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const values = Object.fromEntries(fields.map((field) => [field, Number(form.elements[field].value)]));
  if (!validConfig(values)) return;
  state.config = { ...state.config, ...values };
  reset(false);
  render();
});

document.querySelector("#start-demo").addEventListener("click", startDemo);
document.querySelector("#reset").addEventListener("click", () => reset(true));

async function runHistoricalAnalysis(event) {
  event.preventDefault();
  const button = document.querySelector("#analyze-history");
  const payload = {
    apiKey: historicalForm.elements.apiKey.value.trim(),
    apiSecret: historicalForm.elements.apiSecret.value.trim(),
    secContact: historicalForm.elements.secContact.value.trim(),
    date: historicalForm.elements.analysisDate.value,
    symbols: historicalForm.elements.symbols.value,
    config: Object.fromEntries(fields.map((field) => [field, Number(form.elements[field].value)])),
  };
  button.disabled = true;
  analysisStatus.className = "analysis-status running";
  analysisStatus.textContent = "실제 과거 분봉, 뉴스, SEC 공시를 조회하고 있습니다...";
  actualResults.innerHTML = "";
  try {
    const response = await fetch("/api/historical/analyze", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "분석에 실패했습니다.");
    renderHistoricalResults(result, actualResults, analysisStatus);
  } catch (error) {
    analysisStatus.className = "analysis-status error";
    analysisStatus.textContent =
      error.message === "Failed to fetch"
        ? "실제 분석 기능은 로컬 앱으로 실행할 때 사용할 수 있습니다."
        : error.message;
  } finally {
    button.disabled = false;
  }
}

async function runMarketScan(event) {
  event.preventDefault();
  const button = document.querySelector("#scan-market");
  const payload = {
    massiveApiKey: scanForm.elements.massiveApiKey.value.trim(),
    secContact: scanForm.elements.scanSecContact.value.trim(),
    date: scanForm.elements.scanDate.value,
    config: Object.fromEntries(fields.map((field) => [field, Number(form.elements[field].value)])),
  };
  button.disabled = true;
  scanStatus.className = "analysis-status running";
  scanStatus.textContent = "전체시장 일별 후보를 찾고 상위 후보의 분봉과 SEC 공시를 조회하고 있습니다...";
  scanResults.innerHTML = "";
  try {
    const response = await fetch("/api/historical/scan", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "전체시장 스캔에 실패했습니다.");
    renderHistoricalResults(result, scanResults, scanStatus);
  } catch (error) {
    scanStatus.className = "analysis-status error";
    scanStatus.textContent =
      error.message === "Failed to fetch"
        ? "전체시장 스캔은 로컬 앱으로 실행할 때 사용할 수 있습니다."
        : error.message;
  } finally {
    button.disabled = false;
  }
}

function renderHistoricalResults(result, resultsElement, statusElement) {
  statusElement.className = "analysis-status";
  const emptyScope = result.totals.marketSymbolsScanned ? "전체시장 후보 재검사" : "선택한 종목과 기준";
  statusElement.textContent = result.reports.length
    ? `${result.date} 실제 데이터 분석이 완료되었습니다. 후보 ${result.reports.length}건을 확인했습니다.`
    : `${result.date} ${emptyScope}에서는 급변 후보가 발견되지 않았습니다.`;
  const scanned = result.totals.marketSymbolsScanned
    ? `<span><strong>전체 일봉 확인</strong>${number(result.totals.marketSymbolsScanned)}개</span>`
    : `<span><strong>조사 종목</strong>${number(result.symbols.length)}개</span>`;
  const summary = `
    <div class="result-summary">
      ${scanned}
      <span><strong>확인 분봉</strong>${number(result.totals.barsExamined)}개</span>
      <span><strong>발견 후보</strong>${number(result.reports.length)}건</span>
      <span><strong>연결 뉴스</strong>${number(result.totals.newsRetrieved)}건</span>
      <span><strong>당일 SEC 공시</strong>${number(result.totals.filingsRetrieved)}건</span>
    </div>
    <p class="analysis-footnote">${escapeText(result.methodology)}</p>
    ${result.warnings.length ? `<div class="analysis-warning">${result.warnings.map((warning) => escapeText(warning)).join("<br>")}</div>` : ""}
  `;
  resultsElement.innerHTML = summary + result.reports.map(actualReportCard).join("");
}

function actualReportCard(report) {
  const detectedTime = new Intl.DateTimeFormat("ko-KR", {
    timeZone: "America/New_York",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(report.detectedAt));
  const filings = report.filings.length
    ? `<div class="evidence-group"><h4>SEC 당일 공시</h4>${report.filings.map((filing) =>
        `<a href="${safeUrl(filing.url)}" target="_blank" rel="noreferrer">${escapeText(filing.form)} · ${escapeText(filing.filingDate)}</a>`
      ).join("")}</div>`
    : "";
  const news = report.news.length
    ? `<div class="evidence-group"><h4>급등 시점 주변 뉴스</h4>${report.news.map((article) =>
        `<a href="${safeUrl(article.url)}" target="_blank" rel="noreferrer">${escapeText(article.headline)}</a>`
      ).join("")}</div>`
    : '<div class="evidence-group"><h4>직접 근거</h4><div class="report-detail">연결된 공시 또는 시점 주변 뉴스가 발견되지 않았습니다.</div></div>';
  return `
    <article class="report actual-card class-${escapeText(report.classification)}">
      <div>
        <span class="phase">실제 사후 분석</span>
        <div class="ticker">${escapeText(report.symbol)} <span class="change">+${report.changePct}%</span></div>
        <div class="report-meta">
          ${escapeText(report.session)} · ${escapeText(detectedTime)} ET<br>
          $${report.baselinePrice.toFixed(2)} → $${report.peakPrice.toFixed(2)}<br>
          거래대금 $${number(report.dollarVolume)}
        </div>
      </div>
      <div>
        <h3>${escapeText(report.headline)}</h3>
        ${filings}
        ${news}
      </div>
    </article>
  `;
}

function startDemo() {
  reset(false);
  state.mode = "demo-running";
  const start = Date.now();
  const ticks = [];
  Object.entries(SCENARIOS).forEach(([symbol, scenario], scenarioIndex) => {
    scenario.prices.forEach((price, index) => {
      ticks.push({
        symbol,
        price,
        size: scenario.size,
        session: scenario.session,
        timestamp: start + index * 7000 + scenarioIndex * 900,
      });
    });
  });
  ticks.sort((left, right) => left.timestamp - right.timestamp).forEach((tick, index, allTicks) => {
    schedule(() => {
      acceptTick(tick);
      if (index === allTicks.length - 1) {
        state.mode = "demo-complete";
        render();
      }
    }, index * 350);
  });
  render();
}

function acceptTick(tick) {
  state.ticksReceived += 1;
  const alert = detect(tick);
  if (alert) {
    const scenario = SCENARIOS[tick.symbol];
    state.reports.unshift(createReport(alert, scenario, scenario.primary, "1차 보고"));
    if (scenario.followUp) {
      schedule(() => {
        state.reports.unshift(createReport(alert, scenario, scenario.followUp, "2차 보고"));
        render();
      }, 2400);
    }
  }
  render();
}

function detect(tick) {
  const windowStart = tick.timestamp - state.config.windowSeconds * 1000;
  const points = (history.get(tick.symbol) || []).filter((point) => point.timestamp >= windowStart);
  points.push(tick);
  history.set(tick.symbol, points);
  if (tick.price < state.config.minPrice || points.length < 2) return null;

  const baseline = points[0];
  const changePct = ((tick.price - baseline.price) / baseline.price) * 100;
  const dollarVolume = points.reduce((total, point) => total + point.price * point.size, 0);
  const lastAlert = lastAlertAt.get(tick.symbol) || 0;
  if (
    changePct < state.config.thresholdPct ||
    dollarVolume < state.config.minDollarVolume ||
    tick.timestamp - lastAlert < state.config.cooldownSeconds * 1000
  ) {
    return null;
  }
  lastAlertAt.set(tick.symbol, tick.timestamp);
  return {
    symbol: tick.symbol,
    price: tick.price,
    session: tick.session,
    changePct: Math.round(changePct * 100) / 100,
    dollarVolume: Math.round(dollarVolume),
    windowSeconds: state.config.windowSeconds,
  };
}

function createReport(alert, scenario, evidence, phase) {
  return {
    ...alert,
    phase,
    sourceMode: "DEMO",
    company: scenario.name,
    classification: evidence.classification,
    headline: evidence.headline,
    detail: evidence.detail,
    confidence: evidence.confidence,
    links: {
      sec: `https://www.sec.gov/edgar/search/#/q=${encodeURIComponent(alert.symbol)}`,
      stockTitan: `https://www.stocktitan.net/news/${encodeURIComponent(alert.symbol)}/`,
    },
  };
}

function reset(shouldRender) {
  timers.forEach((timer) => clearTimeout(timer));
  timers.clear();
  history.clear();
  lastAlertAt.clear();
  state.mode = "idle";
  state.reports = [];
  state.ticksReceived = 0;
  if (shouldRender) render();
}

function schedule(callback, milliseconds) {
  const timer = setTimeout(() => {
    timers.delete(timer);
    callback();
  }, milliseconds);
  timers.add(timer);
}

function validConfig(values) {
  const bounds = {
    windowSeconds: [60, 1800],
    thresholdPct: [0.1, 1000],
    minPrice: [0, 100000],
    minDollarVolume: [0, 1000000000],
  };
  for (const [field, range] of Object.entries(bounds)) {
    if (!Number.isFinite(values[field]) || values[field] < range[0] || values[field] > range[1]) {
      window.alert("설정값을 확인해주세요.");
      return false;
    }
  }
  return true;
}

function render() {
  fields.forEach((field) => {
    const input = form.elements[field];
    if (document.activeElement !== input) input.value = state.config[field];
  });
  document.querySelector("#status").textContent = labels[state.mode] || state.mode;
  document.querySelector("#ticks").textContent = number(state.ticksReceived);
  document.querySelector("#reports-count").textContent = number(state.reports.length);
  document.querySelector("#condition").textContent =
    `${state.config.windowSeconds}초 / +${state.config.thresholdPct}%`;
  reportList.innerHTML = state.reports.length
    ? state.reports.map(reportCard).join("")
    : '<div class="empty">데모 시장을 재생하면 보고서가 이곳에 나타납니다.</div>';
}

function reportCard(report) {
  const confidence = report.confidence ? `<div>신뢰도: ${escapeText(report.confidence)}</div>` : "";
  return `
    <article class="report class-${escapeText(report.classification)}">
      <div>
        <span class="phase">${escapeText(report.phase)} | ${escapeText(report.sourceMode)}</span>
        <div class="ticker">${escapeText(report.symbol)} <span class="change">+${report.changePct}%</span></div>
        <div class="report-meta">
          ${escapeText(report.session)} · $${report.price.toFixed(2)}<br>
          ${report.windowSeconds}초 거래대금 $${number(report.dollarVolume)}
        </div>
      </div>
      <div>
        <h3>${escapeText(report.headline)}</h3>
        <div class="report-detail">${escapeText(report.detail)}${confidence}</div>
      </div>
      <nav class="report-links" aria-label="참고 링크">
        <a href="${report.links.sec}" target="_blank" rel="noreferrer">SEC 검색 예시</a>
        <a href="${report.links.stockTitan}" target="_blank" rel="noreferrer">Stock Titan 검색 예시</a>
      </nav>
    </article>
  `;
}

function number(value) {
  return new Intl.NumberFormat("ko-KR").format(value);
}

function safeUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.toString() : "#";
  } catch {
    return "#";
  }
}

function setDefaultAnalysisDate() {
  const date = new Date();
  date.setDate(date.getDate() - 1);
  while (date.getDay() === 0 || date.getDay() === 6) {
    date.setDate(date.getDate() - 1);
  }
  historicalForm.elements.analysisDate.value = date.toISOString().slice(0, 10);
  scanForm.elements.scanDate.value = date.toISOString().slice(0, 10);
}

function escapeText(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[character]));
}
