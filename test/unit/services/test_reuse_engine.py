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


# ===================================================================
# PHASE 4 — TIME SUBSTITUTION
# ===================================================================
class TestTimeSubstitution:

    def test_time_substitution_replaces_between_dates(self, mock_deps):
        """_apply_time_substitution should replace BETWEEN date literals."""
        cs, executor, validator, sv = mock_deps
        engine = QueryReuseEngine(cs, executor, validator, sv)

        sql = (
            "SELECT * FROM task_master_log "
            "WHERE LOG_TIMESTAMP BETWEEN '2025-01-01 00:00:00' AND '2025-01-31 23:59:59'"
        )
        result = engine._apply_time_substitution(
            sql, "2026-04-01 00:00:00", "2026-04-30 23:59:59"
        )
        assert "2026-04-01 00:00:00" in result
        assert "2026-04-30 23:59:59" in result
        assert "2025-01-01" not in result

    def test_time_substitution_no_between_unchanged(self, mock_deps):
        """SQL without BETWEEN should not be modified."""
        cs, executor, validator, sv = mock_deps
        engine = QueryReuseEngine(cs, executor, validator, sv)

        sql = "SELECT COUNT(*) FROM bot_master"
        result = engine._apply_time_substitution(sql, "2026-04-01", "2026-04-30")
        assert result == sql

    def test_time_substitution_with_none_args(self, mock_deps):
        """None time args should return SQL unchanged."""
        cs, executor, validator, sv = mock_deps
        engine = QueryReuseEngine(cs, executor, validator, sv)

        sql = "SELECT * FROM t WHERE ts BETWEEN '2025-01-01' AND '2025-12-31'"
        result = engine._apply_time_substitution(sql, None, None)
        assert result == sql


# ===================================================================
# PHASE 4 — TENANT SUBSTITUTION
# ===================================================================
class TestTenantSubstitution:

    def test_tenant_substitution_replaces_in_clause(self, mock_deps):
        """_apply_tenant_substitution should update IN (...) values."""
        cs, executor, validator, sv = mock_deps
        engine = QueryReuseEngine(cs, executor, validator, sv)

        sql = "SELECT * FROM t WHERE `host-location` IN ('OLD_TENANT')"
        result = engine._apply_tenant_substitution(sql, "host-location", ["NEW_SITE"])
        assert "'NEW_SITE'" in result
        assert "'OLD_TENANT'" not in result

    def test_tenant_substitution_equality(self, mock_deps):
        """_apply_tenant_substitution should update = 'value' form."""
        cs, executor, validator, sv = mock_deps
        engine = QueryReuseEngine(cs, executor, validator, sv)

        sql = "SELECT * FROM t WHERE `host-location` = 'FRK'"
        result = engine._apply_tenant_substitution(sql, "host-location", ["SHAKTI"])
        assert "'SHAKTI'" in result

    def test_tenant_substitution_no_match_unchanged(self, mock_deps):
        """SQL without tenant column should not be modified."""
        cs, executor, validator, sv = mock_deps
        engine = QueryReuseEngine(cs, executor, validator, sv)

        sql = "SELECT COUNT(*) FROM bot_master"
        result = engine._apply_tenant_substitution(sql, "host-location", ["FRK"])
        assert result == sql


# ===================================================================
# PHASE 4 — END-TO-END REUSE WITH SUBSTITUTION
# ===================================================================
class TestReuseWithSubstitution:

    def test_try_reuse_applies_time_and_tenant(self, mock_deps):
        """Full try_reuse call should apply both time and tenant substitution."""
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": "correct",
            "similarity_score": 0.92,
            "generated_sql": (
                "SELECT COUNT(*) FROM task_master_log "
                "WHERE `host-location` IN ('OLD') "
                "AND LOG_TIMESTAMP BETWEEN '2025-01-01 00:00:00' AND '2025-01-31 23:59:59'"
            ),
            "user_query": "total tasks at old site",
        }

        engine = QueryReuseEngine(cs, executor, validator, sv)
        result = engine.try_reuse(
            "total tasks today",
            entities={"host-location": ["FRK"]},
            time_from="2026-04-26 00:00:00",
            time_to="2026-04-26 23:59:59",
            tenant_column="host-location",
        )

        assert result is not None
        sql, exec_result = result
        assert "2026-04-26 00:00:00" in sql
        assert "'FRK'" in sql
        assert "'OLD'" not in sql
        assert "2025-01-01" not in sql

    def test_try_reuse_without_substitution_params(self, mock_deps):
        """try_reuse with no extra params should still work (backward compatible)."""
        cs, executor, validator, sv = mock_deps
        cs.find_similar_classified_query.return_value = {
            "classification": "correct",
            "generated_sql": "SELECT 1 FROM dual",
            "user_query": "test",
        }

        engine = QueryReuseEngine(cs, executor, validator, sv)
        result = engine.try_reuse("test query")
        assert result is not None
