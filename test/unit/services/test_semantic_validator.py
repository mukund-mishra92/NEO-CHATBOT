"""
Unit Tests — SemanticValidator
Target: backend/app/services/sql_assistant/semantic_validator.py

Tests:
  - Zero rows is valid (no error)
  - Extremely large result sets are blocked
  - Tenant sanity check logging (debug only)
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.semantic_validator import (
    SemanticValidator,
    SemanticValidationError,
)


@pytest.fixture
def validator():
    return SemanticValidator()


class FakeResult:
    def __init__(self, rows, row_count=None):
        self.rows = rows
        self.row_count = row_count if row_count is not None else len(rows)


# ===================================================================
# ZERO ROWS — ALLOWED
# ===================================================================
class TestZeroRows:

    def test_zero_rows_passes(self, validator):
        """Zero rows is a valid empty result."""
        validator.validate(FakeResult([], 0))

    def test_zero_rows_with_sql(self, validator):
        validator.validate(FakeResult([], 0), sql="SELECT 1 WHERE 1=0")


# ===================================================================
# LARGE RESULT SETS — BLOCKED
# ===================================================================
class TestLargeResultSets:

    def test_within_limit_passes(self, validator):
        rows = [{"id": i} for i in range(100)]
        validator.validate(FakeResult(rows, 100))

    def test_at_limit_passes(self, validator):
        validator.validate(FakeResult([], 500_000))

    def test_over_limit_raises(self, validator):
        with pytest.raises(SemanticValidationError, match="too large"):
            validator.validate(FakeResult([], 500_001))

    def test_way_over_limit_raises(self, validator):
        with pytest.raises(SemanticValidationError, match="1000000"):
            validator.validate(FakeResult([], 1_000_000))


# ===================================================================
# TENANT SANITY CHECK (debug log only, no error)
# ===================================================================
class TestTenantCheck:

    def test_tenant_present_in_row(self, validator):
        """No error when tenant value visible in first row."""
        rows = [{"host-location": "frk", "id": 1}]
        validator.validate(FakeResult(rows, 1), tenant="frk")

    def test_tenant_missing_from_row_no_error(self, validator):
        """Missing tenant in first row only logs debug — no exception."""
        rows = [{"id": 1, "article": "ART-001"}]
        validator.validate(FakeResult(rows, 1), tenant="frk")

    def test_no_tenant_no_check(self, validator):
        rows = [{"id": 1}]
        validator.validate(FakeResult(rows, 1), tenant=None)

    def test_tenant_case_insensitive(self, validator):
        rows = [{"host-location": "FRK", "id": 1}]
        validator.validate(FakeResult(rows, 1), tenant="frk")
