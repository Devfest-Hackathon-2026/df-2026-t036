"""追跡ID・メンテナンス・リクエストログを共通化する。"""

import json
import logging
from time import perf_counter
import uuid

from starlette.requests import Request
from starlette.exceptions import HTTPException

from .config import Settings
from .errors import error_response
from .upload_limits import MAX_DEMO_REQUEST_BYTES

logger = logging.getLogger("uvicorn.error.requests")


class RequestContextMiddleware:
    """ストリーミングを妨げず、応答開始前の想定外例外をJSONへ変換する。"""

    def __init__(self, app, settings: Settings):
        self.app, self.settings = app, settings

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        request = Request(scope)
        # 利用者が指定したヘッダーは採用せず、サーバーで一意なIDを作る。
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        path = scope["path"]
        normal_api = path == "/api/v1" or path.startswith("/api/v1/")
        internal_cleanup = path in {"/api/v1/internal/cleanup", "/api/v1/internal/artwork-cleanup"} and scope["method"] == "POST"
        limited_upload = path.rstrip('/') in {'/api/v1/vision-demo', '/api/v1/artworks'} and scope['method'] == 'POST'
        received_bytes = 0

        async def limited_receive():
            nonlocal received_bytes
            message = await receive()
            if message['type'] == 'http.request':
                received_bytes += len(message.get('body', b''))
                # Content-Lengthが省略・偽装されても実際の受信量で打ち切る。
                if received_bytes > MAX_DEMO_REQUEST_BYTES:
                    raise HTTPException(status_code=413)
            return message

        started, status = False, 500
        begin = perf_counter()

        async def send_response(message):
            nonlocal started, status
            if message["type"] == "http.response.start":
                started, status = True, message["status"]
                headers = [(key, value) for key, value in message.get("headers", [])
                           if key.lower() not in {b"x-request-id"}
                           and not (normal_api and key.lower() == b"cache-control")]
                headers.append((b"x-request-id", request_id.encode("ascii")))
                if normal_api:
                    headers.append((b"cache-control", b"private, no-store"))
                message = {**message, "headers": headers}
            await send(message)

        try:
            if normal_api and not internal_cleanup and self.settings.maintenance_mode:
                response = error_response(request, 503, "MAINTENANCE", "メンテナンス中です。")
                await response(scope, receive, send_response)
            elif limited_upload:
                # 申告容量が超過していれば、本文を読み込まずに拒否する。
                declared_length = request.headers.get('content-length', '')
                # 桁数の大きな値も整数変換せず比較し、異常入力で500にしない。
                digits = declared_length.lstrip('0') or '0'
                ceiling = str(MAX_DEMO_REQUEST_BYTES)
                oversized = len(digits) > len(ceiling) or (len(digits) == len(ceiling) and digits > ceiling)
                if declared_length.isascii() and declared_length.isdecimal() and oversized:
                    response = error_response(request, 413, 'PAYLOAD_TOO_LARGE', '容量の上限を超えています。')
                    await response(scope, receive, send_response)
                else:
                    await self.app(scope, limited_receive, send_response)
            else:
                await self.app(scope, receive, send_response)
        except Exception as exc:
            # 本文や例外メッセージには個人情報が入り得るため、型だけを記録する。
            logger.error("unhandled_failure requestId=%s exceptionType=%s", request_id, type(exc).__name__)
            if started:
                raise
            response = error_response(request, 500, "INTERNAL_ERROR", "処理に失敗しました。")
            await response(scope, receive, send_response)
        finally:
            # 実パス・クエリ・UID・Authorizationはログへ保存しない。
            route = scope.get("route")
            logger.info(json.dumps({
                "event": "api_request", "requestId": request_id,
                "method": scope["method"], "route": getattr(route, "path", "<unmatched>"),
                "status": status, "durationMs": round((perf_counter() - begin) * 1000, 2),
            }))
