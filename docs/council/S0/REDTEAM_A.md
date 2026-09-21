# 레드팀 A — 기술 타당성·아키텍처 검증 (협의체 1차, 2026-09-19)

> 검토 대상: BRIEF(사용자 답변 포함), PM, PO, AI, iOS, macOS_iPad, Backend, QA 결정서 전부. 대조 원본: `docs/REQUIREMENTS.md`, `docs/design/12_앱_아키텍처_설계.md`, `contracts/openapi.yml`(v1.0), `contracts/db.dbml`, `apps/ios-macos/Project.swift`, 15번 T-C2, 14번 §15·§16.
> Apple API 사실은 `mcp__sosumi__fetchAppleDocumentation`으로 2026-09-19에 직접 재확인했다(§B 표). 저장소 파일은 수정하지 않았다.
> 등급 기준은 PM §5 표를 그대로 썼다: **치명** = REQ 위반 / 계약 v1.0 변경 / 원문 유출 경로 / 유료 결제 / 잔여 시간 초과. **중요** = 대안·검증·되돌림 결함, 파트 간 모순으로 착수 불가. **경미** = 절 번호·표기·견적 단위.

## 요약

| 등급 | 건수 | ID |
|---|---|---|
| 치명 | 3 | RT-A-01, RT-A-02, RT-A-03 |
| 중요 | 13 | RT-A-04 ~ RT-A-16 |
| 경미 | 8 | RT-A-17 ~ RT-A-24 |

**착수 가능 여부: 조건부 불가.** S0 Day 2~5(Tuist 타깃·서버 뼈대·Redis 키 규약)는 어느 치명 항목과도 무관하므로 그대로 착수해도 된다. 그러나 **Day 11(AI 라우터)·Day 14(온디바이스 엔진)·Day 18(알림 payload)은 치명 3건과 중요 RT-A-04~08이 같은 세션에서 해소되기 전에는 착수하면 안 된다.** 세 치명 건은 모두 "세 파트가 같은 문제에 서로 다른 답을 적어 놓고 각자 자기 답으로 일정을 잡은" 유형이라, 코드가 아니라 결정 하나로 닫힌다.

---

## A. 발견 목록

### 치명

**RT-A-01 | 치명 | AI-4 · PO-3 · Backend B-1 · PM Day 11 | 무료 Gemini 티어에 실사용자 원문을 보내는지가 세 파트에서 세 가지 상태이고, Backend 기본 사슬은 이미 "보낸다"로 구현된다**
- 문제: AI-4는 약관 원문("Do not submit sensitive, confidential, or personal information to the Unpaid Services", 인간 검토 가능, 학습 사용 Yes)을 인용하며 **PO 결정 전에는 합성 데이터만**이라고 못 박았다. PO-3 규칙표 마지막 행은 "무료 티어 데이터 사용 정책 **확인 필요**… 실사용자 원문은 TestFlight 베타부터, 베타 시작 전 정책 확인이 게이트"라고 써서 AI가 이미 확인한 사실을 미확인으로 되돌렸고 게이트를 S5로 미뤘다. Backend B-1 §5-4 폴백 사슬은 `DETECT_PLAIN: gemini_free(cheap) → …`가 prod 기본이며 `AI_REAL_USER_TEXT` 같은 게이트가 없다. PM Day 11은 "Gemini Flash 무료 + Groq 폴백만"으로 확정했다. 즉 S2에 만들어질 라우터는 사용자 원문(회의 기밀)을 무료 티어로 보내는 코드가 되고, 그 사실을 결정한 사람은 없다.
- 근거: AI.md §1-①(약관 인용, 2026-09-19 확인), AI-4 §4 대안 (a)(b)(c); PO.md §3-1 "프라이버시" 행; Backend.md B-1 §5-4·§5-3 `gemini_free` 행; PM.md §2 Day 11. REQ-14의 문면은 "원문은 SDK로 안 나감"이지만 12번 §12 위협 모델과 REQ-14의 "왜"(기밀)가 이 경로를 포괄하며, PM §5 치명 기준 "원문 유출 경로"에 해당. Groq 약관은 아무도 확인하지 않았다(AI.md "확인 필요").
- 권고: (1) S1 킥오프(10/2) 전에 PO가 AI-4 (a)/(b)/(c) 중 하나를 REQ-11 각주로 확정. (2) 어느 쪽이든 Backend 사슬에 `AI_REAL_USER_TEXT`(기본 false) 플래그를 넣고, false면 사용자 요청은 `none`(사전만) 또는 503 — 즉 dev·CI·평가는 합성 데이터만 무료 티어로. (3) 12번 §12 위협 모델 표에 AI-8의 "AI 엔진" 열을 실제로 추가하고 Groq(LLM·Whisper 둘 다) 약관 확인을 Day 11 착수 조건으로.

**RT-A-02 | 치명 | AI-2 · iOS-A1(A-4 #2) · PM-2/PM-3 · Backend B-1 | 온디바이스 Foundation Models가 v1.0 사용자 경로에 있는지가 세 파트에서 다르고, AI-2가 정의한 "오프라인 임시 해석"은 REQ-14(검수 사전 우선)를 어긴다**
- 문제: AI-2 §4-1 앱 결정 트리는 v1.0에서 appleFM을 (a) 결과 도착 전 "쉬운 말 미리보기", (b) 서버 503·오프라인 시 "임시 해석(저장 안 됨)"으로 **사용자에게 보여 준다**. iOS-A1 A-4 #2는 "v1.0은 전 OS 서버, 온디바이스 해석은 v1.1"이라고 적었고, PM-2/PM-3은 "온디바이스·MLX·sLLM은 측정까지, v1.0 미포함"이다. Backend `on_device` 어댑터는 v1.1 `engineHint` 전제다. 세 결정이 양립하지 않는데 AI §7 8번(S2 Day 14 확장)에 2~3일 견적으로 앱 `AppleFMTranslationEngine` 구현이 잡혀 있고 PM 일정에는 없다.
  REQ 위반: 오프라인 온디바이스 결과에는 서버의 사전 덮어쓰기·인덱스 재계산(REQ-14)이 없다. 앱은 사전 전체를 갖지 않는다(12번 D-10 "캐시는 /levels 하나", 계약에 사전 전체 조회 op 없음). 따라서 (b) 경로는 "검수된 사전이 AI보다 우선"을 만족할 수 없다. (a) 미리보기도 D-7과 같은 논리로 서버 결과와 다른 문장을 먼저 보여 준 뒤 바꾸는 UX이며, 계약 v1.0으로는 그 결과를 서버에 보낼 수도 없다(AI-2 자신이 인정).
- 근거: AI.md §4-1 "v1.0 동작"; iOS.md A-4 #2 폴백 열; PM.md PM-2 §4·PM-3 §4; 12번 D-10·§2-1 op 목록; REQ-14.
- 권고: v1.0 = 온디바이스 **사용자 경로 없음**(iOS·PM 입장 채택). Foundation Models는 `eval/` 어댑터(macOS 26 개발 Mac, 사용자 답변으로 실측 가능)로만 점수표에 오른다 — REQ-10 "전부 비교"는 이것으로 충족. 온디바이스 사용자 경로는 v1.1 `clientHints/engineHint` + 사전 스냅샷 다운로드 op와 함께 한 번에. AI §7 8번을 S2에서 제거하고 PM 수지에서 −2일.

**RT-A-03 | 치명 | macOS_iPad MN-1 · Backend B-3 · PO §5-2 · PM S3-A · QA A-24 | `contracts/push-payload.json` 하나에 대해 스키마 3개가 제출됐고 서로 호환되지 않는다**
- 문제: MN-1은 `aps` + **중첩 `mw` 딕셔너리**(`v, type, deepLink(필수·유일한 행동 계약), notificationId, sentAt, review/action/decode/levelUp 섹션`). Backend B-3 §5-2는 **평면 커스텀 키**(`v, type, notificationId, projectId, meetingId, translationId, actionId, quizId, dueCount`), `deepLink` 없음, 대안 표에서 "`mw` 객체"를 명시적으로 탈락시킴. PO §5-2는 평면 `{type, translationId?, meetingId?, projectId?, quizId?, badge, dueCount?}` + 카테고리 `review.reminder`(다른 둘은 `REVIEW_REMINDER`). PM S3-A는 "`deepLink` 문자열, 텍스트 필드 없음". 앱 `DeepLink.parse(userInfo:)`(Day 24)와 서버 빌더(Day 18)와 QA 릴리스 체크 A-24가 같은 파일을 읽어야 하는데 파일이 셋이다. 이대로면 Day 18과 Day 24가 각자 다른 스키마를 구현한다.
  부수 충돌: Backend ACTION_DUE 예시는 `body`에 `action_text`(AI가 원문에서 추출한 할 일 문장)를 넣는다. MN-1 불변식은 "`aps.alert`에는 용어명·개수·회의 제목까지만", PO는 "텍스트 없음". Backend는 Q3으로 PO에 넘겼지만 예시 JSON은 이미 넣은 상태다. `interruption-level`도 Backend는 `time-sensitive`(엔타이틀먼트 필요), MN-1은 `active`로 시작.
- 근거: macOS_iPad.md MN-1 §4 JSON·yml; Backend.md B-3 §3 대안표·§5-2·§5-3; PO.md §5-2; PM.md S3-A; QA.md §6 A-24. REQ-04.
- 권고: 한 세션에서 하나로 확정. 기술적으로는 **MN-1(`mw` + `deepLink`)**이 옳다 — 워치가 ID 조합 규칙 4종을 알 필요가 없고 `v`로 버전 관리가 되며, Apple 문서(WKApplication.registerForRemoteNotifications, 확인)의 "payload 동일 → 중복 제거" 조건을 플랫폼 무관하게 만족한다. Backend 반론("앱 §13이 평면으로 합의")은 12번 §13이 v1.1 백로그 문구일 뿐 계약이 아니므로 성립하지 않는다. `alert.body`의 `action_text`는 REQ-14 확장 해석에 따라 금지하고 "할 일 1건 마감 30분 전"으로. `time-sensitive`는 v1.1.

### 중요

**RT-A-04 | 중요 | AI-3 · Backend B-1/B-2 · PO-4 · PM Day 3 | `aiModel` 한 필드에 규약 3개, 그리고 PO의 측정식은 계약상 불가능한 `IS NULL`을 전제한다**
- 문제: AI-3 `{track}/{model}@{ver}#{promptVer}` + 앱 `EngineTag.parse`. Backend `"{engine}:{model}"`, `none:dictionary`, 그리고 Day 3 지시 "`aiModel` 문자열을 파싱하지 **말 것**". PO-4 `dictionary_only_rate = translations.ai_model IS NULL 비율` — dbml 304행 `ai_model varchar(50) not null`이라 NULL이 생길 수 없다. REQ-13 측정 입력이 첫 줄부터 틀린다.
- 근거: AI.md AI-3 §4·§6; Backend.md B-1 §5-2 `TranslationResult.model` 주석, B-6 Day 3; PO.md §4-1 표; `contracts/db.dbml` L304.
- 권고: Backend 규약(`engine:model`) 채택 + `dict:only` 대신 `none:dictionary` 하나로. 서버 정규식 테스트 1개. 앱은 v1.0에서 파싱하지 않는다(Backend Day 3 지시가 맞다). PO `dictionary_only_rate`는 `ai_model = 'none:dictionary'` 또는 `ai_usage.engine = NONE` 비율로 정정.

**RT-A-05 | 중요 | AI-2 §4-1 · Backend B-1 §5-4 · PO-1 §1-3 | 라우터 "작업" 단위가 AI(4작업)·Backend(4작업이지만 NUANCE+ACTIONS 병합, 요청당 최대 2호출)·AI 기본값("한 호출에 4출력")·PO 원가식(detect+nuance = 2호출)에서 전부 다르다**
- 문제: 호출 수가 다르면 무료 RPD 소진 시점(RT-A-01·PO-3 예산 50%), `ai_usage` 행 수, REQ-13 원가가 전부 달라진다. AI는 "점수표에서 분할이 +5점 이상이면 분할"이라 했지만 Backend 폴백 사슬은 이미 2사슬 고정이고, `EngineTask` Literal에 `NUANCE_ACTIONS`가 박혀 있다. `dueAt`은 AI "규칙 코드", Backend는 언급 없음.
- 근거: AI.md §4-1 결정 트리·"v0 기본은 한 호출"; Backend.md B-1 §5-2 `EngineTask`·§5-4 흐름; PO.md §1-3 `calls_per_user`.
- 권고: Day 11 전에 `EngineTask`를 하나로 확정(권고: Backend 2사슬. 이유: NUANCE 사슬을 건너뛰어 "계약상 합법인 강등"(nuance=null)이 가능해 예산 게이트가 단순). PO `calls_per_user`를 2호출 기준으로 고정하고 AI 점수표의 "분할 호출" 열은 실험 열로만.

**RT-A-06 | 중요 | AI-1 · QA-2 · PO-1 · 14번 §16 | 평가셋 파일·스키마·위치가 네 벌이고, QA 데이터 형식은 계약 enum에 없는 값을 쓴다**
- 문제: 경로 — 14번 §16 루트 `eval/`, PO `services/eval/`, Backend `eval/prices.yml`, QA `eval/dataset.jsonl`, AI `eval/data/pangyo200.v1.jsonl`. 스키마 — AI는 `TranslationResponse` 부분집합(`direction: JARGON_TO_PLAIN`, `detectedTerms[]{startIndex,endIndex}`, `acceptable`), QA는 `{"direction":"TO_PLAIN", "expected":{"terms":["align"], "resultTextKeywords":[…]}}` — `TO_PLAIN`은 yml `TranslationDirection` enum(`JARGON_TO_PLAIN | PLAIN_TO_JARGON`)에 없고 `terms`가 영문 키라 AI의 스팬 F1 채점이 불가능하다. 채점 함수도 AI(`score.py`, 가중 종합 0~100)와 QA(`run.py --fail-on-regression`, baseline −3pt)가 별개.
- 근거: AI.md §2-2 JSON; QA.md §2-1 JSON 한 줄; PO.md §1-1 트리·§6 3번; Backend.md B-2 §5-3; 14번 §16 L333; `openapi.yml` L1792.
- 권고: 위치는 루트 `eval/`(14번 §16 원안, 서버 venv를 쓰려면 `uv --project services/api`로 충분). 스키마는 AI §2-2 하나. QA-2의 회귀 게이트는 AI `score.py` 출력 위에 얹는 얇은 스크립트로. 소유자 AI 파트.

**RT-A-07 | 중요 | PO-1 · Backend B-2 · PM S2-G | REQ-13 계산기가 두 파트에서 각각 설계됐고 입력 스키마가 다르다**
- 문제: PO `cost_model.py`(표준 라이브러리만, 자체 YAML 부분집합 로더 60줄, `usage.yml` 1인당 프로파일 + `pricing.yml`), Backend `eval/cost_model.py`(`usage_daily.csv` + `eval/prices.yml`, `--on-device-ratio`). 파일 이름까지 겹친다(`pricing.yml` vs `prices.yml`). PM S2-G는 `eval/prices.yml` + pytest 3케이스로 0.5일. PO의 자체 YAML 파서는 REQ-23(바퀴 재발명 금지)과 어긋난다 — `services/api`에 이미 PyYAML/pydantic이 있다.
- 근거: PO.md §1-1~1-5; Backend.md B-2 §5-3; PM.md S2-G; REQ-23.
- 권고: 계산 로직은 PO 초안(손익분기 역산·`over_limit` 3정책이 더 완성됨), 입력은 Backend의 `usage_daily`(DB가 진실 — PO-4 원칙과도 일치). 단가 파일 이름 하나(`eval/prices.yml`), 로더는 PyYAML.

**RT-A-08 | 중요 | iOS-C1 6-8 · PM S1-B · macOS_iPad MI-1 | "넓은 화면" 판정 환경값이 이름 3개·식 3개이고, 두 식이 같은 기기에서 반대 결과를 낸다**
- 문제: iOS `mwLayoutClass = macOS→.regular; iOS→ h == .regular && width ≥ 700`. PM `mwIsWide = h == .regular || os(macOS)`. MI-1 `mwLayout = h == .regular && v == .regular`(폭 없음). 사례 — iPad 13" 가로 1/2 Split(MI-6 표 678pt, h·v 둘 다 regular): MI-1 = wide, iOS-C1 = compact(678 < 700). iPhone Pro Max 가로(h regular, v compact): PM = wide(사이드바 출현, MI-1이 막으려던 바로 그 사고), MI-1 = compact. 세 파트가 각자 자기 값으로 D-2 분기·스냅샷 기대값을 잡았다.
  사실 보정: Apple 문서(확인) — `horizontalSizeClass`는 macOS 10.15+에서 존재하며 "macOS·tvOS에서는 항상 `.regular`". iOS.md 대안 ①의 "Mac에는 sizeClass가 없어(항상 nil/regular)"는 부정확(nil 아님). 따라서 MI-1 식은 `#if os(macOS)` 없이 그대로 Mac에서 wide가 되어 가장 단순하다.
- 근거: iOS.md C-1 6-8; PM.md S1-B; macOS_iPad.md MI-1 §4·MI-4 표; sosumi `swiftui/environmentvalues/horizontalsizeclass`.
- 권고: MI-1 식·이름(`mwLayout`) 채택, 폭 임계값은 넣지 않는다(REQ-23·HIG "앱은 멀티태스킹 구성을 알 수 없다"). iOS-C1 규칙 6-8을 MI-1로 교체하고 히스테리시스 조항 삭제.

**RT-A-09 | 중요 | iOS-A1 A-2/A-4 #3 · PM S1-A · macOS_iPad MI-2 · 12번 §9 | 루트 구현 개수(2 vs 3)와 위치(MwonmalUI vs Composition)가 다르고, iOS안의 위치는 모듈 그래프를 위반한다**
- 문제: iOS·PM = `#available(iOS 18)`이면 `TabView.sidebarAdaptable`, 아니면 compact `TabView` / wide `NavigationSplitView` → **코드 경로 3개**, 위치 `MwonmalUI/Layout/AdaptiveRoot`. MI-2 = `sidebarAdaptable` 완전 배제, 경로 2개, 위치 `Composition/CompactRoot·WideRoot`. `sidebarAdaptable`은 iPadOS에서 "상단 탭바가 사이드바로 접히는" 모양(문서 확인)이라 REQ-01 "iPad = 사이드바·세 열"에 맞지 않는다 — MI-2가 옳고, 3경로는 스냅샷 매트릭스만 키운다. 위치 — 루트는 `TabCoordinator`·`Tab`·`AppRoute`(Navigation)를 바인딩해야 하는데 `MwonmalUI`는 SwiftUI만 import한다(12번 D-21, `Project.swift` MwonmalUI `dependencies: []`). 12번 §9 트리의 "`Layout/AdaptiveRoot(TabView sidebarAdaptable 래퍼)`"는 제네릭 래퍼가 아닌 한 컴파일되지 않는다. iOS A-2 게이트 표가 `MwonmalUI/Layout/AdaptiveRoot`를 `#available` 허용 위치로 지정한 것도 같은 문제.
- 근거: iOS.md A-2 표·A-4 #3; PM.md S1-A; macOS_iPad.md MI-2 §3(a)·§5; 12번 §9·D-21; `Project.swift` L42~50; sosumi `swiftui/tabviewstyle/sidebaradaptable`.
- 권고: MI-2 채택(경로 2, Composition). 12번 §9 `Layout/`에는 `ListDetail`(2·3열, Domain 모름)만 남긴다. iOS A-2 게이트 허용 위치에서 `MwonmalUI/Layout/AdaptiveRoot` 삭제. PM S1-A 견적은 "루트 2벌"로 재산정(3경로보다 작아진다).

**RT-A-10 | 중요 | macOS_iPad MI-2 §4 · PM Day 24 · 12번 §8 | `@SceneStorage`에 `NavigationSplitViewVisibility`를 넣는 코드는 컴파일되지 않고, PM은 `@SceneStorage` 복원 자체를 v1.1로 뺐다**
- 문제: MI-2 "`@SceneStorage("mw.sidebar") var sidebar: NavigationSplitViewVisibility = .all`". Apple 문서(확인): `NavigationSplitViewVisibility`는 `Decodable, Encodable, Equatable, Sendable`만 채택, `RawRepresentable` 아님. `SceneStorage` 초기화자는 Bool/Int/Double/String/URL/Data 또는 `RawRepresentable`(RawValue Int/String)만 받는다 → 타입 오류. 동시에 PM Day 24는 "`@SceneStorage` 복원 → v1.1"로 감축했는데 MI-2는 이를 compact↔wide 전환 시 사이드바 상태 보존의 근거로 쓴다. 12번 §8 "상태 복원: `AppRoute: Codable` → `@SceneStorage`에 `paths`·`selectedTab` 저장"도 `[Tab: [AppRoute]]`는 RawRepresentable이 아니라 JSON `Data`/`String`으로 직렬화하는 래퍼가 필요하다(누구도 적지 않음).
- 근거: macOS_iPad.md MI-2 §4 "열 가시성"; PM.md §2 Day 24; 12번 §8; sosumi `swiftui/navigationsplitviewvisibility`, `swiftui/scenestorage/init(wrappedvalue:_:)`.
- 권고: v1.0은 사이드바 가시성을 `TabCoordinator`의 `@State`(창 수명)로만 보존 — compact↔wide 전환에는 이것으로 충분(뷰 트리 교체 위에 코디네이터가 있음). 씬 재시작 복원은 PM대로 v1.1, 그때 `String`(JSON) 래퍼로.

**RT-A-11 | 중요 | PM §1~§3 vs iOS·macOS_iPad·AI·QA | PM 재산정이 각 파트가 실제로 요구한 작업량을 반영하지 않았고, PM이 v1.1로 뺀 것을 다른 파트가 v1.0으로 다시 넣었다**
- 문제(구체 대조):
  - Vision OCR: PM Day 14 "→ v1.1". MI-3(드롭→OCR), MI-4(iPad 카메라 촬영 OCR +1.0일, `NSCameraUsageDescription`)는 v1.0.
  - SpeechAnalyzer 미리보기: PM Day 19 "→ v1.1, 스텁만". iOS-A1 A-4 #1은 `SpeechAnalyzerTranscriber`(26) + `SFSpeechTranscriber`(17, 55초 재생성) **두 구현** 3~4일. MI-5는 "SFSpeech 폴백 v1 안 함, 구현체 1개 + nil". 세 가지.
  - 라이브 액티비티: PM "→ v1.1". iOS A-3 `NSSupportsLiveActivities` 추가, MI-4 iPad 표시 확인 요청.
  - macOS 로컬 알림(D-19): PM Day 28 "→ v1.1". MI-6 A-02/A-05 행 "Mac: 로컬 알림(D-19)" 유지.
  - Motion: PM S2-A 0.5일 + Catalog v1.1. iOS-B1 1.5 + 1.0(MotionLab) + 0.5 = 3.0일, MotionLab v1.0.
  - AI: PM S2 타임박스 1.5일. AI §7은 평가셋 2일+채점 1일+앱 엔진 2~3일+FM 어댑터 2~3일.
  - QA: `app-nightly.yml`·SwiftLint 7규칙·카나리 테스트 4종·`scripts/available-audit.sh`·`coverage-gate.sh` — PM 어디에도 없음(S0 Day 5 "규칙 추가"만).
  PM 수지 "잔여 −3.0일 → 버퍼 0"은 위를 넣으면 −10일 이상이다.
- 근거: PM.md §1·§2·§3-2; iOS.md A-1 §2·A-4 #1·B-1 §2; macOS_iPad.md MI-3·MI-4·MI-6; AI.md §3 구현 난이도 행·§7; QA.md §1-5·§3-3·§6.
- 권고: PM이 각 파트의 "v1.0 산출물" 목록을 표로 받아 재산정. 감축 권고(레드팀 의견): SFSpeech 폴백·카메라 OCR·MotionLab·앱 FM 엔진은 v1.1; 미리보기는 26 전용 `SpeechAnalyzer` 스텁 대신 **구현체 0 + "받아쓰기 준비 중"**(MI-5안) — 그러면 `NSSpeechRecognitionUsageDescription`도 v1.0에 불필요.

**RT-A-12 | 중요 | AI-2 · Backend B-1 §5-3 · PO-3 · PM Day 11 | REQ-11 "사용자 제공 키"의 해석이 셋이고, Backend prod 사슬은 운영자 유료 키를 1순위로 둔다**
- 문제: AI = 최종 사용자 BYOK(라우터 `byok(claude|openai, 키 있을 때만)` NUANCE 1순위, 키는 "사용자별 암호화 저장, v1.1 계약"). Backend = 운영자 `.env` 키(`anthropic_key`가 NUANCE_ACTIONS·MEETING_SUMMARY **1순위**, `.env.example`에 `ANTHROPIC_API_KEY`, Q1로 PO에 질문). PO-3 = "서버 라우터는 사용자 키를 받지 않는다… 키 소유자=나=결제 발생=REQ-11 위반, 평가 트랙 전용". 키가 없으면 `UNCONFIGURED`로 빠지므로 당장 결제는 없지만, 설계 문서·env 예시·사슬 순서가 전부 "키를 넣으면 유료 1순위"로 되어 있어 실수 한 번이 REQ-11 위반이다(PM 치명 기준 "유료 결제 발생"의 경로).
- 근거: AI.md §4-1·§4-2·AI-8 표 "① BYOK" 행; Backend.md B-1 §5-3 `openai_key`/`anthropic_key` 행·B-6 Day 4 ③; PO.md §3-1 "키 종류"·"사용자 제공 키" 행·§3 7항.
- 권고: PO-3 해석 채택. prod 사슬에서 `anthropic_key`/`openai_key` 제거(`APP_ENV=prod`에서 존재 시 기동 실패 assert — PO-3 규칙 재사용). `eval/`에서만 CLI 인자로. 최종 사용자 BYOK는 v1.2 이후 검토. AI-2 §4-2 표의 1순위 열을 Gemini Flash로 고쳐 쓴다.

**RT-A-13 | 중요 | Backend B-4 · AI-8 · PO §6-2 | 회의 오디오를 Groq Whisper(외부)로 보내는 결정에 데이터 흐름 행·약관 확인·REQ-20 기록이 없다**
- 문제: Backend B-4는 STT 1순위 `groq_whisper`(무료 8h/일), 2순위 Gemini 오디오, 3순위 자체 whisper. AI-8 데이터 흐름 표는 "오디오는 어떤 엔진에도 안 감(오디오는 STT만)"이라 쓰고 STT 행이 없다. PO는 STT가 원가 65%라 제공자 미정을 레드팀 질문으로 넘겼다. 회의 원음성은 텍스트보다 민감한 자산인데(12번 §12 표 "오디오 조각" 행) 제공자 약관·보존 정책을 아무도 확인하지 않았다. Backend B-4 표의 무료 한도 수치는 전부 "확인 필요".
- 근거: Backend.md B-4 §2 표·§5; AI.md AI-8 표 마지막 문단; PO.md §6 2번; 12번 §12.
- 권고: AI-8 표에 `STT: groq_whisper / gemini_audio / whisper_local` 3행 추가(원문이 가는 곳·저장·학습·검증). dev 기본은 이미 `whisper_local`이므로 prod 사슬 순서는 약관 확인 뒤 Day 17에 확정. OCI A1(4코어/24GB)에서 `faster-whisper` 실시간 여부를 S2에 실측해 "원음성 외부 전송 0" 옵션이 살아 있는지 먼저 본다.

**RT-A-14 | 중요 | AI-5 · AI-6 · MN-3 · MN-4 · QA §2-2/§2-3/§4 | REQ-20 7항목 형식이 빠진 결정들 — PM §5 규칙상 "무효"**
- 문제: AI-5(FM 게이트 3겹·MESSAGE 500자 한정), AI-6(MLX 실험 플래그)는 §0 표 한 줄뿐. MN-3(워치 최소 계약), MN-4(할 것/하지 말 것 6개)는 표·목록. QA §2-2(스키마 검증), §2-3(카나리 — "요약"으로 압축, 영향 파일·검증 번호 없음), §4(도구 ADR 초안 — 의도/비용/대안/왜 4항목만, 영향·검증·되돌림 없음). REQ-20은 "최우선"이고 PM §5는 "형식이 빠진 결정은 무효"로 못 박았다.
- 근거: REQ-20; PM.md §5 산출물; 각 문서 해당 절.
- 권고: 해당 역할이 같은 세션에서 7항목으로 보완. QA §4는 ADR 0005~0013로 옮길 때 채운다고 했으니 "결정"이 아니라 "ADR 초안 재료"로 표기 변경.

**RT-A-15 | 중요 | QA-2 · PO-3 · AI §2-1 | 무료 티어 호출 예산을 세 파트가 각자 잡아 합계가 한도를 넘는다 / CI 외부 호출 정책이 모순**
- 문제: PO-3 "단위·계약 테스트는 항상 Fake, **CI에서 외부 AI 호출 0**", 개발 예산 = RPD 50%. QA-2 "프롬프트 변경 PR마다 20문장 + 야간 40문장(CI, `secrets.GEMINI_API_KEY`)". AI: dev 50 + test 150 × 트랙 수, judge도 Gemini. AI가 인용한 3차 자료 중 하나는 Flash **20 RPD**. 20 RPD면 야간 40문장 하나로 하루 한도를 넘고, 데모·개발 호출은 0이 된다. QA는 "최악 20 RPD로 설계"라 하면서 40을 기본으로 뒀다.
- 근거: PO.md §3-1 "테스트"·"개발 중 호출 예산"; QA.md §1-2 마지막 행·§2-1 §2; AI.md §1-① RPM/RPD 행·§7 1번.
- 권고: AI §7 1번(AI Studio 실제 한도 캡처, 9/22~23)을 **S0 게이트**로 올리고, 그 수치 하나로 PO 예산·QA 표본·AI 평가 회전을 한 표(`eval/limits.md`)에서 배분. CI 호출은 `schedule`에서만, PR에서는 캐시 히트만 허용(PO-3 원칙 유지).

**RT-A-16 | 중요 | Backend B-6 Day 4 ② | v1.0 마이그레이션에 `MACOS`, `WATCHOS`를 미리 넣는 안은 계약 v1.0(dbml) 변경이다**
- 문제: dbml 41~44행 `device_platform { IOS, WEB }`. Backend는 `dbml2sql diff 0` 검사를 유지한다면서 초기 마이그레이션에 두 값을 "미리 포함"하는 안을 냈다 — diff가 0이 될 수 없고, BRIEF "계약 v1.0은 제출본, v1.1 백로그로만"에 반한다.
- 근거: Backend.md B-6 Day 4 ②; `contracts/db.dbml` L41~44; BRIEF 고정 제약.
- 권고: 넣지 않는다. MySQL 8 `ALTER TABLE … MODIFY ENUM`(끝에 값 추가)은 v1.1 expand 단계에서 실행(Q9는 v1.1 시점에 확인).

### 경미

**RT-A-17 | 경미 | Backend B-4 §5 | 사용자 일 한도 429 `TOO_MANY_REQUESTS`는 계약 v1.0 `Error.code` 목록에 없다**
- `openapi.yml` L1649~1665: 429는 `GUEST_QUOTA_EXCEEDED`뿐. 앱 D-8은 429 처리 자체가 없고 D-14 매핑은 `.unknown`. Backend도 "목록에 없음 → v1.1 문안"이라 썼으나 서버 구현은 Day 11·17에 잡혀 있다. 권고: v1.0 서버는 30/분 레이트리밋만, 일 한도는 v1.1 코드와 함께.

**RT-A-18 | 경미 | PM Day 29 · PO-4 · QA A-16 | Amplitude 이벤트 수가 6(PM) / 15(QA 체크리스트) / PO 의존 이벤트(`translation_result_left`, `recording_finished`, `review_answered`, `action_checked`)로 어긋난다**
- PM의 6개에는 PO-4 §4-2가 쓰는 이벤트가 하나도 없다. PO는 "DB가 진실"이라 비용 입력은 무사하지만 REQ-31 대시보드 5개 정의가 깨진다. 권고: PM 목록을 PO §4-2 5개 + 옵트아웃으로 교체(개수는 같음).

**RT-A-19 | 경미 | iOS-C1 6-10 · macOS_iPad MI-6 | Mac 최소 창 1000×700(D-20 유지) vs 900×600 제안, 기본 1200×800 vs 1280×800**
- MI-6 스스로 "합의 필요"로 표시. 권고: 12번 D-20 값 유지(변경 근거 없음).

**RT-A-20 | 경미 | QA §1-5 · BRIEF 사용자 답변 | CI Xcode 고정 `26.5` vs 개발 Mac Xcode `26.4(17E192)`, 런타임 `17.0` vs CI `17.5`**
- 스냅샷 기준 이미지는 러너에서 기록해야 하고, 로컬 재기록은 diff를 만든다. 권고: `XCODE_VERSION`을 사용자 환경(26.4)에 맞추거나 "기준 이미지는 CI `SNAPSHOT_RECORD=1` 잡에서만 생성" 규칙을 명문화. iOS 17 축은 17.0(설치됨)으로 통일.

**RT-A-21 | 경미 | PO-1 §1 3항 | 자체 YAML 부분집합 로더 60줄 — REQ-23(있는 것을 쓴다) 위반**
- RT-A-07에 흡수. `services/api` venv의 PyYAML 사용.

**RT-A-22 | 경미 | Backend B-3 §5-3 4) · 14번 §5-4 | LEVEL_UP은 v1.0에 푸시를 보내지 않는다고 적으면서 카테고리 4종 등록·픽스처 4개를 검증 대상으로 둔다**
- 앱 `PushRegistrar` 카테고리 4종 등록은 무해하나 Day 28 실기기 "iOS 4종 수신"은 3종만 검증 가능. 문구 정정.

**RT-A-23 | 경미 | 12번 §13 · PM-4 | `DELETE /users/me`(계정 삭제)가 v1.1이라 App Store 심사 제출은 v1.1 계약 전에는 불가**
- PM-4가 11/6·11/13을 TestFlight로 한정했으므로 v1.0 목표와는 충돌하지 않지만, 어느 파트도 "스토어 제출 = v1.1 이후"를 명시하지 않았다. PM 마일스톤 문구에 한 줄.

**RT-A-24 | 경미 | iOS A-3 | `SWIFT_TREAT_WARNINGS_AS_ERRORS` + `-warnings-as-errors`를 전 타깃 base에 두면 생성 코드(MwonmalAPI)·Tuist 생성 스텁 경고로 Day 3이 막힐 수 있다**
- iOS 스스로 "확인 필요"로 표시. 권고: Day 2에는 넣지 않고 Day 3 생성 코드 컴파일 후 타깃별로.

---

## B. "[사실]" 표기 검증 표 (sosumi, developer.apple.com 원문, 2026-09-19)

| # | 출처 파트·주장 | 확인 결과 | 판정 |
|---|---|---|---|
| 1 | macOS_iPad §0 / iOS C-1 ① — `horizontalSizeClass` iOS 13 / macOS 10.15, macOS는 항상 `.regular` | 문서: iOS 13.0+, macOS 10.15+ … "In macOS, and tvOS, it's always `.regular`", `@backDeployed(before: macOS 14.0 …)`(쓰기만) | macOS_iPad **정확**. iOS.md "Mac에는 sizeClass가 없어(항상 nil/regular)" **부정확**(존재하며 regular) |
| 2 | iOS A-4 #15 — `.spring(duration:bounce:blendDuration:)`, `.smooth/.snappy/.bouncy` iOS 13 | 문서: 둘 다 iOS 13.0+ / macOS 10.15+ | **정확** |
| 3 | macOS_iPad §0 — `onPasteCommand(of:perform:)` macOS 11 전용 | 문서: macOS 11.0+ 만 | **정확** (12번 §8-3의 iPad ⌘V 전제는 불가 → MI-3 `PasteButton` 대체 타당) |
| 4 | PM §0 / iOS #3 / MI §0 — `sidebarAdaptable` iOS 18 / macOS 15, iPadOS는 상단 탭바 | 문서: iOS 18.0+, macOS 15.0+; "iPadOS displays a top tab bar that can adapt into a sidebar" | **정확** (RT-A-09 근거) |
| 5 | PM·iOS·MI — `@Entry` iOS 13 back-deploy, 15번 T-C2 "17+면 @Entry 손실"은 오류 | 문서: iOS 13.0+, macOS 10.15+ | **정확**, T-C2 정정 타당 |
| 6 | AI §1-② — `Generable` watchOS 27.0+ 표기 | 문서: iOS 26.0+ … watchOS 27.0+ | **정확** |
| 7 | iOS A-4 #13 — `onGeometryChange(for:of:action:)` iOS 16 / macOS 13 back-deploy | 문서: iOS 16.0+, macOS 13.0+ | **정확** |
| 8 | iOS A-4 #21 — `Synchronization.Mutex` iOS 18 / macOS 15 | 문서: iOS 18.0+, macOS 15.0+ | **정확** |
| 9 | MI §0 — `PasteButton` iOS 16 / macOS 10.15 | 문서: iOS 16.0+, macOS 10.15+ | **정확** |
| 10 | MI-2 "`Settings` 씬 macOS 전용 — 확인 필요" | 문서: macOS 11.0+ 만, 예제가 `#if os(macOS)` | **해소**: macOS 전용 맞음 |
| 11 | MI §0 — `hoverEffect(_:)` iOS 13.4+, macOS 없음 | 문서: iOS 13.4+, iPadOS, Mac Catalyst, tvOS 16, visionOS; macOS 없음 | **정확** |
| 12 | QA-3 — `accessibilityReduceMotion`은 get-only라 환경 주입 불가 | 문서: `var accessibilityReduceMotion: Bool { get }` | **정확** (iOS B-4 MotionLab의 `.environment(\.accessibilityReduceMotion, true)` 토글은 컴파일 불가 → QA의 `\.mwMotion` 프로필 주입 방식이 맞음) |
| 13 | MI §0·MI-5 "`dropDestination(for:isEnabled:action:)` 신 API 최소 버전 확인 필요" / iOS #24 "26" | 문서: iOS 26.0+, macOS 26.0+, `DropSession` | **해소**: iOS.md 정확 |
| 14 | AI §1-② — `LanguageModelSession.GenerationError` deprecated, Xcode 27 필요 | 문서: Deprecated, "You must update to Xcode 27 to catch the new error types before submitting your app" | **정확** (개발 Mac Xcode 26.4 — v1.1 온디바이스 출시 시 Xcode 27 전제) |
| 15 | iOS A-4 #19 — `ASWebAuthenticationSession.Callback` iOS 17.4 / macOS 14.4 | 문서: iOS 17.4+, macOS 14.4+ | **정확** |
| 16 | MI §0 — `NavigationSplitView` iOS 16 / macOS 13 / watchOS 9, compact에서 가시성 무시 | 문서: 동일, "The split view ignores the visibility control when it collapses" | **정확** |
| 17 | MI §0 / Backend B-3 — `WKApplication.registerForRemoteNotifications()` watchOS 7, "양쪽에 보내면 동일 payload는 하나만 표시" | 문서: watchOS 7.0+, 원문 일치 | **정확** |
| 18 | iOS #5b·#22 — `Observations` iOS 26 | 문서: iOS 26.0+ | **정확** |
| 19 | iOS #11 — `.lineHeight(_:)` iOS 26 | 문서: iOS 26.0+ | **정확** |
| 20 | MI §0 — `TabSection`, `presentationSizing` iOS 18 / macOS 15 | 문서: 둘 다 iOS 18.0+, macOS 15.0+ | **정확** |
| 21 | iOS #3·#29 — `tabBarMinimizeBehavior`, `TabViewBottomAccessoryPlacement` iOS 26 | 문서: iOS 26.0+ | **정확** |
| 22 | AI §1-② — `contextSize` 26.4 이전 backDeployed | 문서: `@backDeployed(before: iOS 26.4, macOS 26.4 …)` | **정확** |
| 23 | iOS #1 — `requiresOnDeviceRecognition` iOS 13, `supportsOnDeviceRecognition`이 true일 때만 존중 | 문서: iOS 13.0+, "only honors this setting if supportsOnDeviceRecognition is also true" | **정확** — 즉 미지원 기기에서 `true`를 세팅해도 오디오가 서버로 갈 수 있으므로 iOS-A1의 "`supportsOnDeviceRecognition == false`면 미리보기 끔" 게이트는 **필수**(잘 잡았음) |
| 24 | iOS #8 / MI-4 "라이브 액티비티 iPad 확인 필요" | 문서: `Activity` iOS 16.1+, **iPadOS 16.1+**, macOS 없음 | **해소**: iPad도 16.1+ |
| 25 | QA §1-2 "`performAccessibilityAudit` 최소 OS 확인 필요" | 문서(`xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:)`): iOS 17.0+, macOS 14.0+, Xcode 16.3+ | **해소**: iOS 17·macOS 14 전 축에서 사용 가능 |
| 26 | MI-2 §4 — `@SceneStorage` + `NavigationSplitViewVisibility` | 문서: 타입은 `Codable/Equatable/Sendable`, `RawRepresentable` 아님; `SceneStorage.init(wrappedValue:_:)`는 `RawRepresentable`(Int/String) 요구 | **오류** (RT-A-10) |
| 27 | iOS #1 — `SpeechAnalyzer` iOS 26 / macOS 26, watchOS 없음(Backend B-4) | 문서: iOS 26.0+, macOS 26.0+, tvOS 26.0+, visionOS 26.0+; watchOS 없음 | **정확** |
| 28 | iOS #25 / MI-5 — `UIPasteboard.detectPatterns` 최소 버전 "확인 필요" | 검색으로 심볼 존재 확인(`detectPatterns(for:completionHandler:)`, `detectedPatterns(for:)` async). 페이지 본문 미취득 | **미해소**(iOS 14 추정 유지, 착수 전 재확인) |

외부(Apple 아님) 주장 중 이 도구로 검증 불가: QA F-1/F-2/F-3(hosted `macos-26` GA·`macos-14` 폐기·공개 저장소 무료), AI §1-① Gemini 모델명·단가·약관, Backend B-4 Groq 한도, PO 단가 전부. 각 문서가 "확인 필요"로 표기한 것은 유지하되, **QA F-1~F-3은 "[사실]"처럼 서술됐으나 출처 URL·확인일이 없다** → 경미로 표기 요구(RT-A-20 옆에 처리).

---

## C. 검증 관점별 요약

**1. REQ 위반·누락**: REQ-14 — RT-A-01(무료 티어 경로), RT-A-02(오프라인 온디바이스에 사전 우선 없음), RT-A-03(APNs body의 `action_text`). REQ-11 — RT-A-12(운영자 유료 키 1순위). REQ-20 — RT-A-14. REQ-23 — RT-A-21. 계약 v1.0 불변 — RT-A-16, RT-A-17. REQ-02(17+)·REQ-01(iPad)·REQ-03(화면)·REQ-22(Motion)·REQ-24(archify)·REQ-25(협의체)·REQ-27·REQ-32는 위반 없음.
**2. 사실 오류**: 28건 검증, 오류 2건(RT-A-10 `SceneStorage`, iOS.md의 Mac sizeClass "nil"), "확인 필요" 4건 해소(Settings 씬, dropDestination 26, 라이브 액티비티 iPad, performAccessibilityAudit).
**3. 파트 간 모순**: 레이아웃 분기(RT-A-08), 루트 구조(RT-A-09), AI 라우팅 책임·작업 단위(RT-A-05), `aiModel` 규약(RT-A-04), PO↔AI 무료 원문(RT-A-01), PM 견적↔파트 요구(RT-A-11), payload(RT-A-03), 평가셋(RT-A-06), 비용 계산기(RT-A-07), BYOK(RT-A-12).
**4. 아키텍처 결함**: 모듈 경계 — RT-A-09(MwonmalUI가 Navigation을 알아야 하는 루트). Swift 6 strict + `@available`: iOS A-5의 처리(`deinit` 저장 프로퍼티만, `SFSpeechRecognizer` 콜백에서 값만 yield, `Synchronization` 금지, `AsyncThrowingStream<_, any Error>`)는 검토 결과 타당하며 컴파일 위험을 못 찾았다. `@available` 구현체 선택을 `if #available` 표현식으로 쓰려면 `any TranscribingService` 타입 주석이 필요하다는 점만 A-2 예시에 빠져 있다(경미, 별도 ID 없음). 상태 보존 — RT-A-10(`SceneStorage` 타입), MI-2의 "루트 트리 교체 시 `RouteHost` `@State vm` 재생성 → refetch"는 D-10과 일치하나 **입력 중이던 W-01 텍스트가 유실**된다(compact 시트 → wide detail 화면으로 표현 자체가 바뀜, MI-6 W-01 행). 시트 VM은 시트 수명(12번 §8-4)이라 iPad Split View 진입 순간 작성 중 원문이 사라진다 — MI-2 리스크 항목에 추가 권고(중요 RT-A-09에 포함). 계약 v1.0 온디바이스 미전송의 실제 UX — RT-A-02.
**5. 빠진 것**: (a) REQ-21 `docs/lessons/` 리듬을 어느 파트도 다루지 않음(PM §5 산출물에 lessons 없음). (b) REQ-04 워치 포워딩 알림에서 `UNNotificationCategory` 액션이 뜨는지 — PO가 "확인 필요"로 남기고 아무도 해소하지 않음(Day 28 실기기 확인으로 이관 명시 필요). (c) 사전 전체를 앱이 받는 op 부재 — 온디바이스·오프라인 논의 전체의 전제인데 아무 파트도 계약 v1.1 백로그에 넣지 않음(RT-A-02 권고에 포함). (d) `NSSpeechRecognitionUsageDescription`·`UIBackgroundModes: audio` 심사 사유 — PM이 SpeechAnalyzer·라이브 액티비티를 뺀 뒤의 Info.plist 정리를 아무도 적지 않음. (e) 사용자 답변 "iOS 17.0 시뮬레이터 설치됨, Xcode 26.4"가 QA·iOS 매트릭스(17.5, 26.5)에 반영되지 않음(RT-A-20).

---

## D. 다음 세션 착수 순서 제안(레드팀 의견, 결정은 각 파트)

1. PO: RT-A-01·RT-A-12 (무료 티어 원문 정책, 키 해석) — REQ-11 각주 1개로 둘 다 닫힌다.
2. AI+iOS+PM: RT-A-02 (온디바이스 v1.0 제외) — PM 수지 −2일.
3. macOS_iPad+Backend: RT-A-03 (payload = `mw`+`deepLink`) — 픽스처 4개 확정.
4. macOS_iPad+iOS+PM: RT-A-08·09·10 (`mwLayout` 식 1개, 루트 2벌 in Composition, SceneStorage v1.1).
5. AI+Backend+PO+QA: RT-A-04·05·06·07·15 (`aiModel` 규약, 작업 2사슬, `eval/` 단일 스키마, 계산기 1개, 한도표 1개).
6. PM: RT-A-11 재산정.
7. 나머지 중요·경미는 해당 파트가 문서 수정만.
