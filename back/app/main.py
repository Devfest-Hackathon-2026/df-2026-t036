"""設定・ミドルウェア・ルーターを組み合わせてAPIを構築する。"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings
from .errors import ERROR_RESPONSES, install_error_handlers
from .middleware import RequestContextMiddleware
from .users import router


def create_app(settings: Settings | None = None) -> FastAPI:
    """テストでは設定を差し替え、本番では起動時の環境変数を固定する。"""
    settings = settings or Settings.from_env()
    app = FastAPI(title="Illustration Exchange API", responses=ERROR_RESPONSES)
    app.state.settings = settings
    install_error_handlers(app)
    app.add_middleware(RequestContextMiddleware, settings=settings)
    # 共通ミドルウェアの500・503応答にもCORSヘッダーを付ける。
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_methods=["GET", "POST", "DELETE", "PATCH", "PUT"],
        allow_headers=["Authorization", "Content-Type"],
        expose_headers=["X-Request-Id", "Retry-After"],
    )
    app.include_router(router)

    @app.get("/health")
    def health() -> dict[str, str]:
        """メンテナンス時も、外部サービスに接続せず生存確認する。"""
        return {"status": "ok"}

    return app


app = create_app()
