"use strict";

const SCENARIOS = {
  BNVA: {
    name: "Bionova Therapeutics",
    theme: "biotech",
    session: "pre-market",
    prices: [2.08, 2.1, 2.13, 2.19, 2.24, 2.31, 2.38],
    size: 19000,
    evidence: {
      primary: {
        classification: "confirmed",
        headline: "회사 임상 시험 결과 발표 자료가 확인됨",
        detail: "공식 보도자료 후보와 SEC 공시 후보가 가격 변동 시점 주변에서 발견된 데모 상황입니다.",
      },
    },
  },
  QNTM: {
    name: "Quantum Vector Systems",
    theme: "quantum",
    session: "regular",
    prices: [3.42, 3.44, 3.5, 3.59, 3.68, 3.81, 3.96],
    size: 16000,
    evidence: {
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
  },
  DRNE: {
    name: "Drone Horizon",
    theme: "drone",
    session: "after-hours",
    prices: [1.3, 1.31, 1.34, 1.36, 1.41, 1.47, 1.5],
    size: 900,
    evidence: {
      primary: {
        classification: "filtered",
        headline: "거래대금 기준 미달",
        detail: "급등률은 높지만 유동성이 부족해 경보에서 제외되는 데모 상황입니다.",
      },
    },
  },
};

function createDemoTickStream() {
  const ticks = [];
  const start = Date.now();
  Object.entries(SCENARIOS).forEach(([symbol, scenario], scenarioIndex) => {
    scenario.prices.forEach((price, index) => {
      ticks.push({
        symbol,
        price,
        size: scenario.size,
        session: scenario.session,
        timestamp: start + index * 7000 + scenarioIndex * 900,
        step: index,
      });
    });
  });
  return ticks.sort((left, right) => left.timestamp - right.timestamp);
}

module.exports = { SCENARIOS, createDemoTickStream };
