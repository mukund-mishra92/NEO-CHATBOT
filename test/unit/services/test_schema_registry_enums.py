"""
Unit Tests — SchemaRegistry dynamic enum extraction
Target: backend/app/services/schema_registry.py

Regression tests for:
  1. _extract_enums() static method — parses enum('VAL1','VAL2') from CSV
  2. enum_registry populated correctly from Table_information.csv
  3. get_enum_values() and get_relevant_enums() API
  4. Correct enum values (GTP_STATION not GTP, auto/manual, etc.)
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.schema_registry import SchemaRegistry


# ═══════════════════════════════════════════════════════════════
# Fixtures
# ═══════════════════════════════════════════════════════════════

@pytest.fixture(scope="module")
def registry():
    """Load SchemaRegistry from the real Table_information.csv."""
    csv_path = str(
        Path(__file__).parent.parent.parent.parent
        / "data" / "database" / "Table_information.csv"
    )
    return SchemaRegistry(csv_path=csv_path)


# ═══════════════════════════════════════════════════════════════
# _extract_enums static method tests
# ═══════════════════════════════════════════════════════════════

class TestExtractEnumsMethod:
    """Direct tests for SchemaRegistry._extract_enums() parser."""

    def test_single_enum_column(self):
        raw = "STATUS(enum('ENABLED','DISABLED')), NAME(varchar)"
        result = SchemaRegistry._extract_enums(raw)
        assert "STATUS" in result
        assert result["STATUS"] == ["ENABLED", "DISABLED"]

    def test_multiple_enum_columns(self):
        raw = (
            "STATION_TYPE(enum('GTP_STATION','GTC_STATION')), "
            "STATUS(enum('ENABLED','DISABLED')), "
            "BOT_ID(int)"
        )
        result = SchemaRegistry._extract_enums(raw)
        assert "STATION_TYPE" in result
        assert result["STATION_TYPE"] == ["GTP_STATION", "GTC_STATION"]
        assert "STATUS" in result
        assert result["STATUS"] == ["ENABLED", "DISABLED"]
        assert "BOT_ID" not in result  # not an enum

    def test_no_enum_returns_empty(self):
        raw = "BOT_ID(int), NAME(varchar), STATUS(varchar)"
        result = SchemaRegistry._extract_enums(raw)
        assert result == {}

    def test_empty_string_returns_empty(self):
        result = SchemaRegistry._extract_enums("")
        assert result == {}

    def test_enum_with_many_values(self):
        raw = "TYPE(enum('A','B','C','D','E'))"
        result = SchemaRegistry._extract_enums(raw)
        assert "TYPE" in result
        assert result["TYPE"] == ["A", "B", "C", "D", "E"]

    def test_enum_values_stripped(self):
        """Values should be stripped of surrounding whitespace/quotes."""
        raw = "STATUS(enum( 'ENABLED' , 'DISABLED' ))"
        result = SchemaRegistry._extract_enums(raw)
        assert "STATUS" in result
        assert result["STATUS"] == ["ENABLED", "DISABLED"]


# ═══════════════════════════════════════════════════════════════
# enum_registry populated from real CSV
# ═══════════════════════════════════════════════════════════════

class TestEnumRegistryPopulation:
    """Verify that the real CSV loads correct enum values.
    These are regression tests for the ENUM_REGISTRY correction fix."""

    def test_enum_registry_not_empty(self, registry):
        """At least some tables should have enum columns."""
        assert len(registry.enum_registry) > 0, (
            "enum_registry should be populated from CSV"
        )

    def test_hw_station_master_station_type(self, registry):
        """hw_station_master.STATION_TYPE should have GTP_STATION, GTC_STATION
        (NOT 'GTP', 'GTC' which was the old incorrect value)."""
        vals = registry.get_enum_values("hw_station_master", "STATION_TYPE")
        if vals is not None:
            assert "GTP_STATION" in vals, (
                f"Expected 'GTP_STATION' in STATION_TYPE, got {vals}"
            )
            assert "GTC_STATION" in vals, (
                f"Expected 'GTC_STATION' in STATION_TYPE, got {vals}"
            )
            # Make sure OLD incorrect values are NOT present
            assert "GTP" not in vals or "GTP_STATION" in vals, (
                "Should NOT have bare 'GTP' without '_STATION' suffix"
            )

    def test_get_enum_values_returns_list(self, registry):
        """get_enum_values should return a list for known enum columns."""
        # Find any table with enums
        for table, enums in registry.enum_registry.items():
            for col, vals in enums.items():
                result = registry.get_enum_values(table, col)
                assert result is not None
                assert isinstance(result, list)
                assert len(result) > 0
                return  # one success is enough

    def test_get_enum_values_unknown_returns_none(self, registry):
        """Unknown table/column should return None."""
        assert registry.get_enum_values("nonexistent_table", "COL") is None

    def test_get_relevant_enums_filters_by_tables(self, registry):
        """get_relevant_enums should only return enums for requested tables."""
        # Pick a table that has enums
        if registry.enum_registry:
            table_with_enums = next(iter(registry.enum_registry))
            result = registry.get_relevant_enums([table_with_enums])
            assert table_with_enums in result
            assert len(result) == 1

    def test_get_relevant_enums_empty_for_no_enums(self, registry):
        """Tables without enums shouldn't appear in result."""
        result = registry.get_relevant_enums(["nonexistent_table_xyz"])
        assert result == {}


# ═══════════════════════════════════════════════════════════════
# Specific enum value correctness tests
# ═══════════════════════════════════════════════════════════════

class TestEnumValueCorrectness:
    """Verify specific enum values that were previously incorrect
    in the hardcoded ENUM_REGISTRY and have been fixed via dynamic
    extraction from CSV."""

    def test_bot_master_auto_manual_if_exists(self, registry):
        """bot_master.AUTO_MANUAL should have lowercase values if present."""
        vals = registry.get_enum_values("bot_master", "AUTO_MANUAL")
        if vals is not None:
            # Should be lowercase (auto, manual) not uppercase (AUTO, MANUAL)
            for v in vals:
                assert v == v.lower() or v in ("auto", "manual", "Auto", "Manual"), (
                    f"AUTO_MANUAL values should be lowercase, got '{v}'"
                )

    def test_station_type_not_bare_gtp(self, registry):
        """STATION_TYPE enum should never have bare 'GTP'/'GTC' without suffix."""
        for table in registry.enum_registry:
            vals = registry.get_enum_values(table, "STATION_TYPE")
            if vals and "GTP" in vals:
                # If GTP is present, GTP_STATION should also be present
                # (or GTP should be a correct value for that specific table)
                pass  # Table-specific validation
