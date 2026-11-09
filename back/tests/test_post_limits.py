"""上限、時間境界、ユーザー分離を検証する。"""

from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

import pytest

from app.errors import ApiError
from app.post_limits import consume_post, LIMITS

NOW = datetime(2026, 11, 8, tzinfo=timezone.utc)


@pytest.mark.parametrize("kind", ["idea", "artwork"])
def test_limit_and_window_boundary(kind):
    # 上限直前は成功し、上限到達では書込せず429を返す。
    tx = Mock()
    field = f"postAttempts_{kind}"
    stamps = [NOW] * (LIMITS[kind] - 1)
    consume_post(tx, "user", {field: stamps}, kind, NOW)
    recorded = tx.update.call_args.args[1][field]
    assert len(recorded) == LIMITS[kind]
    tx.reset_mock()
    with pytest.raises(ApiError) as error:
        consume_post(tx, "user", {field: recorded}, kind, NOW)
    assert error.value.status == 429
    tx.update.assert_not_called()
    consume_post(tx, "user", {field: recorded}, kind, NOW + timedelta(hours=1))
    assert tx.update.call_args.args[1][field] == [NOW + timedelta(hours=1)]


def test_independent_user_and_kind():
    # 他の投稿種別の履歴や別ユーザーの枠を変更しない。
    tx = Mock()
    consume_post(tx, "other-user", {"postAttempts_artwork": [NOW] * 20}, "idea", NOW)
    tx.update.assert_called_once_with("other-user", {"postAttempts_idea": [NOW]})
