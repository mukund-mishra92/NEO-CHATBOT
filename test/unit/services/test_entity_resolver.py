"""
Unit Tests — EntityResolver
Target: backend/app/services/sql_assistant/entity_resolver.py

Tests:
  - BOT resolution (bot 1 → BOT-0001)
  - STATION resolution
  - WAVE resolution
  - ORDER resolution
  - BIN resolution
  - Substitution in question text
  - Edge cases (no match, multiple entities)
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.entity_resolver import EntityResolver


@pytest.fixture
def resolver():
    return EntityResolver()


# ===================================================================
# BOT RESOLUTION
# ===================================================================
class TestBotResolution:

    def test_bot_with_space(self, resolver):
        result = resolver.resolve("what is bot 4 doing")
        assert result["BOT_ID"] == "BOT-0004"

    def test_bot_with_dash(self, resolver):
        result = resolver.resolve("status of bot-04")
        assert result["BOT_ID"] == "BOT-0004"

    def test_bot_with_underscore(self, resolver):
        result = resolver.resolve("details for bot_12")
        assert result["BOT_ID"] == "BOT-0012"

    def test_bot_single_digit(self, resolver):
        result = resolver.resolve("bot 1")
        assert result["BOT_ID"] == "BOT-0001"

    def test_bot_four_digit(self, resolver):
        result = resolver.resolve("bot 9999")
        assert result["BOT_ID"] == "BOT-9999"

    def test_bot_case_insensitive(self, resolver):
        result = resolver.resolve("BOT 5 status")
        assert result["BOT_ID"] == "BOT-0005"


# ===================================================================
# STATION RESOLUTION
# ===================================================================
class TestStationResolution:

    def test_station_basic(self, resolver):
        result = resolver.resolve("scans at station 3")
        assert result["STATION_ID"] == "STATION-0003"

    def test_station_dash(self, resolver):
        result = resolver.resolve("station-10 performance")
        assert result["STATION_ID"] == "STATION-0010"


# ===================================================================
# WAVE RESOLUTION
# ===================================================================
class TestWaveResolution:

    def test_wave_basic(self, resolver):
        result = resolver.resolve("details of wave 1234")
        assert result["WAVE_ID"] == "WAVE-001234"

    def test_wave_small_number(self, resolver):
        result = resolver.resolve("wave 5 status")
        assert result["WAVE_ID"] == "WAVE-000005"


# ===================================================================
# ORDER RESOLUTION
# ===================================================================
class TestOrderResolution:

    def test_order_basic(self, resolver):
        result = resolver.resolve("status of order 456")
        assert result["ORDER_ID"] == "ORD-000456"

    def test_order_with_dash(self, resolver):
        result = resolver.resolve("order-100 tracking")
        assert result["ORDER_ID"] == "ORD-000100"


# ===================================================================
# BIN RESOLUTION
# ===================================================================
class TestBinResolution:

    def test_bin_basic(self, resolver):
        result = resolver.resolve("items in bin 23")
        assert result["BIN_ID"] == "BIN-0023"

    def test_bin_single_digit(self, resolver):
        result = resolver.resolve("bin 1 contents")
        assert result["BIN_ID"] == "BIN-0001"


# ===================================================================
# MULTIPLE ENTITIES
# ===================================================================
class TestMultipleEntities:

    def test_bot_and_station(self, resolver):
        result = resolver.resolve("bot 3 at station 5")
        assert result["BOT_ID"] == "BOT-0003"
        assert result["STATION_ID"] == "STATION-0005"

    def test_all_entities(self, resolver):
        result = resolver.resolve("bot 1 station 2 wave 3 order 4 bin 5")
        assert len(result) == 5
        assert result["BOT_ID"] == "BOT-0001"
        assert result["STATION_ID"] == "STATION-0002"
        assert result["WAVE_ID"] == "WAVE-000003"
        assert result["ORDER_ID"] == "ORD-000004"
        assert result["BIN_ID"] == "BIN-0005"


# ===================================================================
# NO MATCH
# ===================================================================
class TestNoMatch:

    def test_no_entities_found(self, resolver):
        result = resolver.resolve("show me total picks today")
        assert result == {}

    def test_partial_word_no_match(self, resolver):
        """'bottom' should not match 'bot'."""
        result = resolver.resolve("show me the bottom 10 articles")
        assert "BOT_ID" not in result


# ===================================================================
# SUBSTITUTION
# ===================================================================
class TestSubstitution:

    def test_substitute_bot(self, resolver):
        entities = {"BOT_ID": "BOT-0004"}
        result = resolver.substitute("what is bot 4 doing", entities)
        assert "BOT-0004" in result
        assert "bot 4" not in result.lower()

    def test_substitute_station(self, resolver):
        entities = {"STATION_ID": "STATION-0005"}
        result = resolver.substitute("scans at station 5", entities)
        assert "STATION-0005" in result

    def test_substitute_multiple(self, resolver):
        entities = {"BOT_ID": "BOT-0003", "STATION_ID": "STATION-0005"}
        result = resolver.substitute("bot 3 at station 5", entities)
        assert "BOT-0003" in result
        assert "STATION-0005" in result

    def test_substitute_no_entities(self, resolver):
        result = resolver.substitute("show picks today", {})
        assert result == "show picks today"
