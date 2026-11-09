"""認証境界と、登録の再送時に既存データを保持することを検証する。"""

from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from fastapi.security import HTTPAuthorizationCredentials

from app.main import app
from app import users, auth as authentication


@pytest.fixture
def store(monkeypatch):
    """外部接続を使わず、登録が書き込む文書と既存値を検査する。"""
    documents = {}
    transaction = Mock()

    def create(reference, value):
        assert reference.path not in documents
        documents[reference.path] = deepcopy(value)

    transaction.create.side_effect = create

    class Reference:
        def __init__(self, path):
            self.path = path

        def get(self, **kwargs):
            data = documents.get(self.path)
            return SimpleNamespace(exists=data is not None, to_dict=lambda: deepcopy(data))

    db = SimpleNamespace(
        collection=lambda name: SimpleNamespace(document=lambda uid: Reference(f"{name}/{uid}")),
        transaction=lambda: transaction,
    )
    monkeypatch.setattr(users.firestore, "transactional", lambda function: function)
    monkeypatch.setattr(users, "database", lambda: db)
    monkeypatch.setattr(authentication, "database", lambda: db)
    app.dependency_overrides[authentication.google_uid] = lambda: "google-user"
    yield documents, db
    app.dependency_overrides.clear()


def test_register_and_retry_preserves_all_documents(store):
    """3文書の作成後、再送でも名前・累計・枠・ピンを消さない。"""
    documents, _ = store
    with TestClient(app) as client:
        first = client.post("/api/v1/users/register")
        assert first.status_code == 201
        assert set(documents) == {"users/google-user", "userSlots/google-user", "userPins/google-user"}
        assert documents["userSlots/google-user"] == {
            "maxSlots": 5, "slots": {f"slot_{i}": {} for i in range(5)},
        }
        assert documents["userPins/google-user"] == {"maxPins": 5, "pinnedIdeaIds": []}
        documents["users/google-user"]["drawnCount"] = 7
        documents["userPins/google-user"]["pinnedIdeaIds"] = ["idea-1"]
        before = deepcopy(documents)
        retry = client.post("/api/v1/users/register")
        assert retry.status_code == 200
        assert retry.json()["nickname"] == first.json()["nickname"]
        assert retry.json()["drawnCount"] == 7
        assert documents == before
        me = client.get("/api/v1/me")
        assert me.json() == retry.json()
        assert me.headers["cache-control"] == "private, no-store"
        assert set(me.json()) == {
            "uid",
            "nickname",
            "status",
            "ideaCount",
            "drawnCount",
            "likesReceived",
            "bio",
            "socialLinks",
        }
        assert me.json()["bio"] == ""
        assert me.json()["socialLinks"] == []


def test_suspended_user_is_not_reactivated(store):
    """再登録でも停止状態とカウンターを維持し、アクセスを拒否する。"""
    documents, _ = store
    with TestClient(app) as client:
        client.post("/api/v1/users/register")
        documents["users/google-user"]["status"] = "suspended"
        before = deepcopy(documents)
        for path, method in (("/api/v1/users/register", client.post), ("/api/v1/me", client.get)):
            assert method(path).status_code == 403
        assert documents == before


def test_missing_user_and_body_rejection(store):
    """登録前の本人情報と、本文によるUID指定を拒否する。"""
    documents, _ = store
    with TestClient(app) as client:
        assert client.get("/api/v1/me").status_code == 404
        assert client.post("/api/v1/users/register", json={"uid": "other"}).status_code == 422
        assert documents == {}


def test_missing_token():
    """認証がなければFirebaseへ接続せず401を返す。"""
    with TestClient(app) as client:
        response = client.post("/api/v1/users/register")
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "UNAUTHENTICATED"
        assert response.json()["error"]["requestId"]


@pytest.mark.parametrize("provider", ["password", "anonymous", None])
def test_non_google_provider_is_rejected(monkeypatch, provider):
    """他のプロバイダーのトークンから登録させない。"""
    monkeypatch.setattr(authentication, "firebase_app", lambda: SimpleNamespace(project_id="test"))
    monkeypatch.setattr(authentication.auth, "verify_id_token", lambda *a, **kw: {
        "uid": "user", "firebase": {"sign_in_provider": provider},
    })
    with pytest.raises(users.ApiError) as error:
        authentication.google_uid(HTTPAuthorizationCredentials(scheme="Bearer", credentials="token"))
    assert error.value.status == 401


def test_verified_uid_is_used(monkeypatch):
    """失効確認を有効にして検証したUIDだけを返す。"""
    firebase_app = SimpleNamespace(project_id="test")
    monkeypatch.setattr(authentication, "firebase_app", lambda: firebase_app)
    verify = Mock(return_value={"uid": "verified", "firebase": {"sign_in_provider": "google.com"}})
    monkeypatch.setattr(authentication.auth, "verify_id_token", verify)
    assert authentication.google_uid(HTTPAuthorizationCredentials(scheme="Bearer", credentials="token")) == "verified"
    verify.assert_called_once_with("token", app=firebase_app, check_revoked=True)


def test_invalid_token(monkeypatch):
    """署名不正や期限切れを認証失敗として扱う。"""
    monkeypatch.setattr(authentication, "firebase_app", lambda: SimpleNamespace(project_id="test"))
    monkeypatch.setattr(authentication.auth, "verify_id_token", Mock(side_effect=authentication.auth.InvalidIdTokenError("invalid")))
    with TestClient(app) as client:
        assert client.get("/api/v1/me", headers={"Authorization": "Bearer invalid"}).status_code == 401


def test_maintenance_does_not_stop_health(monkeypatch):
    """メンテナンスでは登録を止め、監視用healthを維持する。"""
    from app.main import create_app
    from app.config import Settings
    with TestClient(create_app(Settings(maintenance_mode=True))) as client:
        response = client.post("/api/v1/users/register")
        assert response.status_code == 503
        assert response.json()["error"]["code"] == "MAINTENANCE"
        assert response.headers["retry-after"] == "30"
        assert client.get("/health").status_code == 200


def test_registration_cors_preflight():
    """ブラウザーからBearer付きPOSTを実行できる。"""
    with TestClient(app) as client:
        response = client.options("/api/v1/users/register", headers={
            "Origin": "http://localhost:3000", "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization",
        })
        assert response.status_code == 200


def test_upstream_failure_is_retryable(monkeypatch):
    """証明書取得の失敗を、ユーザーの認証不正と区別する。"""
    monkeypatch.setattr(authentication, "firebase_app", lambda: SimpleNamespace(project_id="test"))
    monkeypatch.setattr(authentication.auth, "verify_id_token", Mock(side_effect=authentication.auth.CertificateFetchError("offline", RuntimeError("offline"))))
    with TestClient(app) as client:
        response = client.get("/api/v1/me", headers={"Authorization": "Bearer token"})
        assert response.status_code == 503
        assert response.headers["retry-after"] == "30"
