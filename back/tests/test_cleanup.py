"""内部認証・期限境界・再実行・走査位置・二重起動を外部接続なしで検証する。"""

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock

from fastapi.testclient import TestClient
from google.auth.exceptions import TransportError
import pytest

from app import cleanup
from app.config import Settings
from app.errors import ApiError
from app.main import create_app

NOW = datetime(2026, 11, 7, tzinfo=timezone.utc)
ACCOUNT = "cleanup@example.iam.gserviceaccount.com"
AUDIENCE = "https://api.example.test"


class Reference:
    """SDKと同様、トランザクションの全読取を全書込より先に要求する。"""

    def __init__(self, db, path):
        self.db, self.path = db, path
        self.id = path.split("/")[-1]

    def get(self, transaction=None):
        assert transaction is None or not transaction.written
        value = deepcopy(self.db.docs.get(self.path))
        return SimpleNamespace(id=self.id, exists=value is not None, to_dict=lambda: value)


class Transaction:
    def __init__(self, db):
        self.db, self.written = db, False

    def set(self, ref, value):
        self.written = True
        self.db.docs[ref.path] = deepcopy(value)

    def update(self, ref, value):
        self.written = True
        self.db.docs[ref.path].update(deepcopy(value))


class Collection:
    def __init__(self, db, name, cursor=None, limit=None):
        self.db, self.name, self.cursor, self.maximum = db, name, cursor, limit

    def document(self, uid):
        return Reference(self.db, f"{self.name}/{uid}")

    def order_by(self, field):
        assert field == "__name__"
        return self

    def start_after(self, cursor):
        return Collection(self.db, self.name, cursor["__name__"].id)

    def limit(self, value):
        return Collection(self.db, self.name, self.cursor, value)

    def stream(self):
        ids = sorted(path.split("/")[1] for path in self.db.docs if path.startswith(f"{self.name}/"))
        ids = [uid for uid in ids if self.cursor is None or uid > self.cursor]
        return [self.document(uid).get() for uid in ids[:self.maximum]]


@pytest.fixture
def db(monkeypatch):
    store = SimpleNamespace(docs={})
    store.collection = lambda name: Collection(store, name)
    store.transaction = lambda: Transaction(store)
    monkeypatch.setattr(cleanup.firestore, "transactional", lambda function: function)
    monkeypatch.setattr(cleanup, "utc_now", lambda: NOW)
    return store


def seed_idea(db, name, *, days=1, deleted=False):
    db.docs[f"ideas/{name}"] = {"ownerId": "owner", "acceptUntil": NOW + timedelta(days=days),
                              "deletedAt": NOW if deleted else None}


def test_removes_expired_deleted_missing_but_keeps_pin_only_period(db):
    # TL掲載7日を過ぎても30日の受付期限までは、事前ピンを保持する。
    seed_idea(db, "pinned-only", days=20)
    seed_idea(db, "boundary", days=0)
    seed_idea(db, "expired", days=-1)
    seed_idea(db, "deleted", deleted=True)
    db.docs["userPins/viewer"] = {"maxPins": 5,
        "pinnedIdeaIds": ["pinned-only", "boundary", "expired", "deleted", "missing"]}
    result = cleanup.cleanup_pins(db)
    assert result.model_dump() == {"scannedUsers": 1, "updatedUsers": 1, "removedPins": 4, "hasMore": False}
    assert db.docs["userPins/viewer"] == {"maxPins": 5, "pinnedIdeaIds": ["pinned-only"]}
    assert db.docs["ideas/deleted"]["deletedAt"] == NOW
    assert cleanup.cleanup_pins(db).removedPins == 0


def test_empty_collection_and_deleted_pin_document_are_safe(db):
    assert cleanup.cleanup_pins(db).scannedUsers == 0
    cleanup._acquire(db, "worker")
    assert cleanup._clean_pins(db, "missing", "worker") == (0, False)


def test_reloads_current_pins_instead_of_overwriting_with_scan_snapshot(db):
    seed_idea(db, "old", days=-1)
    seed_idea(db, "new")
    db.docs["userPins/viewer"] = {"pinnedIdeaIds": ["old"]}
    cleanup._acquire(db, "worker")
    # 走査後にユーザーが追加・解除した最新状態を、更新トランザクションが読む。
    db.docs["userPins/viewer"]["pinnedIdeaIds"] = ["new"]
    assert cleanup._clean_pins(db, "viewer", "worker") == (0, False)
    assert db.docs["userPins/viewer"]["pinnedIdeaIds"] == ["new"]


def test_batches_resume_after_missing_cursor_document_and_wrap(db, monkeypatch):
    monkeypatch.setattr(cleanup, "BATCH_SIZE", 1)
    for uid in ["a", "b", "c"]:
        db.docs[f"userPins/{uid}"] = {"pinnedIdeaIds": ["missing"]}
    assert cleanup.cleanup_pins(db).hasMore is True
    assert db.docs["cleanupState/pins"]["cursor"] == "a"
    del db.docs["userPins/a"]
    assert cleanup.cleanup_pins(db).hasMore is True
    assert db.docs["cleanupState/pins"]["cursor"] == "b"
    assert cleanup.cleanup_pins(db).hasMore is False
    assert db.docs["cleanupState/pins"]["cursor"] is None
    assert db.docs["userPins/c"]["pinnedIdeaIds"] == []


def test_lease_blocks_overlap_and_old_worker_after_expiry(db, monkeypatch):
    cleanup._acquire(db, "first")
    with pytest.raises(ApiError, match="CLEANUP_BUSY"):
        cleanup.cleanup_pins(db)
    monkeypatch.setattr(cleanup, "utc_now", lambda: NOW + timedelta(minutes=6))
    cleanup._acquire(db, "second")
    with pytest.raises(ApiError, match="CLEANUP_BUSY"):
        cleanup._clean_pins(db, "viewer", "first")
    cleanup._release(db, "first", cursor="wrong", advance=True)
    assert db.docs["cleanupState/pins"]["leaseOwner"] == "second"
    assert "cursor" not in db.docs["cleanupState/pins"]


def test_failure_releases_lease_without_advancing_cursor(db, monkeypatch):
    db.docs["userPins/viewer"] = {"pinnedIdeaIds": ["missing"]}
    monkeypatch.setattr(cleanup, "_clean_pins", Mock(side_effect=RuntimeError("failure")))
    with pytest.raises(RuntimeError):
        cleanup.cleanup_pins(db)
    assert db.docs["cleanupState/pins"]["leaseOwner"] is None
    assert db.docs["cleanupState/pins"].get("cursor") is None


@pytest.fixture
def client(db, monkeypatch):
    monkeypatch.setattr(cleanup, "database", lambda: db)
    verifier = Mock(return_value={"email": ACCOUNT, "email_verified": True})
    monkeypatch.setattr(cleanup.id_token, "verify_oauth2_token", verifier)
    app = create_app(Settings(maintenance_mode=True, cleanup_service_account=ACCOUNT,
                              cleanup_audience=AUDIENCE))
    with TestClient(app) as connection:
        yield connection, verifier


def test_oidc_required_even_during_maintenance(client):
    connection, verifier = client
    assert connection.post("/api/v1/internal/cleanup").status_code == 401
    verifier.assert_not_called()
    response = connection.post("/api/v1/internal/cleanup", headers={"Authorization": "Bearer scheduler-token"})
    assert response.status_code == 200
    assert response.json()["scannedUsers"] == 0
    assert verifier.call_args.args[0] == "scheduler-token"
    assert verifier.call_args.kwargs["audience"] == AUDIENCE


@pytest.mark.parametrize("claims", [
    {"email": "other@example.iam.gserviceaccount.com", "email_verified": True},
    {"email": ACCOUNT, "email_verified": False},
    {"email": ACCOUNT, "email_verified": "true"},
    {},
])
def test_unapproved_identity_is_rejected(client, claims):
    connection, verifier = client
    verifier.return_value = claims
    assert connection.post("/api/v1/internal/cleanup", headers={"Authorization": "Bearer token"}).status_code == 403


@pytest.mark.parametrize("failure,status", [(ValueError("invalid token"), 401), (TransportError("offline"), 503)])
def test_invalid_token_and_certificate_failure(client, failure, status):
    connection, verifier = client
    verifier.side_effect = failure
    response = connection.post("/api/v1/internal/cleanup", headers={"Authorization": "Bearer token"})
    assert response.status_code == status


def test_disabled_cleanup_and_rejects_caller_input(client):
    connection, _ = client
    headers = {"Authorization": "Bearer token"}
    assert connection.post("/api/v1/internal/cleanup", json={"uid": "other"}, headers=headers).status_code == 422
    assert connection.post("/api/v1/internal/cleanup?cursor=other", headers=headers).status_code == 422
    with TestClient(create_app(Settings())) as disabled:
        assert disabled.post("/api/v1/internal/cleanup", headers=headers).status_code == 503


def test_cleanup_settings_pair(monkeypatch):
    monkeypatch.setenv("CLEANUP_SERVICE_ACCOUNT", ACCOUNT)
    monkeypatch.setenv("CLEANUP_AUDIENCE", "")
    with pytest.raises(ValueError, match="must be set together"):
        Settings.from_env()
    monkeypatch.setenv("CLEANUP_AUDIENCE", AUDIENCE)
    settings = Settings.from_env()
    assert settings.cleanup_audience == AUDIENCE
    assert settings.cleanup_service_account == ACCOUNT
