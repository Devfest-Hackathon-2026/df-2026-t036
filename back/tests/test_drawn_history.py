"""お題の削除後も描いた履歴を残し、削除済みの内容を返さないことを確認する。"""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest

from app.artworks import _list_history
from app.schemas import PageQuery


@pytest.mark.parametrize("state", ["active", "deleted", "missing", "expired"])
def test_history_preserves_record_and_hides_deleted_idea(state):
    # 作品やお題の期限では履歴を消さず、手動削除・欠損時だけ参照不可にする。
    now = datetime.now(timezone.utc)
    db = MagicMock()
    history = MagicMock()
    history.id = "submission"
    history.to_dict.return_value = {
        "ideaId": "idea", "submittedAt": now, "lastLiked": True,
    }
    collection = db.collection.return_value.document.return_value.collection.return_value
    collection.order_by.return_value.order_by.return_value.limit.return_value.stream.return_value = [history]
    idea = MagicMock()
    idea.id = "idea"
    idea.exists = state != "missing"
    created_at = now - timedelta(days=40) if state == "expired" else now
    idea.to_dict.return_value = {
        "ownerId": "owner", "title": "お題", "description": "説明", "tags": [],
        "createdAt": created_at, "publishedUntil": created_at + timedelta(days=7),
        "acceptUntil": created_at + timedelta(days=30),
        "deletedAt": now if state == "deleted" else None,
    }
    owner = MagicMock()
    owner.id = "owner"
    owner.to_dict.return_value = {"nickname": "投稿者"}
    db.get_all.side_effect = [[idea], [owner]]

    result = _list_history(db, "artist", PageQuery())

    assert len(result.items) == 1
    item = result.items[0]
    assert item.submissionId == "submission"
    assert item.ideaId == "idea"
    assert item.lastLiked is True
    assert item.submittedAt == now
    if state in {"deleted", "missing"}:
        assert item.idea is None
        assert item.ideaAvailability == "unavailable"
    else:
        assert item.idea.title == "お題"
        assert item.ideaAvailability == "available"
    assert result.nextCursor is None
