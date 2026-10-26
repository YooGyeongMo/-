# ADR-0019: 온디바이스 지능은 로컬 SPM 패키지 `MwonmalIntelligence` 하나로 묶고, Platform만 링크하며, 패키지는 Domain을 모른다

- 상태: 채택 (2026-10-26) — v1.0은 링크하지 않는다(ADR-0015). 패키지는 저장소에 두고 CI에서 `swift test`만 돈다
- 관련: ADR-0001·0005·0007 §4-5·0008·0011·0015·0016·0018(판교어 탐지 모델), REQ-02·10·14·33, 12번 §2·§18

## 맥락
- 사용자 요구(2026-10-26): iOS 26/27 사용자에게 Foundation Models를 쓰고(게이트), "우리만의 모델 모듈"을 SPM 패키지로. 공개 자료로 확인되는 VoyagerX 사례는 자체 dewarping 모델을 경량화해 온디바이스로 돌린 2019년 글 하나이고, 패키징 방식은 공개되지 않았다.
- 사실(2026-10-26, Xcode 26.4 SDK 확인):
  - FM `LanguageModelError`·`variant`는 26.4 SDK에 없다. `SystemLanguageModel`·`LanguageModelSession`은 Sendable이다. `contextSize`는 26.0 back-deploy.
  - `MLModelCollection`은 sunset("Use Background Assets or NSURLSession"). ODR은 iOS 27부터 deprecated. Apple-hosted Background Assets `ensureLocalAvailability(of:requireLatestVersion:)`는 26.4+이고, 팩 버전은 앱 빌드에 묶이지 않는다.
  - SPM `.process`는 .mlmodel을 컴파일하지 않는다(미리 컴파일한 .mlmodelc를 `.copy`). `coremlcompiler compile --encrypt`가 있다. 암호화 모델은 첫 로드에 키 서버가 필요하다.
- Domain은 Tuist 타깃이라 로컬 패키지가 의존할 수 없다. v1.0 앱은 FM 코드 0줄(ADR-0015).

## 선택지
| 선택지 | 장점 | 단점 |
|---|---|---|
| ① Platform 폴더 안에 직접 구현 | 타깃 증가 0 | 앱 없이 테스트 불가, FM·Core ML 코드가 Platform 재컴파일을 유발, "모듈"로 설명 불가 |
| ② 패키지가 Domain 프로토콜을 쓰도록 Domain을 패키지로 이전 | 어댑터 0 | ADR-0001·0016 역행, Domain watchOS 데스티네이션·Tuist 캐시 재설계 |
| ③ 계약 패키지(`MwonmalContracts`)를 따로 두고 Domain·Intelligence가 공유 | 타입 공유 | Domain "의존 0" 깨짐, 패키지 2개 유지 |
| **④ 자기 값 타입·프로토콜만 가진 로컬 패키지 + Platform 어댑터 (채택)** | Domain 소유 원칙 유지, `swift test`로 앱 없이 검증, 네트워크 0줄을 테스트로 증명, v1.0 링크 0 | 매핑 코드 ≈40줄, 타입이 비슷하게 두 벌 |

## 결정
1. `apps/ios-macos/Packages/MwonmalIntelligence`(swift-tools 6.0, iOS 17 / macOS 14, Swift 6 모드). 제품은 `MwonmalIntelligenceCore`(Foundation만) · `JargonDetection`(사전 trie + Core ML `NLModel` 태거, actor) · `FoundationModelsEngine`(`#if canImport` + `@available(26)`, 게이트 로직은 순수) · `IntelligenceTesting`(Fake). 실행 파일 `mwintel-eval`은 개발 Mac 전용이다.
2. 링크: v1.0은 `packages:`에 넣지 않는다. v1.1부터 **Platform만** 링크한다(`IntelligenceTesting`은 테스트·Example만). Feature·Domain·Data는 금지이고, 의존 검사 스크립트에 규칙을 추가한다.
3. 경계: 패키지는 Domain을 모른다. Platform `AI/` 어댑터가 Domain `TranslationEngine`·오류·가용성으로 매핑한다. `#available`은 패키지(`FMEngineFactory`, `TaggerModelLocator`) 안에만 있다(게이트 ① = Platform 층).
4. 게이트: ADR-0015 다섯 겹을 `FMGate.evaluate`(순수 함수)로 구현한다. 정책 기본값은 닫힘이다. 모델 키는 `fm/apple-26.0|26.4|27-core|27-adv`, 26.4 SDK 빌드가 iOS 27에서 돌면 `fm/apple-27-unknown`(정책에 없음 → 닫힘).
5. 태그: `{track}/{model}#p{n}`(ADR-0007 §4-5). 태거는 `tagger/<model>#p<병합정책>`, 사전만은 `none/dictionary#p1`. 텔레메트리 이벤트에는 문자열 필드가 없다(태그 제외).
6. 리소스: v1.1은 미리 컴파일한 .mlmodelc를 `.copy`로 동봉하고, 사전만 쓰는 경로가 항상 바닥이다. v1.2는 Apple-hosted Background Assets(26.4+) + 팩 manifest 호환 검사 + 번들 폴백. ODR·`MLModelCollection`·패키지 내 URLSession은 금지. Core ML 암호화는 비공개 데이터로 학습한 모델이 생길 때까지 보류.
7. 인덱스 단위는 유니코드 스칼라다(서버·eval·Python과 같다). 미리보기에는 형광펜을 그리지 않는다(ADR-0015·REQ-14). 태거 결과는 개수 칩·FM 힌트·오프라인 상태에만 쓴다.
8. 평가: `eval/dataset/*.jsonl`을 그대로 읽고, `mwintel-eval`은 예측 JSONL만 낸다. 채점은 `eval/run.py` 한 곳에서. 학습–추론 토큰화 패리티 테스트를 필수로 둔다.
9. 27 전용 API(`LanguageModelError`, `variant`, PCC)는 Xcode 27 CI 전환(ADR-0011 개정) 뒤 `#if compiler(>=6.4)` 블록으로만 추가한다. PCC는 이 패키지에 넣지 않는다(원문이 기기를 나감, 별도 ADR).

## 근거
- 스켈레톤 검증(2026-10-26, Xcode 26.4): `swift build` 경고 0. `swift test` 통과 32 / 실패 0 / 건너뜀 1(FM 실호출, 사유 출력: Apple Intelligence 꺼짐). Core ML 태거의 Swift 추론이 Python 실험과 60문장 모두 라벨 일치(F1 0.827). 최소 macOS 14에서 FoundationModels·BackgroundAssets는 `LC_LOAD_WEAK_DYLIB`. iOS Simulator 빌드 성공. 패키지 소스에 네트워크 API 0건(테스트).
- 패키지는 MwonmalUI가 이미 쓰는 "SDK는 값만 받는다" 원칙의 지능판이다. 경계가 컴파일러와 테스트로 지켜져 1인 리뷰 부담이 적다.
- 모델 갱신 경로를 Apple 공식 권장(Background Assets)에 맞추면 서버 비용 0, 심사 없는 모델 교체가 가능하다.

## 결과 (쉬워지는 것 / 어려워지는 것)
- 쉬워짐: 앱·시뮬레이터 없이 `swift test`(1분 미만)로 엔진·게이트·패리티 검증. 모델 교체가 태그 하나로 추적된다. FM 미지원 기기·OS·27-unknown이 전부 같은 "닫힘" 경로로 수렴한다. 포트폴리오에서 "모델 + 모듈 경계 + 평가 + 폴백"을 한 저장소 경로로 보여 줄 수 있다.
- 어려워짐: 비슷한 값 타입이 두 벌(패키지·Domain)이고 매핑 테스트가 필요하다. 에셋 팩은 모든 앱 버전에 배포되므로 I/O 스키마를 버전 관리해야 한다. 정적 링크 + SPM 리소스 번들 확인이 필요하다. v1.0 CI 검사를 grep에서 바이너리 `otool`로 바꿔야 한다.

## 되돌리는 조건
- 매핑 코드가 200줄을 넘거나 Domain과 패키지 타입 변경이 릴리스마다 2회 이상 동시에 일어나면 → 선택지 ③(계약 패키지)을 재검토한다.
- ADR-0018에서 태거가 탈락하면 → `JargonDetection`은 사전만 남기고 Core ML 경로를 삭제한다(제품 구조는 유지).
- Tuist 정적 링크에서 `Bundle.module`이 동작하지 않으면 → 모델과 사전을 앱 번들 리소스로 옮기고 `.file(URL)`로만 주입한다.
- Core AI(27+) 채택률이 최소 OS 상향 조건(ADR-0005)에 도달하면 → `CoreAITagger`를 추가하고 Core ML 경로를 단계적으로 폐기한다.
