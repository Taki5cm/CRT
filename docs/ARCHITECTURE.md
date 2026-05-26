# Architecture

## Purpose

CRT는 짧은 시간 내 급격한 가격 변화를 발견한 뒤, 동일 날짜의 공시와 시점 주변 뉴스를 함께 표시하여 사용자가 움직임의 배경을 조사하도록 돕는 기능형 베타입니다.

## Components

| 영역 | 구현 | 책임 |
| --- | --- | --- |
| macOS UI | SwiftUI | 설정 입력, 분석 실행, 결과 카드 표시 |
| App state | `AppModel.swift` | 사용자 입력, 로딩 상태, 서비스 호출 관리 |
| Analysis service | `CRTMac/Sources/CRT/MarketService.swift` | 외부 API 호출, 급변 감지, 근거 결합 |
| Credential storage | `CRTMac/Sources/CRT/KeychainStore.swift` | API 키의 로컬 키체인 저장 |
| Notifications | `CRTMac/Sources/CRT/NotificationService.swift` | 사용자가 허용한 분석 완료 로컬 알림 전달 |
| Live stream | `CRTMac/Sources/CRT/LiveQuoteService.swift` | 사용자 권한에 따른 Alpaca IEX/SIP WebSocket 체결 수신 |
| Live detection | `CRTMac/Sources/CRT/LiveRapidMoveDetector.swift` | 초 단위 가격·거래대금 조건 계산과 중복 경보 제한 |
| Browser prototype | Node.js + static UI | 기능 흐름과 API 동작의 보조 검증 |
| Automated tests | Node test runner | 핵심 감지 및 결합 로직 회귀 검사 |

## macOS Processing Flow

### Whole-Market Scan

1. 사용자가 지난 거래일과 급변 기준을 선택합니다.
2. Massive 일별 집계에서 일중 변동폭과 거래대금 기준에 맞는 후보를 선별합니다.
3. 무료 호출 한도에 맞춰 상위 후보 최대 4개의 1분봉을 가져옵니다.
4. 선택한 시간 창 안의 상승률과 거래대금 조건을 만족하는 움직임을 감지합니다.
5. 감지된 종목에 대해 SEC 당일 공시를 확인합니다.
6. 사용자가 알림을 켠 경우 분석 완료와 후보 수를 Mac 알림으로 표시합니다.

### Watchlist Analysis

1. 사용자가 최대 30개 티커를 입력합니다.
2. Alpaca 무료 계정과 호환되는 IEX 피드에서 지난 날짜의 1분봉을 조회합니다.
3. 급변 후보에 대해 과거 뉴스 및 SEC 공시를 조회합니다.
4. 근거에 따라 `공시 확인`, `뉴스 확인`, `원인 미확인`으로 표시합니다.

## Interaction Improvements In 0.2

- 작은 날짜 입력 대신 그래픽 달력 패널과 최근 거래일 바로가기를 제공합니다.
- 직접 날짜 입력과 이전 해·다음 해 이동으로 긴 기간을 빠르게 탐색합니다.
- 주말 선택은 직전 평일로 보정하며, 실제 미국 휴장 여부는 외부 데이터 조회 결과에 맡깁니다.
- 결과는 공시·뉴스·원인 미확인 분류별로 필터링할 수 있습니다.
- 로컬 알림은 자동 감시가 아닌 사용자가 실행한 분석 완료에만 연결됩니다.
- 관심종목 현재가는 무료 IEX 스트림으로 표시하되 전체시장 감시 결과로 해석하지 않습니다.
- 관심종목 사후 분봉 분석도 IEX 범위이며, 전체시장 후보 탐색은 Massive 흐름에서 별도로 수행합니다.

## Live Detection In 0.3

1. 사용자가 자기 Alpaca 키와 사용할 데이터 범위를 고릅니다.
2. 무료 IEX 모드는 입력한 관심종목만, 유료 SIP 모드는 선택 시 전체 상장주 체결을 구독합니다.
3. 시장 체결 메시지의 타임스탬프를 기준으로 `1`, `2`, `5`, `30`, `60`초 창을 유지하고 상승률·최소 주가·거래대금 조건을 검사합니다.
4. 관심종목 모드는 현재 체결을 화면에 표시하지만, 전체시장 모드는 수신량을 줄이기 위해 감지된 후보만 UI로 전달합니다.
5. 조건에 맞는 종목은 화면 로그에 추가하고 사용자가 알림을 허용한 경우 즉시 macOS 알림을 표시합니다.
6. 현재 경보는 가격 기반 1차 알림이며 뉴스·공시 기반 2차 보고는 이후 확장 범위입니다.

## Design Decisions

- **User-owned stream**: 상업용 시세 재배포 없이 제품 경험을 검증하기 위해 사용자의 데이터 권한으로 로컬 스트림을 수신합니다.
- **Official interfaces**: 화면 자동조작이나 비공식 크롤링 대신 데이터 제공자와 SEC의 공식 API를 사용합니다.
- **Failure isolation**: 뉴스·공시 보강 요청에 문제가 생겨도 가격 기반 후보 결과는 유지하고 경고를 표시합니다.
- **Local credentials**: Mac 앱 자격정보는 서버 데이터베이스가 아니라 사용자 Mac의 Keychain에 저장합니다.

## Future Direction

유료 제품으로 확장하려면 자동 뉴스 조사 연결, 라이선스 조건, 장애 대응, 사용자 온보딩, 보안과 금융 관련 표시 정책을 함께 설계해야 합니다. 서버가 여러 사용자에게 시세 또는 알림을 직접 제공하는 형태는 별도의 상업용 데이터 계약 검토가 필요합니다.
