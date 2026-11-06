"""受信作品一覧、描いた履歴、既読・いいね操作。画像データは扱わない。"""

from firebase_admin import firestore
from fastapi import APIRouter, Query
from google.cloud.firestore_v1.base_query import FieldFilter
from starlette.concurrency import run_in_threadpool

from .auth import ActiveUser, active
from .clock import UtcDatetime, utc_now
from .errors import ApiError
from .firebase import database
from .ideas import _cursor_decode, _cursor_encode
from .schemas import ApiModel, Page, PageQuery

router = APIRouter(prefix="/api/v1")


class IdeaSnapshot(ApiModel):
    title: str
    description: str
    tags: list[str]
    ownerId: str


class InboxItem(ApiModel):
    submissionId: str
    artistId: str
    artistNickname: str
    sourceIdeaId: str
    sourceIdeaSnapshot: IdeaSnapshot
    liked: bool
    readAt: UtcDatetime | None
    createdAt: UtcDatetime
    expiresAt: UtcDatetime


class InboxPage(Page[InboxItem]):
    pass


class DrawnIdea(ApiModel):
    ideaId: str
    ownerId: str
    ownerNickname: str
    title: str
    description: str
    tags: list[str]
    createdAt: UtcDatetime
    publishedUntil: UtcDatetime
    acceptUntil: UtcDatetime


class HistoryItem(ApiModel):
    submissionId: str
    ideaId: str
    submittedAt: UtcDatetime
    lastLiked: bool
    idea: DrawnIdea | None
    ideaAvailability: str


class HistoryPage(Page[HistoryItem]):
    pass


class ReadResult(ApiModel):
    submissionId: str
    readAt: UtcDatetime


class LikeResult(ApiModel):
    submissionId: str
    liked: bool


def _unavailable() -> ApiError:
    return ApiError(404, "RESOURCE_UNAVAILABLE", "参照できません。")


def _page_query(db, collection, uid: str, query: PageQuery, scope: str):
    cursor = None
    if query.cursor:
        doc_id = _cursor_decode(query.cursor, scope, uid)
        cursor = collection.document(doc_id).get()
        if not cursor.exists:
            raise ApiError(422, "INVALID_INPUT", "一覧を更新して最初から取得してください。")
    return cursor


def _list_inbox(db, uid: str, query: PageQuery) -> InboxPage:
    now = utc_now()
    coll = db.collection("artworks")
    request = (coll.where(filter=FieldFilter("recipientId", "==", uid))
               .where(filter=FieldFilter("deletedAt", "==", None))
               .where(filter=FieldFilter("expiresAt", ">", now))
               .order_by("createdAt", direction=firestore.Query.DESCENDING)
               .order_by("__name__", direction=firestore.Query.DESCENDING))
    cursor = _page_query(db, coll, uid, query, "inbox")
    if cursor:
        request = request.start_after(cursor)
    docs = list(request.limit(query.limit + 1).stream())
    shown, more = docs[:query.limit], len(docs) > query.limit
    artist_ids = list(dict.fromkeys(d.to_dict().get("artistId") for d in shown))
    refs = [db.collection("users").document(x) for x in artist_ids if isinstance(x, str)]
    artists = {s.id: s.to_dict() for s in db.get_all(refs)}
    items = []
    for doc in shown:
        data = doc.to_dict()
        snapshot = data["sourceIdeaSnapshot"]
        items.append(InboxItem(
            submissionId=doc.id, artistId=data["artistId"],
            artistNickname=artists.get(data["artistId"], {}).get("nickname", ""),
            sourceIdeaId=data["sourceIdeaId"], sourceIdeaSnapshot=snapshot,
            liked=data.get("liked", False), readAt=data.get("readAt"),
            createdAt=data["createdAt"], expiresAt=data["expiresAt"],
        ))
    return InboxPage(items=items, nextCursor=_cursor_encode("inbox", uid, shown[-1].id)
                     if more and shown else None, serverTime=now)


def _list_history(db, uid: str, query: PageQuery) -> HistoryPage:
    now = utc_now()
    coll = db.collection("users").document(uid).collection("drawnHistory")
    request = coll.order_by("submittedAt", direction=firestore.Query.DESCENDING).order_by(
        "__name__", direction=firestore.Query.DESCENDING)
    cursor = _page_query(db, coll, uid, query, "drawn-history")
    if cursor:
        request = request.start_after(cursor)
    docs = list(request.limit(query.limit + 1).stream())
    shown, more = docs[:query.limit], len(docs) > query.limit
    ideas = {}
    ids = list(dict.fromkeys(d.to_dict().get("ideaId") for d in shown))
    refs = [db.collection("ideas").document(x) for x in ids if isinstance(x, str)]
    snapshots = {s.id: s for s in db.get_all(refs)}
    owner_ids = []
    for idea_id, snap in snapshots.items():
        if snap.exists:
            owner_ids.append(snap.to_dict().get("ownerId"))
    owner_refs = [db.collection("users").document(x) for x in dict.fromkeys(owner_ids) if isinstance(x, str)]
    owners = {s.id: s.to_dict() for s in db.get_all(owner_refs)}
    for idea_id, snap in snapshots.items():
        if not snap.exists:
            continue
        data = snap.to_dict()
        owner = owners.get(data.get("ownerId"), {})
        ideas[idea_id] = DrawnIdea(
            ideaId=idea_id, ownerId=data["ownerId"], ownerNickname=owner.get("nickname", ""),
            title=data["title"], description=data["description"], tags=data.get("tags", []),
            createdAt=data["createdAt"], publishedUntil=data["publishedUntil"],
            acceptUntil=data["acceptUntil"],
        )
    items = []
    for doc in shown:
        data = doc.to_dict()
        idea_id = data["ideaId"]
        items.append(HistoryItem(
            submissionId=doc.id, ideaId=idea_id, submittedAt=data["submittedAt"],
            lastLiked=data.get("lastLiked", False), idea=ideas.get(idea_id),
            ideaAvailability="available" if idea_id in ideas else "unavailable",
        ))
    return HistoryPage(items=items, nextCursor=_cursor_encode("drawn-history", uid, shown[-1].id)
                       if more and shown else None, serverTime=now)


def _mark_read(db, uid: str, submission_id: str) -> ReadResult:
    artwork_ref = db.collection("artworks").document(submission_id)
    user_ref = db.collection("users").document(uid)
    transaction = db.transaction()

    @firestore.transactional
    def apply(tx):
        user = user_ref.get(transaction=tx)
        artwork = artwork_ref.get(transaction=tx)
        if not user.exists:
            raise _unavailable()
        active(user.to_dict())
        if not artwork.exists:
            raise _unavailable()
        data = artwork.to_dict()
        if data.get("recipientId") != uid or data.get("deletedAt") is not None or data.get("expiresAt") <= utc_now():
            raise _unavailable()
        read_at = data.get("readAt")
        if read_at is None:
            read_at = utc_now()
            tx.update(artwork_ref, {"readAt": read_at})
        return ReadResult(submissionId=submission_id, readAt=read_at)

    return apply(transaction)


def _like(db, uid: str, submission_id: str) -> LikeResult:
    artwork_ref = db.collection("artworks").document(submission_id)
    user_ref = db.collection("users").document(uid)
    transaction = db.transaction()

    @firestore.transactional
    def apply(tx):
        user = user_ref.get(transaction=tx)
        artwork = artwork_ref.get(transaction=tx)
        if not user.exists:
            raise _unavailable()
        active(user.to_dict())
        if not artwork.exists:
            raise _unavailable()
        data = artwork.to_dict()
        if data.get("recipientId") != uid or data.get("deletedAt") is not None or data.get("expiresAt") <= utc_now():
            raise _unavailable()
        if not data.get("liked", False):
            artist_id = data["artistId"]
            artist_ref = db.collection("users").document(artist_id)
            artist = artist_ref.get(transaction=tx)
            if not artist.exists:
                raise _unavailable()
            active(artist.to_dict())
            history_ref = artist_ref.collection("drawnHistory").document(submission_id)
            history = history_ref.get(transaction=tx)
            if not history.exists:
                raise _unavailable()
            tx.update(artwork_ref, {"liked": True})
            tx.update(history_ref, {"lastLiked": True})
            tx.update(artist_ref, {"likesReceived": firestore.Increment(1)})
        return LikeResult(submissionId=submission_id, liked=True)

    return apply(transaction)


@router.get("/me/artworks/inbox", response_model=InboxPage)
async def get_inbox(user: ActiveUser, query: PageQuery = Query()):
    return await run_in_threadpool(lambda: _list_inbox(database(), user["uid"], query))


@router.get("/me/drawn-history", response_model=HistoryPage)
async def get_drawn_history(user: ActiveUser, query: PageQuery = Query()):
    return await run_in_threadpool(lambda: _list_history(database(), user["uid"], query))


@router.post("/artworks/{submission_id}/read", response_model=ReadResult)
async def read_artwork(submission_id: str, user: ActiveUser):
    return await run_in_threadpool(lambda: _mark_read(database(), user["uid"], submission_id))


@router.post("/artworks/{submission_id}/like", response_model=LikeResult)
async def like_artwork(submission_id: str, user: ActiveUser):
    return await run_in_threadpool(lambda: _like(database(), user["uid"], submission_id))
