"""
Integration Tests — Classification Storage (JSONL round-trip)
Target: QueryClassificationService with real file I/O

Tests store_query → find_similar → classify → learn cycle
using tmp_path for isolated file system.
"""

import pytest
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))

from app.services.query_classification_service import QueryClassificationService


@pytest.mark.integration
class TestClassificationRoundTrip:
    """Store → find → classify → learn cycle with real JSONL files."""

    @pytest.fixture(autouse=True)
    def setup_service(self, tmp_path):
        self.svc = QueryClassificationService(tmp_path / "classification")

    def test_store_creates_jsonl_entry(self):
        qid = self.svc.store_query(
            session_id="s1",
            user_query="show total picks today",
            generated_sql="SELECT COUNT(*) FROM bal_pick_dtl",
            execution_status="success",
            rows_returned=1,
            confidence=0.9,
            tables_used=["bal_pick_dtl"],
        )
        assert qid != ""
        assert len(self.svc.classified_queries_cache) == 1
        assert self.svc.classified_queries_cache[0]["classification"] == "unclassified"

    def test_store_then_find_returns_none_when_unclassified(self):
        """find_similar only returns 'correct' queries."""
        self.svc.store_query(
            session_id="s1",
            user_query="show total picks today",
            generated_sql="SELECT COUNT(*) FROM bal_pick_dtl",
            execution_status="success",
            rows_returned=1,
            confidence=0.9,
            tables_used=["bal_pick_dtl"],
        )
        result = self.svc.find_similar_classified_query("show total picks today")
        assert result is None  # still unclassified

    def test_store_classify_then_find(self):
        """Full round-trip: store → classify as correct → find similar."""
        qid = self.svc.store_query(
            session_id="s1",
            user_query="show total picks today",
            generated_sql="SELECT COUNT(*) FROM bal_pick_dtl",
            execution_status="success",
            rows_returned=1,
            confidence=0.9,
            tables_used=["bal_pick_dtl"],
        )
        ok = self.svc.classify_query(qid, "correct", notes="verified manually")
        assert ok is True

        match = self.svc.find_similar_classified_query(
            "total picks today", similarity_threshold=0.7
        )
        assert match is not None
        assert match["classification"] == "correct"
        assert "bal_pick_dtl" in match["generated_sql"]

    def test_incorrect_query_not_returned(self):
        """Queries classified as 'incorrect' must not be reused."""
        qid = self.svc.store_query(
            session_id="s2",
            user_query="show total puts",
            generated_sql="SELECT COUNT(*) FROM bal_put_dtl",
            execution_status="success",
            rows_returned=1,
            confidence=0.5,
            tables_used=["bal_put_dtl"],
        )
        self.svc.classify_query(qid, "incorrect", corrected_sql="SELECT COUNT(*) FROM bal_put_dtl WHERE status='done'")

        match = self.svc.find_similar_classified_query("show total puts", similarity_threshold=0.7)
        assert match is None

    def test_corrected_sql_stored(self):
        """When incorrect, corrected_sql should be persisted."""
        qid = self.svc.store_query(
            session_id="s3",
            user_query="picks per article",
            generated_sql="SELECT article FROM bal_pick_dtl",
            execution_status="success",
            rows_returned=100,
            confidence=0.6,
            tables_used=["bal_pick_dtl"],
        )
        self.svc.classify_query(
            qid, "incorrect",
            corrected_sql="SELECT article, COUNT(*) FROM bal_pick_dtl GROUP BY article"
        )

        # Reload from file to verify persistence
        reloaded = QueryClassificationService(self.svc.storage_path)
        q = [q for q in reloaded.classified_queries_cache if q["query_id"] == qid][0]
        assert q["corrected_sql"] == "SELECT article, COUNT(*) FROM bal_pick_dtl GROUP BY article"


@pytest.mark.integration
class TestClassificationStats:

    @pytest.fixture(autouse=True)
    def setup_service(self, tmp_path):
        self.svc = QueryClassificationService(tmp_path / "classification")

    def test_stats_empty(self):
        stats = self.svc.get_classification_stats()
        assert stats["total_queries"] == 0

    def test_stats_after_multiple_stores(self):
        for i in range(5):
            self.svc.store_query(
                session_id=f"s{i}",
                user_query=f"query {i}",
                generated_sql=f"SELECT {i}",
                execution_status="success",
                rows_returned=1,
                confidence=0.8,
                tables_used=["bal_pick_dtl"],
            )
        stats = self.svc.get_classification_stats()
        assert stats["total_queries"] == 5
        assert stats.get("unclassified", 0) == 5

    def test_unclassified_queries_list(self):
        for i in range(3):
            self.svc.store_query(
                session_id=f"s{i}",
                user_query=f"query {i}",
                generated_sql=f"SELECT {i}",
                execution_status="success",
                rows_returned=1,
                confidence=0.8,
                tables_used=["bal_pick_dtl"],
            )
        unclassified = self.svc.get_unclassified_queries(limit=10)
        assert len(unclassified) == 3

    def test_add_manual_query_updates_jsonl_runtime(self):
        created = self.svc.add_manual_query(
            user_query="How many active bots are there?",
            generated_sql="SELECT COUNT(*) FROM bot_master WHERE status='ENABLED'",
            notes="added from classification ui"
        )

        assert created is not None
        assert created["classification"] == "unclassified"
        assert len(self.svc.classified_queries_cache) == 1

        jsonl_file = self.svc.storage_path / "classified_queries.jsonl"
        assert jsonl_file.exists()

        with open(jsonl_file, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]

        assert len(lines) == 1
        payload = json.loads(lines[0])
        assert payload["query_id"] == created["query_id"]
        assert payload["user_query"] == "How many active bots are there?"
        assert payload["generated_sql"].startswith("SELECT COUNT(*)")


@pytest.mark.integration
class TestClassificationPersistence:
    """Verify data survives service restart (new instance from same path)."""

    def test_data_survives_restart(self, tmp_path):
        storage = tmp_path / "persist_test"

        svc1 = QueryClassificationService(storage)
        qid = svc1.store_query(
            session_id="s1",
            user_query="total picks",
            generated_sql="SELECT COUNT(*) FROM bal_pick_dtl",
            execution_status="success",
            rows_returned=1,
            confidence=0.9,
            tables_used=["bal_pick_dtl"],
        )
        svc1.classify_query(qid, "correct")

        # Simulate restart
        svc2 = QueryClassificationService(storage)
        assert len(svc2.classified_queries_cache) == 1
        match = svc2.find_similar_classified_query("total picks", similarity_threshold=0.8)
        assert match is not None
        assert match["classification"] == "correct"

    def test_jsonl_file_integrity(self, tmp_path):
        """Each line in JSONL must be valid JSON."""
        storage = tmp_path / "jsonl_test"
        svc = QueryClassificationService(storage)

        for i in range(10):
            svc.store_query(
                session_id=f"s{i}",
                user_query=f"query number {i}",
                generated_sql=f"SELECT {i}",
                execution_status="success",
                rows_returned=i,
                confidence=0.7 + i * 0.02,
                tables_used=["bal_pick_dtl"],
            )

        # Read raw file and validate each line
        jsonl_file = storage / "classified_queries.jsonl"
        assert jsonl_file.exists()
        with open(jsonl_file, "r", encoding="utf-8") as f:
            lines = [l for l in f if l.strip()]
        assert len(lines) == 10
        for line in lines:
            obj = json.loads(line)
            assert "query_id" in obj
            assert "user_query" in obj
