"""再送しても初期化し直さないユーザー登録を扱う。"""

import secrets
from typing import Literal
from urllib.parse import urlsplit

from firebase_admin import firestore
from fastapi import APIRouter, Request, Response
from pydantic import Field, field_validator
from starlette.concurrency import run_in_threadpool

from .auth import ActiveUser, GoogleUid, active
from .errors import ApiError
from .firebase import database
from .schemas import ApiModel, InputModel

MAX_SOCIAL_LINKS = 5
MAX_BIO_LENGTH = 300
MAX_NICKNAME_LENGTH = 24
ALLOWED_SOCIAL_HOSTS = {
    "x": {"x.com", "twitter.com"},
    "instagram": {"instagram.com"},
    "pixiv": {"pixiv.net"},
    "youtube": {"youtube.com", "youtu.be"},
}


class Me(ApiModel):
    """本人に公開する項目だけを明示する。"""

    uid: str
    nickname: str
    status: str
    ideaCount: int
    drawnCount: int
    likesReceived: int
    bio: str = ""
    socialLinks: list["SocialLink"] = Field(default_factory=list)


class SocialLink(InputModel):
    type: Literal["x", "instagram", "pixiv", "youtube", "other"]
    label: str = Field(min_length=1, max_length=40)
    url: str = Field(min_length=1, max_length=2048)

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str, info):
        parsed = urlsplit(value)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError("URL must be an HTTPS URL without credentials")
        if info.data.get("type") != "other":
            allowed = ALLOWED_SOCIAL_HOSTS[info.data["type"]]
            host = parsed.hostname.lower().rstrip(".")
            if not any(host == domain or host.endswith("." + domain) for domain in allowed):
                raise ValueError("URL host does not match social link type")
        return value


class ProfileUpdate(InputModel):
    nickname: str | None = Field(default=None, min_length=1, max_length=MAX_NICKNAME_LENGTH)
    bio: str = Field(max_length=MAX_BIO_LENGTH)
    socialLinks: list[SocialLink] = Field(max_length=MAX_SOCIAL_LINKS)

    @field_validator("nickname")
    @classmethod
    def validate_nickname(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value or any(ord(character) < 32 or ord(character) == 127 for character in value):
            raise ValueError("nickname must not be empty or contain control characters")
        return value

    @field_validator("socialLinks")
    @classmethod
    def unique_urls(cls, links: list[SocialLink]) -> list[SocialLink]:
        normalized = [link.url.rstrip("/").casefold() for link in links]
        if len(set(normalized)) != len(normalized):
            raise ValueError("social links must be unique")
        return links


class PublicProfile(ApiModel):
    uid: str
    nickname: str
    bio: str
    socialLinks: list[SocialLink]


def me_dto(uid: str, data: dict) -> Me:
    """内部フィールドやAuthの個人情報を応答に含めない。"""
    return Me(uid=uid, **{key: data[key] for key in (
        "nickname", "status", "ideaCount", "drawnCount", "likesReceived"
    )})


def profile_fields(data: dict) -> dict:
    """Only explicitly supported public profile fields cross API boundaries."""
    return {
        "bio": data.get("bio", ""),
        "socialLinks": data.get("socialLinks", []),
    }


def register_user(db, uid: str) -> tuple[Me, bool]:
    """3文書を原子的に作成し、競合・再送時は既存値を維持する。"""
    user_ref = db.collection("users").document(uid)
    slots_ref = db.collection("userSlots").document(uid)
    pins_ref = db.collection("userPins").document(uid)

    @firestore.transactional
    def initialize(transaction):
        snapshot = user_ref.get(transaction=transaction)
        if snapshot.exists:
            data = snapshot.to_dict()
            active(data)
            return me_dto(uid, data), False
        # Googleの本名・メールを使わず、再送時にはこの名前を再生成しない。
        data = {
            "nickname": secrets.choice(("そら", "つき", "にじ", "ほし"))
            + "の" + secrets.choice(("えふで", "パレット", "スケッチ"))
            + secrets.token_hex(2),
            "status": "active", "ideaCount": 0, "drawnCount": 0,
            "likesReceived": 0, "createdAt": firestore.SERVER_TIMESTAMP,
        }
        transaction.create(user_ref, data)
        # 空き枠もMapに統一し、削除後と初期登録時の型を揃える。
        transaction.create(slots_ref, {
            "maxSlots": 5, "slots": {f"slot_{index}": {} for index in range(5)},
        })
        transaction.create(pins_ref, {"maxPins": 5, "pinnedIdeaIds": []})
        return me_dto(uid, data), True

    return initialize(db.transaction())


router = APIRouter(prefix="/api/v1")


@router.post("/users/register", response_model=Me)
async def register(request: Request, response: Response,
                   uid: GoogleUid):
    """本文のUIDは受け付けず、認証済みUIDで初回登録する。"""
    if await request.body():
        raise ApiError(422, "INVALID_INPUT", "リクエスト本文は不要です。")
    # 同期SDKはイベントループ外で実行する。
    result, created = await run_in_threadpool(lambda: register_user(database(), uid))
    response.status_code = 201 if created else 200
    return result


@router.get("/me", response_model=Me)
def get_me(user: ActiveUser):
    """共通の登録・active検証を通した本人情報を返す。"""
    values = me_dto(user["uid"], user).model_dump()
    values.update(profile_fields(user))
    return Me(**values)


@router.patch("/me/profile", response_model=Me)
async def update_profile(payload: ProfileUpdate, user: ActiveUser):
    """本人の表示名、自己紹介、外部SNSリンクを更新する。"""
    uid = user["uid"]
    db = database()
    ref = db.collection("users").document(uid)
    update = payload.model_dump(exclude_none=True)

    def save():
        @firestore.transactional
        def apply(transaction):
            snapshot = ref.get(transaction=transaction)
            if not snapshot.exists:
                raise ApiError(404, "RESOURCE_UNAVAILABLE", "参照できません。")
            current = snapshot.to_dict()
            active(current)
            transaction.update(ref, update)
            values = me_dto(uid, current).model_dump()
            values.update(profile_fields(current))
            values.update(update)
            return Me(**values)

        return apply(db.transaction())

    return await run_in_threadpool(save)
