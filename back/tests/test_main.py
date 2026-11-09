"""ヘルスチェックとブラウザーからの接続許可を検証する。"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    """起動確認用のレスポンス形式を保証する。"""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_cors():
    """開発用Web画面からのみCORSを許可する。"""
    allowed = client.get("/health", headers={"Origin": "http://localhost:3000"})
    assert allowed.headers["access-control-allow-origin"] == "http://localhost:3000"
    denied = client.get("/health", headers={"Origin": "https://example.com"})
    assert "access-control-allow-origin" not in denied.headers
