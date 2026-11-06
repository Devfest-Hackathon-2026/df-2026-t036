"""機能APIに依存せず、共通契約・境界値・障害時の応答を検証する。"""

from datetime import datetime, timedelta, timezone
import json
import logging
from typing import Annotated
from uuid import UUID

from fastapi import HTTPException, Query
from fastapi.testclient import TestClient
from google.api_core.exceptions import ServiceUnavailable
from pydantic import Field, ValidationError
import pytest

from app.clock import as_utc, is_unexpired, rfc3339, utc_now
from app.config import Settings
from app.errors import ApiError
from app.main import create_app
from app.schemas import InputModel, Page, PageQuery


class ExampleInput(InputModel):
    """テスト用の入力。業務APIとしては公開しない。"""

    title: str = Field(min_length=1, max_length=4)
    count: int
    tags: list[str] = Field(default_factory=list)


@pytest.fixture
def application():
    """失敗経路を意図的に起こせる独立したアプリを作る。"""
    app = create_app(Settings())

    @app.post("/api/v1/test-input")
    def input_route(body: ExampleInput):
        return body

    @app.get("/api/v1/test-page", response_model=Page[str])
    def page_route(query: Annotated[PageQuery, Query()]):
        return Page(items=[str(query.limit)], nextCursor=query.cursor, serverTime=utc_now())

    @app.get("/api/v1/test-failure/{kind}")
    def failure_route(kind: str):
        if kind == "upstream":
            raise ServiceUnavailable("secret-upstream-value")
        if kind == "business":
            raise ApiError(409, "CONFLICT", "競合しました。")
        if kind == "rate":
            raise HTTPException(429, detail="secret", headers={"Retry-After": "90"})
        raise RuntimeError("secret-internal-value")

    return app


@pytest.mark.parametrize("path,status,code", [
    ("/api/v1/missing", 404, "RESOURCE_UNAVAILABLE"),
    ("/api/v1/test-failure/upstream", 503, "SERVICE_UNAVAILABLE"),
    ("/api/v1/test-failure/business", 409, "CONFLICT"),
    ("/api/v1/test-failure/unexpected", 500, "INTERNAL_ERROR"),
    ("/api/v1/test-failure/rate", 429, "RATE_LIMITED"),
])
def test_error_contract_and_cors(application, path, status, code):
    """全失敗経路で追跡・CORS・非キャッシュを維持し、内部情報を隠す。"""
    with TestClient(application) as client:
        response = client.get(path, headers={"Origin": "http://localhost:3000"})
    assert response.status_code == status
    error = response.json()["error"]
    assert error["code"] == code
    assert set(error) == {"code", "message", "details", "requestId"}
    assert error["details"] is None
    assert str(UUID(error["requestId"])) == response.headers["x-request-id"]
    assert response.headers["cache-control"] == "private, no-store"
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert "secret" not in response.text
    if status == 503:
        assert response.headers["retry-after"] == "30"
    if status == 429:
        assert response.headers["retry-after"] == "90"


def test_wrong_method_and_auth_challenge(application):
    """標準405も共通化し、401にはBearerの認証要求を付ける。"""
    with TestClient(application) as client:
        method = client.post("/api/v1/me")
        assert method.status_code == 405
        assert method.json()["error"]["code"] == "METHOD_NOT_ALLOWED"
        assert method.headers["allow"] == "GET"
        auth = client.get("/api/v1/me")
        assert auth.status_code == 401
        assert auth.headers["www-authenticate"] == "Bearer"


def test_request_logs_do_not_include_user_data(application, caplog):
    """テンプレートパスとサーバー生成IDのみを記録する。"""
    caplog.set_level(logging.INFO, logger="uvicorn.error.requests")
    with TestClient(application) as client:
        first = client.get("/api/v1/test-failure/private-id?token=private-query", headers={
            "Authorization": "Bearer private-token", "X-Request-Id": "client-controlled",
        })
        second = client.get("/health")
    entries = [json.loads(record.message) for record in caplog.records if record.message.startswith('{"event"')]
    assert entries[0]["route"] == "/api/v1/test-failure/{kind}"
    assert entries[0]["status"] == 500
    assert entries[0]["requestId"] == first.headers["x-request-id"]
    assert first.headers["x-request-id"] != second.headers["x-request-id"]
    assert entries[0]["durationMs"] >= 0
    for private in ("private-id", "private-query", "private-token", "client-controlled", "secret-internal-value"):
        assert private not in caplog.text


def test_maintenance_exempts_only_cleanup_and_health():
    """メンテナンス中も内部処理への経路を維持し、類似パスは除外しない。"""
    app = create_app(Settings(maintenance_mode=True, retry_after_seconds=12))

    @app.post("/api/v1/internal/cleanup")
    def cleanup():
        # 実際のcleanup実装では別途内部認証を必須にする。
        return {"test": "reachable"}

    with TestClient(app) as client:
        assert client.get("/health").status_code == 200
        assert client.post("/api/v1/internal/cleanup").status_code == 200
        for path in ("/api/v1/me", "/api/v1/internal/cleanup/other", "/api/v1/internal/cleanup"):
            response = client.get(path, headers={"Origin": "http://localhost:3000"})
            assert response.status_code == 503
            assert response.headers["retry-after"] == "12"
            assert response.headers["access-control-allow-origin"] == "http://localhost:3000"


@pytest.mark.parametrize("body", [
    {"title": "  ", "count": 1},
    {"title": "ok", "count": "1"},
    {"title": "ok", "count": True},
    {"title": 123, "count": 1},
    {"title": "ok", "count": 1, "secret": "private-value"},
])
def test_strict_input_rejection(application, body):
    """未知フィールド・型変換・空白だけの必須入力を拒否する。"""
    with TestClient(application) as client:
        response = client.post("/api/v1/test-input", json=body)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_INPUT"
    assert "private-value" not in response.text


def test_trim_before_unicode_length_check(application):
    """前後空白とタグを整形し、絵文字をコードポイントで数える。"""
    with TestClient(application) as client:
        response = client.post("/api/v1/test-input", json={
            "title": "  絵😀  ", "count": 1, "tags": [" 空 ", " 海 "],
        })
    assert response.status_code == 200
    assert response.json() == {"title": "絵😀", "count": 1, "tags": ["空", "海"]}


@pytest.mark.parametrize("query", ["limit=0", "limit=51", "limit=true", "cursor=", "unexpected=1"])
def test_page_query_rejects_invalid_values(application, query):
    """ページ数と未知パラメーターをAPI境界で検証する。"""
    with TestClient(application) as client:
        assert client.get(f"/api/v1/test-page?{query}").status_code == 422


def test_page_contract(application):
    """既定件数とUTCのserverTimeを返す。"""
    with TestClient(application) as client:
        response = client.get("/api/v1/test-page")
        assert response.status_code == 200
        assert response.json()["items"] == ["20"]
        assert response.json()["nextCursor"] is None
        assert response.json()["serverTime"].endswith("Z")
        assert client.get("/api/v1/test-page?limit=50&cursor=opaque").json()["nextCursor"] == "opaque"


def test_utc_and_expiration_boundaries():
    """UTC変換と、期限直前・一致・直後の判定を固定する。"""
    deadline = datetime(2026, 11, 6, tzinfo=timezone.utc)
    assert is_unexpired(deadline, deadline - timedelta(microseconds=1))
    assert not is_unexpired(deadline, deadline)
    assert not is_unexpired(deadline, deadline + timedelta(microseconds=1))
    local = deadline.astimezone(timezone(timedelta(hours=9)))
    assert as_utc(local) == deadline
    assert rfc3339(local) == "2026-11-06T00:00:00Z"
    assert utc_now().tzinfo == timezone.utc
    with pytest.raises(ValueError):
        as_utc(datetime(2026, 11, 6))
    with pytest.raises(ValidationError):
        Page[str](items=[], nextCursor=None, serverTime=datetime(2026, 11, 6))


def test_settings_validate_environment(monkeypatch):
    """設定の重複除去と、誤記したメンテナンス値の拒否を確認する。"""
    monkeypatch.setenv("CORS_ORIGINS", "http://localhost:3000, http://localhost:3000")
    assert Settings.from_env().cors_origins == ("http://localhost:3000",)
    monkeypatch.setenv("MAINTENANCE_MODE", "treu")
    with pytest.raises(ValueError):
        Settings.from_env()


def test_openapi_publishes_error_contract(application):
    """API利用者が共通エラーを仕様画面で確認できる。"""
    operation = application.openapi()["paths"]["/api/v1/me"]["get"]
    schema = operation["responses"]["422"]["content"]["application/json"]["schema"]
    assert schema["$ref"].endswith("/ErrorEnvelope")
