"""画像検証・審査・保存と、冪等な投稿確定および未確定画像の回収。"""

from datetime import timedelta
import hashlib
from io import BytesIO
import logging
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, Request, Response, UploadFile
from firebase_admin import firestore
from google.api_core.exceptions import NotFound
from google.cloud import storage
from google.cloud.firestore_v1.base_query import FieldFilter
from PIL import Image
from starlette.concurrency import run_in_threadpool

from .auth import ActiveUser, active
from .cleanup import cleanup_identity
from .clock import utc_now
from .errors import ApiError
from .firebase import database
from .ideas import _parse_idea_id, _submission_id
from .image_processing import ImageProcessingError, normalize_image
from .upload_limits import MAX_DEMO_UPLOAD_BYTES
from .vision_demo import MAX_INLINE_IMAGE_BYTES, analyze_image
from .vision_policy import POLICY_VERSION

logger = logging.getLogger(__name__)
router = APIRouter(prefix='/api/v1')
internal_router = APIRouter(prefix='/api/v1/internal')
LEASE = timedelta(minutes=30)


def unavailable():
    return ApiError(404, 'RESOURCE_UNAVAILABLE', '参照できません。')


def references(db, uid, idea_id):
    sid = _submission_id(uid, idea_id)
    user = db.collection('users').document(uid)
    return sid, user, db.collection('ideas').document(idea_id), user.collection('drawnHistory').document(sid), db.collection('artworkSubmissions').document(sid)


def check_eligibility(db, tx, uid, idea_id, user_ref, idea_ref, history_ref):
    """全読取を先に行い、受付期限・ピン・両当事者の状態を再確認する。"""
    user = user_ref.get(transaction=tx)
    idea = idea_ref.get(transaction=tx)
    history = history_ref.get(transaction=tx)
    pins = db.collection('userPins').document(uid).get(transaction=tx)
    if not user.exists or not idea.exists:
        raise unavailable()
    active(user.to_dict())
    data = idea.to_dict()
    owner = db.collection('users').document(data['ownerId']).get(transaction=tx)
    now = utc_now()
    if (not owner.exists or owner.to_dict().get('status') != 'active'
            or data['ownerId'] == uid or data.get('deletedAt') is not None
            or now >= data['acceptUntil']
            or (now >= data['publishedUntil'] and idea_id not in (pins.to_dict() or {}).get('pinnedIdeaIds', []))):
        raise unavailable()
    if history.exists:
        raise ApiError(409, 'ALREADY_SUBMITTED', 'このお題には送信済みです。')
    return data, now


def reserve(db, uid, idea_id, digest, bucket_name):
    sid, user, idea, history, submission = references(db, uid, idea_id)
    token = uuid4().hex
    attempt = db.collection('artworkUploads').document(token)

    @firestore.transactional
    def apply(tx):
        old = submission.get(transaction=tx)
        data = old.to_dict() if old.exists else {}
        if data.get('status') == 'committed':
            if data['digest'] != digest:
                raise ApiError(409, 'ALREADY_SUBMITTED', 'このお題には送信済みです。')
            return data['result'], None
        if data.get('status') == 'processing' and data['expiresAt'] > utc_now():
            raise ApiError(409, 'SUBMISSION_BUSY', '送信処理中です。時間をおいて再試行してください。')
        check_eligibility(db, tx, uid, idea_id, user, idea, history)
        expires = utc_now() + LEASE
        path = f'artworks/{sid}/{token}.webp'
        # アップロード前に回収可能な記録を残す。試行ごとに別パスを使う。
        tx.set(submission, {'status': 'processing', 'token': token, 'digest': digest, 'expiresAt': expires})
        tx.set(attempt, {'submissionId': sid, 'token': token, 'bucket': bucket_name,
                         'storagePath': path, 'status': 'processing', 'expiresAt': expires})
        return None, {'submissionId': sid, 'token': token, 'storagePath': path, 'bucket': bucket_name}

    return apply(db.transaction())


def finalize(db, uid, idea_id, attempt, digest):
    sid, user, idea, history, submission = references(db, uid, idea_id)
    upload = db.collection('artworkUploads').document(attempt['token'])
    artwork = db.collection('artworks').document(sid)

    @firestore.transactional
    def apply(tx):
        reservation = submission.get(transaction=tx).to_dict() or {}
        upload_data = upload.get(transaction=tx).to_dict() or {}
        if reservation.get('status') == 'committed' and reservation.get('digest') == digest:
            return reservation['result']
        if (reservation.get('token') != attempt['token'] or reservation.get('status') != 'processing'
                or upload_data.get('status') != 'processing' or reservation['expiresAt'] <= utc_now()):
            raise ApiError(409, 'SUBMISSION_EXPIRED', '送信処理の有効期限が切れました。再試行してください。')
        data, now = check_eligibility(db, tx, uid, idea_id, user, idea, history)
        result = {'submissionId': sid, 'submittedAt': now.isoformat()}
        # 作品・履歴・累計・完了記録を同時に確定し、再送で累計を増やさない。
        tx.set(artwork, {'artistId': uid, 'recipientId': data['ownerId'], 'sourceIdeaId': idea_id,
                        'sourceIdeaSnapshot': {key: data[key] for key in ('title', 'description', 'tags', 'ownerId')},
                        'storagePath': attempt['storagePath'], 'storageBucket': attempt['bucket'],
                        'contentType': 'image/webp', 'liked': False, 'readAt': None,
                        'createdAt': now, 'expiresAt': now + timedelta(days=7), 'deletedAt': None,
                        'visionPolicyVersion': POLICY_VERSION})
        tx.set(history, {'artistId': uid, 'ideaId': idea_id, 'submittedAt': now, 'lastLiked': False})
        tx.update(user, {'drawnCount': firestore.Increment(1)})
        tx.update(submission, {'status': 'committed', 'result': result})
        tx.update(upload, {'status': 'committed'})
        return result

    return apply(db.transaction())


def fence_attempt(db, token, *, force=False):
    """DB確定の成否が曖昧な場合も、確定画像を削除しないよう先に状態を確定する。"""
    ref = db.collection('artworkUploads').document(token)

    @firestore.transactional
    def apply(tx):
        snap = ref.get(transaction=tx)
        if not snap.exists:
            return None
        data = snap.to_dict()
        submission = db.collection('artworkSubmissions').document(data['submissionId'])
        current = submission.get(transaction=tx).to_dict() or {}
        if data['status'] == 'committed' or (current.get('status') == 'committed' and current.get('token') == token):
            tx.delete(ref)
            return None
        if not force and data['expiresAt'] > utc_now():
            return None
        tx.update(ref, {'status': 'abandoned', 'expiresAt': utc_now()})
        if current.get('token') == token and current.get('status') == 'processing':
            tx.update(submission, {'status': 'failed'})
        return data

    return apply(db.transaction())


def recover_attempt(db, token, storage_client, *, force=False):
    data = fence_attempt(db, token, force=force)
    if data is None:
        return
    try:
        storage_client.bucket(data['bucket']).blob(data['storagePath']).delete(timeout=60)
    except NotFound:
        pass
    # 削除失敗時は記録を残し、内部の回収APIから再実行する。
    db.collection('artworkUploads').document(token).delete()


def recover_untracked_objects(db, settings, client):
    """回収後に停止中の処理が再開して画像を置いた場合も、走査で回収する。"""
    if not settings.artwork_bucket:
        return 0
    cursor_ref = db.collection('cleanupState').document('artworkObjects')
    cursor = cursor_ref.get().to_dict() or {}
    iterator = client.list_blobs(settings.artwork_bucket, prefix='artworks/',
                                 page_token=cursor.get('pageToken'), max_results=100)
    scanned = 0
    for blob in iterator:
        scanned += 1
        parts = blob.name.split('/')
        if len(parts) != 3 or not parts[2].endswith('.webp'):
            continue
        sid, token = parts[1], parts[2][:-5]

        @firestore.transactional
        def can_delete(tx):
            # 同じスナップショットで確認し、確定済み画像や進行中の試行を守る。
            attempt = db.collection('artworkUploads').document(token).get(transaction=tx)
            artwork = db.collection('artworks').document(sid).get(transaction=tx)
            return (not attempt.exists and
                    (not artwork.exists or artwork.to_dict().get('storagePath') != blob.name))

        if can_delete(db.transaction()):
            try:
                blob.delete(if_generation_match=blob.generation, timeout=60)
            except NotFound:
                pass
    # 完成画像が多数あっても同じ先頭100件だけを走査し続けない。
    cursor_ref.set({'pageToken': iterator.next_page_token})
    return scanned


def submit(db, settings, uid, idea_id, raw):
    if not settings.artwork_bucket:
        raise ApiError(503, 'STORAGE_NOT_CONFIGURED', '作品の保存先が設定されていません。')
    digest = hashlib.sha256(raw).hexdigest()
    previous, attempt = reserve(db, uid, idea_id, digest, settings.artwork_bucket)
    if previous is not None:
        return previous, False
    client = None
    upload_started = False
    try:
        normalized = normalize_image(raw)
        if len(normalized.data) > MAX_INLINE_IMAGE_BYTES:
            raise ApiError(413, 'PAYLOAD_TOO_LARGE', '変換後の画像は7MB以下にしてください。')
        decision = analyze_image(normalized)['decision']
        if decision == 'rejected':
            raise ApiError(422, 'IMAGE_REJECTED', 'この画像は送信できません。')
        if decision != 'approved':
            raise ApiError(503, 'MODERATION_UNAVAILABLE', '画像を判定できませんでした。再試行してください。')
        # 審査済み画像だけを、作品用WebPへ変換して保存する。
        with Image.open(BytesIO(normalized.data)) as image:
            output = BytesIO()
            image.save(output, format='WEBP', quality=85, method=4)
        if len(output.getvalue()) > MAX_DEMO_UPLOAD_BYTES:
            raise ApiError(413, 'PAYLOAD_TOO_LARGE', '変換後の画像が大きすぎます。')
        client = storage.Client(project=settings.project_id)
        blob = client.bucket(attempt['bucket']).blob(attempt['storagePath'])
        upload_started = True
        blob.upload_from_string(output.getvalue(), content_type='image/webp', if_generation_match=0, timeout=60)
        return finalize(db, uid, idea_id, attempt, digest), True
    except Exception as exc:
        try:
            # 失敗時もDB状態を確認してから回収し、確定済み画像を守る。
            if upload_started:
                recover_attempt(db, attempt['token'], client, force=True)
            else:
                # 画像を送る前の失敗ではStorageへ接続する必要はない。
                record = fence_attempt(db, attempt['token'], force=True)
                if record is not None:
                    db.collection('artworkUploads').document(attempt['token']).delete()
        except Exception:
            logger.warning('artwork_recovery_pending')
        if isinstance(exc, ImageProcessingError):
            raise ApiError(422, exc.code, str(exc)) from exc
        if isinstance(exc, ApiError):
            raise
        logger.warning('artwork_submission_failed exceptionType=%s', type(exc).__name__)
        raise ApiError(503, 'SERVICE_UNAVAILABLE', '送信を確定できませんでした。同じ画像で再試行してください。') from exc
    finally:
        if client is not None:
            client.close()


@router.post('/artworks', status_code=201)
async def post_artwork(request: Request, response: Response, user: ActiveUser,
                       ideaId: str = Form(...), file: UploadFile = File(...)):
    """Flutterから画像を直接受け、審査成功後にだけ投稿を確定する。"""
    idea_id = _parse_idea_id(ideaId)
    raw = await file.read(MAX_DEMO_UPLOAD_BYTES + 1)
    if len(raw) > MAX_DEMO_UPLOAD_BYTES:
        raise ApiError(413, 'PAYLOAD_TOO_LARGE', '画像は20MB以下にしてください。')
    result, created = await run_in_threadpool(lambda: submit(database(), request.app.state.settings, user['uid'], idea_id, raw))
    response.status_code = 201 if created else 200
    return result


@internal_router.post('/artwork-cleanup', dependencies=[Depends(cleanup_identity)])
async def cleanup_uploads(request: Request):
    """期限切れ・失敗した試行を最大100件回収する。作品自体の期限削除とは別処理。"""
    if await request.body() or request.query_params:
        raise ApiError(422, 'INVALID_INPUT', 'リクエスト本文・クエリは不要です。')

    def recover():
        db = database()
        records = list(db.collection('artworkUploads').where(
            filter=FieldFilter('expiresAt', '<=', utc_now())).limit(100).stream())
        failed = 0
        scanned_objects = 0
        with storage.Client(project=request.app.state.settings.project_id) as client:
            for record in records:
                try:
                    recover_attempt(db, record.id, client)
                except Exception:
                    failed += 1
                    logger.warning('artwork_cleanup_failed')
            scanned_objects = recover_untracked_objects(db, request.app.state.settings, client)
        return {'scanned': len(records), 'scannedObjects': scanned_objects, 'failed': failed, 'hasMore': len(records) == 100}

    return await run_in_threadpool(recover)
