# ADR-0009: MAU당 월 원가는 `eval/cost_model.py`(표준 라이브러리, TOML 입력)가 계산하고, BM은 v1.0에서 코드 없이 가설 3개로만 둔다

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-09-21) |
| 관련 REQ | REQ-12(BM 고려 라우팅), REQ-13(MAU당 비용 자동 산정), REQ-11, REQ-23(있는 것을 쓴다), REQ-32(무료 티어 우선) |
| 관련 결정 | FD-6, FD-11, PO-1·2·4, Backend B-2, PM S2-G·S5-A, RT-A-07·21, RT-B-08·09·14·15·16, U-1·U-2·U-18·U-19, 사용자 결정 (4) |
| 출처 | `council/S0/PO.md` §1·§2·§4, `council/S0/Backend.md` B-2, `council/S0/REDTEAM_B.md` §2, `council/cost_model_draft.py`(초안, 저장소 밖) |

## 1. 의도
REQ-13 "MAU마다 한 달에 얼마"를 코드로 답하고, REQ-12 라우팅 결정의 원가 축을 ADR-0007 점수표의 "원가/건" 열과 같은 숫자로 맞춘다. 사용자 지시 "초반 BM 전략도 생각해놔야 해"에 대해 v1.0은 결제 없이 **가설·실험·허용 원가**만 문서로 둔다(`docs/bm/early-strategy.md`). 실측값은 공개하지 않는다(사용자 결정).

## 2. 비용
- 돈: 0. 계산기는 외부 호출 없음.
- 시간: 코드 ~350줄(PO 초안 재사용) + pytest 0.5일(S2), 실측 갱신 0.5일(S5), `usage_snapshot.py` 100줄.
- 유지보수: `pricing.toml` 월 1회 공식 페이지 확인 + `verified_on` 갱신(30분). 무료 한도는 자주 바뀌므로 `verified_on` 30일 초과 시 CI 경고(실패 아님).
- 저장소: `eval/measured/`는 `.gitignore`(MAU·1인당 사용량 비공개, U-18).

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| 스프레드시트 | REQ-13 "코드로, 측정값 갱신"·PR 리뷰·테스트 불가 |
| 제공자 청구서(billing export) 그대로 | 예측 불가(MAU 10배면?), 무료 티어라 청구서가 비어 있음. 월 1회 대조용으로만 |
| PyYAML·pandas 의존 + 자체 YAML 부분집합 로더 60줄(PO 초안) | 자체 파서는 REQ-23 위반(RT-A-21). PyYAML은 `services/api` venv 밖의 `eval/`에 의존성을 하나 더 만든다 → 표준 라이브러리 `tomllib`(3.11+)로 해결 |
| Backend B-2 입력(`usage_daily.csv` + `--on-device-ratio`)와 PO 입력(`usage.yml` 1인당 프로파일) 두 벌 | 파일명까지 겹침(`pricing.yml` vs `prices.yml`, RT-A-07). 계산 로직은 PO 초안(손익분기 역산·`over_limit` 3정책), 입력은 서버 `usage_daily`가 진실(PO-4)로 통합 |
| BM 완전 무료 + 포트폴리오 / 광고 / 유료 단일 | PO-2 대안 (a)(b)(c) 그대로 탈락: 원가 상한 0, 회의 원문 앱에 광고 SDK는 REQ-14 충돌, 무료 없으면 학습 루프 리텐션 없음 |
| PO-2 "녹음은 유료 전용, 무료 30분, REQ-15 신설"을 v1.0 결정으로 | 근거 65%가 `pricing_example.yml`의 가정 단가(0.006$/분)에서만 나오고, Backend는 STT 유료 지출 0(자체 whisper)을 전제 → 결론 근거 붕괴(RT-B-09). **가설로 강등**, REQ 신설 없음 |

## 4. 왜
비용은 "1인당 호출 수 × 호출당 토큰 × 단가"로 분해되고 세 인자의 원천이 다르다(DB 측정 / 프롬프트 실측 / 공식 가격표). 원천별로 파일을 나누고 계산만 코드에 두면 어느 숫자가 바뀌었는지 PR diff로 보인다(PO-1). 서버가 실제로 부른 것은 `ai_usage`·`usage_daily`(ADR-0007)에 남으므로 **서버 DB가 진실**이고 Amplitude는 MAU 성장·세그먼트 비율 경로로만 들어간다(PO-4).

레드팀이 직접 실행해 찾은 산식 오류 3개를 반영한다: (1) 무료 한도를 `RPD×30`으로 월 평균화하면 소진 MAU가 1.5배 과대(94 → 141), 피크 RPM은 3.6배 과소 → **일 단위 RPD와 피크 RPM 둘 다** 근무일·근무시간 기준으로(RT-B-08). (2) 온디바이스 비율을 `calls_per_user`와 트랙 배정에서 두 번 적용해 iOS 17~25 서버 몫이 0원 → **한 번만**(RT-B-14). (3) 고정비 `t0: 15$`(t4g.small)는 PM 결정(v1.0 prod = OCI Always Free)과 불일치 → OCI Free 0원 시나리오 기본(RT-B-15).

**BM(FD-11)**: v1.0은 결제 없음, 전원 무료, 베타 50명. 계약 v1.1에 `plan`(FREE|PRO) 필드만 예약. 가설 3개(무료+구독 4,900원 & 녹음 유료 / 팀 라이선스 / B2B 사전)와 각 가설의 검증 실험·지표·허용 원가는 `docs/bm/early-strategy.md`. 무료 녹음 상한 후보(월 30분)는 REQ 신설 없이 가설 표에만. 초기 90일: 베타 → 대기열 → 유료 전환 실험.

### 4-1. 파일·입력
```
eval/
├─ cost_model.py        계산·CLI. 표준 라이브러리만(tomllib, dataclasses, argparse). PyYAML 금지
├─ pricing.toml         단가·무료 한도·verified_on·출처 URL. 미확인 값은 null 대신 키 생략 + unverified = true
├─ usage.toml           가정(source = "assumption"): MAU, 1인당 월 해석·녹음 분·복습 수, 온디바이스 비율,
│                       active_days_per_month(20), active_hours_per_day(10), 피크 계수(2.5), guest_translations_per_day
├─ usage_snapshot.py    서버 usage_daily → eval/measured/usage.toml (월 1회, 사람 PR)
├─ measured/            .gitignore — 실측 비공개(사용자 결정)
└─ tests/test_cost_model.py
Makefile: make cost MAU=1000  (MAU="100 1000 10000" TRACK=…)
```
입력 타입(PO §1-2 채택, `frozen` dataclass): `UsageProfile`, `ModelPrice(input/cached/output per Mtok, free_rpd, free_rpm, free_tpm, over_limit ∈ {pay, fallback, degrade}, fallback_model, unverified)`, `TaskTokens`, `Track`, `SttChain[{provider, free_sec_per_day, usd_per_minute, selfhost_cpu_min_per_audio_min}]`, `StoragePrice`(R2, 오디오 30일), `FixedTier`(계단 함수, `t_free` OCI 0원 기본·`t_aws` t4g.small 옵션), `RevenueAssumption`(마진·전환율·VAT·스토어 수수료).

### 4-2. 계산
```
월 원가 = Σ트랙( 호출 × 토큰 × 단가 ; 무료 한도는 RPD×active_days 와 피크 RPM 둘 다 적용, 초과분만 과금 )
        + STT 사슬( whisper_local CPU 분당 원가 = VM 시간 기반 ; 외부 STT는 사슬에 있을 때만 )
        + 저장( R2, 오디오 30일 상시량 ≈ 한 달치 )
        + 고정비( prod = OCI Free 0원 시나리오 기본, AWS t4g.small 옵션 )
온디바이스 비율은 한 번만 적용. Guest(하루 3회, PRD)는 MAU 분모 밖이지만 무료 RPD 소모(RT-B-16).
출력: 월 원가, MAU당 원가(한계원가 별도), 손익분기 구독가(마진·전환율 입력), 무료 한도 소진 MAU, 트랙별 비교표(markdown)
```
손익분기: `list_price = (total_krw / (1 − margin)) / payers / (1 − store_fee) × (1 + vat)`, 역산 항등식 `allowed_cost(breakeven_price(x)) == x/MAU`.

### 4-3. 갱신 리듬
- 월초: `python eval/usage_snapshot.py --month 2026-11 > eval/measured/usage.toml` → 비공개. `make cost` 표는 PR 본문에만(숫자 자체는 저장소에 남기지 않음).
- 단가 갱신은 ADR 불필요, 정책 필드(`over_limit`·`fallback_model`·트랙 구성) 변경은 ADR.
- 토큰 프로파일(`tasks`)은 실측으로만(`ai_usage` 월 평균).
- 세그먼트(`free/paid`, `p95`)는 v1.1 `plan` 이후. 비용 모델은 평균, 공정 사용 상한은 p95.

## 5. 영향 파일·문서
- `eval/cost_model.py`, `eval/pricing.toml`, `eval/usage.toml`, `eval/usage_snapshot.py`, `eval/tests/test_cost_model.py`, `Makefile`, `.gitignore`(`eval/measured/`).
- `docs/bm/early-strategy.md`(신설, FD-11).
- 14번 §8 "AI 비용" 행을 이 모델 출력으로 대체, §15 라우터 표에 비용 열, §16 `eval/` 트리. 16번 S5 Day 30 관측 대시보드에 `usage_daily` Grafana 패널(MySQL 데이터소스, 추가 서비스 없음).
- 12번 §10 이벤트 표에 "비용 입력 여부" 열. Amplitude 이벤트 6개는 PO §4-2 5개(`translation_result_left`, `action_checked`, `review_answered`/`review_finished`, `recording_finished`, `onboarding_completed`) + 옵트아웃으로 교체(RT-A-18).
- 계약 v1.1 백로그: `users.plan`(FREE|PRO), `GET /users/me`에 `plan`(예약만).
- REQUIREMENTS REQ-13 영향 칸 `eval/cost_model.py` 유지(루트), REQ-12 "무료 한도 초과 MAU"를 첫 유료 전환 지표로.

## 6. 검증
- 단위 테스트: `calls_per_user` 손계산 벡터, 무료 한도 경계(`RPD × active_days ± 1`), 피크 RPM 경고 경계, 폴백 3단 캐스케이드, `degrade` 거절 건수, 온디바이스 비율 단일 적용(api 트랙과 하이브리드 트랙 원가가 다름을 assert), 손익분기 역산 항등식, 고정 픽스처 CSV 결과가 `packages/test-vectors/cost_model.json`과 일치.
- `make cost MAU=1000`이 월 원가·MAU당 원가·손익분기·무료 한도 소진 MAU를 출력. 단가표에 `verified_on`·출처 URL, `unverified` 모델 목록이 표 하단에.
- 월 1회 대조: 제공자 콘솔 실제 요청 수·토큰 vs 모델 예측, 오차 ±20% 밖이면 `tasks` 갱신. 첫 실측이 가정과 2배 이상 다르면 BM 허용선 재검토 이슈.
- CI: `verified_on` 비어 있거나 30일 초과면 경고(실패 아님).

## 7. 리스크와 되돌리는 조건
- 리스크: 가정값이 "그럴듯한 숫자"로 굳음 → `usage.toml`의 `source = "assumption"`이 S5 이후에도 남아 있으면 이슈 자동 생성. 무료 한도가 달마다 바뀜(2025년 여러 번) → `verified_on` 경고. 베타 수십 명 통계는 개인 편차에 흔들림 → 중앙값·평균 병기, 가입 30일 이상 사용자만 프로파일에.
- 되돌리는 조건: 유료 전환 후 청구서와 모델 오차가 3개월 연속 ±30% 밖이면 모델 구조(토큰 프로파일 → 실제 청구 기반)로 재설계. STT 실측 원가가 지배적(> 50%)이면 D-7 재협의(iOS 26 온디바이스 transcript 채택)를 PO·iOS 안건으로 — 그 전엔 손대지 않음(Backend B-4 §7).
