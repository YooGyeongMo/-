# 레드팀 B 판정서 — 일정·비용·프라이버시·운영 (협의체 1차, 2026-09-19)

> 검토 대상: BRIEF(사용자 답변 포함), PM.md, PO.md, AI.md, Backend.md, QA.md, iOS.md, macOS_iPad.md, cost_model_draft.py, pricing.yml / pricing_example.yml, usage*.yml, 저장소 `docs/REQUIREMENTS.md`, `docs/16_실행계획.md`, `.github/workflows/{app,contracts,server}.yml`, `docs/adr/0002`, 12번 §12, 14번 §6·§8·§14, PRD §2.
> 직접 실행·계산한 것: `cal 9~11 2026`, 평일·주말 카운트 스크립트, `python3 cost_model_draft.py`(기본 pricing.yml / pricing_example.yml / usage_norec.yml, `--price 4900`), 무료 한도·CI 분 산식, `gh repo view`(PUBLIC 확인), `gh issue list`(29건 OPEN).
> 등급 기준은 PM.md §5 표 그대로(치명 = REQ 위반·원문 유출 경로·유료 결제 발생·1인 견적이 잔여 시간 초과 / 중요 = 대안·검증·되돌림 결함, 확인 안 된 사실 / 경미 = 형식). 저장소 파일은 수정하지 않았다.

---

## 0. 요약

### 착수 가능 여부: **불가(치명 5건)** — 아래 치명 5건이 같은 세션에서 수정·재판정되기 전에는 S0 착수 불가. 단, S0 Day 2~4(Tuist 타깃 17/14, MwonmalAPI 생성, FastAPI 뼈대)는 어느 치명과도 무관하므로 **"S0 뼈대 3일만 조건부 착수"**는 가능하다.

| 등급 | 건수 | ID |
|---|---|---|
| 치명 | 5 | RT-B-01(파트 합산 견적 ≫ PM 견적), RT-B-02(파트 간 v1.0 범위 모순), RT-B-10(Gemini 무료 티어에 실원문·오디오), RT-B-11(회의 오디오 → Groq/Gemini, 약관 미확인), RT-B-12(운영자 키로 Claude/OpenAI 프로덕션 호출 = REQ-11 위반 경로) |
| 중요 | 14 | RT-B-03, 04, 05, 06, 07, 08, 09, 13, 14, 15, 16, 17, 18, 19 |
| 경미 | 8 | RT-B-20 ~ 27 |

### 한 줄 판정
- **일정**: 사용자 답변(공휴일 전부 근무)으로 PM §0의 "공휴일 −5일" 리스크는 사라지지만 PM 산식은 원래 토·일만 뺀 것이라 **숫자는 그대로 −1일·버퍼 0**이다. 문제는 PM이 아니라 **다른 6개 파트가 요구한 작업량 합(순증 약 +25~30일)이 PM이 인정한 +10.5일의 2.5배**라는 점. 7개 메모는 같은 v1.0을 그리고 있지 않다.
- **비용**: 계산기는 돌아가고 산식 자체는 대체로 맞다. 그러나 (a) RPD를 30일 평균으로 나눠 무료 한도 소진 MAU를 **1.5배 과대**(94 → 141), (b) STT 원가를 PO는 "유료 분당 단가"로, Backend는 "Groq 무료 8h/일 + 자체 whisper"로 다르게 가정해 **PO-2(녹음 유료화) 결론의 근거가 Backend 설계와 충돌**, (c) 무료 RPD 가정치가 PO 250 / QA 20 / Backend 500 / AI "15 RPM·1,500 RPD 또는 20 RPD"로 **네 메모가 네 숫자**.
- **프라이버시**: 실원문·오디오가 나가는 경로 12개 중 **4개(Gemini 무료 티어 텍스트, Groq Whisper 오디오, Gemini 오디오, 운영자 BYOK)를 어느 파트도 막지 않았고**, AI 파트가 확인한 Google 약관("기밀 제출 금지·개선에 사용·인간 검토")을 Backend·PM은 인지조차 안 한 채 프로덕션 1순위로 박았다.
- **운영·CI**: 저장소는 PUBLIC(`gh repo view` 확인)이라 표준 hosted macOS 러너 분은 **과금 0**(QA F-3 맞음, iOS.md의 "10배 과금"은 비공개 저장소 규칙). 대신 QA 매트릭스는 **월 ≈ 7,950 macOS-분**이라 비공개로 바꾸는 순간 ×10 = 79,500분 ≈ 무료 2,000분의 40배. 동시성 5 상한과 PR당 5개 macOS job이 정확히 맞물려 대기 발생. self-hosted를 PR에 쓰는 안(iOS.md)은 ADR-0002 자체 결과 항목과 충돌.
- **REQ-20**: AI-5·AI-6, Backend B-6 ②(ENUM 전략), macOS_iPad MN-4, QA §2-3 요약 기록이 7항목 미달. QA F-1(macos-26 GA 날짜 등)은 출처 없이 "사실"로 적혔다.

### 사용자 결정 필요 목록 (에이전트가 임의로 정한 것 — §7에 상세)
U-1 BM(무료+구독 4,900원, 녹음 유료 전용, 무료 30분) · U-2 REQ-15 신설 · U-3 카카오 로그인 컷 후보 · U-4 macOS TestFlight 11/13 분리(v1.0 정의 변경) · U-5 v1.1 이관 8건(OCR·STT 미리보기·라이브 액티비티·SceneStorage·macOS 로컬 알림·AWS prod·오답 AI·Amplitude 15→6) · U-6 Gemini 무료 티어에 실원문 전송 + 고지/옵트아웃 · U-7 회의 오디오 외부 STT(Groq/Gemini) 전송 · U-8 "사용자 제공 키"의 뜻(운영자 키 vs 최종 사용자 BYOK) · U-9 강등(사전만) 결과 prod 허용 · U-10 잠금화면에 할 일 문장 노출 · U-11 Mac 최소 창 900×600 vs 1000×700 · U-12 iPad 카메라 OCR 추가(신규 기능) · U-13 Liquid Glass v1 채택 여부 · U-14 Foundation Models v1.0 포함 여부 · U-15 CI 전략(hosted macos-26 vs self-hosted, Xcode 핀 26.5 vs 보유 26.4) · U-16 `eval/` 위치 · U-17 Domain에 watchOS 데스티네이션 · U-18 공개 저장소에 실측 usage.yml(MAU) 공개 · U-19 베타 인원 상한 · U-20 협의체 격주 완화 조건.

---

## 1. 일정

### RT-B-01 | 치명 | PM-1 · PM §1~§2 · AI §7 · iOS A1/B1/C1 · macOS_iPad MI-1~4 · Backend B-1/B-4 · QA-1~4 | 파트 메모의 v1.0 작업량 합이 PM 견적의 약 2.5배
- **문제**: PM은 신규 REQ 순증을 +10.5일로 잡고 −8.5일을 잘라 −3.0일을 토요일 2회 + 버퍼 0으로 메웠다. 그런데 각 파트가 "v1.0에 넣겠다"고 쓴 항목을 그대로 합치면 순증이 약 +25~30일이다.
- **근거(직접 합산, 각 메모의 "비용" 항목·표에서 발췌)**:
  | 파트 | v1.0 순증 자기 견적 | PM이 인정한 몫 |
  |---|---|---|
  | AI | AI-1 평가셋 2일 + 채점 1일, AI-2 서버 라우터 2일 + 앱 `TranslationEngine` 2~3일, §3 표 ② Apple FM 어댑터 2~3일("v1.0 출시 포함 Y"), §7 #1~#6이 S0·S1 "자투리"에 2.5일 → **9~11일** | S2-C~H 타임박스 1.5일 + Day 11 |
  | iOS | A1 폴백 구현체 4개 3~4일(SFSpeechTranscriber 포함), B1 Motion 1.5+1(MotionLab)+0.5 = 3일, C1 0.5+1+0.5 = 2일 → **8~9일** | S0-A 0.5 + S1-A 1.0 + S2-A 0.5 + S6-A 1.0 = 3.0 |
  | macOS·iPad | MI-1 0.5, MI-2 1.0, MI-3 0.5, MI-4 1.0(카메라 OCR), MN-4 0.5 → **3.5일** | S1-A 1.0에 일부 |
  | Backend | Day 11에 Protocol + 어댑터 5종 + Redis 한도 + 브레이커 + 레코더 + 마이그레이션 0002 + 평가셋 v0 점수표; Day 17에 STT 어댑터 3종 + 큐 3개 + `faster-whisper` 자체 호스팅(신규 서비스); Day 18에 payload 빌더 + cron 2개; Day 30에 v1.1 15건 초안 → 기존 Day에 "흡수"라고 쓰지만 실질 **+3일** | 0 |
  | QA | 워크플로 2개, SwiftLint 규칙 7개, 프라이버시 카나리 5층(CapturingTransport·sentry_sink.py·AnalyticsValue enum), coverage-gate.sh, archify 야간 job, 릴리스 체크리스트 15항목 → 개발 시간 견적 자체가 없음, 실질 **3~4일** | S6 ①② 2.0 |
  | PO | cost_model + tests + usage_snapshot.py → 1일 | S2-G 0.5 + S5-A 0.5 = 1.0 |
  | **합** | **≈ 28~31일** (중복 제거해도 ≥ 20일) | **10.5일** |
  달력: `cal` 기준 9/22(화)~11/6(금) = 46일, 평일 34, 주말 12. 공휴일 평일 5일(9/24·25·28, 10/5, 10/9)은 사용자 답변으로 전부 근무 → PM 산식(토·일만 제외)과 동일하므로 **추가 여유 0**. 16번 Day 1~30 + S6 5일 = 35슬롯 > 34 평일 → −1일(PM 맞음). 6h/일이면 204h, 8h/일이면 272h. 파트 합산 +20일 이상은 주말 12일을 전부 써도 안 들어간다.
- **권고**: 각 파트가 "v1.0 필수 / v1.1"을 PM 표 §2의 Day 번호에 **직접 매핑**한 뒤(Day에 못 붙는 항목 = 자동 v1.1), PM이 재합산해 "순증 ≤ 감축"을 증명한 표 한 장을 내야 착수. 협의체 규칙(PM §5 "1인 견적이 스프린트 잔여 시간을 초과 = 치명")을 스스로 적용할 것.

### RT-B-02 | 치명 | PM-2 vs AI-5/§3/§4-1 vs iOS A-4 #1·#2 vs macOS_iPad MI-5 vs PM S3-B | 같은 기능의 v1.0 포함 여부가 파트마다 다름
- **문제**: 세 기능의 v1.0 포함 여부가 메모마다 반대다.
  | 기능 | PM | AI | iOS | macOS·iPad |
  |---|---|---|---|---|
  | Apple Foundation Models 온디바이스 해석 | PM-2 "v1.0 미포함" | AI-5·§3 "v1.0 포함 Y(게이트 뒤 폴백·미리보기)", §4-1 앱 결정 트리 v1.0 동작 정의 | 표 #2 "v1.0은 전 OS 서버" | MI-5 "AI 파트 결정과 연동" |
  | 17~25 받아쓰기 미리보기(SFSpeechRecognizer) | S3-B "SpeechAnalyzer 미리보기 → v1.1, SF 폴백 +1.0 탈락" | — | A-4 #1 `SFSpeechTranscriber` 구현(55초 재생성·온디바이스 강제) **v1.0** | MI-5 "SFSpeechRecognizer 폴백은 v1에 안 함, 구현체 1개 + nil" |
  | OCR | Day 14 "Vision OCR → v1.1" | — | A-4 #18 `VNRecognizeTextRequest` 전 OS v1 | MI-4 **iPad 카메라 OCR 신규 추가**(+1일, `NSCameraUsageDescription`) |
- **근거**: 위 표 각 셀의 원문. 12번 D-6·D-7·T-C2·T-D3가 흔들린 자리를 네 파트가 각자 다르게 메웠다.
- **권고**: 세 기능에 대해 협의체가 한 줄씩 확정(REQ-20 7항목)하고 나머지 메모는 그 결정을 인용만 하게. 미확정 상태로는 Day 14·19·20 이슈 본문을 쓸 수 없다.

### RT-B-03 | 중요 | Backend B-1 §2 "Day 11 하루" · PM Day 11 | Day 11 하루(6h)에 들어갈 수 없는 항목 수
- **문제**: PM Day 11은 "Gemini Flash 무료 + Groq 폴백만"으로 축소했는데 Backend B-1은 어댑터 5종(gemini_free·openai_key·anthropic_key·vllm_local·none) + Redis 한도(Lua) + Redis 브레이커(HALF_OPEN 프로브 락) + 레코더 + `ai_usage`/`usage_daily` 마이그레이션 0002 + testcontainers 통합 테스트 + 평가셋 v0 50문장 점수표를 같은 날에 둔다. 파일 ~10개·어댑터당 80줄이라 해도 테스트 포함 6h 불가.
- **근거**: Backend B-1 §2 표 "시간: Day 11 하루", §5-1 파일 목록, B-6 "Day 11 EngineRouter + 마이그레이션 0002 + 평가셋 v0".
- **권고**: Day 11 = gemini_free + none + 브레이커(프로세스 메모리 아님, Redis) + 레코더까지. openai_key·anthropic_key·vllm_local 어댑터는 RT-B-12 결정 후 v1.1. 마이그레이션 0002는 Day 12로.

### RT-B-04 | 중요 | AI §7 #1~#6 · PM §2 | "S0·S1 자투리"에 2.5일을 넣음 — S0·S1에 자투리가 없음
- **문제**: AI §7은 9/22~10/2에 한도 캡처·score.py·평가셋 v0 50문장·FM 스파이크·router.yml·ADR-0005를 배치하고 "서버 날이 아닌 날의 자투리"라 부른다. 그러나 PM §2의 S0·S1은 이미 Day 5 과적재를 덜어내고 토요일 9/26을 문서 작업으로 채운 상태이고, S1의 서버 날은 Day 6·7뿐이다.
- **근거**: AI §7 표(#2 1일, #3 2일, #4 주말, #5 S1 서버 날), PM §2 Day 2~10 행 전부 "유지/수정"으로 6h 찬 상태.
- **권고**: #1(한도 캡처 30분)·#2(스키마만)만 S0에 남기고 #3·#5는 PM 10/10(토) "AI 4트랙" 이슈에 합치되, PM-3의 타임박스 1.5일을 2.5일로 정정하거나 평가셋 v0를 30문장으로 줄인다.

### RT-B-05 | 중요 | PM S6-A · iOS A-6 · macOS_iPad MI-6 · QA §1-2/§3-2 | 스냅샷 매트릭스가 네 개(12장 / 96장 PR+400장 야간 / ~90장 / ~100장)
- **문제**: 같은 REQ-03을 위해 PM은 "기기 3종 × 흐름 4 = 12장 갱신"(1.0일), iOS는 PR 96장 + 야간 400장, macOS·iPad는 48+변형 ≈ 90장, QA는 화면 12 × 구성 8 ≈ 100장 + 6K 이미지 3장. 유지 비용(기준 이미지 재기록, OS별 폴더, 러너 Xcode 고정)은 장수에 비례하는데 견적은 PM 것만 반영됐다.
- **근거**: PM S6-A, iOS A-6 "≈ 96장/PR, Tier 2 ≈ 400장/야간", MI-6 "총 ~90장", QA-1 비용 "≈ 100장(≤ 30MB)".
- **권고**: QA가 단일 소유. PR = QA 표 A·D·E만, 야간 = B·C·6K. iOS·macOS_iPad 표는 QA 표를 인용으로 대체.

### RT-B-06 | 중요 | PM §0·§7 · BRIEF 사용자 답변 | 사용자 답변 3건 반영 후 PM 문서 갱신 안 됨
- **문제**: PM §7의 확인 필요 3건(공휴일·iOS 17 런타임·Mac 26/AI)이 BRIEF에서 전부 답변됐다. 그러면 (1) PM 리스크 #1·#2의 트리거가 소멸, (2) S2-E(Foundation Models 어댑터 "조건부/v1.1")가 "실측 가능"으로 바뀌어 §1 S2 순증에 +0.5 복귀, (3) PM-2 되돌림 조건("런타임 설치 불가 → 18/15")이 무효. 재산정표가 그대로다.
- **근거**: BRIEF "사용자 답변(2026-09-19 14:30 확정)", PM S2-E, PM-2 §7.
- **권고**: PM이 §1 S2 합계(+3.5 → +4.0)·§2 수지·§4 리스크 표를 갱신하고, 시뮬레이터 런타임이 **iOS 17.0**(17.5 아님)임을 QA·iOS 매트릭스에 반영(QA는 17.5, iOS는 17.x로 적음).

### RT-B-07 | 중요 | PM-4 · 16번 §3 S6 | v1.0 정의("TestFlight 양 플랫폼")를 PM이 단독 변경
- **문제**: 16번 S6 목표는 "TestFlight 양 플랫폼, v1.0". PM-4는 macOS를 11/13로 미루고 태그를 `app/v1.0.1`로 만든다. 이는 범위 컷이 아니라 **릴리스 정의 변경**이고 사용자 결정 사항(U-4)이다. 또 PM-4 비용에 "macOS 파이프라인 1.0일"을 절약으로 잡았지만 그 1.0일은 11/13 전 주에 어차피 써야 해서 총량은 같다(S6 안에서만 이동).
- **권고**: 사용자 승인 전까지 PM-4는 "제안". 승인 시 16번 §3·REQUIREMENTS E표에 기록.

---

## 2. 비용·무료 티어 (`cost_model_draft.py` 실행 결과 기반)

실행: `python3 cost_model_draft.py --pricing pricing.yml --usage usage.yml --mau 100 1000` / `--pricing pricing_example.yml ... --track api_split --price 4900` / `--usage usage_norec.yml`. 전부 정상 종료, 산식 오류(예외)는 없음. PO §1-6 표의 숫자와 출력이 일치함을 확인(api_split MAU 1,000 = 1,555,865원, STT 720$, 녹음 0이면 187원/MAU).

### RT-B-08 | 중요 | PO-1 `bill_models` · Backend B-2 §5-3 산식 · PO §1-4 "MAU ~140" | 무료 한도를 RPD×30으로 월 평균화 → 소진 MAU 1.5배 과대, 피크 RPM 3.6배 과소
- **문제**: `free_month = free_rpd × 30`, `avg_rpm = calls/30/1440 × 5`. usage.yml 스스로 "근무일 20일 × 1.5건"이라 썼는데 호출을 30일·24h에 균등 분배한다. RPD는 **일** 한도라 근무일 하루 호출로 나눠야 한다.
- **근거(재계산)**: api_free_only 1인당 월 Gemini 호출 = 30×0.9×0.8×2 + 4 + 1 + 5 = 53.2건 → 근무일 하루 2.66건. RPD 250이면 소진 MAU = 250/2.66 = **94**(PO는 141). RPD 20(QA 최악)이면 **8명**(PO 산식 11명). 피크 RPM: MAU 1,000 api_split의 Gemini 26,600건/월 → 근무일 1,330건/일 → 근무 10h 기준 평균 2.2 RPM, ×5 = 11 > free_rpm 10 → **MAU 1,000에서 이미 RPM 초과**인데 모델은 MAU 10,000에서만 경고(30.8). Backend B-2 §5-3 "무료 한도 소진 MAU = free.rpd × 30 / 월 호출"도 같은 오류.
- **권고**: `usage.yml`에 `active_days_per_month: 20`, `active_hours_per_day: 10` 추가하고 `free_month = rpd × active_days`, `avg_rpm = calls/active_days/(active_hours×60)`. 테스트 벡터(PO-1 검증 (i) "무료 한도 경계 RPD×30 ±1")도 갱신.

### RT-B-09 | 중요 | PO-2 · PO §1-6 · Backend B-4 §2·§5 · pricing.yml `stt` | STT 원가 가정이 PO와 Backend에서 정반대 → PO-2(녹음 유료) 결론의 근거 붕괴
- **문제**: PO-2는 "예시 단가로도 STT가 MAU당 원가의 60~70%"를 근거로 **녹음을 유료 전용**으로 정했다. 그 65%는 `pricing_example.yml`의 `usd_per_minute: 0.006`(가정)에서만 나온다. Backend B-4는 STT 사슬을 `groq_whisper(무료 28,800초/일) → gemini_audio(무료) → whisper_local(자체, 0원)`로 설계해 **STT 유료 지출 0**을 전제한다. 두 설계 중 하나만 맞을 수 있고, cost_model에는 STT 무료 한도(`free_minutes_per_month: 0`)·사슬·자체 호스팅 CPU 비용이 아예 없다.
- **근거(재계산)**: Groq 28,800초/일 = 480분/일 → 근무일 20일 기준 9,600분/월 → 120분/인이면 **MAU 80명**까지 STT 0원, 그 다음은 whisper_local(OCI A1 무료, CPU 실시간 미확인). PO §1-6 "녹음 0으로 두면 187원/MAU"가 사실상 Backend 설계의 원가다. 또 pricing_example의 0.006$/분은 PO 스스로 "사실 아님"이라 표기했는데 PO-2 결정문 4항 "왜"는 그 숫자에 의존한다.
- **권고**: PO-2를 "가설, STT 실측 후 결정"으로 강등(U-1). cost_model에 `stt.chain[{provider, free_sec_per_day, usd_per_minute}]`과 `selfhost_cpu_min_per_audio_min`을 추가하고 PO·Backend가 같은 pricing.yml을 본다.

### RT-B-10 | 치명 | AI-4 · PO-3 규칙표 "프라이버시" 행 · Backend B-1 §5-3/§5-4 · PM Day 11 | Gemini 무료 티어에 실사용자 원문(및 B-4 오디오)이 프로덕션 1순위로 박힘 — 약관·REQ-14 위반 경로
- **문제**: AI 파트가 Google 약관을 **[사실]**로 확인했다: 무료 티어는 "Used to improve products: Yes", "human reviewers may read", "**Do not submit sensitive, confidential, or personal information to the Unpaid Services**". 그런데 Backend B-1 폴백 사슬은 `gemini_free`를 DETECT_PLAIN·QUIZ 1순위, NUANCE·SUMMARY 폴백으로 두고 B-4는 `gemini_audio`를 STT 2순위로 둔다(회의 오디오 전체). PM Day 11도 "Gemini Flash 무료 + Groq 폴백만". PO-3는 "확인 필요… 베타 시작 전 정책 확인이 게이트"라 적어 AI가 이미 확인한 사실을 미확인으로 되돌렸다. 제품 원칙 "기밀"(REQ-14, 12번 §12)과 정면 충돌하며, 결정 주체(사용자)에게 올라가지 않은 채 코드 계획이 진행된다.
- **근거**: AI §1-① 표 "무료 티어 데이터 사용" 행, AI-8 표 ① 행 "합성 데이터만", Backend §5-4 사슬 표, B-4 §5 STT 사슬, PO-3 규칙표 마지막 행, PM §2 Day 11.
- **권고**: (1) 사용자 결정 U-6 전까지 서버 설정 기본값 `AI_REAL_USER_TEXT=false`(AI-8) + `gemini_audio` 사슬 제외를 Backend B-1·B-4에 명기. (2) 선택지는 AI-4의 (a) 고지+옵트아웃 / (b) 온디바이스·BYOK만 / (c) 유료 전환(REQ-11 개정) 셋뿐임을 사용자에게 그대로 제시. (3) 12번 §12 위협 모델 표에 "AI 제공자" 열 추가(AI-8 제안)를 채택.

### RT-B-11 | 치명 | Backend B-4 §2·§5 · AI §1-① "Groq" 행 | 회의 오디오 전체를 Groq(약관 미확인)로 보내는 설계
- **문제**: B-4는 prod STT 1순위를 Groq Whisper로 정했다. AI 메모는 Groq의 "데이터 사용 약관도 미확인"이라 썼다. 오디오는 원문보다 민감(화자 식별 가능)한데 12번 §12 위협 모델 "오디오 조각" 행에는 "서버: 30일 후 삭제"만 있고 외부 STT 제공자 열이 없다. REQ-14 "원문·받아쓰기·오디오는 어떤 SDK로도 안 나감"의 취지상 STT 제공자는 사용자에게 고지되어야 한다(App Privacy 라벨 포함).
- **근거**: Backend B-4 §2 후보 표(Groq 1순위, "카드 불필요"), §7 "Groq 무료 한도 축소 → 다음 칸 자동"(약관 리스크 없음), AI §1-① Groq 행 "[확인 필요] … 데이터 사용 약관도 미확인".
- **권고**: 사용자 결정 U-7. 결정 전 dev 기본을 `whisper_local`로(B-4에 이미 dev 사슬이 그렇게 되어 있음), prod 사슬은 약관 확인 결과를 ADR-0008에 첨부한 뒤에만 Groq 포함.

### RT-B-12 | 치명 | Backend B-1 §5-3 `openai_key`/`anthropic_key` · PO-3 규칙표 "사용자 제공 키" · AI-2 §4-1 "byok" | "사용자 제공 키"가 세 메모에서 세 뜻 — 그중 Backend 해석은 REQ-11 위반 경로
- **문제**: REQ-11 "OpenAI·Claude는 사용자 제공 키". PO-3: "평가셋 전용·선택, 서버 라우터는 사용자 키를 받지 않는다(키 소유자 = 나 = 결제 발생 = REQ-11 위반)". AI-2: 최종 사용자 BYOK(`user.byokProvider`, NUANCE 1순위 "byok(claude|openai, 키 있을 때만)"), 단 v1.0 계약에 키 저장이 없음을 인정. Backend: "운영자가 `.env`에 넣는 키로 해석", `anthropic_key`를 **prod NUANCE_ACTIONS·MEETING_SUMMARY 1순위**, "크레딧 소진 시 402/429 → 브레이커". 운영자 키가 prod 사슬 1순위면 크레딧이 곧 결제이고(REQ-11 "유료 결제 없음" 위반), 실사용자 원문이 개발자 개인 계정으로 Anthropic/OpenAI에 간다(REQ-14·약관).
- **근거**: 위 세 메모의 해당 절 원문. Backend Q1이 스스로 이 질문을 PO에 던졌지만 설계는 이미 1순위로 박혀 있다.
- **권고**: 사용자 결정 U-8. 결정 전까지는 PO-3 해석(평가 전용, 서버 사슬 제외)을 기본으로 Backend §5-4 사슬에서 `anthropic_key`·`openai_key`를 제거하고 `gemini_free(strong)`을 NUANCE 1순위로. 계약 v1.1 백로그에 "사용자별 키 저장"은 넣지 않는다(시크릿 취급·삭제 API·약관까지 필요, v1.2 이후 — Backend Q1 제안과 동일).

### RT-B-13 | 중요 | pricing.yml `free_rpd/free_rpm` · AI §1-① · QA-2 §2 · Backend B-1 §2 | 무료 RPD·RPM 가정치가 메모마다 다름 (250 / 20 / 500 / 1,500)
- **문제**: PO pricing.yml Gemini `free_rpd: 250, free_rpm: 10`; AI "15 RPM/1,500 RPD(2026-05)와 20 RPD·Flash-Lite 500 RPD(2026-09)가 서로 다름"; QA "최악 20 RPD로 설계, 야간 40문장"; Backend "Flash-Lite 500 RPD·Flash 계열은 훨씬 적음". 전부 "확인 필요"라 표기는 했지만 **각자 다른 숫자로 설계·산식·CI 표본 수를 정해 버렸다**. 20 RPD가 맞으면 QA 야간 40문장 + 개발 데모 + 평가셋이 하루 한도를 즉시 넘고, PO-3의 "일일 예산 = RPD 50%"는 10건이 된다.
- **근거**: 각 파일 해당 행. AI §7 #1이 "9/22~23 AI Studio 캡처 → `eval/limits.md`"로 이미 해소 계획을 갖고 있음.
- **권고**: AI §7 #1을 **S0 Day 1 게이트**로 승격하고 `eval/limits.md`가 `pricing.yml`의 유일한 출처가 되게(다른 메모의 숫자 삭제). 20 RPD 시나리오의 대응(QA-2 §7, PO-3 §7)을 지금 기본안으로 채택.

### RT-B-14 | 중요 | PO-1 `calls_per_user`·`volumes` · pricing.yml `tracks.ondevice_hybrid` | 온디바이스 비율을 두 번 적용해 iOS 17~25 서버 몫이 0원으로 계산됨
- **문제**: `detect = ai_T × (1 − ondevice_detect_rate)`로 호출을 뺀 뒤, `ondevice_hybrid` 트랙은 **남은** detect 호출을 다시 `ondevice_fm`(단가 0)에 배정한다. 즉 iOS 17~25·Apple Intelligence 미지원 기기의 서버 detect 원가가 0으로 사라진다. 실행 결과 api_split과 ondevice_hybrid의 AI 원가가 동일(374.72$)한 것이 그 증거(detect가 어느 트랙이든 0).
- **근거**: cost_model_draft.py L216~223, L228~231, pricing.yml L174~179, 실행 출력 표.
- **권고**: `Track.detect_ondevice`와 `Track.detect_server` 두 슬롯으로 나누고 rate로 가중. 또는 하이브리드 트랙을 삭제하고 rate만 쓴다.

### RT-B-15 | 중요 | pricing.yml `fixed_tiers.t0` 15$ · PM Day 26 "AWS prod → v1.1, OCI Always Free" · REQ-32 | v1.0 고정비 가정이 PM 결정과 불일치, MAU 100 원가의 100%가 이 값
- **문제**: 기본 pricing.yml로 돌리면 MAU 100 전 트랙이 "210원/MAU"인데 전부 `t0: 15$/월`(t4g.small) 때문이다. PM은 v1.0 prod를 OCI Always Free로 결정했으므로 고정비 ≈ 0(도메인 정도). 손익분기 산출이 이 값을 그대로 쓴다.
- **권고**: `fixed_tiers`에 `t_free: {max_mau: 500, usd: 1, label: oci-free}`를 추가하고 PM Day 26 결정을 pricing.yml 주석에 인용.

### RT-B-16 | 중요 | usage.yml · PRD §2 Guest 행 · PO-4 | 사용량 가정이 PRD 페르소나·Guest 규칙과 안 맞음
- **문제**: (1) PRD "비로그인 방문자: 해석 하루 3회, 결과 저장 안 함" — Guest 호출은 MAU 분모에 없지만 무료 RPD를 소모한다. usage.yml·cost_model에 Guest 항목이 없어 무료 한도 소진 MAU가 과대. (2) 페르소나는 "매일 오가는 말 한 문장 … 회의에서 오간 말의 절반을 못 알아듣는" 신입인데 `translations: 30/월`(하루 1.5건)은 그 서사보다 보수적이고, 반대로 `meeting_decodes: 4, recording_minutes: 120`은 신입이 회의를 녹음할 권한·상황(동의 시트 W-02a)을 감안하면 낙관적. 둘 다 `source: assumption`으로 표기됐으니 사실 오류는 아니나, PO-2 BM 결론이 이 가정에 서 있다. (3) `peak_factor 5.0 "퇴근길 18~19시"` — 퇴근길 활동은 복습(AI 0원)이고 해석 피크는 근무 시간이다.
- **권고**: `usage.yml`에 `guest_translations_per_day`(PRD 3회 상한)와 `mau_to_guest_ratio` 추가. peak 가정을 "근무 시간 10h 중 상위 1h = 2.5배"로 바꾸고 근거(PRD)를 주석에.

### RT-B-17 | 중요 | AI-3 `aiModel` 규약 vs Backend §5-2 `translations.ai_model = f"{engine}:{model}"` vs Backend B-6 Day 3 "aiModel 파싱하지 말 것" | 같은 컬럼 규약이 두 개, 앱 파싱 여부도 반대
- **문제**: AI-3: `{track}/{model}@{ver}#{promptVer}` + 앱 `EngineTag.parse` + 정규식 검증. Backend: `"{engine}:{model}"` + schemathesis 검증 + "앱은 `aiModel` 문자열을 파싱하지 **말 것**". PO-4·cost_model은 `ai_model`을 세그먼트 키로 쓴다. 규약이 둘이면 ai_usage·usage_daily·대시보드가 갈라진다.
- **권고**: Backend 형식을 채택하되 `prompt_version`은 `ai_usage` 컬럼(이미 있음)으로. AI-3의 앱 파싱은 v1.1 `engine` 필드로.

---

## 3. 프라이버시 (REQ-14) — 원문·받아쓰기·오디오가 나갈 수 있는 경로 전수

범례: ✅ 막음(테스트·설정 명시) / ⚠ 언급만·부분 / ❌ 언급 없음 / 🔴 오히려 열어 둠

| # | 경로 | 무엇이 나가나 | PM | PO | AI | Backend | QA | iOS | macOS·iPad | 판정 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Gemini 무료 티어(텍스트) | 원문·회의록 → Google, 학습·인간 검토 | 🔴 Day 11 1순위 | ⚠ "확인 필요·베타 전 게이트" | ✅ 약관 확인·AI-4 에스컬레이션·`AI_REAL_USER_TEXT=false` | 🔴 prod 사슬 1순위 | ❌ | ❌ | ❌ | **RT-B-10 치명** |
| 2 | Gemini 오디오 입력(STT 2순위) | 회의 오디오 → Google 무료 티어 | ❌ | ❌ | ❌ | 🔴 B-4 사슬 | ❌ | ❌ | ❌ | **RT-B-10 치명** |
| 3 | Groq Whisper(STT 1순위) | 회의 오디오 → Groq, 약관 미확인 | ❌ | ❌ | ⚠ "약관 미확인" | 🔴 B-4 1순위 | ❌ | ❌ | ❌ | **RT-B-11 치명** |
| 4 | 운영자 키 Claude/OpenAI(prod) | 원문 → 개발자 개인 계정 | ❌ | ✅ 서버 경로 금지 | ⚠ 최종 사용자 BYOK 전제 | 🔴 prod 1순위 | ❌ | ❌ | ❌ | **RT-B-12 치명** |
| 5 | SFSpeechRecognizer 서버 인식 | 오디오 → Apple | ✅ 폴백 자체 v1.1 | ❌ | ❌ | ✅ 대안표에서 탈락 사유로 명시 | ❌ | ✅ `requiresOnDeviceRecognition=true` 강제, 불가 시 끔 | ✅ 안 함 | 막힘(단 RT-B-02 모순) |
| 6 | Sentry(앱·서버) breadcrumb·request.data·에러 본문 | 원문 조각, 제공자 에러 메시지에 되돌아온 입력 | ❌ | ❌ | ✅ "제공자 응답 본문 예외에 안 실음" | ✅ `EngineError`에 본문 금지·`before_send`·화이트리스트 로거·테스트 | ✅ 카나리 5층·`SentryScrubber` 순수 함수 | ❌ | ❌ | 막힘. 단 **attachScreenshot/attachViewHierarchy 명시 OFF 없음**(경미 RT-B-24) |
| 7 | Amplitude 속성·autocapture | 탭한 요소 라벨(용어 텍스트) | ⚠ 15→6개 | ⚠ "행동 지표만" | ❌ | ❌ | ✅ `AnalyticsValue` enum·화이트리스트 테스트 | ❌ | ❌ | ⚠ **Amplitude-Swift autocapture(elementInteractions) 끄는 결정 없음** — RT-B-18 중요 |
| 8 | 서버 로그·Caddy·uvicorn | 바디·쿼리 | ❌ | ❌ | ✅ 로그 grep 테스트 | ✅ `__repr__` 글자 수·dict 화이트리스트 | ✅ 카나리 | — | — | 막힘 |
| 9 | `ai_usage`/`usage_daily` → `eval/data/*.csv`(공개 저장소) | 텍스트 0(스키마), 사용 통계 | ❌ | ⚠ usage.yml 커밋 | ❌ | ✅ 텍스트 컬럼 0 | ❌ | — | — | 원문은 안 나감. 사업 지표 공개는 U-18 |
| 10 | 평가셋·judge·LoRA 데이터에 실사용 원문 유입 | 원문 → Gemini judge·HF 리포·공개 저장소 | ❌ | ❌ | ⚠ AI-8 "합성만" / AI-1 §7 "옵트인 신고 문장으로 v2 교체"(열림) | ❌ | ✅ QA-2 "합성만, 위반 시 히스토리 정리" | — | — | ⚠ AI-1 §7의 옵트인 경로는 공개 저장소·judge와 결합 시 유출 — 경미 RT-B-25 |
| 11 | MLX 모델 다운로드(HF Hub) | 원문 무관, 다운로드 텔레메트리·IP | ❌ | ❌ | ⚠ "원문과 무관" | ❌ | ❌ | ❌ | ❌ | `HF_HUB_DISABLE_TELEMETRY` 미언급, "네트워크 Spy 0" 테스트가 첫 실행에 실패 — 경미 RT-B-26 |
| 12 | APNs payload | `action_text`(AI가 원문에서 뽑은 문장)·`meetings.title` | ❌ | ❌ | ❌ | 🔴 ACTION_DUE body = `action_text` 60자, Q3로만 남김 | ❌ | ❌ | ✅ MN-1 "alert에는 용어·개수·회의 제목까지만" | **파트 간 반대** — RT-B-19 중요 |
| 13 | MySQL 백업(`mysqldump` → S3, 30일) | 원문·transcript 전체 | ❌ | ❌ | ❌ | ❌ | ❌ | — | — | 14번 §6에 있으나 **암호화·접근권한을 아무도 안 씀** — 경미 RT-B-27 |
| 14 | Foundation Models / Vision / 클립보드 / 카메라 이미지 | 기기 밖 안 나감 | ✅ | ✅ | ✅ 네트워크 Spy 테스트 | — | — | ✅ | ✅ 메모리 처리 후 폐기 | 막힘 |

### RT-B-18 | 중요 | QA §2-3 앱 Amplitude 행 · 12번 §10 · PM Day 29 | Amplitude SDK 자동 수집(autocapture) 끄는 결정 없음
- **문제**: QA는 우리 코드가 보내는 속성만 enum으로 막았다. Amplitude-Swift SDK의 autocapture(세션·화면·**요소 상호작용** — 탭한 뷰의 접근성 라벨/타이틀 수집)를 명시적으로 끄지 않으면 용어 텍스트·회의 제목이 라벨로 나간다. 규칙 5(접근성 라벨 필수)가 있어 라벨에는 내용이 들어간다.
- **근거**: QA §2-3 표 "앱 Amplitude" 행(우리 `AnalyticsService`만 검사), 12번 §10 "텍스트 속성 금지"(SDK 옵션 언급 없음). SDK 기본값은 **확인 필요**(버전별 상이).
- **권고**: Sentry `attachScreenshot=false`·`attachViewHierarchy=false`·`enableAutoBreadcrumbTracking` 범위와 함께 Amplitude `autocapture = []`(또는 세션만)를 ADR에 명시하고, QA 카나리 통합(야간) 흐름에서 "버튼 라벨에 카나리" 케이스 추가.

### RT-B-19 | 중요 | Backend B-3 §5-3 ACTION_DUE vs macOS_iPad MN-1 4항 | 잠금화면 알림 본문에 AI 추출 문장 노출 — 두 파트가 반대 설계
- **문제**: Backend는 `action_text`(AI가 원문에서 추출한 할 일 문장)를 body로, macOS·iPad는 "용어·개수·회의 제목까지만"으로 고정. `action_text`는 사실상 원문의 재서술이며 APNs(Apple 서버)와 잠금화면(타인 시야)을 거친다. 회의 제목(`meetings.title`)도 기밀일 수 있다("OO 인수 검토").
- **권고**: 사용자 결정 U-10. 기본은 MN-1(제목·개수만) + v1.1 "미리보기 표시" 옵트인. `contracts/push-examples/*.json`을 이 기본으로 통일하고 서버 빌더 grep 테스트에 `action_text` 추가.

---

## 4. 운영·CI

### 계산 (QA §1-5 `app.yml` 변경안 + `app-nightly.yml` 기준, 첫 실측 전 추정)
- PR 1회 macOS-분: lint 4 + build-test 15 + snapshot 3×10 = **≈ 49분**, macOS job 5개 동시.
- main 푸시 1회: 49 + e2e-ios 10 = 59분. 야간: ios17-min 60 + mac-a11y-xcui 25 = 85분(ubuntu ai-eval 별도).
- 월(34 근무일, PR ≈ 50건, 푸시 ≈ 50건, 야간 30회): 50×49 + 50×59 + 30×85 = **≈ 7,950 macOS-분/월**.
- 저장소는 **PUBLIC**(`gh repo view YooGyeongMo/-` → `"visibility":"PUBLIC"`). GitHub 정책상 공개 저장소의 표준 hosted 러너는 무료 → 과금 0. **비공개로 전환하면** macOS ×10 = 79,500분 ≈ 무료 2,000분의 **40배**(≈ $600/월 초과분, 단가 확인 필요). iOS.md 매트릭스(96장/PR + 2 destination)와 macOS_iPad(~90장)를 더하면 더 커진다.
- 동시성: Free 플랜 macOS 동시 job 5(QA도 "확인 필요"). PR 하나가 5개를 정확히 채우므로 PR·푸시가 겹치면 대기 → QA-1 "PR ≤ 15분" 목표는 단독 실행일 때만 성립.

### RT-B-20 | 중요 | iOS A1 §2·A-5·A-6 · macOS_iPad MI-5 §2 · ADR-0002 · QA §1-4 | self-hosted 러너를 PR 기본으로 쓰는 안 — 공개 저장소에서 fork PR 코드가 개발 Mac에서 실행
- **문제**: iOS.md는 "hosted macOS 러너는 분당 10배 과금이라 self-hosted Mac을 기본"이라며 A-6 표에서 self-hosted를 "PR 기본"으로 둔다. (1) 과금 전제가 틀렸다(공개 저장소 무료, QA F-3). (2) ADR-0002 "결과" 항은 `pull_request_target` 금지만 적었지 `pull_request`에서의 self-hosted 배정을 막지 않아, iOS.md 안대로면 외부 fork PR의 `tuist generate`·SwiftLint 플러그인·빌드 스크립트가 개발자 Mac(sops age 키·Keychain·시뮬레이터 런타임 보유)에서 실행된다. QA §1-4만 "PR에는 절대 배정하지 않는다"고 올바르게 썼다.
- **근거**: iOS.md A1 비용 항 마지막 줄, A-6 러너 표 1행, MI-5 "self-hosted 러너 우선 16번 §1", ADR-0002 결정·결과 항, QA §1-4 보안 단락.
- **권고**: ADR-0002 개정(사용자 결정 U-15): "PR = hosted 전용, self-hosted는 `push main`·`schedule`·`workflow_dispatch`만 + 러너는 별도 macOS 사용자 계정·ephemeral". iOS·macOS_iPad 메모의 러너 표는 QA 표로 교체.

### RT-B-21 | 중요 | QA F-1·F-2·F-5 · BRIEF "Xcode 26.4(17E192)" · iOS A-6 | hosted `macos-26` 이미지 사실이 출처 없이 단정됐고, Xcode 핀(26.5)이 사용자 보유 버전(26.4)과 다름
- **문제**: QA F-1은 "macos-26 이미지 2026-02-26 GA, OS 26.6.1, Xcode 26.0.1~26.6(기본 26.6), iOS 26.2/26.4/26.5 시뮬레이터, iOS 17.x 없음"을 사실로 적었으나 출처(actions/runner-images README·릴리스 노트 URL)가 없다. 같은 사실을 iOS·macOS_iPad는 "확인 필요"로 뒀다. F-2 "macos-14 2026-07-06 폐기 시작·11-02 종료"도 동일. 그리고 QA는 `XCODE_VERSION: "26.5"`로 핀하지만 사용자 Mac은 **26.4(17E192)**(BRIEF) — 스냅샷은 Xcode 고정이 전제(QA F-5)이므로 로컬 기록·CI 검증이 다른 Xcode에서 돌게 되어 첫 PR부터 diff가 난다. 시뮬레이터 런타임도 사용자는 17.0인데 QA·iOS는 17.5.
- **권고**: F-1·F-2에 출처·조회일을 붙이거나 "확인 필요"로 강등. Xcode 핀은 **사용자 보유 26.4로** 맞추고 러너 이미지에 26.4가 있는지 확인(없으면 스냅샷 기록 위치를 CI로 단일화). 런타임은 17.0으로 통일.

### RT-B-22 | 중요 | QA §1-5 build-test · 16번 §1 · ADR-0002 · 현재 `app.yml` | 현재 워크플로와 결정의 괴리 — `latest-stable`·`macos-15`·`tuist test`가 그대로
- **문제**: 저장소 `app.yml`은 `macos-15` + `xcode-version: latest-stable` + `tuist test MwonmalIOS --no-selective-testing`이고, 16번·ADR-0002는 self-hosted 우선인데 워크플로에는 self-hosted 잡이 없다. QA 변경안은 `macos-26`·`26.5` 핀·`xcodebuild -only-testing` 7개로 바꾸지만 이것이 S0 Day 1(이미 완료된 PR #31)에 들어갈 자리가 없다 — PM §2에 CI 변경 이슈가 없다.
- **권고**: PM §2 Day 2에 `[S0][infra] app.yml 러너·Xcode 핀·매트릭스 v2`(0.5일)를 추가하고, `server.yml`의 `schemathesis … || true` 제거(QA S-7)를 Day 4 완료 기준에 명시.

---

## 5. 기록 형식 (REQ-20)

### RT-B-23 | 경미 | AI-5 · AI-6 · Backend B-6 ② · macOS_iPad MN-4 · QA §2-3 | 7항목 형식이 빠진 결정
- AI-5(FM 게이트·MESSAGE 500자·MEETING_NOTE 제외), AI-6(MLX 숨은 플래그): §0 요약표에만 있고 7항목 본문 없음. PM §5 기준 "형식이 빠진 결정은 무효".
- Backend B-6 ② "Alembic ENUM 전략 확정: MySQL 네이티브 ENUM + `device_platform`에 MACOS/WATCHOS 초기 포함": 스키마 결정인데 의도·대안 없음(JSON/CHECK/lookup 테이블 대안 미검토, `ALTER ENUM` INSTANT 여부 확인 필요를 근거로 씀).
- macOS_iPad MN-4 "할 것 3/하지 말 것 3": 결정 6개가 목록만.
- QA §2-3 "결정 기록(요약)": 영향 파일·검증 방법 항 누락(비용·대안·왜·되돌림만).
- **권고**: 해당 파트가 같은 세션에서 보강. 특히 AI-5는 RT-B-02 결정과 묶어 재작성.

### RT-B-24 | 경미 | 12번 §10 · QA §2-3 · iOS | Sentry 첨부 옵션 명시 없음
- `attachScreenshot`, `attachViewHierarchy`, `enableAutoBreadcrumbTracking`(UI 이벤트 breadcrumb에 접근성 라벨 포함 가능)의 OFF가 어느 메모에도 없다. 12번 §10은 `sendDefaultPii`·리플레이·바디만 다룸. → ADR 초안(QA §4 Sentry 행)에 옵션 표 추가.

### RT-B-25 | 경미 | AI-1 §7 · QA-2 §7 | 평가셋 v2 "옵트인 사용자 신고 문장" 경로가 공개 저장소·judge와 결합
- AI-1 §7은 출시 후 사용자 신고 문장으로 평가셋을 교체한다고 했고, 평가셋은 공개 저장소 `eval/data/*.jsonl`이며 judge는 Gemini 무료다. 옵트인이라도 회사 기밀 문장이 공개·학습 경로로 간다. → "신고 문장은 비공개 브랜치·로컬 judge(MLX)만, 공개 평가셋은 합성 유지"로 못 박을 것.

### RT-B-26 | 경미 | AI-8 표 ③ · AI-6 | MLX 모델 다운로드 텔레메트리·"네트워크 0" 테스트 충돌
- HF Hub 다운로드는 텔레메트리 헤더·IP를 보낸다(`HF_HUB_DISABLE_TELEMETRY`, swift-huggingface 동작은 확인 필요). AI-8 "온디바이스 경로 네트워크 Spy 호출 0" 테스트는 첫 실행 다운로드에서 실패. → 다운로드 단계와 추론 단계를 분리해 추론 단계만 Spy 0.

### RT-B-27 | 경미 | 14번 §6 백업 · Backend · PM Day 30 | 원문 전체가 든 `mysqldump` 백업의 암호화·키 관리 결정 없음
- 백업 = 원문·transcript 영구본이 R2에 30일. 어느 메모도 서버측 암호화(sops age 키로 gpg? R2 SSE?)·복구 연습 시 로컬에 풀리는 덤프 삭제를 다루지 않음. → Day 30 완료 기준에 "백업 암호화 + 복구 후 로컬 덤프 shred".

### 사실처럼 쓴 "확인 필요"(추가 목록)
- iOS A1 비용 "hosted macOS 러너 분당 10배 과금" — 공개 저장소에는 틀림(RT-B-20).
- PO-2 "무료 사용자 한계원가 상한 100원/MAU를 라우터 정책 상수로" — 가정 단가에서 나온 값을 상수로 승격(RT-B-09).
- PO-1 §1-4 "Gemini 무료는 MAU ~140에서 소진" — 산식 오류(RT-B-08).
- Backend B-3 §3 vs macOS_iPad §0 `WKApplication` 행 — Apple 문서 인용이 서로 다른 뉘앙스("종속 앱은 iPhone만 보내도 됨" vs "항상 양쪽에 보내라"). 둘 중 하나는 인용 오류. 확인 필요.
- QA F-1·F-2(러너 이미지 날짜) — 출처 없음(RT-B-21).
- Backend B-4 "Groq Whisper 2,000 req/일·28,800초/일·20 RPM·카드 불필요" — 표 아래 "전부 확인 필요"라 적었으나 §4 "왜"와 큐 설계(18 RPM)가 이 값을 사실로 쓴다.
- 12번 자체 모순(참고): §10 "이벤트 15개" vs §16 단계 5 "이벤트 8개" vs PM "6개" vs QA·PO "15개".

---

## 6. 무료 한도 초과 정책의 파트 간 일관성 (과제 2 소항목)

| 상황 | PO-3 | Backend B-1/B-4 | AI-2 §4-1 | 일치? |
|---|---|---|---|---|
| Gemini 429/한도 소진 | 즉시 폴백(재시도 없음) → Groq → 503 `AI_UNAVAILABLE` + `Retry-After: 5`. **사전 매칭 결과는 503이어도 반환 안 함** | DETECT: gemini(cheap)→gemini(strong)→vllm→anthropic→openai→`none`(dev 허용/prod 503). NUANCE: **생략(null)**, 503 아님 | 예산 게이트 후보 순서 → 전부 소진 503 | ❌ PO는 "사전만 결과 금지", Backend는 `none`(사전만) 강등을 dev 기본·prod 옵션으로. NUANCE 생략을 PO는 언급 없음 |
| 개발 중 일일 예산 | RPD × 50%, 초과 시 503, 로그 지표만 | 엔진 일 한도 80% → NUANCE 생략, 95% → DETECT `none`/503 | 잔량 < 10% → 다음 후보 | ❌ 세 가지 임계(50% / 80·95% / 90%) |
| 유료 전환 | 출시 시 ADR + `over_limit: pay`를 트랙 단위로만 | REQ-11 재협의 필요 | 429 > 5%/일이면 PO에 유료 전환 요청 | ⚠ 방향은 같으나 트리거 다름 |
| 결제 방지 장치 | `APP_ENV != prod and over_limit == pay → 기동 실패` | 없음(운영자 키 크레딧 소진을 402로 처리 = 결제 발생 후) | 없음 | ❌ RT-B-12 |

→ 정책 소유자를 Backend 하나로 정하고 PO-3 규칙표·AI §4-1은 그 문서를 인용. `ROUTER_ALLOW_DEGRADED`(사전만 결과) 허용 여부는 U-9.

---

## 7. 사용자 결정 필요 목록 (에이전트가 임의로 정한 것)

| # | 항목 | 어디서 정했나 | 왜 사용자 몫인가 |
|---|---|---|---|
| U-1 | BM = 무료+구독, 월 4,900원, **녹음은 유료 전용**, 무료 월 30분 체험, 유료 상한 200분 | PO-2 | 가격·수익 모델은 제품 소유자 결정. 근거 단가가 가정(RT-B-09) |
| U-2 | REQ-15 신설(무료 녹음 분 상한) | PO-2 5항 | REQ 대장은 사용자 소유 |
| U-3 | 카카오 로그인 → Google·Apple만(다음 컷 1) | PM §3-2 #7 | 로그인 수단은 도달 범위·T-D6 심사 요건과 직결 |
| U-4 | macOS TestFlight 11/13(v1.0.1) 분리 | PM-4 | 16번 v1.0 정의 변경 |
| U-5 | v1.1 이관: Vision OCR(D-6), SpeechAnalyzer 미리보기(D-7·T-D3), 라이브 액티비티(T-D1), @SceneStorage, macOS 로컬 알림(D-19), AWS prod(REQ-32), 퀴즈 오답 AI, Amplitude 15→6·Sentry 트랜잭션 제거·대시보드 4→2, Maestro 4→2, macOS XCUITest | PM §2·§3-2 | 제출본 설계 결정 8건과 REQ-31·32 범위를 바꿈 |
| U-6 | Gemini 무료 티어에 실사용자 원문 전송(고지+옵트아웃 / 온디바이스·BYOK만 / 유료 전환) | AI-4가 에스컬레이션, Backend·PM은 1순위로 진행 | 약관 "기밀 제출 금지"와 REQ-14·11의 충돌 |
| U-7 | 회의 오디오를 Groq Whisper / Gemini 오디오로 전송 | Backend B-4 | 오디오 외부 전송·약관 미확인 |
| U-8 | "사용자 제공 키"의 뜻: 운영자 `.env` 키(결제 = 개발자) vs 최종 사용자 BYOK vs 평가 전용 | Backend(운영자) / AI(BYOK) / PO(평가 전용) | REQ-11 원문 해석 |
| U-9 | 강등(`none`, 사전만) 결과를 prod에서 허용(앱 "간이 해석" 배지) vs 503 | Backend Q2, PO-3 "반환 안 함" | 제품 품질 기준 |
| U-10 | ACTION_DUE 잠금화면에 할 일 문장 노출 | Backend B-3(노출) vs MN-1(비노출) | 기밀·UX |
| U-11 | Mac 최소 창 900×600·기본 1280×800 | macOS_iPad MI-6(제안) vs iOS C-1 6-10(1000×700 유지) vs 12번 D-20 | 디자인 결정 |
| U-12 | iPad 카메라 OCR 추가(`NSCameraUsageDescription`) | macOS_iPad MI-4 | 신규 기능·권한 문구·심사 |
| U-13 | Liquid Glass v1 미채택(머티리얼) | MI-5 vs iOS A-4 #12(26에서 글래스) vs 05번 디자인시스템 | 디자인 원칙 |
| U-14 | Foundation Models 온디바이스 해석 v1.0 포함 | AI-5(포함) vs PM-2·iOS(미포함) | 차별점·일정 |
| U-15 | CI: PR을 hosted `macos-26`로, self-hosted는 main/야간만(ADR-0002 개정), Xcode 핀 26.4 | QA vs iOS vs ADR-0002 | 개발 Mac 보안·비용 |
| U-16 | `eval/` 위치(루트 vs `services/eval/`) | PO §6 #3 | 모노레포 §16 변경 |
| U-17 | Domain을 watchOS 데스티네이션(10.0)에 올림 | MN-2 | 그래프·CI 변경(ADR-0001) |
| U-18 | 공개 저장소에 실측 `usage.yml`(MAU·1인당 사용량) 커밋 | PO-4 | 사업 지표 공개 |
| U-19 | TestFlight 베타 인원 상한(예: 50명) | PO §6 #4 | 무료 한도·원가 |
| U-20 | 협의체 1.5h/스프린트 상한, 2회 초과 시 격주 | PM-5 | REQ-25 "매 스프린트" 완화 조건 |

---

## 8. 재판정 조건 (같은 세션에서 수정 후 1회)
1. RT-B-01·02: PM이 파트별 v1.0 항목을 Day에 매핑한 합산표 1장 + 세 기능(FM·STT 미리보기·OCR)의 단일 결정.
2. RT-B-10·11·12: Backend B-1 §5-4 사슬·B-4 STT 사슬을 "사용자 결정 전 기본값"(gemini 실원문 OFF, 오디오 whisper_local, 운영자 키 사슬 제외)으로 고치고 U-6·7·8을 사용자에게 질문 목록으로 넘김.
3. 위 2가지가 끝나면 착수 가능 등급으로 재판정. S0 Day 2~4는 지금 착수해도 무방.
