"""環境変数を型付き設定へ集約する。変更はAPI再起動で反映する。"""

from dataclasses import dataclass
import os
from pathlib import Path

from dotenv import dotenv_values


# 作業ディレクトリに依存せず、API直下のローカル設定だけを読み込む。
LOCAL_ENV_FILE = Path(__file__).resolve().parents[1] / '.local.env'


@dataclass(frozen=True)
class Settings:
    """プロセス共通の設定。認証情報自体はADCに任せる。"""

    project_id: str | None = None
    cors_origins: tuple[str, ...] = ("http://localhost:3000",)
    # 明示的に許可した開発環境だけ、Flutterの可変ローカルポートを受け付ける。
    cors_allow_localhost: bool = False
    maintenance_mode: bool = False
    retry_after_seconds: int = 30
    # 内部処理は専用サービスアカウントと明示したOIDC audienceだけに許可する。
    cleanup_service_account: str | None = None
    cleanup_audience: str | None = None
    vision_demo_bucket: str | None = None

    @classmethod
    def from_env(cls) -> "Settings":
        """誤った設定で起動せず、値を明示的に検証する。"""
        # コンテナやCloud Runで指定された環境変数をファイルより優先する。
        values = {**dotenv_values(LOCAL_ENV_FILE, encoding='utf-8-sig'), **os.environ}
        maintenance = values.get("MAINTENANCE_MODE", "false").strip().lower()
        if maintenance not in {"true", "false"}:
            raise ValueError("MAINTENANCE_MODE must be true or false")
        local_cors = values.get('CORS_ALLOW_LOCALHOST', 'false').strip().lower()
        if local_cors not in {'true', 'false'}:
            raise ValueError('CORS_ALLOW_LOCALHOST must be true or false')
        retry = int(values.get("RETRY_AFTER_SECONDS", "30"))
        if retry < 1:
            raise ValueError("RETRY_AFTER_SECONDS must be positive")
        origins = tuple(dict.fromkeys(
            value.strip() for value in values.get(
                "CORS_ORIGINS", "http://localhost:3000"
            ).split(",") if value.strip()
        ))
        if "*" in origins:
            raise ValueError("CORS_ORIGINS must list explicit origins")
        cleanup_account = (values.get("CLEANUP_SERVICE_ACCOUNT") or "").strip() or None
        cleanup_audience = (values.get("CLEANUP_AUDIENCE") or "").strip() or None
        if bool(cleanup_account) != bool(cleanup_audience):
            raise ValueError("CLEANUP_SERVICE_ACCOUNT and CLEANUP_AUDIENCE must be set together")
        return cls(
            project_id=(values.get("GOOGLE_CLOUD_PROJECT") or "").strip() or None,
            cors_origins=origins,
            cors_allow_localhost=local_cors == 'true',
            maintenance_mode=maintenance == "true",
            retry_after_seconds=retry,
            cleanup_service_account=cleanup_account,
            cleanup_audience=cleanup_audience,
            vision_demo_bucket=(values.get("VISION_DEMO_BUCKET") or "").strip() or None,
        )
