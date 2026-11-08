"""再送しても初期化し直さないユーザー登録を扱う。"""

import secrets

from firebase_admin import firestore
from fastapi import APIRouter, Request, Response
from starlette.concurrency import run_in_threadpool

from .auth import ActiveUser, GoogleUid, active
from .errors import ApiError
from .firebase import database
from .schemas import ApiModel


class Me(ApiModel):
    """本人に公開する項目だけを明示する。"""

    uid: str
    nickname: str
    status: str
    ideaCount: int
    drawnCount: int
    likesReceived: int


def me_dto(uid: str, data: dict) -> Me:
    """内部フィールドやAuthの個人情報を応答に含めない。"""
    return Me(uid=uid, **{key: data[key] for key in (
        "nickname", "status", "ideaCount", "drawnCount", "likesReceived"
    )})


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
    return me_dto(user["uid"], user)
