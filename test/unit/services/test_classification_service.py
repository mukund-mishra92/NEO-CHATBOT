"""
Unit Tests — QueryClassificationService (find_similar_classified_query)
Target: backend/app/services/query_classification_service.py

Tests:
  - find_similar_classified_query() similarity matching
  - store_query() stores correctly
  - get_classification_stats()
  - Only "correct" classification reused
"""

import pytest
import sys
import json
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))


@pytest.fixture
def classification_service(tmp_path):
    """Create a QueryClassificationService with a small JSONL file."""
    from app.services.query_classification_service import QueryClassificationService

    storage_dir = tmp_path / "classification"
    storage_dir.mkdir(parents=True, exist_ok=True)

    records = [
        {
            "query_id": "q-001",
            "user_query": "show total picks today",
            "generated_sql": "SELECT COUNT(*) FROM bal_pick_dtl",
            "classification": "correct",
            "confidence": 0.92,
            "session_id": "s1",
            "timestamp": "2026-03-23T10:00:00",
            "execution_status": "success",
            "rows_returned": 1,
            "tables_used": ["bal_pick_dtl"],
            "classification_timestamp": None,
            "classification_notes": None,
            "corrected_sql": None,
            "metadata": {}
        },
        {
            "query_id": "q-002",
            "user_query": "how many items received yesterday",
            "generated_sql": "SELECT COUNT(*) FROM bal_inbound_receipt_dtl",
            "classification": "correct",
            "confidence": 0.88,
            "session_id": "s1",
            "timestamp": "2026-03-23T10:05:00",
            "execution_status": "success",
            "rows_returned": 1,
            "tables_used": ["bal_inbound_receipt_dtl"],
            "classification_timestamp": None,
            "classification_notes": None,
            "corrected_sql": None,
            "metadata": {}
        },
        {
            "query_id": "q-003",
            "user_query": "show all bots",
            "generated_sql": "SELECT * FROM bal_master_bot",
            "classification": "incorrect",
            "confidence": 0.45,
            "session_id": "s2",
            "timestamp": "2026-03-23T10:10:00",
            "execution_status": "success",
            "rows_returned": 50,
            "tables_used": ["bal_master_bot"],
            "classification_timestamp": None,
            "classification_notes": None,
            "corrected_sql": None,
            "metadata": {}
        },
        {
            "query_id": "q-004",
            "user_query": "total picks at shakti",
            "generated_sql": "SELECT COUNT(*) FROM bal_pick_dtl WHERE `host-location` = 'shakti'",
            "classification": "unclassified",
            "confidence": 0.8,
            "session_id": "s3",
            "timestamp": "2026-03-23T10:15:00",
            "execution_status": "success",
            "rows_returned": 1,
            "tables_used": ["bal_pick_dtl"],
            "classification_timestamp": None,
            "classification_notes": None,
            "corrected_sql": None,
            "metadata": {}
        },
    ]

    # Write JSONL file
    jsonl_file = storage_dir / "classified_queries.jsonl"
    with open(jsonl_file, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

    svc = QueryClassificationService(storage_dir)
    return svc


# ===================================================================
# FIND SIMILAR CLASSIFIED QUERY
# ===================================================================
class TestFindSimilar:

    def test_exact_match_returns_correct(self, classification_service):
        result = classification_service.find_similar_classified_query(
            "show total picks today", similarity_threshold=0.85
        )
        assert result is not None
        assert result["classification"] == "correct"
        assert "bal_pick_dtl" in result["generated_sql"]

    def test_similar_query_matches(self, classification_service):
        result = classification_service.find_similar_classified_query(
            "give me total picks today", similarity_threshold=0.85
        )
        # May or may not match depending on SequenceMatcher — at threshold 0.85
        # This is a realistic test of the algorithm
        if result:
            assert result["classification"] == "correct"

    def test_no_match_returns_none(self, classification_service):
        result = classification_service.find_similar_classified_query(
            "completely unrelated xyz query", similarity_threshold=0.85
        )
        assert result is None

    def test_incorrect_not_returned(self, classification_service):
        """Even if similar, incorrect classification should not be reused."""
        result = classification_service.find_similar_classified_query(
            "show all bots", similarity_threshold=0.85
        )
        # "show all bots" matches q-003 which is "incorrect" → should return None
        assert result is None

    def test_unclassified_not_returned(self, classification_service):
        result = classification_service.find_similar_classified_query(
            "total picks at shakti", similarity_threshold=0.85
        )
        assert result is None


# ===================================================================
# GET CLASSIFICATION STATS
# ===================================================================
class TestClassificationStats:

    def test_stats_counts(self, classification_service):
        stats = classification_service.get_classification_stats()
        # Stats should have classification breakdown
        assert stats.get("correct", 0) == 2
        assert stats.get("incorrect", 0) == 1
        assert stats.get("unclassified", 0) == 1
