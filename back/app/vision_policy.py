"""SafeSearchの判定結果から、対象カテゴリだけで投稿承認を判断する。"""

POLICY_VERSION = "possible-allowed-v2"
CATEGORIES = ("adult", "spoof", "medical", "violence", "racy")
# medical・racyは結果を取得するが、承認・拒否・判定不能の判断には使わない。
MODERATED_CATEGORIES = ("adult", "spoof", "violence")
ALLOWED = {"VERY_UNLIKELY", "UNLIKELY", "POSSIBLE"}
REJECTED = {"LIKELY", "VERY_LIKELY"}


def evaluate_categories(categories: dict[str, str]) -> str:
    """明確な拒否を優先し、不明・欠損した判定を承認へ流さない。"""
    values = [categories.get(category) for category in MODERATED_CATEGORIES]
    if any(value in REJECTED for value in values):
        return "rejected"
    if all(value in ALLOWED for value in values):
        return "approved"
    return "retry_required"
