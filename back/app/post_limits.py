"""投稿枠をユーザー文書へ保存し、複数インスタンス間でも上限を共有する。"""

from datetime import timedelta

from .errors import ApiError

WINDOW = timedelta(hours=1)
LIMITS = {"idea": 10, "artwork": 20}


def consume_post(tx, user_ref, user_data, kind, now):
    """直近1時間の枠を投稿トランザクション内で消費する。失敗時は書込も戻る。"""
    field = f"postAttempts_{kind}"
    recent = [stamp for stamp in user_data.get(field, []) if stamp > now - WINDOW]
    if len(recent) >= LIMITS[kind]:
        raise ApiError(429, "RATE_LIMITED", "投稿回数の上限に達しました。時間をおいて再試行してください。")
    # 記録件数を上限以内に保ち、期限切れ日時は次回投稿時に除去する。
    tx.update(user_ref, {field: [*recent, now]})
