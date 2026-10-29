# ADR-0025: 움직임 프리셋 마무리(#41)·메인 화면 움직임·성능 측정 방법

- 상태: 채택 (2026-10-29)
- 관련: ADR-0012(Motion 토큰), ADR-0024(시작 연출·온보딩), REQ-22·REQ-03, 이슈 #41·#123

## 맥락

- 사용자 요구(2026-10-29): "다 인터랙티브 구현도 되고 성능적으로 좋은가" → "될 때까지 다 하고 검증".
- ADR-0024는 시작 연출·온보딩·로그인에만 움직임을 넣었다. 메인 화면(홈·해석·결과)에는 없었다.
- ADR-0012가 정한 것 중 `MwCurve`·`MwTiming`, 프리셋 3개(cardFlip·decodingPulse·sheetPresent), `@Entry mwMotion`이 코드에 없었다(#41).
- 성능은 설계로만 막았고 잰 적이 없었다.

## 결정

1. **#41 마무리**(ADR-0012 §4-1 그대로)
   - `MwCurve`(linear·easeIn·easeOut·easeInOut·spring), `MwTiming`(instant·quick 0.16·standard 0.24·paper·snappy·soft).
     `reduced()` = 스프링 없음·지연 0·0.15초 이하. `animation(reduceMotion:)`은 이것을 거친다.
   - 프리셋 `MwCardFlipSpec`(paper, 원근 0.55, 들림 1.03) · `MwDecodingPulseSpec`(1.4초, 옅음 0.45, 부풂 1.015) ·
     `MwSheetPresentSpec`(soft, 24pt, 어둡게 0.28). 묶음 `MwMotionTheme`(`Codable`, `.default`·`.reduced`).
   - 모디파이어 `.mwCardFlip(isFlipped:back:)`·`.mwDecodingPulse(isActive:)`·`.mwSheetTransition()`·`.mwMotionTheme(_:)`.
   - **동작 줄이기 판단은 `EnvironmentValues.mwReduceMotion` 하나**(= 시스템 `accessibilityReduceMotion` || `mwMotion.isReduced`).
     모든 움직임이 이것만 본다. 그래서 Composition이 따로 `.reduced`를 주입할 필요가 없고(ADR-0012 §4-1의 주입 단계 생략),
     테스트·카탈로그는 `.reduced`를 넣어 시스템 설정 없이 확인한다.
   - 카탈로그 앱 `MotionLab`(최소판): 프리셋 3개 시연, 동작 줄이기 스위치, 슬라이더, 테마 JSON 복사.
2. **메인 화면 움직임**(끝 상태 = Figma, ADR-0024 원칙 그대로)
   - 홈 A-01: 위 칩·등급 카드는 초점 맞춤, 날짜 → "오늘" → 복습 카드 → 할 일이 차례로 떠오름. 처음 보일 때 한 번.
   - 붙여넣기: 해석을 기다리는 동안 붙여 넣은 글이 숨 쉼(decodingPulse). 버튼 진행 표시는 그대로(동작 줄이기 대비).
   - 결과 A-06: 불러오는 동안 결과 카드 모양 대기 자리(`MwDecodingPlaceholder`), 오면 카드가 차례로 떠오르고 모르는 말 칩이 튀어나옴.
   - 체크 상자: 체크 표시가 튀어나옴(pop). 할 일 줄 글자색은 snappy로 바뀜.
   - 토스트: sheetPresent(24pt 떠오름 + 페이드). 전에는 화면 아래 끝에서 통째로 올라왔다.
   - 카드 뒤집기는 복습 카드(v1.1)용이라 지금은 MotionLab에서만 쓴다.
3. **성능 측정 방법**: `Apps/IOS/E2E/MwonmalPerfTests.swift`(평소 건너뜀, `TEST_RUNNER_MW_PERF=1`일 때만).
   실행 시간, 온보딩 흐름(끊김·CPU·메모리), 쪽마다 가만히 4초 CPU, 쪽 넘김 한 번, 보조 기능 조회 중 CPU, 메인 화면 순회.
   끊김(`XCTHitchMetric`)은 iOS 26 **실기기**에서만 나온다. 합격선: 끊김 시간 비율 5ms/s 미만.
4. **떠다니기는 초당 30번**(반딧불·물결과 같음). 가장 빠른 자전거도 약 7pt/초라 한 번에 0.25pt 이하로 움직인다.
5. **CI에 iOS Release 빌드 추가**. Release(-O)에서 Swift 6.3 컴파일러가 `ViewModelState`의 제네릭 중첩 클래스에서 죽었다
   (Debug만 빌드하던 CI는 몰랐다 → TestFlight 빌드를 막았을 것). 상자 클래스를 제네릭이 아니게 바꿔 피했다.
6. **온보딩 아래 바탕색을 쪽마다 Figma 값으로**: O-1 `#F7F3EC`(canvas) · O-2 `#E2F3F2` · O-3 `#FDEBDF`
   (토큰 `bg.onboardingTeal`·`bg.onboardingOrange`, 다크는 canvas). ADR-0024 때 놓친 차이(화면 비교로 발견).

## 측정 결과(2026-10-29, iPhone 17 Pro 시뮬레이터 iOS 26.4, Debug + `-O`)

이 Mac은 측정 중 다른 작업 때문에 부하 평균이 5~52로 흔들렸다. 그래서 수치는 같은 조건의 앞뒤 비교로만 읽는다.

| 항목 | 바꾸기 전 | 바꾼 뒤 |
|---|---|---|
| 온보딩 1쪽 가만히 4초 CPU | 0.18초 | 0.21초 |
| 온보딩 2쪽 가만히 4초 CPU | 0.11초 | 0.10초 |
| 온보딩 3쪽 가만히 4초 CPU(반딧불·물결) | 0.38초 | 0.38초 |
| 쪽 넘김 한 번 + 3초 CPU | 0.25초 | 0.30초 |
| 보조 기능 조회 중 1쪽 4초 CPU | 0.47초 | 0.44초 |
| 메인 화면 순회 CPU(바꾼 뒤는 움직임 추가) | 1.02초 | 0.85초 |
| 메모리 최고 | 255MB | 256MB |

- 메모리는 대부분 시뮬레이터가 올린 시스템 라이브러리 몫이다(`footprint`: 앱 그림 래스터 0.3MB, CoreAnimation 0.5MB).
- 온보딩 흐름 전체 CPU(6~12초)는 테스트 도구가 화면 요소를 기다리며 조회하는 비용이 섞여 사용자 부하로 읽지 않는다.
- **아직 못 잰 것**: 실기기 끊김·실행 시간. 개인 개발 팀은 "Apple로 로그인" 권한을 줄 수 없어 측정용 빌드는
  번들 ID를 바꾸고 권한을 뺀 설정(저장소에 넣지 않음)으로 만든다. 기기가 연결된 동안 측정한다.

## 비용

- 돈 0, 외부 라이브러리 0. 스냅샷 라이브러리 없이 `ImageRenderer` 픽셀 비교로 끝 상태를 확인한다(S6에서 swift-snapshot-testing 도입 때 옮긴다).
- 새 파일: Motion 3개(토큰·프리셋·프리셋 모디파이어), 부품 1개(대기 자리), 테스트 2개, 카탈로그 1개.

## 대안

| 대안 | 탈락 이유 |
|---|---|
| Composition이 시스템 값을 읽어 `.reduced` 주입(ADR-0012 원안) | 주입을 빠뜨린 화면(시트·새 창)에서 동작 줄이기가 안 먹는다. 읽는 쪽에서 합치면 빠뜨릴 곳이 없다 |
| 결과 대기에 `ProgressView`만 | 기다리는 12초 동안 무엇이 올지 모른다. 카드 모양 자리는 결과 배치를 미리 보여 준다 |
| 떠다니기를 화면 주사율(120Hz) 그대로 | 차이가 보이지 않는데 계산만 4배 |
| 칩 그림을 칩 크기로 잘라 메모리 절약 | 측정상 그림 래스터가 0.3MB라 효과가 없다. Figma 겹침 비교(차이 0)를 다시 해야 한다 |
| 시뮬레이터 수치를 합격 기준으로 | 시뮬레이터는 끊김 지표가 없고 Mac 부하에 흔들린다 |

## 검증

- 단위 테스트: 시간표 불변식(0.6초 이하·기본 스프링 감쇠 0.8 이상·동작 줄이기 변환), Codable 왕복, 카드 뒤집기·맥박 진행률 함수,
  `mwReduceMotion`, 끝 상태 픽셀 비교(뒤집기 2×2, 맥박 3가지, 비교 대상끼리 다름 확인). iOS·macOS 둘 다.
- iOS E2E(17 Pro) 통과. 온보딩 세 쪽 자리 잡은 화면 ↔ Figma O-1~O-3 나란히 비교.
- 린트 strict 0, String Catalog 검사 통과, iOS·macOS Release 빌드 통과.
- macOS E2E: 실행 시 macOS가 UI 자동화 인증(암호·Touch ID)을 요구해 사람 없이 못 돈다(#123에 남김).
