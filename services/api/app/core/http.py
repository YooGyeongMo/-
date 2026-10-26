"""HTTP 공통 방어: 요청 본문 크기 제한 + API 응답 보안 헤더 (순수 ASGI 미들웨어).

- 본문 제한이 없으면 인증 없는 POST /auth/oauth/* 에 수백 MB 를 보내 워커 메모리를 터뜨릴 수 있다.
  Content-Length 가 크면 읽기 전에 413, 길이 없이(chunked) 오면 읽는 도중 넘는 순간 413.
  업로드 라우트(이미지 5MB·녹음 200MB)가 생기면 `limits` 에 경로 접두사로 더 큰 한도를 준다.
- 응답 헤더: 토큰·개인정보 응답이 캐시에 남지 않게 no-store, MIME 스니핑 금지.
"""

import json
import logging
import traceback
from collections.abc import Mapping

from starlette.exceptions import HTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.errors import INTERNAL_ERROR, ErrorCode, error_body

log = logging.getLogger(__name__)

DEFAULT_MAX_BODY = 1024 * 1024  # 1 MiB: JSON API 는 이보다 훨씬 작다

SECURITY_HEADERS: tuple[tuple[bytes, bytes], ...] = (
    (b"x-content-type-options", b"nosniff"),
    (b"cache-control", b"no-store"),
    (b"referrer-policy", b"no-referrer"),
)


class BodyLimitMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        max_body: int = DEFAULT_MAX_BODY,
        limits: Mapping[str, int] | None = None,
    ) -> None:
        self.app = app
        self.max_body = max_body
        self.limits = dict(limits or {})

    def _limit_for(self, path: str) -> int:
        for prefix, limit in self.limits.items():
            if path.startswith(prefix):
                return limit
        return self.max_body

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        limit = self._limit_for(scope["path"])
        for name, value in scope["headers"]:
            if name == b"content-length":
                try:
                    declared = int(value)
                except ValueError:
                    declared = -1
                if declared < 0 or declared > limit:
                    await _send_too_large(send)
                    return

        received = 0

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    # FastAPI 가 본문 파싱 오류를 400 으로 바꾸지 않도록 HTTPException 으로 올린다.
                    raise HTTPException(status_code=413)
            return message

        await self.app(scope, limited_receive, send)


async def _send_error(send: Send, status: int, body_obj: dict[str, str]) -> None:
    body = json.dumps(body_obj, ensure_ascii=False).encode()
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(body)).encode()),
                (b"connection", b"close"),
                *SECURITY_HEADERS,
            ],
        }
    )
    await send({"type": "http.response.body", "body": body})


async def _send_too_large(send: Send) -> None:
    await _send_error(send, 413, error_body(ErrorCode.FILE_TOO_LARGE, "요청이 너무 커요."))


class UnhandledErrorMiddleware:
    """처리 안 된 예외 → Error 봉투 500. 예외 메시지는 응답에도 로그에도 싣지 않는다.

    DB 오류 메시지엔 값이 들어간다(MySQL: "Duplicate entry 'a@b.com' for key ...").
    Starlette 기본 처리는 전체 트레이스백(메시지 포함)을 로그에 남기므로 여기서 먼저 잡고,
    로그엔 예외 타입과 발생 위치(파일:줄)만 남긴다 (ADR-0008 / REQ-14).
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started = False

        async def tracking_send(message: Message) -> None:
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, receive, tracking_send)
        except Exception as exc:  # noqa: BLE001 - 마지막 방어선
            frames = traceback.extract_tb(exc.__traceback__)
            where = [f"{f.filename.rsplit('/', 1)[-1]}:{f.lineno}" for f in frames[-5:]]
            route = getattr(scope.get("route"), "path", "-")  # 템플릿 경로(값 없음)
            log.error(
                "unhandled_error type=%s at=%s route=%s",
                type(exc).__name__,
                ",".join(where),
                route,
            )
            if not started:
                await _send_error(
                    send, 500, error_body(INTERNAL_ERROR, "잠시 후 다시 시도해 주세요.")
                )


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                present = {k.lower() for k, _ in message.get("headers", [])}
                extra = [(k, v) for k, v in SECURITY_HEADERS if k not in present]
                message = {**message, "headers": [*message.get("headers", []), *extra]}
            await send(message)

        await self.app(scope, receive, send_with_headers)
