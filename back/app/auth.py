"""Google認証と登録済みactiveユーザーの認可を共用する。"""

from typing import Annotated

import firebase_admin
from firebase_admin import auth
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from google.api_core.exceptions import GoogleAPICallError

from .errors import ApiError
from .firebase import database, firebase_app


bearer = HTTPBearer(auto_error=False)


def google_uid(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> str:
    """署名・期限・失効・Googleログインを検証し、操作主体を決める。"""
    if credentials is None:
        raise ApiError(401, "UNAUTHENTICATED", "ログインしてください。")
    app = firebase_app()
    if not app.project_id:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "認証サービスの設定を確認してください。")
    try:
        claims = auth.verify_id_token(
            credentials.credentials, app=app, check_revoked=True
        )
    except auth.CertificateFetchError as exc:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "認証を再試行してください。") from exc
    except (auth.InvalidIdTokenError, auth.RevokedIdTokenError,
            auth.UserDisabledError, auth.UserNotFoundError, ValueError) as exc:
        raise ApiError(401, "UNAUTHENTICATED", "再度ログインしてください。") from exc
    except (firebase_admin.exceptions.FirebaseError, GoogleAPICallError) as exc:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "認証を再試行してください。") from exc
    if claims.get("firebase", {}).get("sign_in_provider") != "google.com":
        raise ApiError(401, "UNAUTHENTICATED", "Googleでログインしてください。")
    uid = claims.get("uid")
    if not isinstance(uid, str) or not uid or "/" in uid or "\x00" in uid:
        raise ApiError(401, "UNAUTHENTICATED", "認証情報が不正です。")
    return uid


def active(data: dict) -> None:
    """登録の再送でも停止状態を上書きしない。"""
    if data.get("status") != "active":
        raise ApiError(403, "USER_SUSPENDED", "現在このアカウントは利用できません。")


def active_user(uid: Annotated[str, Depends(google_uid)]) -> dict:
    """通常APIでは認証に加え、登録済み・active状態を毎回確認する。"""
    snapshot = database().collection("users").document(uid).get()
    if not snapshot.exists:
        raise ApiError(404, "RESOURCE_UNAVAILABLE", "参照できません。")
    data = snapshot.to_dict()
    active(data)
    return {**data, "uid": uid}


# 更新トランザクションでは、この依存関係に加えてユーザー状態を再読込する。
GoogleUid = Annotated[str, Depends(google_uid)]
ActiveUser = Annotated[dict, Depends(active_user)]
