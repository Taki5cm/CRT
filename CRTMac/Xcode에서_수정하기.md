# CRT를 Xcode에서 수정하기

이제부터 앱의 작업 원본은 `CRT.xcodeproj`입니다. 브라우저 데모가 아니라 이 Xcode 프로젝트를 열어 화면과 기능을 직접 확인하고 수정할 수 있습니다.

## 처음 열기

1. Finder에서 `CRTMac` 폴더를 엽니다.
2. `CRT.xcodeproj` 파일을 더블클릭합니다.
3. Xcode 왼쪽 목록에서 `CRT` 폴더를 펼칩니다.
4. 상단 실행 버튼을 누르면 앱 화면이 뜹니다.

처음 실행 시 서명 관련 안내가 표시되면 Xcode의 프로젝트 설정에서 본인의 Apple ID 팀을 선택하면 됩니다. 개인 Mac에서 직접 시험하는 단계에서는 무료 Apple ID로 실행할 수 있습니다.

## 가장 쉽게 수정하는 곳

| 원하는 변경 | 여는 파일 | 바꿀 내용 |
| --- | --- | --- |
| 글자, 버튼 이름, 색상, 화면 배치 | `ContentView.swift` | 화면에 보이는 구성 |
| 초기 관심종목, 상태 문구, 버튼 동작 시작점 | `AppModel.swift` | 사용 흐름 |
| 급등 기준의 자료 구조, 결과 구분 | `Models.swift` | 설정과 결과 종류 |
| Massive, Alpaca, SEC 조회와 급등 판정 | `MarketService.swift` | 실제 분석 기능 |
| API Key 저장 | `KeychainStore.swift` | Mac 키체인 처리 |
| 앱이 처음 시작되는 방식 | `CRTApp.swift` | 앱 진입점 |

## 우선 고쳐보기 좋은 예시

앱 첫 화면 제목을 바꾸려면 `ContentView.swift`를 열고 아래 문구를 찾습니다.

```swift
Text("지난 거래일의 급등 이유를\n실제 자료로 추적합니다")
```

따옴표 안의 문장을 원하는 문장으로 바꾼 뒤 Xcode 상단 실행 버튼을 누르면 변경된 화면을 확인할 수 있습니다.

초기 관심종목 목록은 `AppModel.swift`의 이 부분입니다.

```swift
@Published var watchlistText = "AAPL, NVDA, TSLA, PLTR, IONQ, RGTI, QBTS"
```

## 내가 작업할 때의 기준

앞으로 기능을 추가하거나 고칠 때도 `CRT.xcodeproj`에서 바로 보이는 Swift 파일 안에 반영합니다. 즉, 사용자는 Xcode에서 같은 원본 코드를 열어 제 작업을 확인하고, 직접 수정하고, 실행해볼 수 있습니다.

`build` 폴더의 `.app` 파일은 완성된 실행본이라 수정 대상이 아닙니다. 실제로 손대는 곳은 `Sources/CRT` 안의 `.swift` 파일들입니다.
