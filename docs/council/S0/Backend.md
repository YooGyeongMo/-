# Backend 파트장 결정서 — AI 엔진 라우터 · 비용 집계 · 알림 스키마 · iOS 17 대응 · 계약 v1.1 · S0 영향

> 협의체 1차 세션 (2026-09-19). 작성: Backend 파트장 에이전트.
> 근거 문서: `docs/REQUIREMENTS.md`(REQ-04, 10~14, 20, 27, 31), `docs/design/14_시스템_설계서.md` §1·§3·§5-1·§5-2·§5-5·§6·§7·§8·§9·§10·§11·§15·§16·§17, `docs/design/12_앱_아키텍처_설계.md` §8-2(D-19)·§10·§12·§13, `docs/design/15_기술_트레이드오프_결정기록.md` T-A2·T-B7·T-C2·H, `docs/16_실행계획.md` §3·§4, `contracts/openapi.yml` v1.0, `contracts/db.dbml`, `services/api/app/main.py`, `infra/docker-compose.yml`, `infra/deploy/blue-green.sh`, `docs/adr/0003`.
> 고정 제약: 계약 v1.0은 제출본(변경은 v1.1 백로그로만), 무료 티어만(REQ-11), 원문·받아쓰기·오디오는 로그·Sentry·SDK로 안 나감(REQ-14, 14번 §6·§13), 저장소 파일 수정 없음.
> 사실 확인: Apple API는 mcp__sosumi로 확인(날짜 2026-09-19). 확인 못 한 수치는 **"확인 필요"**로 표기.

---

## 0. 한 장 요약 (결정 목록)

| # | 결정 | 한 줄 | 계약 영향 | 착수 시점 |
|---|---|---|---|---|
| B-0 | 서버 패키지는 **컨텍스트 우선** 폴더(`app/{identity,workspace,decode,learning,notify}/…`) | 14번 §3(층 우선)과 §17(컨텍스트 격리)을 하나로 | 없음 | S0 Day 4 |
| B-1 | `decode` 안의 **EngineRouter**: `Engine` Protocol + 어댑터 5종 + Redis 한도 카운터 + Redis circuit breaker + 작업별 폴백 사슬 + 호출마다 `ai_usage` | REQ-10~13 충족, §15 재작성 | v1.1 `engineHint`/`engine`(선택 필드) | S2 Day 11 (뼈대는 Day 4) |
| B-2 | **비용 파이프라인**: `ai_usage`(호출 단위) → 일 배치 `usage_daily` → `eval/cost_model.py` 입력 CSV + `eval/prices.yml` | REQ-13 "코드로, 측정값 갱신" | dbml v1.1 테이블 2개 | 마이그레이션 0002 (Day 11), 배치 Day 18 |
| B-3 | **알림 payload v1**: `aps` + 평면 커스텀 키(`v,type,…Id,notificationId`), `DevicePlatform`에 `MACOS`·`WATCHOS`, 발송은 IOS+WATCHOS 토큰 전부(시스템이 한 곳만 울림) | REQ-04 | v1.1 `PushPayload` 스키마·enum 2개 | Day 18 (enum은 Day 4 마이그레이션에 미리) |
| B-4 | **iOS 17~25**: STT는 어차피 서버가 진실(D-7)이라 STT 부하 불변, 늘어나는 건 "쉬운 말+용어" AI 몫 → 서버 STT 1순위 Groq Whisper(무료 8h/일), 큐 3개 분리, 사용자 일 한도 + 엔진 예산 게이트 + 사전-only 강등 | REQ-02 | v1.1 `engine` 값 `NONE`(강등 표시) | Day 11·17 |
| B-5 | 계약 **v1.1 통합 백로그 15건**(기존 9 + 신규 6), 전부 하위 호환(추가만) | 12번 §13 + 14번 §11 통합 | — | S5 Day 30 초안 PR |
| B-6 | S0 Day 4~5에 지금 정할 것 4가지(폴더, ENUM 전략, `.env.example` 키, Redis 키 규약) — 나머지는 S2/S3로 미룸 | | | Day 4·5 |

---

## B-0. 서버 패키지 구조: 컨텍스트 우선 (전제 결정)

1. **의도**: 14번 §3은 `api/domain/usecases/infra` 층 우선이고, §17은 컨텍스트끼리 import 금지(`import-linter`). 두 규칙을 한 폴더 구조로 동시에 만족시켜 EngineRouter를 "`decode` 안"에 두라는 요구(과제 1)를 코드로 강제한다.
2. **비용**: 폴더 이동뿐(코드 아직 없음). import-linter 계약 파일 1개(~30줄). 유지보수: 컨텍스트 5개 × 층 4개 = 폴더 20개, 초기엔 빈 폴더가 많다.
3. **대안**
   - 층 우선(§3 그대로) + import-linter로 모듈명 패턴 규제 → 탈락: `infra/ai/router.py`가 `decode`의 것인지 `learning`(퀴즈 오답 생성)의 것인지 폴더로 안 보임. 린터 규칙이 정규식 지옥이 됨.
   - 컨텍스트별 별도 패키지(`packages/decode` 등) → 탈락: 1인, 배포 단위 3개(api/worker/scheduler)가 다 같은 코드를 쓰므로 패키지 분리는 §17 "분리 조건" 전엔 과함.
4. **왜**: MSA 분리(§17 조건)가 "폴더 하나를 옮기는 것"이 되려면 컨텍스트가 최상위여야 한다. 층은 컨텍스트 안에서 유지하므로 §3의 의존 방향(`api → usecases → domain ← infra`)은 그대로다.
5. **영향**: 14번 §3 트리 갱신, §17에 "폴더 = 컨텍스트" 한 줄. 코드: `services/api/app/{identity,workspace,decode,learning,notify}/{api,domain,usecases,infra}/`, 공용은 `app/core`. `learning`의 퀴즈 오답 생성은 `decode`의 EngineRouter를 **읽기 전용 인터페이스**(§17 허용 통신)로 쓴다: `decode/domain/services/engine_port.py`의 Protocol만 import.
6. **검증**: CI `import-linter`(layers + forbidden 계약). `/levels`가 `identity`에 있고 `decode`를 import하지 않음을 린트가 보장.
7. **리스크·되돌림**: 빈 폴더가 많아 "왜 이렇게 넓냐"는 인상 → README 한 줄. 되돌리는 조건: 없음(폴더 이동은 언제든 싸다).

---

## B-1. AI 엔진 라우터 (`decode` 컨텍스트, REQ-10~13)

### 1. 의도
- 엔진 후보 4트랙(REQ-10: 외부 API / Apple Foundation Models / MLX / 자체 sLLM)을 **하나의 Protocol 뒤**에 두고, 평가셋 점수표(§15)로만 순서를 바꾼다.
- 개발·테스트는 **무료 티어만**(REQ-11), 배포는 품질·지연·MAU당 원가를 같이 보는 라우팅(REQ-12).
- 요청마다 어느 엔진·토큰·지연·비용이 들었는지 남겨 REQ-13 비용 모델의 **측정값 입력**이 되게 한다.
- 원문은 라우터를 지나도 **DB 외엔 어디에도 남지 않는다**(REQ-14, 14번 §6).

### 2. 비용
| 항목 | 값 |
|---|---|
| 돈 | 0원. gemini_free는 Google AI Studio 무료 티어(모델별 RPD/RPM 상이, 2026-09 기준 Flash-Lite 계열 500 RPD·Flash 계열은 훨씬 적음 — **확인 필요**, 자주 바뀜). openai_key/anthropic_key는 키가 `.env`에 있을 때만 활성, 없으면 `health()=UNCONFIGURED`로 자동 제외. vllm_local은 스팟 GPU 실험(§15 파인튜닝 트랙, 프로덕션 기본 아님). |
| 시간 | Day 11 하루(§4 계획 그대로) + Day 4에 뼈대 30분. |
| 복잡도 | 파일 ~10개(Protocol 1, 어댑터 5, 정책 1, 한도 1, 브레이커 1, 기록 1). 어댑터 하나당 ~80줄. |
| 유지보수 | 무료 한도 수치는 코드가 아니라 설정(`MWONMAL_AI_QUOTA_*`)에. 가격표는 `eval/prices.yml`(버전 문자열). |

### 3. 대안
| 대안 | 왜 탈락 |
|---|---|
| **LiteLLM/LangChain 같은 라우팅 라이브러리** | 의존성 수백 개, 원문이 라이브러리 로깅·콜백을 타는 경로가 생겨 REQ-14 불변식을 코드 리뷰로 증명하기 어려움. 우리 어댑터는 5개뿐. |
| **단일 유료 모델(14번 §1 표의 "Claude API claude-opus-5")** | REQ-11 위반(유료 결제 없음). §1 표는 §15와도 이미 모순 → §1 표를 "EngineRouter(§15)"로 고쳐야 함. |
| **앱이 직접 외부 API 호출(서버 우회)** | 키가 앱에 들어감(REQ-27), 검수 사전 우선·인덱스 재계산(REQ-14)을 서버가 못 함. |
| **프로세스 메모리 circuit breaker** | uvicorn 2 workers × 블루·그린 2세트 + ARQ 워커 = 최소 5개 프로세스가 각자 다른 상태를 봄 → Redis로. |

### 4. 왜
라우터는 "제공자를 갈아끼울 수 있게, 평가셋 없이는 바꾸지 않는다"(§15 S-3)를 코드로 만든 것이다. Protocol 하나·어댑터 5개·정책 표 하나면 REQ-10의 4트랙이 전부 같은 자리에 꽂히고, 앱이 온디바이스로 처리했을 때(`engineHint`)도 같은 검수·인덱스 단계(§5-1 5·6단계)를 지나므로 "서버가 인덱스를 재검증한다"는 규칙이 유지된다. 한도·브레이커·기록을 Redis/MySQL에 두면 블루·그린 전환(ADR-0003) 중 두 버전이 같은 카운터를 공유해 무료 한도를 두 배로 쓰는 사고가 없다.

### 5. 설계 (영향 파일: `services/api/app/decode/…`, 14번 §5-1 4단계·§15 재작성)

#### 5-1. 파일 배치
```
app/decode/
  domain/
    models.py            TranslationDraft, TranslationResult(엔진 무관 값 객체), EngineCall(관측 레코드)
    prompts.py           프롬프트 템플릿 + PROMPT_VERSION (텍스트는 로그 금지, 버전·해시만 기록)
    services/engine_port.py   Engine / SttEngine Protocol, EngineTask, EngineHint (learning이 import하는 유일한 파일)
    rules/index_check.py      startIndex/endIndex 재계산(§5-1 6단계) — 순수 함수, test-vectors 공유
  usecases/translate.py       §5-1 1~8단계. 4단계만 router.run(task, ...) 호출
  infra/engines/
    router.py            EngineRouter(policy, quota, breaker, recorder)
    policy.py            작업별 폴백 사슬(설정에서 읽음)
    quota.py             Redis 무료 한도 카운터
    breaker.py           Redis circuit breaker
    recorder.py          ai_usage INSERT (비동기, 실패해도 해석은 성공)
    gemini_free.py  openai_key.py  anthropic_key.py  vllm_local.py  none.py
    stt/ groq_whisper.py  gemini_audio.py  whisper_local.py   (B-4)
```

#### 5-2. Protocol (Python 3.12, 14번 §1 스택)
```python
# app/decode/domain/services/engine_port.py
from typing import Protocol, Literal
from dataclasses import dataclass

EngineId = Literal["gemini_free", "openai_key", "anthropic_key", "vllm_local", "none", "on_device"]
EngineTask = Literal["DETECT_PLAIN", "NUANCE_ACTIONS", "QUIZ_DISTRACTOR", "MEETING_SUMMARY"]
EngineHint = Literal["SERVER", "ON_DEVICE_PARTIAL", "ON_DEVICE_FULL"]   # 계약 v1.1 TranslationRequest.engineHint
Health = Literal["UP", "DEGRADED", "DOWN", "UNCONFIGURED"]

@dataclass(frozen=True, slots=True)
class EngineRequest:
    task: EngineTask
    source_text: str                 # 메모리에만. __repr__ 에서 제외(로그 유출 방지)
    direction: str                   # JARGON_TO_PLAIN | PLAIN_TO_JARGON
    dictionary_excerpt: tuple[str, ...]   # 사전 발췌(프롬프트 캐시 대상)
    max_output_tokens: int
    timeout_s: float                 # §5-1: 총 8초 안에서 작업별 분배
    def __repr__(self) -> str: return f"EngineRequest(task={self.task}, chars={len(self.source_text)})"

@dataclass(frozen=True, slots=True)
class TranslationResult:             # 엔진 무관. usecase가 사전 덮어쓰기·인덱스 재계산 후 DB 모델로 변환
    result_text: str | None
    intent_type: str | None
    nuance: dict | None              # {note, tip, confidence}
    action_items: tuple[dict, ...]
    detected_terms: tuple[dict, ...] # {term_ko, plain_ko, matched_text, start_index, end_index, confidence}
    summary: str | None
    engine: EngineId
    model: str                       # 실제 모델 ID (translations.ai_model = f"{engine}:{model}")
    input_tokens: int
    output_tokens: int
    cached_tokens: int
    latency_ms: int

@dataclass(frozen=True, slots=True)
class CostEstimate:
    usd: float
    price_version: str               # eval/prices.yml 의 version

class Engine(Protocol):
    id: EngineId
    model: str
    async def translate(self, req: EngineRequest) -> TranslationResult: ...
    async def health(self) -> Health: ...           # 키 유무·최근 브레이커 상태·(선택) 핑
    def cost_estimate(self, input_tokens: int, output_tokens: int, cached_tokens: int = 0) -> CostEstimate: ...
    def quota_keys(self) -> tuple[str, ...]: ...    # 이 엔진이 소모하는 한도 버킷 이름(5-5)
```
- `EngineError(code: Literal["TIMEOUT","RATE_LIMITED","BAD_JSON","PROVIDER_5XX","UNCONFIGURED"], engine, http_status)`만 밖으로 나간다. **제공자 응답 본문은 예외에 싣지 않는다**(입력 텍스트를 되돌려주는 제공자 에러 메시지가 Sentry로 새는 경로 차단).
- JSON 스키마 출력: 어댑터 안에서 `pydantic` 모델로 파싱, 실패 시 1회만 "JSON만" 재요청(재시도는 §7 규칙상 **호출 단위**가 아니라 **파싱 단위**라 중복 생성 없음), 그래도 실패면 `BAD_JSON` → 폴백.

#### 5-3. 어댑터 5종 (+ 기록 전용 1종)
| id | 실체 | 키·설정 | 기본 역할(§15 표 갱신) | 비고 |
|---|---|---|---|---|
| `gemini_free` | Google AI Studio 무료 티어, JSON 스키마 출력. 모델 2단(`MWONMAL_GEMINI_MODEL_CHEAP`=Flash-Lite 계열, `..._STRONG`=Flash 계열, 모델 ID는 설정) | `GEMINI_API_KEY` | DETECT_PLAIN 1순위, QUIZ_DISTRACTOR 1순위, NUANCE_ACTIONS·MEETING_SUMMARY 폴백 | RPD가 모델마다 다르고 자주 바뀜(**확인 필요**) → 한도는 설정값 |
| `openai_key` | OpenAI Chat, structured output | `OPENAI_API_KEY`(없으면 UNCONFIGURED) | 키·크레딧 있을 때만 NUANCE_ACTIONS 후보 | REQ-11 "사용자 제공 키" = 개발자(운영자)가 `.env`에 넣는 키로 해석. **최종 사용자 BYOK는 범위 밖**(키 저장=시크릿 취급 필요, PO 확인) |
| `anthropic_key` | Claude Messages, JSON 출력, 프롬프트 캐싱(사전 발췌) | `ANTHROPIC_API_KEY` | 키 있을 때 NUANCE_ACTIONS·MEETING_SUMMARY 1순위(§15 "품질이 중요한 작업만") | 크레딧 소진 시 402/429 → 브레이커 OPEN → gemini_free |
| `vllm_local` | 자체 sLLM(Qwen3 LoRA, §15 파인튜닝 트랙) vLLM OpenAI 호환 엔드포인트 | `VLLM_BASE_URL`(없으면 UNCONFIGURED) | 실험: 평가셋에서 API 대비 ≥80%면 DETECT_PLAIN 후보 | 스팟 GPU 켜져 있을 때만. MLX(Mac)도 같은 OpenAI 호환 서버로 꽂힘 → 어댑터 재사용 |
| `none` | AI 없음. 사전 trie 매칭만 → detected_terms + result_text=치환문, nuance=None, action_items=() | 없음 | **최종 폴백**(절대 실패하지 않음). "강등 모드" | 결과의 `aiModel="none:dictionary"`. 허용 여부는 `ROUTER_ALLOW_DEGRADED`(dev true / prod는 앱 v1.1 배지 전까지 false → 503) |
| `on_device` | 어댑터 아님. 앱이 처리했음을 **기록**하는 id | — | `engineHint=ON_DEVICE_*`일 때 ai_usage에 남김(토큰·비용 0) | 서버는 5-4의 검수 단계만 수행 |

#### 5-4. 선택 정책 입력과 흐름 (요청 하나 = 작업 최대 2개, §15 "두 모델로 나눠도 된다")
```
입력: task, engineHint(계약 v1.1, 없으면 SERVER), clientDraft(v1.1, hint가 ON_DEVICE_*일 때 필수),
      user_daily_count(Redis), engine quota 잔량(Redis), breaker 상태(Redis), 설정 ROUTER_ALLOW_DEGRADED
흐름(POST /translations 4단계 내부):
  hint=SERVER            → DETECT_PLAIN 사슬 실행 → NUANCE_ACTIONS 사슬 실행
  hint=ON_DEVICE_PARTIAL → DETECT_PLAIN 생략(clientDraft.resultText/detectedTerms 사용) → NUANCE_ACTIONS 사슬 실행
  hint=ON_DEVICE_FULL    → 두 사슬 모두 생략(clientDraft에 nuance/actionItems 포함) → 검수만
공통 후처리(엔진과 무관, §5-1 5·6단계 그대로):
  사전(APPROVED) 매칭 우선 → detected_terms 중 사전 용어는 plain_ko 덮어쓰기
  인덱스 재계산: matchedText가 sourceText[start:end]와 다르면 서버가 다시 찾음, 못 찾으면 그 용어 폐기(앱/AI 인덱스는 믿지 않는다)
  clientDraft가 hint와 안 맞으면 400 INVALID_INPUT(field=clientDraft)
```
폴백 사슬(설정 `policy.yml`, 기본값):
| task | 사슬 (왼쪽부터) | 사슬 끝 |
|---|---|---|
| DETECT_PLAIN | gemini_free(cheap) → gemini_free(strong) → vllm_local → anthropic_key → openai_key | `none`(허용 시) / 503 AI_UNAVAILABLE |
| NUANCE_ACTIONS | anthropic_key → gemini_free(strong) → gemini_free(cheap) → openai_key | **생략**(nuance=null, actionItems=[] — 계약상 합법, 503 아님) |
| QUIZ_DISTRACTOR | gemini_free(cheap) → 규칙(사전 다른 용어 뜻 섞기, §5-4) | 규칙(실패 없음) |
| MEETING_SUMMARY | anthropic_key → gemini_free(strong) | FAILED(reason=AI_UNAVAILABLE) 3회 backoff(§5-2) |
사슬의 각 칸을 건너뛰는 조건: `health()!=UP` / breaker OPEN / 한도 소진(5-5) / 예산 게이트(B-4). 건너뛴 이유는 `ai_usage.outcome`에 남긴다.

#### 5-5. 무료 한도 카운터 (Redis, 14번 §9 토큰 버킷과 별개 — 이건 "제공자 한도")
- 키: `ai:quota:{engine}:{model}:{unit}:{window}` — unit ∈ `rpm, rpd, tpm, tpd, audio_sec_d`, window = `YYYYMMDDHHmm`(분) / `YYYYMMDD`(일, **UTC 기준** — Google 무료 티어 리셋 기준이 태평양 시간이라는 설도 있어 **확인 필요**; 확인 전엔 UTC로 보수 운용).
- 연산: `INCRBY` 후 값 > 한도×0.8(소프트 상한)이면 `DECRBY`하고 다음 칸으로. TTL 분 키 120s, 일 키 48h. 원자성이 필요하면 Lua 한 줄(`INCR + 비교 + 조건 DECR`).
- 한도값은 설정(`MWONMAL_AI_QUOTA__gemini_free__<model>__rpd=…`), 코드에 숫자 없음. 20% 여유는 두 프로세스가 동시에 마지막 칸을 쓰는 경쟁과 제공자 카운팅 오차 대비.
- 사용자 일 한도(B-4)도 같은 모듈: `ai:user:{user_id}:d:{YYYYMMDD}`.

#### 5-6. Circuit breaker (Redis 공유, §15 "30초 안에 2회 실패 → 폴백")
- 키 `ai:cb:{engine}:{model}` = `{state, opened_at, fail_count}`(HASH). 실패 창은 `ai:cb:fail:{engine}:{model}` ZSET(타임스탬프), 30초 밖은 `ZREMRANGEBYSCORE`.
- CLOSED → OPEN: 30초 안 실패 2회(TIMEOUT/PROVIDER_5XX/RATE_LIMITED; BAD_JSON은 세지 않음 — 모델 품질 문제라 브레이커로 못 고침).
- OPEN → HALF_OPEN: 60초 뒤 프로브 1회(`SET NX` 락으로 프로세스 하나만). 성공 → CLOSED, 실패 → OPEN 60초 연장(최대 10분).
- 브레이커 상태 변화는 구조화 로그 + Prometheus 게이지 `ai_breaker_state{engine,model}`. 14번 §10 알림 "AI 실패율 > 5%"와 같은 대시보드.

#### 5-7. 관측 (요청마다 `EngineCall` → `ai_usage`, B-2)
- 기록 필드: request_id(`X-Request-Id`, Caddy 생성), user_id, translation_id(저장 후 UPDATE), task, engine, model, engine_hint, client_os(User-Agent에서 `iOS 17` 같은 메이저만), input/output/cached tokens, audio_sec, latency_ms, outcome, fallback_from, cost_usd, price_version, prompt_version.
- **없는 것**: 원문·프롬프트·응답 텍스트·제공자 에러 본문. `EngineRequest.__repr__`이 글자 수만 내고, 로거는 `dict` 화이트리스트로만 직렬화. Sentry `send_default_pii=False` + `before_send`에서 `request.data` 삭제(14번 §6). 이 불변식은 **테스트로 고정**: 가짜 엔진이 예외를 던질 때 캡처된 로그·Sentry 이벤트 JSON에 sourceText 조각이 없음을 assert.
- 지표: `ai_calls_total{engine,model,task,outcome}`, `ai_latency_seconds` 히스토그램, `ai_tokens_total{direction}`, `ai_cost_usd_total{engine}`, `ai_quota_remaining{engine,unit}`.

### 6. 검증 방법
- 단위: 정책 표 → 사슬 순서 테스트(엔진 가짜 5개), 브레이커 상태 전이(Clock 주입), 한도 카운터 경계(80% 소프트 상한), `none` 어댑터가 test-vectors의 형광펜 정답과 일치.
- 통합(testcontainers Redis): uvicorn 2 프로세스가 같은 브레이커를 보는지(한쪽에서 OPEN시키고 다른 쪽이 건너뛰는지).
- 계약: schemathesis에서 `aiModel`이 항상 `"{engine}:{model}"` 형식, 503 경로가 `Retry-After: 5` 포함(§7).
- 평가셋(§15): Day 11 v0 50문장으로 `make eval ENGINE=gemini_free MODEL=…` 점수표 → 사슬 기본값은 이 표로만 바꾼다.
- 유출 테스트: 위 5-7 불변식 테스트가 PR 게이트.

### 7. 리스크와 되돌리는 조건
| 리스크 | 신호 | 되돌림·완화 |
|---|---|---|
| 무료 티어 한도가 실사용을 못 버팀(Flash 계열 RPD가 두 자리라는 보도) | `ai_quota_remaining` 0 도달 시각이 매일 앞당겨짐 | (1) DETECT_PLAIN을 온디바이스(iOS 26)로 이전(v1.1), (2) 사용자 일 한도 하향, (3) REQ-11 재협의(유료 전환은 REQ 변경 필요) |
| 강등(`none`)이 잘못된 "청정 한국어" 빈 상태를 만듦 | 강등 중 jargonCount=0 비율 | prod `ROUTER_ALLOW_DEGRADED=false` 유지 → 503. 앱 v1.1이 `engine=NONE` 배지 표시하면 true |
| 어댑터별 프롬프트 두 벌 유지(15번 H) | 평가셋 점수 격차 > 10점 | 프롬프트는 공통 1벌 + 어댑터별 "출력 형식" 어댑션만 |
| Redis 장애 시 한도·브레이커 불가 | `/ready` Redis ping 실패 | fail-open이 아니라 **fail-safe**: 카운터 못 읽으면 `none`/503 (무료 한도 초과로 계정 정지되는 것이 더 큰 손해) |

---

## B-2. 비용 집계 파이프라인 (REQ-13)

### 1. 의도
"MAU당 월 비용 자동 산정, 수치는 측정값으로 갱신"(REQ-13)을 위해 호출 단위 원시 기록 → 일 집계 → 계산기 입력의 세 층을 만든다. 앱이 온디바이스로 처리한 요청도 세어야 "온디바이스 비율"이 원가에 반영된다.

### 2. 비용
- 저장: `ai_usage` 행 ≈ 200B. 해석 1건 = 최대 2행. 200 MAU × 10건/일 × 2 = 4천 행/일 → 월 12만 행, 수십 MB. 90일 보존 후 삭제(`usage_daily`는 영구).
- 배치: ARQ cron 1개(매일 00:10 KST, 전날 UTC 기준 집계 — 무료 한도 창과 같은 기준). 실행 수 초.
- 코드: 마이그레이션 1개, 레코더 1개, 집계 SQL 1개, `cost_model.py` 입력 로더 1개.

### 3. 대안
| 대안 | 왜 탈락 |
|---|---|
| Prometheus 카운터만으로 비용 산정 | 사용자 수(MAU)·요청과 조인 불가, 보존 14일(로그 정책)로 월 단위 계산 불가 |
| `translations.ai_model/latency_ms`만 쓰기 | 실패·폴백·강등·퀴즈 오답·STT가 안 잡힘. 토큰 수 없음 → 단가 곱셈 불가 |
| 외부 비용 SaaS(제공자 콘솔) | 무료 티어는 콘솔 집계가 조악하고, 온디바이스·`none` 호출은 제공자에 존재하지 않음 |

### 4. 왜
비용 모델의 오차는 "요청당 토큰"과 "온디바이스·강등 비율"에서 나온다. 둘 다 서버가 호출 시점에만 정확히 안다. 호출마다 남기고 하루 단위로 접으면 계산기는 CSV 하나만 읽으면 되고, 원시 행은 90일 뒤 지워도 집계가 남는다.

### 5. 문안·형식 (영향: `contracts/db.dbml` v1.1, `eval/`, 14번 §6·§16)

#### 5-1. dbml v1.1 추가분 (PII 없음: 텍스트 컬럼 0개, user_id는 기존 테이블과 같은 내부 대리키)
```dbml
Enum ai_task {
  DETECT_PLAIN     [note: '용어 탐지 + 쉬운 말']
  NUANCE_ACTIONS   [note: '숨은 뜻 + 할 일 추출']
  QUIZ_DISTRACTOR  [note: '실력 테스트 오답 생성']
  MEETING_SUMMARY  [note: '회의록 5000자 초과 요약']
  STT_CHUNK        [note: '녹음 조각 받아쓰기']
}

Enum ai_engine {
  GEMINI_FREE   [note: 'Google AI Studio 무료 티어']
  OPENAI_KEY    [note: '운영자 키가 있을 때만']
  ANTHROPIC_KEY [note: '운영자 키가 있을 때만']
  VLLM_LOCAL    [note: '자체 sLLM(vLLM/MLX OpenAI 호환)']
  NONE          [note: 'AI 없음 - 검수 사전만 (강등 모드)']
  ON_DEVICE     [note: '앱이 온디바이스로 처리, 서버는 검수·인덱스만']
  GROQ_WHISPER  [note: 'STT - Groq Whisper 무료 티어']
  GEMINI_AUDIO  [note: 'STT - Gemini 오디오 입력']
  WHISPER_LOCAL [note: 'STT - 자체 호스팅 faster-whisper']
}

Enum ai_outcome {
  OK            [note: '성공']
  TIMEOUT       [note: '타임아웃 - 브레이커 실패로 집계']
  PROVIDER_5XX  [note: '제공자 오류']
  RATE_LIMITED  [note: '제공자 429']
  BAD_JSON      [note: '스키마 불일치 - 브레이커에 안 셈']
  QUOTA_SKIP    [note: '무료 한도 소진으로 호출 안 함']
  BREAKER_SKIP  [note: '브레이커 OPEN으로 호출 안 함']
  BUDGET_SKIP   [note: '사용자·엔진 예산 게이트로 호출 안 함']
}

Enum engine_hint {
  SERVER            [note: '서버가 전부 처리 (v1.0 클라이언트 기본값)']
  ON_DEVICE_PARTIAL [note: '앱이 쉬운 말+용어 처리, 서버는 뉘앙스·할 일']
  ON_DEVICE_FULL    [note: '앱이 네 출력 전부 처리, 서버는 검수·인덱스·저장만']
}

Table ai_usage {
  id             bigint      [pk, increment]
  request_id     char(36)    [not null, note: 'X-Request-Id (Caddy). 앱 Sentry 이벤트와 결합']
  user_id        bigint      [not null]
  translation_id bigint      [note: '저장 후 연결. 실패·퀴즈·STT는 NULL']
  recording_id   bigint      [note: 'STT_CHUNK일 때']
  task           ai_task     [not null]
  engine         ai_engine   [not null]
  model          varchar(50) [not null, note: '실제 모델 ID. ON_DEVICE는 "apple-fm" 등 앱이 보고한 값, NONE은 "dictionary"']
  engine_hint    engine_hint [not null, default: 'SERVER']
  client_os      varchar(12) [note: '"iOS 17" 같은 메이저까지만 (User-Agent). 온디바이스 비율 세그먼트용']
  input_tokens   int         [not null, default: 0]
  output_tokens  int         [not null, default: 0]
  cached_tokens  int         [not null, default: 0, note: '프롬프트 캐시 적중 토큰']
  audio_sec      int         [note: 'STT_CHUNK 입력 길이(초)']
  latency_ms     int         [not null]
  outcome        ai_outcome  [not null]
  fallback_from  ai_engine   [note: '이 호출이 폴백이면 원래 1순위 엔진']
  cost_usd       decimal(10,6) [not null, default: 0, note: 'prices.yml 단가 × 토큰. 무료 티어는 0이지만 "유료였다면" 값을 별도 열로']
  list_cost_usd  decimal(10,6) [not null, default: 0, note: '무료 티어를 정가로 환산한 값 - 손익분기 계산용']
  price_version  varchar(20) [not null, note: 'eval/prices.yml version']
  prompt_version varchar(20) [not null, note: 'decode/domain/prompts.py PROMPT_VERSION']
  created_at     datetime    [not null, default: `now()`]

  indexes {
    created_at [name: 'ix_ai_usage_time']
    (engine, model, created_at) [name: 'ix_ai_usage_engine_time']
    (user_id, created_at) [name: 'ix_ai_usage_user_time']
    translation_id [name: 'ix_ai_usage_translation']
  }
  Note: 'AI·STT 호출 1건 = 1행. 텍스트 컬럼 없음(원문·프롬프트·응답 금지, REQ-14). 90일 보존 후 삭제, 집계는 usage_daily에 남음'
}

Table usage_daily {
  date            date        [not null, note: 'UTC 기준 일자 (무료 한도 창과 동일)']
  engine          ai_engine   [not null]
  model           varchar(50) [not null]
  task            ai_task     [not null]
  calls           int         [not null, default: 0]
  ok_calls        int         [not null, default: 0]
  fallback_calls  int         [not null, default: 0]
  input_tokens    bigint      [not null, default: 0]
  output_tokens   bigint      [not null, default: 0]
  cached_tokens   bigint      [not null, default: 0]
  audio_sec       bigint      [not null, default: 0]
  latency_p50_ms  int
  latency_p95_ms  int
  cost_usd        decimal(12,6) [not null, default: 0]
  list_cost_usd   decimal(12,6) [not null, default: 0]
  distinct_users  int         [not null, default: 0, note: '그날 이 (engine,model,task)를 쓴 사용자 수']
  price_version   varchar(20) [not null]
  computed_at     datetime    [not null, default: `now()`]

  indexes {
    (date, engine, model, task) [pk]
    date [name: 'ix_usage_daily_date']
  }
  Note: 'ai_usage 일 집계. ARQ cron aggregate_usage_daily 가 멱등(UPSERT)으로 생성. eval/cost_model.py 입력'
}

Ref: ai_usage.user_id > users.id
Ref: ai_usage.translation_id > translations.id
Ref: ai_usage.recording_id > meeting_recordings.id
```
`ai_usage.user_id`는 MAU 분모(그날 distinct 사용자)를 세기 위해 필요하다. 이메일·닉네임 같은 식별 정보는 없다. `usage_daily`에는 user_id가 없다(집계만).

#### 5-2. 배치
- ARQ cron `aggregate_usage_daily(date)` 매일 00:10 KST(= 전날 UTC 하루가 닫힌 뒤). `INSERT … SELECT … GROUP BY date, engine, model, task ON DUPLICATE KEY UPDATE` → 멱등, 재실행 안전. p50/p95는 MySQL 8 윈도 함수(`PERCENT_RANK`) 또는 파이썬 집계(행 수 수천이라 파이썬이 단순).
- `purge_ai_usage` 매일 03:10: `created_at < now-90d` 삭제(§5-5 `purge_recordings` 옆).
- 실패 시 다음 날 cron이 최근 3일을 다시 집계(누락 자동 복구).

#### 5-3. `eval/cost_model.py`가 읽는 형식
```
eval/
  prices.yml           # version: "2026-09"; engines.<engine>.<model>: {input_per_mtok, output_per_mtok, cached_per_mtok, audio_per_min, free: {rpd, rpm, tpm, audio_sec_per_day}}  ← 값은 전부 "확인 필요", 제공자 가격 페이지에서 채움
  data/usage_daily.csv # usage_daily 테이블 그대로 (make usage-export DATE_FROM=… 가 SQL → CSV)
  cost_model.py        # 입력: --mau, --translations-per-user-month, --recordings-per-user-month, --recording-minutes,
                       #       --reviews-per-user-month, --on-device-ratio(기본: usage_daily에서 측정), --prices eval/prices.yml
                       # 측정값(usage_daily에서): 작업별 평균 input/output/cached 토큰, 폴백 비율, 강등 비율, STT 초/녹음
                       # 출력: 월 원가(엔진별·작업별), MAU당 원가, 정가 환산 원가(list), 손익분기 가격(원가/목표 마진), 무료 한도 소진 MAU(무료 rpd ÷ 1인당 일 호출)
```
계산 골자(단위: 달):
```
호출수(task) = MAU × 1인당 월 해석 × 서버 처리 비율(task)        # 온디바이스 비율은 ai_usage.engine=ON_DEVICE 로 측정
토큰비용(task) = 호출수 × (평균 input × 단가_in + 평균 cached × 단가_cached + 평균 output × 단가_out)   # 평균은 usage_daily 가중평균
STT비용 = MAU × 1인당 월 녹음 × 분 × 단가_audio
월 원가 = Σ 토큰비용 + STT비용 + 고정비(VM, 14번 §12 2~4만 원)
MAU당 원가 = 월 원가 / MAU ;  손익분기 가격 = MAU당 원가 / (1 - 목표마진)
무료 한도 소진 MAU = min_engine(free.rpd × 30 / (1인당 월 호출 × 서버 비율))   ← "무료 티어로 몇 명까지 버티나"
```
대시보드(REQ-13)는 Grafana에 `usage_daily`를 MySQL 데이터소스로 직접 붙인다(추가 서비스 없음).

#### 5-4. 계약 v1.1 문안 (`contracts/openapi.yml`, 전부 선택 필드 → 하위 호환)
```yaml
    EngineHint:
      type: string
      description: |
        앱이 온디바이스 AI로 어디까지 처리했는지. 서버는 어떤 값이든 검수 사전 우선·인덱스 재계산을 수행한다.
        SERVER(서버가 전부) / ON_DEVICE_PARTIAL(앱이 쉬운 말+용어, 서버는 뉘앙스·할 일) / ON_DEVICE_FULL(앱이 전부, 서버는 검수·저장)
      enum: [SERVER, ON_DEVICE_PARTIAL, ON_DEVICE_FULL]
      default: SERVER
    EngineId:
      type: string
      description: 결과를 만든 엔진. NONE은 AI 없이 검수 사전만으로 만든 강등 결과(앱은 "간이 해석" 배지)
      enum: [GEMINI_FREE, OPENAI_KEY, ANTHROPIC_KEY, VLLM_LOCAL, NONE, ON_DEVICE]
    ClientDraft:
      type: object
      description: engineHint가 ON_DEVICE_*일 때 필수. 서버가 인덱스를 재계산하므로 startIndex/endIndex는 참고값
      required: [resultText, detectedTerms, model]
      properties:
        model: { type: string, maxLength: 50, description: '앱이 쓴 온디바이스 모델 식별자 (예: apple-fm-26.4)', example: apple-fm-26.4 }
        resultText: { type: string, maxLength: 2000 }
        detectedTerms:
          type: array
          items:
            type: object
            required: [matchedText, startIndex, endIndex]
            properties:
              termKo: { type: string, maxLength: 100 }
              plainKo: { type: string, maxLength: 200 }
              matchedText: { type: string, maxLength: 100 }
              startIndex: { type: integer }
              endIndex: { type: integer }
              confidence: { type: number, format: float, minimum: 0, maximum: 1 }
        intentType: { allOf: [{ $ref: '#/components/schemas/IntentType' }], nullable: true, description: ON_DEVICE_FULL일 때 }
        nuance: { allOf: [{ $ref: '#/components/schemas/NuanceInfo' }], nullable: true, description: ON_DEVICE_FULL일 때 }
        actionItems:
          type: array
          description: ON_DEVICE_FULL일 때. actionId/isChecked는 서버가 채우므로 actionText/dueHint만
          items: { type: object, required: [actionText], properties: { actionText: { type: string, maxLength: 300 }, dueHint: { type: string, nullable: true, maxLength: 100 } } }

    TranslationRequest:            # 추가되는 두 필드만
      properties:
        engineHint: { allOf: [{ $ref: '#/components/schemas/EngineHint' }], default: SERVER }
        clientDraft: { allOf: [{ $ref: '#/components/schemas/ClientDraft' }], nullable: true }

    TranslationResponse:           # 추가되는 두 필드만. aiModel은 유지("{engine소문자}:{model}" 형식으로 채움)
      properties:
        engine: { $ref: '#/components/schemas/EngineId' }
        degraded: { type: boolean, default: false, description: 'true면 AI 없이 사전만으로 만든 결과(engine=NONE) 또는 뉘앙스 사슬을 건너뜀' }
```
v1.0 브리지: `aiModel`은 이미 자유 문자열이라 v1.0에서도 `"gemini_free:<model>"`, `"none:dictionary"`를 넣을 수 있다(계약 무변경). `engine`/`degraded`는 앱이 배지를 그리기 위한 정형화일 뿐이다.

### 6. 검증
- 마이그레이션 0002 `alembic check` 통과, dbml v1.1과 `dbml2sql` diff 0.
- 단위: 레코더가 텍스트를 절대 쓰지 않음(스키마에 텍스트 컬럼이 없어 컴파일 수준에서 보장 + 테스트).
- 집계 멱등: 같은 날을 두 번 돌려도 행 수·합계 동일.
- `cost_model.py`: 고정 CSV 픽스처로 결과가 손계산과 일치(테스트 벡터 `packages/test-vectors/cost_model.json`).

### 7. 리스크·되돌림
- `prices.yml` 값이 오래됨 → `price_version`이 30일 이상이면 CI 경고. 무료 티어 폐지 시 `list_cost_usd`가 곧 실비가 되므로 열을 미리 둔다.
- 행 수 폭증(MAU 5천+) → `usage_daily`만 남기고 `ai_usage` 보존 30일로 단축(설정값).

---

## B-3. 워치 대비 알림 스키마 (REQ-04)

### 1. 의도
알림 4종의 payload·딥링크·복습 카드 모델을 지금부터 워치가 쓸 수 있게 고정한다(REQ-04: 설계 v1, 구현 v2). 앱 12번 §8-2의 `DeepLink.parse(userInfo)` 순수 함수가 iOS·watchOS에서 같은 코드가 되게.

### 2. 비용
- 서버: payload 빌더 1개(`notify/domain/push_payload.py`), `DevicePlatform` enum 값 2개 추가(마이그레이션 expand), 발송 루프가 `IOS`뿐 아니라 `WATCHOS` 토큰도 순회. APNs 연결 수는 그대로(같은 `.p8` 키, 토픽만 다름).
- 앱: v1.0에서는 아무것도 안 함(워치 타깃 없음, T-D4).
- 크기: 4KB 한도(Apple 문서) 대비 payload ≈ 300B.

### 3. 대안
| 대안 | 왜 탈락 |
|---|---|
| 아이폰에만 보내고 시스템 전달(forwarding)에 의존 | Apple 문서: "종속(dependent) watchOS 앱은 iPhone에만 보내도 됨", 그러나 "독립 watchOS 앱은 두 기기 모두에 보내야 하며 시스템이 한 곳만 울림". v2 워치 앱 형태를 아직 모르므로 **둘 다 보내는 경로**를 열어 두는 게 되돌리기 쉬움. 토큰이 없으면 자연히 아이폰만. |
| `mw` 네임스페이스 객체 하나에 커스텀 키를 모으기 | 앱 §13이 이미 평면 키(`type, translationId, meetingId, projectId, quizId`)로 합의. 앱 계약을 깨지 않기 위해 평면 유지 + `v`로 버전 관리. |
| `content-available` 사일런트 푸시로 데이터만 보내고 앱이 로컬 알림 생성 | 앱이 꺼져 있으면 iOS가 전달을 제한, 워치는 더 제한. 알림 텍스트는 서버가 이미 `notifications.title/body`로 갖고 있음. |

### 4. 왜
Apple 문서(Generating a remote notification)는 커스텀 키를 `aps`의 형제로, 값은 원시 타입으로만 두라고 한다. 우리 4종은 ID 몇 개면 딥링크가 되고, 텍스트는 `notifications.title/body`(dbml) 두 개뿐이다. `interruption-level`·`thread-id`·`category`를 지금 정해 두면 워치 short look(제목만 표시)과 iOS 알림 액션(A-05 "지금 복습/미루기")이 같은 payload로 동작한다.

### 5. 문안 (영향: yml v1.1 `PushPayload`·`DevicePlatform`·`NotificationType`, dbml `device_platform`, 14번 §5-5, 12번 §8-2·§13)

#### 5-1. enum 문안
```yaml
    DevicePlatform:
      type: string
      description: IOS(iPhone·iPad APNs) / MACOS(v1.1 APNs, 그 전엔 로컬 알림 D-19) / WATCHOS(v2 워치 앱 자체 토큰) / WEB(계약 유지, 등록 안 함)
      enum: [IOS, MACOS, WATCHOS, WEB]
    NotificationType:
      type: string
      enum: [REVIEW_REMINDER, ACTION_DUE, DECODE_DONE, LEVEL_UP]
```
```dbml
Enum device_platform {
  IOS     [note: 'iPhone, iPad - APNs']
  MACOS   [note: 'v1.1 - APNs (v1.0은 로컬 알림)']
  WATCHOS [note: 'v2 - 워치 앱 자체 토큰. 발송은 IOS+WATCHOS 모두, 시스템이 한 곳만 울림']
  WEB     [note: '계약 유지용, 토큰 등록 안 함']
}
```
`DeviceRequest.pushToken` description을 "IOS·MACOS·WATCHOS일 때 APNs 토큰"으로. `user_devices.push_token` note 동일.

#### 5-2. `PushPayload` 스키마(yml v1.1, 앱·워치가 디코딩 테스트에 쓰는 원본; `contracts/push-payload.json` 예시 4개 동봉 — 14번 §16 트리에 이미 자리 있음)
```yaml
    PushPayload:
      type: object
      description: APNs 커스텀 키(aps의 형제). 텍스트는 aps.alert에만, 원문·받아쓰기·해석 결과는 절대 넣지 않는다
      required: [v, type, notificationId]
      properties:
        v: { type: integer, description: payload 스키마 버전, example: 1 }
        type: { $ref: '#/components/schemas/NotificationType' }
        notificationId: { type: integer, format: int64, description: notifications.id (열림 추적·중복 제거) }
        projectId: { type: integer, format: int64, nullable: true }
        meetingId: { type: integer, format: int64, nullable: true }
        translationId: { type: integer, format: int64, nullable: true }
        actionId: { type: integer, format: int64, nullable: true }
        quizId: { type: integer, format: int64, nullable: true }
        dueCount: { type: integer, nullable: true, description: REVIEW_REMINDER 오늘 복습 카드 수 }
```
APNs 헤더 규칙(서버): `apns-push-type: alert`, `apns-priority: 10`(REVIEW_REMINDER·LEVEL_UP은 5), `apns-topic` = 번들 ID(iOS `kr.mwonmal.app`, macOS `kr.mwonmal.mac`, watchOS `kr.mwonmal.app.watchkitapp` — 워치 토픽 명명은 **확인 필요**), `apns-collapse-id` = `{type}:{targetId}`(같은 알림 중복 접기), `apns-expiration` = ACTION_DUE는 due_at, 나머지 24h.

#### 5-3. 알림 4종 payload 예시
```json
// 1) REVIEW_REMINDER (스케줄러 review_reminder, §5-5) — 액션 카테고리로 A-05 "지금 복습 / 미루기"
{ "aps": { "alert": { "title": "얼라인, 기억나세요?", "body": "오늘 복습할 카드 7장이 기다려요" },
           "badge": 7, "sound": "default", "category": "REVIEW_REMINDER",
           "thread-id": "review", "interruption-level": "active", "relevance-score": 0.6 },
  "v": 1, "type": "REVIEW_REMINDER", "notificationId": 9001, "dueCount": 7 }

// 2) ACTION_DUE (마감 30분 전) — body는 사용자의 할 일 문장(action_text, 60자 절단). 원문(sourceText)은 넣지 않는다
{ "aps": { "alert": { "title": "30분 뒤 마감", "body": "담당자별 역할 정리 문서 만들기" },
           "sound": "default", "category": "ACTION_DUE",
           "thread-id": "meeting:12", "interruption-level": "time-sensitive", "relevance-score": 0.9 },
  "v": 1, "type": "ACTION_DUE", "notificationId": 9002,
  "projectId": 7, "meetingId": 12, "translationId": 1024, "actionId": 5001 }

// 3) DECODE_DONE (decode_meeting 완료) — 제목에 회의 제목(meetings.title)만
{ "aps": { "alert": { "title": "해석이 끝났어요", "body": "스프린트 계획 회의 · 판교어 4개, 할 일 2개" },
           "sound": "default", "category": "DECODE_DONE",
           "thread-id": "meeting:12", "interruption-level": "active", "relevance-score": 0.8 },
  "v": 1, "type": "DECODE_DONE", "notificationId": 9003,
  "projectId": 7, "meetingId": 12, "translationId": 2048 }

// 4) LEVEL_UP (§5-4: v1.0은 저장만, 푸시는 앱이 보고 있으므로 안 보냄. 워치 v2에서 보낼 때의 형태)
{ "aps": { "alert": { "title": "등급이 올랐어요", "body": "이주민 → 원주민" },
           "sound": "default", "category": "LEVEL_UP",
           "thread-id": "level", "interruption-level": "passive", "relevance-score": 0.4 },
  "v": 1, "type": "LEVEL_UP", "notificationId": 9004, "quizId": 77 }
```
텍스트 정책: payload에 들어가는 문장은 `notifications.title/body` 두 개뿐이고, 그 소스는 (1) 고정 문구, (2) `meetings.title`, (3) `terms.term_ko`, (4) `translation_actions.action_text`(사용자의 할 일)로 제한. `sourceText`·`transcript`·`result_text`·`nuance_*`는 금지(빌더 단위 테스트로 고정). 잠금 화면에 할 일 문장이 보이는 것이 부담이면 v1.1에 사용자 설정 "미리보기 숨김"(body를 "할 일 1건 마감 임박"으로) — PO 확인.

#### 5-4. 워치가 쓰는 복습 카드 모델
`ReviewCard`(yml 기존 스키마)에 워치용 축약이 필요하면 v2에서 `GET /reviews/sessions/{id}?fields=compact`가 아니라 **같은 스키마를 그대로** 쓴다(워치 앱이 `Domain` 모듈을 공유, REQ-04 "Domain 모델 워치 공유 가능"). 서버 변경 없음. 워치 독립 실행 시 토큰 등록은 `POST /devices {platform: WATCHOS}` 그대로.

### 6. 검증
- `PushPayload` JSON 예시 4개가 yml 스키마로 validate(contracts CI). 앱 `DeepLink.parse` 단위 테스트가 같은 파일을 읽음(test-vectors).
- 빌더 테스트: 금지 텍스트 필드가 payload 문자열에 포함되지 않음, 크기 < 4096B.
- Day 28 실기기: iOS 4종 수신, 액션 2종 동작. 워치는 v2.

### 7. 리스크·되돌림
- 아이폰+워치 둘 다 보내면 두 번 울린다는 우려 → Apple 문서: 시스템이 최적 기기 한 곳에만 전달. 실측(v2)에서 중복이면 `WATCHOS` 발송을 끄는 설정 한 줄.
- `time-sensitive`는 앱 entitlement 필요(`com.apple.developer.usernotifications.time-sensitive`) — iOS 파트 확인. 없으면 `active`로 강등.

---

## B-4. iOS 17~25 클라이언트 대응 (REQ-02)

### 0. 사실 정리 (먼저 오해를 푼다)
| 기능 | iOS 17~25 | iOS 26 | 출처 |
|---|---|---|---|
| `SpeechAnalyzer`(실시간 미리보기) | 없음 | iOS 26.0+ / macOS 26.0+ (watchOS 없음) | Apple 문서 SpeechAnalyzer |
| `SFSpeechRecognizer` 온디바이스(`supportsOnDeviceRecognition`) | iOS 13+ / macOS 10.15+ 에서 API 존재. **ko-KR 온디바이스 지원 여부는 확인 필요** | 있음 | Apple 문서 supportsOnDeviceRecognition |
| Foundation Models `SystemLanguageModel` | 없음 | iOS 26.0+ / macOS 26.0+ (Apple Intelligence 기기·지역 한정, watchOS 없음) | Apple 문서 SystemLanguageModel |
| 서버 STT | **필요(진실)** | **필요(진실)** | 12번 D-7, 14번 §13 "온디바이스 결과를 transcript로 채택 안 함" |

→ **STT 서버 부하는 OS와 무관하게 녹음 1분당 1조각이다.** iOS 17이 늘리는 것은 (a) 미리보기 없음(UX, iOS 파트), (b) v1.1 온디바이스 "쉬운 말+용어" 이전을 못 받아 **DETECT_PLAIN이 100% 서버**. 즉 부하 증가는 STT가 아니라 무료 LLM 한도 쪽이다. 다만 서버 STT 자체가 §1 표에 "외부 STT API"로만 적혀 있고 제공자·한도가 미정이라 여기서 정한다.

### 1. 의도
17~25 사용자도 같은 계약·같은 품질(서버 결과가 진실)을 받되, 무료 한도(REQ-11)를 특정 사용자군이 소진하지 않게 큐·한도·강등으로 공정성을 유지한다.

### 2. 비용
- STT 무료 티어(2026-09 웹 조사, **전부 확인 필요**):
  | 후보 | 무료 한도 | 한국어 | 평가 |
  |---|---|---|---|
  | **Groq Whisper(large-v3/turbo)** | 2,000 req/일, 28,800 오디오초/일(=8h), 20 RPM, 7,200초/시간, 파일 25MB, 카드 불필요 | Whisper 다국어(ko 포함) | **1순위**. 60초 조각 = 1req → 하루 8시간 분량 회의. 동시 20세션(14번 §8)은 20 RPM 상한과 정확히 맞물림 → 큐 스무딩 필요 |
  | Gemini API 오디오 입력 | 모델별 RPD(Flash-Lite 계열 500/일 보도, 자주 변동) | 있음 | 2순위 폴백. LLM 한도와 **같은 버킷을 나눠 씀** → DETECT_PLAIN과 경쟁 |
  | 자체 `faster-whisper`(OCI A1 4코어/24GB Always Free, 14번 §14) | 0원, CPU 처리속도 실측 필요(60초 조각이 60초 안에 끝나는지) | 있음 | dev 기본·prod 3순위. 원문이 외부로 안 나가는 유일한 경로(기밀 관점 가점) |
  | Deepgram | 가입 크레딧 $200(일회성) | 있음 | 반복 무료 아님 → 실험용만 |
  | Google Cloud STT / Azure Speech | 월 60분 / 월 5시간 무료로 알려짐 — **확인 필요** | 있음 | 월 한도가 작아 폴백 4순위 |
  | CLOVA Speech / ETRI 공공 API | 한국어 특화. 무료 여부·한도 **확인 필요** | 최상 | S2 평가셋(WER)에서 비교 후 결정 |
- 코드: `SttEngine` Protocol + 어댑터 3개(groq_whisper, gemini_audio, whisper_local), 라우터·한도·브레이커는 B-1 재사용. ARQ 큐 3개 = 워커 프로세스 설정 3줄.

### 3. 대안
| 대안 | 왜 탈락 |
|---|---|
| iOS 26 기기의 `SpeechAnalyzer` 결과를 transcript로 채택해 서버 STT 절감 | D-7·14번 §13 고정 결정 위반. 되돌리는 조건에만 기록 |
| 17~25에게만 해석 레이트리밋을 낮춤(OS 차별) | 계약에 OS 개념이 없고, 같은 사용자가 두 기기를 쓸 수 있음. 한도는 **사용자·엔진** 단위여야 공정 |
| 17~25에서 `SFSpeechRecognizer` 서버 인식(온디바이스 불가 시 Apple 서버로 전송) | 오디오가 Apple 서버로 나감 → REQ-14 취지 위반 가능(앱 §12 위협 모델). iOS 파트가 `requiresOnDeviceRecognition=true`일 때만 미리보기 허용해야 함 |
| 단일 큐 유지 | 회의 끝 `decode_meeting`(5000자 요약)이 실시간 조각 STT를 막아 W-02 "실시간 받아쓰기"가 멈춤 |

### 4. 왜
서버가 진실이라는 결정(D-7) 덕에 iOS 17은 STT 설계를 바꾸지 않는다. 바뀌는 건 "무료 LLM 한도를 누가 먼저 쓰나"이고, 이는 사용자 일 한도 + 엔진 예산 게이트 + 강등이라는 세 겹의 밸브로 푼다. STT는 Groq가 8h/일 무료로 가장 넉넉하되 20 RPM이 동시 20세션과 맞물려 큐 우선순위와 초당 발사 제한이 필수다.

### 5. 설계 (영향: 14번 §1 STT 행·§5-2·§8·§9, `services/worker`, 13번 §5-2 시크릿 목록)
- **STT 사슬**: `groq_whisper → gemini_audio → whisper_local` (prod), `whisper_local → groq_whisper` (dev). 각 칸은 B-1의 한도 카운터(`audio_sec_d`, `rpm`)·브레이커를 그대로 쓴다. 조각 STT 실패는 §5-2대로 3회 backoff, 그래도 실패면 FAILED(reason=STT_UNAVAILABLE).
- **큐 3개(ARQ `queue_name`)**: `mw:q:stt`(stt_chunk, 워커 동시 4, 초당 발사 ≤ 0.3/초 = 18 RPM으로 Groq 20 RPM 아래) / `mw:q:decode`(decode_meeting, make_quiz, 동시 2) / `mw:q:cron`(스케줄러·집계, 동시 1). 워커 프로세스 하나가 세 큐를 다 듣되 동시성만 다르게. 큐 적체 지표 `arq_queue_depth{queue}` → §10 알림 "적체 > 100"은 `stt`에만 적용(가장 사용자 체감).
- **레이트리밋(14번 §9 갱신)**: 기존 "해석 30/분/사용자" 유지 + **사용자 일 한도** `MWONMAL_AI_USER_DAILY_TRANSLATIONS`(기본 100, 초과 429 `TOO_MANY_REQUESTS` — 계약 v1.0에 코드는 있으나 Error description 목록에 없음 → v1.1 문안에 추가) + **엔진 예산 게이트**: 엔진 일 한도의 80% 도달 시 NUANCE_ACTIONS 사슬 생략(강등, `degraded=true`), 95% 도달 시 DETECT_PLAIN도 `none` 또는 503. 게이트 임계는 설정.
- **17~25 세그먼트 관측**: `ai_usage.client_os`로 온디바이스 비율·강등 비율을 OS별로 본다. 비용 모델의 `--on-device-ratio`가 여기서 나온다.
- **User-Agent 규약**(13번 §5-3 확장): `Mwonmal-iOS/1.0.0 (iOS 17.5) contract/1.0`. 서버는 OS 메이저만 기록, 정책 분기엔 쓰지 않는다.

### 6. 검증
- k6(S6): 동시 20 녹음 세션에서 `stt` 큐 p95 대기 < 10초, Groq 429 0건.
- STT 평가: 판교어 회의 음성 샘플 10개(WER) — Groq vs whisper_local vs (CLOVA 확인 시). 결과로 사슬 순서 확정.
- 예산 게이트 테스트: 한도 80%·95% 경계에서 `degraded`/503 전환.

### 7. 리스크·되돌림
- Groq 무료 한도 축소·폐지 → 사슬 다음 칸 자동. whisper_local이 CPU에서 실시간 미만이면 OCI A1의 4코어를 STT 전용 컨테이너로 분리(§12 확장 트리거 2번과 동일 절차).
- STT 비용이 비용 모델에서 지배적(> 50%)이 되면 **D-7 재협의**(iOS 26 기기 온디바이스 transcript 채택 + 서버는 인덱스만) — PO·iOS 파트 안건으로 넘김. 그 전엔 손대지 않음.
- `SFSpeechRecognizer` ko-KR 온디바이스가 불가면 17~25 미리보기는 파형만(T-D3 되돌림 조건과 동일) — iOS 파트 결정.

---

## B-5. 계약 v1.1 통합 백로그 (기존 9건 + 신규 6건)

| # | 항목 | 왜 | yml 변경 위치 | dbml 변경 위치 | 하위 호환 | 출처 |
|---|---|---|---|---|---|---|
| 1 | `DevicePlatform`에 `MACOS`, **`WATCHOS`** | macOS APNs(D-19 해제), 워치 v2(REQ-04) | `components/schemas/DevicePlatform.enum`, `DeviceRequest.pushToken.description` | `Enum device_platform` +2 | ✅ enum 추가만(앱 v1.0은 안 보냄) | 12번 §13 + B-3 |
| 2 | refresh 토큰 + `expiresIn` | 60분 녹음 중 만료(T-B6) | `POST /auth/refresh` 신설, `AuthResponse.expiresIn`, `refreshToken` | `refresh_tokens` 테이블(해시·회전) | ✅ 추가 필드·경로. 액세스 1h 단축은 앱 v1.1 배포 후 | 12번 §13, 14번 §11 |
| 3 | `Idempotency-Key` 헤더(createTranslation, startQuiz) | 503 후 안전 재시도(T-B7) | 두 op의 `parameters`에 header 추가 | 없음(Redis 24h) | ✅ 선택 헤더 | 12번 §13 |
| 4 | 날짜 `+09:00` 오프셋 | 표준 파서(T-B5) | `info.description` 공통 규칙, 모든 `format: date-time` example | 없음 | ⚠️ 응답 형식 변경 → 앱 D-13 트랜스코더가 둘 다 파싱하므로 실질 호환. `User-Agent contract/1.1`일 때만 오프셋 출력 | 12번 §13 |
| 5 | `PushPayload` 스키마 + `contracts/push-payload.json` 예시 4개 | 딥링크 조상 복원, 워치 공유 | `components/schemas/PushPayload`(B-3 5-2) | 없음 | ✅ 문서용 스키마(HTTP 응답 아님) | 12번 §13 + B-3 |
| 6 | `NotificationType` enum 4종 명시 | 기획서 일치 | `components/schemas/NotificationType` 신설 | 이미 있음 | ✅ | 12번 §13 |
| 7 | `DELETE /users/me`, `GET /devices` | App Store 계정 삭제 요건 | paths 2개 신설 | 없음(삭제 잡은 S3 객체·토큰 폐기) | ✅ | 12번 §13 |
| 8 | `uploadRecording.durationSec` "누적" 명시 | 계약 모호 | `paths./meetings/{id}/recordings.post.requestBody…durationSec.description` | `meeting_recordings.duration_sec` note | ✅ 문구 | 12번 §13, 13번 §3 |
| 9 | `securitySchemes: bearerAuth` + `security` 전역 | 생성 클라이언트·schemathesis 인증 | `components/securitySchemes`, 루트 `security`, `/levels`·`/terms/{id}`는 `security: []` | 없음 | ✅ (제출본이 의도적으로 뺐던 것 — 심사 기준 확인 후 v1.1) | 12번 §13, 14번 §11 |
| 10 | 426 계약 버전 협상 | `User-Agent contract/x.y` 밖이면 426 | `components/responses/UpgradeRequired` + Error code `CONTRACT_UNSUPPORTED` | 없음 | ✅ 새 코드는 앱 `.unknown` 매핑으로 흡수 | 14번 §11, T-B9 |
| **11** | **`TranslationRequest.engineHint`, `clientDraft`** | 온디바이스 처리 시 서버는 검수·인덱스만(REQ-10·14) | `TranslationRequest.properties` + `EngineHint`·`ClientDraft` 스키마(B-2 5-4) | `translations.engine_hint`(engine_hint, default SERVER) | ✅ 선택 필드, 기본 SERVER | 신규 B-1 |
| **12** | **`TranslationResponse.engine`, `degraded`** | 강등·온디바이스 결과 표시("간이 해석" 배지) | `TranslationResponse.properties` + `EngineId` 스키마 | `translations.ai_model` note("engine:model" 형식) | ✅ 추가 필드. v1.0 브리지는 `aiModel` 문자열 | 신규 B-1 |
| **13** | **`ai_usage`, `usage_daily` 테이블 + enum 4종** | REQ-13 비용 모델 측정값 | 없음(내부) | 새 테이블 2, `Enum ai_task/ai_engine/ai_outcome/engine_hint` | ✅ 추가만(expand) | 신규 B-2 |
| **14** | **Error 코드 목록 갱신**: `TOO_MANY_REQUESTS`(429, 사용자 일 한도·30/분), `STT_UNAVAILABLE`(503) | 14번 §9 레이트리밋이 계약 Error description에 없음, STT 장애 구분 | `Error.code.description`, `responses.TooManyRequests`·`ServiceUnavailable` example | `meeting_recordings.failure_reason` note | ✅ 코드 추가(앱 30코드 매핑에 2개 추가 → `.unknown` 폴백이라 v1.0 앱도 안 깨짐) | 신규 B-4 |
| **15** | **`RecordingResponse.sttEngine`**(nullable) + `meeting_recordings.stt_engine` | STT 제공자별 품질 추적(WER 평가와 결합) | `RecordingResponse.properties.sttEngine` | `meeting_recordings.stt_engine ai_engine [null]` | ✅ 선택 필드 | 신규 B-4 |

전부 "추가만"이라 **expand 단계 하나로 배포 가능**(ADR-0003 expand/contract). contract 단계가 필요한 것은 #4의 "오프셋 없는 출력 제거"뿐이고, 그것도 v1.0 앱 지원 종료 뒤(별도 릴리스).

---

## B-6. S0 Day 2~5에 미치는 영향과 순서

| Day | 계획(16번 §4) | 이번 결정이 바꾸는 것 | 하지 않을 것(미룸) |
|---|---|---|---|
| **Day 2 (app Tuist)** | 모듈 8 + 앱 2 | Backend 영향 없음. iOS 파트: `Project.swift` deploymentTargets 26 → 17/14(REQ-02, BRIEF) | — |
| **Day 3 (app MwonmalAPI 생성)** | v1.0 yml로 43 op 컴파일 | 없음. v1.1 필드(#11·12·15)는 전부 선택 필드라 나중에 재생성해도 호출부가 안 깨짐. `aiModel` 문자열을 "engine:model"로 파싱하지 **말 것**(v1.1 `engine` 필드를 기다림) | v1.1 yml 미리 만들기(제출본 고정) |
| **Day 4 (server 뼈대·마이그레이션·/levels·Compose)** | FastAPI 뼈대, Alembic 17테이블, `/levels`, schemathesis | **① 폴더를 컨텍스트 우선으로 생성(B-0)** — `/levels`는 `app/identity/api/levels.py`, `app/decode/…`는 빈 `__init__.py`+`engine_port.py` Protocol만(구현 0). **② Alembic ENUM 전략 확정**: dbml `Enum`을 MySQL 네이티브 `ENUM`으로(계약 충실, `dbml2sql` diff 검사 유지). v1.1의 값 추가(`MACOS`·`WATCHOS`)는 `ALTER … MODIFY ENUM`(끝에 추가는 메타데이터 변경으로 빠르다고 알려짐 — **확인 필요**, 아니면 Day 4에 미리 넣는 편이 싸므로 `device_platform`에 `MACOS, WATCHOS`를 **초기 마이그레이션에 포함**하고 dbml v1.1 문안과 맞춘다. 서버가 값을 쓰지 않으면 v1.0 계약과 충돌 없음). **③ `.env.example`에 키 이름만**: `GEMINI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY, VLLM_BASE_URL, GROQ_API_KEY, MWONMAL_STT_CHAIN, MWONMAL_AI_CHAIN_*, MWONMAL_AI_QUOTA__*, ROUTER_ALLOW_DEGRADED`(13번 §5-2의 `ANTHROPIC_API_KEY, STT_API_KEY`를 제공자별로 갱신). gitleaks 게이트 그대로. **④ `/ready`에 Redis ping 포함**(계획대로) — 한도·브레이커가 Redis에 의존하므로 Redis 없이는 ready 아님. `test_health.py`의 43 op 검사 유지, 마이그레이션 테이블 수 검사는 **17**(ai_usage는 0002) | EngineRouter 구현, ai_usage 마이그레이션(둘 다 Day 11), 워커 큐(Day 17) |
| **Day 5 (blue-green·Caddyfile)** | 블루그린 스크립트, Caddyfile | **⑤ Redis 키 규약을 문서로 고정**(`services/api/README.md` 또는 ADR-0005): `ai:quota:*`, `ai:cb:*`, `ai:user:*`, `mw:q:*`. 블루·그린 두 버전이 **같은 키**를 봐야 한도가 두 배로 새지 않는다 → 키에 앱 버전을 넣지 않는다. Caddyfile `X-Request-Id`는 이미 있음 → `ai_usage.request_id`의 소스. 스크립트 변경 없음 | 워커 컨테이너 Compose 추가(Day 17), APNs(Day 18) |

이후 순서: **Day 11** EngineRouter + 마이그레이션 0002(`ai_usage`, `usage_daily`, enum 4종) + 평가셋 v0 → **Day 17** STT 어댑터·큐 3개 → **Day 18** `PushPayload` 빌더 + `aggregate_usage_daily`·`purge_ai_usage` cron → **Day 30** 계약 v1.1 초안 PR(B-5 표 15건) + `cost_model.py` 첫 실측 보고.

ADR 후보(REQ-20·21): `0005 EngineRouter와 무료 티어 정책`, `0006 ai_usage/usage_daily 비용 파이프라인`, `0007 PushPayload v1과 플랫폼 enum`, `0008 서버 STT 사슬과 큐 분리`. 각각 이 문서의 B-1~B-4 절을 옮기면 된다. 문서 갱신 목록: 14번 §1(AI·STT 행), §3(폴더), §5-1 4단계, §5-5(WATCHOS), §9(사용자 일 한도), §11(15건 표로 교체), §15(어댑터 표·사슬), §16(`eval/prices.yml`, `push-payload.json`); 13번 §5-2 시크릿 목록; REQUIREMENTS E표 "14번 §15 AI 라우터" 행 → "협의체 B-1 채택, ADR-0005".

---

## 열린 질문 · 확인 필요 목록 (다른 파트장·PO에게)

| # | 항목 | 누구 |
|---|---|---|
| Q1 | REQ-11 "사용자 제공 키"가 운영자 `.env` 키인지 최종 사용자 BYOK인지. BYOK면 키 저장(암호화·삭제 API)·비용 귀속·약관이 필요 → v1.2 이후 제안 | PO |
| Q2 | 강등(`none`) 결과를 prod에서 허용할지(앱 "간이 해석" 배지 전제) vs 503 유지 | PO·iOS |
| Q3 | ACTION_DUE 잠금 화면에 할 일 문장 노출 허용 여부(미리보기 숨김 옵션) | PO·QA |
| Q4 | `time-sensitive` entitlement 신청 여부 | iOS |
| Q5 | `SFSpeechRecognizer` ko-KR 온디바이스 지원(17~25 미리보기 가능성) — Apple 문서에 로케일별 목록 없음 | iOS (실기기 `supportsOnDeviceRecognition` 확인) |
| Q6 | Gemini 무료 티어 모델별 RPD/RPM 현재값, 리셋 기준 시간대 | Backend(Day 11 착수 시 설정값으로) |
| Q7 | Groq Whisper 무료 한도(2,000 req·28,800초/일·20 RPM) 재확인, whisper_local CPU 실시간 여부 실측 | Backend(Day 17) |
| Q8 | CLOVA Speech·ETRI 무료 한도, 한국어 WER 비교 | AI 파트 |
| Q9 | MySQL `ALTER … MODIFY ENUM` 값 추가가 INSTANT인지(아니면 Day 4에 미리 포함) | Backend(Day 4) |
| Q10 | watchOS 앱 `apns-topic` 명명(`.watchkitapp` 접미) | iOS(v2) |
