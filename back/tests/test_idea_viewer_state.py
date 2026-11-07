"""お題の所有者・描画履歴が一覧の状態に反映されることを確認する。"""

from datetime import datetime, timedelta, timezone

import pytest

from app.ideas import _idea_dto


@pytest.mark.parametrize(
    "owner_id,drawn_ids,is_own,has_drawn,can_submit",
    [
        ("viewer", set(), True, False, False),
        ("owner", {"idea"}, False, True, False),
        ("owner", set(), False, False, True),
    ],
)
def test_idea_viewer_state(owner_id, drawn_ids, is_own, has_drawn, can_submit):
    # 緑・黄・青の表示と送信ボタンが同じ閲覧者の状態を使う。
    now = datetime.now(timezone.utc)
    idea = _idea_dto(
        "idea",
        {
            "ownerId": owner_id,
            "title": "お題",
            "description": "説明",
            "createdAt": now,
            "publishedUntil": now + timedelta(days=7),
            "acceptUntil": now + timedelta(days=30),
            "deletedAt": None,
        },
        "名前", True, "viewer", [], drawn_ids, now,
    )
    assert idea.isOwn is is_own
    assert idea.hasDrawn is has_drawn
    assert idea.canSubmit is can_submit
