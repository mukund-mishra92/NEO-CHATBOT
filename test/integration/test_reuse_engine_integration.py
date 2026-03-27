"""
Integration Tests — Reuse Engine (QueryReuseEngine)
Target: Classification → Reuse → Validation → Execution chain

Tests the full reuse path:
  - ClassificationService finds a match
  - ReuseEngine validates it (SQLValidator + SchemaValidator)
  - Executor runs the reused SQL
  - Falls back on any failure
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))

from app.services.sql_assistant.reuse_engine import QueryReuseEngine
from app.services.sql_assistant.validator import SQLValidator
from app.services.sql_assistant.schema_validator import SchemaValidator
from app.services.sql_assistant.models import SQLExecutionResult


@pytest.mark.integration
class TestReusePathIntegration:
    """Tests the real reuse engine with real validators + mock classification/executor."""

    @pytest.fixture
    def setup_reuse(self, sample_schema):
        """Wire up real validators with mock classification service and executor."""
        self.cls_svc = MagicMock()
        self.executor = MagicMock()
        self.sql_validator = SQLValidator()
        self.schema_validator = SchemaValidator(sample_schema)

        self.engine = QueryReuseEngine(
            classification_service=self.cls_svc,
            executor=self.executor,
            validator=self.sql_validator,
            schema_validator=self.schema_validator,
        )

    def test_successful_reuse_valid_sql(self, setup_reuse):
        """Correct classified query with valid SQL → reuse succeeds."""
        self.cls_svc.find_similar_classified_query.return_value = {
            "classification": "correct",
            "user_query": "total picks today",
            "generated_sql": "SELECT COUNT(*) FROM bal_pick_dtl",
            "corrected_sql": None,
        }
        self.executor.execute.return_value = SQLExecutionResult(
            rows=[{"count": 42}], row_count=1, execution_time_ms=30
        )

        result = self.engine.try_reuse("total picks today")
        assert result is not None
        sql, exec_result = result
        assert "bal_pick_dtl" in sql
        assert exec_result.row_count == 1

    def test_reuse_prefers_corrected_sql(self, setup_reuse):
        """When corrected_sql exists, it should be used over generated_sql."""
        self.cls_svc.find_similar_classified_query.return_value = {
            "classification": "correct",
            "user_query": "picks per article",
            "generated_sql": "SELECT article FROM bal_pick_dtl",
            "corrected_sql": "SELECT article, COUNT(*) AS cnt FROM bal_pick_dtl GROUP BY article LIMIT 100",
        }
        self.executor.execute.return_value = SQLExecutionResult(
            rows=[{"article": "A1", "cnt": 5}], row_count=1, execution_time_ms=40
        )

        result = self.engine.try_reuse("picks per article")
        assert result is not None
        sql, _ = result
        assert "GROUP BY" in sql

    def test_reuse_falls_back_on_invalid_table(self, setup_reuse):
        """If reused SQL references a table not in schema, validation fails → returns None."""
        self.cls_svc.find_similar_classified_query.return_value = {
            "classification": "correct",
            "user_query": "old query",
            "generated_sql": "SELECT * FROM dropped_table LIMIT 10",
            "corrected_sql": None,
        }

        result = self.engine.try_reuse("old query")
        assert result is None  # SchemaValidator rejects

    def test_reuse_falls_back_on_dangerous_sql(self, setup_reuse):
        """If classified SQL somehow contains write ops, validator blocks it."""
        self.cls_svc.find_similar_classified_query.return_value = {
            "classification": "correct",
            "user_query": "bad query",
            "generated_sql": "DROP TABLE bal_pick_dtl; SELECT 1",
            "corrected_sql": None,
        }

        result = self.engine.try_reuse("bad query")
        assert result is None  # SQLValidator rejects

    def test_reuse_skips_non_correct_classification(self, setup_reuse):
        """Queries not classified as 'correct' must be skipped."""
        for classification in ["incorrect", "needs_review", "unclassified"]:
            self.cls_svc.find_similar_classified_query.return_value = {
                "classification": classification,
                "user_query": "some query",
                "generated_sql": "SELECT 1",
            }
            result = self.engine.try_reuse("some query")
            assert result is None

    def test_reuse_skips_when_no_match(self, setup_reuse):
        """No similar query found → returns None."""
        self.cls_svc.find_similar_classified_query.return_value = None
        result = self.engine.try_reuse("completely new question")
        assert result is None

    def test_reuse_falls_back_on_executor_failure(self, setup_reuse):
        """If executor raises, reuse engine falls back gracefully."""
        self.cls_svc.find_similar_classified_query.return_value = {
            "classification": "correct",
            "user_query": "total picks",
            "generated_sql": "SELECT COUNT(*) FROM bal_pick_dtl",
            "corrected_sql": None,
        }
        self.executor.execute.side_effect = Exception("DB connection lost")

        result = self.engine.try_reuse("total picks")
        assert result is None  # Fell back gracefully
