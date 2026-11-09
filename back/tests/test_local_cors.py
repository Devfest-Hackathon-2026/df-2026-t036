"""開発環境の可変ポート許可が外部ホストや本番へ広がらないことを検証する。"""
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_local_cors_is_opt_in_and_rejects_external_hosts():
    for enabled in (False, True):
        with TestClient(create_app(Settings(cors_allow_localhost=enabled))) as client:
            for origin, expected in (
                ("http://localhost:54321", 200 if enabled else 400),
                ("http://127.0.0.1:54321", 200 if enabled else 400),
                ("http://localhost.attacker.test:54321", 400),
                ("https://external.test", 400),
            ):
                response = client.options("/api/v1/users/register", headers={
                    "Origin": origin, "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "authorization",
                })
                assert response.status_code == expected


def test_local_cors_environment(monkeypatch):
    monkeypatch.setenv("CORS_ALLOW_LOCALHOST", "true")
    assert Settings.from_env().cors_allow_localhost is True