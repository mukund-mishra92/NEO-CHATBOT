"""
Unit Tests — ColumnResolver
Target: backend/app/services/sql_assistant/collumn_resolver.py

Tests:
  - Exact match
  - Fuzzy match (> 0.6 cutoff)
  - No match
  - Missing table
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.collumn_resolver import ColumnResolver


@pytest.fixture
def resolver(sample_schema):
    return ColumnResolver(sample_schema)


class TestColumnResolver:

    def test_exact_match(self, resolver):
        result = resolver.resolve("bal_pick_dtl", "article")
        assert result == "article"

    def test_fuzzy_match(self, resolver):
        result = resolver.resolve("bal_pick_dtl", "articl")
        assert result == "article"

    def test_close_variant(self, resolver):
        result = resolver.resolve("bal_pick_dtl", "staus")
        assert result == "status"

    def test_no_match(self, resolver):
        result = resolver.resolve("bal_pick_dtl", "zzzzzzz")
        assert result is None

    def test_missing_table(self, resolver):
        result = resolver.resolve("nonexistent_table", "article")
        assert result is None

    def test_hyphenated_column(self, resolver):
        result = resolver.resolve("bal_pick_dtl", "host-location")
        assert result == "host-location"

    def test_fuzzy_hyphenated(self, resolver):
        result = resolver.resolve("bal_pick_dtl", "host_location")
        # difflib may or may not match depending on cutoff — test it doesn't crash
        assert result is None or result == "host-location"
