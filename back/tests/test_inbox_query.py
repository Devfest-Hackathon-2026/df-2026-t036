"""実際のFirestore SDKで受信一覧の検索とカーソルを構築し、並び順の再発を防ぐ。"""

from datetime import datetime, timedelta, timezone

from google.auth.credentials import AnonymousCredentials
from google.cloud.firestore_v1 import Client, DocumentSnapshot
from google.cloud.firestore_v1.document import DocumentReference
from google.cloud.firestore_v1.query import Query
import pytest

from app.artworks import _list_inbox
from app.ideas import _cursor_encode
from app.schemas import PageQuery


@pytest.mark.parametrize('with_cursor', [False, True])
def test_inbox_sdk_query_keeps_document_key_last(monkeypatch, with_cursor):
    # 外部通信をせず、モックだけでは見逃すSDKの暗黙の並び順も検証する。
    db = Client(project='inbox-test', credentials=AnonymousCredentials())
    now = datetime(2026, 11, 8, tzinfo=timezone.utc)
    ref = db.collection('artworks').document('previous')
    snapshot = DocumentSnapshot(ref, {'createdAt': now,
        'expiresAt': now + timedelta(days=7)}, True, now, now, now)
    monkeypatch.setattr(DocumentReference, 'get', lambda *args, **kwargs: snapshot)
    monkeypatch.setattr(db, 'get_all', lambda refs: [])
    requests = []

    def stream(query, *args, **kwargs):
        requests.append(query._to_protobuf())
        return iter(())

    monkeypatch.setattr(Query, 'stream', stream)
    cursor = _cursor_encode('inbox', 'recipient', 'previous') if with_cursor else None
    result = _list_inbox(db, 'recipient', PageQuery(limit=20, cursor=cursor))
    request = requests[0]
    assert [order.field.field_path for order in request.order_by] == [
        'expiresAt', 'createdAt', '__name__']
    assert all(order.direction == 2 for order in request.order_by)
    assert request.limit == 21
    if with_cursor:
        assert len(request.start_at.values) == 3
        assert request.start_at.before is False
        assert request.start_at.values[-1].reference_value.endswith('/artworks/previous')
    assert result.items == []
    assert result.nextCursor is None
