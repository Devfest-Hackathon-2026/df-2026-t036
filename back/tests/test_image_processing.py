"""画像正規化ルールのユニットテスト。"""

from io import BytesIO

from PIL import Image
import pytest

from app.image_processing import ImageProcessingError, normalize_image


def encoded_image(image: Image.Image, image_format: str) -> bytes:
    stream = BytesIO()
    image.save(stream, format=image_format)
    return stream.getvalue()


def test_opaque_png_is_normalized_to_jpeg_without_metadata():
    source = Image.new("RGB", (120, 80), (210, 40, 60))
    result = normalize_image(encoded_image(source, "PNG"))

    assert result.image_format == "JPEG"
    assert result.content_type == "image/jpeg"
    assert (result.width, result.height) == (120, 80)
    assert not result.has_transparency
    with Image.open(BytesIO(result.data)) as output:
        assert output.format == "JPEG"
        assert output.size == (120, 80)
        assert not output.info.get("exif")


def test_transparent_png_remains_png_with_alpha():
    source = Image.new("RGBA", (40, 30), (10, 20, 30, 0))
    source.putpixel((10, 10), (200, 80, 40, 128))
    result = normalize_image(encoded_image(source, "PNG"))

    assert result.image_format == "PNG"
    assert result.content_type == "image/png"
    assert result.has_transparency
    with Image.open(BytesIO(result.data)) as output:
        assert output.format == "PNG"
        assert output.getpixel((10, 10))[3] == 128


def test_webp_is_rejected():
    source = Image.new("RGB", (10, 10), (0, 0, 0))

    with pytest.raises(ImageProcessingError) as error:
        normalize_image(encoded_image(source, "WEBP"))

    assert error.value.code == "UNSUPPORTED_IMAGE"


def test_empty_image_is_rejected():
    with pytest.raises(ImageProcessingError) as error:
        normalize_image(b"")

    assert error.value.code == "INVALID_IMAGE"


def test_heic_input_normalizes_to_supported_output(monkeypatch):
    from app import image_processing

    monkeypatch.setattr(image_processing, "SUPPORTED_FORMATS", {"JPEG", "PNG", "HEIF"})
    source = Image.new("RGB", (8, 6), (45, 70, 90))
    heif_data = encoded_image(source, "HEIF")
    result = normalize_image(heif_data)

    assert result.image_format == "JPEG"
    assert result.content_type == "image/jpeg"
    assert (result.width, result.height) == (8, 6)
