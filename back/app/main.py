"""開発時の接続確認に使用するFastAPIアプリ。"""

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Illustration Exchange API")

# Flutter Webの開発サーバーなど、許可した接続元だけを受け付ける。
origins = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    """Flutterと運用監視からAPIの起動状態を確認する。"""
    return {"status": "ok"}
