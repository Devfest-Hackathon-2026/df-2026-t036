"""環境変数を型付き設定へ集約する。変更はAPI再起動で反映する。"""

from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    """プロセス共通の設定。認証情報自体はADCに任せる。"""

    project_id: str | None = None
    cors_origins: tuple[str, ...] = ("http://localhost:3000",)
    maintenance_mode: bool = False
    retry_after_seconds: int = 30

    @classmethod
    def from_env(cls) -> "Settings":
        """誤った設定で起動せず、値を明示的に検証する。"""
        maintenance = os.getenv("MAINTENANCE_MODE", "false").strip().lower()
        if maintenance not in {"true", "false"}:
            raise ValueError("MAINTENANCE_MODE must be true or false")
        retry = int(os.getenv("RETRY_AFTER_SECONDS", "30"))
        if retry < 1:
            raise ValueError("RETRY_AFTER_SECONDS must be positive")
        origins = tuple(dict.fromkeys(
            value.strip() for value in os.getenv(
                "CORS_ORIGINS", "http://localhost:3000"
            ).split(",") if value.strip()
        ))
        if "*" in origins:
            raise ValueError("CORS_ORIGINS must list explicit origins")
        return cls(
            project_id=os.getenv("GOOGLE_CLOUD_PROJECT", "").strip() or None,
            cors_origins=origins,
            maintenance_mode=maintenance == "true",
            retry_after_seconds=retry,
        )
