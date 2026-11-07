"""SafeSearchの5カテゴリへ、投稿承認の共通基準を適用する。"""

POLICY_VERSION = "possible-allowed-v1"
CATEGORIES = ("adult", "spoof", "medical", "violence", "racy")
ALLOWED = {"VERY_UNLIKELY", "UNLIKELY", "POSSIBLE"}
REJECTED = {"LIKELY", "VERY_LIKELY"}


def evaluate_categories(categories: dict[str, str]) -> str:
    """明確な拒否を優先し、不明・欠損した判定を承認へ流さない。"""
    values = [categories.get(category) for category in CATEGORIES]
    if any(value in REJECTED for value in values):
        return "rejected"
    if all(value in ALLOWED for value in values):
        return "approved"
    return "retry_required"
