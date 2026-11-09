"""Validate and normalize uploaded artwork without storage or database access."""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO
import warnings

from PIL import Image, ImageOps, UnidentifiedImageError
from pillow_heif import register_heif_opener


register_heif_opener()

SUPPORTED_FORMATS = {"JPEG", "PNG", "HEIF"}
# Deliberately high safety ceilings; product limits should follow load tests.
MAX_INPUT_BYTES = 512 * 1024 * 1024
MAX_OUTPUT_BYTES = 512 * 1024 * 1024
# Guard against decompression bombs before full decode; confirm this cap against
# the Cloud Run memory limit with representative inputs.
MAX_IMAGE_PIXELS = 40_000_000
MAX_EDGE = 2560
JPEG_QUALITY = 85


class ImageProcessingError(ValueError):
    """An image is invalid, unsupported, or exceeds a safety limit."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class NormalizedImage:
    data: bytes
    content_type: str
    image_format: str
    width: int
    height: int
    has_transparency: bool


def normalize_image(data: bytes) -> NormalizedImage:
    """Decode JPEG/PNG/HEIC, strip metadata, resize, and encode PNG or JPEG.

    The 512 MiB output cap is a deliberately high safety ceiling, not a normal
    upload target. Product/storage limits should be chosen after measurement.
    """
    if not isinstance(data, bytes) or not data:
        raise ImageProcessingError("INVALID_IMAGE", "画像データが空です。")
    if len(data) > MAX_INPUT_BYTES:
        raise ImageProcessingError("IMAGE_TOO_LARGE", "画像の容量が上限を超えています。")

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", Image.DecompressionBombWarning)
            with Image.open(BytesIO(data)) as source:
                source_format = (source.format or "").upper()
                if source_format in {"HEIC", "HEIF"}:
                    source_format = "HEIF"
                if source_format not in SUPPORTED_FORMATS:
                    raise ImageProcessingError("UNSUPPORTED_IMAGE", "JPEG、PNG、HEIC/HEIFのみ対応しています。")
                if getattr(source, "n_frames", 1) != 1:
                    raise ImageProcessingError("UNSUPPORTED_IMAGE", "アニメーション画像には対応していません。")
                width, height = source.size
                if width <= 0 or height <= 0 or width * height > MAX_IMAGE_PIXELS:
                    raise ImageProcessingError("IMAGE_DIMENSIONS_TOO_LARGE", "画像の縦横サイズが上限を超えています。")

                source.load()
                image = ImageOps.exif_transpose(source)
                has_transparency = _has_transparency(image)
                if has_transparency:
                    image = image.convert("RGBA")
                    target_format = "PNG"
                    content_type = "image/png"
                else:
                    image = image.convert("RGB")
                    target_format = "JPEG"
                    content_type = "image/jpeg"

                image.thumbnail((MAX_EDGE, MAX_EDGE), Image.Resampling.LANCZOS)
                output = BytesIO()
                if target_format == "PNG":
                    image.save(output, format="PNG", optimize=True)
                else:
                    image.save(output, format="JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
    except ImageProcessingError:
        raise
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise ImageProcessingError("INVALID_IMAGE", "画像を読み込めませんでした。") from exc

    normalized = output.getvalue()
    if len(normalized) > MAX_OUTPUT_BYTES:
        raise ImageProcessingError("NORMALIZED_IMAGE_TOO_LARGE", "画像の処理後容量が上限を超えています。")

    return NormalizedImage(
        data=normalized,
        content_type=content_type,
        image_format=target_format,
        width=image.width,
        height=image.height,
        has_transparency=has_transparency,
    )


def _has_transparency(image: Image.Image) -> bool:
    """Return true only when at least one pixel is not fully opaque."""
    if "A" in image.getbands():
        alpha = image.getchannel("A")
        return alpha.getextrema()[0] < 255
    transparency = image.info.get("transparency")
    if transparency is None:
        return False
    rgba = image.convert("RGBA")
    return rgba.getchannel("A").getextrema()[0] < 255
