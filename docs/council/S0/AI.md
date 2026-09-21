# AI 파트장 결정서 — 해석 엔진 4트랙 평가 계획 + 라우팅 정책 v0

> 협의체 1차 세션 (2026-09-19). 담당: AI 파트장. 근거 문서: `docs/REQUIREMENTS.md` B절(REQ-10~14), `docs/design/14_시스템_설계서.md` §5-1·§8·§15·§16, `docs/design/15_기술_트레이드오프_결정기록.md` §H·§I, `docs/design/12_앱_아키텍처_설계.md` §2·§10·§12, `contracts/openapi.yml`(`TranslationRequest` L2156, `TranslationResponse` L2507), `contracts/db.dbml`(`translations` L286, `translation_terms` L336).
> 표기 규칙: **[사실]** = 문서·공식 자료에서 확인(출처·날짜 병기). **[예상]** = 측정 전 추정. **[확인 필요]** = 확인 못 함. 지어낸 수치 없음.
> 참고: 과제문의 "TranslationResult"는 yml에 없는 이름이다. 실제 스키마명은 `TranslationResponse`(L2507)이며 이 문서는 그 이름을 쓴다.

---

## 0. 한 장 요약

| 결정 | 요지 |
|---|---|
| AI-1 | **평가셋 200문장이 모든 라우팅 결정의 유일한 근거.** 정답 = `TranslationResponse`의 AI 생성 부분집합 JSON. 채점은 필드별로 정확 일치 / 스팬 F1 / LLM-judge를 나눠 쓴다 |
| AI-2 | **라우팅은 서버 라우터(Python)가 결정하고, 앱 `TranslationEngine`은 "능력 보고 + 온디바이스 실행"만 한다.** v1.0 계약으로는 온디바이스 결과를 서버에 못 보내므로 온디바이스는 v1.0에서 폴백·미리보기·평가 수집 용도, 비용 절감은 v1.1 |
| AI-3 | **엔진 출처 기록**: v1.0은 `aiModel`(varchar 50) 문자열 규약 `{track}/{model}@{ver}`, v1.1 후보로 `engine` 객체 추가 |
| AI-4 | **Gemini 무료 티어의 데이터 사용 조항** 때문에 실사용자 원문 경로는 PO 결정 필요(에스컬레이션). 개발·평가는 합성 평가셋만 무료 티어로 |
| AI-5 | Foundation Models(②)는 `@available(iOS 26, macOS 26, *)` 게이트 안에서 **MESSAGE 500자 + 용어 탐지·쉬운 말**만. 4096 토큰 한도로 MEETING_NOTE 제외. 서버 인덱스 재검증 유지 |
| AI-6 | MLX(③)는 **macOS 앱의 숨은 실험 플래그**로만. v1.0 출시 범위 밖, 평가표에는 포함 |
| AI-7 | 자체 모델(④)은 **Qwen3 LoRA 우선**, nanoGPT는 1일짜리 학습 실험으로 한정(포기 조건 명시). 무료 GPU(Kaggle 30h/주)로만 |
| AI-8 | REQ-14 프라이버시 불변식을 **엔진별 데이터 흐름 표**로 확장. "원문이 어디까지 가는가"를 트랙마다 명시 |
| 순서 | 평가셋 v0(50) → 서버 라우터(무료 티어) → 평가셋 v1(200) → 온디바이스 FM 어댑터 → MLX 실험 → LoRA 실험. **14번 §15의 순서와 같다** |

---

## 1. 트랙별 기술 사실 확인

### ① 외부 API (Gemini 무료 티어 / OpenAI·Claude는 사용자 대여 키)

| 항목 | 내용 | 근거 |
|---|---|---|
| Gemini 무료 티어 존재 | **[사실]** `gemini-3.8-flash`, `gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`, `gemini-2.5-flash`, `gemini-2.5-flash-lite`, `gemini-embedding-2`, Gemma 4 등이 "Free of charge". **Pro 계열은 2026-04 이후 무료 티어에서 제외**(3차 자료, 확인 필요) | ai.google.dev/gemini-api/docs/pricing (2026-09-19 확인) |
| 무료 티어 데이터 사용 | **[사실]** 무료 티어는 전 모델 "Used to improve products: **Yes**". 약관: "Google uses the content you submit to the Services and any generated responses to provide, improve, and develop Google products and services", "human reviewers may read, annotate, and process your API input and output", **"Do not submit sensitive, confidential, or personal information to the Unpaid Services."** | ai.google.dev/gemini-api/terms (2026-09-19 확인) |
| 유료 단가 (원가 모델 입력값) | **[사실]** 3.8/3.7/3.6 Flash: 입력 $0.75 / 출력 $3.75 per 1M tokens (2026-12-31까지 표기). 3.5 Flash: $1.50 / $9.00. 3.5 Flash-Lite: $0.30 / $2.50 | 같은 pricing 페이지 |
| 무료 티어 속도 제한(RPM/RPD) | **[확인 필요]** 공식 rate-limits 페이지는 수치를 싣지 않고 AI Studio(`aistudio.google.com/rate-limit`)에서 보라고만 함. 3차 자료는 "Flash 약 15 RPM / 1,500 RPD"(2026-05)와 "Flash 20 RPD, Flash-Lite 500 RPD"(2026-09)로 **서로 다름**. S2 Day 11 전에 AI Studio에서 실제 값을 캡처해 `eval/limits.md`에 적는다 | ai.google.dev/gemini-api/docs/rate-limits |
| OpenAI·Claude | REQ-11: 사용자 제공 키(BYOK)만. 무료 티어 없음 → **라우터에서 "키가 있을 때만 활성"인 선택 제공자**. 14번 §1 "AI: Claude API `claude-opus-5`"와 §15 "숨은 뜻 1순위 Claude"는 REQ-11과 충돌 → §4에서 재정의 | REQ-11 |
| Groq 무료(§15 폴백 후보) | **[확인 필요]** 3차 자료: 30 RPM, 6K TPM, 14.4K RPD, 조직 단위, Qwen3·Llama 제공. 공식 `console.groq.com/docs/rate-limits`에서 재확인. 데이터 사용 약관도 미확인 | 검색 결과(3차) |
| 구조화 출력 | Gemini: JSON 스키마 응답(`responseSchema`) **[사실, 일반 지식 — 버전별 필드명 확인 필요]** | |

### ② Apple Foundation Models (온디바이스)

| 항목 | 내용 | 근거 (Apple 문서, 2026-09-19 sosumi/apple-docs로 확인) |
|---|---|---|
| 지원 OS | **[사실]** 프레임워크·`SystemLanguageModel`·`@Generable`·`Availability`: iOS 26.0+ / iPadOS 26.0+ / macOS 26.0+ / visionOS 26.0+ / Mac Catalyst 26.0+. `Generable`은 watchOS 27.0+도 표기 | `/documentation/foundationmodels/systemlanguagemodel`, `/generable` |
| 지원 기기 | **[사실]** "Model availability depends on whether the device and region supports Apple Intelligence." 기기 목록은 apple.com/apple-intelligence 참조. 3차 정리: iPhone 15 Pro/Pro Max·16 이후·iPhone Air, iPad M1+·iPad mini A17 Pro, Mac M1+ **[확인 필요: 공식 표로 재확인]** | SystemLanguageModel Overview; support.apple.com/121115 |
| 한국어 | **[사실]** Apple Intelligence 지원 언어에 한국어 포함(iOS 18.4부터, Apple Newsroom 2025-03). 모델은 다국어. 코드에서 `SystemLanguageModel.default.supportsLocale()`로 확인, 미지원이면 `LanguageModelError.unsupportedLanguageOrLocale` | "Supporting languages and locales with Foundation Models" |
| 컨텍스트 한도 | **[사실]** "Apple's on-device foundation model has a context window of **4096 tokens per session**", 한국어 등 멀티바이트 언어는 "**a token typically represents one character**". 프롬프트·instructions·Generable 스키마·출력 전부 포함. 초과 시 `LanguageModelError.contextSizeExceeded`. `contextSize` 프로퍼티는 26.4 이전으로 backDeployed, `tokenCount(for:)`로 사전 계산 가능 | "Managing the context window", `contextSize` |
| 구조화 출력 | **[사실]** `@Generable` + `@Guide(description:, .count/.maximumCount/.range…)`, `session.respond(to:generating:)`, `GenerationSchema`/`DynamicGenerationSchema`, 스트리밍용 `PartiallyGenerated`. 스키마가 JSON Schema로 변환돼 컨텍스트를 소비 | `/generable` |
| 가용성 체크 API | **[사실]** `SystemLanguageModel.default.availability` → `.available` / `.unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)`; `isAvailable` Bool. `SystemLanguageModel`은 `Observable` | `/availability-swift.enum/unavailablereason` |
| 모델 버전 | **[사실]** "Currently, there are 3 model versions": 26.0–26.3 / 26.4 / 27.0. 프롬프트가 버전마다 달리 반응할 수 있음("Updating prompts for new model versions") | SystemLanguageModel Overview |
| 오류 타입 변경 | **[사실]** `LanguageModelSession.GenerationError`는 **deprecated** → `LanguageModelError`, `SystemLanguageModel.Error`, `LanguageModelSession.Error`. "You must update to Xcode 27 to catch the new error types before submitting your app." | `/languagemodelsession/generationerror` |
| 가드레일 | **[사실]** `Guardrails.default` / `.permissiveContentTransformations`; 위반 시 `guardrailViolation`. 가드레일은 지원 언어에서만 동작 | `/systemlanguagemodel/guardrails` |
| 특화 use case | **[사실]** `SystemLanguageModel(useCase: .contentTagging, guardrails:)` — 용어 태깅에 후보 | `/systemlanguagemodel/usecase` |
| 토큰 사용량 | **[사실]** `LanguageModelSession.usage` (`input.totalTokenCount/cachedTokenCount`, `output.totalTokenCount/reasoningTokenCount`) → 평가 지표에 그대로 기록 가능. Xcode Instruments "Foundation Models" 템플릿 존재 | 프레임워크 개요 목차 |
| 커스텀 어댑터(LoRA) | **[사실]** Adapter Training Toolkit: Apple silicon Mac **32GB+** 또는 Linux GPU, Python 3.11+. 어댑터 **약 160MB**, 앱 번들 금지 → Background Assets로 배포. **"Each adapter is compatible with a single specific system model version"** → OS 모델 버전마다 재학습. 배포 시 `com.apple.developer.foundation-model-adapter` 엔타이틀먼트(Account Holder 신청). **Toolkit 26.0.0이 마지막이며 OS 27과 비호환**. 데이터: 기본 100~1,000, 복잡 5,000+ 샘플 jsonl | developer.apple.com/apple-intelligence/foundation-models-adapter (2026-09-19 확인) |
| iOS 27 추가 사항 | **[사실]** `LanguageModel` 프로토콜(iOS 27.0+): 서드파티 모델(서버·MLX)을 같은 `LanguageModelSession` API로 꽂는 브리지. `PrivateCloudComputeLanguageModel` 타입 존재(상세 확인 필요) | `/languagemodel` |
| 모델 크기 | **[사실]** Apple ML Research(2026-06-08): AFM 3 Core = 3B dense; AFM 3 Core Advanced = 20B sparse(활성 1~4B). 어느 OS 버전이 어느 모델인지 **[확인 필요]** | machinelearning.apple.com |
| 처리 속도 | **[확인 필요 → 측정]** 공식 tok/s 없음. 평가셋에서 측정 | |

**함의**: REQ-02(iOS 17+)에 따라 ②는 `if #available(iOS 26, macOS 26, *)` + `availability == .available` + `supportsLocale()` 세 겹 게이트 뒤에만 존재한다. 500자 MESSAGE(≈500 토큰) + instructions(≈300) + 스키마(≈200~400) + 출력(≈400) ≈ **1,400~1,600 토큰 [예상]** → 4096 안. MEETING_NOTE 5,000자는 **불가**(청크 분할은 v1 밖).

### ③ 로컬 LLM — MLX Swift (Mac 앱 안)

| 항목 | 내용 | 근거 (Context7 `/ml-explore/mlx-swift-lm`, `/ml-explore/mlx-swift`, 2026-09-19) |
|---|---|---|
| 패키지 | **[사실]** `https://github.com/ml-explore/mlx-swift-lm` (문서상 `.upToNextMajor(from: "3.31.3")`), 프로덕트 `MLXLLM`, `MLXLMCommon`, `MLXHuggingFace`, `MLXGuidedGeneration`, `MLXFoundationModels`. 보조: `huggingface/swift-huggingface`, `huggingface/swift-transformers`(Tokenizers) | README, using.md |
| 플랫폼 | **[사실]** mlx-swift `Package.swift`: macOS 14.0, iOS 17, tvOS 17, visionOS 1. **시뮬레이터 불가**(Metal GPU family 필요) — 개발은 Mac 또는 실기기 | Package.swift, troubleshooting.md |
| 메모리 | **[사실]** "~0.5GB per 1B parameters for 4-bit quantized" → Qwen3-4B-4bit ≈ **2GB+**, 8B-4bit ≈ **4GB+** 가중치, 추론 시 추가 메모리. iOS는 jetsam 종료 위험, "Increased Memory Limit" 엔타이틀먼트 언급 | model-container.md, running-on-ios.md |
| 모델 로드 | **[사실]** `LLMModelFactory.shared.loadContainer(from: HubClient.default, using: TokenizersLoader(), configuration: .init(id: "mlx-community/Qwen3-4B-4bit"))`, `ChatSession(container).respond(to:)`, 스트리밍 `streamResponse`. Hugging Face Hub에서 **런타임 다운로드** | SKILL.md |
| 구조화 출력 | **[사실]** `MLXGuidedGeneration`: JSON Schema/EBNF/XGrammar로 logit 마스킹, **macOS 14 / iOS 17+**. `MLXFoundationModels`로 `@Generable`을 그대로 쓰는 경로는 **iOS 27 / macOS 27+** (`#huggingFaceLanguageModel(... capabilities: [.guidedGeneration])`) | MLXGuidedGeneration README, README |
| iPhone 가능 여부 | **[사실+예상]** 패키지는 iOS 17+를 지원하지만, 4B-4bit ≈ 2GB+ 상주 메모리 → 8GB RAM 기기에서도 jetsam 경계. **iPhone은 v1 평가 대상에서 제외**, macOS·iPad(M 시리즈)만 |
| Mac App Store 샌드박스 | **[확인 필요]** 런타임 2~5GB 모델 다운로드 + `network.client` 엔타이틀먼트로 가능할 것으로 보이나, MAS 심사·디스크 사용 정책은 미확인. D-25(MAS) 유지 전제로 v1.0 출시 범위 밖 |
| 속도 | **[확인 필요 → 측정]** 개발자 Mac에서 tok/s, 첫 토큰 지연, 콜드 로드 시간 측정 |

### ④ 자체 소형 모델 (nanoGPT vs Qwen LoRA·증류)

| 항목 | 내용 | 근거 |
|---|---|---|
| nanoGPT | **[사실]** GPT-2 124M 재현 = 8×A100 40GB 약 4일. shakespeare_char(≈1M 파라미터급, 6층·384dim)는 GPU 3분, Mac CPU 3분(작은 설정). Apple Silicon `--device=mps` 2~3배 가속. 코드 ≈ 300줄 모델 + 300줄 학습 루프 | github.com/karpathy/nanoGPT README (2026-09-19 확인) |
| nanoGPT 함의 | 판교어 "원문 → 4출력 JSON"은 지시 따르기·한국어 이해·JSON 형식이 다 필요. 처음부터 학습한 1억 파라미터급 모델은 한국어 사전학습 데이터(수십 GB)와 GPU 수십 시간 없이 **이 태스크에 못 미친다 [예상, 강한 확신]**. 포트폴리오·이해 목적의 1일 실험으로 한정(AI-7) |
| Qwen3 LoRA | **[사실]** Qwen3 4B/8B 4bit MLX 변환본이 `mlx-community`에 존재(위 모델 ID). SKALA 과제에서 Qwen LoRA SFT 파이프라인 경험(메모리: Trainable 1.18%, SFT로 지표 상승) — 재사용 가능 | 14번 §15 파인튜닝 트랙 2 |
| 무료 GPU | **[사실, 3차·변동]** Colab 무료: T4 16GB, 세션 최대 ~12h, 주간 한도 비공개·변동. Kaggle: **주 30h**, 세션 9h, P100 16GB 또는 T4×2, 전화 인증 필요. 둘 다 정책 변동 → 실험 시작일에 재확인 | 검색 결과(2026) |
| 서빙 | 14번 §15: vLLM을 스팟 GPU에 "실험용으로만". REQ-11(유료 결제 없음) 아래서는 **스팟 GPU도 불가** → 서빙 평가는 (a) Kaggle 세션 안 vLLM 임시 엔드포인트, (b) 개발자 Mac MLX(③과 합류). 상시 서빙은 v1 밖 |
| Apple 어댑터 경로 | ②의 Adapter Toolkit도 "자체 모델"의 한 형태(160MB, OS 모델 버전마다 재학습, 27 비호환). 학습은 개발자 Mac이 32GB 이상일 때만 — **[확인 필요: 개발 Mac 메모리]** |

---

## 2. 평가셋 설계 (`eval/`, 14번 §16)

### AI-1. 평가셋을 먼저 만들고, 이것으로만 라우팅을 바꾼다

1. **의도** — REQ-10 "전부 비교", REQ-12 "품질·지연·BM 같이", 14번 §15 "평가셋 없이는 모델을 바꾸지 않는다"를 실행 가능한 형태로. 4트랙이 같은 입력·같은 정답·같은 채점기를 통과하게.
2. **비용** — 문장 200개 작성·검수 약 2일(합성 1일 + 검수 1일), 채점 스크립트 1일. 돈 0원(합성·judge 모두 Gemini 무료 티어, 합성 문장이라 기밀 없음). 유지: 모델·프롬프트 바뀔 때마다 `make eval` 재실행(무료 티어 RPD 안에서 200건 × 트랙 수).
3. **대안** — (a) 공개 벤치마크(KoBEST 등) 사용: 판교어·의도·할 일 추출을 안 재서 탈락. (b) 실사용 로그로 채점: 출시 전엔 없고, 실원문은 REQ-14로 judge에 보낼 수 없어 탈락. (c) 사람 채점만: 1인이라 반복 불가, 탈락.
4. **왜** — 필드별로 "정답이 하나인 것"(용어 스팬, intentType, 할 일 개수)과 "정답이 여럿인 것"(쉬운 말, 숨은 뜻 문장)을 분리하면 대부분을 결정적으로 채점하고 judge 의존을 20%로 줄일 수 있다. 사전 용어의 `plainKo`는 REQ-14로 어차피 사전이 덮어쓰므로 **탐지만** 채점하면 된다.
5. **영향** — `eval/` 신설(14번 §16 구조): `eval/data/pangyo200.v1.jsonl`, `eval/score.py`, `eval/run.py`, `eval/cost_model.py`(REQ-13), `Makefile eval MODEL=`. 14번 §15 "평가셋" 문단을 이 절로 교체. 16번 Day 11 "평가셋 v0 50문장" 유지.
6. **검증** — judge 신뢰도: 30건을 사람이 1~5로 채점해 judge와 Spearman ≥ 0.7이면 채택, 아니면 루브릭 수정. 채점기 자체 테스트(정답을 후보로 넣으면 100점, 빈 응답이면 0점).
7. **리스크·되돌리기** — 합성 문장이 실제 판교어와 다르면 점수가 실사용과 어긋남 → 출시 후 옵트인 사용자 신고 문장(사용자가 직접 제출 동의)으로 v2 교체. judge가 Gemini면 Gemini 후보에 유리할 수 있음 → judge는 후보와 다른 계열(MLX Qwen3-8B 로컬 judge 병행)로 교차, 두 judge 차이 > 0.5점이면 사람이 본다.

### 2-1. 구성 (200문장)

| 카테고리 | 수 | 원문 유형 | 무엇을 재나 | 주요 채점 필드 |
|---|---|---|---|---|
| A 용어 | 80 | MESSAGE 1~2문장, 사전 용어 1~4개, 그중 20건은 사전에 없는 신조어 포함, 10건은 청정 한국어(`jargonCount 0`) | 탐지·스팬·쉬운 말 | `detectedTerms[]`, `resultText`, `jargonCount` |
| B 숨은 뜻 | 50 | 완곡 표현(제안형 통보, 거절, 압박) 40 + 뉘앙스 없음 10 | 의도 분류, 뉘앙스 유무·내용 | `intentType`, `nuance{note,tip}` (null 포함) |
| C 할 일 추출 | 40 | 지시·요청 메시지, 할 일 0~3개, 기한 힌트 25건(상대 표현 "내일 오전", "다음 스프린트 전") | 할 일 개수·문장·기한 | `actionItems[]{actionText, dueHint, dueAt}` |
| D 회의록 | 30 | MEETING_NOTE 300~1,500자 28건 + 4,500~5,000자 2건 | 요약·할 일·용어 종합 | 위 전부 + `summary`(dbml `translations.summary`, yml 응답엔 없음 → 채점만) |

- 직군 분포: 개발 40% / 기획 25% / 디자인 15% / 영업·HR·기타 20% (yml `JobGroup`, `TermCategory` 6종 골고루).
- 방향: `JARGON_TO_PLAIN` 180 / `PLAIN_TO_JARGON` 20(역방향은 `resultText`만 채점).
- 분할: **dev 50**(프롬프트 튜닝용) / **test 150**(고정, 프롬프트 튜닝에 안 봄). 파일 해시를 점수표에 기록.
- 생성: 사전(APPRoved terms) 발췌 + 페르소나(팀장·PM·디자이너) 프롬프트로 Gemini 무료 티어가 초안 → 개발자가 전수 검수·수정(판교 근무 경험 기준) → 30건은 손으로 작성. 중복 제거(정규화 문자열 + 3-gram Jaccard > 0.8 제거).

### 2-2. 정답 형식 — `TranslationResponse`의 AI 생성 부분집합

```json
{
  "id": "A-013", "category": "TERM", "sourceType": "MESSAGE", "direction": "JARGON_TO_PLAIN",
  "sourceText": "이번 스프린트 스코프 아웃하고 넥스트로 밀죠. 그 전에 R&R 정리해서 얼라인 쳐주세요",
  "expected": {
    "resultText": "이번 작업 범위에서 빼고 다음으로 미루죠. 그 전에 누가 뭘 할지 정리해서 합의해 주세요.",
    "jargonCount": 4,
    "intentType": "DECISION",
    "nuance": { "note": "...", "tip": "...", "confidence": null },
    "actionItems": [ { "actionText": "담당자별 역할 정리 문서 만들기", "dueHint": "다음 스프린트 시작 전", "dueAt": null } ],
    "detectedTerms": [
      { "termId": 21, "termKo": "스코프 아웃", "plainKo": "작업 범위에서 제외", "matchedText": "스코프 아웃", "startIndex": 8, "endIndex": 14 },
      { "termId": null, "termKo": "넥스트", "plainKo": "다음 스프린트", "matchedText": "넥스트", "startIndex": 19, "endIndex": 22 }
    ]
  },
  "acceptable": { "intentType": ["DECISION", "REQUEST"], "actionCount": [1, 2] },
  "meta": { "author": "human|synthetic", "reviewed": true, "split": "test", "jobGroup": "개발", "charCount": 44 }
}
```
- 필드명·의미는 yml 그대로(`DetectedTerm` L2215, `NuanceInfo` L2253, `ActionItem` L2272). 서버가 계산하는 필드(`actionId`, `sortOrder`, `isChecked`, `alertEnabled`, `inMyCards`, `confidence`, `aiModel`, `latencyMs`, `createdAt`, id류)는 정답에 없다.
- `startIndex/endIndex`는 yml 정의대로 "0부터, 끝 미포함", **Swift `String.Index`가 아니라 유니코드 스칼라 기준**으로 고정(앱 `HighlightRange` 규칙과 같은 테스트 벡터를 `packages/test-vectors/`에 공유, 14번 §16).
- `acceptable`: 정답이 둘일 수 있는 필드의 허용 집합(과잉 감점 방지).

### 2-3. 채점 — 어디에 무엇을

| 필드 | 방식 | 산식 | 이유 |
|---|---|---|---|
| `detectedTerms` 스팬 | **정확 일치(스팬 F1)** | (matchedText, start, end) 3중 일치 = TP. P/R/F1. 부분 겹침은 0.5점 변형 지표로 별도 | 형광펜은 인덱스가 틀리면 틀린 것. 서버가 재계산(14번 §5-1 6단계)하므로 "matchedText만 맞고 인덱스 틀림"도 별도 열로 기록 |
| `detectedTerms.termId` (사전 용어) | **정확 일치** | 사전 매칭 정확도 | 사전이 덮어쓰므로 `plainKo`는 채점 안 함 |
| 신조어(`termId null`) `plainKo` | **LLM-judge 1~5** | 루브릭: 뜻 정확·쉬운 말·15자 이내 | 정답 표현이 여럿 |
| `jargonCount` | 정확 일치 + 청정 한국어 오탐률 | 0인데 >0으로 낸 비율(거짓 형광펜) | 빈 상태 UX와 직결 |
| `intentType` | **정확 일치**(acceptable 집합) | 5-class accuracy + macro-F1 | 라벨이 하나 |
| `nuance` 유무 | 정확 일치 | null 여부 binary accuracy | 💭 블록 표시 여부 |
| `nuance.note/tip` | **LLM-judge 1~5** | 루브릭: 실제 의도 지적 정확성 / 팁의 실행 가능성 / 단정 과잉 없음 | 문장 자유도 |
| `actionItems` 개수 | 정확 일치(acceptable 범위) | count accuracy | 할 일이 없는데 만들면 UX 해악 |
| `actionText` | **의미 유사**(정렬 후) | 정답↔후보 헝가리안 매칭, 임베딩 cos ≥ 0.75 를 일치로(임베딩: `gemini-embedding-2` 무료 또는 로컬 MLX 임베딩) → 매칭 F1. 애매 구간(0.6~0.75)만 judge | 표현 다양, 개수는 결정적 |
| `dueHint` | 정규화 후 정확 일치 | 공백·조사 제거 문자열 | 원문 발췌라 결정적 |
| `dueAt` | 상대 표현 해석 정확도 | 기준 시각 고정(2026-09-16T10:00 KST)에서 ±1h 일치 | 알림 시각 오차는 곧 오알림 |
| `resultText` | **LLM-judge 1~5** + chrF(참고) | 루브릭: 뜻 보존 / 판교어 잔존 0 / 자연스러운 한국어 / 길이 원문 1.5배 이하 | 자유 문장 |
| `summary`(D) | LLM-judge 1~5 | 핵심 결정·할 일 포함 여부 체크리스트 | |
| JSON 유효율 | 결정적 | 스키마 파싱 성공률(Pydantic) | 파싱 실패 = 503 AI_UNAVAILABLE |
| 가드레일·거부율 | 결정적 | ②의 `guardrailViolation`, API의 refusal 비율 | 회의 텍스트에 거친 표현 |

**종합 점수(0~100)** = 스팬 F1 25 + intent 15 + nuance(유무 5 + judge 15) + actions(count 10 + text 10 + due 5) + resultText 10 + JSON 유효율 5. 가중치는 v1 고정, 바꾸면 이전 표를 다시 계산해 같이 싣는다.
**게이트(15번 §H 그대로)**: 온디바이스·자체 모델은 종합 점수가 **서버 최고 트랙의 80% 이상**이어야 라우터에 들어간다.

### 2-4. 점수표 열 (트랙마다 한 행)

`track | provider/model | promptVersion | dataset hash | 종합 | spanF1 | intentAcc | nuanceJudge | actionF1 | dueAcc | resultJudge | jsonValid% | refusal% | p50 ms | p95 ms | 입력토큰 평균 | 출력토큰 평균 | 원가/건(₩, 유료 환산) | 무료 티어 한도 대비 사용 | 오프라인 가능(Y/N) | 원문 외부 전송(Y/N) | 측정 기기·날짜`

- 원가는 REQ-13 `eval/cost_model.py`가 계산: `(입력토큰×입력단가 + 출력토큰×출력단가) × 환율`. 무료 티어여도 **유료 환산가를 항상 같이 적는다**(무료 티어 폐지 시 BM 즉시 계산). 온디바이스는 원가 0 + 배터리·시간(측정).
- 지연은 트랙별로 "무엇을 재는지" 고정: API = 서버에서 호출~응답, ②③ = 기기 위 `respond` 호출~완료(콜드 로드 별도 열).

---

## 3. 트랙별 예상 표 (전부 **[예상]**, 측정 후 §2-4 표로 대체)

| | ① Gemini Flash-Lite(무료) | ① Claude/OpenAI(BYOK) | ② Apple FM (3B, 온디바이스) | ③ MLX Qwen3-4B/8B 4bit (Mac) | ④-a Qwen3-4B LoRA (서버) | ④-b nanoGPT 자체 학습 |
|---|---|---|---|---|---|---|
| 품질(종합, 예상) | 중상 70~80 | 상 80~90 | 중 55~70 (용어·쉬운 말은 양호, 숨은 뜻·기한 해석 약함 예상) | 중 60~75 (8B가 4B보다 +5~10) | 중상 70~80 (증류 데이터 품질에 좌우) | 하 <30 |
| 한국어 판교어 이해 | 양호 | 최상 | 미지수(한국어 지원은 사실, 신조어는 측정) | Qwen3 한국어 양호 | 학습 데이터로 보강 | 없음 |
| 지연 p95(예상) | 1~3s | 2~6s | 1~4s(500자, 기기별) | 5~15s(출력 300~400 토큰, 첫 로드 5~20s) | 2~5s(GPU) / MLX 서빙 시 ③과 동일 | — |
| 원가/건(유료 환산, 2k in + 0.5k out) | ₩0 (유료 환산 ≈ $0.0019 ≈ ₩2.5, 환율 1,350 가정) | Claude/OpenAI 단가 **[확인 필요]** (사용자 부담) | ₩0 (배터리) | ₩0 (Mac 전력) | GPU 서빙비 (REQ-11 아래 0, 상시 서빙 불가) | — |
| 오프라인 | N | N | **Y** | **Y** | N | — |
| 원문 외부 전송 | **Y(Google, 학습·인간 검토 가능)** | Y(사용자 본인 키·약관) | **N** | **N** | Y(우리 서버만) | — |
| 프라이버시 등급 | 낮음(무료 티어 약관) | 중(사용자 선택) | 최상 | 최상 | 상(자사 서버) | — |
| 구현 난이도 | 낮음(1일) | 낮음(라우터 제공자 추가 0.5일) | 중(Platform 어댑터 + @Generable 스키마 + 3겹 게이트 + 폴백, 2~3일) | 중상(패키지·모델 다운로드·메모리·MAS, 3~4일) | 상(데이터 2~3k + 학습 + 평가 + 서빙, 5~8일) | 중(1일 실험) |
| 기기·OS 조건 | 서버 | 서버 | iOS/macOS 26+, Apple Intelligence 기기·설정 ON, ko 로케일 | macOS 14+ 실질 M 시리즈 8GB+(4B) / 16GB+(8B) | 서버 GPU | — |
| MEETING_NOTE 5,000자 | Y | Y | **N**(4096 토큰) | Y(컨텍스트 여유, 느림) | Y | — |
| v1.0 출시 포함 | **Y(기본)** | Y(옵션) | Y(게이트 뒤 폴백·미리보기) | N(실험 플래그) | N(실험) | N |

---

## 4. 라우팅 정책 v0

### AI-2. 서버 라우터가 결정, 앱 `TranslationEngine`은 능력 보고와 온디바이스 실행

1. **의도** — REQ-12(품질·지연·BM 동시 고려)와 REQ-14(사전 우선·인덱스 서버 재계산)를 한 곳에서 지키기. 두 클라이언트(iOS·macOS)가 각자 라우팅 규칙을 갖지 않게.
2. **비용** — 서버: `infra/ai/router.py` + 제공자 어댑터 3개(gemini, groq, byok-anthropic/openai) + circuit breaker, 2일(16번 Day 11 범위). 앱: `Domain/Services/TranslationEngine` 프로토콜 + Platform 어댑터 2개(`AppleFMTranslationEngine`, `RemoteTranslationEngine`), 2~3일(S2 Day 14 확장 또는 S5). 돈 0.
3. **대안** — (a) 앱이 전부 결정(온디바이스 우선, 실패 시 서버): 계약 v1.0으로는 온디바이스 결과를 서버에 저장할 수 없고(`TranslationRequest`에 결과 필드 없음), 사전 우선·인덱스 재검증(REQ-14)을 앱이 하게 되어 탈락. (b) 서버가 온디바이스까지 원격 제어(서버 응답에 "기기에서 하라" 지시): 왕복 1회 낭비, 오프라인 무의미, 탈락. (c) 하이브리드(앱이 능력을 헤더로 알리고 서버가 분업 지시): 맞는 방향이나 **계약 변경(헤더·요청 필드)이 필요 → v1.1**.
4. **왜** — 계약 v1.0은 제출본이라 v1.0에서 가능한 것은 "서버 안 라우팅"뿐이다. 온디바이스는 계약을 안 건드리는 자리(서버 실패 시 저장되지 않는 임시 해석, 결과 도착 전 미리보기, 평가 데이터 수집)에 먼저 넣고, v1.1에서 요청에 `clientHints`를 추가해 분업(용어·쉬운 말은 기기, 숨은 뜻·할 일은 서버)으로 넘어간다. 이 순서면 계약을 어기지 않고 S2부터 두 트랙이 동시에 실측된다.
5. **영향** — 14번 §15 "모델 라우터" 표 교체(아래 4-2), §5-1 4단계에 라우터 호출로 변경, §11 v1.1 표에 `clientHints`·`engine` 추가; 12번 §2 `Services/`에 `TranslationEngine` 추가, §13 백로그에 v1.1 항목 추가; 15번 §H 표 갱신; ADR 신규 `0005-ai-router-and-engine-split.md`.
6. **검증** — 라우터 단위 테스트(기기·작업·예산 조합 → 선택 엔진 표 전수), 평가셋 점수표가 라우터 설정 파일(`router.yml`)과 일치하는지 CI 검사(설정의 1순위 모델 점수 ≥ 폴백 점수), 앱 `TranslationEngine` Fake로 VM 테스트(availability 3종 × 네트워크 2종).
7. **리스크·되돌리기** — 무료 티어 한도 초과가 잦으면(429 > 5%/일) 라우터가 BYOK·온디바이스 비중을 올리고 PO에 유료 전환 결정 요청. 온디바이스 점수가 80% 게이트 미달이면 ②는 미리보기에서도 빼고 평가 수집만 남긴다(15번 §H 되돌리기 조건).

### 4-1. 결정 트리 v0 (서버 `router.py`)

```
입력: task ∈ {TERM_PLAIN, NUANCE, ACTIONS, MEETING_SUMMARY}, sourceType, charCount,
      user.byokProvider?, budget(일일 무료 한도 잔량, 사용자 분당 30), clientHints(v1.1: engineCaps)

0. 사전 매칭(trie) → 사전에 있는 용어는 AI 결과와 무관하게 확정 (REQ-14)
1. 같은 사용자·원문·방향 10분 내 결과 있음 → 재사용, AI 호출 0 (14번 §5-1)
2. task별 후보 순서
   TERM_PLAIN       : [clientHints.appleFM(v1.1) → 기기] → gemini-flash-lite → groq(qwen3) → gemini-flash
   NUANCE           : byok(claude|openai, 키 있을 때만) → gemini-flash → gemini-flash-lite
   ACTIONS(+dueAt)  : gemini-flash → byok → gemini-flash-lite   (dueAt 계산은 규칙 코드, AI는 dueHint만)
   MEETING_SUMMARY  : byok → gemini-flash (5,000자 초과는 요약 먼저, 14번 §5-2). 온디바이스 후보 없음(4096 토큰)
3. 예산 게이트: 후보의 무료 한도 잔량 < 10% → 다음 후보. 전부 소진 → 503 AI_UNAVAILABLE + Retry-After (14번 §7)
4. circuit breaker: 30초 내 2회 실패 → 해당 제공자 60초 차단(14번 §15)
5. 결과 후처리: 인덱스 재계산, 사전 덮어쓰기, `ai_model` 기록(AI-3), 지연·토큰 지표
```
- 요청 하나를 두 제공자로 나눠도 된다(14번 §15). v0 기본은 **한 호출에 4출력 JSON**(무료 RPD 절약), 점수표에서 "분할 호출"이 +5점 이상이면 분할.
- **Claude가 §15에서 1순위였던 자리는 BYOK 조건부로 내려간다**(REQ-11). 키가 없는 사용자(대부분)는 Gemini Flash가 숨은 뜻 1순위.

**앱 측 결정 트리 (`TranslationEngine` 선택, Composition에서 조립)**
```
if #available(iOS 26, macOS 26, *), SystemLanguageModel.default.availability == .available,
   SystemLanguageModel.default.supportsLocale(), sourceType == MESSAGE, charCount ≤ 500
      → appleFM 사용 가능 (capability = .onDeviceTermPlain)
else  → capability = .none

v1.0 동작:
  - 온라인: 서버 호출이 진실. appleFM은 (a) 결과 도착 전 "쉬운 말 미리보기"(형광펜 없음, D-7과 같은 규칙) (b) 서버 503/오프라인 시 "임시 해석(저장 안 됨)" 표시 (c) 설정 옵트인 시 평가 로그(점수만, 원문 없음)
  - 오프라인: appleFM만. 결과는 저장되지 않으며 화면에 "오프라인 임시 해석" 배지
v1.1 동작:
  - 요청에 clientHints{engineCaps:[APPLE_FM_TERM_PLAIN], onDeviceResult?} → 서버가 TERM_PLAIN을 건너뛰고 인덱스만 재검증
```
- 결정 기준(기기·OS·작업·네트워크·예산) 중 **기기·OS·네트워크는 앱**이, **작업 유형·예산·제공자**는 서버가 안다. 이것이 책임 분리의 선이다.
- MLX(③)는 macOS 앱에서 `.experimentalMLX` 플래그(DEBUG 빌드 또는 숨은 설정)로만 `TranslationEngine` 구현체를 바꿔 끼운다. 라우터·계약 무변경.

### 4-2. 14번 §15 라우터 표 교체본

| 작업 | 1순위 | 2순위 | 3순위 | 온디바이스(v1.1) | 비고 |
|---|---|---|---|---|---|
| 용어 탐지 + 쉬운 말 | Gemini Flash-Lite(무료) | Groq Qwen3(무료, 약관 확인) | Gemini Flash | Apple FM(게이트 통과 시) | 값싼 작업, 온디바이스 1순위 이전 후보 |
| 숨은 뜻 | BYOK(Claude/OpenAI) | Gemini Flash | Gemini Flash-Lite | 평가 후 결정 | 품질 작업 |
| 할 일 추출 | Gemini Flash | BYOK | Flash-Lite | 평가 후 결정 | dueAt는 규칙 코드 |
| 회의록 요약 | BYOK | Gemini Flash | — | 없음 | 5,000자 |
| 실력 테스트 오답 | Flash-Lite | 규칙(사전 섞기) | — | — | 캐시 |

### AI-3. 엔진 출처 기록 — v1.0 `aiModel` 규약, v1.1 `engine` 객체

1. **의도** — REQ-12·13: 어떤 결과가 어느 엔진(트랙·모델·버전·위치·프롬프트)에서 나왔는지 없으면 원가·품질을 사후 분석할 수 없다. 사용자에게도 "온디바이스에서 처리됨"을 보여 줄 수 있어야 한다(프라이버시 가치).
2. **비용** — v1.0: 서버 한 줄(문자열 조합) + 앱 파싱 함수 1개. v1.1: yml 스키마 1개 + dbml 컬럼 4개 + 마이그레이션.
3. **대안** — (a) 지금 계약에 `engine` 객체 추가: 계약 v1.0 고정 원칙 위반, 탈락. (b) 서버 로그에만 기록: 앱이 표시 못 하고 사용자별 분석이 조인 필요, 탈락. (c) `aiModel` 문자열에 규약 인코딩(선택): 계약 무변경, 50자 제한 안.
4. **왜** — `aiModel`은 yml에 `type: string`(예시 `claude-opus-5`), dbml `ai_model varchar(50) not null`이라 어떤 문자열이든 계약 안이다. 규약 `{track}/{model}@{modelVer}#{promptVer}` — 예: `api/gemini-3.5-flash-lite#p3`(29자), `fm/apple-26.4#p2`(16자), `mlx/qwen3-4b-4bit#p2`, `sllm/qwen3-4b-lora-r16-v3#p1`, `dict/only`(사전만으로 끝난 경우). **50자 이내 검증을 서버 테스트로 강제**.
5. **영향** — 14번 §5-1 8단계 "ai_model 저장"에 규약 명시, 12번 `Data` DTO→Entity 매핑에 `EngineTag.parse`, 계약 v1.1 백로그(14번 §11, 12번 §13)에 `engine{track, provider, model, modelVersion, location: SERVER|DEVICE, promptVersion}` + `location`을 앱이 "기기에서 처리됨" 배지로 표시. dbml v1.1: `engine_track`, `engine_location`, `prompt_version` 컬럼(또는 json 1개).
6. **검증** — 서버: 모든 201 응답의 `aiModel`이 정규식 `^(api|fm|mlx|sllm|dict)/[a-z0-9.-]+(@[a-z0-9.-]+)?#p\d+$`와 50자 이내. 앱: 파싱 왕복 테스트. 대시보드: `ai_model` 그룹별 지연·실패율.
7. **리스크·되돌리기** — 규약이 지저분하다는 리뷰가 오면 v1.1 `engine` 객체 도입과 함께 `aiModel`은 표시용 모델명만 남긴다(호환 유지: 문자열).

### AI-4. Gemini 무료 티어와 실사용자 원문 (PO 에스컬레이션)

1. **의도** — REQ-11(무료 티어만)과 제품 원칙 "기밀"(REQ-14, 12번 §12 위협 모델) 사이의 충돌을 명시하고 결정 주체를 정하기.
2. **비용** — 결정 자체는 0. 선택지별 비용은 아래.
3. **대안** — (a) 무료 티어에 실사용자 원문 전송 + 앱 내 고지("무료 AI 제공자가 품질 개선에 사용할 수 있음", 옵트아웃 시 온디바이스만): 돈 0, 신뢰 비용. (b) 실사용자 원문은 BYOK·온디바이스로만, 무료 티어는 개발·평가·합성 데이터 전용: 키 없는 iOS 17~25 사용자는 해석 불가 → 제품 불성립. (c) 유료 티어 전환(Flash-Lite ₩2.5/건 예상): REQ-11 위반(개발 단계), 출시 시점 재검토 대상.
4. **왜** — 약관이 "Do not submit sensitive, confidential, or personal information to the Unpaid Services"라고 명시하므로 AI 파트장 단독으로 (a)를 확정할 수 없다. **권고: 개발·테스트(S0~S5)는 (b)+합성 데이터, TestFlight 베타부터는 (a)의 고지·옵트아웃과 함께 운영하고, REQ-13 계산기로 (c)의 손익분기 가격을 S5에 제시**. 최종은 PO/PM.
5. **영향** — REQ-11 각주 추가 제안(무료 티어 데이터 사용 조항 인지), 12번 §12 위협 모델 표에 "AI 제공자" 열 추가, A-09 설정에 "온디바이스만 사용" 토글(v1.1 후보), 앱 심사 Privacy 라벨.
6. **검증** — 베타 사용자 고지 문구 A/B 없음(1인). 옵트아웃 비율·해석 실패율을 Amplitude 속성(bool)로만.
7. **리스크·되돌리기** — 약관 변경 시 즉시 재평가. 기업 고객 문의가 생기면 (b)를 기본으로 뒤집고 BYOK·온디바이스를 전면에.

---

## 5. 자체 모델 트랙 실험 계획

### AI-7. Qwen3 LoRA 우선, nanoGPT는 1일 학습 실험

1. **의도** — REQ-10 ④ 비교 의무 + 포트폴리오(SKALA LoRA 경험 연결) + 장기 BM(월 해석 > 50만 건 시 자체 서빙, 15번 §H).
2. **비용** — 시간: 데이터 3일(합성 2,000 + 증류 800 + 검수), 학습 Kaggle 무료 30h/주 안에서 4B QLoRA 2~4h × 3회 **[예상]**, 평가 0.5일, MLX 변환·Mac 서빙 0.5일. 돈 0(REQ-11). 저장: HF 개인 리포(공개 시 데이터 라이선스 확인).
3. **대안** — (a) nanoGPT 처음부터: §1-④ 사실로 한국어 지시 모델 불가능, **학습·설명 목적 1일**로만 남김. (b) 8B LoRA: 무료 T4 16GB에서 QLoRA 가능하나 시간 2배, MLX 8B-4bit 4GB+로 iPad 불가 → 4B 먼저, 4B가 게이트 80%에 5점 이내로 근접하면 8B. (c) Apple Adapter Toolkit: 어댑터 160MB·OS 모델 버전마다 재학습·**Toolkit 26.0.0이 마지막이며 27 비호환** → 유지 비용이 1인에겐 과함, **개발 Mac이 32GB 이상일 때만 1회 실험 [확인 필요]**.
4. **왜** — 같은 200문장 평가로 "API 대비 몇 점"이 나와야 자체 모델의 존재 이유(비용 0·오프라인·기밀)가 수치로 남는다. LoRA는 기반 모델의 한국어·지시 능력을 그대로 쓰므로 3천 개 데이터로 승부가 되고, 결과물이 그대로 ③(MLX)에 꽂힌다(14번 §15 5단계 "끝그림").
5. **영향** — `eval/finetune/`(데이터 생성·검수·학습 노트북·변환 스크립트), 14번 §15 파인튜닝 트랙 갱신, ADR `0006-sllm-track.md`, 라우터 `sllm` 제공자 슬롯(기본 off).
6. **검증** — 성공 기준: test 150에서 종합 ≥ 서버 최고의 80%, JSON 유효율 ≥ 98%, 스팬 F1 ≥ 0.85, MLX 4bit 변환 후 점수 하락 ≤ 3점, Mac p95 ≤ 8s. 데이터 누수 검사: test 150과 학습 데이터 3-gram 중복 0.
7. **리스크·포기 조건** — 3회 학습 후 종합 < 60% 또는 JSON 유효율 < 90% → 트랙 종료, 문서에 수치와 원인(데이터 부족·태스크 난이도)을 남기고 ②③만 유지. 무료 GPU 정책 변경으로 주 10h 미만이면 중단. 학습 데이터에 실사용자 원문은 **절대 넣지 않는다**(합성·검수·증류만).

### 5-1. 데이터
| 출처 | 수 | 방법 | 검수 |
|---|---|---|---|
| 사전 기반 합성 | 2,000 | 사전 용어 × 상황 템플릿 × 페르소나 → Gemini 무료 티어 생성(기밀 없음) | 10% 표본 사람 검수 + 자동 규칙(용어 스팬 존재, JSON 유효) |
| 증류 | 800 | 합성 원문에 대해 서버 최고 트랙(BYOK 있으면 Claude) 출력 → 사람 수정 | 전수 스팬 재계산 |
| 손 작성 | 200 | 개발자 경험 기반 | 전수 |
| **제외** | — | 평가셋 test 150, 실사용자 원문 | 중복 검사 |

### 5-2. nanoGPT vs LoRA 선택 기준(기록용)
| 기준 | nanoGPT(처음부터) | LoRA(Qwen3) |
|---|---|---|
| 필요 데이터 | 한국어 사전학습 수십 GB + 지시 데이터 | 지시 데이터 3천 |
| 무료 GPU로 가능 | 124M조차 8×A100 4일 → 불가 | T4 1장 수 시간 |
| 학습 가치 | 트랜스포머 내부 이해(포트폴리오 설명력) | 실무 파이프라인 |
| 결정 | **1일 실험**: shakespeare_char 설정으로 판교어 문장 코퍼스(합성 3천 문장) char-level 학습 → "다음 글자 예측"만 시연, 점수표에는 "측정 불가(태스크 미달)"로 기록 | **본 트랙** |

### 5-3. 무료 GPU 예산
- Kaggle 주 30h(세션 9h) 우선, Colab은 보조(한도 비공개). 3주 × 30h = 90h 예산 중 학습 3회(≤12h) + 평가·변환(≤6h) = 18h 사용, 나머지는 여유.
- 정책 수치는 실험 시작일에 재확인해 `eval/finetune/README.md`에 날짜와 함께 기록.

---

## 6. 프라이버시 불변식(REQ-14)을 트랙별로 지키는 법

### AI-8. 엔진별 데이터 흐름 표를 불변식에 추가

1. **의도** — 12번 §10 불변식("sourceText·transcript·extractedText·오디오·이미지는 어떤 SDK로도 나가지 않는다")은 관측 SDK 기준이다. 해석 엔진은 원문을 **받는 것이 일**이므로 "어디까지, 무슨 조건으로" 가는지를 트랙별로 못 박아야 한다.
2. **비용** — 문서 표 1개, 서버 테스트 2개(로그·judge 경로에 원문 없음), 앱 테스트 1개(온디바이스 경로에서 네트워크 호출 0).
3. **대안** — (a) "AI 제공자는 예외"로 두루뭉술: 무료 티어 약관 문제를 못 잡음, 탈락. (b) 모든 원문을 온디바이스만: iOS 17~25 사용자 배제, 탈락.
4. **왜** — 불변식은 검증 가능해야 한다. 표가 있으면 각 줄이 테스트 하나가 된다.
5. **영향** — 12번 §10·§12 표에 열 추가, 14번 §6 "개인정보" 문단 확장, App Privacy 라벨.
6. **검증** — 아래 표의 "검증" 열.
7. **리스크·되돌리기** — 제공자 약관 변경 시 표 갱신이 결정보다 먼저.

| 트랙 | 원문이 가는 곳 | 저장 | 학습에 쓰임 | 지키는 방법 | 검증 |
|---|---|---|---|---|---|
| 사전 매칭 | 서버 메모리 | DB(설계) | N | — | — |
| ① Gemini 무료 | Google(무료 티어: 개선·인간 검토 가능) | Google 측 미상 | **Y(약관)** | AI-4 결정(고지·옵트아웃 또는 유료) 전엔 **합성 데이터만**. 프롬프트에 userId·프로젝트명·회의 제목 넣지 않음(원문만) | 서버 테스트: 프롬프트 빌더 출력에 식별자 없음. 개발 환경 플래그 `AI_REAL_USER_TEXT=false` 기본 |
| ① BYOK | 사용자가 고른 제공자 | 제공자 약관 | 제공자 약관 | 키는 서버 `.env`가 아니라 **사용자별 암호화 저장(v1.1 계약 필요)** 또는 v1.0은 개발자 본인 키만(테스트) | 키 유출 스캔(gitleaks), 키 저장 컬럼 없음(v1.0) |
| ② Apple FM | 기기 밖으로 안 나감 | 없음(세션 메모리) | N | `AppleFMTranslationEngine`은 `URLSession` 의존 0. 평가 로그는 점수·토큰 수만 | 앱 테스트: 온디바이스 경로에서 네트워크 Spy 호출 0. Instruments로 토큰 확인 |
| ③ MLX | 기기 밖으로 안 나감(모델 다운로드만 HF) | 없음 | N | 모델 다운로드는 첫 실행 1회, 원문과 무관 | 같은 네트워크 Spy 테스트 |
| ④ 자체(서버) | 우리 서버 GPU/vLLM | DB(설계) | **N — 실사용자 원문은 학습 데이터에서 영구 제외** | 학습 파이프라인 입력은 `eval/finetune/data/`만, DB 접근 코드 없음 | CI: 학습 스크립트에 DB 드라이버 import 금지(`import-linter`) |
| LLM-judge(평가) | Gemini 무료 / 로컬 MLX | — | Y(무료) | **judge 입력은 평가셋(합성)만**. 실사용자 원문 채점 금지 | `eval/`이 DB·API 서버에 접근 불가(네트워크 분리) |
| 공통 | 로그·Sentry·지표 | — | — | 14번 §6: 요청 바디 로깅 금지, `send_default_pii=False`, 지표에 원문 금지. 라우터 지표는 `ai_model`·지연·토큰 수·실패 코드만 | 로그 grep 테스트(고정 문장 해석 후 로그에 없음) |

- 12번 §12 표의 "SDK" 열과 별도로 **"AI 엔진" 열**을 추가: `sourceText → 서버(설계) → 라우터가 고른 엔진(위 표)`. `transcript`는 MEETING_SUMMARY 경로만, 오디오·이미지는 어떤 엔진에도 안 감(D-6, 오디오는 STT만).

---

## 7. S2 이전에 끝내야 할 것과 순서

S2는 10/5(Day 11 "AI 라우터 … 평가셋 v0 50문장 점수표"). 그 전(S0·S1 병행, 서버 날이 아닌 날의 자투리)에 아래를 끝낸다. 순서는 의존성 순.

| # | 언제 | 무엇 | 완료 기준 | 의존 |
|---|---|---|---|---|
| 1 | 9/22~9/23 (S0 Day 1~2 자투리) | **AI Studio에서 무료 티어 실제 RPM/RPD 캡처**, Groq 약관·한도 확인, Gemini 응답 스키마 필드명 확인 → `eval/limits.md` | 표에 날짜·수치·스크린샷 경로 | 없음 |
| 2 | 9/24 | 평가셋 스키마(§2-2) + `score.py` 뼈대 + 채점기 자기 테스트(정답→100, 빈→0) | `make eval` 더미 통과 | 1 |
| 3 | 9/25~9/26 | **평가셋 v0 50문장**(카테고리 20/12/10/8) 합성+검수, dev 분할 | jsonl 커밋, 해시 기록 | 2 |
| 4 | 9/27(주말, 선택) | Foundation Models 스파이크: 개발 Mac(macOS 26)에서 `@Generable` 4출력 스키마 토큰 수 측정(`tokenCount(for:)`), 한국어 500자 1건 응답·지연·가드레일 확인 | 수치 5개(스키마 토큰, 입력 토큰, 출력 토큰, 지연, 오류 유형) | 3 |
| 5 | 9/28~10/2 (S1, 서버 날 자투리) | 라우터 설정 파일 `router.yml` v0(4-2 표), 제공자 어댑터 인터페이스(`domain/services/ai.py`), circuit breaker 단위 테스트 | 테스트 초록, Day 11에 Gemini만 꽂으면 되는 상태 | 1 |
| 6 | 10/2 | ADR 0005(AI-2·AI-3), REQ 대장 갱신 제안(REQ-11 각주, AI-4 PO 결정 요청), 14번 §15 교체본 PR | 협의체 레드팀 검토 | 5 |
| 7 | 10/5 (Day 11) | Gemini Flash-Lite/Flash + Groq로 v0 50문장 점수표 1차 | 점수표 커밋 | 3,5 |
| 8 | S2 중 (Day 14 확장) | 앱 `TranslationEngine` 프로토콜 + `RemoteTranslationEngine` + `AppleFMTranslationEngine`(게이트 3겹, 미리보기·오프라인 임시 해석) | VM 테스트: availability 3종 × 네트워크 2종 | 4 |
| 9 | S3~S4 자투리 | 평가셋 v1 200문장 완성, judge 신뢰도 30건, ② 점수 측정 | 점수표 v1 | 7,8 |
| 10 | S4 말 | MLX 실험 플래그(macOS DEBUG), Qwen3-4B-4bit 점수·지연 측정 | 점수표 행 추가 | 9 |
| 11 | S5 | REQ-13 `cost_model.py` + 대시보드 수치(측정값 반영), AI-4 PO 결정 반영, v1.1 `clientHints`·`engine` 초안(Day 30 "계약 v1.1 초안 PR") | 손익분기 가격 산출 | 7,9 |
| 12 | S6 이후(v1.0 뒤) | LoRA 트랙(§5), Apple 어댑터 1회 실험(32GB 조건) | 성공/포기 기준 판정 | 9 |

**S2 진입 게이트**: 1·2·3·5가 끝나 있어야 Day 11이 하루에 끝난다. 4·8은 REQ-02 재결정(T-C2 → 17+)과 맞물리므로 iOS 파트와 `@available` 게이트 규칙을 공유한다.

---

## 8. 다른 파트에 넘기는 질문·요청

| 대상 | 내용 |
|---|---|
| PO/PM | AI-4: 무료 티어 약관("기밀 제출 금지·개선에 사용·인간 검토")과 실사용자 원문 — 고지·옵트아웃 / BYOK·온디바이스 전용 / 유료 전환 중 결정. 손익분기 수치는 S5에 제공 |
| iOS / macOS·iPad | REQ-02 재결정 시 `@available(iOS 26, macOS 26, *)` 게이트 규칙과 `Platform/AppleFMTranslationEngine` 배치 합의. macOS 앱 MLX 실험 플래그 자리(DEBUG 스킴). 개발 Mac 메모리(32GB?) 확인 |
| Backend | `router.py` 슬롯(gemini, groq, byok, sllm, dict), `ai_model` 규약 검증 테스트, 프롬프트 빌더에 식별자 미포함 테스트, `eval/`의 네트워크 분리 |
| QA | 평가셋 judge 신뢰도 30건 사람 채점(개발자 외 1인 있으면 교차), 청정 한국어 오탐 케이스 |
| 레드팀 | 이 문서의 [예상] 수치가 결정 근거로 쓰이지 않았는지(모든 라우팅 결정이 §2-4 표에 묶여 있는지) 검증 |

## 9. 출처 목록 (확인일 2026-09-19)
- Apple: `/documentation/foundationmodels/{systemlanguagemodel, generable, managing-the-context-window, supporting-languages-and-locales-with-foundation-models, languagemodel, systemlanguagemodel/guardrails, systemlanguagemodel/usecase, systemlanguagemodel/contextsize, systemlanguagemodel/availability-swift.enum/unavailablereason, languagemodelsession/generationerror}`; developer.apple.com/apple-intelligence/foundation-models-adapter; machinelearning.apple.com "Introducing the Third Generation of Apple's Foundation Models"(2026-06-08); support.apple.com/121115.
- MLX: github.com/ml-explore/mlx-swift-lm (README, using.md, SKILL.md, model-container.md, MLXGuidedGeneration README), github.com/ml-explore/mlx-swift (Package.swift, running-on-ios.md, troubleshooting.md) — Context7 경유.
- Google: ai.google.dev/gemini-api/docs/pricing, /gemini-api/terms, /gemini-api/docs/rate-limits(수치 없음).
- nanoGPT: github.com/karpathy/nanoGPT README.
- 3차 자료(변동·확인 필요 표기): Gemini 무료 RPD, Groq 한도, Colab/Kaggle 한도, Apple Intelligence 기기 목록 요약.
