"""
Unit Tests — SchemaFeedbackGenerator
Target: backend/app/services/sql_assistant/schema_feedback.py

Tests:
  - Unknown table → suggests closest matches
  - Unknown column → suggests closest columns
  - Syntax error handling
  - LIMIT missing feedback
  - _find_closest_tables / _find_closest_columns accuracy
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.schema_feedback import SchemaFeedbackGenerator


@pytest.fixture
def feedback_gen(sample_schema):
    return SchemaFeedbackGenerator(sample_schema)


# ===================================================================
# UNKNOWN TABLE FEEDBACK
# ===================================================================
class TestUnknownTable:

    def test_unknown_table_suggests_closest(self, feedback_gen):
        error = "Table 'bal_pick' doesn't exist"
        sql = "SELECT * FROM bal_pick"
        fb = feedback_gen.generate_feedback(error, sql)
        assert "bal_pick_dtl" in fb
        assert "does not exist" in fb.lower() or "Did you mean" in fb

    def test_completely_wrong_table(self, feedback_gen):
        error = "Table 'zzz_table' doesn't exist"
        sql = "SELECT * FROM zzz_table"
        fb = feedback_gen.generate_feedback(error, sql)
        assert "Did you mean" in fb or "does not exist" in fb.lower()


# ===================================================================
# UNKNOWN COLUMN FEEDBACK
# ===================================================================
class TestUnknownColumn:

    def test_unknown_column_suggests_closest(self, feedback_gen):
        error = "Unknown column 'artcle' in field list"
        sql = "SELECT artcle FROM bal_pick_dtl LIMIT 10"
        fb = feedback_gen.generate_feedback(error, sql)
        assert "article" in fb.lower() or "does not exist" in fb.lower()

    def test_ambiguous_column(self, feedback_gen):
        error = "Column 'status' is ambiguous"
        sql = "SELECT status FROM bal_pick_dtl p JOIN bal_master_bot b ON p.id = b.id LIMIT 10"
        fb = feedback_gen.generate_feedback(error, sql)
        assert "does not exist" in fb.lower() or "Did you mean" in fb


# ===================================================================
# LIMIT MISSING FEEDBACK
# ===================================================================
class TestLimitFeedback:

    def test_limit_required_feedback(self, feedback_gen):
        error = "LIMIT clause required for safety"
        sql = "SELECT * FROM bal_pick_dtl"
        fb = feedback_gen.generate_feedback(error, sql)
        assert "LIMIT" in fb


# ===================================================================
# SYNTAX ERROR FEEDBACK
# ===================================================================
class TestSyntaxError:

    def test_syntax_error_includes_query(self, feedback_gen):
        error = "You have a syntax error near 'FRIM'"
        sql = "SELECT * FRIM bal_pick_dtl LIMIT 10"
        fb = feedback_gen.generate_feedback(error, sql)
        assert "FRIM" in fb or "syntax" in fb.lower()


# ===================================================================
# CLOSEST MATCH HELPERS
# ===================================================================
class TestClosestMatches:

    def test_find_closest_tables(self, feedback_gen):
        matches = feedback_gen._find_closest_tables("bal_pick", top_k=3)
        assert len(matches) <= 3
        table_names = [m[0] for m in matches]
        assert "bal_pick_dtl" in table_names

    def test_find_closest_columns(self, feedback_gen):
        columns = ["article", "station-id", "bot-id", "wave-id", "quantity"]
        matches = feedback_gen._find_closest_columns("articl", columns, top_k=2)
        assert len(matches) <= 2
        col_names = [m[0] for m in matches]
        assert "article" in col_names
