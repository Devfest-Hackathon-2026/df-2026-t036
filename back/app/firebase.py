"""Firebase AdminアプリとFirestore接続を共用する。"""

from functools import lru_cache
from threading import Lock

import firebase_admin
from firebase_admin import firestore

from .config import Settings


_initialization_lock = Lock()


@lru_cache
def firebase_app():
    """認証情報はADCから取得し、秘密鍵をコードへ埋め込まない。"""
    # 初回リクエストが並行してもデフォルトアプリを二重作成しない。
    with _initialization_lock:
        try:
            return firebase_admin.get_app()
        except ValueError:
            project = Settings.from_env().project_id
            return firebase_admin.initialize_app(options={"projectId": project} if project else None)


@lru_cache
def database():
    """初回利用時に接続し、health確認には認証情報を要求しない。"""
    return firestore.client(app=firebase_app())


