# 서버 레드팀 (2026-10-26): API·보안 전수 점검

- **범위**: `services/api`(Day 1~2: /health·/ready, Apple 로그인, JWT, /users/me), `infra/`(compose·Caddy·블루그린), `services/api/Dockerfile`, `.github/workflows/*`. 계약(`contracts/*`)은 손대지 않았다.
- **방법**: 공격 시나리오마다 로컬에서 PoC를 실제로 돌렸다(pytest/TestClient, 날 소켓, uvicorn 실프로세스, Docker 안 Caddy 2대). 고친 것은 전부 "수정 전 실패 → 수정 후 통과" 회귀 테스트가 붙어 있다.
- **라운드**: R1 직접 공격 → 수정. R2 독립 리뷰어(별도 에이전트)가 R1 수정을 공격 → 수정. R3 R2 수정 재점검. R2·R3에서 Critical·High 0이 나와 종료했다.

## 라운드별 개수

| 라운드 | Critical | High | Medium | Low |
|---|---|---|---|---|
| R1 | 0 | 4 | 11 | 6 |
| R2 (R1 수정 공격) | 0 | 0 | 3 | 5 |
| R3 (R2 수정 재점검) | 0 | 0 | 0 | 0 |

## 발견 목록

| # | 심각도 | 무엇 | 상태 |
|---|---|---|---|
| H1 | High | `Depends(session)` 기본 scope는 커밋을 **응답을 보낸 뒤에** 한다. 커밋이 실패해도 클라이언트는 200과 토큰을 받는다(계정은 저장 안 됨). PoC: 커밋 실패를 흉내 내면 200 | 고침: `app.core.db.DbSession`(scope="function") |
| H2 | High | 요청 본문 크기 제한이 없다. 인증 없는 `POST /auth/oauth/*`에 수 MB~GB를 보내면 그대로 메모리에 올라가고 Apple로도 넘어간다 | 고침: 앱 1 MiB 한도(413 FILE_TOO_LARGE, chunked 포함) + Caddy `request_body 1MB` |
| H3 | High | Caddy `admin 0.0.0.0:2019`. 같은 Docker 네트워크의 아무 컨테이너나 인증 없이 upstream을 바꿀 수 있다. **재현**: 옆 컨테이너에서 POST 한 번으로 dial을 `attacker.example:80`으로 바꿈 | 고침: `admin localhost:2019`, 전환은 `docker compose exec caddy caddy reload` |
| H4 | High | MySQL REPEATABLE READ에서 IntegrityError 뒤의 평범한 SELECT는 앞서 잡힌 스냅숏을 읽는다. 그래서 "같은 사람 동시 첫 로그인" 처리가 동작하지 않아 500, 이메일 동시 충돌도 409 대신 500 | 고침: `FOR SHARE` 잠금 읽기, 이메일 충돌은 409. **MySQL 실측은 아직** (아래) |
| M1 | Medium | 404/405/500이 `{"detail"}`/text/plain으로 나간다. Starlette 기본 500은 예외 메시지(MySQL 중복키 메시지엔 이메일)를 담은 트레이스백을 로그에 남긴다 | 고침: Error 봉투, 로그엔 타입·파일:줄만 |
| M2 | Medium | DB 오류 메시지·로그에 바인드 값(이메일, 앞으로는 사용자 원문)이 실린다 (ADR-0008) | 고침: `hide_parameters=True` |
| M3 | Medium | JWT 키를 첫 요청 때 읽는다. 키 없는 prod 컨테이너도 /ready를 통과하고 첫 로그인에서 500 | 고침: lifespan `check_keys()`. RSA 2048 미만·빈 kid도 거부 |
| M4 | Medium | 이미지 기본 env가 local이다(fail-open). `--workers 2` + 임시 키면 워커마다 키가 달라 토큰이 무작위로 401(로컬 Compose는 지금도 그랬다) | 고침: 이미지 `MWONMAL_ENV=prod`, `WEB_CONCURRENCY`, 로컬 1 |
| M5 | Medium | blue-green.sh는 호스트에서 `localhost:2019`를 친다. 포트는 publish 안 됐고 JSON 경로 `handle/0`은 headers 핸들러라 어느 쪽이든 전환 불가 | 고침: `MW_UPSTREAM` + `caddy reload`, 상태는 `infra/.upstream` |
| M6 | Medium | Dockerfile `uv sync --frozen \|\| uv sync`: 잠금이 안 맞으면 잠금을 무시하고 새로 푼다. uv 미고정, `chown -R app /srv`(앱이 자기 코드를 고쳐 쓸 수 있음) | 고침 |
| M7 | Medium | 워크플로 3개에 `permissions` 없음, 서드파티 액션이 움직이는 태그 참조 | 고침: 최상위 `contents: read`, 전부 SHA 고정 |
| M8 | Medium | contract job은 `\|\| true`이고 schemathesis 4에 없는 옵션을 써서 **매번 옵션 오류로 끝나고도 초록**(검사 0건) | 고침: 구현된 operation만 돌고 실패하면 빨강. 알려진 차이만 `schemathesis.toml`로 끔 |
| M9 | Medium | 계약상 유효한 `{"code": ""}`를 400으로 거부 (schemathesis가 찾음) | 고침: 401 OAUTH_CODE_INVALID, Apple 호출 없음 |
| M10 | Medium | Caddy에 보안 헤더 없음, minio 고정 자격증명 포트가 LAN에 열림 | 고침 |
| M11 | Medium | 로그인 rate limit 없음(요청당 Apple 호출 1회) | **보류** (아래) |
| R2-M1 | Medium | `/openapi.json`이 요청마다 98KB YAML을 파싱(~70ms CPU). 20 동시 요청이면 /health가 14ms → 1.4s | 고침: 캐시 |
| R2-M2 | Medium | httptools는 헤더 크기 한도가 없다. 100MB 헤더 1개로 RSS 116MB → 5.9GB | 고침: `--http h11`(16KB 넘으면 400) |
| R2-M3 | Medium | compose가 `MWONMAL_ENV: local`을 리터럴로 박아 서버에서도 fail-closed를 덮는다 | 고침: `${MWONMAL_ENV:-local}`, 서버는 `infra/.env` |
| L | Low | Apple 비정상 응답(배열·깨진 JWK)이 500, 모르는 kid마다 JWKS 재요청, JWKS 장애 시 캐시도 버림, werkzeug(dev) 취약점, 413 뒤 연결 유지, 공백 kid, CI `sleep 3` 경합 | 고침 |
| L | Low | 동시 가입에서 닉네임까지 겹치면 500(100만 칸 난수라 사실상 없음), InnoDB 3자 경합 데드락이면 500 | 보류 |

R2 자기 수정 공격에서 나온 것: JWKS 재요청 간격 제한이 **실패한 갱신**도 세는 바람에, 한 번 일시 장애가 나면 60초 동안 로그인이 전부 401이었다 → 성공한 갱신만 세도록 고침.

## 확인했지만 문제 없던 것

- **JWT**: `alg:none`, 공개키를 HMAC 비밀로 쓰는 HS256 혼동, 모르는 kid, exp 없음, 미래 iat, 위조 role(서명 필요) → 전부 401. 삭제된 사용자의 토큰 → /users/me 401.
- **Apple**: iss·aud·exp·서명을 모두 검사한다. id_token은 Apple 응답에서만 오고 공격자가 넣을 수 없다. 이메일이 같으면 계정을 연결하지 않고 409로 막는다(탈취 경로 없음). `{sub}@apple.invalid`는 Apple만 만들 수 있다.
- **API**: SQL은 전부 바인드 파라미터. CORS 미설정(네이티브 앱이라 브라우저 교차 출처 요청을 허용하지 않음). /docs·/redoc 꺼짐.
- **로그**: 우리 로그엔 code·토큰·이메일이 없다(caplog로 확인). `pip-audit`(prod 의존성) 0건.
- **CI**: `pull_request_target` 없음, `${{ github.event.* }}` 주입 없음. self-hosted는 fork PR에서 안 돈다.
- **schemathesis**: oauthLogin·getMe 344 케이스 통과(알려진 차이 3개만 끔).

## 보류와 이유 (v1.1·다음 Day 백로그)

1. **로그인 rate limit**: 계약 v1.0엔 429가 `GUEST_QUOTA_EXCEEDED`뿐이라, 새 코드를 쓰려면 계약 변경이 필요하다. 워커별 메모리 카운터는 블루그린·다중 워커에서 정확하지 않다. Redis 기반으로 하고 계약 v1.1에 `RATE_LIMITED`를 넣는 것을 제안한다. 지금은 본문 1MB 한도와 Apple 쪽 제한이 1차 방어다.
2. **계약 v1.1 노트**: Error.code 목록에 `NOT_FOUND`·`METHOD_NOT_ALLOWED`·`INTERNAL_ERROR`(·`HTTP_ERROR`)를 추가한다. 타임스탬프 `+09:00`(#75). `OAuthLoginRequest`에 `identityToken`·`nonce`(재전송 방지) 필드.
3. **토큰 폐기 없음**: 24h 동안 role이 갱신되지 않고, 삭제된 계정도 /users/me 밖의 엔드포인트에선 유효하다. 새 엔드포인트는 계정 존재를 직접 확인해야 한다. refresh 토큰·폐기 목록은 v1.1.
4. **prod 인프라**: S5 Day 26 전이다. TLS는 앞단(Cloudflare)을 가정한다. Flexible SSL이면 원본 구간이 평문이니 Full(strict)로 해야 한다. compose의 DB 비밀번호 `local`, 이미지 digest 고정, `checkout persist-credentials: false`, X-Request-Id 업스트림 전달도 그때 한다.
5. **Caddy 재시작**: `docker compose restart caddy`는 생성 시점 env(=예전 색)로 돌아간다. 다시 띄울 땐 `up -d caddy`를 쓴다(스크립트 주석). `.upstream`이 실제 활성 색과 어긋나는 경우(수동 배포) 교차 확인은 아직 없다.

## 검증하지 못한 것 (솔직하게)

- **Docker Desktop이 레드팀 중간에 응답 불능이 됐다.** 그래서 다음은 로컬에서 못 했다. 이 브랜치 PR의 CI(server.yml: MySQL 서비스·이미지 빌드·Trivy)가 첫 실측이다.
  - H4 잠금 읽기의 **실제 MySQL 경합 테스트**(`tests/test_account_repository.py::test_real_race_on_mysql`): 코드와 테스트는 작성했지만 MySQL에서 돌려 보지 못했다. 수정 전 코드로 이 테스트가 실패하는 것도 MySQL에서 확인하지 못했다.
  - Docker 이미지 빌드(uv 0.12.13 고정, root 소유 /srv에서 비root 실행, HEALTHCHECK), Trivy 스캔
  - 수정된 Caddyfile·blue-green.sh를 실제 Caddy로 실행(H3 공격 자체는 수정 전 설정으로 Docker에서 재현했다. 수정 후 동작은 Caddy 소스 기준 추론과 리뷰어 확인뿐)
  - gitleaks 로컬 스캔(CI secrets job에 맡김. 테스트 키는 전부 실행 중에 만든다)
- 수정 전 MySQL 마이그레이션 왕복(up/down)과 기존 MySQL 테스트는 R1 초반에 통과를 확인했다(81 passed, skip 0).

## 배운 점

- "트랜잭션 = 요청 하나"라고 써 둔 의존성이 실제로는 응답 뒤에 커밋하고 있었다. 프레임워크 기본값이 바뀌는 지점(yield 의존성 scope)은 **실패를 주입하는 테스트**로만 드러난다.
- "CI에 계약 검사가 있다"는 말이 사실이 아니었다(`|| true` + 없는 옵션). 2026-10-25 gitleaks 건과 같은 계열이다. 게이트는 **일부러 실패시켜 빨강이 뜨는지**로 확인한다.
- 같은 Docker 네트워크는 신뢰 경계가 아니다. 관리 포트는 루프백에만 연다.
