# ADR-0014: 로그인 = Apple code 교환 + id_token JWKS 검증, 우리 토큰 = PyJWT RS256 (v1.0)

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-10-25) |
| 관련 | 이슈 #6, 14번 §4(로그인·토큰), ADR-0013(v1.0 = Apple만), 계약 v1.0 `oauthLogin`·`getMe` |

## 1. 의도
계약 v1.0(`{code, redirectUri}`)을 바꾸지 않고 iPhone 네이티브 Sign in with Apple로 로그인시키고, 서버가 신원을 **Apple 서명으로** 확인한 뒤 우리 토큰을 준다.

## 2. 비용
- 돈 0. 의존성 2개(`pyjwt[crypto]`, `httpx`). Apple Developer 키(.p8) 1개 필요 — 사용자 작업.
- 요청당 Apple 호출 1회(토큰) + JWKS는 1시간 캐시(모르는 kid면 즉시 다시 받음).

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| 앱이 받은 `identityToken`을 서버가 바로 검증 | 계약 v1.0 요청에 필드가 없다(수정 금지). v1.1 후보 |
| `authlib` | OAuth 서버·클라이언트 전부를 담은 큰 라이브러리. 필요한 건 JWT 서명·검증 2개 |
| `python-jose` | 유지보수가 느리고 보안 이슈 이력. PyJWT가 FastAPI 문서 표준 |
| `PyJWKClient`(PyJWT 내장) | 동기 urllib 호출이라 이벤트 루프를 막는다 → httpx 비동기로 직접 캐시 |
| **PyJWT + httpx 직접 (채택)** | — |

## 4. 왜 / 세부 결정
- client_secret = ES256 JWT(iss=팀 ID, sub=번들 ID `kr.mwonmal.app`, aud=Apple, 5분). id_token은 `iss`·`aud`·`exp`·서명을 모두 검사(변조 테스트 + 검증을 끈 돌연변이 테스트로 확인).
- 네이티브 흐름이라 `redirect_uri`는 Apple에 보내지 않는다. 계약상 필수라 받기만 한다.
- id_token에 email이 없으면 `{sub}@apple.invalid`(users.email NOT NULL·unique).
- 닉네임 = `판교뉴비` + 6자리 난수(unique, 충돌 시 재시도). 수정은 v1.1 `updateMe`.
- 같은 email이 다른 제공자로 있으면 409 `EMAIL_ALREADY_REGISTERED`(계약 문구 그대로).
- kakao·google → 400 `INVALID_INPUT(field=provider)`. 계약 enum엔 있으나 v1.0 미구현(#90).
- 우리 토큰: RS256, 헤더 `kid`, 클레임 `sub·role·iat·exp·iss`, 24h. 키는 `MWONMAL_JWT_PRIVATE_KEY`; local·test만 임시 키.
- 제공자 응답 본문은 사용자·로그에 내보내지 않는다(로그엔 상태 코드·예외 타입만).

## 5. 계약과 알려진 차이 (schemathesis, 2026-10-25)
1. `timestamp`가 오프셋 없는 KST → OpenAPI `date-time`(RFC 3339) 형식 위반. 14번 §7이 정한 v1.0 규칙이고 계약 예시도 같다. v1.1 `+09:00`(#75).
2. `OPTIONS /users/me`의 Allow에 PATCH 없음 — `updateMe`는 v1.1.
3. `POST /auth/oauth/google`·`kakao`가 400 — 위 결정.

## 6. 되돌리는 조건
- Apple이 네이티브 code 교환 규칙(redirect_uri 생략)을 바꾸면 그대로 전달하도록 1줄 수정.
- 계약 v1.1에서 `identityToken` 필드가 생기면 토큰 엔드포인트 호출을 생략하는 경로를 추가(교환은 refresh 토큰 용도로만).
