"""サーバー時刻とAPIのUTC日時表現を統一する。"""

from datetime import datetime, timezone
from typing import Annotated

from pydantic import AfterValidator, PlainSerializer


def utc_now() -> datetime:
    """トランザクションでは各再試行の中で呼び直す。"""
    return datetime.now(timezone.utc)


def as_utc(value: datetime) -> datetime:
    """タイムゾーンなしの日時を暗黙にローカル時刻として扱わない。"""
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Timezone is required")
    return value.astimezone(timezone.utc)


def rfc3339(value: datetime) -> str:
    """UTC文字列は必ずZで終える。"""
    return as_utc(value).isoformat().replace("+00:00", "Z")


def is_unexpired(expires_at: datetime, now: datetime) -> bool:
    """期限と同時刻になった時点で無効とする。"""
    return as_utc(now) < as_utc(expires_at)


# DTOの日時フィールドに指定し、Firestore保存時はdatetimeのまま扱う。
UtcDatetime = Annotated[
    datetime, AfterValidator(as_utc),
    PlainSerializer(rfc3339, return_type=str, when_used="json"),
]
