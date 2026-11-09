"""期限切れ作品のStorage画像を除去し、文書をFirestore TTLへ渡す。"""

from datetime import timedelta
import logging
from uuid import uuid4

from fastapi import APIRouter, Depends, Request
from firebase_admin import firestore
from google.api_core.exceptions import NotFound
from google.cloud import storage
from starlette.concurrency import run_in_threadpool

from .cleanup import cleanup_identity
from .clock import utc_now
from .errors import ApiError
from .firebase import database
from .schemas import ApiModel

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/internal")
BATCH_SIZE = 100
LEASE_DURATION = timedelta(minutes=5)


class ArtworkExpiryResult(ApiModel):
    scanned: int
    markedForTtl: int
    failed: int
    hasMore: bool


def _busy() -> ApiError:
    return ApiError(409, "CLEANUP_BUSY", "作品の期限整理は実行中です。")


def _acquire(db, token: str):
    ref = db.collection("cleanupState").document("artworkExpiry")

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


def _release(db, token: str, *, cursor: str | None = None, advance: bool = False):
    ref = db.collection("cleanupState").document("artworkExpiry")

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


def _eligible(data: dict, now) -> bool:
    return (data.get("purgeAt") is None and
            (data.get("deletedAt") is not None or
             (data.get("expiresAt") is not None and data["expiresAt"] <= now)))


def _safe_storage_path(submission_id: str, path: str) -> bool:
    parts = path.split("/") if isinstance(path, str) else []
    return (len(parts) == 3 and parts[0] == "artworks" and parts[1] == submission_id
            and parts[2].endswith(".webp") and len(parts[2]) > 5)


def _purge_one(db, client, settings, snapshot) -> bool:
    ref = db.collection("artworks").document(snapshot.id)
    current = ref.get()
    if not current.exists:
        return False
    data = current.to_dict()
    if not _eligible(data, utc_now()):
        return False
    path = data.get("storagePath")
    bucket_name = data.get("storageBucket") or settings.artwork_bucket
    if not bucket_name or not _safe_storage_path(snapshot.id, path):
        raise ValueError("invalid artwork storage reference")

    blob = client.bucket(bucket_name).blob(path)
    try:
        blob.reload(timeout=30)
        blob.delete(if_generation_match=blob.generation, timeout=60)
    except NotFound:
        pass

    # Storage削除後に文書を再読し、同一作品・同一画像参照の場合だけTTL印を付ける。
    @firestore.transactional
    def mark_for_ttl(tx):
        latest = ref.get(transaction=tx)
        if not latest.exists:
            return False
        latest_data = latest.to_dict()
        if (not _eligible(latest_data, utc_now()) or
                latest_data.get("storagePath") != path or
                (latest_data.get("storageBucket") or settings.artwork_bucket) != bucket_name):
            return False
        tx.update(ref, {"purgeAt": utc_now()})
        return True

    return mark_for_ttl(db.transaction())


def cleanup_expired_artworks(db, settings) -> ArtworkExpiryResult:
    token = str(uuid4())
    cursor = _acquire(db, token)
    try:
        collection = db.collection("artworks")
        query = collection.order_by("__name__")
        if cursor:
            query = query.start_after({"__name__": collection.document(cursor)})
        docs = list(query.limit(BATCH_SIZE + 1).stream())
        shown, more = docs[:BATCH_SIZE], len(docs) > BATCH_SIZE
        scanned = marked_for_ttl = failed = 0
        with storage.Client(project=settings.project_id) as client:
            for doc in shown:
                scanned += 1
                try:
                    if _purge_one(db, client, settings, doc):
                        marked_for_ttl += 1
                except Exception as exc:
                    failed += 1
                    logger.warning("artwork_expiry_item_failed exceptionType=%s", type(exc).__name__)
        next_cursor = shown[-1].id if more and shown else None
        _release(db, token, cursor=next_cursor, advance=True)
        result = ArtworkExpiryResult(scanned=scanned, markedForTtl=marked_for_ttl,
                                     failed=failed, hasMore=more)
        logger.info("artwork_expiry_cleanup_completed scanned=%s markedForTtl=%s failed=%s hasMore=%s",
                    scanned, marked_for_ttl, failed, more)
        return result
    except Exception:
        logger.warning("artwork_expiry_cleanup_failed")
        try:
            _release(db, token)
        except Exception:
            logger.warning("artwork_expiry_cleanup_release_failed")
        raise


@router.post("/artwork-expiry-cleanup", response_model=ArtworkExpiryResult,
             dependencies=[Depends(cleanup_identity)])
async def cleanup_artworks(request: Request):
    if await request.body() or request.query_params:
        raise ApiError(422, "INVALID_INPUT", "リクエスト本文・クエリは不要です。")
    return await run_in_threadpool(
        lambda: cleanup_expired_artworks(database(), request.app.state.settings))
