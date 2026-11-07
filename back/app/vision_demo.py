"""Authenticated, temporary Cloud Vision SafeSearch demo endpoint."""

from __future__ import annotations

import logging
import uuid

from fastapi import APIRouter, File, Request, UploadFile
from google.cloud import storage, vision
from starlette.concurrency import run_in_threadpool

from .auth import ActiveUser
from .config import Settings
from .errors import ApiError
from .image_processing import ImageProcessingError, normalize_image
from .upload_limits import MAX_DEMO_UPLOAD_BYTES

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1")


@router.post("/vision-demo")
async def inspect_image(
    request: Request,
    user: ActiveUser,
    file: UploadFile = File(...),
):
    """Normalize an uploaded image, inspect it from GCS, then remove the temp object."""
    settings: Settings = request.app.state.settings
    if not settings.vision_demo_bucket:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "Visionデモのバケット設定がありません。")

    raw = await file.read(MAX_DEMO_UPLOAD_BYTES + 1)
    if len(raw) > MAX_DEMO_UPLOAD_BYTES:
        raise ApiError(413, "PAYLOAD_TOO_LARGE", "画像は20MB以下にしてください。")
    try:
        # 重い画像処理を別スレッドへ移し、他のリクエストを待たせない。
        normalized = await run_in_threadpool(normalize_image, raw)
    except ImageProcessingError as exc:
        raise ApiError(422, exc.code, str(exc)) from exc

    extension = {"JPEG": "jpg", "PNG": "png"}.get(normalized.image_format)
    if extension is None:
        raise ApiError(415, "UNSUPPORTED_MEDIA_TYPE", "この画像形式には対応していません。")
    if len(normalized.data) > MAX_DEMO_UPLOAD_BYTES:
        raise ApiError(413, "PAYLOAD_TOO_LARGE", "画像の処理後容量が20MBを超えました。別の画像をお試しください。")
    object_name = f"vision-demo/{uuid.uuid4().hex}.{extension}"
    bucket_name = settings.vision_demo_bucket
    gcs_uri = f"gs://{bucket_name}/{object_name}"

    def analyze():
        bucket = storage.Client(project=settings.project_id).bucket(bucket_name)
        blob = bucket.blob(object_name)
        try:
            blob.upload_from_string(normalized.data, content_type=normalized.content_type)
            image = vision.Image()
            image.source.image_uri = gcs_uri
            with vision.ImageAnnotatorClient() as client:
                response = client.safe_search_detection(image=image)
            if response.error.message:
                raise RuntimeError("Vision returned an image annotation error")
            annotation = response.safe_search_annotation
            return {
                "categories": {
                    "adult": annotation.adult.name,
                    "spoof": annotation.spoof.name,
                    "medical": annotation.medical.name,
                    "violence": annotation.violence.name,
                    "racy": annotation.racy.name,
                },
                "width": normalized.width,
                "height": normalized.height,
            }
        finally:
            # Best effort cleanup; GCS lifecycle policy is the backstop for failures.
            try:
                blob.delete()
            except Exception:
                logger.warning("vision_demo_cleanup_failed")

    try:
        return await run_in_threadpool(analyze)
    except ApiError:
        raise
    except Exception as exc:
        logger.warning("vision_demo_failed exceptionType=%s", type(exc).__name__)
        raise ApiError(503, "SERVICE_UNAVAILABLE", "画像を判定できませんでした。設定と接続を確認してください。") from exc
