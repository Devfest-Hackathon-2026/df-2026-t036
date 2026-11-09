"""タグ候補、検索条件とカーソルの分離を外部通信なしで検証する。"""
from types import SimpleNamespace

import pytest
from google.auth.credentials import AnonymousCredentials
from google.cloud.firestore_v1 import Client
from google.cloud.firestore_v1.query import Query
from pydantic import ValidationError

from app import ideas
from app.errors import ApiError
from app.schemas import TimelineQuery


def test_tag_query_validation():
    # 投稿時の空白除去と文字数制限を検索にも適用する。
    assert TimelineQuery(tag='  空  ').tag == '空'
    for value in ['', '   ', 'a' * 21]:
        with pytest.raises(ValidationError):
            TimelineQuery(tag=value)


@pytest.mark.parametrize('tag', [None, '空'])
def test_timeline_tags_and_sdk_filter(monkeypatch, tag):
    db = Client(project='tag-test', credentials=AnonymousCredentials())
    requests = []
    def stream(query, *args, **kwargs):
        request = query._to_protobuf()
        requests.append(request)
        if request.select.fields:
            return iter([SimpleNamespace(to_dict=lambda: {'tags': ['空', '海', '空']}),
                         SimpleNamespace(to_dict=lambda: {})])
        return iter(())
    monkeypatch.setattr(Query, 'stream', stream)
    result = ideas._list_ideas(db, uid='viewer', query=TimelineQuery(tag=tag), own=False)
    assert result.tags == sorted(['空', '海'])
    assert result.items == []
    assert result.nextCursor is None
    assert len(requests) == 2
    filters = requests[1].where.composite_filter.filters
    tag_filters = [f.field_filter for f in filters if f.field_filter.field.field_path == 'tags']
    assert len(tag_filters) == (0 if tag is None else 1)
    if tag:
        assert tag_filters[0].op == 7
        assert tag_filters[0].value.string_value == tag
    assert requests[1].limit == 21
    assert [o.field.field_path for o in requests[1].order_by] == ['publishedUntil', '__name__']


def test_cursor_cannot_cross_tag_scope():
    # 異なるタグや未選択時へのカーソル使い回しを拒否する。
    cursor = ideas._cursor_encode('timeline:tag:空', 'viewer', 'previous')
    assert ideas._cursor_decode(cursor, 'timeline:tag:空', 'viewer') == 'previous'
    for scope in ['timeline', 'timeline:tag:海']:
        with pytest.raises(ApiError):
            ideas._cursor_decode(cursor, scope, 'viewer')
