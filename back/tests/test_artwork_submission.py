"""投稿確定の境界・二重送信・途中障害を外部接続なしで検証する。"""

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from io import BytesIO
from threading import RLock
from types import SimpleNamespace
from unittest.mock import Mock

from PIL import Image
import pytest

from app import artwork_submission as service
from app.config import Settings
from app.errors import ApiError

NOW = datetime(2026, 11, 8, tzinfo=timezone.utc)
IDEA = '00000000-0000-4000-8000-000000000000'


class Reference:
    def __init__(self, db, path):
        self.db, self.path = db, path
        self.id = path.split('/')[-1]

    def get(self, transaction=None):
        assert transaction is None or not transaction.writes
        data = deepcopy(self.db.docs.get(self.path))
        return SimpleNamespace(exists=data is not None, to_dict=lambda: data)

    def collection(self, name):
        return Collection(self.db, f'{self.path}/{name}')

    def delete(self):
        self.db.docs.pop(self.path, None)

    def set(self, data):
        self.db.docs[self.path] = deepcopy(data)


class Collection:
    def __init__(self, db, path):
        self.db, self.path = db, path

    def document(self, name):
        return Reference(self.db, f'{self.path}/{name}')


class Transaction:
    def __init__(self, db):
        self.db, self.writes = db, []

    def set(self, ref, data):
        self.writes.append(('set', ref.path, deepcopy(data)))

    def update(self, ref, data):
        self.writes.append(('update', ref.path, deepcopy(data)))

    def delete(self, ref):
        self.writes.append(('delete', ref.path, None))


@pytest.fixture
def environment(monkeypatch):
    db = SimpleNamespace(docs={}, lock=RLock())
    db.collection = lambda name: Collection(db, name)
    db.transaction = lambda: Transaction(db)

    def transactional(function):
        def apply(tx):
            # 読取後の書込と原子性を再現し、並行する投稿を直列化する。
            with db.lock:
                result = function(tx)
                for op, path, data in tx.writes:
                    if op == 'delete':
                        db.docs.pop(path, None)
                    elif op == 'set':
                        db.docs[path] = data
                    else:
                        for key, value in data.items():
                            if isinstance(value, service.firestore.Increment):
                                value = db.docs[path].get(key, 0) + value.value
                            db.docs[path][key] = value
                return result
        return apply

    monkeypatch.setattr(service.firestore, 'transactional', transactional)
    monkeypatch.setattr(service, 'utc_now', lambda: NOW)
    db.docs['users/artist'] = {'status': 'active', 'drawnCount': 0}
    db.docs['users/owner'] = {'status': 'active'}
    db.docs[f'ideas/{IDEA}'] = {
        'ownerId': 'owner', 'title': 'title', 'description': 'description', 'tags': [],
        'deletedAt': None, 'publishedUntil': NOW + timedelta(days=1), 'acceptUntil': NOW + timedelta(days=24),
    }
    db.docs['userPins/artist'] = {'pinnedIdeaIds': []}
    image = BytesIO()
    Image.new('RGB', (8, 6)).save(image, format='PNG')
    client = Mock()
    blob = client.bucket.return_value.blob.return_value
    monkeypatch.setattr(service.storage, 'Client', lambda **kwargs: client)
    monkeypatch.setattr(service, 'analyze_image', lambda image: {'decision': 'approved'})
    return db, Settings(artwork_bucket='private-bucket'), image.getvalue(), client, blob


def test_submission_and_retry_are_atomic(environment):
    db, settings, raw, client, blob = environment
    result, created = service.submit(db, settings, 'artist', IDEA, raw)
    repeated, created_again = service.submit(db, settings, 'artist', IDEA, raw)
    assert created and not created_again and repeated == result
    sid = result['submissionId']
    assert db.docs[f'users/artist/drawnHistory/{sid}']['ideaId'] == IDEA
    artwork = db.docs[f'artworks/{sid}']
    assert artwork['recipientId'] == 'owner'
    assert artwork['expiresAt'] == NOW + timedelta(days=7)
    assert db.docs['users/artist']['drawnCount'] == 1
    blob.upload_from_string.assert_called_once()
    data = blob.upload_from_string.call_args.args[0]
    assert Image.open(BytesIO(data)).format == 'WEBP'
    assert blob.upload_from_string.call_args.kwargs['if_generation_match'] == 0
    blob.delete.assert_not_called()
    with pytest.raises(ApiError) as error:
        service.submit(db, settings, 'artist', IDEA, raw + b'changed')
    assert error.value.status == 409


@pytest.mark.parametrize('state', ['self', 'expired', 'deleted', 'unpin', 'suspended', 'owner_suspended', 'history'])
def test_ineligible_submission_never_uploads(environment, state):
    db, settings, raw, client, blob = environment
    idea = db.docs[f'ideas/{IDEA}']
    if state == 'self':
        idea['ownerId'] = 'artist'
    elif state == 'expired':
        idea['acceptUntil'] = NOW
    elif state == 'deleted':
        idea['deletedAt'] = NOW
    elif state == 'unpin':
        idea['publishedUntil'] = NOW
    elif state == 'suspended':
        db.docs['users/artist']['status'] = 'suspended'
    elif state == 'owner_suspended':
        db.docs['users/owner']['status'] = 'suspended'
    else:
        sid = service._submission_id('artist', IDEA)
        db.docs[f'users/artist/drawnHistory/{sid}'] = {'ideaId': IDEA}
    with pytest.raises(ApiError):
        service.submit(db, settings, 'artist', IDEA, raw)
    blob.upload_from_string.assert_not_called()
    assert db.docs['users/artist']['drawnCount'] == 0


def test_prior_pin_allows_late_submission(environment):
    db, settings, raw, client, blob = environment
    db.docs[f'ideas/{IDEA}']['publishedUntil'] = NOW
    db.docs['userPins/artist']['pinnedIdeaIds'] = [IDEA]
    assert service.submit(db, settings, 'artist', IDEA, raw)[1]


@pytest.mark.parametrize('decision,status', [('rejected', 422), ('retry_required', 503)])
def test_moderation_failure_does_not_save(environment, monkeypatch, decision, status):
    db, settings, raw, client, blob = environment
    monkeypatch.setattr(service, 'analyze_image', lambda image: {'decision': decision})
    with pytest.raises(ApiError) as error:
        service.submit(db, settings, 'artist', IDEA, raw)
    assert error.value.status == status
    blob.upload_from_string.assert_not_called()
    assert not any(path.startswith('artworks/') for path in db.docs)


def test_revoked_eligibility_after_upload_is_rechecked(environment):
    db, settings, raw, client, blob = environment
    blob.upload_from_string.side_effect = lambda *args, **kwargs: db.docs[f'ideas/{IDEA}'].update(deletedAt=NOW)
    with pytest.raises(ApiError):
        service.submit(db, settings, 'artist', IDEA, raw)
    blob.delete.assert_called_once()
    assert db.docs['users/artist']['drawnCount'] == 0
    assert not any(path.startswith('artworks/') for path in db.docs)


def test_ambiguous_success_preserves_committed_image(environment, monkeypatch):
    db, settings, raw, client, blob = environment
    original = service.finalize
    def commit_then_disconnect(*args):
        original(*args)
        raise ConnectionError('lost response')
    monkeypatch.setattr(service, 'finalize', commit_then_disconnect)
    with pytest.raises(ApiError):
        service.submit(db, settings, 'artist', IDEA, raw)
    blob.delete.assert_not_called()
    assert db.docs['users/artist']['drawnCount'] == 1
    assert not service.submit(db, settings, 'artist', IDEA, raw)[1]


def test_cleanup_failure_is_recoverable(environment, monkeypatch):
    db, settings, raw, client, blob = environment
    monkeypatch.setattr(service, 'finalize', Mock(side_effect=RuntimeError('db failed')))
    blob.delete.side_effect = RuntimeError('storage offline')
    with pytest.raises(ApiError):
        service.submit(db, settings, 'artist', IDEA, raw)
    token = next(path.split('/')[-1] for path in db.docs if path.startswith('artworkUploads/'))
    assert db.docs[f'artworkUploads/{token}']['status'] == 'abandoned'
    blob.delete.side_effect = None
    service.recover_attempt(db, token, client)
    assert f'artworkUploads/{token}' not in db.docs


def test_expired_worker_cannot_finalize_after_cleanup(environment, monkeypatch):
    db, settings, raw, client, blob = environment
    digest = service.hashlib.sha256(raw).hexdigest()
    _, attempt = service.reserve(db, 'artist', IDEA, digest, settings.artwork_bucket)
    monkeypatch.setattr(service, 'utc_now', lambda: NOW + timedelta(minutes=31))
    service.recover_attempt(db, attempt['token'], client)
    with pytest.raises(ApiError):
        service.finalize(db, 'artist', IDEA, attempt, digest)
    assert db.docs['users/artist']['drawnCount'] == 0


def test_concurrent_reservations_only_one_can_proceed(environment):
    db, settings, raw, client, blob = environment
    def reserve():
        try:
            return service.reserve(db, 'artist', IDEA, 'digest', settings.artwork_bucket)[1]
        except ApiError:
            return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: reserve(), range(2)))
    assert sum(result is not None for result in results) == 1


def test_http_submission_and_retry(environment, monkeypatch):
    from fastapi.testclient import TestClient
    from app.auth import active_user
    from app.main import create_app

    db, settings, raw, client, blob = environment
    app = create_app(settings)
    app.dependency_overrides[active_user] = lambda: {'uid': 'artist'}
    monkeypatch.setattr(service, 'database', lambda: db)
    with TestClient(app) as http:
        first = http.post('/api/v1/artworks', data={'ideaId': IDEA}, files={'file': ('image.png', raw, 'image/png')})
        retry = http.post('/api/v1/artworks', data={'ideaId': IDEA}, files={'file': ('image.png', raw, 'image/png')})
    assert first.status_code == 201
    assert retry.status_code == 200
    assert retry.json() == first.json()
    assert set(first.json()) == {'submissionId', 'submittedAt'}


def test_upload_limit_applies_to_submission_without_content_length(environment, monkeypatch):
    from fastapi.testclient import TestClient
    from app import middleware
    from app.main import create_app

    db, settings, raw, client, blob = environment
    monkeypatch.setattr(middleware, 'MAX_DEMO_REQUEST_BYTES', 1024)
    # Content-Lengthなしの送信でも、通常投稿の受信量を制限する。
    content = b'--test\r\nContent-Disposition: form-data; name="file"; filename="large.png"\r\n\r\n' + b'x' * 2048 + b'\r\n--test--\r\n'
    with TestClient(create_app(settings)) as http:
        response = http.post('/api/v1/artworks', content=iter([content]), headers={'Content-Type': 'multipart/form-data; boundary=test'})
    assert response.status_code == 413
    blob.upload_from_string.assert_not_called()


def test_artwork_cleanup_requires_internal_identity(environment):
    from fastapi.testclient import TestClient
    from app.main import create_app

    with TestClient(create_app(environment[1])) as http:
        response = http.post('/api/v1/internal/artwork-cleanup')
    assert response.status_code == 401


def test_commit_failure_before_result_can_be_retried(environment, monkeypatch):
    db, settings, raw, client, blob = environment
    original = service.finalize
    monkeypatch.setattr(service, 'finalize', Mock(side_effect=RuntimeError('db unavailable')))
    with pytest.raises(ApiError):
        service.submit(db, settings, 'artist', IDEA, raw)
    assert db.docs['users/artist']['drawnCount'] == 0
    blob.delete.assert_called_once()
    monkeypatch.setattr(service, 'finalize', original)
    assert service.submit(db, settings, 'artist', IDEA, raw)[1]
    assert db.docs['users/artist']['drawnCount'] == 1


def test_orphan_sweep_preserves_committed_and_processing_images(environment):
    db, settings, raw, client, blob = environment
    class Page(list):
        next_page_token = 'next-page'

    committed = Mock(name='committed')
    committed.name = 'artworks/committed/token1.webp'
    processing = Mock(name='processing')
    processing.name = 'artworks/processing/token2.webp'
    orphan = Mock(name='orphan')
    orphan.name = 'artworks/orphan/token3.webp'
    orphan.generation = 42
    db.docs['artworks/committed'] = {'storagePath': committed.name}
    db.docs['artworkUploads/token2'] = {'status': 'processing'}
    client.list_blobs.return_value = Page([committed, processing, orphan])
    assert service.recover_untracked_objects(db, settings, client) == 3
    committed.delete.assert_not_called()
    processing.delete.assert_not_called()
    orphan.delete.assert_called_once_with(if_generation_match=42, timeout=60)
    assert db.docs['cleanupState/artworkObjects']['pageToken'] == 'next-page'
    service.recover_untracked_objects(db, settings, client)
    assert client.list_blobs.call_args.kwargs['page_token'] == 'next-page'


def test_post_limit_prevents_expensive_processing(environment):
    # 上限到達時は画像処理やStorageを呼ばず、予約も作らない。
    db, settings, raw, client, blob = environment
    db.docs['users/artist']['postAttempts_artwork'] = [NOW] * 20
    with pytest.raises(ApiError) as error:
        service.submit(db, settings, 'artist', IDEA, raw)
    assert error.value.status == 429
    client.bucket.assert_not_called()
    assert not any(path.startswith('artworkSubmissions/') for path in db.docs)


def test_replay_at_limit_does_not_consume_slot(environment):
    # 確定済み再送は制限を超えていても結果だけ返す。
    db, settings, raw, client, blob = environment
    result, _ = service.submit(db, settings, 'artist', IDEA, raw)
    assert len(db.docs['users/artist']['postAttempts_artwork']) == 1
    db.docs['users/artist']['postAttempts_artwork'] = [NOW] * 20
    assert service.submit(db, settings, 'artist', IDEA, raw) == (result, False)
    assert len(db.docs['users/artist']['postAttempts_artwork']) == 20
    blob.upload_from_string.assert_called_once()


def test_parallel_reservations_share_one_user_limit(environment):
    # 並行リクエストは同じユーザー文書を更新し、上限を超えて予約しない。
    db, settings, raw, client, blob = environment
    ids = [f"00000000-0000-4000-8000-{index:012d}" for index in range(25)]
    for idea_id in ids:
        db.docs[f'ideas/{idea_id}'] = deepcopy(db.docs[f'ideas/{IDEA}'])

    def attempt(idea_id):
        try:
            service.reserve(db, 'artist', idea_id, 'digest', 'private-bucket')
            return 201
        except ApiError as error:
            return error.status

    with ThreadPoolExecutor(max_workers=8) as executor:
        statuses = list(executor.map(attempt, ids))
    assert statuses.count(201) == 20
    assert statuses.count(429) == 5
    assert len(db.docs['users/artist']['postAttempts_artwork']) == 20


def test_idea_limit_survives_slot_reuse_and_allows_replay(environment, monkeypatch):
    # スロットを空けても時間内の投稿枠は復活せず、同一投稿の再送は許可する。
    from app import ideas
    from uuid import uuid4

    db, settings, raw, client, blob = environment
    monkeypatch.setattr(ideas, 'utc_now', lambda: NOW)
    monkeypatch.setattr(Transaction, 'create', Transaction.set, raising=False)
    first = None
    for index in range(10):
        db.docs['userSlots/artist'] = {'slots': {}}
        body = ideas.IdeaCreate(ideaId=str(uuid4()), title='title', description='description')
        first = first or body
        assert ideas._create_idea(db, 'artist', body)[1]
    db.docs['userSlots/artist'] = {'slots': {}}
    with pytest.raises(ApiError) as error:
        ideas._create_idea(db, 'artist', ideas.IdeaCreate(
            ideaId=str(uuid4()), title='title', description='description'))
    assert error.value.status == 429
    assert db.docs['users/artist']['ideaCount'] == 10
    assert not ideas._create_idea(db, 'artist', first)[1]
    assert len(db.docs['users/artist']['postAttempts_idea']) == 10


def test_empty_slot_maps_create_delete_and_reuse(environment, monkeypatch):
    # 登録直後と同じ空Mapから作成し、削除後に古い項目を残さず再利用する。
    from app import ideas
    from uuid import uuid4
    db, *_ = environment
    monkeypatch.setattr(ideas, 'utc_now', lambda: NOW)
    monkeypatch.setattr(Transaction, 'create', Transaction.set, raising=False)
    db.docs['userSlots/artist'] = {'slots': {f'slot_{i}': {} for i in range(5)}}
    first = ideas.IdeaCreate(ideaId=str(uuid4()), title='first', description='description')
    ideas._create_idea(db, 'artist', first)
    assert ideas._get_slots(db, 'artist').model_dump()['slots']['slot_0']['ideaId'] == first.ideaId
    ideas._delete_idea(db, 'artist', first.ideaId)
    assert db.docs['userSlots/artist']['slots']['slot_0'] == {}
    assert ideas._get_slots(db, 'artist').model_dump()['slots'] == {f'slot_{i}': {} for i in range(5)}
    second = ideas.IdeaCreate(ideaId=str(uuid4()), title='second', description='description')
    ideas._create_idea(db, 'artist', second)
    assert db.docs['userSlots/artist']['slots']['slot_0']['ideaId'] == second.ideaId
    ideas._delete_idea(db, 'artist', first.ideaId)
    assert db.docs['userSlots/artist']['slots']['slot_0']['ideaId'] == second.ideaId


def test_slot_response_normalizes_legacy_expired_and_missing(environment, monkeypatch):
    # 旧null・空Map・期限切れ・参照欠損・削除済みは同じ空オブジェクトで返す。
    from app import ideas
    db, *_ = environment
    monkeypatch.setattr(ideas, 'utc_now', lambda: NOW)
    db.docs[f'ideas/{IDEA}']['deletedAt'] = NOW
    db.docs['userSlots/artist'] = {'slots': {
        'slot_0': None,
        'slot_1': {},
        'slot_2': {'ideaId': IDEA, 'expiresAt': NOW},
        'slot_3': {'ideaId': 'missing', 'expiresAt': NOW + timedelta(days=1)},
        'slot_4': {'ideaId': IDEA, 'expiresAt': NOW + timedelta(days=1)},
    }}
    assert ideas._get_slots(db, 'artist').model_dump()['slots'] == {f'slot_{i}': {} for i in range(5)}
