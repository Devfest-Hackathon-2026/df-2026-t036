"""Idea, slot, and pin APIs backed by Firestore transactions."""

from __future__ import annotations

import base64
import hashlib
import json
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import Field, field_validator
from starlette.concurrency import run_in_threadpool

from .auth import ActiveUser, GoogleUid, active
from .clock import UtcDatetime, utc_now
from .errors import ApiError
from .post_limits import consume_post
from .firebase import database
from .schemas import ApiModel, InputModel, Page, PageQuery, TimelineQuery


router = APIRouter(prefix="/api/v1")
MAX_SLOTS = 5
MAX_PINS = 5
PUBLISHED_FOR = timedelta(days=7)
ACCEPTED_FOR = timedelta(days=30)


class IdeaCreate(InputModel):
    ideaId: str = Field(min_length=36, max_length=36)
    title: str = Field(min_length=1, max_length=40)
    description: str = Field(min_length=1, max_length=600)
    tags: list[str] = Field(default_factory=list, max_length=5)

    @field_validator("ideaId")
    @classmethod
    def validate_idea_id(cls, value: str) -> str:
        try:
            parsed = UUID(value)
        except ValueError as exc:
            raise ValueError("ideaId must be a UUID v4") from exc
        if parsed.version != 4 or str(parsed) != value.lower():
            raise ValueError("ideaId must be a canonical UUID v4")
        return str(parsed)

    @field_validator("tags")
    @classmethod
    def validate_tags(cls, values: list[str]) -> list[str]:
        if any(not value or len(value) > 20 for value in values):
            raise ValueError("tags must contain 1 to 20 characters")
        return list(dict.fromkeys(values))


class Idea(ApiModel):
    ideaId: str
    ownerId: str
    ownerNickname: str
    title: str
    description: str
    tags: list[str]
    createdAt: UtcDatetime
    publishedUntil: UtcDatetime
    acceptUntil: UtcDatetime
    canPin: bool
    canSubmit: bool
    # 一覧の色分けに使い、送信可否とは分けて本人・描画履歴を示す。
    isOwn: bool = False
    hasDrawn: bool = False


class IdeaPage(Page[Idea]):
    # 表示ページや選択条件に依存しない、掲載中のお題全体のタグ候補。
    tags: list[str] = Field(default_factory=list)


class SlotIdea(ApiModel):
    ideaId: str
    expiresAt: UtcDatetime
    title: str | None = None


class EmptySlot(ApiModel):
    """空きスロットはnullではなく空のオブジェクトで返す。"""


class Slots(ApiModel):
    maxSlots: int
    slots: dict[str, SlotIdea | EmptySlot]
    serverTime: UtcDatetime


class Pins(ApiModel):
    maxPins: int
    items: list[Idea]
    serverTime: UtcDatetime


def _resource_unavailable() -> ApiError:
    return ApiError(404, "RESOURCE_UNAVAILABLE", "参照できません。")


def _parse_idea_id(idea_id: str) -> str:
    try:
        parsed = UUID(idea_id)
    except ValueError as exc:
        raise ApiError(422, "INVALID_INPUT", "ideaIdを確認してください。") from exc
    if parsed.version != 4 or str(parsed) != idea_id.lower():
        raise ApiError(422, "INVALID_INPUT", "ideaIdを確認してください。")
    return str(parsed)


def _submission_id(uid: str, idea_id: str) -> str:
    """Use the stable artist/idea key defined by DB_v0.md."""
    return hashlib.sha256(uid.encode("utf-8") + b"\x00" + idea_id.encode("utf-8")).hexdigest()


def _cursor_encode(scope: str, uid: str, document_id: str) -> str:
    payload = json.dumps(
        {"v": 1, "scope": scope, "uid": uid, "id": document_id},
        separators=(",", ":"),
    ).encode("utf-8")
    return base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")


def _cursor_decode(cursor: str, scope: str, uid: str) -> str:
    try:
        raw = base64.b64decode(cursor + "=" * (-len(cursor) % 4), altchars=b"-_", validate=True)
        payload = json.loads(raw)
        document_id = payload["id"]
        if (
            payload.get("v") != 1
            or payload.get("scope") != scope
            or payload.get("uid") != uid
            or not isinstance(document_id, str)
            or not document_id
            or "/" in document_id
        ):
            raise ValueError("cursor scope mismatch")
        return document_id
    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        raise ApiError(422, "INVALID_INPUT", "一覧カーソルを確認してください。") from exc


def _cursor_snapshot(db, cursor: str | None, scope: str, uid: str):
    if cursor is None:
        return None
    document_id = _cursor_decode(cursor, scope, uid)
    snapshot = db.collection("ideas").document(document_id).get()
    if not snapshot.exists:
        raise ApiError(422, "INVALID_INPUT", "一覧を更新して最初から取得してください。")
    return snapshot


def _user_data(db, uid: str, *, transaction=None) -> dict[str, Any]:
    snapshot = db.collection("users").document(uid).get(transaction=transaction)
    if not snapshot.exists:
        raise _resource_unavailable()
    data = snapshot.to_dict()
    active(data)
    return data


def _pin_document(db, uid: str, *, transaction=None) -> dict[str, Any]:
    snapshot = db.collection("userPins").document(uid).get(transaction=transaction)
    return snapshot.to_dict() if snapshot.exists else {"maxPins": MAX_PINS, "pinnedIdeaIds": []}


def _valid_pin_ids(db, uid: str, pin_ids: list[str], now: datetime) -> list[str]:
    """Filter stale pins without relying on delayed Scheduler cleanup."""
    ids = list(dict.fromkeys(value for value in pin_ids if isinstance(value, str)))
    if not ids:
        return []
    refs = [db.collection("ideas").document(value) for value in ids]
    snapshots = {snapshot.id: snapshot for snapshot in db.get_all(refs)}
    candidate_data: dict[str, dict[str, Any]] = {}
    for idea_id in ids:
        snapshot = snapshots.get(idea_id)
        if not snapshot or not snapshot.exists:
            continue
        data = snapshot.to_dict()
        if (
            data.get("deletedAt") is None
            and data.get("acceptUntil") is not None
            and data["acceptUntil"] > now
            and data.get("ownerId") != uid
        ):
            candidate_data[idea_id] = data
    if not candidate_data:
        return []
    owner_ids = list(dict.fromkeys(
        data["ownerId"]
        for data in candidate_data.values()
        if isinstance(data.get("ownerId"), str) and data["ownerId"] != uid
    ))
    owner_refs = [db.collection("users").document(owner_id) for owner_id in owner_ids]
    active_owners = {
        snapshot.id
        for snapshot in db.get_all(owner_refs)
        if snapshot.exists and snapshot.to_dict().get("status") == "active"
    }
    return [
        idea_id
        for idea_id, data in candidate_data.items()
        if data.get("ownerId") in active_owners
    ]


def _viewer_pin_ids(db, uid: str, now: datetime) -> list[str]:
    return _valid_pin_ids(db, uid, _pin_document(db, uid).get("pinnedIdeaIds", []), now)


def _has_drawn(db, uid: str, idea_id: str) -> bool:
    ref = (
        db.collection("users")
        .document(uid)
        .collection("drawnHistory")
        .document(_submission_id(uid, idea_id))
    )
    return ref.get().exists


def _idea_dto(
    idea_id: str,
    data: dict[str, Any],
    owner_nickname: str,
    owner_active: bool,
    viewer_uid: str,
    pin_ids: list[str],
    drawn_ids: set[str],
    now: datetime,
) -> Idea:
    owner_id = data["ownerId"]
    published_until = data["publishedUntil"]
    accept_until = data["acceptUntil"]
    can_pin = (
        owner_id != viewer_uid
        and owner_active
        and data.get("deletedAt") is None
        and published_until > now
        and idea_id not in pin_ids
        and len(pin_ids) < MAX_PINS
    )
    can_submit = (
        owner_id != viewer_uid
        and owner_active
        and data.get("deletedAt") is None
        and idea_id not in drawn_ids
        and now < accept_until
        and (now < published_until or idea_id in pin_ids)
    )
    return Idea(
        ideaId=idea_id,
        ownerId=owner_id,
        ownerNickname=owner_nickname,
        title=data["title"],
        description=data["description"],
        tags=data.get("tags", []),
        createdAt=data["createdAt"],
        publishedUntil=published_until,
        acceptUntil=accept_until,
        canPin=can_pin,
        canSubmit=can_submit,
        isOwn=owner_id == viewer_uid,
        hasDrawn=idea_id in drawn_ids,
    )


def _make_ideas(db, snapshots, viewer_uid: str, now: datetime) -> list[Idea]:
    snapshots = list(snapshots)
    if not snapshots:
        return []
    data_by_id = {snapshot.id: snapshot.to_dict() for snapshot in snapshots}
    owner_ids = list(dict.fromkeys(data["ownerId"] for data in data_by_id.values()))
    owner_refs = [db.collection("users").document(uid) for uid in owner_ids]
    owners = {snapshot.id: snapshot.to_dict() for snapshot in db.get_all(owner_refs)}
    pin_ids = _viewer_pin_ids(db, viewer_uid, now)

    history_doc_to_idea = {
        _submission_id(viewer_uid, idea_id): idea_id for idea_id in data_by_id
    }
    history_refs = [
        db.collection("users")
        .document(viewer_uid)
        .collection("drawnHistory")
        .document(history_doc_id)
        for history_doc_id in history_doc_to_idea
    ]
    history_ids = {
        history_doc_to_idea[history.id]
        for history in db.get_all(history_refs)
        if history.exists and history.id in history_doc_to_idea
    }

    return [
        _idea_dto(
            snapshot.id,
            data_by_id[snapshot.id],
            owners.get(data_by_id[snapshot.id]["ownerId"], {}).get("nickname", ""),
            owners.get(data_by_id[snapshot.id]["ownerId"], {}).get("status") == "active",
            viewer_uid,
            pin_ids,
            history_ids,
            now,
        )
        for snapshot in snapshots
    ]


def _list_ideas(db, *, uid: str, query: PageQuery, own: bool) -> IdeaPage:
    now = utc_now()
    scope = "own-ideas" if own else "timeline"
    collection = db.collection("ideas")
    tag = query.tag if isinstance(query, TimelineQuery) and not own else None
    if tag is not None:
        # カーソルを選択タグへ結び付け、別の検索条件での再利用を拒否する。
        scope += ":tag:" + tag
    if own:
        firestore_query = (
            collection.where(filter=FieldFilter("ownerId", "==", uid))
            .where(filter=FieldFilter("deletedAt", "==", None))
            .order_by("createdAt", direction=firestore.Query.DESCENDING)
            .order_by("__name__", direction=firestore.Query.DESCENDING)
        )
    else:
        firestore_query = (
            collection.where(filter=FieldFilter("deletedAt", "==", None))
            .where(filter=FieldFilter("publishedUntil", ">", now))
            .order_by("publishedUntil", direction=firestore.Query.DESCENDING)
            .order_by("__name__", direction=firestore.Query.DESCENDING)
        )
    tags = []
    if not own:
        # 全ページの候補を維持し、絞り込み後も別のタグへ切り替えられる。
        tags = sorted({
            value for snapshot in firestore_query.select(["tags"]).stream()
            for value in snapshot.to_dict().get("tags", [])
            if isinstance(value, str) and value
        })
    if tag is not None:
        firestore_query = firestore_query.where(filter=FieldFilter("tags", "array_contains", tag))
    cursor_snapshot = _cursor_snapshot(db, query.cursor, scope, uid)
    if cursor_snapshot is not None:
        firestore_query = firestore_query.start_after(cursor_snapshot)
    documents = list(firestore_query.limit(query.limit + 1).stream())
    has_more = len(documents) > query.limit
    page_documents = documents[: query.limit]
    items = _make_ideas(db, page_documents, uid, now)
    next_cursor = (
        _cursor_encode(scope, uid, page_documents[-1].id)
        if has_more and page_documents
        else None
    )
    return IdeaPage(items=items, nextCursor=next_cursor, serverTime=now, tags=tags)


def _get_idea(db, uid: str, idea_id: str) -> Idea:
    now = utc_now()
    snapshot = db.collection("ideas").document(idea_id).get()
    if not snapshot.exists:
        raise _resource_unavailable()
    data = snapshot.to_dict()
    if data.get("deletedAt") is not None:
        raise _resource_unavailable()

    owner_id = data["ownerId"]
    pin_ids = _viewer_pin_ids(db, uid, now)
    drawn = _has_drawn(db, uid, idea_id) if owner_id != uid else False
    published = data["publishedUntil"]
    accepting = data["acceptUntil"]
    can_view = (
        now < published
        or (now < accepting and (owner_id == uid or idea_id in pin_ids or drawn))
        or (now >= accepting and (owner_id == uid or drawn))
    )
    if not can_view:
        raise _resource_unavailable()

    owner = db.collection("users").document(owner_id).get()
    if not owner.exists:
        raise _resource_unavailable()
    owner_data = owner.to_dict()
    drawn_ids = {idea_id} if drawn else set()
    return _idea_dto(
        idea_id,
        data,
        owner_data.get("nickname", ""),
        owner_data.get("status") == "active",
        uid,
        pin_ids,
        drawn_ids,
        now,
    )


def _create_idea(db, uid: str, body: IdeaCreate) -> tuple[Idea, bool]:
    user_ref = db.collection("users").document(uid)
    idea_ref = db.collection("ideas").document(body.ideaId)
    slots_ref = db.collection("userSlots").document(uid)
    transaction = db.transaction()

    @firestore.transactional
    def create(transaction):
        user_snapshot = user_ref.get(transaction=transaction)
        idea_snapshot = idea_ref.get(transaction=transaction)
        slots_snapshot = slots_ref.get(transaction=transaction)

        if not user_snapshot.exists:
            raise _resource_unavailable()
        user = user_snapshot.to_dict()
        active(user)

        if idea_snapshot.exists:
            existing = idea_snapshot.to_dict()
            if existing.get("ownerId") != uid:
                raise _resource_unavailable()
            if existing.get("deletedAt") is not None:
                raise ApiError(409, "IDEA_ID_CONFLICT", "このideaIdは再利用できません。")
            if any(existing.get(key) != getattr(body, key) for key in ("title", "description", "tags")):
                raise ApiError(409, "IDEA_ID_CONFLICT", "同じideaIdに異なる入力は使えません。")
            return existing, False

        if not slots_snapshot.exists:
            raise ApiError(503, "SERVICE_UNAVAILABLE", "掲載枠を読み込めません。")
        slots_data = slots_snapshot.to_dict()
        slot_map = dict(slots_data.get("slots", {}))
        now = utc_now()
        free_slot = None
        for index in range(MAX_SLOTS):
            slot_key = f"slot_{index}"
            slot = slot_map.get(slot_key)
            if not slot or slot.get("expiresAt") <= now:
                free_slot = slot_key
                break
        if free_slot is None:
            raise ApiError(409, "SLOT_LIMIT_REACHED", "掲載中のお題は5件までです。")

        created = {
            "ownerId": uid,
            "title": body.title,
            "description": body.description,
            "tags": body.tags,
            "createdAt": now,
            "publishedUntil": now + PUBLISHED_FOR,
            "acceptUntil": now + ACCEPTED_FOR,
            "deletedAt": None,
        }
        slot_map[free_slot] = {"ideaId": body.ideaId, "expiresAt": created["publishedUntil"]}
        consume_post(transaction, user_ref, user, "idea", now)
        transaction.create(idea_ref, created)
        transaction.update(slots_ref, {"slots": slot_map})
        transaction.update(user_ref, {"ideaCount": int(user.get("ideaCount", 0)) + 1})
        return created, True

    data, created = create(transaction)
    owner = db.collection("users").document(uid).get().to_dict() or {}
    result = _idea_dto(
        body.ideaId, data, owner.get("nickname", ""),
        owner.get("status") == "active", uid, [], set(), utc_now()
    )
    return result, created


def _delete_idea(db, uid: str, idea_id: str) -> None:
    user_ref = db.collection("users").document(uid)
    idea_ref = db.collection("ideas").document(idea_id)
    slots_ref = db.collection("userSlots").document(uid)
    transaction = db.transaction()

    @firestore.transactional
    def delete(transaction):
        user_snapshot = user_ref.get(transaction=transaction)
        idea_snapshot = idea_ref.get(transaction=transaction)
        slots_snapshot = slots_ref.get(transaction=transaction)
        if not user_snapshot.exists:
            raise _resource_unavailable()
        user = user_snapshot.to_dict()
        active(user)
        if not idea_snapshot.exists:
            raise _resource_unavailable()
        idea = idea_snapshot.to_dict()
        if idea.get("ownerId") != uid:
            raise _resource_unavailable()
        if idea.get("deletedAt") is not None:
            return

        now = utc_now()
        transaction.update(idea_ref, {"deletedAt": now})
        if slots_snapshot.exists:
            slot_data = slots_snapshot.to_dict()
            slot_map = dict(slot_data.get("slots", {}))
            for key, slot in slot_map.items():
                if slot and slot.get("ideaId") == idea_id:
                    # 全Mapを更新することで、ideaId等の古い項目を残さない。
                    slot_map[key] = {}
            transaction.update(slots_ref, {"slots": slot_map})
        transaction.update(user_ref, {"ideaCount": max(0, int(user.get("ideaCount", 0)) - 1)})

    delete(transaction)


def _get_slots(db, uid: str) -> Slots:
    now = utc_now()
    snapshot = db.collection("userSlots").document(uid).get()
    if not snapshot.exists:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "掲載枠を読み込めません。")
    stored = snapshot.to_dict()
    result: dict[str, SlotIdea | EmptySlot] = {}
    for index in range(MAX_SLOTS):
        key = f"slot_{index}"
        slot = stored.get("slots", {}).get(key)
        if not slot or slot.get("expiresAt") <= now:
            result[key] = EmptySlot()
            continue
        idea_snapshot = db.collection("ideas").document(slot["ideaId"]).get()
        if not idea_snapshot.exists:
            result[key] = EmptySlot()
            continue
        idea = idea_snapshot.to_dict()
        if idea.get("deletedAt") is not None:
            result[key] = EmptySlot()
            continue
        result[key] = SlotIdea(
            ideaId=slot["ideaId"], expiresAt=slot["expiresAt"], title=idea.get("title")
        )
    return Slots(maxSlots=MAX_SLOTS, slots=result, serverTime=now)


def _add_pin(db, uid: str, idea_id: str) -> None:
    user_ref = db.collection("users").document(uid)
    idea_ref = db.collection("ideas").document(idea_id)
    pins_ref = db.collection("userPins").document(uid)
    transaction = db.transaction()

    @firestore.transactional
    def add(transaction):
        user_snapshot = user_ref.get(transaction=transaction)
        idea_snapshot = idea_ref.get(transaction=transaction)
        pins_snapshot = pins_ref.get(transaction=transaction)
        if not user_snapshot.exists:
            raise _resource_unavailable()
        user = user_snapshot.to_dict()
        active(user)
        if not idea_snapshot.exists:
            raise _resource_unavailable()
        idea = idea_snapshot.to_dict()
        if idea.get("deletedAt") is not None:
            raise _resource_unavailable()
        if idea.get("ownerId") == uid:
            raise ApiError(403, "FORBIDDEN", "自分のお題はピンできません。")
        now = utc_now()

        pin_data = pins_snapshot.to_dict() if pins_snapshot.exists else {"pinnedIdeaIds": []}
        raw_ids = pin_data.get("pinnedIdeaIds", [])
        unique_ids = list(dict.fromkeys(value for value in raw_ids if isinstance(value, str)))
        pinned_ideas: dict[str, dict[str, Any] | None] = {idea_id: idea}
        for existing_id in unique_ids:
            if existing_id not in pinned_ideas:
                existing_snapshot = db.collection("ideas").document(existing_id).get(transaction=transaction)
                pinned_ideas[existing_id] = existing_snapshot.to_dict() if existing_snapshot.exists else None

        owner_ids = list(dict.fromkeys(
            pinned_idea.get("ownerId")
            for pinned_idea in pinned_ideas.values()
            if pinned_idea and isinstance(pinned_idea.get("ownerId"), str)
            and pinned_idea.get("ownerId") != uid
        ))
        owner_data = {uid: user}
        for owner_id in owner_ids:
            owner_snapshot = db.collection("users").document(owner_id).get(transaction=transaction)
            owner_data[owner_id] = owner_snapshot.to_dict() if owner_snapshot.exists else None

        valid_ids = [
            existing_id
            for existing_id in unique_ids
            if pinned_ideas.get(existing_id)
            and pinned_ideas[existing_id].get("deletedAt") is None
            and pinned_ideas[existing_id].get("acceptUntil") is not None
            and pinned_ideas[existing_id]["acceptUntil"] > now
            and pinned_ideas[existing_id].get("ownerId") != uid
            and (owner_data.get(pinned_ideas[existing_id].get("ownerId")) or {}).get("status") == "active"
        ]
        already_pinned = idea_id in valid_ids
        if not already_pinned and (
            now >= idea["publishedUntil"]
            or now >= idea["acceptUntil"]
            or (owner_data.get(idea.get("ownerId")) or {}).get("status") != "active"
        ):
            raise ApiError(409, "IDEA_NOT_PINNABLE", "このお題は新しくピンできません。")
        if not already_pinned and len(valid_ids) >= MAX_PINS:
            raise ApiError(409, "PIN_LIMIT_REACHED", "ピンは5件までです。")
        updated_ids = valid_ids if already_pinned else [*valid_ids, idea_id]
        if not pins_snapshot.exists or updated_ids != raw_ids:
            transaction.set(pins_ref, {"maxPins": MAX_PINS, "pinnedIdeaIds": updated_ids})

    add(transaction)


def _remove_pin(db, uid: str, idea_id: str) -> None:
    user_ref = db.collection("users").document(uid)
    pins_ref = db.collection("userPins").document(uid)
    transaction = db.transaction()

    @firestore.transactional
    def remove(transaction):
        user_snapshot = user_ref.get(transaction=transaction)
        pins_snapshot = pins_ref.get(transaction=transaction)
        if not user_snapshot.exists:
            raise _resource_unavailable()
        active(user_snapshot.to_dict())
        if pins_snapshot.exists:
            pin_data = pins_snapshot.to_dict()
            ids = [value for value in pin_data.get("pinnedIdeaIds", []) if value != idea_id]
            if ids != pin_data.get("pinnedIdeaIds", []):
                transaction.update(pins_ref, {"pinnedIdeaIds": ids})
        else:
            transaction.create(pins_ref, {"maxPins": MAX_PINS, "pinnedIdeaIds": []})

    remove(transaction)


def _get_pins(db, uid: str) -> Pins:
    now = utc_now()
    pin_data = _pin_document(db, uid)
    valid_ids = _valid_pin_ids(db, uid, pin_data.get("pinnedIdeaIds", []), now)
    snapshots = [db.collection("ideas").document(idea_id).get() for idea_id in valid_ids]
    items = _make_ideas(db, snapshots, uid, now)
    return Pins(maxPins=MAX_PINS, items=items, serverTime=now)


@router.get("/ideas", response_model=IdeaPage)
async def list_timeline(
    query: Annotated[TimelineQuery, Query()],
    user: ActiveUser,
):
    """Return current public timeline ideas in stable cursor order."""
    return await run_in_threadpool(
        lambda: _list_ideas(database(), uid=user["uid"], query=query, own=False)
    )


@router.post(
    "/ideas",
    response_model=Idea,
    status_code=201,
    responses={200: {"model": Idea, "description": "Idempotent replay of the same request."}},
)
async def create_idea(
    body: IdeaCreate,
    request: Request,
    response: Response,
    uid: GoogleUid,
):
    """Create one idea and reserve one of the user's five active slots."""
    idea, created = await run_in_threadpool(lambda: _create_idea(database(), uid, body))
    response.status_code = 201 if created else 200
    return idea


@router.get("/ideas/{idea_id}", response_model=Idea)
async def get_idea(idea_id: str, user: ActiveUser):
    """Apply publication, pin, submission-history, and ownership visibility rules."""
    parsed_id = _parse_idea_id(idea_id)
    return await run_in_threadpool(lambda: _get_idea(database(), user["uid"], parsed_id))


@router.delete("/ideas/{idea_id}", status_code=204, response_model=None)
async def delete_idea(idea_id: str, uid: GoogleUid):
    """Soft-delete the owner's idea, release its matching slot, and decrement once."""
    parsed_id = _parse_idea_id(idea_id)
    await run_in_threadpool(lambda: _delete_idea(database(), uid, parsed_id))
    return Response(status_code=204)


@router.get("/me/ideas", response_model=IdeaPage)
async def list_my_ideas(
    query: Annotated[PageQuery, Query()],
    user: ActiveUser,
):
    """Return the caller's undeleted ideas including expired history."""
    return await run_in_threadpool(
        lambda: _list_ideas(database(), uid=user["uid"], query=query, own=True)
    )


@router.get("/me/slots", response_model=Slots)
async def get_my_slots(user: ActiveUser):
    """Return five slots, presenting expired entries as available."""
    return await run_in_threadpool(lambda: _get_slots(database(), user["uid"]))


@router.get("/me/pins", response_model=Pins)
async def list_my_pins(user: ActiveUser):
    """Return valid pinned ideas, filtering expired or deleted ideas immediately."""
    return await run_in_threadpool(lambda: _get_pins(database(), user["uid"]))


@router.post("/pins/{idea_id}", status_code=204, response_model=None)
async def add_pin(idea_id: str, uid: GoogleUid):
    """Pin another user's idea before its seven-day publication deadline."""
    parsed_id = _parse_idea_id(idea_id)
    await run_in_threadpool(lambda: _add_pin(database(), uid, parsed_id))
    return Response(status_code=204)


@router.delete("/pins/{idea_id}", status_code=204, response_model=None)
async def remove_pin(idea_id: str, uid: GoogleUid):
    """Remove a pin idempotently, including when its idea has disappeared."""
    parsed_id = _parse_idea_id(idea_id)
    await run_in_threadpool(lambda: _remove_pin(database(), uid, parsed_id))
    return Response(status_code=204)
