# 알림 payload 예시 (FD-3 / ADR-0010, REQ-04)

`../push-payload.schema.json`(JSON Schema 2020-12)의 예시 4개. 서버 빌더(`notify/domain/push_payload.py`)·앱 `DeepLink.parse` 단위 테스트·워치 v2 가 같은 파일을 읽는다.

| 파일 | `mw.type` | 트리거 | `deepLink` | body 규칙 |
|---|---|---|---|---|
| `review_due.json` | `REVIEW_DUE` | 스케줄러 복습 리마인더 | `mwonmal://review` | 고정 문구 + `dueCount` |
| `action_due.json` | `ACTION_DUE` | 할 일 마감 30분 전 | `mwonmal://actions/{actionId}` | 고정 문구 + 개수. **할 일 문장(actionText) 없음** — 잠금화면 비노출(FD-10) |
| `translation_done.json` | `TRANSLATION_DONE` | 회의 해석 완료 | `mwonmal://translations/{translationId}` | `meetings.title` + 개수만 |
| `level_up.json` | `LEVEL_UP` | 판능시 등급 상승 (v1.0 저장만, 푸시는 워치 v2) | `mwonmal://level` | 등급명만 |

## 구조
- `aps`: `alert{title, body}`, `category`(= type), `thread-id`, `sound`, 선택 `badge`·`interruption-level`·`relevance-score`.
- `mw`: `v: 1`, `type`, `deepLink`, `notificationId`, 그리고 ID 들(`projectId`·`meetingId`·`translationId`·`actionId`·`quizId`·`dueCount`). 문자열은 `type`·`deepLink` 둘뿐.
- **body 에 넣을 수 있는 텍스트**: 고정 문구, 개수, `meetings.title`, 등급명. `sourceText`·`resultText`·`transcript`·`actionText`·`nuance.*` 금지.
- `deepLink` 가 유일한 행동 계약. 쿼리는 ID·숫자만. `notificationId` 는 열림 추적·중복 제거.
- 헤더(서버): `apns-push-type: alert`, `apns-priority: 10`(REVIEW_DUE·LEVEL_UP 은 5), `apns-collapse-id = {type}:{targetId}`, `apns-expiration` = ACTION_DUE 는 due_at, 나머지 24h.
- 워치: v1 앱 없음, iPhone 잠금 + 워치 착용 시 시스템 포워딩. v2 워치 앱은 같은 payload·같은 `DeepLink`.

검증: `cd services/api && uv run pytest -q tests/test_push_payload.py` (스키마 적합·금지 필드·4KB).
계약 v1.1 에서 `components.schemas.PushPayload` 가 이 스키마를 참조하고 `NotificationType` enum 4종·`DevicePlatform`(`MACOS`,`WATCHOS`) 이 추가된다. **v1.0 `openapi.yml`·`db.dbml` 은 불변.**
