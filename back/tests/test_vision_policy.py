"""承認の境界と、欠損・不明時に承認しないことを検証する。"""

import pytest
from app.vision_policy import CATEGORIES, evaluate_categories


@pytest.mark.parametrize("value,expected", [
    ("VERY_UNLIKELY", "approved"), ("UNLIKELY", "approved"),
    ("POSSIBLE", "approved"), ("LIKELY", "rejected"),
    ("VERY_LIKELY", "rejected"), ("UNKNOWN", "retry_required"),
    ("unexpected", "retry_required"),
])
def test_likelihood_boundary(value, expected):
    assert evaluate_categories(dict.fromkeys(CATEGORIES, value)) == expected


def test_one_category_can_prevent_approval():
    # 他カテゴリが許容でも、1カテゴリの欠損・不明・拒否を見落とさない。
    categories = dict.fromkeys(CATEGORIES, "POSSIBLE")
    del categories["violence"]
    assert evaluate_categories(categories) == "retry_required"
    categories["adult"] = "LIKELY"
    assert evaluate_categories(categories) == "rejected"


@pytest.mark.parametrize("ignored", [
    {}, {"medical": "VERY_LIKELY", "racy": "VERY_LIKELY"},
    {"medical": "UNKNOWN", "racy": "unexpected"},
])
def test_medical_and_racy_do_not_affect_decision(ignored):
    # 除外カテゴリは高い値・欠損・不明のいずれでも承認や拒否を変えない。
    categories = {"adult": "POSSIBLE", "spoof": "UNLIKELY", "violence": "POSSIBLE", **ignored}
    assert evaluate_categories(categories) == "approved"
    categories["violence"] = "LIKELY"
    assert evaluate_categories(categories) == "rejected"
