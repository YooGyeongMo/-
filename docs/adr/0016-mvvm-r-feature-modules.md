# ADR-0016: 표현 계층은 MVVM-R(@Observable 화면 모델 + UseCase + 단일 AppRouter), 화면 흐름은 기능 모듈로 나눈다

- 상태: 채택 (2026-10-26) — 사용자 지시 "TCA·MVVM·MV 기술 트레이드오프 다 고려하고 모듈화 빡세게"(2026-10-26)
- 관련: 설계 12번 D-4(폐기)·D-15(개정)·D-17(개정)·§6·§8, 15번 T-C3(개정), ADR-0001(개정), ADR-0005, ADR-0006(모듈명 변경), ADR-0011, ADR-0013

## 맥락
모든 모듈이 아직 플레이스홀더라 지금은 구조를 바꾸는 비용이 가장 싸다(약 3h). T-C3은 TCA를 한 줄로 기각했고, D-4는 흐름 8개를 Presentation 단일 타깃에 두고 SwiftLint로 격리했다. 1인·하루 3h·v1.0 60h(ADR-0013) 조건에서 다음을 다시 따졌다. (1) TCA, MVVM-C, 순수 MV, 그리고 혼합안. (2) 흐름을 기능 모듈로 나눌지(Tuist TMA).
사실(2026-10-26 확인): TCA 최신은 1.26.2(2026-08-28). 1.25(2026-03)가 2.0 대비 대량 deprecation을 냈고, 2.0은 2026-04-01부터 Point-Free Max 등급의 beta preview이며 GA는 아직 없다. Swift 6.4(Xcode 27)에서 Point-Free 생태계가 연속 회귀 패치를 냈다. Apple 샘플은 @Observable + @State + .environment를 기본으로 하고, WWDC26에서 @State 클래스 lazy 초기화를 iOS 17까지 백포트했다(Xcode 27). Tuist TMA는 개발 동적, 릴리스 정적을 권장한다.

## 선택지
| 선택지 | 장점 | 단점 |
|---|---|---|
| TCA 1.26 → 2.0 | 전이를 빠짐없이 테스트(TestStore), 경로가 값이라 딥링크·복원이 쉽다 | 1.x→2.0 전환기, 2.0 유료 베타, 매크로 빌드 비용(swift-syntax), 단일 벤더, 60h 안의 러닝커브, Clean UseCase와 Dependency 이중 구조 |
| MVVM-C(현행) | 익숙함, 설계 완료 | 흐름 팩토리 8 + Coordinating 8 + 이중 코디네이터 보일러플레이트, Presentation 단일 타깃이라 한 화면 수정에 8흐름을 재컴파일 |
| 순수 MV | 가장 적은 코드, Apple 샘플과 같음 | 비동기 액션·취소·내비 로직이 View로 들어가 단위 테스트 불가, 리뷰어에게 "구조 없음"으로 보일 위험 |
| **MVVM-R + 기능 모듈 (채택)** | D-15·D-17·ADR-0006 유지, 라우팅이 한 줄, Feature 병렬 컴파일, Example 앱으로 로그인 없이 실행, 격리 설정을 모듈별로 | 타깃 수 19 → 약 27, AppRoute 수정 시 모든 Feature 재컴파일 |

## 결정
1. 화면 상태는 `@MainActor @Observable` 화면 모델(D-15 계약 유지). 사용자 액션 메서드는 `@discardableResult -> Task<Void, Never>`를 돌려 테스트가 기다릴 수 있게 한다.
2. 흐름 Coordinator(8 팩토리, 8 `*Coordinating`, AppCoordinator/TabCoordinator 이중 구조)는 없애고, `Routing` 모듈의 `AppRouter`(@Observable, 탭·경로·시트·딥링크 큐) 하나와 `AppNavigating` 프로토콜 하나로 바꾼다. 목적지 해석은 Composition의 `RouteDestination` 하나가 맡는다. `AdaptiveRoot`는 목적지 클로저를 받는 제네릭으로 Routing에 둔다.
3. 모듈: Domain, DomainTesting, MwonmalAPI, Platform, Data, MwonmalUI, Routing(구 Navigation), FeatureKit(구 Presentation/Common), `<Flow>Feature`(v1.0: Auth, Translate, Home, Settings; v1.1: Onboarding, Review, Quiz; v1.2: Project, Meeting), Composition, 앱 3개. Example 앱은 Translate·Review·Meeting만. Feature별 Interface·Testing 타깃은 만들지 않는다(계약은 Routing·Domain, Fake는 DomainTesting).
4. 금지: Feature→Feature, Feature→Data/Platform/MwonmalAPI, 코어→UI 계층. 강제 수단: 매니페스트 헬퍼 허용 표(생성 실패), `enforceExplicitDependencies`, CI `tuist inspect dependencies` + `tuist graph --format json` 검사 스크립트, SwiftLint `feature_forbidden_import`.
5. 제품 유형: 개발 `.framework`, 아카이브·릴리스 `TUIST_PRODUCT_TYPE=static`. App Intents 프레임워크(도입 시)만 항상 동적.
7. 문구: 화면 문구는 코드 리터럴이 아니라 **모듈별 String Catalog(`Resources/Localizable.xcstrings`)** 로 관리한다. 개발 언어 ko, v1.0부터 en 동시 제공. 키는 `<feature>.<screen>.<element>` (예: `translate.result.plainTitle`), 조회는 `String(localized:bundle: .module)`·`LocalizedStringResource`. 키 누락·미번역은 CI에서 실패(xcstrings 검사 스크립트). MwonmalUI는 문자열을 갖지 않는다(D-21 유지).
6. 격리: UI 계층 모듈만 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY=YES`. Domain/Data/API/Platform은 nonisolated + strict complete.

## 근거
- 이 앱의 핵심 로직은 이미 순수 함수(DeepLink, LevelTable, HighlightRange)와 UseCase 테스트에 있다. 경로 상태도 이미 한 객체(D-17)에 있다. TCA 고유의 이득 중 남는 것은 "VM 전이 테스트 문법"뿐인데, 그 대가(전환기 API, 유료 베타, 매크로 빌드, 벤더 의존)가 60h 예산에서 비싸다. 가중 평가 TCA 320 / MVVM-C 405 / MV 340 / MVVM-R 440 (/500).
- Coordinator의 가치(테스트 가능한 내비)는 `AppNavigating` Spy 하나로 그대로 얻는다. 흐름 팩토리 8개는 v1.0에 화면이 4흐름뿐이라 순수 비용이다.
- 기능 모듈은 경계를 린트 정규식이 아니라 컴파일러가 지키게 하고, Feature를 병렬 컴파일하며, Example 앱으로 하루 3h 루프의 로그인·서버 대기를 없앤다. D-4가 걱정한 "Navigation이 8개를 import"는 Composition 한 곳의 정상적인 조립으로 바뀐다.
- 국내 대형사 공개 자료(토스 Microfeature + Tuist, 모듈 약 700개)와 공고 표본(MVVM 다수, TCA 소수)에 비추면 포트폴리오 설명력도 이 쪽이 높다.

## 결과 (쉬워지는 것 / 어려워지는 것)
- 쉬워짐: 화면 하나 = Feature 하나로 읽힌다. `tuist generate tag:feature:translate` 포커스. 로그인 없이 Example 실행. Intent·위젯이 Feature 없이 Domain + DeepLink만으로 진입한다. 격리를 모듈별로 다르게 줄 수 있다.
- 어려워짐: 타깃 수 증가(약 27). AppRoute를 바꾸면 모든 Feature를 재컴파일하므로 라우트 추가는 릴리스 시작일에 몰아서 한다. 동적과 정적 링크 차이는 야간·릴리스 CI에서 잡아야 한다. 의존 규칙 위반 메시지가 `tuist generate` 출력에 안 보여 CI 스크립트가 필요하다. 12번 §6·§8, 15번 T-C3, ADR-0001·0006, `.swiftlint.yml` 개정.

## 되돌리는 조건
- TCA 2.0 GA 후 3개월간 회귀 패치 없이 안정적이고, 동시에 v1.2 회고에서 "전이 누락·효과 순서" 버그가 2회 이상 확인되면 → 신규 Feature 하나만 TCA 2.0으로 시범 운영한다(병행 기한 1 릴리스).
- 화면 모델 의존 인자가 평균 5개를 넘거나 Example/Preview 조립이 Feature당 30줄을 넘으면 → Feature 계층에만 swift-dependencies를 도입한다.
- Feature가 다른 Feature의 화면을 자식으로 임베드해야 하면 → 그 Feature에만 `XxxFeatureInterface`를 만든다.
- 타깃 수가 커져 `tuist generate`가 10s를 넘으면 → 코어 묶기(MwonmalAPI + Data).
- 상태 1~2개, 비동기 액션 0개인 화면은 VM 없이 View + @State로 둔다(상시 예외).

## 부록: 평가표 (가중 /500)
| 기준 (가중치) | TCA | MVVM-C | MV | **MVVM-R** |
|---|---|---|---|---|
| 테스트 (15) | 5 | 4 | 2 | 4 |
| Swift 6 마찰 (10) | 3 | 4 | 4 | 5 |
| iOS 17 (5) | 5 | 5 | 5 | 5 |
| 내비·딥링크·Intent 진입 (15) | 4 | 4 | 3 | 4 |
| 보일러플레이트·속도 (20) | 2 | 3 | 3 | 4 |
| 빌드·프리뷰 (10) | 2 | 4 | 5 | 4 |
| 가독성·포트폴리오 (10) | 3 | 5 | 2 | 5 |
| 의존 위험 (5) | 2 | 5 | 5 | 5 |
| Clean 적합 (5) | 3 | 5 | 2 | 5 |
| Intents·위젯 공유 (5) | 3 | 4 | 3 | 5 |
| **합계** | **320** | **405** | **340** | **440** |

검증: 별도 스케치 프로젝트(Tuist 4.208, Xcode 26.4)에서 27개 타깃 `tuist generate` + iOS 시뮬레이터 빌드 성공, `TUIST_PRODUCT_TYPE=static` 전환 확인, UI 모듈만 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` 적용 확인. 금지 의존을 넣으면 생성은 실패하지만 메시지가 안 나와 CI 스크립트가 필요. 미확인: 정적 프레임워크의 App Intents 메타데이터 추출, 계정 없는 로컬 캐시.
전체 조사(출처 URL 포함)는 PR 본문과 이슈에 남긴다.
