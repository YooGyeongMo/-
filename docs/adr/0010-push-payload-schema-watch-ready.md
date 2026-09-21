# ADR-0010: 알림 payload는 `aps` + `mw`(`deepLink`가 유일한 행동 계약) 단일 스키마로, 워치는 v1 앱 없이 포워딩에 의존하고 Domain만 watchOS 데스티네이션에 올린다

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-09-21) |
| 관련 REQ | REQ-04(워치 확장 가능한 알림 설계), REQ-14(알림 본문에 원문 금지), REQ-26 |
| 관련 결정 | 12번 D-19 **개정**(macOS 로컬 알림은 v1.1), 15번 T-D4 갱신("워치 앱 없음, 포워딩 의존, v2"), ADR-0001 개정(Domain watchOS), FD-3, FD-10, MN-1·2·3·4, Backend B-3 **수정**, PO-5, RT-A-03·16·22, RT-B-19, U-10·U-17 |
| 출처 | `council/S0/macOS_iPad.md` §0·MN-1~MN-4, `council/S0/Backend.md` B-3·B-5, `council/S0/PO.md` PO-5, `council/S0/REDTEAM_A.md` RT-A-03·§B #17 |

## 1. 의도
iPhone·iPad(v1.0), Mac(v1.1 `MACOS`), 워치(v2)가 **같은 payload**를 받아 같은 규칙으로 이동한다. 서버 Day 18(빌더)·앱 Day 24(딥링크 파서)·Day 28(APNs)·QA 릴리스 체크 A-24가 **한 파일**을 읽는다 — 1차 세션에서는 같은 파일에 대해 스키마 3개(MN-1 중첩 `mw`, Backend 평면 키, PO 평면 키)가 제출되어 호환되지 않았다(RT-A-03 치명). 원문·받아쓰기·오디오·할 일 문장은 APNs(Apple 서버)와 잠금화면으로도 나가면 안 된다.

## 2. 비용
- 돈: 0(APNs 무료).
- 시간: 스키마 파일 + 픽스처 4개 + 검증 테스트 0.5일(S3-A, 서버 Day 18에 얹음). `Project.swift` Domain 2줄 + 야간 워치 빌드 잡 1개(약 1분). Domain 파일 이동 2개.
- 크기: 4KB 한도 대비 ≈ 600B.
- 앱: v1.0에서 워치 타깃·WatchConnectivity·컴플리케이션 없음(T-D4 유지).

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| 최상위 평면 커스텀 키 `{v, type, notificationId, projectId, meetingId, translationId, actionId, quizId, dueCount}`, `deepLink` 없음(Backend B-3·14번 §5-5·PO §5-2) | 최상위 키는 `aps`와 섞여 네임스페이스 충돌·버전 관리가 어렵고, 워치가 4종 type마다 ID 조합 규칙을 알아야 한다(로직 중복). Backend의 반론("12번 §13이 평면으로 합의")은 §13이 v1.1 백로그 문구일 뿐 계약이 아니므로 성립하지 않음(RT-A-03) |
| ID 없이 `deepLink`만 | iOS §8-2 "조상 ID 보강" 규칙은 payload에 ID가 있으면 API 호출 0회. 워치는 `deepLink`만, iOS는 ID까지 쓰는 두 층이 낫다 |
| `mutable-content` + Notification Service Extension | 타깃 하나 더, 워치는 익스텐션 미지원 경로 |
| `content-available` 사일런트 푸시 + 앱이 로컬 알림 생성 | 앱이 꺼져 있으면 전달 제한, 워치는 더 제한 |
| v1.0 마이그레이션 0001에 `MACOS`·`WATCHOS`를 미리 포함(Backend B-6 ②) | dbml v1.0(`device_platform { IOS, WEB }`, L41~44)과 `dbml2sql diff 0` 검사가 깨짐 = 계약 v1.0 변경(RT-A-16) |
| ACTION_DUE body에 `action_text`(Backend 예시) | AI가 원문에서 추출한 문장은 사실상 원문의 재서술. APNs와 잠금화면(타인 시야)을 거침(RT-B-19). 사용자 결정 U-10: 비노출 |
| 워치 앱(복습 카드 4버튼)을 v1에 | 화면 설계 없음(15번 T-D4), 인증 전제(refresh 토큰)가 v1.1, 5일 이상 |
| **`aps` + 중첩 `mw` + `deepLink` 필수, dbml v1.0 불변, 워치 앱 없음 (채택, MN-1 채택)** | — |

## 4. 왜
Apple 문서(`WKApplication.registerForRemoteNotifications()`, watchOS 7+, 2026-09-19 확인): iOS 컴패니언이 있으면 "워치와 iPhone 양쪽에 보내라. payload가 동일하면 시스템이 중복을 인식해 하나만 표시". 이 조건을 플랫폼 무관하게 만족하려면 payload가 플랫폼을 몰라야 하고, `mw.v`로 버전이 관리되어야 한다. Apple 문서(watchOS "Taking advantage of notification forwarding", PO-5 확인): 서버가 iPhone으로 보낸 원격 알림은 **iPhone이 잠겨 있고 워치를 착용·잠금 해제 상태면 워치로 전달**된다 — 즉 워치 앱 없이도 알림은 손목에 간다. 워치에서 `UNNotificationCategory` 액션("지금 복습/미루기")이 그대로 표시되는지는 **확인 필요**(Day 28 실기기). Backend B-3 §3과 macOS_iPad §0의 `WKApplication` 인용 뉘앙스("종속 앱은 iPhone만 보내도 됨" vs "항상 양쪽에")가 서로 다름 — 둘 중 하나는 인용 오류, **확인 필요**(RT-B §5).

### 4-1. 스키마 v1 — `contracts/push-payload.schema.json`(JSON Schema draft 2020-12) + `contracts/push-examples/{review_due,action_due,translation_done,level_up}.json`
```jsonc
{
  "aps": {
    "alert": { "title": "얼라인, 기억나세요?", "body": "오늘 복습 12장" },  // notifications.title/body. 원문·transcript·할 일 문장 절대 금지
    "badge": 12,
    "sound": "default",
    "category": "REVIEW_DUE",            // == mw.type. iOS·watchOS UNNotificationCategory identifier 동일
    "thread-id": "review",               // review | action | decode | level
    "interruption-level": "active"       // time-sensitive는 엔타이틀먼트 필요(확인 필요) → v1.1
  },
  "mw": {
    "v": 1,                              // 앱은 v > 자기 버전이면 deepLink만 사용
    "type": "REVIEW_DUE",                // REVIEW_DUE | ACTION_DUE | TRANSLATION_DONE | LEVEL_UP
    "deepLink": "mwonmal://review/session",   // 유일한 행동 계약. 워치·Mac·iPhone 동일. 워치는 이것만 파싱
    "notificationId": 9912,              // notifications.id — 열림 dedupe
    "sentAt": "2026-09-21T18:00:00+09:00",
    "review":  { "dueCount": 12 },       // type별 섹션 하나만 존재
    "action":  { "translationId": 0, "actionId": 0, "meetingId": 0, "projectId": 0, "dueAt": "…" },
    "decode":  { "translationId": 0, "recordingId": 0, "meetingId": 0, "projectId": 0 },
    "levelUp": { "quizId": 0, "levelCode": "SETTLER" }
  }
}
```
- `deepLink` 문법(서버 생성, 앱 파싱만): `mwonmal://review/session` · `mwonmal://projects/{p}/meetings/{m}` · `mwonmal://projects/{p}/meetings/{m}/translations/{t}` · `mwonmal://quizzes/{q}/result`. 12번 §8-2의 (Tab, [AppRoute]) 매핑과 1:1. Universal Link로 바꿔도 경로 동일.
- **body 규칙**: 제목·개수·회의 제목까지만. ACTION_DUE body = "할 일 1건 마감 30분 전"(할 일 문장 비노출, 사용자 결정 U-10). 잠금화면 미리보기 표시는 v1.1 옵트인. DECODE_DONE body = "회의 '스프린트 계획' 해석이 끝났어요" 형식, transcript 발췌 금지.
- APNs 헤더: `apns-push-type: alert`, `apns-collapse-id = review-{userId}-{yyyyMMdd}`(REVIEW_DUE 하루 1개), `apns-topic` 플랫폼별(`kr.mwonmal.app`, v1.1 `kr.mwonmal.mac`, v2 워치 접미 **확인 필요**), ACTION_DUE `apns-expiration` = due_at.
- LEVEL_UP은 v1.0에 푸시를 보내지 않는다(14번 §5-4) — 카테고리 4종 등록·픽스처 4개는 유지하되 Day 28 실기기 검증은 3종만(RT-A-22).

### 4-2. 계약·DB
- 계약 v1.1: `DevicePlatform`에 `MACOS`, `WATCHOS` 추가(Backend B-5 #1), `NotificationType` enum 4종(#6), `PushPayload` 스키마 참조(#5, 문서용). `DeviceRequest.pushToken.description` "IOS·MACOS·WATCHOS일 때 APNs 토큰". `notifications.deep_link varchar(255)` 추가(발송 기록 재현용).
- DB: **dbml v1.0 불변, 마이그레이션 0001은 dbml v1.0 그대로.** ENUM 값 append는 마이그레이션 0002(S5)에서. MySQL 8 `ALTER … MODIFY ENUM` 끝 추가가 INSTANT인지 Day 4에 실측 확인(Backend Q9) — 아니어도 0001에 미리 넣지 않는다.
- macOS 로컬 알림(D-19)은 v1.1로 이관(FD-8). Mac은 v1.1 `MACOS` 등록과 함께 APNs로 한 번에.

### 4-3. Domain을 watchOS 데스티네이션에(MN-2, U-17 채택)
`Project.swift` Domain·DomainTests의 `destinations`에 `.appleWatch`, `deploymentTargets`에 `watchOS: "10.0"`(iOS 17 짝). 현재 Domain은 `dependencies: []`이고 12번 §2 "순수 Swift, Foundation만"이므로 그래프 방향 불변(`enforceExplicitDependencies`). 워치가 공유할 타입: `ReviewCard`(Entity 안 쪼갬, D-21), `ReviewRating`, `ReviewSession`, `ReviewAnswer`, **신규 `StreakStatus`**(Entities; A-01·A-09 `StreakBadge`, 위젯 v1.1, 컴플리케이션 v2 공유), **`DeepLink`를 Navigation → Domain/Rules로 이동**(`parse(url:)`, `parse(userInfo:)` 순수 함수; `DeepLink → (Tab,[AppRoute])`는 Navigation에 남음), `NotificationCategory` 상수 4종 + 액션 ID `review.now`·`review.snooze`. SwiftLint: `Domain/`에서 `import (UIKit|AppKit|SwiftUI|AVFoundation|Vision)` 금지. ADR-0001에 한 줄 개정.

### 4-4. MN-3 재작성 — 워치 v2 "복습 카드 넘기기" 최소 계약 (REQ-20 7항목)
1. **의도**: 워치 v2 한 화면(카드 ≤ 5장 넘기기)이 기존 43 ops로 가능한지 지금 확인해, v1.1 백로그에 필요한 것만 올린다.
2. **비용**: 문서만. v1.1 백로그 항목 ≤ 3개(refresh 토큰은 이미 백로그).
3. **대안**: (a) 워치 전용 BFF/API 미리 만들기 — 쓰이지 않는 채 계약 drift 검사만 늘림, 탈락. (b) 워치는 미러링만 영구 — 손목에서 카드 넘김 가치(PO-5 "중, 가설")를 검증할 길이 없음, 탈락.
4. **왜**: `startReviewSession`(`limit` 1~50, L1256)·`submitReviewAnswer`(L1314, `remainingCount`)·`getReviewSession`(L1284)이 있어 화면 자체는 v1.0 계약으로 충분하다. 부족한 것은 인증(웹세션 `oauthLogin`은 워치 불가 → iPhone이 WatchConnectivity로 토큰 전달, JWT 24h라 **refresh 토큰이 워치의 전제**), `WATCHOS` enum(독립형일 때), `getMyStats` 경량화(`retentionSeries`까지 내려와 백그라운드 예산 부담 → `?fields=dueCount,currentStreak` 후보, 낮음).
5. **영향**: Backend B-5 표 #1·#2에 "워치 전제" 표기, 12번 §13. `ASWebAuthenticationSession` watchOS 지원·`swift-openapi-urlsession` watchOS 지원 **확인 필요**(v2).
6. **검증**: v2 착수 전 체크: refresh 토큰 op 존재, `WATCHOS` enum 존재, 3 ops 워치 시뮬레이터 호출 성공.
7. **리스크·되돌림**: `Codable` Entity의 `Date` 파싱(`KSTDateTranscoder`는 MwonmalAPI에 있음) → v2에 MwonmalAPI를 워치에 올리거나 Domain에 파서를 둔다(v2 결정). 되돌림: 워치 v2 포기 시 `.appleWatch` 2줄 삭제로 끝.

### 4-5. MN-4 재작성 — v1에서 미리 할 것 3 / 하지 말 것 3 (REQ-20 7항목)
1. **의도**: REQ-04 "설계만 v1, 구현 v2"의 경계를 코드로 고정한다.
2. **비용**: 할 것 3개 합 0.5일 + 2줄 + CI 1잡. 하지 말 것은 비용 절감(워치 타깃 5일+ 회피).
3. **대안**: (a) 전부 v2로 — `import UIKit` 한 줄이 Domain에 들어가면 분리 비용 폭증, 탈락. (b) 전부 v1로(워치 타깃까지) — 화면 설계·인증 전제 없음, 탈락.
4. **왜 / 목록**: **할 것** ① payload·딥링크·카테고리 문자열을 Domain 상수 + `contracts/push-examples/*.json` 공유 픽스처로 고정(서버 Day 18·앱 Day 24·28이 한 파일). ② Domain `.appleWatch` 데스티네이션 + 야간 워치 빌드 + import 린트("Domain은 Foundation만"을 컴파일러가 지킨다). ③ `StartReviewUseCase(limit:)`·`AnswerCardUseCase`에 `limit` 처음부터 노출, `ReviewFlow` VM이 `elapsedMs`를 `Clock`으로. **하지 말 것** ① 워치 타깃·WatchConnectivity·컴플리케이션(T-D4). ② payload에 텍스트 본문(원문·받아쓰기·해석 결과·할 일 문장). ③ MwonmalUI·Platform·Presentation에 워치 데스티네이션, 워치 전용 BFF/API.
5. **영향**: `Project.swift` Domain 2타깃, `Domain/Entities/StreakStatus`, `Domain/Rules/DeepLink`, `Domain/Services/NotificationCategory`, `Platform/PushRegistrar.swift`, `Navigation/DeepLinkRouter.swift`, `services/api/app/notify/domain/push_payload.py`, 13번 CI 야간 워치 빌드.
6. **검증**: 야간 CI 워치 빌드 초록(`xcodebuild build -scheme Domain -destination 'platform=watchOS Simulator'`). `DomainTests` watchOS 실행은 Swift Testing watchOS **확인 필요**, 불가 시 빌드만. SwiftLint 위반 픽스처 1개.
7. **리스크·되돌림**: 없음(2줄·상수·순수 함수). 되돌림은 §4-4 7항과 동일.

## 5. 영향 파일·문서
- `contracts/push-payload.schema.json`, `contracts/push-examples/*.json`(4), `contracts.yml` 워크플로에 스키마 validate.
- `Project.swift`(Domain·DomainTests), `.swiftlint.yml`(Domain import 금지), 위 §4-5 코드 목록.
- 12번 §8-2("payload 계약은 §13" → 이 스키마), §10 불변식 APNs 열, §13 표 "알림 payload 스키마" 행 → `mw` + `PushPayload`, §2 트리(`StreakStatus`, `Rules/DeepLink`, `NotificationCategory`), §0 그림 Domain 옆 "(iOS·macOS·watchOS)", D-19 "v1.1 이관".
- 14번 §5-5 payload 문구 교체, §11 `PushPayload`·`WATCHOS` 행, §16 `contracts/push-payload.schema.json`.
- 15번 T-D4 갱신. ADR-0001 개정 한 줄. 이슈 #18(Day 18 +0.5), #24(파서 입력 = 스키마), #28(macOS 로컬 알림 제거).
- REQUIREMENTS REQ-04 "설계 완료(ADR-0010)".

## 6. 검증
- 앱: `DeepLink.parse(userInfo:)` 픽스처 4종 + 미지 `v` + `deepLink` 손상 케이스 단위 테스트, `DeepLink → (Tab,[AppRoute])` 전수(§11).
- 서버: 픽스처와 빌더 출력 diff 테스트, payload < 4096B, `alert`·`mw` 전체 문자열에 `sourceText/transcript/result_text/nuance_*/action_text` 포함되지 않음(grep 테스트).
- contracts CI: 픽스처 4개가 스키마로 validate.
- Day 28 실기기: iOS 3종 수신(REVIEW_DUE·ACTION_DUE·TRANSLATION_DONE), 액션 2종 동작, **iPhone 잠금 + 워치 착용 상태에서 포워딩 수신·액션 표시 여부** 기록(확인 안 되면 워치 앱 v2 우선순위 상향 — PO-5).

## 7. 리스크와 되돌리는 조건
- 리스크: `time-sensitive`는 엔타이틀먼트·심사 노트 필요(**확인 필요**) → v1은 `active`. `deepLink` 문법을 바꾸면 워치까지 깨진다 → `v`를 올리고 구버전 경로 6개월 유지. 아이폰+워치 양쪽 발송(v2)이 두 번 울리면 `WATCHOS` 발송을 끄는 설정 한 줄.
- 되돌리는 조건: Universal Link 도입 시 스킴만 교체(경로 동일). 워치 v2 포기 시 Domain `.appleWatch` 2줄 삭제. 포워딩된 알림에 액션이 안 뜨면 v1.1에 워치 앱(알림 인터페이스만, 앱 UI 없음)을 최소로.
