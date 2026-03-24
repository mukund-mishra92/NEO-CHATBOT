"""
Unit Tests — SQLFormatter
Target: backend/app/services/sql_assistant/formatter.py

Tests:
  - Normal table formatting
  - Zero rows
  - Large datasets (> DISPLAY_LIMIT truncation)
  - Safe value conversion (Decimal, datetime, None)
  - Markdown output structure
"""

import pytest
import sys
from pathlib import Path
from decimal import Decimal
from datetime import datetime, date

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.formatter import SQLFormatter


@pytest.fixture
def formatter():
    return SQLFormatter()


# Helper to build MockSQLExecutionResult-like objects
class FakeResult:
    def __init__(self, rows, row_count=None):
        self.rows = rows
        self.row_count = row_count if row_count is not None else len(rows)
        self.execution_time_ms = 50


# ===================================================================
# _safe_str
# ===================================================================
class TestSafeStr:

    def test_none_returns_empty(self, formatter):
        assert formatter._safe_str(None) == ""

    def test_decimal_converts(self, formatter):
        assert formatter._safe_str(Decimal("3.14")) == "3.14"

    def test_datetime_converts(self, formatter):
        dt = datetime(2026, 3, 23, 14, 30, 0)
        assert formatter._safe_str(dt) == "2026-03-23T14:30:00"

    def test_date_converts(self, formatter):
        d = date(2026, 3, 23)
        assert formatter._safe_str(d) == "2026-03-23"

    def test_int_converts(self, formatter):
        assert formatter._safe_str(42) == "42"

    def test_string_passthrough(self, formatter):
        assert formatter._safe_str("hello") == "hello"


# ===================================================================
# _format_table
# ===================================================================
class TestFormatTable:

    def test_single_row(self, formatter):
        rows = [{"id": 1, "name": "test"}]
        result = formatter._format_table(rows)
        assert "| id | name |" in result
        assert "| 1 | test |" in result

    def test_multiple_rows(self, formatter):
        rows = [{"a": i} for i in range(5)]
        result = formatter._format_table(rows)
        assert result.count("\n") >= 6  # header + separator + 5 data rows

    def test_truncation_message(self, formatter):
        rows = [{"id": i} for i in range(600)]
        result = formatter._format_table(rows)
        assert "Showing first 500" in result
        assert "600" in result

    def test_separator_row(self, formatter):
        rows = [{"col1": "a", "col2": "b"}]
        result = formatter._format_table(rows)
        assert "| --- | --- |" in result


# ===================================================================
# format (main method)
# ===================================================================
class TestFormat:

    def test_zero_rows(self, formatter):
        result = formatter.format(
            "test query",
            "SELECT 1",
            FakeResult([], 0),
            0.9
        )
        assert "No data found" in result
        assert "```sql" in result

    def test_normal_output_has_sql_block(self, formatter):
        result = formatter.format(
            "show picks",
            "SELECT * FROM bal_pick_dtl LIMIT 10",
            FakeResult([{"id": 1, "article": "ART-001"}]),
            0.9
        )
        assert "```sql" in result
        assert "SELECT * FROM bal_pick_dtl" in result
        assert "Rows Returned: 1" in result

    def test_output_contains_data_table(self, formatter):
        result = formatter.format(
            "query",
            "SELECT 1",
            FakeResult([{"cnt": 42}]),
            0.9
        )
        assert "| cnt |" in result
        assert "| 42 |" in result

    def test_decimal_in_output(self, formatter):
        result = formatter.format(
            "query",
            "SELECT 1",
            FakeResult([{"price": Decimal("99.99")}]),
            0.9
        )
        assert "99.99" in result

    def test_none_values_in_output(self, formatter):
        result = formatter.format(
            "query",
            "SELECT 1",
            FakeResult([{"value": None}]),
            0.9
        )
        # None should render as empty string, not "None"
        assert "None" not in result or "| |" in result.replace(" ", "")
