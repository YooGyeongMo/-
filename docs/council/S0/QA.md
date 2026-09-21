# QA·관측 파트장 결정서 (협의체 1차, 2026-09-19)

> 근거 문서: docs/REQUIREMENTS.md(REQ-02·03·11·14·20·22·24·27·31), docs/16_실행계획.md §1-1·§1-2·§3, docs/design/13_개발_CI-CD_전략.md §4~§7, docs/design/12_앱_아키텍처_설계.md §9 규칙 5·6, §10, §11, §12, docs/design/14_시스템_설계서.md §5-1·§8·§10·§15, .github/workflows/app.yml, .swiftlint.yml, apps/ios-macos/Project.swift, ADR-0002.
> 외부 사실은 2026-09-19 조회. 확인 못 한 것은 **확인 필요**로 남겼고 지어내지 않았다.
> 저장소 파일은 수정하지 않았다. 아래 YAML·정규식은 "변경안"이다.

## 0. 먼저 고쳐야 하는 사실 오류 (현재 저장소 기준)

| # | 현재 | 사실 | 영향 |
|---|---|---|---|
| F-1 | `app.yml` 주석 "hosted macos-15는 macOS 26 타깃 테스트 불가 → self-hosted 필요" | GitHub hosted **`macos-26` 이미지가 2026-02-26 GA**. OS 26.6.1, Xcode 26.0.1~26.6(기본 26.6), iOS 26.2/26.4/26.5 시뮬레이터, iPhone 17·iPad Pro M4/M5 기기 포함. **iOS 17.x 런타임은 없음** | macOS 26 실행 테스트는 hosted로 가능. self-hosted의 이유가 바뀐다(§1-4) |
| F-2 | 13번 §5-1 "러너 `macos-15`, Xcode 26.x 고정" | `macos-14` hosted 이미지는 **2026-07-06 폐기 시작, 2026-11-02 완전 종료**(v1.0 11/6 나흘 전). `macos-15`도 차기 폐기 후보(날짜 확인 필요) | macOS 14 최소 OS(REQ-02) 실행 검증은 hosted로 못 한다 |
| F-3 | (암묵) macOS 러너 = 분당 과금 | 공개 저장소(REQ-27)는 **표준 hosted 러너 무료**("The use of standard GitHub-hosted runners is free: In public repositories"). larger 러너만 항상 과금 | CI 예산은 돈이 아니라 **벽시계 시간·동시성**(Free 플랜 macOS 동시 job 상한 5로 알려짐, 확인 필요) |
| F-4 | `Project.swift` deploymentTargets iOS 26/macOS 26 | REQ-02 = iOS 17/macOS 14 | 모든 타깃 `.multiplatform(iOS: "17.0", macOS: "14.0")`로. 테스트 타깃도 같이 |
| F-5 | `app.yml` `xcode-version: latest-stable` | 스냅샷은 Xcode·OS 고정이 전제(12번 §11) | `26.5`처럼 **명시 고정**, 올릴 때 스냅샷 재기록 PR |
| F-6 | 16번 §1-1 "Maestro가 macOS 미지원" | Maestro 공식 지원 플랫폼 문서는 Android·iOS(시뮬레이터 완전 지원)·웹만 기재. 서드파티 글은 "desktop(macOS)" 언급 → **확인 필요**. 계획은 기존대로 macOS = XCUITest | 변경 없음 |

---

## 1. 테스트 매트릭스 재설계 (REQ-02·REQ-03)

### 1-1. 결정 QA-1. 기기·OS 매트릭스는 "PR = 최신 1축, 야간 = 최소 OS + 극단 화면, 릴리스 = 전부"

1. **의도**: REQ-02(iOS 17~26, macOS 14~26)와 REQ-03(SE 4.7"~6K)을 실제로 검증하되, PR 한 번에 15분을 넘기지 않는다. 1인 개발이라 PR이 30분이면 하루 리듬(16번 §5)이 깨진다.
2. **비용**: 돈 0(공개 저장소, 표준 러너). 시간: PR ≈ 12~15분, 야간 ≈ 45~60분(iOS 17 런타임 다운로드 포함), 릴리스 ≈ 90분. 복잡도: 워크플로 1개 → 2개(`app.yml`, `app-nightly.yml`). 유지보수: 스냅샷 파일 수 ≈ 화면 12 × 구성 8 ≈ 100장(1x, ≤ 30MB).
3. **대안**: (a) 매 PR에 전 매트릭스 — 40분+ 대기, 동시성 5 소진, 탈락. (b) iOS 26·macOS 26만 — REQ-02가 요구한 17/14 폴백이 검증 없이 출시, 탈락. (c) 실기기 팜(BrowserStack 등) — 무료 티어 없음(REQ-11), 탈락.
4. **왜**: 버그의 종류가 축마다 다르다. 로직 버그는 OS와 무관하니 한 축(iOS 26 iPhone 17 + macOS 26)에서 PR마다 잡고, `@available` 폴백·레이아웃 깨짐은 OS·화면 극단에서만 나오니 야간에 최소 OS(iOS 17.5 SE)와 극단 화면(iPad 13", Mac 6K)을 돈다. 릴리스 태그는 전부.
5. **영향**: 13번 §4·§5-1(러너·매트릭스 표 교체), 16번 §1-1(스냅샷·E2E 행), 12번 §11 Snapshot 행, `app.yml`, 신규 `app-nightly.yml`, `Project.swift`(F-4), `docs/qa/matrix.md` 신설.
6. **검증**: PR 워크플로 p50 ≤ 15분(Actions 통계 주 1회 기록), 야간 실패 시 자동 이슈, 릴리스 체크리스트(§6) 항목.
7. **리스크·되돌리는 조건**: hosted `macos-26`에서 iOS 17.5 런타임 다운로드가 10분 초과·불안정하면 → 야간 iOS 17 축을 self-hosted로 이동. 야간이 3일 연속 빨간 채 방치되면 → 야간 항목 중 하나를 PR로 승격(원인 항목).

### 1-2. 매트릭스 표

축 정의: **A** iOS 26.5 · iPhone 17 (hosted 기본) / **B** iOS 17.5 · iPhone SE 3세대(4.7", 375×667pt; 런타임 다운로드 필요) / **C** iPadOS 26.5 · iPad Pro 11" M4 / **D** iPadOS 26.5 · iPad Pro 13" M4 / **E** macOS 26 hosted 호스트 / **F** macOS 14 (hosted 없음 → self-hosted Mac 위 VM, §1-4).

| 층 | 도구 | PR마다 | main 머지마다 | 야간(02:00 KST) | 릴리스 태그 `app/v*` | 비고 |
|---|---|---|---|---|---|---|
| 단위(Domain·Data·Navigation·VM) | Swift Testing | A + E | A + E | B (폴백 경로 `@available` 분기 실행) | A·B·E·F | Swift Testing이 iOS 17.5 시뮬레이터에서 도는지 **확인 필요**(안 되면 B는 XCTest 래퍼 없이 스냅샷·E2E만) |
| 계약(yml 예시 디코드, Prism 응답) | 생성 모델 디코드 | E만 | E | — | E | 플랫폼 무관, 한 번이면 됨 |
| 스냅샷 | swift-snapshot-testing | A(DT L·AX3) + D(사이드바 접힘·펼침) + E(창 1024·1440pt) | 좌동 | B(DT L·XXXL·AX5) + C + E 6K(3008×1692pt, §3) + reduceMotion 세트 | 전부 | 러너 이미지·Xcode 고정, 파일명에 OS 포함 |
| E2E iOS | Maestro 4흐름 | — | A | A + B | A + B | Prism 목 서버 or `Mwonmal-Demo` 스킴 |
| E2E macOS | XCUITest 2흐름 | — | — | E | E + F | Maestro macOS 미지원 가정(F-6) |
| 접근성 | XCUITest `performAccessibilityAudit()` | — | — | A + E | A·B·E | API 가용성 iOS 17/macOS 14+로 알려짐, Apple 문서 조회 실패 → **확인 필요** |
| Motion·레이아웃 린트 | SwiftLint custom_rules(§3) | lint job | 좌동 | — | — | 0초에 가까움 |
| AI 회귀(§2) | `eval/run.py` | 프롬프트·eval 변경 PR만 20문장 | — | 40문장 회전 | 200문장 전체 | Gemini 무료 한도 안 |

### 1-3. CI 시간 예산 (hosted `macos-26` 기준 추정, 첫 실측 후 갱신)

| 단계 | 추정 | 줄이는 방법 |
|---|---|---|
| checkout + mise + `tuist install` | 1~2분 | `actions/cache` Tuist 캐시(현재 있음) |
| `brew install swiftlint` | 2~4분 | mise로 swiftlint 고정(가능 여부 확인 필요) 또는 Homebrew 캐시 |
| `tuist generate` + iOS 빌드(캐시 warm) | 3~5분 | `tuist cache`(모듈 바이너리) + DerivedData 캐시 |
| 단위+계약 테스트 | 1~2분 | `-parallel-testing-enabled` |
| 스냅샷 A/D/E | 2~3분 | 1x 스케일, 이미지 diff 시 아티팩트 업로드만 |
| **PR 합계** | **10~15분** | 목표 ≤ 15 |
| iOS 17.5 런타임 다운로드 (`xcodebuild -downloadPlatform iOS -buildVersion 17.5`) | 5~10분(확인 필요) | 야간만. 캐시 불가(수 GB) |
| Maestro 설치 + 4흐름 | 5~8분 | 야간·머지 |
| 접근성 감사 + XCUITest mac | 5분 | 야간 |
| **야간 합계** | **45~60분** | 병렬 job 3개면 벽시계 25분 |

### 1-4. self-hosted 러너 필요성 판단

- **결론: 필수 아님, 단 1가지 용도로 "있으면 좋음"**: macOS 14(REQ-02 최소) 실행 검증. hosted `macos-14`가 11/2에 사라지므로 v1.0(11/6) 릴리스 검증은 hosted로 불가능. 소유자 Mac은 macOS 26(Darwin 25.x)이라 self-hosted 자체도 macOS 26이다 → macOS 14는 **Mac 위 VM**(Tart 또는 UTM, Apple Silicon macOS 14 IPSW)에서만 가능. Tart 무료 범위(개인 사용) **확인 필요**.
- 대안 비교: (a) macOS 14는 **빌드만**(deployment target 14로 컴파일 = `@available` 누락을 컴파일러가 잡음) + 릴리스 전 VM 수동 스모크 20분 — 채택(v1). (b) macOS 14 실기 구매 — 비용, 탈락. (c) macOS 15 hosted로 대체 — 최소 OS가 아니라 의미 반감, 폐기 예정, 탈락.
- 보안(ADR-0002 유지): self-hosted는 `push main`·`schedule`·`workflow_dispatch`에서만. `pull_request`에는 절대 배정하지 않는다(공개 저장소 fork PR 코드 실행 위험).

### 1-5. `app.yml` 변경안 (YAML 조각)

```yaml
name: app
on:
  pull_request:
    paths: ["apps/**", "contracts/**", "packages/test-vectors/**", ".github/workflows/app.yml", ".swiftlint.yml", ".swiftformat"]
  push:
    branches: [main]
    paths: ["apps/**", "contracts/**"]
concurrency:
  group: app-${{ github.ref }}
  cancel-in-progress: true

env:
  XCODE_VERSION: "26.5"          # F-5: latest-stable 금지. 올릴 때 스냅샷 재기록 PR과 함께
  IOS_SIM_LATEST: "iPhone 17,OS=26.5"
  IPAD_SIM_13: "iPad Pro 13-inch (M4),OS=26.5"

jobs:
  lint:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - uses: actions/cache@v4            # brew 캐시 (swiftlint 2~4분 절감)
        with: { path: ~/Library/Caches/Homebrew, key: brew-${{ runner.os }}-swiftlint }
      - run: brew install swiftlint
      - run: swiftlint --strict            # §3 custom_rules 포함
      - run: swiftformat --lint .

  build-test:
    # hosted macos-26: 호스트가 macOS 26이라 macOS 앱 실행 테스트 가능(F-1). iOS 17 런타임은 야간(app-nightly.yml).
    runs-on: macos-26
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: ${{ env.XCODE_VERSION }} }
      - uses: actions/cache@v4
        with:
          path: |
            apps/ios-macos/.tuist-cache
            apps/ios-macos/Tuist/.build
            ~/Library/Developer/Xcode/DerivedData
          key: tuist-${{ runner.os }}-${{ env.XCODE_VERSION }}-${{ hashFiles('apps/ios-macos/Tuist/Package.resolved', 'contracts/openapi.yml') }}
      - run: cd apps/ios-macos && tuist install && tuist generate --no-open
      # 1) 최소 OS 컴파일 게이트: deployment target 17/14로 빌드되면 @available 누락은 여기서 잡힌다(REQ-02)
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalMac -destination 'platform=macOS' -skipPackagePluginValidation build
      # 2) 단위+계약: iOS 26 iPhone 17 + macOS 26 호스트
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalIOS -destination "platform=iOS Simulator,name=${{ env.IOS_SIM_LATEST }}" -skipPackagePluginValidation -parallel-testing-enabled YES -only-testing:DomainTests -only-testing:DataTests -only-testing:MwonmalAPITests -only-testing:PresentationTests -only-testing:NavigationTests -only-testing:CompositionTests -only-testing:PlatformTests test
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalMac -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:DomainTests -only-testing:NavigationTests -only-testing:PlatformTests test
      # 3) 커버리지 게이트 (13번 §4): 변경 라인 ≥80%, Domain/Rules 100%
      - run: cd apps/ios-macos && scripts/coverage-gate.sh   # xccov → 변경 라인 계산 (S0 Day 5에 작성)

  snapshot:
    runs-on: macos-26
    needs: lint
    strategy:
      fail-fast: false
      matrix:
        include:
          - { name: iphone17,  dest: "platform=iOS Simulator,name=iPhone 17,OS=26.5",               scheme: MwonmalIOS }
          - { name: ipad13,    dest: "platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=26.5",   scheme: MwonmalIOS }
          - { name: mac26,     dest: "platform=macOS",                                              scheme: MwonmalMac }
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: ${{ env.XCODE_VERSION }} }
      - uses: actions/cache@v4
        with:
          path: |
            apps/ios-macos/.tuist-cache
            apps/ios-macos/Tuist/.build
            ~/Library/Developer/Xcode/DerivedData
          key: tuist-${{ runner.os }}-${{ env.XCODE_VERSION }}-${{ hashFiles('apps/ios-macos/Tuist/Package.resolved', 'contracts/openapi.yml') }}
      - run: cd apps/ios-macos && tuist install && tuist generate --no-open
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme ${{ matrix.scheme }} -destination "${{ matrix.dest }}" -skipPackagePluginValidation -only-testing:MwonmalUITests -only-testing:PresentationTests/SnapshotTests test
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: snapshot-diff-${{ matrix.name }}, path: "apps/ios-macos/**/__Snapshots__/**/*.png", retention-days: 7 }

  e2e-ios:
    # 머지마다만 (PR 아님). Prism 목 서버 or Mwonmal-Demo 스킴
    if: github.event_name == 'push'
    runs-on: macos-26
    needs: build-test
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: ${{ env.XCODE_VERSION }} }
      - run: brew install maestro                   # 버전 고정은 `brew install maestro@x` 형태 가능 여부 확인 필요
      - run: cd apps/ios-macos && tuist install && tuist generate --no-open
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme Mwonmal-Demo -destination "platform=iOS Simulator,name=${{ env.IOS_SIM_LATEST }}" -derivedDataPath build build
      - run: xcrun simctl boot "iPhone 17" && xcrun simctl install booted apps/ios-macos/build/Build/Products/Debug-iphonesimulator/Mwonmal.app
      - run: maestro test apps/ios-macos/e2e/flows/          # 4흐름: 로그인→해석, 녹음→결과, 복습, 테스트
```

`app-nightly.yml` (신규, 조각):

```yaml
name: app-nightly
on:
  schedule: [{ cron: "0 17 * * *" }]     # 02:00 KST
  workflow_dispatch:
jobs:
  ios17-min:
    runs-on: macos-26
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: "26.5" }
      - run: xcodebuild -downloadPlatform iOS -buildVersion 17.5     # 5~10분 추정, 확인 필요. Xcode 26은 iOS 15+ 시뮬레이터 지원으로 알려짐
      - run: xcrun simctl create "SE3-17" "iPhone SE (3rd generation)" "com.apple.CoreSimulator.SimRuntime.iOS-17-5"
      - run: cd apps/ios-macos && tuist install && tuist generate --no-open
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalIOS -destination "platform=iOS Simulator,name=SE3-17,OS=17.5" -skipPackagePluginValidation test   # 단위 + 스냅샷(SE·XXXL·AX5·reduceMotion)
      - run: brew install maestro && maestro test apps/ios-macos/e2e/flows/
  mac-a11y-xcui:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: cd apps/ios-macos && tuist install && tuist generate --no-open
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalMac -destination 'platform=macOS' -only-testing:MwonmalMacUITests test   # XCUITest 2흐름 + performAccessibilityAudit
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalIOS -destination "platform=iOS Simulator,name=iPhone 17,OS=26.5" -only-testing:MwonmalIOSUITests/AccessibilityAuditTests test
      - run: cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalMac -destination 'platform=macOS' -only-testing:MwonmalUITests/Snapshot6KTests test   # §3-2 6K
  ai-eval:
    runs-on: ubuntu-latest        # §2
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
      - uses: actions/cache@v4
        with: { path: eval/.cache, key: eval-${{ hashFiles('services/api/app/**/prompts/**', 'eval/dataset.jsonl') }} }
      - run: uv run eval/run.py --sample 40 --seed "$(date +%Y%m%d)" --baseline eval/baseline.json --fail-on-regression
        env: { GEMINI_API_KEY: "${{ secrets.GEMINI_API_KEY }}" }
  on-failure-issue:
    needs: [ios17-min, mac-a11y-xcui, ai-eval]
    if: failure()
    runs-on: ubuntu-latest
    steps:
      - run: gh issue create --title "[nightly] $(date +%F) 실패" --label "area:qa,type:test" --body "run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
        env: { GH_TOKEN: "${{ github.token }}" }
```

릴리스 태그(`app/v*`) 워크플로는 위 두 개를 `workflow_call`로 모두 호출 + macOS 14 VM 스모크는 수동 체크리스트(§6).

---

## 2. AI 품질 게이트

### 2-1. 결정 QA-2. 평가셋 회귀는 "캐시 우선, 야간 40문장 회전, 프롬프트 변경 PR만 20문장, 전체 200은 릴리스"

1. **의도**: 14번 §15 "평가셋 없이는 모델을 바꾸지 않는다"를 자동으로 강제. 프롬프트·사전·모델 변경이 품질을 떨어뜨리면 머지 전에 안다.
2. **비용**: 돈 0. Gemini 무료 티어 일일 요청(RPD)은 자료가 엇갈림(2.5 Flash 250 RPD / 신형 Flash ≈ 20 RPD / Flash-Lite 500 RPD) → **확인 필요**, 최악 20 RPD로 설계. 야간 40문장은 2일치(20 RPD면 20문장으로 낮춤). 캐시 히트면 호출 0. 시간: 야간 5분.
3. **대안**: (a) PR마다 200문장 — 하루 한도 초과, 개발 중 실제 해석 호출과 경쟁, 탈락. (b) 회귀 테스트 없이 수동 점수표 — 14번 §15 위반, 탈락. (c) 유료 키 — REQ-11 위반, 탈락.
4. **왜**: 프롬프트가 안 바뀌면 답도 안 바뀐다. 입력 = (모델, 프롬프트 SHA, 사전 SHA, 문장 SHA)를 키로 캐시하면 호출은 "바뀐 것"에만 나간다. 그래서 무료 한도 안에서 사실상 매일 전체를 커버한다(40문장 × 5일 회전 = 200).
5. **영향**: `eval/dataset.jsonl`, `eval/run.py`, `eval/baseline.json`, `eval/.cache/`(gitignore, actions/cache), `app-nightly.yml ai-eval`, `server.yml`에 프롬프트 경로 `paths` 추가, 14번 §15 평가셋 문단에 "CI 회귀" 한 줄, `docs/qa/ai-gate.md`.
6. **검증**: 게이트 임계값 — JSON 유효율 ≥ 98%, intentType 정확도 baseline −3pt 이내, 용어 탐지 F1(termId 기준) baseline −3pt 이내, 할 일 추출 토큰 F1 ≥ 0.6 평균, 인덱스 재계산 일치율 100%(서버가 재계산하므로 AI 인덱스는 참고), p95 지연 기록(게이트 아님). baseline은 S2 Day 11 v0 50문장으로 첫 커밋, 이후 "의도적 개선 PR"에서만 갱신(PR 본문에 전후 표 필수).
7. **리스크·되돌리는 조건**: 무료 RPD가 20 이하로 확인되면 야간 표본 20, 전체 200은 주 1회 일요일 분할(4일 × 50). 평가셋 문장은 **직접 작성한 합성 문장만**(공개 저장소·REQ-14: 사용자 원문 절대 금지) — 위반 발견 시 즉시 삭제·히스토리 정리.

데이터 형식(`eval/dataset.jsonl` 한 줄):
```json
{"id":"E-042","sourceText":"…합성 판교어 문장…","direction":"TO_PLAIN","expected":{"intentType":"REQUEST","terms":["align","asap"],"actionItems":[{"text":"기획안 공유","dueHint":"오늘"}],"resultTextKeywords":["맞추다","빨리"]},"tags":{"len":"S","job":"PM","hard":2}}
```
샘플링: `tags` 층화(길이 S/M/L, 직군, 난이도) 후 `seed=YYYYMMDD` 결정적 추출 → 재현 가능. 점수표는 `eval/reports/YYYY-MM-DD.md`로 저장(아티팩트 + 주간 요약만 커밋).

### 2-2. 스키마 검증 (TranslationResult JSON)

- **원본은 하나**: `contracts/openapi.yml`의 TranslationResponse(정확한 스키마 이름 **확인 필요**). AI 출력 JSON은 이 스키마의 부분집합(resultText, intentType, nuance, actionItems[], detectedTerms[])이어야 하며 14번 §5-1 4단계에서 Pydantic으로 검증한다. AI 전용 필드(ai_term_ko 등)는 `services/api/app/domain/ai_schema.py`에 yml 스키마를 **확장**해 정의하고, yml에서 생성한 Pydantic 모델을 상속해 드리프트를 막는다.
- 서버 테스트 3종(PR마다): ① 녹음된 AI 응답 30건(합성 문장 기준, `tests/ai/fixtures/*.json`) 전부 디코드 ② `hypothesis-jsonschema`로 스키마 기반 퍼징 200회 → 디코드가 예외 없이 accept/reject ③ 잘못된 JSON·필드 누락·enum 밖 intentType → `503 AI_UNAVAILABLE`로 매핑(30코드 계약, 12번 §5).
- 인덱스 검증은 `packages/test-vectors/highlight_ranges.json`(13번 §5-3 "형광펜 정답")을 Swift·Python 양쪽이 읽는다 — 파일은 아직 없음(현재 `level_table.json`만) → S2 Day 11 산출물에 추가.
- 앱: `MwonmalAPITests` yml 예시 디코드(이미 계획). 추가로 야간 eval 산출 JSON 40건을 아티팩트로 내려 Swift 디코드 테스트에 넣는 것은 v1.1(계약 v1.1과 함께).

### 2-3. 프라이버시 테스트 (원문이 로그·Sentry payload에 없는지 자동 검사)

원칙(12번 §10·§12, 13번 §7): `sourceText`, `transcript`, `extractedText`, 오디오는 어떤 SDK로도 나가지 않는다. **카나리 문자열** 기법으로 자동화한다 — 테스트 입력에 `MWCANARY-<uuid>`를 넣고 나가는 모든 바이트에서 grep.

| 층 | 방법 | 언제 |
|---|---|---|
| 서버 Sentry | `sentry_sdk.init(transport=CapturingTransport)`(메모리 트랜스포트)로 pytest 픽스처 구성. `POST /translations`에 카나리 원문 + AI 어댑터를 예외 던지는 Stub으로 → 캡처된 envelope 전체 직렬화에 카나리 없음 assert. `before_send`가 request body·breadcrumb data를 지우는지 여기서 검증 | PR마다 |
| 서버 로그 | structlog/JSON 로거를 `capsys`/핸들러로 캡처. 같은 요청 후 모든 로그 라인에 카나리 없음 + 허용 필드 화이트리스트(request_id, user_hash, operation_id, latency_ms, status) 이외 키 존재 시 실패 | PR마다 |
| 앱 Sentry | `Platform/Observability/SentryScrubber.swift`를 **순수 함수**(`func scrub(_ event: Event) -> Event?`)로 분리. `PlatformTests`에서 URL·request body·breadcrumb message·extra에 카나리를 넣은 Event → scrub 후 `JSONEncoder` 직렬화 문자열에 카나리 없음. `.aiUnavailable/.emptyState/.cancelled`는 nil 반환(드롭) 테스트 | PR마다 |
| 앱 Amplitude | `AnalyticsService` 프로토콜의 속성 타입을 `enum AnalyticsValue { case int, bool, seconds, id(TermID), level, enumString(…) }`로 좁혀 **문자열 자유 입력을 컴파일 시점에 막는다**. 이벤트 15개 × 허용 키 화이트리스트(`termId, level, direction, inputSource, phase, count, seconds, bool`) 테스트 — 표에 없는 키면 실패 | PR마다 |
| 정적 검사 | SwiftLint custom_rule `no_raw_text_to_sdk`: `included: Platform/Sources/Observability/.*` 안에서 `\b(sourceText|transcript|extractedText|resultText)\b` 등장 시 error. 서버는 `bandit` + ruff 커스텀 대신 `tests/test_privacy_grep.py`가 `infra/observability/**`를 grep | lint job |
| 통합(야간) | Maestro 흐름 실행 시 앱 스킴 `Mwonmal-Demo`의 Sentry DSN을 로컬 싱크(`eval/tools/sentry_sink.py`, 20줄 HTTP 서버)로 향하게 하고 강제 에러 화면 1개를 흐름에 포함 → 싱크에 쌓인 envelope에서 카나리·한글 원문 패턴 grep | 야간 |

결정 기록(요약, REQ-20): 의도 = REQ-14 불변식을 사람이 아니라 CI가 지킨다 / 비용 = 테스트 코드 ~200줄, 실행 수 초 / 대안 = Sentry 서버 측 데이터 스크러빙 규칙만(전송 후 삭제라 "안 나감"이 아님, 탈락), 수동 debug view 확인(릴리스 때만, 회귀 못 잡음, 탈락) / 왜 = 나가기 전 마지막 함수(`beforeSend`, 로거)를 순수 함수로 두면 결정적으로 테스트된다 / 되돌리는 조건 = 없음(불변식).

---

## 3. Motion·레이아웃 QA (REQ-03·REQ-22)

### 3-1. 결정 QA-3. reduceMotion·Dynamic Type·화면 극단은 스냅샷으로, 고정 px는 린트로

1. **의도**: "가장 작은 화면부터 6K까지, 고정 px 금지"(REQ-03)와 "애니메이션은 Motion 모듈에서만 튜닝"(REQ-22)을 코드 리뷰가 아니라 도구가 잡는다.
2. **비용**: 스냅샷 파일 +약 60장(1x). 린트 초기 오탐 정리 반나절(S0 Day 5, S2 Day 13). 6K 이미지 스냅샷은 크기(1x 3008×1692 PNG ≈ 2~5MB)라 **핵심 3화면만 이미지**, 나머지는 텍스트 계층 스냅샷.
3. **대안**: (a) 디자인 리뷰 체크리스트만 — 회귀 못 잡음, 탈락. (b) `reduceMotion`을 실제 시스템 설정으로 켜고 XCUITest — 시뮬레이터 설정 조작이 느리고 불안정, 탈락(야간 1회 보조로만). (c) 고정 px를 코드 리뷰로 — 1인 개발에 리뷰어 없음, 탈락.
4. **왜**: `accessibilityReduceMotion`은 SwiftUI 환경값이 **get-only**(Apple 문서: `var accessibilityReduceMotion: Bool { get }`, iOS 13+/macOS 10.15+)라 테스트에서 직접 주입할 수 없다. 그래서 REQ-22의 Motion 모듈이 자기 환경 키 `\.mwMotion: MotionProfile`을 갖고, Composition이 시스템 값을 읽어 `.reduced`로 넣는다. 테스트는 `.environment(\.mwMotion, .reduced)`로 결정적으로 스냅샷한다. Dynamic Type은 `dynamicTypeSize(_:)`(iOS 15+/macOS 12+, Apple 문서 확인)로 주입 가능.
5. **영향**: 12번 §9 규칙 5·6에 "테스트 주입 경로" 한 줄, `MwonmalUI/Motion/MotionProfile.swift`, `MwonmalUITests/Snapshot*`, `.swiftlint.yml` custom_rules, 05번 디자인시스템(토큰 이름 `MwSize`, `MwSpacing` 참조).
6. **검증**: 린트 오탐률 — 도입 첫 주 `warning`으로 두고 disable 주석 수 ≤ 10개면 `error` 승격. 스냅샷 매트릭스 표 §1-2.
7. **리스크·되돌리는 조건**: 규칙이 컴포넌트 작성 속도를 눈에 띄게 늦추면(하루 disable 주석 5개 이상) 해당 규칙만 `warning`으로 강등하고 토큰(`MwSize`)을 보강한다.

### 3-2. 스냅샷 구성

| 세트 | 구성 | 주입 | 어디서 |
|---|---|---|---|
| reduceMotion | 흐름 4개 대표 화면 × {`.standard`, `.reduced`} | `.environment(\.mwMotion, .reduced)` + `UIView.setAnimationsEnabled(false)`(iOS) | PR: A / 야간: B |
| Dynamic Type | 화면 12 × {L, xxxLarge, accessibility3, accessibility5} | `.dynamicTypeSize(.accessibility5)` | PR: L·AX3(A) / 야간: XXXL·AX5(B SE) |
| 최소 화면 SE 4.7" | 화면 12 × L·AX5 | `ViewImageConfig` 375×667pt(snapshot-testing의 `.iPhoneSe`는 320×568 1세대 크기 → **SE 3세대는 `.iPhone8` 구성 사용**, 확인 필요) | 야간 B |
| iPad 11"·13" | 사이드바 접힘·펼침 × 세 열 | `ViewImageConfig(size: 834×1194 / 1032×1376)` + `horizontalSizeClass .regular` | PR: 13"(D) / 야간: 11"(C) |
| Mac 창 | 1024×700, 1440×900 | `NSHostingView(rootView:)` frame | PR: E |
| Mac 6K | 3008×1692pt(6016×3384px @2x를 1x로) | 핵심 3화면(A-01 홈, A-06 결과, W-02 녹음) 이미지 1x + 나머지 `recursiveDescription` 텍스트 스냅샷(프레임 값 포함 → 고정 px가 있으면 diff로 드러남) | 야간 E |
| 빈·에러 상태 | 12번 §11대로 | Fake Repository | PR |

파일명 규칙: `__Snapshots__/<Test>/<case>.<device>.<os>.<dt>.<motion>.png` — OS 문자열 포함으로 러너 OS 변경 시 "재기록 필요"가 diff로 보인다. `perceptualPrecision: 0.98`, `precision: 0.99`(폰트 안티에일리어싱 흔들림 흡수).

### 3-3. 고정 px 금지 린트 — `.swiftlint.yml` custom_rules 초안

```yaml
custom_rules:
  # ── REQ-03: 고정 px 금지 ─────────────────────────────────────────────
  fixed_frame_literal:
    name: "frame에 숫자 리터럴 금지 (REQ-03)"
    included: "apps/ios-macos/Modules/(Presentation|MwonmalUI)/Sources/.*\\.swift"
    excluded: "apps/ios-macos/Modules/MwonmalUI/Sources/Tokens/.*\\.swift"   # 숫자는 토큰 파일에만 산다
    regex: "\\.frame\\([^)]*\\b(?:width|height|minWidth|minHeight|maxWidth|maxHeight|idealWidth|idealHeight)\\s*:\\s*\\d+(?:\\.\\d+)?"
    match_kinds: [identifier, number, keyword, argument]   # comment·string 제외 → 주석·문자열 안 숫자는 오탐 아님
    message: "크기는 MwSize/MwSpacing 토큰 또는 GeometryReader·containerRelativeFrame로. 아이콘 등 예외는 `// swiftlint:disable:next fixed_frame_literal - <이유>`"
    severity: error
  fixed_size_bare:
    name: "fixedSize() 금지 (규칙 6)"
    included: "apps/ios-macos/Modules/(Presentation|MwonmalUI)/Sources/.*\\.swift"
    regex: "\\.fixedSize\\(\\s*\\)|\\.fixedSize\\(\\s*horizontal\\s*:\\s*true"
    match_kinds: [identifier, keyword, argument]
    message: "카드·시트에 fixedSize 금지. 텍스트 줄바꿈용 fixedSize(horizontal: false, vertical: true)만 허용"
    severity: error
  hardcoded_font_size:
    name: "폰트 크기 리터럴 금지 (규칙 6 Dynamic Type)"
    included: "apps/ios-macos/Modules/(Presentation|MwonmalUI)/Sources/.*\\.swift"
    excluded: "apps/ios-macos/Modules/MwonmalUI/Sources/Tokens/.*\\.swift"
    regex: "\\.font\\(\\s*\\.system\\(\\s*size\\s*:|Font\\.custom\\([^)]*size\\s*:\\s*\\d+(?![^)]*relativeTo)"
    match_kinds: [identifier, number, keyword, argument]
    message: "MwFont 토큰만. Font.custom은 relativeTo 필수"
    severity: error
  hardcoded_spacing_literal:
    name: "padding/spacing 숫자 리터럴 (MwSpacing 사용)"
    included: "apps/ios-macos/Modules/(Presentation|MwonmalUI)/Sources/.*\\.swift"
    excluded: "apps/ios-macos/Modules/MwonmalUI/Sources/Tokens/.*\\.swift"
    regex: "\\.padding\\((?:\\.[a-zA-Z]+\\s*,\\s*)?\\d+|\\b(?:VStack|HStack|LazyVStack|LazyHStack|Grid)\\([^)]*spacing\\s*:\\s*\\d+|\\.cornerRadius\\(\\s*\\d+|Spacer\\(\\s*minLength\\s*:\\s*\\d+"
    match_kinds: [identifier, number, keyword, argument]
    message: "MwSpacing/MwRadius 토큰"
    severity: warning        # S1까지 warning, S2 Day 13(JargonText) 이후 error
  # ── REQ-22: 애니메이션 코어는 Motion 모듈에만 ─────────────────────────
  hardcoded_animation:
    name: "애니메이션 프리셋 직접 사용 금지 (REQ-22)"
    included: "apps/ios-macos/Modules/(Presentation|MwonmalUI)/Sources/.*\\.swift"
    excluded: "apps/ios-macos/Modules/MwonmalUI/Sources/Motion/.*\\.swift"
    regex: "\\b(?:withAnimation|\\.animation|\\.transition)\\(\\s*\\.(?:easeIn|easeOut|easeInOut|linear|spring|bouncy|smooth|snappy|interactiveSpring|interpolatingSpring|default)\\b|\\.repeatForever\\(|Animation\\.(?:easeIn|easeOut|easeInOut|linear|spring)\\b|\\bduration\\s*:\\s*\\d+(?:\\.\\d+)?\\s*[,)]"
    match_kinds: [identifier, number, keyword, argument]
    message: "MwMotion.<이름> (MwonmalUI/Motion)만 사용. 새 곡선·지속시간은 Motion 모듈에 추가"
    severity: error
  # ── 오탐 대책: disable 주석엔 이유가 있어야 한다 ──────────────────────
  disable_without_reason:
    name: "swiftlint:disable에 이유 필수"
    regex: "swiftlint:disable(?::next|:this|:previous)?\\s+[a-z_ ]+\\s*$"
    match_kinds: [comment]
    message: "형식: // swiftlint:disable:next <rule> - <이유 한 줄>"
    severity: error
  # ── REQ-14: 원문이 관측 SDK 코드에 등장 금지 ─────────────────────────
  no_raw_text_to_sdk:
    name: "원문 필드가 Observability에 등장 금지 (REQ-14)"
    included: "apps/ios-macos/Modules/Platform/Sources/Observability/.*\\.swift"
    regex: "\\b(?:sourceText|transcript|extractedText|resultText|audioURL)\\b"
    message: "Sentry/Amplitude 어댑터는 원문·받아쓰기·오디오를 알면 안 된다"
    severity: error
```

오탐 대책 정리:
- **범위 제한**: `included`를 Presentation·MwonmalUI Sources로, `excluded`로 Tokens·Motion·Catalog·Tests 제외. 숫자는 토큰 파일 한 곳에만 산다.
- **`match_kinds`로 주석·문자열 제외**: SwiftLint custom_rules는 SourceKit 토큰 종류로 필터 가능 — 문서 문자열의 "44pt" 같은 것은 안 걸린다(정확한 kind 이름 `argument`/`number` 유효성 **확인 필요**, 없으면 `[identifier, keyword, number]`).
- **정당한 예외**: 1pt 구분선·아이콘 24·터치 타깃 44는 `MwSize.hairline/.icon/.tapTarget` 토큰으로 제공해 disable 자체를 줄인다. 그래도 필요하면 disable 주석 + 이유(위 규칙이 강제).
- **텍스트 줄바꿈 관용구** `fixedSize(horizontal: false, vertical: true)`는 허용(정규식이 `horizontal: true`·빈 호출만 잡음).
- **`.frame(maxWidth: .infinity)`**는 숫자가 아니라 통과. `.frame(width: geo.size.width * 0.5)`도 통과(리터럴 아님).
- **lookahead** `(?![^)]*relativeTo)`는 SwiftLint(ICU 정규식)에서 지원. 여러 줄 호출은 `[^)]*`가 줄바꿈을 포함하므로 잡힌다.
- 도입 순서: S0 Day 5에 규칙 추가(전부 warning) → S1 끝 disable 개수 세고 → S2 Day 13부터 error.

---

## 4. 도구별 REQ-20 ADR 초안 항목 (의도 → 비용 → 대안 → 왜, 각 5줄)

| 도구 | 의도 | 비용(무료 한도) | 대안(왜 탈락) | 왜 |
|---|---|---|---|---|
| **Sentry** (앱·서버) | "깨졌나·느린가·어디서"(16번 §1-2). 크래시·처리된 에러·트랜잭션 4개·release health | Developer 플랜 **5,000 errors/월, 10,000 performance units/월, 30일 보존, 1 사용자**(외부 자료, 공식 페이지 **확인 필요**). `tracesSampleRate 0.1`이면 200 MAU에서 여유. 앱 SDK 1개, dSYM 업로드 CI 1분 | Firebase Crashlytics(서버 없음·Google 종속, D-24 Firebase 금지) / 자체 로그만(크래시 심볼화·release health 없음) | 앱·서버를 `X-Request-Id` 하나로 잇는 것이 목적이고 둘 다 지원하는 무료 도구는 이것뿐. 원문 차단은 §2-3 테스트로 보증 |
| **Amplitude** | "쓰나·돌아오나·어디서 떠나나". 이벤트 15개·퍼널 4·리텐션 | Starter 무료 **10,000 MTU·2M events/월·1,000 events/MTU**(외부 자료 2026, 공식 **확인 필요** — 과거 50k MTU 자료와 상충). v1 규모 충분. 텍스트 속성 금지 | Firebase Analytics(D-24) / PostHog 자체 호스팅(운영 대상 +1, 14번 §13 정신 위배) / 서버 로그 집계(리텐션·퍼널 UI 없음) | Sentry와 질문을 분리(REQ-31)하면서 무료로 퍼널·리텐션을 주는 것. IDFA 없음이라 ATT 불필요 |
| **swift-snapshot-testing** | REQ-03 화면 매트릭스를 파일로 고정, PR diff로 회귀 | 무료 MIT. Swift Testing 지원(`@Suite(.snapshots(record: .failed))`). 파일 ~100장·30MB, 러너 OS·Xcode 고정 필요 | XCUITest 스크린샷 비교(느리고 픽셀 도구 없음) / 수동 시뮬레이터 확인(회귀 못 잡음) | SwiftUI 뷰를 hosting해 1x로 찍고 `perceptualPrecision`으로 폰트 흔들림 흡수. Dynamic Type·사이즈 클래스 주입이 코드 한 줄 |
| **Maestro** (iOS E2E) | 핵심 흐름 4개를 실제 시뮬레이터에서 YAML로 | 무료 OSS CLI(`brew install maestro`), Cloud 안 씀. 흐름당 1~2분. macOS 앱 미지원(공식 문서엔 Android·iOS·웹만, **확인 필요**) | XCUITest 전부(작성 비용 3배, 플레이키) / Appium(서버·드라이버 관리) | YAML 흐름은 비개발자도 읽고, 셀렉터가 accessibility id라 접근성 라벨(규칙 5)을 겸사겸사 강제한다. macOS만 XCUITest 2흐름 |
| **schemathesis** (서버 계약) | yml 43 op 전부에 요청 생성 → 응답 스키마·상태코드 검증. 앱·서버를 묶는 가장 강한 게이트(13번 §4) | 무료 OSS. `--hypothesis-max-examples=5`로 PR 2~3분 | Dredd(유지보수 정체) / 손으로 쓴 계약 테스트(43 op 커버 불가) | OpenAPI 하나가 원본이라는 E-1 결정을 실행 가능하게 만든다. 현재 `\|\| true`는 S0 Day 4에 제거 |
| **k6** (부하) | 14번 §8 목표(해석 p95 2s, 폴링 200세션) 검증 | 무료 OSS, dev VM 대상 로컬 실행 15분. Grafana Cloud k6 무료 티어는 안 씀 | Locust(파이썬, 분산 설정 무거움) / ab·wrk(시나리오 불가) | JS 시나리오로 "해석 30rps + 폴링 200세션 동시"를 한 스크립트로 표현, 임계값(`thresholds`)이 exit code라 CI화 가능(S6만) |
| **gitleaks** | REQ-27 시크릿 커밋 금지 | 무료. **개인 계정 저장소는 라이선스 키 불필요**(공식 README: "personal account… no license key is required"), 조직 저장소면 무료 키 발급 필요. PR당 10초 | trufflehog(엔트로피 오탐 많음) / GitHub secret scanning만(푸시 후 감지, 사전 차단 아님) | 공개 저장소에서 사전 차단이 필요하고 히스토리 전체(`fetch-depth: 0`) 스캔이 기본 |
| **trivy** | 컨테이너 이미지·의존성 취약점(CRITICAL/HIGH) 차단 | 무료 OSS, `main` 푸시 시만 1~2분. `@master` 핀 → 태그 고정 권고 | grype(동등, 생태계 작음) / Docker Scout(계정 필요) | SBOM 생성까지 한 도구, GitHub Action 공식 |
| **Tuist** | 8모듈 그래프 강제·캐시(ADR-0001) | 무료 OSS CLI(mise 4.208 고정). Tuist Cloud/서버 캐시 안 씀. CI에 `tuist install` 1~2분 | SPM 단일 패키지(ADR-0001) / XcodeGen | 의존 방향 위반이 생성 실패라 REQ-26을 도구가 지킨다. QA 관점: 테스트 타깃 8개를 스킴에 자동 묶음 |

각 항목은 `docs/adr/0005~0013`로 옮길 때 BRIEF 7항목(영향 파일·검증·되돌리는 조건)을 §1~§3 본문에서 채운다.

---

## 5. archify (REQ-24) 조사

### 5-1. 정체 — 확인됨

- **`tt-a1i/archify`** (GitHub, MIT). "Agent skill for beautiful, verifiable architecture, workflow, sequence, data-flow, and lifecycle diagrams — self-contained HTML with motion and crisp export." Cocoon-AI/architecture-diagram-generator(MIT v1.0) 기반.
- **이미 이 Mac에 설치돼 있다**: `~/.claude/skills/archify` (skill 사본, 2026-09-17), 원본 클론 `~/.claude/skill-vendor/archify` (버전 `2.17.0-dev.1`, 최신 커밋 2026-09-16). Claude Code 스킬 목록에 `archify`로 노출됨.
- **설치 방법**: npm 공개 패키지 **아님**(`package.json` `"private": true`), brew·pip 없음. 공식 경로는 `npx skills add tt-a1i/archify -g` (Cursor/Claude Code/Codex/OpenCode 공용 skills 매니저). 요구: **Node ≥ 18**, 외부 런타임 의존성 없음(devDependencies만: ajv, parse5, saxes, simple-icons). `visual-check`는 브라우저(Playwright 계열) 필요 — 세부 **확인 필요**.
- **입력 형식**: **코드로 그리는 것도, 일반 DSL도 아니다.** 타입이 있는 **JSON IR** 5종(`architecture`, `workflow`, `sequence`, `dataflow`, `lifecycle`; 스키마 `schemas/*.schema.json`). 사람/에이전트가 자연어 요구를 JSON으로 저술하거나, **Mermaid**(`flowchart`/`sequenceDiagram`/`stateDiagram`)를 붙여넣으면 에이전트가 JSON으로 재저술한다. 저장소 코드를 근거로 그리는 "repository evidence" 모드 있음(노드에 커밋 증거 첨부).
- **산출물**: 자립형 **HTML(인라인 SVG)** 1파일 — 다크/라이트, 팬·줌, 검색, 경로 추적, 프레젠테이션. Export: **PNG/JPEG/WebP/SVG/WebM**, 1200×630 공유 카드. CLI: `validate`(9개 검사, `--quality showcase`), `deliver`(SHA-256 영수증), `visual-check`(브라우저 증거), `compare`(아키텍처 델타 HTML), `guide`, `doctor`, `demo`.
- **동명 후보(혼동 주의)**: 14번 §5-1의 "`_archify` '같은 문장은 저장해 두고' 항목"은 이 도구가 아니라 기획 메모 파일명으로 보임 → **확인 필요**. 그 외 macOS 유니버설 바이너리 정리 앱 "Archify" 등 동명 프로젝트가 있으나 REQ-24 문맥(구조·흐름 그림)과 무관.

### 5-2. 대안 비교

| | archify (tt-a1i) | Mermaid | D2 | Structurizr (C4) |
|---|---|---|---|---|
| 입력 | JSON IR(5 스키마) / Mermaid 변환 | 텍스트 DSL | 텍스트 DSL | Structurizr DSL(C4 모델) |
| 출력 | 자립 HTML+SVG, PNG/SVG/WebM | SVG/PNG(mermaid-cli), GitHub 마크다운 **네이티브 렌더** | SVG/PNG(다중 레이아웃 엔진) | Lite(도커)·Cloud, PlantUML/Mermaid export |
| 검증 | 스키마+레이아웃+라벨 충돌 9검사, 영수증 | 문법만 | 문법·레이아웃 | 모델 일관성(C4) |
| GitHub에서 보임 | HTML은 미리보기 불가 → **PNG를 같이 커밋** | 코드블록 그대로 렌더 | 이미지 커밋 | 이미지 커밋 |
| 설치 | Node ≥18 + skills 매니저 | 없음(브라우저), CLI는 npm | brew | Docker/Java |
| 에이전트 친화 | 스킬 자체가 이것 | 높음 | 중간 | 낮음 |
| 비용 | 0 | 0 | 0 | Lite 0 |
| 약점 | 저장소에 도구가 없음(사용자 홈), HTML 미리보기 안 됨, 프로젝트 dev 버전 | 미학·레이아웃 통제 약함 | 검증 없음 | v1 규모에 무거움 |

### 5-3. 결정 QA-4. 그림의 원본은 archify JSON, 보이는 것은 PNG, 검증은 야간

1. **의도**: REQ-24 "구조·흐름·결정은 archify 그림"을 지키되 이슈마다 그림 1장이 부담이 안 되게.
2. **비용**: 0원. 그림 1장 저술 10~20분(스킬이 함). 저장소 용량 PNG 장당 200~500KB.
3. **대안**: Mermaid만(REQ-24 위반, 단 PR 설명 안의 임시 스케치로는 허용) / archify HTML만 커밋(GitHub·Git Wiki에서 안 보임, 탈락) / D2(검증·에이전트 친화 부족, 탈락).
4. **왜**: JSON IR은 diff가 읽히고(`compare`로 아키텍처 델타 HTML까지), PNG는 어디서나 보이며, HTML은 발표·리뷰용. 세 파일을 같이 두면 REQ-21 Git Wiki 이관 때 PNG만 옮기면 된다.
5. **영향**: `docs/diagrams/{src/*.json, *.html, *.png}` 신설(현재 폴더 없음), `docs/diagrams/README.md`(명명: `NN-<주제>.<type>.json`, S0 Day 1 이슈), PR 템플릿 "그림" 항목, 야간 `diagrams` job(ubuntu: `npx -y skills add tt-a1i/archify --skill archify --agent claude-code --global --copy --yes` 후 `node ~/.claude/skills/archify/bin/archify.mjs validate <type> docs/diagrams/src/*.json --quality showcase --json`; CI 경로 **확인 필요**, 안 되면 `schemas/`만 MIT로 vendoring해 ajv 검증).
6. **검증**: `validate` 0 error/0 warning, PNG와 JSON의 갱신 커밋이 같은 PR(간단 스크립트로 mtime 비교).
7. **리스크·되돌리는 조건**: 프로젝트가 `dev` 채널이고 활발히 바뀜(2.17.0-dev.1) → 버전을 `skill-release.json`으로 고정 기록, 스키마 v2 이관이 강제되면 Mermaid로 임시 후퇴 가능(REQ-24 예외를 ADR로).

첫 그림 후보 4장: `01-module-graph.architecture`(ADR-0001), `02-translate-request.sequence`(14번 §5-1 8단계), `03-recording-pipeline.lifecycle`(14번 §5-2 상태 기계), `04-ci-gates.workflow`(이 문서 §1).

---

## 6. 릴리스 체크리스트 v2 (13번 §6 확장, REQ 반영)

앱 릴리스(`app/v*`) — 기존 9항목 유지 + 추가:

| # | 항목 | REQ | 증거 |
|---|---|---|---|
| A-10 | `Project.swift` deploymentTargets = iOS 17.0 / macOS 14.0, 모든 타깃 동일 | REQ-02 | `grep -c '"17.0"' Project.swift` |
| A-11 | 야간 매트릭스 최근 실행 초록: iOS 17.5 SE(단위·스냅샷·Maestro), iPad 11"·13", Mac 6K, reduceMotion 세트 | REQ-02·03 | `app-nightly` run 링크 |
| A-12 | macOS 14 VM(Tart/UTM) 스모크: 로그인→해석→복습 3흐름 수동 20분, 폴백 UI(사이드바 대체, 온디바이스 STT 미리보기 없음 안내) 확인 | REQ-02 | `docs/qa/releases/v1.0.md` 체크 |
| A-13 | `@available(iOS 26, *)` 분기마다 폴백 테스트가 있다(분기 목록 = 테스트 목록 diff 0) | REQ-02 | `scripts/available-audit.sh` |
| A-14 | SwiftLint 고정 px·Motion 규칙 `error`, disable 주석 목록 검토(각각 이유 있음) | REQ-03·22 | lint 로그 |
| A-15 | 프라이버시 카나리 테스트 4종 초록 + Sentry 실 debug view에서 최근 이벤트 10개 열어 원문·바디 없음 육안 확인 | REQ-14 | 스크린샷 |
| A-16 | Amplitude debug view 이벤트 15개 속성 키가 화이트리스트 밖 0개 | REQ-31 | 스크린샷 |
| A-17 | Sentry 한도 사용량 < 50%(5k/월), Amplitude MTU < 50%(10k) — 초과 시 샘플링 조정 | REQ-11 | 대시보드 |
| A-18 | AI 평가셋 **200문장 전체** 점수표가 baseline 이상, 결과 `eval/reports/`에 커밋 | REQ-10·12 | 리포트 링크 |
| A-19 | 비용 모델 `eval/cost_model.py` 입력값(모델 단가·평균 토큰)이 이번 릴리스 실측으로 갱신 | REQ-13 | PR 링크 |
| A-20 | 접근성 감사 `performAccessibilityAudit` iOS 26·iOS 17.5·macOS 통과 + Accessibility Inspector 수동(기존) | REQ-03 | 야간 run |
| A-21 | 이번 릴리스에 바뀐 구조·흐름의 archify 그림 갱신(JSON+PNG 같은 PR), `validate` 통과 | REQ-24 | `docs/diagrams/` diff |
| A-22 | 이 릴리스에서 새로 들어온 도구·SDK마다 ADR(의도→비용→대안→왜) 존재 | REQ-20 | `docs/adr/` 목록 |
| A-23 | 커밋 로그에 AI 공동 저자 표기 0건, gitleaks 초록 | REQ-27 | `git log --grep` |
| A-24 | 알림 payload 스키마가 `contracts/push-payload.json`과 일치(워치 확장 필드 예약) | REQ-04 | 계약 테스트 |

서버 릴리스(`server/v*`) — 기존 5항목 + 추가: S-6 프라이버시 카나리(로그·Sentry) 초록 / S-7 schemathesis `|| true` 제거 상태 / S-8 AI 라우터 circuit breaker 테스트·평가셋 통과 / S-9 trivy CRITICAL 0 / S-10 `X-Request-Id`로 앱 Sentry 이벤트 1건을 서버 로그와 실제로 연결해 본 기록.

---

## 7. 열린 질문 (확인 필요 목록, 우선순위순)

1. Swift Testing 번들이 iOS 17.5 시뮬레이터에서 실행되는가(안 되면 야간 B축 단위 테스트는 XCTest 한정).
2. hosted `macos-26`에서 `xcodebuild -downloadPlatform iOS -buildVersion 17.5` 소요 시간·성공률.
3. Gemini 무료 티어 정확한 RPD(모델별) — 야간 표본 크기 결정.
4. Sentry Developer·Amplitude Starter 공식 한도 페이지 원문(외부 요약 자료만 확인).
5. `XCUIApplication.performAccessibilityAudit` 최소 OS(Apple 문서 조회 실패 — 경로 확인 후 재조회).
6. Maestro macOS 데스크톱 지원 여부(공식 문서엔 없음).
7. Tart 무료 사용 범위(macOS 14 VM용).
8. SwiftLint `match_kinds` 유효 값에 `argument`/`number`가 포함되는지.
9. GitHub Free 플랜 macOS 동시 job 상한(5로 알려짐).
10. 14번 §5-1의 `_archify` 참조가 무엇인지.
