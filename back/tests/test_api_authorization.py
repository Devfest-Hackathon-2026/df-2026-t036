"""API全体の認可境界と、他人のデータ操作の拒否を検証する。"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock

from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
import pytest

from app import auth, artworks, ideas
from app.config import Settings
from app.errors import ApiError
from app.main import create_app


def user_routes():
    # 実際のルーターを列挙し、API追加時も未認証アクセスを検証する。
    for route in create_app(Settings()).routes:
        if isinstance(route, APIRoute) and route.path.startswith('/api/v1/') and '/internal/' not in route.path:
            path = route.path.replace('{idea_id}', '00000000-0000-4000-8000-000000000000').replace('{submission_id}', 'other-artwork')
            for method in route.methods:
                yield method, path


@pytest.mark.parametrize('method,path', list(user_routes()))
def test_all_user_apis_require_authentication(method, path):
    with TestClient(create_app(Settings())) as client:
        response = client.request(method, path)
    assert response.status_code == 401
    assert response.json()['error']['code'] == 'UNAUTHENTICATED'


@pytest.mark.parametrize('exists,status,expected', [(False, 'active', 404), (True, 'suspended', 403)])
@pytest.mark.parametrize('method,path', [(m, p) for m, p in user_routes() if p != '/api/v1/users/register'])
def test_unregistered_and_suspended_users_are_denied(monkeypatch, exists, status, expected, method, path):
    app = create_app(Settings())
    app.dependency_overrides[auth.google_uid] = lambda: 'viewer'
    snapshot = SimpleNamespace(exists=exists, to_dict=lambda: {'status': status})
    db = Mock()
    db.collection.return_value.document.return_value.get.return_value = snapshot
    monkeypatch.setattr(auth, 'database', lambda: db)
    with TestClient(app) as client:
        response = client.request(method, path)
    assert response.status_code == expected


@pytest.mark.parametrize('operation', ['delete_idea', 'mark_read', 'like'])
def test_other_users_cannot_modify_resources(monkeypatch, operation):
    # 認証済みでも、所有者・受信者が異なる文書には一切書き込まない。
    documents = {
        'users/viewer': {'status': 'active'},
        'ideas/target': {'ownerId': 'someone-else', 'deletedAt': None},
        'artworks/target': {'recipientId': 'someone-else', 'deletedAt': None,
                            'expiresAt': datetime.now(timezone.utc) + timedelta(days=1)},
    }
    class Collection:
        def __init__(self, name):
            self.name = name

        def document(self, key):
            data = documents.get(f'{self.name}/{key}')
            return SimpleNamespace(get=lambda **kwargs: SimpleNamespace(
                exists=data is not None, to_dict=lambda: data))

    tx = Mock()
    db = SimpleNamespace(collection=Collection, transaction=lambda: tx)
    module = ideas if operation == 'delete_idea' else artworks
    monkeypatch.setattr(module.firestore, 'transactional', lambda function: function)
    function = {'delete_idea': ideas._delete_idea, 'mark_read': artworks._mark_read, 'like': artworks._like}[operation]
    with pytest.raises(ApiError) as error:
        function(db, 'viewer', 'target')
    # 存在情報も漏らさないよう、他人の文書は404として扱う。
    assert error.value.status == 404
    tx.update.assert_not_called()
    tx.set.assert_not_called()
    tx.delete.assert_not_called()
