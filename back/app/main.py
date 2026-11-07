"""設定・ミドルウェア・ルーターを組み合わせてAPIを構築する。"""

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings
from .auth import active_user
from .errors import ERROR_RESPONSES, install_error_handlers
from .middleware import RequestContextMiddleware
from .ideas import router as ideas_router
from .artworks import router as artworks_router
from .cleanup import router as cleanup_router
from .vision_demo import router as vision_demo_router
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
        # 外部ホストへは広げず、開発時にだけループバックの可変ポートを許可する。
        allow_origin_regex=(r"http://(localhost|127\.0\.0\.1):[0-9]+"
                            if settings.cors_allow_localhost else None),
        allow_methods=["GET", "POST", "DELETE", "PATCH", "PUT"],
        allow_headers=["Authorization", "Content-Type"],
        expose_headers=["X-Request-Id", "Retry-After"],
    )
    app.include_router(router)
    # 通常APIはルーター単位で認可し、新しいエンドポイントの付け忘れを防ぐ。
    # 更新処理内の再確認は、認可後の停止・権限変更との競合を防ぐため維持する。
    user_access = [Depends(active_user)]
    app.include_router(ideas_router, dependencies=user_access)
    app.include_router(artworks_router, dependencies=user_access)
    app.include_router(cleanup_router)
    app.include_router(vision_demo_router, dependencies=user_access)

    @app.get("/health")
    def health() -> dict[str, str]:
        """メンテナンス時も、外部サービスに接続せず生存確認する。"""
        return {"status": "ok"}

    return app


app = create_app()
