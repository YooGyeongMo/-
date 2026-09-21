# ADR-0008: 실사용자 원문은 옵트인한 사용자만 외부 AI(무료 Gemini)로 보내고, 오디오는 어떤 외부 STT에도 보내지 않는다

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-09-21) — 사용자 결정 "A" |
| 관련 REQ | REQ-14(기밀·사전 우선), REQ-11(무료 티어·결제 0), REQ-27(공개 저장소), REQ-31(관측 PII), **REQ-33**(신설) |
| 관련 결정 | FD-4, AI-4·AI-8, PO-3, Backend B-1 §5-3·§5-4·B-4 **수정**, 12번 §10·§12 확장, RT-A-01·12·13, RT-B-10·11·12·18·19·24, U-6·U-7·U-8·U-9 |
| 출처 | `council/S0/AI.md` §1-①·AI-4·AI-8, `council/S0/PO.md` PO-3, `council/S0/Backend.md` B-1·B-4, `council/S0/REDTEAM_B.md` §3 |

## 1. 의도
REQ-11(무료 티어만)과 REQ-14(기밀) 사이의 충돌을 **사용자가 결정한 형태**로 닫는다. 실사용자 원문·회의 오디오가 나갈 수 있는 경로 12개(REDTEAM_B §3 표) 중 어느 파트도 막지 않았던 4개(Gemini 무료 텍스트, Groq Whisper 오디오, Gemini 오디오, 운영자 키 Claude/OpenAI)를 코드·설정·테스트로 닫는다. "사용자 제공 키"(REQ-11)의 뜻을 하나로 정한다.

## 2. 비용
- 돈: 0. 결제 0원 유지. 외부 STT 미사용이므로 STT 유료 지출 0.
- 시간: 서버 설정 플래그 + 헤더 파싱 + `none` 강등 배지(앱) 0.5일. 고지문·설정 토글 0.5일(S5 전). `faster-whisper`(CPU) 컨테이너 + 실시간 여부 실측 0.5일(S2, RT-A-13).
- 복잡도: prod 사슬이 `gemini_free` → `none` 두 칸으로 단순해진다. 옵트인 신호는 계약 무변경(요청 헤더).
- 유지보수: 제공자 약관 변경 시 부록 갱신이 결정보다 먼저. 무료 한도 카운터는 ADR-0007과 공유.
- 품질: 미동의 사용자는 AI 없는 "간이 해석"(사전 + 규칙)만 — 베타 ≤ 50명 안에서 옵트인 비율을 본다.

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| (a′) 고지 없이 무료 Gemini에 실원문 전송(Backend B-1·PM Day 11 원안) | 약관 "Do not submit sensitive, confidential, or personal information to the Unpaid Services"와 정면 충돌, REQ-14 취지 위반(RT-A-01·RT-B-10 치명). 결정 주체(사용자)에게 올라가지 않은 채 코드 계획이 진행되고 있었음 |
| (b) 실원문은 온디바이스·최종 사용자 BYOK로만, 무료 티어는 합성 데이터 전용 | iOS 17~25·Apple Intelligence 미지원 기기 사용자는 해석 불가 → 제품 불성립. BYOK는 키 저장·삭제 API·약관까지 필요(v1.2 이후) |
| (c) 유료 티어 전환(Flash-Lite 유료 환산 ≈ ₩2.5/건 [예상]) | REQ-11 위반(개발 단계). 출시 시점 재검토 대상으로만(ADR-0009 손익분기) |
| Backend 해석 "운영자 `.env` 키를 prod 1순위" | 운영자 키 크레딧 = 결제(REQ-11 위반 경로), 실사용자 원문이 개발자 개인 계정으로 Anthropic/OpenAI에 감(RT-B-12 치명). 키가 없으면 `UNCONFIGURED`라 당장 결제는 없지만 설계·env 예시·사슬 순서가 "키를 넣으면 유료 1순위" |
| 외부 STT 사슬 `groq_whisper → gemini_audio → whisper_local`(Backend B-4) | Groq 데이터 사용 약관 미확인(AI §1-①), Gemini 오디오는 텍스트와 같은 무료 약관, 회의 원음성은 텍스트보다 민감(화자 식별)한데 12번 §12 위협 모델에 외부 STT 제공자 열이 없음(RT-B-11 치명) |
| **(a) 고지 + 옵트인만 외부 AI, 미동의는 사전·규칙 간이 해석, 오디오는 서버 `whisper_local`만 (채택, 사용자 결정 "A")** | — |

## 4. 왜
AI 파트가 확인한 Google 약관(부록)은 무료 티어 입력을 제품 개선에 쓰고 사람이 읽을 수 있으며 기밀 제출을 금지한다. 그러므로 "기본은 안 보냄, 사용자가 고지문을 읽고 켜면 보냄"이 무료 티어를 쓰면서 약관과 REQ-14를 동시에 지키는 유일한 형태다. 옵트인 신호를 요청 헤더 `X-Mw-AI-Consent: 1`로 두면 계약 v1.0(43 ops)을 바꾸지 않고 앱 설정 토글(로컬 저장)만으로 동작한다. 오디오는 대안이 있다 — OCI A1(4코어/24GB, Always Free)의 `faster-whisper` CPU가 원문이 외부로 안 나가는 유일한 경로(Backend B-4 표)이며, iOS 17이 STT 부하를 늘리지 않으므로(D-7 "서버가 진실") 외부 STT 없이도 부하는 불변이다.

**규칙표**

| 영역 | 규칙 |
|---|---|
| 서버 기본값 | `AI_EXTERNAL_TEXT=off`. off이면 모든 사용자 요청은 `none`(사전 + 규칙) 경로. on이어도 헤더 `X-Mw-AI-Consent: 1`이 없는 요청은 `none` |
| 옵트인 신호 | v1.0: 요청 헤더 `X-Mw-AI-Consent: 1`(앱 A-09 설정 토글, 고지문 읽은 뒤 켬, 로컬 저장). v1.1 계약: `User.aiConsent` 필드로 승격 + `PATCH /users/me` |
| 고지문 | "무료 AI 제공자(Google)가 입력을 제품 개선에 사용하고 사람이 검토할 수 있습니다. 회사 기밀·개인정보가 든 문장은 보내지 마세요." — 문안 확정은 PO, App Privacy 라벨에 반영 |
| 미동의 사용자 | 검수 사전 trie + 규칙 기반 "간이 해석"(`aiModel = "none/dictionary#p1"`), 앱 배지 표시(사용자 결정 U-9 허용). nuance=null, actionItems=[] |
| 베타 | TestFlight ≤ **50명**(사용자 결정, U-19). 옵트인 비율·실패율은 Amplitude bool 속성만 |
| prod 사슬 | 작업 무관, 요청 1회에 4필드 전부 생성: `gemini_free`(옵트인 + 한도 내) → `none`. `openai_key`·`anthropic_key`는 **prod 사슬에 없음**(`APP_ENV=prod`에서 키 존재 시 기동 실패 assert — PO-3 규칙 재사용) |
| dev/eval 사슬 | `gemini_free` → `openai_key`/`anthropic_key`(**평가셋 전용 운영자 키**, `.env` sops) → `none`. 입력은 합성 평가셋만 |
| "사용자 제공 키"의 뜻 | **평가셋 전용 운영자 키**(REQ-11 해석 확정, U-8). 최종 사용자 BYOK는 v1.2 이후(시크릿 저장·삭제 API·약관 필요). `eval/` CLI 인자 또는 로컬 `.env`로만 |
| 오디오 | 서버 `whisper_local`(faster-whisper, CPU)만. Groq Whisper·Gemini 오디오는 약관 확인 결과를 이 ADR 부록에 첨부하기 전엔 **어떤 사슬에도 없음**. 오디오 외부 전송 0. `SFSpeechRecognizer` 폴백은 v1.0 없음(ADR-0005) |
| 무료 한도 | Redis 일/분 카운터 2개 + 피크 RPM 별도(RT-B-08). 개발 예산 = 무료 RPD 50%. CI 외부 호출 0(테스트는 항상 Fake 제공자) |
| 프롬프트 | userId·프로젝트명·회의 제목을 넣지 않는다(원문만). 제공자 에러 본문은 예외에 싣지 않는다(`EngineError`) |
| 관측 | 서버 로그(요청 바디 로깅 금지, `__repr__` 글자 수만), Sentry(`send_default_pii=False`, `beforeSend` 스크럽, **`attachScreenshot=false`, `attachViewHierarchy=false`**, `enableAutoBreadcrumbTracking` 범위 제한 — RT-B-24), Amplitude(**autocapture OFF**, 프로퍼티 allowlist, `AnalyticsValue` enum — RT-B-18), `ai_usage` 테이블(텍스트 컬럼 0) |
| 알림 | APNs `alert.body`에 할 일 문장·원문 절대 없음(ADR-0010) |
| 백업 | `mysqldump`(원문 전체) 암호화 + 복구 연습 후 로컬 덤프 shred — Day 30 완료 기준(RT-B-27) |
| 평가셋·judge·LoRA | 합성 문장만. 옵트인 신고 문장은 비공개 브랜치·로컬 judge(MLX)만, 공개 평가셋은 합성 유지(RT-B-25) |

## 5. 영향 파일·문서
- `services/api/app/decode/infra/engines/policy.py`(prod 사슬 2칸), `router.py`(헤더 → consent), `app/core/settings.py`(`AI_EXTERNAL_TEXT`, prod 키 assert), `stt/whisper_local.py`(dev·prod 유일), `services/api/.env.example`(`GROQ_API_KEY` 삭제, 평가 전용 키에 주석), `infra/docker-compose.yml`(faster-whisper 컨테이너).
- 앱: `Presentation/Settings`(A-09 "AI 해석 켜기" 토글 + 고지 시트), `Platform/Network`(헤더 주입), `Platform/Observability`(Sentry·Amplitude 옵션), 결과 카드 "간이 해석" 배지.
- 12번 §12 위협 모델 표에 **"AI 제공자" 열** 추가(AI-8 표 그대로 + STT 행), §10 불변식에 APNs 열. 14번 §6 개인정보 문단 확장, §1 표 STT 행 "외부 STT API" → "`whisper_local`(CPU)". 13번 §5-2 시크릿 목록.
- REQUIREMENTS: REQ-11 각주(무료 티어 데이터 사용 조항 인지, "사용자 제공 키" = 평가 전용 운영자 키), **REQ-33** 신설.
- 계약 v1.1 백로그: `User.aiConsent`(Backend B-5에 추가). App Privacy 라벨.
- `docs/bm/early-strategy.md`(옵트인 비율이 가설 A의 전제).

## 6. 검증
- 서버 테스트: (1) `AI_EXTERNAL_TEXT=off` 또는 헤더 없음 → 외부 호출 0, 결과 `aiModel` = `none/…`. (2) `APP_ENV=prod` + `ANTHROPIC_API_KEY` 존재 → 기동 실패. (3) STT 사슬에 `whisper_local` 외 엔진이 없음(설정 로드 assert). (4) 어떤 경로에서도 유료 엔드포인트 호출 없음(Fake 제공자).
- 카나리 `MWCANARY-<uuid>`(QA §2-3): 서버 Sentry(`CapturingTransport`)·서버 로그·앱 `SentryScrubber` 순수 함수·Amplitude allowlist — PR마다. 야간: Maestro 흐름 + 로컬 Sentry 싱크 grep, "버튼 라벨에 카나리" 케이스(autocapture OFF 검증).
- `ai_usage` 스키마에 텍스트 컬럼 0(컴파일 수준) + 테스트. 프롬프트 빌더 출력에 식별자 없음.
- `faster-whisper` 실시간 여부(60초 조각이 60초 안에 끝나는지) S2 실측 — 실패 시 §7.
- 베타 시작 조건: 고지문·토글·배지가 TestFlight 빌드에 있음(릴리스 체크 A-15).

## 7. 리스크와 되돌리는 조건
- 리스크: 옵트인 비율이 낮으면 대부분 사용자가 간이 해석만 본다 → 베타 50명에서 비율을 측정하고 ADR-0009 손익분기와 함께 유료 전환(대안 c) 재검토. `faster-whisper` CPU가 실시간 미만이면 OCI A1 4코어를 STT 전용 컨테이너로 분리(14번 §12 확장 트리거 2번 절차). 약관 변경 시 즉시 재평가.
- 되돌리는 조건: (1) Groq/Gemini 오디오 약관을 확인해 부록에 첨부하고 협의체가 승인하면 STT 사슬에 추가. (2) 기업 고객 문의가 생기면 (b) 온디바이스·BYOK를 전면으로. (3) 출시 결정(S6)에서 REQ-12에 따라 유료 전환 ADR을 쓰고 `over_limit: pay`를 트랙 단위로만 연다.

## 부록 A. 약관 인용 (AI.md §1-① 인용, 확인일 2026-09-19)
| 제공자 | 항목 | 인용·사실 | 출처 URL |
|---|---|---|---|
| Google Gemini API 무료 티어 | 데이터 사용 | "Used to improve products: **Yes**"(무료 티어 전 모델). 약관: "Google uses the content you submit to the Services and any generated responses to provide, improve, and develop Google products and services", "human reviewers may read, annotate, and process your API input and output", "**Do not submit sensitive, confidential, or personal information to the Unpaid Services.**" | https://ai.google.dev/gemini-api/terms |
| Google Gemini API | 무료 모델 존재 | `gemini-3.8-flash`, `gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`, `gemini-2.5-flash`, `gemini-2.5-flash-lite`, `gemini-embedding-2`, Gemma 4 등 "Free of charge". Pro 계열은 2026-04 이후 무료 제외(3차 자료, **확인 필요**) | https://ai.google.dev/gemini-api/docs/pricing |
| Google Gemini API | 유료 단가(원가 모델 입력) | 3.8/3.7/3.6 Flash: 입력 $0.75 / 출력 $3.75 per 1M tokens(2026-12-31까지 표기). 3.5 Flash: $1.50 / $9.00. 3.5 Flash-Lite: $0.30 / $2.50 | 같은 pricing 페이지 |
| Google Gemini API | 무료 RPM/RPD | **확인 필요.** 공식 rate-limits 페이지는 수치를 싣지 않고 AI Studio(`aistudio.google.com/rate-limit`)에서 보라고만 함. 3차 자료는 "Flash 약 15 RPM / 1,500 RPD"(2026-05)와 "Flash 20 RPD, Flash-Lite 500 RPD"(2026-09)로 서로 다름 → S0 Day 1에 캡처해 `eval/limits.md` | https://ai.google.dev/gemini-api/docs/rate-limits |
| Groq (LLM·Whisper) | 무료 한도·데이터 사용 약관 | **미확인.** 3차 자료: 30 RPM, 6K TPM, 14.4K RPD(LLM); Whisper 2,000 req/일·28,800초/일·20 RPM(Backend B-4, 전부 "확인 필요"). 데이터 사용 약관은 아무도 확인하지 않음 → 확인 전 어떤 사슬에도 없음 | https://console.groq.com/docs/rate-limits (재확인 필요) |
| Anthropic / OpenAI | 무료 API 티어 | PO 이해로는 무료 API 티어 없음(**확인 필요**). 평가 전용 운영자 키 전제 | — |

## 부록 B. 원문이 나갈 수 있는 경로 12개와 판정 (REDTEAM_B §3 요약)
| # | 경로 | 이 ADR 후 상태 |
|---|---|---|
| 1 | Gemini 무료 티어(텍스트) | 옵트인 사용자만, 기본 off |
| 2 | Gemini 오디오 입력 | 사슬 없음 |
| 3 | Groq Whisper | 사슬 없음(약관 첨부 전) |
| 4 | 운영자 키 Claude/OpenAI(prod) | prod 사슬 제거 + 기동 assert |
| 5 | SFSpeechRecognizer 서버 인식 | 폴백 자체 v1.0 없음 |
| 6 | Sentry breadcrumb·request.data·첨부 | `beforeSend` + 첨부 OFF + 카나리 |
| 7 | Amplitude autocapture | OFF + allowlist |
| 8 | 서버 로그·Caddy·uvicorn | 바디 로깅 금지 + grep 테스트 |
| 9 | `usage_daily` → 공개 저장소 | 텍스트 0, 실측 usage는 `eval/measured/` 비공개 |
| 10 | 평가셋·judge·LoRA 데이터 | 합성만 |
| 11 | MLX 모델 다운로드 텔레메트리 | 원문 무관, 추론 단계만 Spy 0 |
| 12 | APNs payload | 제목·개수만(ADR-0010) |
| 13 | MySQL 백업 | 암호화 + shred(Day 30) |
| 14 | Foundation Models / Vision / 클립보드 / 카메라 | 기기 밖 안 나감 |
