# ADR-0011: PR은 hosted `macos-26`(Xcode 26.4 핀), self-hosted 러너는 `push main`·`schedule`·`workflow_dispatch`에서만 — Supersedes ADR-0002 §러너

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-09-21). **Supersedes ADR-0002 §러너**("앱 job은 self-hosted 우선, `macos-15` 폴백"). ADR-0002의 "GitHub Actions, Jenkins 안 씀" 결정은 유지 |
| 관련 REQ | REQ-02·03(매트릭스), REQ-11(무료), REQ-27(공개 저장소·보안), REQ-30 |
| 관련 결정 | FD-9, FD-1(스냅샷 Tier), QA-1·§1-4·§1-5, iOS A-6, MI-6, RT-A-20, RT-B-05·20·21·22, U-15 |
| 출처 | `council/S0/QA.md` §0·§1, `council/S0/REDTEAM_B.md` §4, `.github/workflows/app.yml`(현재) |

## 1. 의도
공개 저장소에서 fork PR 코드가 개발 Mac(sops age 키·Keychain·시뮬레이터 런타임 보유)에서 실행되는 경로를 없애고, 스냅샷 기준 이미지가 로컬과 같은 Xcode에서 기록되게 하며, macOS 14(REQ-02 최소) 실행 검증이 hosted 이미지 폐기 뒤에도 가능하게 한다. PR 한 번에 15분을 넘기지 않는다.

## 2. 비용
- 돈: **0.** 저장소는 PUBLIC(`gh repo view`, REDTEAM_B 확인)이라 표준 hosted 러너는 무료("The use of standard GitHub-hosted runners is free: In public repositories" — QA F-3, 출처 URL·확인일 **확인 필요**). 비공개로 바꾸는 순간 macOS 분 ×10(월 ≈ 7,950분 → 79,500분 ≈ 무료 2,000분의 40배, 단가 확인 필요)이므로 공개 유지가 전제.
- 시간: `app.yml` 러너·Xcode 핀·매트릭스 v2 0.5일(S0 Day 2에 추가 — RT-B-22). self-hosted 등록(별도 macOS 사용자 계정, ephemeral) 0.5일. PR ≈ 10~15분, 야간 ≈ 45~60분(병렬 3 job이면 벽시계 25분).
- 동시성: Free 플랜 macOS 동시 job 5(확인 필요) → PR macOS job ≤ 4(lint·build-test·snapshot 3 매트릭스는 4개 안에서 배치 — 현재 QA 안 5개는 1개 줄인다).
- 유지보수: Xcode 핀을 올릴 때마다 스냅샷 재기록 PR. macOS 14 축은 self-hosted Mac 위 VM(Tart/UTM, Tart 무료 범위 **확인 필요**) 또는 릴리스 전 수동 스모크 20분.

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| ADR-0002 원안: 앱 job은 self-hosted 우선, `macos-15` 폴백(iOS A-6 "PR 기본 self-hosted") | (1) 과금 전제("hosted macOS 분당 10배")가 공개 저장소에는 틀림. (2) `pull_request`에서 self-hosted 배정을 막지 않아 외부 fork PR의 `tuist generate`·SwiftLint 플러그인·빌드 스크립트가 개발자 Mac에서 실행됨(RT-B-20 중요). (3) 현재 `app.yml`은 `macos-15` + `latest-stable`이라 macOS 26 실행 테스트가 불가하고 self-hosted 잡도 없음(RT-B-22) |
| hosted만(self-hosted 0) | macOS 14 실행 검증 불가: `macos-14` 이미지는 2026-07-06 폐기 시작·2026-11-02 완전 종료(QA F-2, 출처 **확인 필요**) = v1.0 나흘 전. iOS 17.0 런타임도 hosted `macos-26`에는 없어(QA F-1) 매 야간 다운로드 5~10분 |
| hosted `macos-15`로 macOS 14 대체 | 최소 OS가 아니라 의미 반감, 차기 폐기 후보 |
| macOS 14 실기 구매 / 실기기 팜(BrowserStack) | 비용, 무료 티어 없음(REQ-11) |
| Xcode `latest-stable` / QA 안 `26.5` 핀 | 스냅샷은 Xcode·OS 고정이 전제(12번 §11). 사용자 Mac은 **26.4(17E192)**(BRIEF) → 로컬 기록·CI 검증이 다른 Xcode면 첫 PR부터 diff(RT-A-20·RT-B-21) |
| **PR = hosted `macos-26` + Xcode 26.4 핀 / self-hosted = main·schedule·dispatch만 (채택)** | — |

## 4. 왜
버그의 종류가 축마다 다르다(QA-1). 로직 버그는 OS와 무관하니 한 축(iOS 26 iPhone 17 + macOS 26 호스트)에서 PR마다 잡고, `@available` 폴백·레이아웃 깨짐은 OS·화면 극단에서만 나오니 야간에 최소 OS(iOS 17.0 SE)와 극단 화면(iPad 13", Mac 6K)을 돈다. hosted `macos-26` 이미지가 있으므로(QA F-1: 2026-02-26 GA, OS 26.6.1, Xcode 26.0.1~26.6 — **출처·확인일 필요**, 26.4 포함 여부 확인) macOS 26 실행 테스트에 self-hosted가 필요하다는 현재 `app.yml` 주석은 틀렸다. self-hosted의 남은 용도는 두 가지뿐이다: macOS 14 실행 검증(VM)과 iOS 17.0 시뮬 스냅샷(런타임이 이미 설치되어 다운로드 0). 둘 다 야간이면 충분하다.

**러너 표**
| 러너 | Xcode | 트리거 | 용도 |
|---|---|---|---|
| hosted `macos-26` | **26.4** 핀(`maxim-lobanov/setup-xcode`) | `pull_request`, `push main` | lint, build-test(iOS 26 iPhone 17 + macOS 26 호스트), 스냅샷 Tier1, e2e-ios(머지만) |
| hosted `ubuntu-latest` | — | 전부 | 서버·계약·ai-eval(야간 40문장, 캐시 우선)·archify validate·on-failure-issue |
| self-hosted(개발 Mac, macOS 26, 별도 macOS 사용자 계정, ephemeral) | 26.4(로컬) | **`push main`·`schedule`·`workflow_dispatch`만**. `pull_request`·`pull_request_target` 절대 금지 | iOS 17.0 시뮬 스냅샷·단위(Tier2), macOS 14 VM 실행 검증, Domain watchOS 빌드(ADR-0010) |

**매트릭스**
| 층 | PR = Tier1 | 야간 = Tier2 | 릴리스 `app/v*` |
|---|---|---|---|
| 기기·OS | iPhone 17 iOS 26.4 + Mac 26 (+ iPhone SE 3세대 iOS 17.0은 deployment target 17 **컴파일 게이트**만 — PR은 hosted만이라 17.0 실행은 야간) | + iPad 11"/13" 세로·가로·Split 1/2, Mac 14(self-hosted VM), 6K, Dynamic Type AX3·AX5, reduceMotion, iPhone Pro Max 가로 | 전부 |
| 단위·계약 | A(iOS 26) + E(macOS 26) | B(iOS 17.0, `@available` 분기 실행) | A·B·E·F |
| 스냅샷 | A(DT L·AX3) + D(iPad 13" 접힘·펼침) + E(창 1000×700·1440) | B·C·6K·reduceMotion | 전부 |
| E2E | — (머지 시 Maestro 2흐름: 로그인→해석, 녹음→결과 — FD-8 4→2) | A + B | A + B |
| 접근성 | — | `performAccessibilityAudit`(iOS 17.0+/macOS 14.0+, Xcode 16.3+ 확인) A + E | A·B·E |
| AI 회귀 | 캐시 히트만(외부 호출 0) | 40문장 회전 | 200문장 전체 |

> Tier1 정정: FD-1은 "Tier1(PR) = iPhone SE 3세대 iOS 17.0"을 포함하지만 iOS 17.0 런타임은 hosted에 없으므로 PR에서는 deployment target 17로의 **컴파일**이 게이트이고 SE 17.0 **실행**은 야간(self-hosted)이다. 스냅샷 기준 이미지는 `SNAPSHOT_RECORD=1` 잡(hosted, Xcode 26.4)에서만 생성한다. OS별 폴더 `__Snapshots__/{os}{major}/`, 파일명에 OS·기기·DT·motion 포함.

## 5. 영향 파일·문서
- `.github/workflows/app.yml`: `runs-on: macos-26`, `XCODE_VERSION: "26.4"`, `IOS_SIM_LATEST: "iPhone 17,OS=26.4"`, macOS 14 컴파일 게이트(`-scheme MwonmalMac build`), 단위 7타깃 `-only-testing`, 스냅샷 매트릭스 3, e2e-ios `if: push`, `concurrency` 유지, Homebrew·Tuist·DerivedData 캐시. 주석 "hosted macos-15는 …" 삭제.
- `.github/workflows/app-nightly.yml`(신규): `schedule 0 17 * * *`(02:00 KST) + `workflow_dispatch`, jobs `ios17-min`(self-hosted), `mac14-vm`(self-hosted), `mac-a11y-xcui`(hosted), `domain-watchos`(hosted), `ai-eval`(ubuntu), `diagrams-validate`(ubuntu), `on-failure-issue`.
- `.github/workflows/server.yml`: `schemathesis … || true` 제거를 Day 4 완료 기준에(QA S-7).
- 릴리스 워크플로: 두 파일을 `workflow_call` + macOS 14 VM 스모크 수동 체크리스트(QA A-12).
- `docs/adr/0002-github-actions-not-jenkins.md`: "러너 전략은 ADR-0011로 대체" 한 줄.
- 13번 §4·§5-1 러너·매트릭스 표 교체, 16번 §1 CI 행("self-hosted 우선" → 이 표), 12번 §11·§15 CI job. `docs/qa/matrix.md` 신설.
- 이슈 추가 `[S0][infra] app.yml 러너·Xcode 핀·매트릭스 v2`(0.5일, Day 2).

## 6. 검증
- PR 워크플로 p50 ≤ 15분(Actions 통계 주 1회 기록). 첫 실측 후 §2 추정 갱신.
- 보안: `.github/workflows/*.yml`에서 `runs-on: [self-hosted` 가 있는 job은 전부 `if: github.event_name != 'pull_request'`이거나 `pull_request` 트리거가 없는 워크플로에만 존재 — grep 테스트(contracts CI에 추가). `pull_request_target` 0건.
- 스냅샷: 로컬(Xcode 26.4)에서 기록한 이미지와 CI가 diff 0 — 첫 PR에서 확인.
- 야간 실패 시 자동 이슈(`on-failure-issue`). 야간이 3일 연속 빨간 채 방치되면 원인 항목을 PR로 승격.
- 동시성: PR 하나가 macOS job ≤ 4 — 워크플로 정적 검사.

## 7. 리스크와 되돌리는 조건
- 리스크: hosted `macos-26` 이미지에 Xcode 26.4가 없으면(이미지 갱신으로 제거될 수 있음) → 러너 이미지에 있는 가장 가까운 26.x로 핀을 올리고 스냅샷 재기록 PR을 같이. 개발 Mac이 꺼져 있으면 야간 self-hosted 잡 대기 → 야간이므로 다음 날 재실행, 릴리스 주에는 켜 둔다. Tart가 개인 무료 범위 밖이면 UTM 또는 릴리스 전 수동 스모크.
- 되돌리는 조건: 저장소를 비공개로 전환하면(가능성 낮음) hosted macOS 분이 과금되므로 PR도 self-hosted로 옮기되 `pull_request`는 협력자 PR만 남기고 fork PR을 막는 설정과 함께 ADR 재작성. 팀이 생겨 조직 표준이 있으면 ADR-0002 되돌림 조건과 동일.
