# ADR-0022: 앱 네트워크는 URLSession + OpenAPI 생성 클라이언트 유지(Alamofire·Moya 안 씀), 캐시는 "개인 데이터는 디스크에 0", 실시간은 소켓 없이 폴링·APNs

- 상태: 채택 (2026-10-27)
- 관련: 15번 T-C5(API 클라이언트)·T-C7(로컬 저장)·T-B2(폴링 vs SSE vs WebSocket)·T-B8(업로드), 12번 D-12·D-24, ADR-0008(원문 외부 전송), ADR-0010(알림 payload), ADR-0016(MVVM-R), REQ-14·20
- 사용자 질문(2026-10-27): "URLSession 쓰다가 어떤 문제가 있어서 Moya나 Alamofire를 쓰는지, 그 이유까지 적고", "Alamofire로 전송 계층만 교체하는 건 어떤가"

## 맥락
URLSession만 쓰는 팀이 Alamofire·Moya로 가는 이유는 보통 다섯 가지다.

| URLSession만 쓸 때 문제 | Alamofire가 주는 것 | Moya가 주는 것 | 우리 구조에서 이미 해결된 방법 |
|---|---|---|---|
| ① 엔드포인트마다 URL·메서드·헤더·바디·디코딩을 손으로 쓴다(43개) → 오타·계약 drift는 런타임에 안다 | `AF.request(...).responseDecodable` 로 짧아짐(여전히 손수) | `TargetType` enum 으로 엔드포인트를 한곳에 모음(여전히 손수) | **swift-openapi-generator**: `contracts/openapi.yml` 에서 `Client` 를 생성. 계약이 바뀌면 **컴파일 에러**(T-C5) |
| ② 토큰 붙이기·401 처리·재시도를 요청마다 반복 | `RequestInterceptor`(adapt/retry) | Plugin | `ClientMiddleware` 4개: Auth(Bearer, 401 신호 1회로 합침) · Retry(GET 503만 1회, Retry-After) · Error(공통 봉투 → `MwonmalServerError`) · AIConsent(TaskLocal 동의 → 헤더) |
| ③ multipart 만들기 | `MultipartFormData` | `.uploadMultipart` | 생성기가 multipart 정식 지원(`uploadRecording`, 12번 §7) |
| ④ 테스트 스텁 | `URLProtocol` 직접 | `stubClosure` | `ClientTransport` 프로토콜을 가짜로 바꾸거나 `URLProtocol` 스텁(Data 테스트 10개) |
| ⑤ 응답 검증·로깅·지표 | `validate()`, `EventMonitor` | NetworkLoggerPlugin | 검증은 생성 코드 + ErrorMiddleware. 로깅은 **일부러 안 함**(원문이 요청 바디에 있다, REQ-14) |

정리하면 Alamofire·Moya가 푸는 문제(①~④)는 **생성 클라이언트 + 미들웨어**가 이미 풀었다. 남는 Alamofire 장점은 `ServerTrustManager`(인증서 고정)와 `EventMonitor`(요청 지표) 정도다.

## 선택지

| 선택지 | 장점 | 단점 |
|---|---|---|
| **URLSession + 생성 클라이언트 + 미들웨어(채택)** | 계약 drift 컴파일 에러, 의존성 Apple 패키지만, Swift 6 strict 동시성 그대로, 미들웨어는 순수 함수라 테스트 쉬움 | 생성 타입명이 길다(Mapping 한 층 뒤에 숨김). background URLSession 미지원(아래) |
| 생성 클라이언트 + **Alamofire 전송**(전송 계층만 교체) | `ServerTrustManager`, `EventMonitor` | 공식 Alamofire 전송 없음 → `ClientTransport` 어댑터 ~80줄 손수. 인터셉터·재시도가 미들웨어와 **두 벌**이 된다(어느 층이 401·503을 처리하나 헷갈림). 바이너리 +수 MB |
| Moya(+Alamofire) | 엔드포인트 enum | 계약에서 생성하지 않으므로 ① 문제가 되살아난다(43개 손수). Combine/Rx 확장 중심 |
| 손수 URLSession 래퍼 | 의존성 0 | ①·② 를 직접 다시 만든다 |

v1.2 녹음(최대 200MB) 백그라운드 업로드는 **어느 쪽도 해결하지 못한다**: background URLSession은 delegate 기반 + 파일 업로드만 되고, Alamofire도 background session을 지원 대상으로 두지 않는다. 그래서 그 한 경로만 `URLSession(configuration: .background)` + `uploadTask(fromFile:)`로 손수 쓴다(T-B8, 12번 §7).

## 결정

1. 전송은 `URLSessionTransport` 그대로. Alamofire·Moya는 넣지 않는다(12번 D-24 유지).
2. URLSession은 `.shared`가 아니라 **앱 전용 하나**(`APIEnvironment.makeSession()`):
   - `urlCache = nil`, `requestCachePolicy = .reloadIgnoringLocalCacheData` — 응답에 원문·할 일이 있다. 디스크·메모리 URL 캐시 0(서버 `Cache-Control: no-store`와 이중 방어).
   - `httpCookieStorage = nil` — 인증은 Bearer. 쿠키를 받을 이유가 없다.
   - `waitsForConnectivity = false` — 오프라인이면 바로 실패해야 화면이 "연결 없음 → 다시 시도"를 보인다(기다리면 스피너만 돈다).
   - 요청 20초 / 자원 60초 — 서버 AI 타임아웃 12초 + 사전 바닥 + 왕복 여유.
3. 재시도는 **GET 503 1회**만. POST(해석)는 재시도하지 않는다 — 중복 저장 위험. 대신 서버가 10분 안 같은 문장을 재사용한다(`recent_duplicate`).
4. 인증서 고정(pinning)은 하지 않는다. ATS + 공개 CA로 충분하고, 고정은 인증서 교체 때 앱이 전부 끊기는 위험이 더 크다.

## 캐시 정책 (무엇을 어디에 얼마나)

| 데이터 | 캐시 | 이유 / 트레이드오프 |
|---|---|---|
| API 응답(원문·결과·할 일) | **없음**(디스크·URLCache 0) | 개인 데이터가 기기에 남지 않는다. 대가: 탭을 오가면 다시 받는다 → 응답이 작고(수 KB) 서버 3문 이내라 체감 없음 |
| 방금 해석한 결과 | **메모리 1개**(`AppRootView.prefetched`) | 붙여넣기 → 결과 시트로 넘어갈 때 같은 것을 다시 받지 않는다. 시트가 닫히면 버린다 |
| 화면 모델(ViewModel) | 뷰 수명 동안 1개(`@ViewModelState`) | 부모가 다시 그려질 때마다 새로 만들지 않는다(아래 렌더링) |
| 용어 상세 | 없음(NSCache 안 씀) | 용어 시트는 한 화면에 한 번 열리고 조회수 집계가 서버 기준이다. 캐시하면 조회수와 "내 카드" 표시가 틀어진다. 반복 조회가 측정되면 그때 `NSCache`(메모리만, 로그아웃 시 비움) |
| 사전(판교어 134개) | 서버 메모리 5분(`load_dictionary`) | 앱에는 두지 않는다(v1.0 해석은 서버). 온디바이스 해석(ADR-0015·0019)이 열리면 앱 번들 + 버전 |
| 로그인 토큰 | Keychain | 유일한 영구 저장. 로그아웃·401에서 지운다 |
| AI 동의 | UserDefaults(Bool) | 개인 데이터 아님. 로그아웃·401에서 끈다(#25) |
| 일러스트·아이콘 | 에셋 카탈로그 벡터(PDF/SVG, `preserves-vector-representation`) | 시스템이 크기별로 래스터화하고 캐시한다. 런타임 디코딩·네트워크 0. 종이 질감 1장만 PNG |

**로그아웃 = 한 곳에서 전부 지운다**: `AppSession.endSession(reason:)`가 상태 → `.signedOut`, Keychain 토큰 삭제, 동의 끔.
화면 상태(라우터·시트·화면 모델·`prefetched`)는 `AppRootView`가 트리에서 빠지면서 함께 사라진다(뷰 수명 = 로그인 수명). 직접 로그아웃·401·시작 시 초기화가 모두 이 함수로 온다.

## 렌더링 (네이티브, 커스텀 비용 최소)

- 화면은 전부 SwiftUI 기본 뷰(`ScrollView`, `LazyVStack`, `TabView`, `NavigationStack`, `.sheet`)다. `Canvas`·`drawingGroup`·Metal·UIKit 래핑 없음.
  커스텀은 탭 바, 칩 흐름 배치(`Layout` 프로토콜 `MwFlowLayout`), 하이라이트 텍스트(`AttributedString` 한 덩어리)뿐이다.

- `@Observable` 모델: 뷰는 **읽은 프로퍼티가 바뀔 때만** 다시 그린다(ObservableObject의 "아무 @Published나 바뀌면 전부"와 다름).
- `@ViewModelState`: `_model = State(initialValue: VM(...))`는 부모가 다시 그릴 때마다(토스트·키보드·탭 바 인셋) VM을 새로 만들고 버린다. 만드는 식을 autoclosure로 받아 **처음 읽을 때 한 번만** 실행한다. `AppRouter`·`AppSession.live()`(Keychain·URLSession 조립)도 같다.
- 그림자: 카드 그림자는 행마다 오프스크린 패스를 만든다. 목록은 `LazyVStack`이라 보이는 행만 그린다. 그림자 반경은 Figma 값(blur/2)이다. 스크롤 프레임 드랍이 측정되면 그 카드만 `compositingGroup()`으로 묶는다(지금은 측정 전이라 넣지 않음 — 넣으면 레이어 메모리가 는다).
- 글꼴 크기·여백은 `mwScale`(기기 폭 / 402) 하나로 비례. 레이아웃 재계산은 폭이 바뀔 때만(`onGeometryChange`).

## 실시간·소켓

- **WebSocket·SSE 없음.** v1.0에는 서버가 먼저 알려야 할 이벤트가 없다(해석은 요청-응답 1회, 1~13초).
- v1.2 회의 녹음 해석(최대 20분)은 **3초 폴링 + ETag**(304는 바디 없음)로 받고, 완료는 APNs로도 보낸다(T-B2).
  WebSocket은 양방향이 필요 없고, 블루·그린 전환 때 연결을 옮기는 비용(드레인·재연결)과 백그라운드에서 끊기는 문제가 있다.
  되돌리는 조건: 동시 폴링 세션 > 200 지속 → SSE `GET /recordings/{id}/events`.

## 알림

- v1.0: 원격 푸시 없음(`user_devices`·`notifications` 표가 아직 없다, ADR-0021). 할 일의 `alertEnabled`는 서버에 저장만 한다.
- v1.1~1.2(ADR-0010): APNs 4종(`REVIEW_DUE`·`ACTION_DUE`·`TRANSLATION_DONE`·`LEVEL_UP`), payload `aps` + `mw.deepLink` 하나로 이동. 원문·할 일 문장은 알림 본문에 넣지 않는다(잠금화면·Apple 서버 경유).
  macOS는 `MACOS` 등록(계약 v1.1)과 함께. 워치는 iPhone 알림 포워딩.

## 근거

- E2E(`MwonmalE2E`, 로컬 서버) 통과 2026-10-27: 로그인 → 해석 → 체크 → 용어 → 기록 → 홈 → MY → 동의 → 로그아웃.
- 단위 테스트(iPhone 17 Pro, iOS 26.4) 전부 통과. `ViewModelState` 테스트: 만드는 식 1회, `$model` 바인딩.

## 결과

- 쉬워짐: 의존성이 Apple 패키지뿐. 계약을 바꾸면 컴파일러가 앱 고칠 곳을 알려 준다.
- 어려워짐: 요청 지표(지연·실패율)를 앱에서 보려면 미들웨어 하나를 더 써야 한다(원문 없이 operationID·상태·지연만).

## 되돌리는 조건 (Alamofire 전송으로 바꾸는 때)

- 인증서 고정이 필요해질 때(금융·기업 고객 요구) — 단, URLSession delegate로도 된다. 그보다 많은 이유(예: 요청 지표 + 고정 + 재시도 정책을 한 라이브러리로)가 함께 생길 때만.
- 바꿀 때는 **전송 계층만**(`ClientTransport` 어댑터) 바꾸고, 인터셉터·재시도는 쓰지 않는다(미들웨어가 한 벌만 있게).
