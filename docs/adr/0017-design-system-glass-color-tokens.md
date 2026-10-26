# ADR-0017: 디자인 시스템 v1 — Liquid Glass는 시스템이 주는 곳에만, 색은 시맨틱 토큰 4벌로

- 상태: 채택 (2026-10-26) — 결정 5(다크 노출)는 Day 12 스냅샷 후 확정. 확신도 숫자 노출은 별도 PO 결정
- 관련: REQ-02·03·22·23, ADR-0005 §4(폴백 표 "Liquid Glass" 행)·ADR-0006·ADR-0012·ADR-0013, 12번 §9 SDK 규칙 3·4·7(D-23)·§18, REQUIREMENTS F-14(#71), 05번 §1·§4.1
- 대체(부분): ADR-0005 §4·12번 §18의 "v1.0에 글래스 없음" → "v1.0에 **커스텀** 글래스 최소". 12번 SDK 규칙 4의 `#8A8494` 교정값 → `#726C7B`.

## 맥락
- 사용자 요구(2026-10-26): Liquid Glass와 HIG를 제대로 이해하고 적절히 쓰기, 색을 아주 잘 쓰기, 사용자 멘탈 모델 중심, Figma 디자인 그대로 구현.
- 사실 1: CI는 Xcode 26.4(iOS 26 SDK)로 빌드한다(ADR-0011). Apple 문서상 최신 SDK로 빌드하면 표준 바·시트·팝오버·컨트롤이 **자동으로** Liquid Glass가 된다(Adopting Liquid Glass). 옵트아웃 키 `UIDesignRequiresCompatibility`는 "임시"이고 iOS 27 SDK부터 무시된다. → "v1.0에 글래스 없음"은 커스텀 표면에만 성립한다.
- 사실 2: HIG Color — "앱이 한 가지 외관만 내보내더라도 Liquid Glass 적응을 위해 라이트·다크 색을 모두 제공", 사용자 지정 색마다 고대비 변형.
- 사실 3: Figma v5.2는 HTML 캡처라 변수·컴포넌트가 없다. 팔레트를 그대로 쓰면 대비 실패 7건(text-3 2.30:1, ocean on paper 4.35:1, coral/tangerine 태그 4.05/3.75:1, 체크박스 1.50:1, leaf 스위치 2.72:1, 형광펜 구분 1.25:1). Figma는 탭바·카드·닫기 버튼에 커스텀 글래스를 쓴다.

## 선택지
| 선택지 | 장점 | 단점 |
|---|---|---|
| ① 현행 유지: 글래스 없음 + 라이트 고정 + Figma 팔레트 그대로 | 작업 0 | 사실 1과 모순(시스템 글래스는 이미 켜짐). 대비 실패 7건 출시. Liquid Glass 적응용 다크 값 없음(HIG 위반) |
| ② Figma 그대로: 커스텀 플로팅 탭바·글래스 카드·글래스 닫기 버튼 | 시안과 픽셀 일치 | HIG "콘텐츠 층에 글래스 금지" 위반. 17~25와 26이 다른 앱처럼 보임. Reduce Transparency·최소화·접근성 재구현. 60h 예산 초과 |
| ③ `UIDesignRequiresCompatibility = YES`로 옛 디자인 고정 | 스냅샷 한 벌 | Apple이 임시라고 명시, Xcode 27에서 무시 → 몇 달 뒤 강제 이행 |
| **④ 시스템 글래스 수용 + 커스텀 글래스는 `Compat` 1곳(선택적 배너) + 시맨틱 토큰 4벌(Asset Catalog)** | HIG 일치, 화면 코드에 `#available` 0, 대비 전부 통과, 다크·고대비가 코드 분기 없이 동작 | 토큰 작업 +0.5일, 스냅샷 OS별 두 벌(ADR-0005가 이미 감수) |

## 결정
**④를 채택한다.**
1. **글래스 범위**: 탭바·내비 바·툴바·시트·토글은 시스템 기본(iOS 26 자동 글래스, 17~25 시스템 머티리얼). 바·시트에 커스텀 배경을 깔지 않는다(scroll edge effect 기본값). 콘텐츠(결과 카드, 원문, 할 일, 기록 행, 입력)는 **불투명** `bg.surface`. 커스텀 글래스는 `MwonmalUI/Compat`의 `.mwGlassSurface(in:)`·`.mwGlassButtonStyle(prominent:)`만 — iOS 26 `glassEffect(.regular, in:)`/`.glassProminent`, 17~25 `.regularMaterial`+1px 테두리, Reduce Transparency·Increase Contrast면 불투명. v1.0 사용처는 0~1곳(떠 있는 배너). `clear` 글래스 금지. 틴트 글래스는 화면당 1개(Primary)만, 색은 `accent.fill` 하나.
2. **색**: 화면은 시맨틱 토큰만(`bg.*`, `text.*`, `accent.*`, `jargon.*`, `status.*`, `intent.*`, `control.border`, `separator`). 토큰마다 Light/Dark × 기본/고대비 4벌을 `MwonmalUI/Resources/Colors.xcassets` color set으로, `MwColor`가 `Color(_:bundle:)`로 노출. 팔레트(ocean·sun·coral…)는 SDK 내부 원료와 일러스트 전용.
3. **대비 기준**: 본문 4.5:1, 큰 글자·UI 3:1, 고대비 7:1. 교정: text-3 → `#726C7B`, 종이 위 ocean 글자 → `accent.text #2A63C2`, coral 태그 → `#B23F2E`, tangerine 태그 → `#A84A12`, 체크박스 → `#8A8494`, 스위치 → 시스템 `Toggle` + `accent.fill`.
4. **색만으로 뜻 금지 구체화**: 판교어 = 형광펜 + 점선 밑줄(`jargon.underline`) + VoiceOver 라벨. 마감 = 글자("오늘/내일/지남") + 서로 다른 SF Symbol. 의도 = SF Symbol + 이름. 완료 = 체크 + 취소선.
5. **외관 모드(D-23 개정)**: 다크·고대비 **값은 v1.0에 넣는다**(HIG 필수). 출시 시 다크 **노출**은 Day 12 스냅샷(SE iOS 17 + iPhone 17 iOS 26, 라이트·다크·AX3)에서 일러스트 헤더 다크 변형이 준비되면 켜고, 아니면 `preferredColorScheme(.light)`를 루트 한 곳에 유지한다(토큰은 그대로).
6. **Figma 정합**: Figma는 "시각 언어(종이·크림·형광펜·Pretendard·일러스트)"의 원본으로 따르고, 내비게이션 구조·글래스 사용·블록 순서·대비는 이 ADR이 우선한다. 충돌 목록(조사 보고서 §2.6 F1~F12)은 Figma에 주석(🟦)으로 남긴다.

## 근거
- HIG Materials: "Don't use Liquid Glass in the content layer." / "Use Liquid Glass effects sparingly." / clear는 시각적으로 풍부한 배경 위에서만.
- HIG Color: 글래스엔 색을 아껴서, 여러 컨트롤 배경에 색 금지, 한 가지 외관이어도 라이트·다크 제공, 고대비 변형.
- HIG Toolbars/Layout: 바 배경 대신 scroll edge effect, prominent는 하나.
- WWDC26: 사용자가 글래스를 "ultra clear ~ fully tinted"로 조절 → 글래스 위 글자 대비는 앱이 보장할 수 없으므로 글래스 위 콘텐츠를 최소화하는 것이 가장 안전.
- 멘탈 모델("붙여넣기 → 쉬운 말 → 할 일")에서 사용자가 오래 읽는 것은 콘텐츠다. 콘텐츠를 불투명하게 두면 가독성이 OS·설정·배경과 무관하게 고정된다.
- 비용: 토큰·color set·대비 스크립트 0.5일(Day 10 안), Compat 모디파이어 2개 0.25일. 커스텀 탭바를 안 그려서 절약 ≥ 0.5일.

## 결과
- 쉬워지는 것: 다크·고대비가 코드 분기 없이 동작. iOS 26/27 글래스 변화(재조정·투명도 슬라이더)를 무료로 받음. 접근성 감사 통과 근거가 표로 남음(계산 스크립트).
- 어려워지는 것: Figma 시안과 픽셀이 다른 곳이 생김(탭바·결과 시트·닫기 버튼). 스냅샷 기준 이미지 OS별 두 벌(이미 ADR-0005). 일러스트 다크 변형 작업(v1.0에 못 하면 라이트 고정 유지).
- 영향 파일: `Modules/MwonmalUI/Resources/Colors.xcassets`, `Modules/MwonmalUI/Sources/Tokens/MwColor.swift`, `Sources/Compat/MwGlass.swift`, 05번 §1·§4.1(글래스 표에 "v1.0: 시스템만" 열), 12번 §9 규칙 4·7·§18 표 "Liquid Glass" 행, ADR-0005 §4 해당 행에 "개정 → ADR-0017", REQUIREMENTS F-14 상태 갱신(삭제 금지, REQ-34), `Project.swift` `defaultKnownRegions`에 `en`.

## 검증
- `contrast.py`(표준 라이브러리만)로 토큰 표 전부 재계산 → CI 단위 테스트로 옮겨 4.5/3/7 미달 시 실패.
- 스냅샷 Tier1: iPhone 17 iOS 26.4 라이트·다크 + Increase Contrast, Reduce Transparency 각 1장. Tier2: SE iOS 17.0.
- 색맹 시뮬레이션(Catalog, Deuteranopia)에서 마감·의도·형광펜 구분 가능.
- Accessibility Inspector 대비 감사 0건(Day 19).
- SwiftLint: `glassEffect|buttonStyle\(\.glass` 가 `Compat/` 밖에서 error.

## 되돌리는 조건
- 디자이너/사용자가 커스텀 탭바 등 Figma 픽셀 일치를 v1.x 필수로 결정하면 → 별도 ADR(비용 재산정)로 `Compat`에 추가.
- iOS 27 이후 Apple이 콘텐츠 층 글래스 지침을 바꾸면 재검토.
- 다크 노출이 Day 19 QA에서 일러스트 문제로 실패하면 `preferredColorScheme(.light)` 유지(토큰은 남김) — 5번 항목의 기본 동작.
