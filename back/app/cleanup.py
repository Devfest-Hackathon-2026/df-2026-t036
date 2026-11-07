"""内部認証とリースで保護した、期限切れピンの分割整理。"""

from datetime import timedelta
import logging
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, Request
from fastapi.security import HTTPAuthorizationCredentials
from firebase_admin import firestore
from google.auth.exceptions import GoogleAuthError, TransportError
from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2 import id_token
from starlette.concurrency import run_in_threadpool

from .auth import bearer
from .clock import utc_now
from .errors import ApiError
from .firebase import database
from .schemas import ApiModel

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/internal")
BATCH_SIZE = 100
LEASE_DURATION = timedelta(minutes=5)


def cleanup_identity(request: Request, credentials: Annotated[
    HTTPAuthorizationCredentials | None, Depends(bearer)
]) -> None:
    """Firebaseの利用者トークンではなく、SchedulerのGoogle OIDCを検証する。"""
    if credentials is None:
        raise ApiError(401, "UNAUTHENTICATED", "内部認証が必要です。")
    settings = request.app.state.settings
    if not settings.cleanup_service_account or not settings.cleanup_audience:
        raise ApiError(503, "CLEANUP_NOT_CONFIGURED", "期限整理の認証設定が必要です。")
    try:
        claims = id_token.verify_oauth2_token(
            credentials.credentials, GoogleRequest(), audience=settings.cleanup_audience,
        )
    except TransportError as exc:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "内部認証を再試行してください。") from exc
    except (ValueError, GoogleAuthError) as exc:
        raise ApiError(401, "UNAUTHENTICATED", "内部認証が不正です。") from exc
    if (claims.get("email") != settings.cleanup_service_account
            or claims.get("email_verified") is not True):
        raise ApiError(403, "FORBIDDEN", "この内部処理は許可されていません。")


class CleanupResult(ApiModel):
    """処理件数だけを返し、ユーザーIDやお題IDを公開しない。"""

    scannedUsers: int
    updatedUsers: int
    removedPins: int
    hasMore: bool


def _busy() -> ApiError:
    return ApiError(409, "CLEANUP_BUSY", "期限整理は実行中です。再試行してください。")


def _acquire(db, token: str):
    """複数インスタンス間でリースと走査位置を共有する。"""
    ref = db.collection("cleanupState").document("pins")

    @firestore.transactional
    def apply(tx):
        snap = ref.get(transaction=tx)
        data = snap.to_dict() if snap.exists else {}
        now = utc_now()
        if data.get("leaseUntil") and data["leaseUntil"] > now:
            raise _busy()
        tx.set(ref, {**data, "leaseOwner": token, "leaseUntil": now + LEASE_DURATION})
        return data.get("cursor")

    return apply(db.transaction())


def _clean_pins(db, uid: str, token: str) -> tuple[int, bool]:
    """現在のピンを再読込し、追加・解除やお題削除との競合時には再評価する。"""
    ref = db.collection("userPins").document(uid)
    lease = db.collection("cleanupState").document("pins")

    @firestore.transactional
    def apply(tx):
        lock = lease.get(transaction=tx).to_dict() or {}
        if lock.get("leaseOwner") != token or lock.get("leaseUntil") <= utc_now():
            raise _busy()
        snap = ref.get(transaction=tx)
        if not snap.exists:
            return 0, False
        original = snap.to_dict().get("pinnedIdeaIds", [])
        # 不正なID・重複・自己ピンも除き、7日経過だけでは削除しない。
        ids = list(dict.fromkeys(x for x in original if isinstance(x, str) and x and "/" not in x))
        snapshots = [(idea_id, db.collection("ideas").document(idea_id).get(transaction=tx))
                     for idea_id in ids]
        now = utc_now()
        kept = []
        for idea_id, idea in snapshots:
            if not idea.exists:
                continue
            data = idea.to_dict()
            if (data.get("deletedAt") is None and data.get("acceptUntil") is not None
                    and data["acceptUntil"] > now and data.get("ownerId") != uid):
                kept.append(idea_id)
        changed = kept != original
        if changed:
            # 一時停止中の投稿者のピンは消さず、停止解除後の権利を保持する。
            tx.update(ref, {"pinnedIdeaIds": kept})
        return len(original) - len(kept), changed

    return apply(db.transaction())


def _release(db, token: str, *, cursor: str | None = None, advance: bool = False):
    """成功したページだけ走査位置を進め、失敗時は同じページを再処理する。"""
    ref = db.collection("cleanupState").document("pins")

    @firestore.transactional
    def apply(tx):
        snap = ref.get(transaction=tx)
        data = snap.to_dict() if snap.exists else {}
        if data.get("leaseOwner") != token:
            return
        updates = {"leaseOwner": None, "leaseUntil": utc_now()}
        if advance:
            updates.update(cursor=cursor, lastCompletedAt=utc_now())
        tx.update(ref, updates)

    apply(db.transaction())


def cleanup_pins(db) -> CleanupResult:
    """1回100ユーザーで区切り、次の定期実行で続きから再開する。"""
    token = str(uuid4())
    cursor = _acquire(db, token)
    try:
        collection = db.collection("userPins")
        query = collection.order_by("__name__")
        if cursor:
            # 文書が削除されても、文書IDの境界から続行できる。
            query = query.start_after({"__name__": collection.document(cursor)})
        docs = list(query.limit(BATCH_SIZE + 1).stream())
        shown, more = docs[:BATCH_SIZE], len(docs) > BATCH_SIZE
        removed, updated = 0, 0
        for doc in shown:
            count, changed = _clean_pins(db, doc.id, token)
            removed += count
            updated += int(changed)
        _release(db, token, cursor=shown[-1].id if more else None, advance=True)
        result = CleanupResult(scannedUsers=len(shown), updatedUsers=updated,
                               removedPins=removed, hasMore=more)
        logger.info("pin_cleanup_completed scannedUsers=%s updatedUsers=%s removedPins=%s hasMore=%s",
                    result.scannedUsers, result.updatedUsers, result.removedPins, result.hasMore)
        return result
    except Exception:
        # 部分成功後の再実行も安全。解放に失敗したリースは5分で失効する。
        logger.warning("pin_cleanup_failed")
        try:
            _release(db, token)
        except Exception:
            logger.warning("pin_cleanup_release_failed")
        raise


@router.post("/cleanup", response_model=CleanupResult, dependencies=[Depends(cleanup_identity)])
async def cleanup(request: Request):
    """メンテナンス中も内部認証を要求し、ピンの整理だけを実行する。"""
    if await request.body() or request.query_params:
        raise ApiError(422, "INVALID_INPUT", "リクエスト本文・クエリは不要です。")
    return await run_in_threadpool(lambda: cleanup_pins(database()))
