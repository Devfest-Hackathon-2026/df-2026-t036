"""受信者限定の画像配信と、取得中の期限・削除変更を検証する。"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock

from fastapi.testclient import TestClient
import pytest

from app import artworks
from app.auth import active_user
from app.config import Settings
from app.main import create_app

NOW = datetime(2026, 11, 8, tzinfo=timezone.utc)


@pytest.fixture
def image_api(monkeypatch):
    records = {
        'users/recipient': {'status': 'active'},
        'artworks/saved': {'recipientId': 'recipient', 'deletedAt': None,
                          'expiresAt': NOW + timedelta(days=1), 'storagePath': 'artworks/saved/image.webp',
                          'storageBucket': 'private'},
    }
    def collection(name):
        def document(key):
            def get():
                data = records.get(f'{name}/{key}')
                return SimpleNamespace(exists=data is not None, to_dict=lambda: data)
            return SimpleNamespace(get=get)
        return SimpleNamespace(document=document)
    monkeypatch.setattr(artworks, 'database', lambda: SimpleNamespace(collection=collection))
    monkeypatch.setattr(artworks, 'utc_now', lambda: NOW)
    cloud = Mock()
    blob = cloud.bucket.return_value.blob.return_value
    blob.download_as_bytes.return_value = b'webp-image'
    monkeypatch.setattr(artworks.storage, 'Client', lambda **kwargs: cloud)
    app = create_app(Settings())
    app.dependency_overrides[active_user] = lambda: {'uid': 'recipient'}
    with TestClient(app) as client:
        yield records, blob, client


def test_recipient_gets_private_image_with_no_cache(image_api):
    records, blob, client = image_api
    response = client.get('/api/v1/artworks/saved/image')
    assert response.status_code == 200
    assert response.content == b'webp-image'
    assert response.headers['content-type'] == 'image/webp'
    assert response.headers['cache-control'] == 'private, no-store'
    assert response.headers['x-content-type-options'] == 'nosniff'
    assert 'storagePath' not in response.text
    blob.download_as_bytes.assert_called_once()


@pytest.mark.parametrize('state', ['other_recipient', 'expired', 'deleted', 'missing', 'suspended'])
def test_invalid_access_never_reads_storage(image_api, state):
    records, blob, client = image_api
    if state == 'other_recipient':
        records['artworks/saved']['recipientId'] = 'someone-else'
    elif state == 'expired':
        records['artworks/saved']['expiresAt'] = NOW
    elif state == 'deleted':
        records['artworks/saved']['deletedAt'] = NOW
    elif state == 'missing':
        del records['artworks/saved']
    else:
        records['users/recipient']['status'] = 'suspended'
    response = client.get('/api/v1/artworks/saved/image')
    assert response.status_code == (403 if state == 'suspended' else 404)
    blob.download_as_bytes.assert_not_called()


def test_deletion_during_download_does_not_deliver_image(image_api):
    records, blob, client = image_api
    def download(**kwargs):
        records['artworks/saved']['deletedAt'] = NOW
        return b'webp-image'
    blob.download_as_bytes.side_effect = download
    assert client.get('/api/v1/artworks/saved/image').status_code == 404
