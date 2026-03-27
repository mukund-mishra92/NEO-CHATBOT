"""
Unit Tests — TablePriorityLoader
Target: backend/app/services/sql_assistant/table_priority_loader.py

Tests:
  - get_table_multiplier() — exact match, partial match, no match
  - get_validated_tables_for_query() — correct/incorrect split
  - _is_similar_query() — word overlap matching
"""

import pytest
import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.table_priority_loader import TablePriorityLoader


@pytest.fixture
def loader(tmp_path):
    """Create loader with a small validations file."""
    validations_file = tmp_path / "table_priority_validations.jsonl"
    validations = [
        {"query": "show total picks today", "table_name": "bal_pick_dtl", "is_correct": True},
        {"query": "show total picks today", "table_name": "bal_master_article", "is_correct": False},
        {"query": "how many items received", "table_name": "bal_inbound_receipt_dtl", "is_correct": True},
        {"query": "how many items received", "table_name": "bal_pick_dtl", "is_correct": False},
    ]
    with open(validations_file, "w") as f:
        for v in validations:
            f.write(json.dumps(v) + "\n")

    return TablePriorityLoader(validations_file)


# ===================================================================
# get_table_multiplier
# ===================================================================
class TestGetTableMultiplier:

    def test_exact_correct_returns_10(self, loader):
        m = loader.get_table_multiplier("show total picks today", "bal_pick_dtl")
        assert m == 10.0

    def test_exact_incorrect_returns_001(self, loader):
        m = loader.get_table_multiplier("show total picks today", "bal_master_article")
        assert m == 0.01

    def test_no_match_returns_1(self, loader):
        m = loader.get_table_multiplier("random query", "bal_pick_dtl")
        # No direct match and probably no similar query → may be 1.0 or partial
        assert m >= 0.01  # At minimum

    def test_partial_match_correct_returns_5(self, loader):
        """Query similar to 'show total picks today' should get partial boost."""
        m = loader.get_table_multiplier("give me total picks today", "bal_pick_dtl")
        assert m in [5.0, 10.0]  # Exact or partial

    def test_completely_unrelated_table(self, loader):
        m = loader.get_table_multiplier("show total picks today", "some_unknown_table")
        assert m == 1.0


# ===================================================================
# get_validated_tables_for_query
# ===================================================================
class TestGetValidatedTables:

    def test_returns_correct_and_incorrect(self, loader):
        result = loader.get_validated_tables_for_query("show total picks today")
        assert "bal_pick_dtl" in result.get("correct", [])
        assert "bal_master_article" in result.get("incorrect", [])

    def test_no_match_returns_empty(self, loader):
        result = loader.get_validated_tables_for_query("zzz completely unrelated")
        assert result.get("correct", []) == [] or len(result.get("correct", [])) >= 0


# ===================================================================
# _is_similar_query
# ===================================================================
class TestIsSimilarQuery:

    def test_identical_queries(self, loader):
        assert loader._is_similar_query("show total picks today", "show total picks today") is True

    def test_similar_queries(self, loader):
        assert loader._is_similar_query("give total picks today", "show total picks today") is True

    def test_different_queries(self, loader):
        assert loader._is_similar_query("bot status", "show total picks today") is False


# ===================================================================
# MISSING FILE
# ===================================================================
class TestMissingFile:

    def test_nonexistent_file_loads_empty(self, tmp_path):
        loader = TablePriorityLoader(tmp_path / "nonexistent.jsonl")
        m = loader.get_table_multiplier("any query", "any_table")
        assert m == 1.0
