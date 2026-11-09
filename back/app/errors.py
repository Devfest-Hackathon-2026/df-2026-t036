"""業務・HTTP・外部サービスのエラー応答を統一する。"""

import logging
import uuid

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from firebase_admin.exceptions import FirebaseError
from google.api_core.exceptions import GoogleAPICallError
from google.auth.exceptions import DefaultCredentialsError
from starlette.exceptions import HTTPException

from .config import Settings
from .schemas import ApiModel

logger = logging.getLogger(__name__)


class ApiError(Exception):
    """サービス層からHTTPと共通コードを指定する。"""

    def __init__(self, status: int, code: str, message: str):
        super().__init__(code)
        self.status, self.code, self.message = status, code, message


class ErrorDetail(ApiModel):
    """入力値・トークン・内部例外をエラーへ含めない。"""

    code: str
    message: str
    details: None = None
    requestId: str


class ErrorEnvelope(ApiModel):
    """OpenAPIにも共通エラー形式を公開する。"""

    error: ErrorDetail


def error_response(request: Request, status: int, code: str, message: str,
                   headers: dict | None = None) -> JSONResponse:
    """再試行指示と追跡IDをエラーにも付ける。"""
    request_id = getattr(request.state, "request_id", None) or str(uuid.uuid4())
    settings: Settings = request.app.state.settings
    response_headers = dict(headers or {})
    response_headers["X-Request-Id"] = request_id
    response_headers["Cache-Control"] = "private, no-store"
    if status in {429, 503}:
        response_headers.setdefault("Retry-After", str(settings.retry_after_seconds))
    if status == 401:
        response_headers["WWW-Authenticate"] = "Bearer"
    body = ErrorEnvelope(error=ErrorDetail(code=code, message=message, requestId=request_id))
    return JSONResponse(status_code=status, content=body.model_dump(mode="json"), headers=response_headers)


def install_error_handlers(app: FastAPI) -> None:
    """FastAPI標準の例外もアプリと同じJSON形式にする。"""
    @app.exception_handler(ApiError)
    async def business_error(request: Request, exc: ApiError):
        return error_response(request, exc.status, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, exc: RequestValidationError):
        return error_response(request, 422, "INVALID_INPUT", "入力を確認してください。")

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException):
        codes = {
            401: ("UNAUTHENTICATED", "ログインしてください。"),
            403: ("FORBIDDEN", "この操作は許可されていません。"),
            404: ("RESOURCE_UNAVAILABLE", "参照できません。"),
            405: ("METHOD_NOT_ALLOWED", "この操作は利用できません。"),
            413: ("PAYLOAD_TOO_LARGE", "容量の上限を超えています。"),
            415: ("UNSUPPORTED_MEDIA_TYPE", "対応していない形式です。"),
            422: ("INVALID_INPUT", "入力を確認してください。"),
            429: ("RATE_LIMITED", "時間をおいて再試行してください。"),
        }
        code, message = codes.get(exc.status_code, ("HTTP_ERROR", "処理に失敗しました。"))
        return error_response(request, exc.status_code, code, message, exc.headers)

    @app.exception_handler(GoogleAPICallError)
    @app.exception_handler(FirebaseError)
    @app.exception_handler(DefaultCredentialsError)
    async def upstream_error(request: Request, exc: Exception):
        logger.warning("upstream_failure requestId=%s exceptionType=%s",
                       request.state.request_id, type(exc).__name__)
        return error_response(request, 503, "SERVICE_UNAVAILABLE", "時間をおいて再試行してください。")


# 全APIのOpenAPIに共通形式を適用し、個別ルーターで必要に応じて補足する。
ERROR_RESPONSES = {status: {"model": ErrorEnvelope} for status in (
    401, 403, 404, 409, 413, 415, 422, 429, 500, 503,
)}
