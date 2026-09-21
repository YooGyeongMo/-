# ADR-0007: 해석 엔진은 4트랙을 같은 평가셋으로 재고, 라우팅은 서버 라우터가 결정하며, Foundation Models는 진입 조건을 통과할 때만 v1.0 미리보기 엔진이다

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-09-21) — Foundation Models 포함 여부는 S2 실측 후 이 문서 §8 점수표로 확정 |
| 관련 REQ | REQ-10(전부 비교), REQ-11(무료 티어), REQ-12(품질·지연·BM 라우팅), REQ-13(비용 모델), REQ-14(사전 우선·인덱스 재계산), REQ-23 |
| 관련 결정 | 14번 §15 **재작성**, 15번 §H 유지(80% 게이트), FD-5, FD-7(라우터), AI-1·2·3·5·6·7, Backend B-0·B-1, PM-3, RT-A-02·04·05·06·12·15, RT-B-02·03·13·17, 사용자 결정 (1) |
| 출처 | `council/S0/AI.md` §1~§5·§7, `council/S0/Backend.md` B-0·B-1·B-4, `council/S0/REDTEAM_A.md`, `council/S0/REDTEAM_B.md` |

## 1. 의도
REQ-10 "전부 비교"와 REQ-11 "무료만"을 동시에 만족하면서 크리티컬 패스(#11 라우터 → #17/#18)를 건드리지 않는다. 4트랙(① 외부 API ② Apple Foundation Models ③ MLX ④ 자체 sLLM)이 **같은 입력·같은 정답·같은 채점기**를 통과하게 하고, 라우팅 순서는 그 점수표로만 바꾼다(14번 §15 "평가셋 없이는 모델을 바꾸지 않는다"). 사용자 지시: "AI Foundation 기능이 macOS랑 iPhone에서 좋으면 하고 아니면 가장 추천(A)으로".

## 2. 비용
- 돈: 0. Gemini 무료 티어(서버·judge), Foundation Models·MLX(개발 Mac macOS 26 + Apple Intelligence, BRIEF 확인), Qwen3 베이스 하한선(Kaggle 무료 GPU 주 30h — 3차 자료, 실험 시작일 재확인).
- 시간: S2 **1.5일 타임박스**(PM-3) 안에 4행 측정. 평가셋 v0 50문장은 S0 자투리(AI §7 #1~#3 중 한도 캡처·스키마·v0만), v1 200문장은 S3~S4 자투리. 초과 시 즉시 중단하고 "미측정(사유)"로 기록해도 REQ-10 충족(비교 대상·방법·결과/미결과가 문서로 남음).
- 복잡도: 서버 Protocol 1개 + 어댑터 4개(`gemini_free`, `openai_key`, `anthropic_key`, `none`) + `vllm_local` 스텁, Redis 한도 카운터 2개 + circuit breaker. 앱은 v1.0에서 `TranslationEngine` 구현체 0(진입 조건 통과 시에만 `AppleFMTranslationEngine` 미리보기).
- 저장소: 모델 가중치 커밋 금지. 실측 usage는 `eval/measured/`(**.gitignore**, 사용자 결정 (4)).

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| 4트랙 전부 라우터에 제공자로 꽂기 | 서버(리눅스 VM)에서 MLX·Foundation Models는 실행 불가, sLLM은 학습 데이터 미확보 |
| 평가를 S6로 미룸 | 라우터 결정(이 ADR)이 S2 Day 11에 필요. 14번 §15 순서 위반 |
| 앱이 전부 결정(온디바이스 우선, 실패 시 서버) | 계약 v1.0으로는 온디바이스 결과를 서버에 저장할 수 없고(`TranslationRequest`에 결과 필드 없음), 사전 우선·인덱스 재검증(REQ-14)을 앱이 해야 함. 앱은 사전 전체를 갖지 않는다(D-10 "캐시는 /levels 하나", 사전 전체 조회 op 없음) — RT-A-02 |
| 서버가 온디바이스까지 원격 제어 | 왕복 1회 낭비, 오프라인 무의미 |
| AI-2 원안 "오프라인 임시 해석(저장 안 됨)"을 v1.0 사용자 경로에 | 서버의 사전 덮어쓰기·인덱스 재계산이 없어 REQ-14 위반(RT-A-02 치명). 탈락 |
| 공개 벤치마크(KoBEST 등)로 채점 | 판교어·의도·할 일 추출을 안 잼 |
| LiteLLM/LangChain 라우팅 라이브러리 | 의존성 수백 개, 원문이 라이브러리 로깅·콜백을 타는 경로가 생겨 REQ-14 불변식을 리뷰로 증명하기 어려움(Backend B-1) |
| Foundation Models를 조건 없이 v1.0 포함(AI-5 원안) / 조건 없이 제외(PM-2·iOS 원안) | 세 파트가 반대로 적었다(RT-B-02). 사용자 결정으로 **조건부** 채택 |

## 4. 왜
계약 v1.0은 제출본이라 v1.0에서 가능한 것은 "서버 안 라우팅"뿐이다. 기기·OS·네트워크는 앱이 알고, 작업 유형·예산·제공자는 서버가 안다 — 이것이 책임 분리의 선이다(AI-2). 온디바이스는 계약을 안 건드리는 자리(결과 도착 전 미리보기)에 먼저 넣되 **정본은 항상 서버 라우터 결과**로 두면 사전 우선·인덱스 재계산이 보장된다. 온디바이스 결과를 서버로 보내는 `clientHints`/`engineHint`·`clientDraft`는 v1.1 계약(Backend B-5 #11·12).

### 4-1. 평가셋(AI-1 채택, RT-A-06 정정 반영)
- 위치: **저장소 루트 `eval/`**(14번 §16 원안 유지, U-16). `eval/run.py`, `eval/score.py`, `eval/dataset/{v0_50,v1_200}.jsonl`, `eval/scores/*.md`, `eval/cost_model.py`(ADR-0009), `eval/pricing.toml`, `eval/usage.toml`(가정), `eval/measured/`(gitignore), `eval/limits.md`(무료 한도 캡처).
- 200문장 = A 용어 80 / B 숨은 뜻 50 / C 할 일 40 / D 회의록 30. dev 50 / test 150 분할, 파일 해시를 점수표에 기록. 전부 **합성+검수, 실사용자 문장 0**(REQ-14, 공개 저장소). 옵트인 신고 문장(AI-1 §7)은 비공개 브랜치·로컬 judge만(RT-B-25).
- 정답 = `TranslationResponse`(yml L2507)의 AI 생성 부분집합. **스키마는 AI §2-2 하나**. `direction` 값은 yml enum `JARGON_TO_PLAIN | PLAIN_TO_JARGON` 그대로(QA 초안의 `TO_PLAIN`은 enum에 없음 — RT-A-06). `startIndex/endIndex`는 유니코드 스칼라 기준, 테스트 벡터는 `packages/test-vectors/`와 공유.
- 채점: 용어 스팬 F1(정확 일치) / 신조어 `plainKo`·`nuance.note/tip`·`resultText`는 LLM-judge 1~5 / `intentType` 정확 일치(acceptable 집합) / `actionItems` 개수 정확 일치 + `actionText` 임베딩 매칭 F1 + `dueHint` 정규화 일치 + `dueAt` ±1h / JSON 유효율 / 거부율. 종합 0~100 가중치는 AI §2-3 표(v1 고정). judge 신뢰도: 30건 사람 채점과 Spearman ≥ 0.7. judge는 후보와 다른 계열(MLX Qwen3-8B 로컬)로 교차.
- QA-2의 회귀 게이트(JSON 유효율 ≥ 98%, intent·스팬 F1 baseline −3pt)는 `score.py` 출력 위의 얇은 스크립트. CI 호출은 야간 `schedule`에서만 40문장 회전(캐시 우선), PR은 캐시 히트만, 릴리스는 200 전부(RT-A-15). 무료 RPD 실제 값은 **확인 필요** — AI Studio 캡처를 S0 Day 1 게이트로(RT-B-13), `eval/limits.md`가 유일한 출처.

### 4-2. S2 측정 4행
| 트랙 | 실행 위치 | 측정 |
|---|---|---|
| ① Gemini 무료(서버) | 서버 라우터 | 점수·p50/p95·유료 환산 원가·무료 한도 대비 사용 |
| ② Foundation Models | **Mac 26 + iPhone 26 실기** 둘 다 | 점수·p50 지연(MESSAGE ≤ 500자)·콜드 로드·`usage` 토큰·가드레일 거부율 |
| ③ MLX Qwen3-4B 4bit | 개발 Mac | 점수·tok/s·첫 토큰·콜드 로드 |
| ④ Qwen3-4B 베이스 하한선 | Kaggle | 점수(LoRA 전 하한선) |

점수표 열: `track | provider/model | promptVersion | dataset hash | 종합 | spanF1 | intentAcc | nuanceJudge | actionF1 | dueAcc | resultJudge | jsonValid% | refusal% | p50 ms | p95 ms | 입력토큰 | 출력토큰 | 원가/건(₩, 유료 환산) | 무료 한도 대비 | 오프라인 | 원문 외부 전송 | 측정 기기·날짜`. AI §3의 [예상] 수치는 결정 근거로 쓰지 않는다.

### 4-3. Foundation Models v1.0 진입 조건 (사용자 지시, FD-5)
**Mac 26 실기와 iPhone 26 실기 둘 다** 종합 점수 ≥ 서버 최고 트랙의 80% **그리고** p50 지연 ≤ 3s(MESSAGE ≤ 500자)일 때만 v1.0에 **미리보기 엔진**으로 들어간다.
- 통과 시: 결과 도착 전 "쉬운 말 미리보기"(형광펜 없음, D-7과 같은 규칙). 정본은 서버 결과. 저장되는 것은 서버 결과뿐. 오프라인 임시 해석은 **없다**.
- 미통과 시: v1.1로 이관하고 점수표를 이 ADR §8에 남긴다. 사용자 경로에는 아무것도 넣지 않고 `eval/` 어댑터로만 점수표에 오른다(REQ-10 충족).
- 게이트 세 겹: `#available(iOS 26, macOS 26, *)` + `SystemLanguageModel.default.availability == .available` + `supportsLocale()`. 4096 토큰/세션(한국어는 토큰 ≈ 1글자, Apple 문서)이라 MEETING_NOTE 5,000자는 불가. `LanguageModelSession.GenerationError`는 deprecated → 새 오류 타입을 잡으려면 Xcode 27 필요(Apple 문서) — v1.1 온디바이스 출시 시 전제.

### 4-4. 서버 라우터(Backend B-0·B-1 채택, 수정 반영)
- 패키지: 컨텍스트 우선 `app/{identity,workspace,decode,learning,notify}/{api,domain,usecases,infra}`. `decode/domain/services/engine_port.py` Protocol(`translate`, `health`, `cost_estimate`, `quota_keys`)이 `learning`이 import하는 유일한 파일(import-linter).
- 어댑터: `gemini_free`(CHEAP/STRONG 모델 2단), `openai_key`·`anthropic_key`(**평가 전용**, prod 사슬 제외 — ADR-0008), `none`(사전 trie만, 절대 실패 없음), `vllm_local`(v1.1 스텁).
- **작업 단위는 Backend 2사슬**(RT-A-05): `DETECT_PLAIN` → `NUANCE_ACTIONS`(요청 1회 = 최대 2호출). AI-2의 "한 호출에 4출력"은 실험 열로만. prod 사슬은 작업 무관 `gemini_free`(옵트인+한도 내) → `none`; dev/eval 사슬 `gemini_free` → `openai_key`/`anthropic_key` → `none`(ADR-0008). NUANCE 사슬 실패는 **생략**(nuance=null, actionItems=[] — 계약상 합법), DETECT 실패는 `none` 강등(사용자 결정 U-9 허용, 앱 "간이 해석" 배지) 또는 503 `AI_UNAVAILABLE` + `Retry-After: 5`.
- 한도·브레이커: Redis `ai:quota:{engine}:{model}:{unit}:{window}` 카운터 **일(RPD)·분(RPM) 두 개** + 피크 RPM 별도(RT-B-08), 80% 소프트 상한. circuit breaker `ai:cb:*` 30초 2회 실패 → 60초 OPEN → HALF_OPEN 프로브(`SET NX`). 블루·그린 두 버전이 **같은 키**를 본다(키에 앱 버전 없음). Redis 못 읽으면 fail-safe(`none`/503). 개발 예산 = 무료 RPD 50%, CI 외부 호출 0.
- 호출마다 `ai_usage`(텍스트 컬럼 0) → 일 배치 `usage_daily`(dbml v1.1, 마이그레이션 0002 — Day 11이 아니라 Day 12로, RT-B-03). Day 11 = `gemini_free` + `none` + 브레이커 + 레코더까지.
- 사전 우선·인덱스 재계산은 엔진과 무관한 공통 후처리(14번 §5-1 5·6단계). `matchedText`가 `sourceText[start:end]`와 다르면 서버가 다시 찾고, 못 찾으면 그 용어 폐기.
- 사용자 일 한도 429 `TOO_MANY_REQUESTS`는 계약 v1.0 `Error.code`에 없음(RT-A-17) → v1.1에 추가, v1.0은 503+Retry-After와 30/분 레이트리밋만.

### 4-5. 엔진 출처 규약 (AI-3·Backend 통합, RT-A-04·RT-B-17)
v1.0 `aiModel`(varchar 50, 계약 무변경): `{track}/{model}#p{promptVer}` — 예 `gemini/gemini-2.5-flash#p1`, `fm/apple-26.4#p1`, `none/dictionary#p1`, `mlx/qwen3-4b-4bit#p1`. 서버 정규식 테스트 1개, 50자 이내. **앱은 v1.0에서 파싱하지 않는다**(Backend Day 3 지시). `prompt_version`은 `ai_usage` 컬럼에도 별도 기록. v1.1에 `engine` 객체(`track, provider, model, modelVersion, location: SERVER|DEVICE, promptVersion`)로 승격. PO-4의 `dictionary_only_rate = ai_model IS NULL`은 dbml L304 `not null`이라 불가 → `ai_model LIKE 'none/%'` 또는 `ai_usage.engine = NONE` 비율로 정정.

### 4-6. AI-5 재작성 — Foundation Models 게이트 (REQ-20 7항목)
1. **의도**: 온디바이스 트랙(REQ-10 ②)을 iOS 17~25 사용자와 Apple Intelligence 미지원 기기를 배제하지 않는 형태로, 진입 조건을 통과했을 때만 v1.0에 넣는다.
2. **비용**: 돈 0. 시간: FM 스파이크 0.5일(개발 Mac, `tokenCount(for:)`·한국어 500자 1건·지연·가드레일) + 통과 시 `Platform/AppleFMTranslationEngine` + `@Generable` 스키마 + 3겹 게이트 + 미리보기 UI 2~3일(S2 Day 14 확장 또는 S5; 미통과면 0). 4096 토큰 예산: 입력 ≈500 + instructions ≈300 + 스키마 ≈200~400 + 출력 ≈400 = **1,400~1,600 [예상]**.
3. **대안**: (a) MEETING_NOTE까지 청크 분할로 온디바이스 — 4096 토큰 한도, v1 밖. (b) `SystemLanguageModel(useCase: .contentTagging)`으로 용어 태깅만 — 후보로 S2 측정 열에 추가하되 기본은 일반 세션. (c) Apple Adapter Toolkit(LoRA 160MB) — 어댑터가 OS 모델 버전마다 재학습, Toolkit 26.0.0이 마지막이며 27 비호환(Apple 문서), 개발 Mac 32GB 조건 **확인 필요** → 1인에게 유지 비용 과함, 탈락.
4. **왜**: 진입 조건(Mac·iPhone 둘 다 80%·3s)을 실기에서 통과하지 못하면 미리보기는 서버 결과와 다른 문장을 먼저 보여 준 뒤 바꾸는 UX가 되어 가치보다 혼란이 크다. 통과하면 REQ-14를 지키면서(정본은 서버) 프라이버시·지연 이점을 얻는다.
5. **영향**: `Platform/AI/AppleFMTranslationEngine.swift`(@available 26), `Composition/AppContainer`(선택), `Domain/Services/TranslationEngine` 프로토콜, 12번 §2 `Services/`, 14번 §15 온디바이스 문단, 이 ADR §8 점수표.
6. **검증**: S2 점수표 ② 행(Mac·iPhone 실기 각 1행). 앱 테스트: 온디바이스 경로에서 네트워크 Spy 호출 0(추론 단계만 — 다운로드 단계 분리, RT-B-26), Fake `LanguageModelClient`로 availability 3종 × 네트워크 2종 VM 테스트. Instruments "Foundation Models" 템플릿으로 토큰 확인.
7. **리스크·되돌림**: 모델 버전(26.0–26.3 / 26.4 / 27.0)마다 프롬프트 반응이 달라짐(Apple 문서 "Updating prompts for new model versions") → 점수표에 `fm/apple-{ver}`로 행 분리. 되돌림: 통과 후에도 15번 §H(80% 미만이면 서버로) 그대로 — 야간 평가에서 2회 연속 미달이면 미리보기 플래그 OFF.

### 4-7. AI-6 재작성 — MLX 실험 플래그 (REQ-20 7항목)
1. **의도**: REQ-10 ③ 비교 의무를 v1.0 출시 범위 밖에서 충족하고, v1.1 이후 Mac 로컬 엔진의 자리를 미리 확보한다.
2. **비용**: 돈 0(Mac 전력). 시간: 어댑터 + 모델 다운로드(Qwen3-4B-4bit ≈ 2GB+) + 50문장 실측 0.5일(S2 타임박스 안). 프로덕션 코드 0(플래그 뒤).
3. **대안**: (a) MLX를 v1.0 macOS 앱 기능으로 — Mac App Store 샌드박스에서 런타임 2~5GB 다운로드·심사 정책 **확인 필요**, D-25(MAS) 유지 전제로 v1.0 밖. (b) iPhone에서도 MLX — 4B-4bit ≈ 2GB+ 상주 메모리로 jetsam 경계, 제외. (c) MLX 서버(리눅스) — Metal 필요, 불가.
4. **왜**: mlx-swift-lm은 macOS 14 / iOS 17+, `MLXGuidedGeneration`(JSON Schema logit 마스킹)이 macOS 14 / iOS 17+(Context7 확인)라 최소 OS와 충돌하지 않는다. 라우터·계약 무변경으로 `TranslationEngine` 구현체만 바꿔 끼울 수 있다.
5. **영향**: macOS 앱 `.experimentalMLX` 플래그(DEBUG 빌드 또는 숨은 설정), `eval/` MLX 어댑터, 이 ADR 점수표 ③ 행. `HF_HUB_DISABLE_TELEMETRY` 설정(swift-huggingface 동작 **확인 필요**).
6. **검증**: 점수표 ③ 행(점수·tok/s·콜드 로드). 추론 단계 네트워크 Spy 0.
7. **리스크·되돌림**: 시뮬레이터 불가(Metal), 개발은 Mac에서만. 되돌림: 8B가 4B보다 +5점 이상이면 8B(16GB+ Mac)로 교체. v1.1 프로덕션 여부는 점수·MAS 정책 확인 후 별도 ADR.

### 4-8. 자체 모델 트랙(AI-7 채택)
Qwen3 LoRA 우선(SKALA LoRA SFT 경험 재사용), nanoGPT는 **1일 학습 실험 기록용**(shakespeare_char 설정으로 char-level, 점수표에는 "측정 불가(태스크 미달)"). LoRA는 Kaggle 무료 GPU로 **S4 이후**. 학습 데이터에 실사용자 원문 절대 금지, 학습 스크립트에 DB 드라이버 import 금지(import-linter). 성공 기준: test 150 종합 ≥ 서버 최고의 80%, JSON 유효율 ≥ 98%, 스팬 F1 ≥ 0.85, MLX 4bit 변환 후 하락 ≤ 3점, Mac p95 ≤ 8s. 포기 조건: 3회 학습 후 종합 < 60% 또는 JSON 유효율 < 90%.

## 5. 영향 파일·문서
- `eval/`(위 §4-1 트리), `Makefile eval MODEL= SAMPLE=`, `.gitignore`에 `eval/measured/`·`eval/.cache/`.
- `services/api/app/decode/…`(§4-4 배치), `services/api/app/core/`, `.importlinter`, `services/api/.env.example`(키 이름만: `GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`(평가 전용), `VLLM_BASE_URL`, `MWONMAL_AI_QUOTA__*`, `ROUTER_ALLOW_DEGRADED`, `AI_EXTERNAL_TEXT`), `services/api/README.md` Redis 키 규약(`ai:quota:*`, `ai:cb:*`, `ai:user:*`, `mw:q:*`).
- 14번 §1 표 "Claude API claude-opus-5" → "EngineRouter(§15)"; §3 트리(컨텍스트 우선); §5-1 4단계; §15 라우터 표(1순위 Gemini Flash, BYOK 열 삭제)·평가셋 문단·4트랙 표; §16 `eval/` 트리; §11 v1.1 표에 `engineHint`·`clientDraft`·`engine`·`degraded`.
- 12번 §2 `Services/TranslationEngine`, §13 백로그.
- 15번 §H 표 갱신. `docs/diagrams/ai-routing.workflow.json`(FD-10 1차 3장 중 하나).
- 이슈 #11(Day 11 범위 축소), 새 S2 이슈 "[S2][docs] AI 4트랙 평가·비용 모델·ADR-0007"(1.5일).

## 6. 검증
- `make eval` 점수표에 4행(미측정은 사유 명시), `pytest eval/` 통과, 채점기 자기 테스트(정답 → 100, 빈 응답 → 0).
- 라우터 단위 테스트: 정책 표 → 사슬 순서 전수(가짜 엔진), 브레이커 상태 전이(Clock 주입), 한도 카운터 80% 경계, `none`이 test-vectors 형광펜 정답과 일치. 통합(testcontainers Redis): 프로세스 2개가 같은 브레이커를 본다.
- CI 검사: 설정의 1순위 모델 점수 ≥ 폴백 점수. schemathesis: 모든 201 `aiModel`이 정규식과 50자 이내, 503에 `Retry-After`.
- 프롬프트 빌더 출력에 userId·프로젝트명·회의 제목 없음(서버 테스트). `eval/`은 DB·API 서버에 접근 불가(네트워크 분리).
- 진입 조건 판정 기록: Mac·iPhone 각 점수·p50을 §8에 날짜와 함께.

## 7. 리스크와 되돌리는 조건
- 리스크: 1.5일 타임박스 초과 → 즉시 중단, 미측정 기록, 잔여는 v1.1 과제. 무료 한도 429 > 5%/일 → 사용자 일 한도 하향·강등 비율 상승, PO에 유료 전환 결정 요청(REQ-11 개정 필요). 무료 RPD가 20 이하로 확인되면 야간 표본 20, 200 전체는 주 1회 분할.
- 되돌리는 조건: 온디바이스 점수가 80% 게이트 미달이면 ②는 미리보기에서도 빼고 평가 수집만(15번 §H). 프롬프트 두 벌 격차 > 10점이면 공통 1벌 + 출력 형식 어댑션만. 월 해석 > 50만 건이 되면 자체 서빙(④) 재검토.

## 8. 점수표 (S2 측정 후 기록)
> 미기록. S2(10/5~10/9) 1.5일 타임박스 결과를 `eval/scores/2026-10-XX.md`에서 여기로 옮긴다. Foundation Models 진입 조건 판정(Mac 26 실기 / iPhone 26 실기 각 종합·p50)과 "통과 / v1.1 이관" 결론을 날짜와 함께 남긴다.
