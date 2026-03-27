"""
Unit Tests — SQLRetryEngine
Target: backend/app/services/sql_assistant/retry_engine.py

Tests:
  - Successful first attempt
  - Retry after validation failure
  - Retry after execution failure
  - Max attempts exceeded raises
  - Forbidden table violation
  - Required table missing
  - Feedback generator integration
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock, call

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.retry_engine import SQLRetryEngine
from app.services.sql_assistant.models import SQLGenerationResult, SQLExecutionResult


@pytest.fixture
def engine():
    return SQLRetryEngine(max_attempts=3)


def make_gen_result(sql="SELECT 1", tables_used=None):
    return SQLGenerationResult(
        sql=sql,
        confidence=0.9,
        explanation="test",
        assumptions=[],
        metadata={"tables_used": tables_used or []}
    )


def make_exec_result(rows=None, row_count=1):
    return SQLExecutionResult(
        rows=rows or [{"id": 1}],
        row_count=row_count,
        execution_time_ms=50
    )


# ===================================================================
# FIRST ATTEMPT SUCCESS
# ===================================================================
class TestFirstAttemptSuccess:

    def test_succeeds_on_first_try(self, engine):
        gen_fn = MagicMock(return_value=make_gen_result("SELECT 1 LIMIT 10"))
        validator = MagicMock()
        executor = MagicMock()
        executor.execute.return_value = make_exec_result()

        gen_result, exec_result = engine.run(gen_fn, validator, executor)

        assert gen_result.sql == "SELECT 1 LIMIT 10"
        assert exec_result.row_count == 1
        gen_fn.assert_called_once()


# ===================================================================
# RETRY AFTER FAILURE
# ===================================================================
class TestRetryAfterFailure:

    def test_retry_after_validation_error(self, engine):
        """First call fails validation, second succeeds."""
        call_count = [0]

        def gen_fn(feedback, prev_sql):
            call_count[0] += 1
            if call_count[0] == 1:
                return make_gen_result("SELECT * FROM t")  # will fail validation
            return make_gen_result("SELECT * FROM t LIMIT 10")

        validator = MagicMock()
        validator.validate.side_effect = [Exception("LIMIT required"), None]

        executor = MagicMock()
        executor.execute.return_value = make_exec_result()

        gen_result, exec_result = engine.run(gen_fn, validator, executor)
        assert "LIMIT" in gen_result.sql
        assert call_count[0] == 2

    def test_retry_after_execution_error(self, engine):
        """First execution fails, second succeeds."""
        gen_fn = MagicMock(return_value=make_gen_result("SELECT 1"))

        validator = MagicMock()
        executor = MagicMock()
        executor.execute.side_effect = [Exception("timeout"), make_exec_result()]

        gen_result, exec_result = engine.run(gen_fn, validator, executor)
        assert exec_result.row_count == 1


# ===================================================================
# MAX ATTEMPTS EXCEEDED
# ===================================================================
class TestMaxAttemptsExceeded:

    def test_raises_after_max_attempts(self, engine):
        gen_fn = MagicMock(return_value=make_gen_result("BAD SQL"))
        validator = MagicMock()
        validator.validate.side_effect = Exception("always fails")
        executor = MagicMock()

        with pytest.raises(Exception, match="SQL generation failed after retries"):
            engine.run(gen_fn, validator, executor)

        assert gen_fn.call_count == 3

    def test_single_attempt_engine(self):
        engine = SQLRetryEngine(max_attempts=1)
        gen_fn = MagicMock(return_value=make_gen_result("BAD"))
        validator = MagicMock()
        validator.validate.side_effect = Exception("fail")
        executor = MagicMock()

        with pytest.raises(Exception):
            engine.run(gen_fn, validator, executor)

        assert gen_fn.call_count == 1


# ===================================================================
# TABLE VALIDATION (forbidden / required)
# ===================================================================
class TestTableValidation:

    def test_forbidden_table_triggers_retry(self, engine):
        """First attempt uses forbidden table, retry uses correct one."""
        call_count = [0]

        def gen_fn(feedback, prev_sql):
            call_count[0] += 1
            if call_count[0] == 1:
                return make_gen_result(
                    "SELECT * FROM bad_table LIMIT 10",
                    tables_used=["bad_table"]
                )
            return make_gen_result(
                "SELECT * FROM bal_pick_dtl LIMIT 10",
                tables_used=["bal_pick_dtl"]
            )

        validator = MagicMock()
        executor = MagicMock()
        executor.execute.return_value = make_exec_result()

        gen_result, _ = engine.run(
            gen_fn, validator, executor,
            forbidden_tables=["bad_table"],
            required_tables=["bal_pick_dtl"]
        )
        assert "bal_pick_dtl" in gen_result.sql

    def test_required_table_missing_triggers_retry(self, engine):
        call_count = [0]

        def gen_fn(feedback, prev_sql):
            call_count[0] += 1
            if call_count[0] == 1:
                return make_gen_result(
                    "SELECT * FROM bal_put_dtl LIMIT 10",
                    tables_used=["bal_put_dtl"]
                )
            return make_gen_result(
                "SELECT * FROM bal_pick_dtl LIMIT 10",
                tables_used=["bal_pick_dtl"]
            )

        validator = MagicMock()
        executor = MagicMock()
        executor.execute.return_value = make_exec_result()

        gen_result, _ = engine.run(
            gen_fn, validator, executor,
            required_tables=["bal_pick_dtl"]
        )
        assert "bal_pick_dtl" in gen_result.sql


# ===================================================================
# FEEDBACK GENERATOR
# ===================================================================
class TestFeedbackGenerator:

    def test_feedback_generator_called_on_error(self, engine):
        gen_fn = MagicMock(return_value=make_gen_result("SELECT 1"))
        validator = MagicMock()
        validator.validate.side_effect = [Exception("bad"), None]
        executor = MagicMock()
        executor.execute.return_value = make_exec_result()
        feedback_gen = MagicMock()
        feedback_gen.generate_feedback.return_value = "Use correct table"

        engine.run(gen_fn, validator, executor, feedback_generator=feedback_gen)

        feedback_gen.generate_feedback.assert_called_once()
