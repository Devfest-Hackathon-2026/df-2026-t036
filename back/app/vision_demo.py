"""検証済み画像を一時保存せず、直接SafeSearchで判定する。"""

from __future__ import annotations

import logging

from fastapi import APIRouter, File, UploadFile
from google.cloud import vision
from starlette.concurrency import run_in_threadpool

from .auth import ActiveUser
from .errors import ApiError
from .image_processing import ImageProcessingError, normalize_image
from .upload_limits import MAX_DEMO_UPLOAD_BYTES

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1")
MAX_INLINE_IMAGE_BYTES = 7_000_000


@router.post("/vision-demo")
async def inspect_image(
    user: ActiveUser,
    file: UploadFile = File(...),
):
    """認証・画像検証を通過したデータだけをVisionへ渡す。"""
    raw = await file.read(MAX_DEMO_UPLOAD_BYTES + 1)
    if len(raw) > MAX_DEMO_UPLOAD_BYTES:
        raise ApiError(413, "PAYLOAD_TOO_LARGE", "画像は20MB以下にしてください。")
    try:
        # 重い画像処理を別スレッドへ移し、他のリクエストを待たせない。
        normalized = await run_in_threadpool(normalize_image, raw)
    except ImageProcessingError as exc:
        raise ApiError(422, exc.code, str(exc)) from exc

    # Base64化を伴う転送でもJSONの10MB上限に余裕を持たせる。
    if len(normalized.data) > MAX_INLINE_IMAGE_BYTES:
        raise ApiError(413, "PAYLOAD_TOO_LARGE", "変換後の画像は7MB以下にしてください。")

    def analyze():
        # バケットや公開URLを経由せず、変換済みバイト列を直接渡す。
        image = vision.Image(content=normalized.data)
        with vision.ImageAnnotatorClient() as client:
            response = client.safe_search_detection(image=image, timeout=60)
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

    try:
        return await run_in_threadpool(analyze)
    except ApiError:
        raise
    except Exception as exc:
        logger.warning("vision_demo_failed exceptionType=%s", type(exc).__name__)
        raise ApiError(503, "SERVICE_UNAVAILABLE", "画像を判定できませんでした。設定と接続を確認してください。") from exc
