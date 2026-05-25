"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { RapidMoveDetector, DEFAULT_CONFIG } = require("./src/detector");
const { SCENARIOS, createDemoTickStream } = require("./src/demo-market");
const { analyzeHistoricalMarket } = require("./src/historical-analysis");
const { scanHistoricalMarket } = require("./src/market-scan");

const PORT = Number(process.env.PORT || 4173);
const HOST = process.env.HOST || "127.0.0.1";
const PUBLIC_DIR = path.join(__dirname, "public");
const detector = new RapidMoveDetector();
const clients = new Set();
const timers = new Set();
const state = {
  config: { ...DEFAULT_CONFIG },
  mode: "idle",
  reports: [],
  ticksReceived: 0,
  notice:
    "데모 모드입니다. 실제 시세·공시·뉴스가 아니며 투자 판단 자료가 아닙니다.",
};

const server = http.createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/api/state") {
      return json(response, state);
    }
    if (request.method === "GET" && request.url === "/api/events") {
      response.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      });
      response.write(`data: ${JSON.stringify(state)}\n\n`);
      clients.add(response);
      request.on("close", () => clients.delete(response));
      return;
    }
    if (request.method === "POST" && request.url === "/api/config") {
      const body = await readJson(request);
      const config = normalizeConfig(body);
      state.config = detector.updateConfig(config);
      broadcast();
      return json(response, state.config);
    }
    if (request.method === "POST" && request.url === "/api/demo/start") {
      startDemo();
      return json(response, { ok: true });
    }
    if (request.method === "POST" && request.url === "/api/reset") {
      reset();
      return json(response, { ok: true });
    }
    if (request.method === "POST" && request.url === "/api/ticks") {
      const tick = await readJson(request);
      acceptTick(tick, null);
      return json(response, { ok: true });
    }
    if (request.method === "POST" && request.url === "/api/historical/analyze") {
      const body = await readJson(request);
      const result = await analyzeHistoricalMarket(body);
      return json(response, result);
    }
    if (request.method === "POST" && request.url === "/api/historical/scan") {
      const body = await readJson(request);
      const result = await scanHistoricalMarket(body);
      return json(response, result);
    }
    if (request.method === "GET") {
      return serveStatic(request, response);
    }
    response.writeHead(404).end("Not found");
  } catch (error) {
    json(response, { error: error.message }, 400);
  }
});

function startDemo() {
  reset();
  state.mode = "demo-running";
  const ticks = createDemoTickStream();
  ticks.forEach((tick, index) => {
    const timer = setTimeout(() => {
      acceptTick(tick, SCENARIOS[tick.symbol]);
      if (index === ticks.length - 1) {
        state.mode = "demo-complete";
        broadcast();
      }
    }, index * 350);
    timers.add(timer);
  });
  broadcast();
}

function acceptTick(tick, scenario) {
  state.ticksReceived += 1;
  const alert = detector.processTick(tick);
  if (!alert) {
    broadcast();
    return;
  }
  const evidence = scenario ? scenario.evidence.primary : {
    classification: "investigating",
    headline: "입력된 시세에서 급변 감지",
    detail: "실제 원인 조회 공급자는 아직 연결되지 않았습니다.",
  };
  state.reports.unshift({
    ...alert,
    phase: "1차 보고",
    sourceMode: scenario ? "DEMO" : "EXTERNAL INPUT",
    company: scenario ? scenario.name : alert.symbol,
    classification: evidence.classification,
    headline: evidence.headline,
    detail: evidence.detail,
    links: externalLinks(alert.symbol),
  });
  if (scenario && scenario.evidence.followUp) {
    const timer = setTimeout(() => addFollowUp(alert, scenario), 2400);
    timers.add(timer);
  }
  broadcast();
}

function addFollowUp(alert, scenario) {
  const followUp = scenario.evidence.followUp;
  state.reports.unshift({
    ...alert,
    id: `${alert.id}-followup`,
    phase: "2차 보고",
    sourceMode: "DEMO",
    company: scenario.name,
    classification: followUp.classification,
    headline: followUp.headline,
    detail: followUp.detail,
    confidence: followUp.confidence,
    links: externalLinks(alert.symbol),
  });
  broadcast();
}

function externalLinks(symbol) {
  return {
    sec: `https://www.sec.gov/edgar/search/#/q=${encodeURIComponent(symbol)}`,
    stockTitan: `https://www.stocktitan.net/news/${encodeURIComponent(symbol)}/`,
  };
}

function reset() {
  timers.forEach((timer) => clearTimeout(timer));
  timers.clear();
  detector.reset();
  state.mode = "idle";
  state.reports = [];
  state.ticksReceived = 0;
  broadcast();
}

function normalizeConfig(body) {
  const config = {};
  const bounds = {
    windowSeconds: [60, 1800],
    thresholdPct: [0.1, 1000],
    minPrice: [0, 100000],
    minDollarVolume: [0, 1000000000],
  };
  Object.entries(bounds).forEach(([field, [min, max]]) => {
    if (body[field] === undefined) return;
    const value = Number(body[field]);
    if (!Number.isFinite(value) || value < min || value > max) {
      throw new Error(`${field} 값이 허용 범위를 벗어났습니다.`);
    }
    config[field] = value;
  });
  return config;
}

function broadcast() {
  const event = `data: ${JSON.stringify(state)}\n\n`;
  clients.forEach((client) => client.write(event));
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 100000) reject(new Error("Request is too large."));
    });
    request.on("end", () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        reject(new Error("Invalid JSON."));
      }
    });
  });
}

function serveStatic(request, response) {
  const requested = request.url === "/" ? "/index.html" : request.url;
  const safePath = path.normalize(requested).replace(/^(\.\.[/\\])+/, "");
  const filePath = path.join(PUBLIC_DIR, safePath);
  if (!filePath.startsWith(PUBLIC_DIR) || !fs.existsSync(filePath)) {
    response.writeHead(404).end("Not found");
    return;
  }
  const typeByExtension = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
  };
  response.writeHead(200, {
    "Content-Type": typeByExtension[path.extname(filePath)] || "application/octet-stream",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
  });
  fs.createReadStream(filePath).pipe(response);
}

function json(response, data, status = 200) {
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(data));
}

server.listen(PORT, HOST, () => {
  console.log(`CRT running at http://${HOST}:${PORT}`);
});
