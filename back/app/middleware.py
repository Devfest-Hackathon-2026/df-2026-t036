"""追跡ID・メンテナンス・リクエストログを共通化する。"""

import json
import logging
from time import perf_counter
import uuid

from starlette.requests import Request

from .config import Settings
from .errors import error_response

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
        internal_cleanup = path == "/api/v1/internal/cleanup" and scope["method"] == "POST"
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
