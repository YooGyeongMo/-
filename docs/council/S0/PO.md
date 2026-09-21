# PO 의견서 — 비용 모델(REQ-13)·BM·무료 티어 운영·지표 연결·iPad/워치 우선순위

> 협의체 1차 세션 2026-09-19 · 역할: PO · 근거 문서: REQUIREMENTS.md B·D절, 01 PRD §1·§4·§9·§10, 14 §5-1·§5-2·§8·§12·§14·§15·§16, 12 §8-2·§10·§13, 15 T-B14·T-C2·T-D4·H·I, 16 §1-2·§3.
> 초안 코드·데이터는 같은 폴더에 두었다(저장소 미수정): `cost_model_draft.py`, `pricing.yml`, `usage.yml`, `pricing_example.yml`(⚠ 가정 단가, 민감도 시연용).
> 단가·무료 한도의 실제 수치는 전부 **확인 필요**로 두었다. 아래 표의 "원" 수치는 예시 단가로 돌린 **구조 검증용**이며 사실이 아니다.

## 0. 한 장 요약 (결정 5개)

| # | 결정 | 한 줄 |
|---|---|---|
| PO-1 | `services/eval/cost_model.py` + `pricing.yml` + `usage.yml` 3파일, 표준 라이브러리만 | 비용 = Σ(1인당 호출 × 토큰 × 단가) + STT + 저장 + 고정비. 무료 한도는 "RPD×30까지 0원, 초과분은 pay/fallback/degrade" 정책으로 계산 |
| PO-2 | BM 기본 가설 = **무료+구독(녹음은 유료 전용)**. 팀 라이선스는 v1.1 검증, B2B 사전은 계약만 | 예시 단가로도 **STT(녹음)가 MAU당 원가의 60~70%**. 무료 사용자에게 녹음을 열면 어떤 구독가로도 안 맞는다 |
| PO-3 | 무료 티어 운영 = 키는 sops `.env`만, 라우터 `over_limit` 3정책, 개발 중 일일 호출 예산 = 무료 RPD의 50% | REQ-11·REQ-27 그대로. 한도 초과는 폴백 → 503, 결제 없음 |
| PO-4 | 사용량 입력은 **서버 DB가 진실**, Amplitude는 행동 지표. `eval/usage_snapshot.py`가 월 1회 `usage.yml` 갱신 | 15개 이벤트 중 비용 입력을 직접 바꾸는 것은 5개, 나머지는 리텐션→MAU 경로 |
| PO-5 | iPad = "regular size class에서 macOS 레이아웃" 그 이상 안 함. 워치 = 알림 포워딩으로 v1 가치 대부분 확보, 앱은 v2 | REQ-01·REQ-04 범위 안에서 자를 것을 자른다 |

---

## 1. PO-1. REQ-13 MAU당 월 비용 자동 산정기

### 결정 기록

1. **의도** — REQ-13 "MAU마다 한 달에 얼마"를 코드로 답하고, REQ-12 라우팅 결정(품질·지연·원가)의 원가 축을 같은 숫자로 맞춘다. 14번 §15 "라우터의 1순위/폴백 결정은 이 표(평가셋)로만 바꾼다"에 **비용 열**을 붙이는 것이 목적.
2. **비용** — 코드 ~350줄(초안 완료, 표준 라이브러리만), 단가 파일 유지 월 30분(공식 페이지 확인 + `verified_on` 갱신), 사용량 스냅샷 스크립트 1개(S5 Day 29 관측 이슈에 얹음). 돈 0. 무료 한도: 산정기 자체는 외부 호출 없음.
3. **대안**
   - (a) 스프레드시트: 빠르지만 REQ-13 "코드로, 측정값 갱신"과 PR 리뷰·테스트 불가 → 탈락.
   - (b) 제공자 청구서(billing export) 그대로 읽기: 실제값이라 정확하지만 **예측**이 안 되고(MAU 10배면?), 무료 티어라 청구서가 비어 있다 → 탈락. 단, 측정값 검증용으로 월 1회 대조는 한다.
   - (c) PyYAML·pandas 의존: 편하지만 `services/api`와 다른 venv가 하나 더 생기고, 과제 조건 "의존성 없음"에 어긋남 → 탈락. 대신 YAML **부분집합(중첩 맵+스칼라+주석)** 로더 60줄.
4. **왜** — 비용은 "1인당 호출 수 × 호출당 토큰 × 단가"로 분해되고, 세 인자의 원천이 다르다(DB 측정 / 프롬프트 측정 / 공식 가격표). 원천별로 파일을 나누고(`usage.yml`, `pricing.yml`의 `tasks`, `pricing.yml`의 `models`) 계산만 코드에 두면, 어느 숫자가 바뀌었는지 PR diff로 보인다. 14번 §15의 라우터 표 한 줄을 그대로 "트랙"으로 옮겨서 REQ-10 4트랙(API·온디바이스·MLX·sLLM)을 같은 표에서 비교한다.
5. **영향 파일/문서** — 신규 `services/eval/cost_model.py`, `services/eval/pricing.yml`, `services/eval/usage.yml`, `services/eval/usage_snapshot.py`, `services/eval/tests/test_cost_model.py`; 14번 §15 "평가셋" 문단에 비용 열 추가·§16 모노레포 트리의 `eval/` 위치를 `services/eval/`로 일치(⚠ 현재 §16은 루트 `eval/`, 과제 지시는 `services/eval/` — **하나로 정해야 함**, PO 의견은 `services/eval/`: 서버 파이썬 툴체인(uv, ruff, pytest)을 그대로 쓰기 위해); 14번 §8 "AI 비용" 행을 이 모델 출력으로 대체; 16번 §3 S5 Day 30 "관측 대시보드 4개"에 비용 대시보드 1장 추가; REQUIREMENTS REQ-13 영향 열 `eval/cost_model.py` → `services/eval/cost_model.py`.
6. **검증 방법** — (i) 단위 테스트: `calls_per_user` 손계산 벡터, 무료 한도 경계(RPD×30 ±1), 폴백 3단 캐스케이드, `degrade` 거절 건수, 손익분기 역산 항등식 `allowed_cost(breakeven_price(x)) == x/MAU`. (ii) 월 1회 대조: 제공자 콘솔 실제 사용량(요청 수·토큰) vs 모델 예측, 오차 ±20% 밖이면 `tasks` 토큰 갱신. (iii) `make cost`가 CI에서 돌아 `pricing.yml`에 `verified_on` 비어 있는 모델이 있으면 **경고(실패 아님)**.
7. **리스크와 되돌리는 조건** — 리스크: 가정값이 측정값으로 안 바뀌고 "그럴듯한 숫자"로 굳음 → `usage.yml`의 `source: assumption`이 S5 이후에도 남아 있으면 이슈 자동 생성. 무료 한도가 달마다 바뀜(2025년에 실제로 여러 번) → `verified_on` 30일 초과 시 경고. 되돌리는 조건: 유료 전환 후 청구서와 모델 오차가 3개월 연속 ±30% 밖이면 모델 구조(토큰 프로파일 → 실제 청구 기반)로 재설계.

### 1-1. 파일 구성

```
services/eval/
├─ cost_model.py        계산·CLI (표준 라이브러리만)
├─ pricing.yml          단가·무료 한도·토큰 프로파일·트랙 (사람이 갱신, verified_on 필수)
├─ usage.yml            1인당 월 사용량 (usage_snapshot.py 가 갱신, source: measured|assumption)
├─ usage_snapshot.py    DB 집계 → usage.yml (S5 Day 29)
├─ evalset/             14번 §15 평가셋 200문장 (기존 계획)
└─ tests/test_cost_model.py
Makefile: make cost MAU="100 1000 10000" TRACK=api_split
```

### 1-2. 입력 스키마 (dataclass, 전부 `frozen`)

| 타입 | 필드 | 원천 | 비고 |
|---|---|---|---|
| `UsageProfile` (1인당 월) | `translations, meeting_decodes, recording_minutes, reviews, quizzes` | DB 집계 | `reviews`는 AI 비용 0이라 지금은 부하 참고용. 셀 수는 있어야 하니 남김 |
| | `dictionary_only_rate, cache_hit_rate, ondevice_detect_rate, long_meeting_rate, quiz_distractor_cache_rate` | DB(`translations.ai_model IS NULL` 비율 등) | 호출을 **빼는** 계수. 14번 §5-1 3단계·10분 재사용·§15 온디바이스 |
| `ModelPrice` | `input_per_mtok, cached_input_per_mtok, output_per_mtok` (USD/1M) | 공식 가격표 | `None` = 확인 필요 |
| | `free_rpd, free_rpm, free_tpm` | 공식 rate-limit 표 | `free_rpd None` = 무료 티어 없음 |
| | `over_limit ∈ {pay, fallback, degrade}`, `fallback_model` | 우리 정책(PO-3) | 라우터 circuit breaker 경로와 동일 |
| `TaskTokens` (작업 1회) | `input_tokens, cached_tokens, output_tokens, per_minute_input_tokens` | 프롬프트 실측(응답 usage 필드) | 14번 §8 "2k 입력(캐시)+0.5k 출력"을 5작업으로 쪼갬 |
| `Track` | `detect, nuance, quiz, meeting, summary → model_id`, `gpu_usd_per_hour, gpu_hours_per_month` | 14번 §15 라우터 표 | REQ-10 ①~④ 각각 트랙 1개 이상 |
| `SttPrice` | `usd_per_minute, free_minutes_per_month` | 공식 | 제공자 미정(14번 §1 "외부 STT API") |
| `StoragePrice` | `usd_per_gb_month, free_gb, usd_per_million_class_a, free_class_a_per_month` | R2 가격표 | `free_gb 10` = 14번 §14 |
| `FixedTier` | `max_mau, usd_per_month, label` | 14번 §12 확장 트리거·§14 표 | 계단 함수 |
| `Pricing` | 위 전부 + `fx_krw_per_usd, audio_mb_per_minute(1.0), audio_retention_days(30)` | | |

### 1-3. 함수 시그니처와 계산식

```python
def load_simple_yaml(path: Path) -> dict            # 중첩 맵+스칼라+주석만. 리스트 나오면 ValueError
def load_pricing(path: Path) -> Pricing
def load_usage(path: Path) -> UsageProfile

def calls_per_user(u: UsageProfile) -> dict[str, float]
    # ai_T   = translations × (1 − dictionary_only_rate) × (1 − cache_hit_rate)
    # detect = ai_T × (1 − ondevice_detect_rate)        # 온디바이스면 서버 호출 없음
    # nuance = ai_T                                      # 숨은 뜻·할 일은 항상 서버 (14번 §15)
    # meeting = meeting_decodes
    # summary = meeting_decodes × long_meeting_rate      # 5000자 초과 (14번 §5-2)
    # quiz    = quizzes × questions_per_quiz × (1 − quiz_distractor_cache_rate)

def volumes(mau, u, p, track) -> list[CallVolume]
    # calls_task = calls_per_user[task] × MAU
    # input  = calls × (input_tokens + minutes_per_decode × per_minute_input_tokens)   # meeting/summary만 길이 비례
    # cached = calls × cached_tokens ;  output = calls × output_tokens
    # minutes_per_decode = recording_minutes / meeting_decodes

def bill_models(vols, p, peak_factor=5.0) -> list[ModelBill]
    # free_month = free_rpd × 30
    # free_calls = min(calls, free_month − 이미 쓴 것) ; billable = calls − free_calls ; share = billable / calls
    # pay      : usd = (in×share×p_in + cached×share×p_cached + out×share×p_out) / 1e6
    # fallback : billable 만큼 CallVolume 을 fallback_model 로 넘겨 재계산 (최대 3단)
    # degrade  : usd 0, warnings 에 "503 거절 N건/월"
    # peak_rpm_needed = calls / 30 / 1440 × peak_factor  (퇴근길 18~19시 몰림 가정 5배; free_rpm 과 비교)

def stt_usd(mau, u, p)     = max(0, MAU × recording_minutes − free_minutes) × usd_per_minute
def storage_usd(mau, u, p) = max(0, GB − free_gb) × usd_per_gb_month + max(0, chunks − free_A) / 1e6 × usd_per_million_class_a
    # GB = MAU × recording_minutes × audio_mb_per_minute / 1024 × (retention_days / 30)   # 30일 보관 → 상시량 ≈ 한 달치
    # chunks = MAU × recording_minutes                                                       # 60초 조각 1개 = Class A 1회
def fixed_usd(mau, p) -> (usd, label)   # 첫 번째 max_mau ≥ MAU 인 계단

def estimate(mau, u, p, track_name) -> CostReport
    # total = ai + gpu(track.gpu_usd_per_hour × hours) + stt + storage + fixed
    # per_mau_krw = total × fx / MAU ; variable_per_mau_krw = (total − fixed) × fx / MAU   # 한계원가

def breakeven_price_krw(report, r: RevenueAssumption) -> dict
    # payers = MAU × paid_ratio
    # list_price = (total_krw / (1 − target_gross_margin)) / payers / (1 − store_fee) × (1 + vat)
def allowed_cost_per_mau_krw(list_price_krw, r) -> dict
    # net_per_mau = list_price / (1 + vat) × (1 − store_fee) × paid_ratio
    # allowed_cost = net_per_mau × (1 − target_gross_margin)

def compare_tracks(mau, u, p, tracks=None) -> list[CostReport]
def sweep(maus, u, p, track) -> list[CostReport]
def to_markdown(reports, p) -> str      # 비교표 + "단가 확인 필요" 모델 목록
def main(argv) -> int                   # --pricing --usage --mau 100 1000 10000 --track --format md|json --price --paid-ratio --store-fee
```

### 1-4. 출력 (`CostReport`)

`track, mau, ai_usd, gpu_usd, stt_usd, storage_usd, fixed_usd, fixed_label, total_usd, total_krw, per_mau_krw, variable_per_mau_krw, model_bills[ModelBill(model_id, calls, free_calls, billable_calls, usd, free_headroom, peak_rpm_needed, over_limit_action, unpriced)], warnings[]`

- **월 원가** = `total_krw`, **MAU당 원가** = `per_mau_krw`, **한계원가** = `variable_per_mau_krw`(고정비 뺀 것 — BM 허용선은 이걸로 본다).
- **손익분기 구독가** = `breakeven_price_krw(...)["list_price_breakeven"]`, 목표 마진 반영가 = `["list_price_target_margin"]`.
- **트랙별 비교표** = `to_markdown(compare_tracks(...))`. 대시보드(REQ-13 "+ 대시보드")는 `--format json`을 Grafana JSON 데이터소스로 읽는다(S5 Day 30).
- **무료 한도 소진 MAU** = `free_headroom`이 1.0을 넘는 첫 MAU (sweep으로 찾음). 아래 시연에서 Gemini 무료(가정 RPD 250)는 **MAU ~140**에서 소진.

### 1-5. `pricing.yml` 형식과 갱신 절차

형식은 `pricing.yml` 초안 그대로(중첩 맵만, 리스트 금지). 최상위 키: `verified_on, fx_krw_per_usd, audio_mb_per_minute, audio_retention_days, models{}, stt{}, storage{}, fixed_tiers{}, tasks{}, tracks{}`.

갱신 절차(단가는 ADR 불필요, 정책 필드 `over_limit`·`fallback_model`·트랙 구성 변경은 ADR):
1. 공식 가격·rate-limit 페이지를 열어 값 확인 → 해당 키의 값 + `verified_on: YYYY-MM-DD` + `# source: URL` 주석.
2. `make cost` 실행, 결과 표를 PR 본문 "테스트"에 붙임. `verified_on` 비어 있는 모델은 CI 경고.
3. 무료 한도(`free_rpd/rpm/tpm`)는 **월 1회** 재확인(2025년 중 Gemini 무료 RPD가 크게 내려간 이력이 있어 "확인 필요"로 둠).
4. 토큰 프로파일(`tasks`)은 실측으로만: 라우터가 응답 `usage`를 `translations.ai_usage_json`(v1.1 컬럼 후보, 없으면 서버 로그 지표)에 남기고 월 평균으로 갱신.
5. 환율은 월초 매매기준율.

2026-09 기준 확인 필요 목록: Gemini 무료 티어 RPD/RPM/TPM과 유료 단가(Flash·Flash-Lite), Groq 무료 한도, Anthropic 무료 API 티어 존재 여부(PO 이해로는 없음 → 사용자 제공 키 전제, 확인 필요)와 Sonnet/Haiku 단가·캐시 읽기 단가, OpenAI mini 단가·데이터 공유 조건 무료 토큰 프로그램 존속 여부, STT 제공자 선정과 분당 단가, R2 GB·Class A 단가, t4g.small 서울 온디맨드, App Store 수수료(Small Business Program 15%), 스팟 GPU 시간당.

### 1-6. 구조 검증 시연 (⚠ `pricing_example.yml` = 가정 단가, 사실 아님)

`usage.yml` 가정: 해석 30/월, 회의 4건·120분/월, 복습 12, 판능시 2, 사전만 10%, 캐시 20%, 온디바이스 0, 긴 회의 25%, 오답 캐시 50%.

| 트랙 | MAU 1,000 | AI | STT | 고정 | 합계(원/월) | MAU당 | 한계원가/MAU |
|---|---|---|---|---|---|---|---|
| api_free_only (REQ-11 개발) | 1,000 | 0 | 720$ | 15$ | 1,031,251 | 1,031 | 1,010 |
| api_split (14번 §15 기본안) | 1,000 | 375$ | 720$ | 15$ | 1,555,865 | 1,556 | 1,535 |
| api_split_haiku | 1,000 | 125$ | 720$ | 15$ | 1,206,122 | 1,206 | 1,185 |
| api_gemini_paid | 1,000 | 66$ | 720$ | 15$ | 1,123,416 | 1,123 | 1,102 |
| sllm_self (GPU 상시 1대) | 1,000 | 0 | 720$ | 15$+360$ | 1,535,251 | 1,535 | 1,514 |
| **녹음 0으로 두면** api_split | 1,000 | 119$ | 0 | 15$ | 187,018 | **187** | 166 |
| 녹음 0, api_split_haiku | 1,000 | 40$ | 0 | 15$ | 76,339 | 76 | 55 |

읽는 법(구조적 결론, 단가가 바뀌어도 유지될 가능성이 높은 것):
- **STT가 MAU당 원가를 지배한다**(예시에서 65%). AI 라우터를 아무리 싸게 짜도 녹음 무료 개방이면 MAU당 1,000원대. 14번 §15 "호출 감소"는 텍스트 해석에만 걸려 있고 **녹음 분 감소 장치가 없다** → PO-2에서 다룬다.
- 무료 티어(Gemini RPD 250 가정)는 MAU 100대에서 끝난다. 개발·베타(TestFlight 내부, 수십 명)에서는 0원이 맞지만 **출시 = 유료 전환 결정**이다(REQ-12).
- 온디바이스 하이브리드는 **돈이 아니라 무료 한도를 아낀다**(탐지가 이미 무료 트랙이므로). 돈을 아끼려면 nuance를 온디바이스로 옮겨야 하는데 그건 품질 위험(15번 H "평가셋 80% 미만이면 서버로").
- sLLM 자체 서빙은 MAU 1,000에서 API보다 비싸다(14번 §15 "GPU 서빙비 > API비" 확인). 손익 역전 MAU는 실제 단가 확인 뒤 `sweep`으로 찾는다.

---

## 2. PO-2. BM 가설 3개와 MAU당 원가 허용선

### 결정 기록

1. **의도** — REQ-12 "BM(MAU당 원가)을 같이 고려한 라우팅"의 **허용선 숫자**를 만든다. 라우터·기능 범위 결정에서 "이 기능은 MAU당 얼마까지"라는 상한이 없으면 REQ-12는 구호로 남는다.
2. **비용** — 문서만. 가격 실험은 v1.0 이후(PRD §4.7 "결제 제외"가 제출본 범위이므로 v1.0에 결제 화면 없음).
3. **대안** — (a) 완전 무료 + 포트폴리오: 원가 상한이 0에 수렴, 녹음을 열 수 없음 → BM 부재로 탈락(REQ-12 위반). (b) 광고: 회의 원문을 다루는 앱에 광고 SDK는 REQ-14·12번 §12 불변식과 충돌, 판교 신입 규모(8.3만 명, PRD §2.3)로는 광고 단가 의미 없음 → 탈락. (c) 유료 단일(무료 없음): 온보딩→첫 해석 퍼널(16번 §1-2)이 막힘, 학습 루프(복습·스트릭)가 무료여야 리텐션이 생김 → 탈락.
4. **왜** — 원가 구조가 "텍스트 해석은 싸고(수십~수백 원/MAU), 녹음은 비싸다(천 원대/MAU)"로 갈리므로, 가격 경계를 **기능 경계와 같은 곳**에 둔다: 무료 = 텍스트 해석·카드·복습·판능시(학습 루프 전부), 유료 = 회의 녹음·받아쓰기(+긴 회의 요약). 이 경계는 PRD IA(§0)에서 "녹음은 항상 회의 안에서"라 자연스럽고, 동의 시트(W-02a)가 이미 게이트 화면이라 결제 게이트를 얹기 쉽다.
5. **영향 파일/문서** — PRD §4.7 "결제 제외"에 "v1.0 제외, v1.1 가설 A 검증" 주석; 14번 §15 라우터 표에 "무료/유료 사용자별 트랙" 열; REQUIREMENTS에 REQ-15(신규 제안) "무료 사용자에게는 녹음 월 N분 상한, 유료는 무제한(공정 사용)" 등록 요청; 계약 v1.1 백로그(12번 §13)에 `users.plan` + `GET /users/me`에 `plan, recordingMinutesLeft` 필드; `usage.yml`에 세그먼트(`free/paid`)별 프로파일.
6. **검증 방법** — S5부터 `usage_snapshot.py`가 free/paid 세그먼트별 사용량을 내고, 허용선 대비 실제 한계원가를 월간 리포트로. 가격 수용도는 v1.1 TestFlight 설문 1문항(Van Westendorp 4문항까지는 과함).
7. **리스크와 되돌리는 조건** — 리스크: 녹음이 유료면 "회의실 iPad" 시나리오(REQ-01)가 무료 사용자에겐 없다 → 무료 월 30분(회의 1건) 체험. 되돌리는 조건: 유료 전환율 < 2%가 3개월이면 가설 B(팀)로 무게 이동; STT 단가가 확인 결과 예시의 1/5 이하면 녹음을 무료 상한 높여 개방.

### 2-1. 가설과 허용선 (허용선 = `allowed_cost_per_mau_krw`, **한계원가 기준**, 고정비는 별도 회수)

공통 가정(전부 확인 필요/가정): VAT 10%, App Store 수수료 15%(Small Business Program), 목표 매출총이익률 50%, 환율 1,400.

| 가설 | 가격 가정 | 전환·좌석 가정 | MAU당 순매출 | **허용 한계원가/MAU (마진 0)** | **허용 (마진 50%)** | 예시 단가 결과와 비교 |
|---|---|---|---|---|---|---|
| **A. 무료+구독** (녹음 유료) | 월 4,900원 | 유료 전환 5% | 4,900/1.1×0.85×0.05 ≈ **189원** | 189원 | **95원** | 텍스트만 api_split 166원 ✗, api_split_haiku 55원 ✓, gemini_paid 50원 ✓ → **무료 사용자 트랙은 Haiku급 이하**, Sonnet급은 유료 사용자에게만 |
| A' 같은 가설, 전환 10% | 4,900원 | 10% | 379원 | 379원 | 189원 | api_split(Sonnet nuance) 가능 |
| A 유료 사용자 1인 | 4,900원 | 본인 | 3,786원 | 3,786원 | 1,893원 | 녹음 120분 포함 1,535원 ✓ (STT 예시 단가 기준). 녹음 300분 넘으면 적자 → **공정 사용 상한 필요** |
| **B. 팀 라이선스** (5~50석, 팀 사전 공유) | 좌석당 월 3,000원 | 좌석 = MAU(전원 활성 가정 70%) | 3,000/1.1×(웹 결제 PG 3%: 0.97)×(1/0.7) ≈ **3,780원/활성 MAU** | 3,780원 | 1,890원 | 녹음 포함 api_split 1,535원 ✓. 단 PRD §4.7 "기업 계정·팀 사전 제외" → **v1.1 이후**. 팀 사전(`term_variants`, PRD §9-8)이 전제 |
| **C. B2B 사전 라이선스** (회사가 자사 용어집 검수본을 구독) | 회사당 연 120만 원 | 회사당 활성 사용자 30명 | 1,200,000/12/1.1/30 ≈ **3,030원/MAU** | 3,030원 | 1,515원 | api_split_haiku+녹음 1,185원 ✓, Sonnet 1,535원 경계. 검수 인력(사람) 비용이 별도 → 원가에 **사전 검수 시간**을 넣어야 함(모델 밖) |

세 가설의 공통 결론:
- **무료 사용자 한계원가 상한 = 100원/MAU** (가설 A, 마진 50%). 이 숫자를 라우터 정책의 상수로 둔다(`pricing.yml`에 `policy.free_user_cost_cap_krw: 100` 추가 제안). 넘으면 무료 트랙을 한 단계 싸게(Sonnet→Haiku→Gemini paid→무료 티어 폴백).
- **유료 사용자 한계원가 상한 = 1,900원/MAU**. 녹음 분 상한 = (1,900 − 텍스트 원가) / (STT 분당 원가 × 환율) → 예시 단가면 약 200분/월. 실제 단가 확인 후 재계산.
- 팀·B2B는 원가 여유가 크지만 **PRD §4.7 제외 범위**라 v1.0 결정이 아니다. v1.0에서 하는 것은 계약 v1.1에 `plan`을 넣는 것까지.

---

## 3. PO-3. 무료 티어 테스트 원칙(REQ-11) 운영 규칙

### 결정 기록

1. **의도** — REQ-11 "테스트·개발은 무료 티어만, 유료 결제 없음"과 REQ-27 "시크릿 커밋 금지"를 매일의 규칙으로 바꾼다. 1인 개발이라 실수 한 번(키 커밋, 한도 초과 자동 과금)이 곧 사고다.
2. **비용** — sops+age 키 1쌍, `.env.example` 유지, 라우터 정책 필드 3개, 일일 예산 카운터(Redis INCR, 이미 레이트리밋에 쓰는 것). 돈 0. 무료 한도: Gemini RPD·RPM·TPM(확인 필요), Groq RPD(확인 필요). Sentry·Grafana 무료(14번 §14).
3. **대안** — (a) 개발 중 유료 키 소액 충전: 편하지만 REQ-11 위반, 그리고 "무료 한도 안에서 되는가"가 사업 검증 자체 → 탈락. (b) 키를 GitHub Secrets에만 두고 로컬은 개별 관리: 로컬 `.env` 누락으로 평가셋이 안 돌고, 팀원(협의체·멘토)이 재현 못 함 → 탈락. sops 암호문은 저장소에 두되 복호화 키는 저장소 밖(13번 §5 "sops로 암호화해 두고 배포 시 복호화"와 동일).
4. **왜** — 무료 티어의 본질은 "한도가 있고 예고 없이 바뀐다"이므로, 규칙은 ① 초과 시 **돈이 나가지 않게**(over_limit≠pay 강제) ② 초과가 **보이게**(지표·경고) ③ 개발 호출이 **한도의 절반 이하**로 유지되게(제품 데모·평가셋이 항상 돌 여유)가 전부다.
5. **영향 파일/문서** — `.sops.yaml`, `services/api/.env.sops`, `.env.example`(키 이름만), gitleaks 설정; `infra/ai/router.py`(14번 §15) 정책 필드; 14번 §9 "AI 키는 `.env`(sops)" 그대로; 16번 §1-1 보안 행에 "gitleaks pre-commit"; `docs/adr/0005-free-tier-router-policy.md`.
6. **검증 방법** — gitleaks가 PR·pre-commit에서 실제 키 패턴을 잡는지 가짜 키로 1회 테스트(S0 Day 1); 라우터 단위 테스트: 429/한도 응답 → 폴백 → 폴백도 실패 → 503 `AI_UNAVAILABLE`(14번 §7), **어떤 경로에서도 유료 엔드포인트 호출 없음**을 Fake 제공자로 검증; 일일 예산 카운터 초과 시 개발용 호출이 거부되는지 테스트.
7. **리스크와 되돌리는 조건** — 리스크: 무료 한도 축소로 평가셋 200문장이 하루에 못 돎 → 평가셋을 50문장 샘플 + 주간 전체로 나눔. 사용자 제공 키(OpenAI·Claude)는 **평가 트랙 전용**, 서버 프로덕션 경로에 절대 안 꽂음(키 소유자 = 나 = 결제 발생 = REQ-11 위반). 되돌리는 조건: 출시 결정(S6) 시 REQ-12에 따라 유료 전환 ADR을 쓰고 `over_limit: pay`를 **트랙 단위로만** 연다.

### 3-1. 규칙표

| 영역 | 규칙 | 구현 |
|---|---|---|
| 키 보관 | 모든 AI·STT 키는 `services/api/.env.sops`(sops+age)에만. 평문 `.env`는 `.gitignore`, `.env.example`에는 키 **이름**만 | 13번 §5, 14번 §9 |
| 키 종류 | `GEMINI_API_KEY`(무료 티어, 내 계정), `GROQ_API_KEY`(무료), `ANTHROPIC_API_KEY`·`OPENAI_API_KEY`는 **평가셋 전용·선택**(비어 있으면 그 트랙은 "미측정"으로 표기, 실패 아님) | `make eval MODEL=`가 키 없으면 skip |
| 사용자 제공 키(REQ-11) | `eval/` CLI 인자 또는 로컬 `.env`로만. 서버 라우터는 사용자 키를 **받지 않는다**(계약에 없음, 기밀 원문이 사용자 키로 나가는 경로 금지) | 라우터 설정에 키 소스 = env 뿐 |
| 결제 방지 | 무료 티어 계정에 결제수단 미등록 상태 유지. `pricing.yml`·라우터 설정의 `over_limit`는 개발·dev 환경에서 `pay` 금지(설정 로드 시 assert) | `APP_ENV != prod and over_limit == pay → 기동 실패` |
| 한도 초과 시 라우터 | 제공자 429/RESOURCE_EXHAUSTED → 즉시 폴백(재시도 없음, 14번 §7) → 폴백도 실패 → 503 `AI_UNAVAILABLE` + `Retry-After: 5`. circuit breaker(30초 2회)는 그대로. **사전 매칭 결과는 503이어도 반환하지 않는다**(계약상 TranslationResponse 완전체만) — v1.1에서 "사전만 결과" 부분 응답 검토 | `infra/ai/router.py` |
| 우선 사용 순서 | 사전 → 10분 재사용 캐시 → Gemini 무료 → Groq 무료 → 503. Claude는 개발 중 서버 경로에 없음(트랙 `api_free_only`) | 트랙 설정 `APP_ENV=dev → api_free_only` |
| 개발 중 호출 예산 | 일일 예산 = 무료 RPD × 50%(나머지 50%는 데모·평가셋·협의체 시연 여유). Redis `ai_budget:{provider}:{date}` INCR, 초과 시 개발 요청은 `503 AI_UNAVAILABLE`로 동일 처리하고 Sentry가 아닌 **로그 지표**로만 | 레이트리밋 코드 재사용(14번 §9) |
| 평가셋 예산 | 200문장 × 트랙 수 = 하루 예산 초과 가능 → 일간 50문장 샘플(고정 seed), 주 1회 전체 200 | `make eval SAMPLE=50` |
| 테스트 | 단위·계약 테스트는 **항상 Fake 제공자**. 실제 무료 호출은 `make eval`과 수동 데모뿐. CI에서 외부 AI 호출 0 | pytest fixture |
| 관측 | 제공자별 호출 수·429 수·폴백 수·503 수를 지표로(14번 §10). 하루 호출이 예산 80% 넘으면 Grafana 알림 | 14번 §10 알림 목록에 1줄 추가 |
| 프라이버시 | 무료 티어 데이터 사용 정책(제공자가 무료 입력을 학습에 쓰는지)은 **확인 필요**. 확인 전까지 dev 환경 평가셋만 실제 판교어 문장, 실사용자 원문은 TestFlight 베타부터 → 베타 시작 전 정책 확인이 게이트 | S5 시작 조건 |

---

## 4. PO-4. 제품 지표·Amplitude 이벤트 → 비용 모델 입력 연결

### 결정 기록

1. **의도** — REQ-13 "수치는 측정값 갱신"의 **갱신 경로**를 정한다. 어떤 숫자가 어디서 오고 누가 언제 `usage.yml`을 바꾸는지.
2. **비용** — `usage_snapshot.py`(SQL 6개, 100줄), 월 1회 실행(cron 아님, 사람 PR — 숫자가 바뀌는 것을 리뷰로 보게). Amplitude 무료 플랜 이벤트 한도(확인 필요) 안.
3. **대안** — (a) Amplitude만으로 사용량 산출: 옵트아웃(A-09 토글)·이벤트 유실·`translation_submitted`≠실제 AI 호출(사전 적중·캐시는 클라이언트가 모름) → 비용 입력으로 부정확, 탈락. (b) 제공자 청구 대시보드: 무료 티어라 비어 있고 사용자 단위 분해 불가 → 탈락. 결론: **DB가 진실, Amplitude는 행동·리텐션**(16번 §1-2 "목적 분리" 그대로).
4. **왜** — 비용 입력은 "서버가 실제로 부른 것"이고 그건 `translations.ai_model`(14번 §5-1 8단계)과 워커 작업 기록에 이미 남는다. Amplitude 이벤트는 그 호출을 **일으키는 행동**과 **MAU를 유지하는 행동**을 알려 주므로, 비용 모델에는 "MAU 성장·세그먼트 비율" 경로로만 들어간다.
5. **영향 파일/문서** — `services/eval/usage_snapshot.py`; 계약 v1.1 백로그(12번 §13)에 `translations.ai_usage_json`(입력·캐시·출력 토큰, 제공자) 컬럼 — 없으면 서버 로그 집계로 대체; 12번 §10 이벤트 표에 "비용 입력 여부" 열; 16번 §1-2 Amplitude 대시보드 5개에 "세그먼트별 사용량" 1개; 14번 §10 지표에 "제공자별 토큰".
6. **검증 방법** — 월 스냅샷의 `translations` 합이 제공자 콘솔 요청 수와 ±10% 이내; `source: measured`로 바뀐 뒤 `make cost` 결과와 이전 가정값 차이를 PR 본문에 기록(첫 측정이 가정과 2배 이상 다르면 BM 허용선 재검토 이슈).
7. **리스크와 되돌리는 조건** — 리스크: 베타 사용자 수십 명 → 통계가 개인 편차에 흔들림(한 명이 회의 10건 녹음). 중앙값과 평균을 같이 내고, 비용 모델은 **평균**(총비용이 평균×MAU)이지만 상한 정책(공정 사용)은 p95로 정한다. 되돌리는 조건: 없음(측정 없이는 REQ-13 자체가 성립 안 함).

### 4-1. 비용 입력 ← 원천 매핑

| `usage.yml` 필드 | 원천(진실) | SQL/집계 | Amplitude 보조 이벤트 |
|---|---|---|---|
| `translations` | `translations` WHERE `source_type != MEETING_NOTE` / MAU | 월별 count / distinct user | `translation_submitted`(퍼널 시작, 실패 포함이라 항상 ≥ DB) |
| `dictionary_only_rate` | `translations.ai_model IS NULL` 비율(사전만으로 끝난 건) | | — (클라이언트 모름) |
| `cache_hit_rate` | 10분 재사용 히트 카운터(Redis → 일 집계 테이블 또는 로그 지표) | | — |
| `ondevice_detect_rate` | 요청에 온디바이스 결과 포함 비율(v1.1, `X-Client-Prefill` 등 계약 후보) | | `translation_submitted.inputSource` 보조 |
| `meeting_decodes`, `long_meeting_rate` | `meeting_recordings` status=DONE / MAU; transcript 길이 > 5000자 비율 | | `recording_finished` |
| `recording_minutes` | Σ `meeting_recordings.duration_sec`/60 / MAU (p50·p95 함께) | | `recording_finished.minutes` |
| `reviews` | `review_sessions.finished_at IS NOT NULL` / MAU | | `review_finished` |
| `quizzes`, `quiz_distractor_cache_rate` | `quiz_sessions` / MAU; 오답 캐시 히트 지표 | | `quiz_finished` |
| `tasks.*_tokens` (pricing.yml) | 제공자 응답 usage → `ai_usage_json` 또는 로그 지표 월 평균 | | — |
| MAU 자체 | `translations ∪ review_logs ∪ quiz_sessions ∪ meeting_recordings` distinct user(월) | | Amplitude MAU(옵트아웃 제외라 항상 ≤ DB) |

### 4-2. 제품 지표 5개 → 비용 모델에 주는 영향

| 제품 지표 | 이벤트·속성 | 비용 모델로 가는 경로 | PO 판단 |
|---|---|---|---|
| 해석 뒤 답장 시간(대용: 결과 화면 체류) | `translation_result_left.secondsOnScreen, expandedNuance` | 직접 입력 없음. `expandedNuance` 비율이 낮으면 **nuance 호출을 지연·생략**(탭 전 미호출)할 근거 → `nuance` 호출 계수 신설 후보 | 원가의 큰 축(Sonnet)이 "안 펼치는 사용자"에게 낭비되는지 보는 지표 |
| 마감 전 완료율 | `action_checked.beforeDue, fromNotification` | 비용 0(APNs 무료). 리텐션 경로로 MAU 유지 | 가치 지표, 원가 무관 |
| 복습 정답률 | `review_answered.rating`, `review_finished.goodRate` | 비용 0(SM-2는 서버 계산, AI 없음). 정답률↓ → AGAIN↑ → due 카드↑ → 세션↑ → API 부하만 | **학습 루프는 AI 원가가 0**이라는 것이 BM의 핵심 근거: 무료 사용자가 오래 머물러도 돈이 안 든다 |
| 7일 스트릭 | `review_finished.streakDays` 코호트 | MAU 유지율 → `sweep`의 MAU 시나리오. 스트릭 유지 사용자 비율 = 유료 전환 후보 풀(가설 A `paid_ratio`의 상한 근거) | |
| 온보딩 기간 | `onboarding_completed.skippedSteps`, 온보딩→첫 해석 시간 | 첫 달 `translations` 편향(신규 코호트가 적게 씀). 스냅샷은 가입 30일 이상 사용자만 프로파일에 넣고 신규는 별도 | 신규 사용자 원가 < 정착 사용자 원가. 성장기엔 평균 원가가 낮게 보이는 착시 방지 |

### 4-3. 갱신 리듬

- 월초: `python services/eval/usage_snapshot.py --month 2026-11 > usage.yml` → PR(diff에 숫자 변화) → `make cost` 표를 PR 본문에.
- 세그먼트: `usage.yml`에 `segments.free/paid`(v1.1 `plan` 이후)와 `segments.p95`(공정 사용 상한 설계용). `cost_model.estimate`는 세그먼트별 프로파일을 가중 합(MAU 비율)으로 받는 `estimate_segmented(mau_by_segment: dict[str,int], usage_by_segment: dict[str,UsageProfile], ...)` 추가.

---

## 5. PO-5. iPad·워치가 제품 가치에 주는 것과 우선순위

### 결정 기록

1. **의도** — REQ-01(iPad 확정)·REQ-04(워치 설계만 v1)의 범위 안에서, 1인·7주 일정(16번 §3)에 맞게 **무엇을 잘라도 되는지** PO로서 정한다. 기능이 아니라 사용자 순간(moment) 기준.
2. **비용** — iPad: 코드 추가 거의 0(macOS 레이아웃 재사용, 12번 D-2 확장), 대신 **스냅샷 매트릭스 +2기기 × Dynamic Type**, 멀티태스킹 QA, 심사 스크린샷 세트 1개 추가 ≈ 1.5일. 워치: 앱을 만들면 타깃·WatchConnectivity·복습 카드 UI·심사 ≈ 5일 이상 + 알림 payload 계약(v1.1). 무료 한도 무관.
3. **대안**
   - iPad (a) iPhone 레이아웃을 그대로 키움: 심사 통과는 되지만 REQ-01 "iPad는 macOS와 같은 넓은 레이아웃" 위반 → 탈락. (b) iPad 전용 기능(Pencil 필기 해석, 다중 창, 외부 디스플레이): 회의실 시나리오에 매력적이나 화면 설계(02번)가 없고 계약도 없다 → v2 백로그.
   - 워치 (a) v1에 워치 앱(복습 카드 4버튼): 화면 설계 없음(15번 T-D4), 일정 초과 → 탈락. (b) 아무것도 안 함: REQ-04 "지금부터 payload·딥링크·카드 모델을 워치가 쓸 수 있게 설계" 위반 → 탈락.
4. **왜** — **iPad의 가치는 "회의실에서 녹음하며 받아쓰기를 넓게 본다"(REQ-01 왜 열)** 하나이고, 그건 macOS 레이아웃(W-02·W-04·W-07 세 열)을 `horizontalSizeClass == .regular`에서 그대로 쓰면 나온다. 그 이상(멀티 창, Pencil)은 원가·가치 모두 불확실. **워치의 가치는 "손목에서 퇴근길 복습 알림 → 지금 복습/미루기"(REQ-04 왜 열)** 이고, Apple 문서(watchOS "Taking advantage of notification forwarding", 2026-09-19 확인)에 따르면 **서버가 iPhone으로 보낸 원격 알림은 iPhone이 잠겨 있고 워치를 착용·잠금 해제 상태면 워치로 전달된다.** 즉 워치 앱 없이도 알림 자체는 손목에 간다. 워치에서 액션 버튼("지금 복습/미루기")이 iOS 앱의 `UNNotificationCategory`로 그대로 표시되는지는 **확인 필요**(문서 "Adding actions to notifications on watchOS" 추가 확인). 따라서 v1은 payload·카테고리·딥링크를 워치 호환으로 설계하는 것만으로 REQ-04를 만족하고, 워치 앱은 "복습 카드를 손목에서 넘긴다"는 가치가 지표로 증명될 때(알림 열람률·복습 시작 fromNotification 비율) 붙인다.
5. **영향 파일/문서** — 12번 D-0·D-2에 iPad 규칙(`regular` = macOS군, `compact`(Slide Over·1/3 분할) = iPhone군, 전환 시 경로 유지); 12번 §11 스냅샷 매트릭스에 iPad 13"·iPad mini 추가; 12번 §8-2·§13 알림 payload를 워치 호환으로(아래 요구); 15번 T-D4 갱신("워치 없음" → "워치 앱 없음, 포워딩 의존, v2"); `contracts/push-payload.json`(14번 §16) v1.1.
6. **검증 방법** — iPad: 스냅샷(regular/compact × DT 3단계 × 빈·에러) + Maestro 흐름 4개 중 "녹음→결과" 1개를 iPad 시뮬레이터에서도; 실기기 Split View 전환 중 녹음 세션 유지 확인. 워치: 실기기(iPhone 잠금 + 워치 착용)에서 `REVIEW_REMINDER` 수신·액션 동작 확인을 S5 Day 28 실기기 알림 확인에 포함(확인 안 되면 "확인 필요" 해소 실패 → 워치 앱 v2 우선순위 상향).
7. **리스크와 되돌리는 조건** — iPad: Stage Manager·외부 디스플레이에서 레이아웃 깨짐 → v1은 "지원하되 최적화 안 함", 크래시만 막음. 되돌리는 조건: iPad 사용 비율 < 5%(Amplitude platform 속성)가 3개월이면 iPad 스냅샷을 야간 잡으로 내려 PR 시간 절약. 워치: 포워딩된 알림에 액션이 안 뜨면 "미루기"가 손목에서 불가 → v1.1에 워치 앱(알림 인터페이스만, 앱 UI 없음)을 최소로.

### 5-1. 우선순위 표 (PO 관점)

| 항목 | 사용자 순간 | 가치 | 원가(시간) | v1.0 | 잘라도 되는가 |
|---|---|---|---|---|---|
| iPad regular = macOS 세 열(W-02/W-04/W-07/W-03) | 회의실 iPad로 녹음·받아쓰기 넓게 | 높음(REQ-01 왜) | 0.5일 | ✅ | 안 됨(REQ-01) |
| iPad compact(Slide Over·1/3) = iPhone 레이아웃 | 메신저 옆에 띄워 해석 | 중 | 0.5일(규칙만) | ✅ 최소 | 레이아웃 최적화는 자름 |
| iPad 스냅샷·심사 스크린샷 | — | — | 1일 | ✅ | 안 됨(심사) |
| iPad 다중 창(Stage Manager 창 2개) | 회의 2개 나란히 | 낮음 | 2일+ (12번 D-20 단일 창 정책과 충돌) | ❌ | 자름 |
| iPad Pencil·Scribble 입력 해석 | 손글씨 메모 해석 | 낮음(입력은 붙여넣기·캡처가 주) | 2일 | ❌ | 자름 |
| iPad 외부 키보드 단축키(⌘↩ 등) | macOS와 동일 | 중 | 0(CommandGroup 공유) | ✅ 공짜 | — |
| 워치 호환 알림 payload·카테고리 | 손목에서 복습 알림·"지금/미루기" | 높음(REQ-04 왜) | 0.5일(설계) | ✅ | 안 됨(REQ-04) |
| 워치 앱(복습 카드 4버튼) | 손목에서 카드 넘김 | 중(가설, 미검증) | 5일+ | ❌ | v2 |
| 워치 컴플리케이션(스트릭·due 수) | 하루 한 번 보기 | 낮음 | 2일 | ❌ | v2 |
| 오늘 복습 위젯(iOS) | 홈 화면 | 중 | 1.5일 | ❌ v1.1 (15번 T-D4) | 유지 |

### 5-2. 워치 호환을 위해 v1.0에 넣을 설계 요구 (구현 아님)

- payload: `{type, translationId?, meetingId?, projectId?, quizId?, badge, dueCount?}` + `category`(`REVIEW_REMINDER` → `review.reminder` 카테고리, 액션 `review.now`·`review.snooze`), `thread-id`(회의별 그룹), `interruption-level`(퇴근길 = active). 텍스트 없음(REQ-14 불변식: 알림 본문에 원문 금지).
- 카드 모델: `Domain`의 `ReviewCard`(앞: term, 뒤: plainKo, 출처 칩)를 **Foundation만 의존**으로 유지(12번 §0 원칙) → 워치 타깃이 그대로 import 가능.
- 딥링크: `DeepLink.parse` 순수 함수(12번 §8-2)는 워치에서도 같은 코드.

---

## 6. 레드팀에 넘기는 질문·확인 필요 목록

1. 단가·한도 12항목(§1-5) — 전부 "확인 필요". 특히 Anthropic 무료 API 티어 부재 여부와 무료 티어 데이터 학습 정책.
2. STT 제공자 미정 — 원가의 최대 축인데 14번 §1이 "외부 STT API"로만 되어 있음. 후보 비교(무료 분, ko 품질, 60초 조각 배치)를 AI 에이전트 과제로 요청.
3. `eval/` 위치 불일치(14번 §16 루트 vs 과제 `services/eval/`) — 한 곳으로.
4. 가설 A의 "녹음 유료"는 PRD §4.7 "결제 제외"와 v1.0에서 충돌하지 않지만(결제 없음 = 전원 무료), **v1.0 베타에서 녹음 무료 개방 시 원가**가 MAU당 1,000원대(예시 단가)라 베타 인원 상한(예: 50명)을 정해야 함.
5. 워치 포워딩 알림에서 iOS 앱 카테고리 액션이 표시되는지 — Apple 문서 추가 확인 필요.
6. 온디바이스 트랙이 돈을 아끼려면 nuance까지 온디바이스여야 하는데, 15번 H "평가셋 80% 미만이면 서버" 기준을 nuance에 적용할 것인지.
