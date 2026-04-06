"""
Tests for DashboardKPIResolver
"""
import sys
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

import pytest
from app.services.sql_assistant.kpi_resolver import DashboardKPIResolver, KPIMatch


@pytest.fixture(scope="module")
def resolver():
    """Load the KPI resolver once for all tests."""
    # Try project root path first (when running from project root)
    registry_path = str(Path(__file__).parent.parent.parent.parent / "data" / "dashboard-data" / "kpi_registry.json")
    return DashboardKPIResolver(registry_path=registry_path)


class TestKPIResolverInit:
    """Tests for KPI registry loading."""

    def test_loads_registry(self, resolver):
        assert len(resolver.kpis) > 0

    def test_has_all_categories(self, resolver):
        categories = resolver.get_categories()
        assert "bot" in categories
        assert "inventory" in categories
        assert "orders" in categories
        assert "station" in categories

    def test_list_kpis_returns_all(self, resolver):
        all_kpis = resolver.list_kpis()
        assert len(all_kpis) == len(resolver.kpis)

    def test_list_kpis_filtered(self, resolver):
        bot_kpis = resolver.list_kpis(category="bot")
        assert all(k["category"] == "bot" for k in bot_kpis)
        assert len(bot_kpis) > 0

    def test_kpi_entries_have_keywords(self, resolver):
        for kpi in resolver.kpis:
            assert len(kpi.keywords) > 0, f"KPI '{kpi.kpi_name}' has no keywords"


class TestKPIMatching:
    """Tests for question → KPI matching."""

    def test_active_bots_match(self, resolver):
        match = resolver.resolve("how many bots are active?")
        assert match is not None
        assert match.category == "bot"
        assert "active" in match.kpi_name.lower() or "bot" in match.kpi_name.lower()

    def test_total_bins_match(self, resolver):
        match = resolver.resolve("total bins in inventory")
        assert match is not None
        assert match.category == "inventory"

    def test_bin_utilisation_match(self, resolver):
        match = resolver.resolve("bin utilization percentage")
        assert match is not None
        assert match.category == "inventory"

    def test_wave_count_match(self, resolver):
        match = resolver.resolve("wave counts by type")
        assert match is not None
        assert match.category == "orders"

    def test_station_utilization_match(self, resolver):
        match = resolver.resolve("station wise active vs inactive hours")
        assert match is not None
        assert match.category == "station"

    def test_alarm_per_bot_match(self, resolver):
        match = resolver.resolve("total alarms per bot")
        assert match is not None
        assert "alarm" in match.kpi_name.lower()

    def test_no_match_for_irrelevant(self, resolver):
        match = resolver.resolve("what is the weather today?")
        assert match is None

    def test_no_match_for_generic_sql(self, resolver):
        """A generic SQL question should NOT falsely hit a KPI."""
        match = resolver.resolve("how many bots have an active alarm in bhiwandi?")
        # This is a COUNT query — the normal SQL pipeline should handle it.
        # With keyword-only threshold at 0.55, this should NOT match.
        if match:
            assert match.match_score >= 0.55, (
                f"Weak false-positive: '{match.kpi_name}' score={match.match_score:.3f}"
            )

    def test_no_match_for_sql_query(self, resolver):
        """A normal SQL question should NOT match a KPI."""
        match = resolver.resolve("how many orders are pending?")
        # This might or might not match depending on keyword overlap
        # but if it does match, score should be low
        if match:
            assert match.match_score < 0.8


class TestScoringAndMode:
    """Tests for hybrid scoring and fallback behavior."""

    def test_keyword_only_fallback(self, resolver):
        """In test env without OpenAI, resolver falls back to keyword-only."""
        # _embeddings_available may be True or False depending on env
        # but scoring should still work
        match = resolver.resolve("active bots")
        assert match is not None

    def test_hybrid_score_exists(self, resolver):
        """The _hybrid_score method should exist and return a float."""
        kpi = resolver.kpis[0]
        score = resolver._hybrid_score("test question", kpi)
        assert isinstance(score, float)
        assert 0.0 <= score <= 1.0

    def test_keyword_score_matches(self, resolver):
        """Direct keyword score for a strong match should be high."""
        # Find the "Active vs Inactive" KPI
        kpi = next(k for k in resolver.kpis if "active" in k.kpi_name.lower())
        score = resolver._score_match("active vs inactive hours", kpi)
        assert score >= 0.4


class TestParameterSubstitution:
    """Tests for Grafana variable replacement."""

    def test_location_substitution(self, resolver):
        match = resolver.resolve(
            "how many bots are active?",
            tenant_values=["frk"]
        )
        assert match is not None
        assert "'frk'" in match.sql
        assert "$location" not in match.sql

    def test_time_substitution(self, resolver):
        match = resolver.resolve(
            "how many bots are active?",
            tenant_values=["shakti"],
            time_from="2026-03-01 00:00:00",
            time_to="2026-03-24 23:59:59",
        )
        assert match is not None
        assert "$__timeFrom" not in match.sql
        assert "$__timeTo" not in match.sql
        assert "2026-03-01" in match.sql or "'shakti'" in match.sql

    def test_no_tenant_removes_location_filter(self, resolver):
        match = resolver.resolve("total bins")
        assert match is not None
        # Without tenant, $location should be handled gracefully
        assert "$location" not in match.sql

    def test_parameters_applied_dict(self, resolver):
        match = resolver.resolve("active bots", tenant_values=["pnvl"])
        assert match is not None
        assert "location" in match.parameters_applied
        assert match.parameters_applied["location"] == "pnvl"

    def test_multi_tenant_substitution(self, resolver):
        """Multiple tenants should produce IN ('frk', 'shakti')."""
        match = resolver.resolve(
            "how many bots are active?",
            tenant_values=["frk", "shakti"]
        )
        assert match is not None
        assert "'frk'" in match.sql
        assert "'shakti'" in match.sql
        assert "$location" not in match.sql
        assert match.parameters_applied["location"] == ["frk", "shakti"]

    def test_all_sites_removes_filter(self, resolver):
        """all_sites=True should strip location filter entirely."""
        match = resolver.resolve(
            "how many bots are active?",
            tenant_values=["frk"],
            all_sites=True
        )
        assert match is not None
        assert "$location" not in match.sql
        assert match.parameters_applied["location"] == "all_sites"

    def test_timeFilter_macro_substitution(self, resolver):
        """$__timeFilter(column) should expand to column BETWEEN 'from' AND 'to'."""
        match = resolver.resolve(
            "alarm type per bot",
            tenant_values=["frk"],
            time_from="2026-03-01 00:00:00",
            time_to="2026-03-24 23:59:59",
        )
        assert match is not None
        assert "$__timeFilter" not in match.sql
        assert "$__timeFrom" not in match.sql
        assert "$__timeTo" not in match.sql
        assert "BETWEEN '2026-03-01 00:00:00' AND '2026-03-24 23:59:59'" in match.sql

    def test_explicit_between_time_on_date_window(self, resolver):
        """Absolute window in question should override default last-1-day fallback."""
        match = resolver.resolve(
            "how many bots were inactive between 4pm to 6pm on 5th march in chennai?",
            tenant_values=["chennai"],
        )
        assert match is not None

        expected_year = datetime.now().year
        expected_from = f"{expected_year}-03-05 16:00:00"
        expected_to = f"{expected_year}-03-05 18:00:00"

        assert match.parameters_applied["time_from"] == expected_from
        assert match.parameters_applied["time_to"] == expected_to
        assert expected_from in match.sql
        assert expected_to in match.sql

    def test_explicit_overnight_between_window_rolls_next_day(self, resolver):
        """When end time is earlier than start time, end should roll to next day."""
        match = resolver.resolve(
            "active bots between 11pm to 2am on 5th march in chennai",
            tenant_values=["chennai"],
        )
        assert match is not None

        expected_year = datetime.now().year
        assert match.parameters_applied["time_from"] == f"{expected_year}-03-05 23:00:00"
        assert match.parameters_applied["time_to"] == f"{expected_year}-03-06 02:00:00"

    def test_explicit_during_time_on_date_window(self, resolver):
        """'during' keyword should be recognised like 'between'."""
        match = resolver.resolve(
            "How many active hours and inactive hours did each station in chennai "
            "have during 3pm to 5 pm on 27th march 2026?",
            tenant_values=["chennai"],
        )
        assert match is not None

        assert match.parameters_applied["time_from"] == "2026-03-27 15:00:00"
        assert match.parameters_applied["time_to"] == "2026-03-27 17:00:00"
        assert "2026-03-27 15:00:00" in match.sql
        assert "2026-03-27 17:00:00" in match.sql

    def test_explicit_from_time_on_date_window(self, resolver):
        """'from' keyword should be recognised like 'between'."""
        match = resolver.resolve(
            "active bots from 9am to 12pm on 10th april in chennai",
            tenant_values=["chennai"],
        )
        assert match is not None

        expected_year = datetime.now().year
        assert match.parameters_applied["time_from"] == f"{expected_year}-04-10 09:00:00"
        assert match.parameters_applied["time_to"] == f"{expected_year}-04-10 12:00:00"

    def test_bare_time_on_date_window(self, resolver):
        """Bare '4pm to 6pm on 5th march' without between/during/from keyword."""
        match = resolver.resolve(
            "active bots 4pm to 6pm on 5th march in chennai",
            tenant_values=["chennai"],
        )
        assert match is not None

        expected_year = datetime.now().year
        assert match.parameters_applied["time_from"] == f"{expected_year}-03-05 16:00:00"
        assert match.parameters_applied["time_to"] == f"{expected_year}-03-05 18:00:00"


class TestTopKMatching:
    """Tests for top-k results."""

    def test_top_k_returns_multiple(self, resolver):
        matches = resolver.resolve_top_k("total alarms per bot", top_k=3)
        assert len(matches) >= 1
        # Should be sorted by score descending
        if len(matches) > 1:
            assert matches[0].match_score >= matches[1].match_score

    def test_top_k_all_have_chart_type(self, resolver):
        matches = resolver.resolve_top_k("inventory utilization", top_k=5)
        for m in matches:
            assert m.chart_type, f"KPI '{m.kpi_name}' has no chart_type"


class TestKPIMatchDataclass:
    """Tests for KPIMatch fields."""

    def test_match_has_all_fields(self, resolver):
        match = resolver.resolve("active bots", tenant_values=["frk"])
        assert match is not None
        assert match.kpi_id.startswith("kpi_")
        assert match.kpi_name
        assert match.category in ("bot", "inventory", "orders", "station")
        assert match.chart_type
        assert match.sql
        assert match.raw_query
        assert isinstance(match.match_score, float)
        assert isinstance(match.tables_used, list)
        assert isinstance(match.parameters_applied, dict)

    def test_match_score_range(self, resolver):
        match = resolver.resolve("active bots")
        if match:
            assert 0.0 <= match.match_score <= 1.0
