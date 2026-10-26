# ADR-0015: 온디바이스 AI는 v1.0에 넣지 않는다. v1.1부터 Foundation Models를 "모델 태그별 게이트를 통과한 미리보기"로만 쓴다. PCC·MLX·Core AI·llama.cpp는 조건부 보류, App Intents는 v1.1부터 단계 도입

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-10-26) |
| 관련 REQ | REQ-02, REQ-10, REQ-12, REQ-14, REQ-20, REQ-33 |
| 관련 결정 | ADR-0005 §4 게이트(개정), ADR-0007 §4-3·§4-5·§8(개정), ADR-0008 부록 B #14(분리), ADR-0011(Xcode 27 전환 조건), ADR-0013(일정), ADR-0016(모듈), ADR-0018(자체 판교어 탐지 모델, 예정) |
| 출처 | Apple FM 문서(developer.apple.com/documentation/foundationmodels, 2026-10-26 조회), WWDC26 세션 241·319·339, support.apple.com/121115(2026-10-22), App Review Guidelines(2026-10-16), developer.apple.com/private-cloud-compute, GitHub ml-explore/mlx-swift-lm 3.32.3 · apple/coreai-models 1.0.0, developer.apple.com/forums/thread/834805 |

## 1. 의도
WWDC26 이후 상황(iOS 27과 새 온디바이스 모델 AFM 3, Private Cloud Compute 개방, `LanguageModel` 프로토콜)을 반영해 ADR-0007의 "Foundation Models 조건부 포함"을 **실제로 판정할 수 있는 형태**로 다시 쓴다. v1.0(11/20, 60h)의 크리티컬 패스는 건드리지 않는다. 사용자 지시(2026-10-26): "App Intents, MLX, Core ML, 온디바이스 Foundation 모델 활용을 2026-10 Apple 문서·Swift Forums·WWDC 기준으로 빡세게 확인하고 기술 선정".

## 2. 확인한 사실 (2026-10-26, [V]=1차 자료 확인 · [U]=미확인)
| 사실 | 등급 |
|---|---|
| iOS/macOS 27 정식 출시 2026-09-14. 업로드 최소 SDK는 Xcode 26, Xcode 27 요건은 아직 공지 없음 | V |
| FM 모델 버전 3개(26.0–26.3 / 26.4 / 27.0). iOS 27은 기기별 `variant` = `.core3`(3B dense) / `.coreAdvanced3`(20B sparse) | V |
| 온디바이스 문맥 4,096 토큰, 한국어 ≈ 1글자 1토큰. `contextSize`(26.0 back-deploy), `tokenCount(for:)`(26.4+) | V |
| `LanguageModelError`는 27+, `GenerationError`는 deprecated. `LanguageModelSession`은 `Sendable` | V |
| 어댑터 툴킷 26.0.0이 마지막이고 27과 호환되지 않는다 → **FM을 판교어로 추가 학습하는 길은 닫혔다** | V |
| Apple Intelligence는 한국어를 지원하고 한국 지역 제한이 없다(기기 언어 = Siri 언어 필요). 판교어 해석 품질 공개 근거는 없다 | V / U |
| 대상 기기: iPhone 15 Pro 이상·16 전 모델·Air·Duo, iPad M1+·mini(A17 Pro), Mac M1+. iPhone SE 3세대·iOS 17~25는 영구히 불가 | V |
| PCC(`PrivateCloudComputeLanguageModel`): 27+, 32K 문맥, 오프라인 불가, 사용자별 일일 한도. Small Business Program + 첫 다운로드 200만 미만 + managed entitlement면 비용 0(향후 유료 가능). **원문이 기기를 나간다** | V |
| MLX: mlx-swift-lm 3.32.3, iOS 17/macOS 14. 한국어 가능한 4B 4bit 모델은 2.3~3.1GB. Pro 아이폰 프로세스 메모리 한도 ≈6GB 보고(개발자 1명, Apple 답변 없음) | V |
| Core AI(`AIModel`)는 iOS 27+. Core ML은 실행 엔진이지 LLM 학습 도구가 아니다 | V |
| App Intents: `AppIntent`·`AppShortcutsProvider`는 iOS 16+(게이트 불필요). `IndexedEntity` 18+, `SnippetIntent`·`IntentValueQuery` 26+. "번역·해석" 스키마 도메인은 없다 → 커스텀 intent | V |
| 심사 4.2.3(ii): 추가 다운로드는 크기 고지. 5.1.2(i): 제3자 AI 공유는 명시 동의(2026-10-16 개정). PCC가 "제3자 AI"인지는 미확인 → 보수적으로 동의 대상 | V / U |

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| v1.0에 FM 미리보기 포함(ADR-0007 원안) | §8 점수표가 비어 있다. v3 계획(60h)에 Day가 없다. 26 기준 측정은 27 모델로 무효 |
| FM을 정본 엔진으로 | REQ-14(사전 우선·인덱스 재계산) 위반, iOS 17~25·비AI 기기 배제 |
| PCC를 v1.1 옵트인 엔진으로 | 원문이 기기를 나감 → ADR-0008 개정과 entitlement 승인이 먼저. 정본화엔 계약 v1.1 필요 |
| iPhone MLX / llama.cpp | 2~3GB 다운로드(4.2.3), 메모리 한도 경계, 1인 유지비 |
| Core AI 커스텀 소형 LLM / FM 어댑터 | Core AI는 27+ 전용이고 변환·검증이 수 주. 어댑터 툴킷 종료 |
| **(채택) v1.0 서버만 → v1.1 FM 미리보기(태그별 게이트) + App Intents → v1.2 PCC 검토** | — |

## 4. 결정
| 영역 | 규칙 |
|---|---|
| v1.0 | 앱의 FM 코드 0줄, `TranslationEngine` 구현체 0개. 정본은 서버 라우터(Gemini 옵트인 → 사전) |
| v1.0 선택 작업(앱 예산 밖) | `eval/`에 Python `apple-fm-sdk` 어댑터로 Mac 행을 1~2h에 채운다 |
| 게이트(세 겹 → 다섯 겹) | `#available(iOS 26, macOS 26, *)` + `availability == .available` + `supportsLocale(Locale(identifier: "ko_KR"))`(명시) + 토큰 예산 `text.count ≤ min(500, contextSize − 예약분)` + **모델 태그별 기능 플래그** |
| 점수 게이트 | 태그(`fm/apple-26.4`, `fm/apple-27-core`, `fm/apple-27-adv`, Mac)마다 종합 ≥ 서버 최고 80% 그리고 p50 ≤ 3s(MESSAGE ≤ 500자). 최저 측정 기기 iPhone 15 Pro. 야간 평가 2회 연속 미달이면 그 태그 OFF |
| 프롬프트 | instructions 첫 줄 "The person's locale is ko_KR." + 한국어 응답 지시. 사용자 원문은 instructions가 아니라 prompt에만(Apple 문서: untrusted content). 요청마다 새 세션, greedy 샘플링. 모델 태그별 `promptVersion` |
| 미리보기 범위 | 쉬운 말(`resultText`)과 할 일 문장만. 형광펜·`termId`·`dueAt`은 서버 전용(REQ-14). 저장·전송하지 않고, 서버 결과가 오면 교체 |
| 오류 | 27+ `LanguageModelError`, 26 `GenerationError`를 Platform 안에서 Domain `TranslationEngineError`로 변환 |
| 위치 | Domain `TranslationEngine` 프로토콜, Platform `AppleFMTranslationEngine`, 선택은 Composition만(ADR-0005 게이트 규칙) |
| PCC | 사슬에 넣지 않는다. v1.2에 ADR-0008 개정안 + Small Business Program 가입 확인 + entitlement 신청을 묶어 별도 ADR |
| MLX | iPhone 금지. macOS 실험 플래그만(v1.4 이후) |
| 자체 모델 | FM 추가 학습은 불가. 대신 Create ML로 **판교어 탐지 모델**(구간 찾기)을 실험한다 → ADR-0018에서 판정 |
| App Intents | v1.1: `DecodeJargonIntent`("판교어 해석하기") + `AppShortcutsProvider` + `TermEntity`/`CardEntity`. 서버 정본, 옵트인 헤더 규칙 동일. `IndexedEntity`(18+)는 게이트 안에서 사전 용어·카드 제목만 인덱싱(원문·해석 결과 금지). v1.3: `SnippetIntent`·visual intelligence 검토 |
| Xcode | 27 전용 API(`LanguageModelError`, `variant`, PCC)는 CI를 Xcode 27로 올린 뒤에만(ADR-0011 개정 필요). 그 전에는 26 API만으로 v1.1 구현 가능 |

## 5. 비용
- 돈: 0.
- 시간: v1.0 앱 0h(선택 eval 1~2h). v1.1 측정 하네스 0.5일 + 엔진·스키마·게이트·미리보기 UI 2~3일(통과 시) + App Intents 1~1.5일. v1.2 PCC 검토 ADR 0.5일.

## 6. 영향
- ADR-0005 §4: FM 행을 다섯 겹으로, `IndexedEntity`(18)·`SnippetIntent`(26)·`IntentValueQuery`(26) 행 추가, App Intents 위치를 허용 목록에.
- ADR-0007 §4-3 "Mac 26 + iPhone 26 실기" → "모델 태그별 실기". §4-5 태그 예시에 `fm/apple-27-core#p1`. §8 점수표에 `model tag`·`variant` 열.
- ADR-0008 부록 B #14를 "FM 온디바이스(기기 밖 0)"와 "FM PCC(나감, 사슬 없음)"로 분리.
- 12번 §2 `Domain/Services/TranslationEngine`, §18 게이트 표. 14번 §15-1 ② 행.
- 마케팅: v1.0 문구에 "온디바이스·Apple Intelligence"를 쓰지 않는다(v1.0에 없음, 상표 규칙).

## 7. 검증
- v1.0: 앱 소스에서 `import FoundationModels` 0건(grep, CI).
- v1.1: Fake 엔진 VM 테스트(availability 6종 × 서버 성공·실패·지연), 늦게 온 미리보기는 서버 결과 뒤에 무시, 미리보기 경로 네트워크 Spy 0, Instruments Foundation Models 템플릿 토큰 기록, §8 점수표에 태그·기기·날짜 행.
- App Intents: Shortcuts 실행 시 미동의면 `X-Mw-AI-Consent` 미전송, Spotlight 인덱스에 원문 0(카나리 문자열).

## 8. 되돌리는 조건
1. iPhone 15 Pro에서 27 모델 점수 ≥ 서버 최고 80% & p50 ≤ 3s → v1.1 미리보기 ON. 서버 무료 RPD 소진이 잦으면 계약 v1.1 `clientDraft`로 "온디바이스 → 서버 후처리 정본" 경로를 앞당긴다.
2. PCC 점수 ≥ Gemini 그리고 ADR-0008 개정 승인 → v1.2 옵트인 엔진 ADR.
3. 아이폰 메모리 한도·다운로드 정책이 바뀌면 iPhone MLX 재검토.
4. iOS 17~25 사용자가 남아 있는 동안 서버 경로는 없애지 않는다(REQ-02).
