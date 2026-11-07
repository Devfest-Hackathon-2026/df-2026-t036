"""画像処理がAPIのイベントループを占有しないことを検証する。"""

import asyncio
from io import BytesIO
from threading import get_ident
from types import SimpleNamespace

import pytest
from starlette.datastructures import UploadFile

from app import vision_demo
from app.config import Settings
from app.errors import ApiError
from app.image_processing import ImageProcessingError


def test_normalization_runs_outside_event_loop(monkeypatch):
    async def exercise():
        loop_thread = get_ident()
        worker_threads = []

        def reject_image(raw):
            worker_threads.append(get_ident())
            assert raw == b"invalid"
            raise ImageProcessingError("INVALID_IMAGE", "invalid image")

        monkeypatch.setattr(vision_demo, "normalize_image", reject_image)
        request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(
            settings=Settings(vision_demo_bucket="demo-bucket")
        )))
        with pytest.raises(ApiError) as error:
            await vision_demo.inspect_image(
                request, {"uid": "viewer"}, UploadFile(BytesIO(b"invalid"))
            )
        assert error.value.status == 422
        assert worker_threads and worker_threads[0] != loop_thread

    asyncio.run(exercise())


# HTTPの受信経路から呼び出し、パーサーに渡る前の容量制限を検証する。
def upload_request(app, body, *, content_length=None):
    import json

    async def exercise():
        chunks = [body[index:index + 256] for index in range(0, len(body), 256)]
        reads = 0
        messages = []

        async def receive():
            nonlocal reads
            chunk = chunks[reads]
            reads += 1
            return {"type": "http.request", "body": chunk, "more_body": reads < len(chunks)}

        async def send(message):
            messages.append(message)

        headers = [(b"content-type", b"multipart/form-data; boundary=test"),
                   (b"origin", b"http://localhost:3000")]
        if content_length is not None:
            headers.append((b"content-length", str(content_length).encode()))
        await app({"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1",
                   "method": "POST", "scheme": "http", "path": "/api/v1/vision-demo",
                   "raw_path": b"/api/v1/vision-demo", "query_string": b"",
                   "root_path": "", "headers": headers,
                   "server": ("test", 80), "client": ("test", 123)}, receive, send)
        start = next(message for message in messages if message["type"] == "http.response.start")
        payload = b"".join(message.get("body", b"") for message in messages if message["type"] == "http.response.body")
        return start, json.loads(payload), reads, len(chunks)

    return asyncio.run(exercise())


@pytest.mark.parametrize("declared", [None, 1, 4096, "9" * 5000])
def test_receive_limit_stops_before_storage(monkeypatch, declared):
    from unittest.mock import Mock
    from app import middleware
    from app.main import create_app

    monkeypatch.setattr(middleware, "MAX_DEMO_REQUEST_BYTES", 1024)
    storage = Mock()
    monkeypatch.setattr(vision_demo.storage, "Client", storage)
    body = (b'--test\r\nContent-Disposition: form-data; name="file"; filename="large.png"\r\n'
            b'Content-Type: image/png\r\n\r\n' + b'x' * 2048 + b'\r\n--test--\r\n')
    start, payload, reads, total = upload_request(create_app(Settings()), body, content_length=declared)
    assert start["status"] == 413
    assert payload["error"]["code"] == "PAYLOAD_TOO_LARGE"
    assert dict(start["headers"])[b"access-control-allow-origin"] == b"http://localhost:3000"
    assert payload["error"]["requestId"]
    assert reads < total
    if declared == 4096:
        assert reads == 0
    storage.assert_not_called()


def test_invalid_image_does_not_reach_storage(monkeypatch):
    from unittest.mock import Mock
    from fastapi.testclient import TestClient
    from app.auth import active_user
    from app.main import create_app

    app = create_app(Settings(vision_demo_bucket="demo-bucket"))
    app.dependency_overrides[active_user] = lambda: {"uid": "viewer"}
    storage = Mock()
    monkeypatch.setattr(vision_demo.storage, "Client", storage)
    with TestClient(app) as client:
        response = client.post('/api/v1/vision-demo', files={"file": ("fake.png", b"not an image", "image/png")})
    assert response.status_code == 422
    storage.assert_not_called()


@pytest.mark.parametrize("file_limit,expected", [(1, 413), (20 * 1024 * 1024, 200)])
def test_file_validation_before_cloud_upload(monkeypatch, file_limit, expected):
    from unittest.mock import Mock
    from PIL import Image
    from fastapi.testclient import TestClient
    from app.auth import active_user
    from app.main import create_app

    # 正常画像は保存へ進み、ファイル自体が容量超過なら保存前に止める。
    image = BytesIO()
    Image.new("RGB", (8, 6)).save(image, format="PNG")
    app = create_app(Settings(vision_demo_bucket="demo-bucket"))
    app.dependency_overrides[active_user] = lambda: {"uid": "viewer"}
    storage = Mock()
    monkeypatch.setattr(vision_demo.storage, "Client", storage)
    monkeypatch.setattr(vision_demo, "MAX_DEMO_UPLOAD_BYTES", file_limit)
    annotation = vision_demo.vision.SafeSearchAnnotation(adult=1, spoof=1, medical=1, violence=1, racy=1)
    vision = Mock()
    vision.safe_search_detection.return_value = SimpleNamespace(
        error=SimpleNamespace(message=""), safe_search_annotation=annotation)
    context = Mock()
    context.__enter__ = Mock(return_value=vision)
    context.__exit__ = Mock(return_value=False)
    monkeypatch.setattr(vision_demo.vision, "ImageAnnotatorClient", lambda: context)
    with TestClient(app) as client:
        response = client.post('/api/v1/vision-demo', files={"file": ("sample.png", image.getvalue(), "image/png")})
    assert response.status_code == expected
    if expected == 413:
        storage.assert_not_called()
    else:
        blob = storage.return_value.bucket.return_value.blob.return_value
        blob.upload_from_string.assert_called_once()
        blob.delete.assert_called_once()
        assert response.json()["width"] == 8
