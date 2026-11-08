"""入力検証と一覧応答の共通契約を定義する。"""

from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .clock import UtcDatetime


class ApiModel(BaseModel):
    """未知のフィールドや暗黙の型変換を拒否する。"""

    model_config = ConfigDict(extra="forbid", strict=True)


class InputModel(ApiModel):
    """文字列は前後空白を除去してから各項目の長さを検証する。"""

    @field_validator("*", mode="before")
    @classmethod
    def trim_strings(cls, value):
        """文字列配列も整形するが、重複排除などの業務規則は項目側で行う。"""
        if isinstance(value, str):
            return value.strip()
        if isinstance(value, list):
            return [item.strip() if isinstance(item, str) else item for item in value]
        return value


class PageQuery(BaseModel):
    """URLの数値文字列を受け取り、一覧件数を既定20・最大50に制限する。"""

    model_config = ConfigDict(extra="forbid")
    limit: int = Field(default=20, ge=1, le=50)
    cursor: str | None = Field(default=None, min_length=1, max_length=2048)


Item = TypeVar("Item")


class Page(ApiModel, Generic[Item]):
    """カーソルは各検索の並び順と認証スコープに合わせて生成する。"""

    items: list[Item]
    nextCursor: str | None
    serverTime: UtcDatetime

class TimelineQuery(PageQuery):
    """タグ文字列を完全一致で受け取り、他の一覧の検索条件とは分離する。"""

    tag: str | None = Field(default=None, min_length=1, max_length=20)

    @field_validator("tag", mode="before")
    @classmethod
    def trim_tag(cls, value):
        # 投稿時と同じく前後の空白を除去してから長さを検証する。
        return value.strip() if isinstance(value, str) else value
