"""
Unit Tests — QueryReuseEngine
Target: backend/app/services/sql_assistant/reuse_engine.py

Tests:
  - Reuse when similar classified query exists
  - Skip when no match
  - Skip when match is not "correct" classification
  - Skip when validation fails
  - Skip when execution fails
  - Validation chain (SQLValidator → SchemaValidator → execute)
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.reuse_engine import QueryReuseEngine


@pytest.fixture
def mock_deps():
    """Create mock dependencies for QueryReuseEngine."""
    classification_service = MagicMock()
    executor = MagicMock()
    validator = MagicMock()
    schema_validator = MagicMock()

    executor.execute.return_value = MagicMock(row_count=5, rows=[{"id": 1}])
    validator.validate.return_value = None
    schema_validator.validate.return_value = None

    return classification_service, executor, validator, schema_validator


# ===================================================================
# SUCCESSFUL REUSE
# ===================================================================
class TestSuccessfulReuse:

    def test_reuse_correct_classified_query(self, mock_deps):
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": "correct",
            "generated_sql": "SELECT COUNT(*) FROM bal_pick_dtl",
            "user_query": "total picks"
        }

        engine = QueryReuseEngine(cs, executor, validator, sv)
        result = engine.try_reuse("show total picks")

        assert result is not None
        sql, exec_result = result
        assert "bal_pick_dtl" in sql
        executor.execute.assert_called_once()
        validator.validate.assert_called_once()

    def test_reuse_prefers_corrected_sql(self, mock_deps):
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": "correct",
            "generated_sql": "SELECT * FROM bad_query",
            "corrected_sql": "SELECT COUNT(*) FROM bal_pick_dtl",
            "user_query": "total picks"
        }

        engine = QueryReuseEngine(cs, executor, validator, sv)
        sql, _ = engine.try_reuse("total picks today")

        assert sql == "SELECT COUNT(*) FROM bal_pick_dtl"


# ===================================================================
# SKIP REUSE — NO MATCH
# ===================================================================
class TestSkipNoMatch:

    def test_no_similar_query_found(self, mock_deps):
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = None

        engine = QueryReuseEngine(cs, executor, validator, sv)
        assert engine.try_reuse("completely unique query") is None

    def test_empty_dict_match(self, mock_deps):
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {}

        engine = QueryReuseEngine(cs, executor, validator, sv)
        assert engine.try_reuse("some query") is None


# ===================================================================
# SKIP REUSE — WRONG CLASSIFICATION
# ===================================================================
class TestSkipWrongClassification:

    @pytest.mark.parametrize("classification", ["incorrect", "needs_review", "unclassified"])
    def test_non_correct_classification_skipped(self, mock_deps, classification):
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": classification,
            "generated_sql": "SELECT 1",
        }

        engine = QueryReuseEngine(cs, executor, validator, sv)
        assert engine.try_reuse("any query") is None


# ===================================================================
# SKIP REUSE — VALIDATION FAILURE
# ===================================================================
class TestSkipValidationFailure:

    def test_sql_validator_failure(self, mock_deps):
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": "correct",
            "generated_sql": "SELECT * FROM bal_pick_dtl",
        }
        validator.validate.side_effect = Exception("LIMIT required")

        engine = QueryReuseEngine(cs, executor, validator, sv)
        assert engine.try_reuse("picks query") is None

    def test_schema_validator_failure(self, mock_deps):
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": "correct",
            "generated_sql": "SELECT * FROM dropped_table LIMIT 10",
        }
        sv.validate.side_effect = Exception("Invalid table: dropped_table")

        engine = QueryReuseEngine(cs, executor, validator, sv)
        assert engine.try_reuse("old query") is None


# ===================================================================
# SKIP REUSE — EXECUTION FAILURE
# ===================================================================
class TestSkipExecutionFailure:

    def test_db_execution_error(self, mock_deps):
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": "correct",
            "generated_sql": "SELECT * FROM bal_pick_dtl LIMIT 10",
        }
        executor.execute.side_effect = Exception("Connection refused")

        engine = QueryReuseEngine(cs, executor, validator, sv)
        assert engine.try_reuse("picks query") is None


# ===================================================================
# NO VALIDATORS (optional params)
# ===================================================================
class TestNoValidators:

    def test_works_without_validators(self, mock_deps):
        cs, executor, _, _ = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": "correct",
            "generated_sql": "SELECT COUNT(*) FROM bal_pick_dtl",
        }

        engine = QueryReuseEngine(cs, executor, validator=None, schema_validator=None)
        result = engine.try_reuse("total picks")
        assert result is not None
