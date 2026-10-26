"""공통 에러 계약: 모든 실패는 Error{code, message, field?, timestamp}.

코드·상태는 계약 v1.0 Error.code 설명과 같다(14번 §7, tests/test_errors.py 가 대조).
"""

from enum import StrEnum

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.time import api_now


class ErrorCode(StrEnum):
    INVALID_INPUT = "INVALID_INPUT"
    RECORDING_CONSENT_REQUIRED = "RECORDING_CONSENT_REQUIRED"
    UNAUTHORIZED = "UNAUTHORIZED"
    OAUTH_CODE_INVALID = "OAUTH_CODE_INVALID"
    FORBIDDEN = "FORBIDDEN"
    NOT_OWNER = "NOT_OWNER"
    USER_NOT_FOUND = "USER_NOT_FOUND"
    PROJECT_NOT_FOUND = "PROJECT_NOT_FOUND"
    MEETING_NOT_FOUND = "MEETING_NOT_FOUND"
    TRANSLATION_NOT_FOUND = "TRANSLATION_NOT_FOUND"
    ACTION_NOT_FOUND = "ACTION_NOT_FOUND"
    RECORDING_NOT_FOUND = "RECORDING_NOT_FOUND"
    TERM_NOT_FOUND = "TERM_NOT_FOUND"
    CARD_NOT_FOUND = "CARD_NOT_FOUND"
    SESSION_NOT_FOUND = "SESSION_NOT_FOUND"
    QUIZ_NOT_FOUND = "QUIZ_NOT_FOUND"
    DEVICE_NOT_FOUND = "DEVICE_NOT_FOUND"
    EMAIL_ALREADY_REGISTERED = "EMAIL_ALREADY_REGISTERED"
    NICKNAME_DUPLICATED = "NICKNAME_DUPLICATED"
    PROJECT_NAME_DUPLICATED = "PROJECT_NAME_DUPLICATED"
    ALREADY_ONBOARDED = "ALREADY_ONBOARDED"
    CARD_DUPLICATED = "CARD_DUPLICATED"
    QUIZ_ALREADY_SUBMITTED = "QUIZ_ALREADY_SUBMITTED"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    NO_TEXT_DETECTED = "NO_TEXT_DETECTED"
    NO_DUE_CARDS = "NO_DUE_CARDS"
    NOT_ENOUGH_TERMS = "NOT_ENOUGH_TERMS"
    GUEST_QUOTA_EXCEEDED = "GUEST_QUOTA_EXCEEDED"
    AI_UNAVAILABLE = "AI_UNAVAILABLE"


STATUS: dict[ErrorCode, int] = {
    ErrorCode.INVALID_INPUT: 400,
    ErrorCode.RECORDING_CONSENT_REQUIRED: 400,
    ErrorCode.UNAUTHORIZED: 401,
    ErrorCode.OAUTH_CODE_INVALID: 401,
    ErrorCode.FORBIDDEN: 403,
    ErrorCode.NOT_OWNER: 403,
    ErrorCode.EMAIL_ALREADY_REGISTERED: 409,
    ErrorCode.NICKNAME_DUPLICATED: 409,
    ErrorCode.PROJECT_NAME_DUPLICATED: 409,
    ErrorCode.ALREADY_ONBOARDED: 409,
    ErrorCode.CARD_DUPLICATED: 409,
    ErrorCode.QUIZ_ALREADY_SUBMITTED: 409,
    ErrorCode.FILE_TOO_LARGE: 413,
    ErrorCode.NO_TEXT_DETECTED: 422,
    ErrorCode.NO_DUE_CARDS: 422,
    ErrorCode.NOT_ENOUGH_TERMS: 422,
    ErrorCode.GUEST_QUOTA_EXCEEDED: 429,
    ErrorCode.AI_UNAVAILABLE: 503,
}


# 계약 v1.0 Error.code 목록에 없는 프레임워크 수준 실패. 그래도 모양은
# Error{code, message, timestamp} 로 맞춘다(클라이언트가 한 가지 모양만 파싱하도록).
# 계약 목록 추가는 v1.1 백로그.
NOT_FOUND = "NOT_FOUND"
METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"
INTERNAL_ERROR = "INTERNAL_ERROR"


def status_of(code: ErrorCode) -> int:
    return STATUS.get(code, 404)  # 나머지 *_NOT_FOUND 는 전부 404


class DomainError(Exception):
    def __init__(self, code: ErrorCode, message: str, field: str | None = None) -> None:
        super().__init__(code.value)
        self.code = code
        self.message = message
        self.field = field


def error_body(code: ErrorCode | str, message: str, field: str | None = None) -> dict[str, str]:
    body = {"code": str(code), "message": message, "timestamp": api_now()}
    if field is not None:
        body["field"] = field
    return body


async def _domain_handler(_: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, DomainError):  # 등록한 타입만 온다
        raise exc
    headers = {"Retry-After": "5"} if exc.code is ErrorCode.AI_UNAVAILABLE else None
    return JSONResponse(
        error_body(exc.code, exc.message, exc.field),
        status_code=status_of(exc.code),
        headers=headers,
    )


async def _validation_handler(_: Request, exc: Exception) -> JSONResponse:
    # Pydantic 오류를 그대로 내보내지 않고 첫 필드만 INVALID_INPUT(field) 로 (14번 §7).
    if not isinstance(exc, RequestValidationError):
        raise exc
    first = exc.errors()[0] if exc.errors() else {}
    loc = [str(p) for p in first.get("loc", ()) if p not in ("body", "query", "path", "header")]
    field = loc[-1] if loc else None
    return JSONResponse(
        error_body(ErrorCode.INVALID_INPUT, "입력값을 확인해 주세요.", field), status_code=400
    )


async def _http_handler(_: Request, exc: Exception) -> JSONResponse:
    # 라우팅 404·405, 본문 한도 413 등 Starlette 가 내는 HTTPException. 기본은 {"detail": ...}.
    if not isinstance(exc, StarletteHTTPException):
        raise exc
    status = exc.status_code
    if status == 404:
        body = error_body(NOT_FOUND, "요청한 주소를 찾을 수 없어요.")
    elif status == 405:
        body = error_body(METHOD_NOT_ALLOWED, "지원하지 않는 요청 방식이에요.")
    elif status == 413:
        body = error_body(ErrorCode.FILE_TOO_LARGE, "요청이 너무 커요.")
    elif status == 400:
        body = error_body(ErrorCode.INVALID_INPUT, "입력값을 확인해 주세요.")
    elif status == 401:
        body = error_body(ErrorCode.UNAUTHORIZED, "로그인이 필요한 기능이에요.")
    else:
        body = error_body(
            INTERNAL_ERROR if status >= 500 else "HTTP_ERROR", "요청을 처리할 수 없어요."
        )
    return JSONResponse(body, status_code=status, headers=exc.headers)


def install(app: FastAPI) -> None:
    app.add_exception_handler(DomainError, _domain_handler)
    app.add_exception_handler(RequestValidationError, _validation_handler)
    app.add_exception_handler(StarletteHTTPException, _http_handler)
    # 처리 안 된 예외는 app.core.http.UnhandledErrorMiddleware 가 Error 봉투 500 으로 바꾼다.
