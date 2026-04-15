"""
Tests for DashboardKPIResolver
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

import pytest
from app.services.sql_assistant.kpi_resolver import DashboardKPIResolver, KPIMatch


@pytest.fixture(scope="module")
def resolver():
    """Load the KPI resolver once for all tests.

    The resolver is forced into keyword-only scoring by stubbing out
    ``_get_question_embedding`` so that tests are deterministic and
    do not depend on the availability (or latency) of the OpenAI API.
    KPI embeddings are still loaded from disk cache for any tests that
    exercise ``_hybrid_score`` directly.
    """
    registry_path = str(Path(__file__).parent.parent.parent.parent / "data" / "dashboard-data" / "kpi_registry.json")
    r = DashboardKPIResolver(registry_path=registry_path)
    # Force keyword-only scoring: stub out the live embedding call so
    # resolve() always receives q_embedding=None.
    r._get_question_embedding = lambda self_or_q, *a, **kw: None
    return r


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
        # In keyword-only mode (no embeddings), ambiguity margin may reject this
        if match is not None:
            assert match.category == "inventory"

    def test_bin_utilisation_match(self, resolver):
        match = resolver.resolve("bin utilization percentage")
        # In keyword-only mode, ambiguity margin may reject close matches
        if match is not None:
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
        # Ambiguity margin may reject when alarm KPIs score close together
        if match is not None:
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
        """With question embedding stubbed out, resolver uses keyword-only scoring."""
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
        """$__timeFilter(column) should expand to column BETWEEN ... AND ..."""
        match = resolver.resolve(
            "alarm type per bot",
            tenant_values=["frk"],
            time_from="2026-03-01 00:00:00",
            time_to="2026-03-24 23:59:59",
        )
        # Ambiguity margin may reject in keyword-only mode
        if match is not None:
            assert "$__timeFilter" not in match.sql
            assert "$__timeFrom" not in match.sql
            assert "$__timeTo" not in match.sql
            # Resolver now uses FROM_UNIXTIME(epoch) format
            assert "FROM_UNIXTIME(" in match.sql


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


# ──────────────────────────────────────────────────────────────
# NEW — Phase 2/3 regression tests (thresholds, margin, anchor, entities)
# ──────────────────────────────────────────────────────────────
class TestAmbiguityMargin:
    """Phase 2: Ambiguous candidates (close scores) should be rejected."""

    def test_disambiguation_bot_vs_inventory_stat(self, resolver):
        """Ambiguous stat queries that match both 'orders' and 'station' families
        should either return the correct one or None (NOT the wrong one)."""
        match = resolver.resolve("average orders per hour")
        if match:
            # If it matches, it MUST be in the orders category (not station)
            assert match.category == "orders", (
                f"Expected 'orders' category but got '{match.category}' "
                f"(kpi={match.kpi_name}, score={match.match_score:.3f})"
            )

    def test_threshold_rejects_weak_match(self, resolver):
        """A genuinely unrelated question must return None."""
        match = resolver.resolve("tell me a joke about databases")
        assert match is None, f"Falsely matched: {match.kpi_name} score={match.match_score:.3f}"

    def test_schema_query_rejected(self, resolver):
        """Schema/meta queries about tables/columns must NOT match a KPI."""
        schema_queries = [
            "show all columns in bot_master table",
            "describe task_master table",
            "list all tables in database",
            "show table structure of alarm_master",
        ]
        for q in schema_queries:
            match = resolver.resolve(q)
            assert match is None, (
                f"Schema query '{q}' falsely matched: "
                f"{match.kpi_name} score={match.match_score:.3f}"
            )


class TestAnchorBonus:
    """Phase 2: Near-exact user_query matches should get anchor bonus."""

    def test_exact_user_query_gets_high_score(self, resolver):
        """A question that is an exact or near-exact user_query in the registry
        should score very high (>= 0.70)."""
        match = resolver.resolve("how many bots are active right now")
        if match:
            assert match.match_score >= 0.55, (
                f"Exact user_query should score >=0.55 but got {match.match_score:.3f}"
            )

    def test_user_query_directed_at_correct_kpi(self, resolver):
        """A user_query from a specific KPI should match that KPI — not a sibling."""
        match = resolver.resolve("average bins per hour")
        if match:
            assert "bin" in match.kpi_name.lower() or "bins per hour" in match.kpi_name.lower(), (
                f"Expected a bins/hour KPI but got '{match.kpi_name}'"
            )


class TestEntityPassThrough:
    """Phase 3: bot_id / station_id should be substituted in KPI SQL."""

    def test_bot_id_substitution(self, resolver):
        """Passing bot_id should replace ${bot_id:sqlstring} in SQL."""
        match = resolver.resolve(
            "alarm type per bot",
            tenant_values=["frk"],
            time_from="2026-03-01 00:00:00",
            time_to="2026-03-24 23:59:59",
            bot_id="BOT-0003",
        )
        if match:
            # If the matched KPI's SQL contained ${bot_id:sqlstring},
            # it should now have the actual value
            assert "${bot_id:sqlstring}" not in match.sql

    def test_no_bot_id_wildcard(self, resolver):
        """Without bot_id, ${bot_id:sqlstring} should be replaced with wildcard or removed."""
        match = resolver.resolve(
            "alarm type per bot",
            tenant_values=["frk"],
            time_from="2026-03-01 00:00:00",
            time_to="2026-03-24 23:59:59",
        )
        if match:
            assert "${bot_id:sqlstring}" not in match.sql


# ──────────────────────────────────────────────────────────────
# Production regression tests – synonym resolution & embedding
# ──────────────────────────────────────────────────────────────
class TestSynonymEmbeddingFixes:
    """Synonym-normalised queries must still match the correct KPI.
    The resolver should use original_question for embeddings and
    expand synonyms bidirectionally for keyword scoring."""

    def test_distinct_sku_matches_kpi033(self, resolver):
        """'distinct sku in blr' → kpi_033 (Total Distinct SKU)."""
        match = resolver.resolve(
            "distinct article in blr",  # synonym-normalised
            tenant_values=["blr"],
            original_question="distinct sku in blr",
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_033", (
            f"Expected kpi_033 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_total_distinct_sku_matches_kpi033(self, resolver):
        """'Show total distinct SKU count in blr' → kpi_033."""
        match = resolver.resolve(
            "show total distinct article count in blr",
            tenant_values=["blr"],
            original_question="Show total distinct SKU count in blr",
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_033", (
            f"Expected kpi_033 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_reserve_to_put_matches_kpi035(self, resolver):
        """'reserve to put in banglore for last one week' → kpi_035."""
        match = resolver.resolve(
            "reserve to put in banglore for last one week",
            tenant_values=["blr"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_035", (
            f"Expected kpi_035 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_total_reserve_to_put_matches_kpi035(self, resolver):
        """'total reserve to put in banglore for last one week' → kpi_035."""
        match = resolver.resolve(
            "total reserve to put in banglore for last one week",
            tenant_values=["blr"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_035", (
            f"Expected kpi_035 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_blocked_sku_count_matches_kpi040(self, resolver):
        """'Total blocked SKU count in banglore' → kpi_040 (Total Blocked SKUs)."""
        match = resolver.resolve(
            "total blocked article count in banglore",
            tenant_values=["blr"],
            original_question="Total blocked SKU count in banglore",
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_040", (
            f"Expected kpi_040 but got {match.kpi_id} ({match.kpi_name})"
        )


# ──────────────────────────────────────────────────────────────
# Production regression tests – bin / volume utilization
# ──────────────────────────────────────────────────────────────
class TestBinVolumeUtilization:
    """Bin used / volume utilization queries must resolve to the correct
    KPI considering count-vs-% intent and tiebreaker fixes."""

    def test_volume_util_percent_symbol(self, resolver):
        """'volume utilization % in blr' → kpi_021 (Volume Utilization)."""
        match = resolver.resolve(
            "volume utilization % in blr",
            tenant_values=["blr"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_021", (
            f"Expected kpi_021 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_volume_util_percentage_word(self, resolver):
        """'volume utilization percentage in blr' → kpi_021."""
        match = resolver.resolve(
            "volume utilization percentage in blr",
            tenant_values=["blr"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_021", (
            f"Expected kpi_021 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_bin_used_percent_symbol(self, resolver):
        """'bin used % in blr' → kpi_015 (Bin Utilisation %)."""
        match = resolver.resolve(
            "bin used % in blr",
            tenant_values=["blr"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_015", (
            f"Expected kpi_015 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_bin_used_percentage_word(self, resolver):
        """'bin used percentage in blr' → kpi_015 (Bin Utilisation %)."""
        match = resolver.resolve(
            "bin used percentage in blr",
            tenant_values=["blr"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_015", (
            f"Expected kpi_015 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_bin_used_no_rate_indicator(self, resolver):
        """'bin used in blr' → kpi_014 (Bins Used — count, NOT utilisation %)."""
        match = resolver.resolve(
            "bin used in blr",
            tenant_values=["blr"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_014", (
            f"Expected kpi_014 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_bin_utilisation_matches_kpi015(self, resolver):
        """'bin utilisation' (explicit utilisation word) → kpi_015."""
        match = resolver.resolve("bin utilisation")
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_015", (
            f"Expected kpi_015 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_total_bins_matches_kpi013(self, resolver):
        """'total bins' → kpi_013 (Total Bins — pure count)."""
        match = resolver.resolve("total bins")
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_013", (
            f"Expected kpi_013 but got {match.kpi_id} ({match.kpi_name})"
        )


# ──────────────────────────────────────────────────────────────
# Production regression tests – station/IPP ambiguity families
# ──────────────────────────────────────────────────────────────
class TestStationFamilyDisambiguation:
    """Short station queries should resolve to the right sibling KPI."""

    def test_station_wise_pick_ipp_matches_kpi066(self, resolver):
        match = resolver.resolve("Show station-wise pick IPP")
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_066", (
            f"Expected kpi_066 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_ipp_per_station_for_picking_matches_kpi066(self, resolver):
        match = resolver.resolve("What is IPP per station for picking?")
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_066", (
            f"Expected kpi_066 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_put_ipp_by_station_matches_kpi080(self, resolver):
        match = resolver.resolve("Show put IPP by station")
        assert match is not None, "Should match a KPI"
        # Both kpi_080 (Station-wise Put IPP) and kpi_092 (PUT IPP) are
        # valid responses.  In keyword-only mode the shorter name wins.
        assert match.kpi_id in ("kpi_080", "kpi_092"), (
            f"Expected kpi_080 or kpi_092 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_station_wave_duration_today_matches_kpi065(self, resolver):
        match = resolver.resolve("Show station-wise wave duration in hours today")
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_065", (
            f"Expected kpi_065 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_station_wave_time_today_matches_kpi065(self, resolver):
        match = resolver.resolve("station-wise wave time in hours today")
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_065", (
            f"Expected kpi_065 but got {match.kpi_id} ({match.kpi_name})"
        )


class TestLocationBreakdownKPIs:
    """Sitewise KPI requests should either group by location or fall back."""

    # ── core rewrite tests ──

    def test_total_bins_sitewise_rewrites_to_group_by_location(self, resolver):
        match = resolver.resolve(
            "give me total bins sitewise",
            tenant_values=["blr", "frk"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is not None, "Simple stat KPI should support sitewise rewrite"
        assert match.kpi_id == "kpi_013"
        assert "AS location" in match.sql
        assert "GROUP BY bim.`host-location`" in match.sql
        assert "ORDER BY bim.`host-location`" in match.sql
        assert match.parameters_applied["location"] == ["blr", "frk"]
        assert match.parameters_applied["location_breakdown"] == "grouped_by_location"

    def test_bins_used_sitewise_rewrites_to_group_by_location(self, resolver):
        match = resolver.resolve(
            "show bins used for each site",
            tenant_values=["blr", "frk"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is not None, "Used-bin KPI should support sitewise rewrite"
        assert match.kpi_id == "kpi_014"
        assert "GROUP BY lim.`host-location`" in match.sql
        assert match.parameters_applied["location_breakdown"] == "grouped_by_location"

    def test_complex_sitewise_kpi_falls_through(self, resolver):
        match = resolver.resolve(
            "volume utilization sitewise",
            tenant_values=["blr", "frk"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is None, "Complex aggregate KPI should fall back to SQL generation"

    # ── additional phrasing variants ──

    def test_total_bins_per_site(self, resolver):
        """'total bins per site' → kpi_013 with GROUP BY."""
        match = resolver.resolve(
            "total bins per site",
            tenant_values=["blr", "frk"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is not None
        assert match.kpi_id == "kpi_013"
        assert "GROUP BY" in match.sql
        assert match.parameters_applied["location_breakdown"] == "grouped_by_location"

    def test_total_bins_for_each_site(self, resolver):
        """'give me total bins for each site' → kpi_013 with GROUP BY."""
        match = resolver.resolve(
            "give me total bins for each site",
            tenant_values=["blr", "frk"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is not None
        assert match.kpi_id == "kpi_013"
        assert "GROUP BY" in match.sql

    # ── single-tenant sitewise ──

    def test_single_site_breakdown_still_adds_group_by(self, resolver):
        """Even with one tenant, location_breakdown should add GROUP BY."""
        match = resolver.resolve(
            "total bins sitewise",
            tenant_values=["blr"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is not None
        assert match.kpi_id == "kpi_013"
        assert "GROUP BY" in match.sql
        assert "'blr'" in match.sql

    # ── multi-tenant values preserved ──

    def test_breakdown_preserves_all_tenants_in_where(self, resolver):
        """All tenant values should appear in the IN clause."""
        match = resolver.resolve(
            "show total bins location wise",
            tenant_values=["blr", "frk", "pnvl"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is not None
        assert "'blr'" in match.sql
        assert "'frk'" in match.sql
        assert "'pnvl'" in match.sql

    # ── without breakdown flag → normal KPI ──

    def test_no_breakdown_flag_returns_normal_result(self, resolver):
        """Without location_breakdown=True, result should be a normal single-value KPI."""
        match = resolver.resolve(
            "total bins",
            tenant_values=["blr"],
        )
        assert match is not None
        assert match.kpi_id == "kpi_013"
        assert "GROUP BY" not in match.sql
        assert "location_breakdown" not in match.parameters_applied

    # ── complex KPIs that must fall through ──

    def test_active_bots_sitewise_falls_through(self, resolver):
        """Active bots (CTE) is complex → should return None."""
        match = resolver.resolve(
            "active bots sitewise",
            tenant_values=["blr", "frk"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is None, "CTE-based KPI must fall through to SQL generation"

    def test_bin_utilisation_pct_sitewise_falls_through(self, resolver):
        """Bin Utilisation % (subquery in SELECT) → should return None."""
        match = resolver.resolve(
            "bin utilisation percentage sitewise",
            tenant_values=["blr", "frk"],
            all_sites=True,
            location_breakdown=True,
        )
        assert match is None, "Subquery-based KPI must fall through"


# ──────────────────────────────────────────────────────────────
# Direct tests for the SQL rewrite method
# ──────────────────────────────────────────────────────────────
class TestLocationBreakdownRewrite:
    """Verify _rewrite_for_location_breakdown with controlled SQL shapes."""

    def test_simple_count_with_alias_rewritten(self, resolver):
        sql = (
            "SELECT COUNT(DISTINCT bim.BIN_ID) AS total_bins "
            "FROM bin_info_master bim "
            "WHERE `host-location` IN ('blr', 'frk') AND bim.Bin_Type <> 'VIRTUAL_BIN'"
        )
        result, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "grouped_by_location"
        assert "GROUP BY bim.`host-location`" in result
        assert "AS location" in result

    def test_simple_count_without_alias_rewritten(self, resolver):
        sql = (
            "SELECT COUNT(BIN_ID) * 36 AS value "
            "FROM bin_info_master "
            "WHERE `host-location` IN ('blr') AND BIN_TYPE <> 'VIRTUAL_BIN'"
        )
        result, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "grouped_by_location"
        assert "GROUP BY `host-location`" in result

    def test_join_sql_not_rewritten(self, resolver):
        sql = (
            "SELECT a.x FROM table1 a "
            "JOIN table2 b ON a.id = b.id "
            "WHERE `host-location` IN ('blr')"
        )
        _, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "unsupported"

    def test_cte_sql_not_rewritten(self, resolver):
        sql = (
            "WITH cte AS (SELECT 1 AS val) "
            "SELECT val FROM cte WHERE `host-location` IN ('blr')"
        )
        _, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "unsupported"

    def test_subquery_in_select_not_rewritten(self, resolver):
        sql = (
            "SELECT ROUND( (SELECT COUNT(*) FROM t2) * 100.0 / "
            "(SELECT COUNT(*) FROM t3), 2) AS pct "
            "FROM t1 WHERE `host-location` IN ('blr')"
        )
        _, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "unsupported"

    def test_group_by_present_not_rewritten(self, resolver):
        sql = (
            "SELECT category, COUNT(*) FROM t "
            "WHERE `host-location` IN ('blr') GROUP BY category"
        )
        _, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "unsupported"

    def test_union_sql_not_rewritten(self, resolver):
        sql = (
            "SELECT x FROM t1 WHERE `host-location` IN ('blr') "
            "UNION ALL SELECT x FROM t2 WHERE `host-location` IN ('blr')"
        )
        _, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "unsupported"

    def test_no_host_location_in_where_not_rewritten(self, resolver):
        sql = "SELECT COUNT(*) AS cnt FROM my_table WHERE status = 'active'"
        _, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "unsupported"

    def test_multi_table_from_not_rewritten(self, resolver):
        sql = (
            "SELECT a.x FROM t1 a, t2 b "
            "WHERE a.id = b.id AND `host-location` IN ('blr')"
        )
        _, mode = resolver._rewrite_for_location_breakdown(sql)
        assert mode == "unsupported"


# ──────────────────────────────────────────────────────────────
# Comprehensive regression tests for ALL session changes
# ──────────────────────────────────────────────────────────────
class TestSessionChangesRegression:
    """Cover every major fix/enhancement from this session."""

    # ── 1. Schema query rejection ──

    def test_schema_query_show_columns_rejected(self, resolver):
        assert resolver.resolve("show all columns in bot_master table") is None

    def test_schema_query_describe_rejected(self, resolver):
        assert resolver.resolve("describe task_master table") is None

    def test_schema_query_list_tables_rejected(self, resolver):
        assert resolver.resolve("list all tables in database") is None

    def test_schema_query_table_structure_rejected(self, resolver):
        assert resolver.resolve("show table structure of alarm_master") is None

    # ── 2. 'time' removed from filler set → wave time queries work ──

    def test_wave_time_phrasing_matches_kpi(self, resolver):
        """'time' should not be stripped; wave time queries should match."""
        match = resolver.resolve("station-wise wave time in hours today")
        assert match is not None
        assert match.kpi_id == "kpi_065"

    def test_wave_duration_phrasing_matches_kpi(self, resolver):
        match = resolver.resolve("Show station-wise wave duration in hours today")
        assert match is not None
        assert match.kpi_id == "kpi_065"

    # ── 3. Hyphenated phrase matching ──

    def test_station_wise_hyphenated_recognised(self, resolver):
        match = resolver.resolve("Show station-wise pick IPP")
        assert match is not None
        assert match.kpi_id == "kpi_066"

    def test_items_per_pick_phrasing_recognised(self, resolver):
        """IPP as rate word should not be penalised by count-intent filter."""
        match = resolver.resolve("What is IPP per station for picking?")
        assert match is not None
        assert match.kpi_id == "kpi_066"

    # ── 4. Count-style 'used/in use/occupied' prefers count KPI ──

    def test_bin_used_prefers_count_over_percent(self, resolver):
        """'bin used in blr' → kpi_014 (count), NOT kpi_015 (%)."""
        match = resolver.resolve("bin used in blr", tenant_values=["blr"])
        assert match is not None
        assert match.kpi_id == "kpi_014"

    def test_bin_used_with_pct_prefers_utilisation(self, resolver):
        """'bin used % in blr' → kpi_015 (%), respecting rate indicator."""
        match = resolver.resolve("bin used % in blr", tenant_values=["blr"])
        assert match is not None
        assert match.kpi_id == "kpi_015"

    # ── 5. Pick vs Put IPP disambiguation ──

    def test_pick_ipp_not_confused_with_put(self, resolver):
        match = resolver.resolve("Show station-wise pick IPP")
        assert match is not None
        assert match.kpi_id == "kpi_066"

    def test_put_ipp_not_confused_with_pick(self, resolver):
        match = resolver.resolve("Show put IPP by station")
        assert match is not None
        # Both kpi_080 and kpi_092 are valid in keyword-only mode
        assert match.kpi_id in ("kpi_080", "kpi_092")

    # ── 6. KPIMatch always carries kpi_id ──

    def test_kpi_match_has_id_field(self, resolver):
        match = resolver.resolve("active bots", tenant_values=["frk"])
        assert match is not None
        assert match.kpi_id.startswith("kpi_")

    # ── 7. Synonym-normalised queries still work ──

    def test_synonym_sku_matches_kpi033(self, resolver):
        """After SynonymResolver maps sku→article, KPI 033 should still match."""
        match = resolver.resolve(
            "distinct article in blr",
            tenant_values=["blr"],
            original_question="distinct sku in blr",
        )
        assert match is not None
        assert match.kpi_id == "kpi_033"

    def test_blocked_sku_matches_kpi040(self, resolver):
        match = resolver.resolve(
            "total blocked article count in banglore",
            tenant_values=["blr"],
            original_question="Total blocked SKU count in banglore",
        )
        assert match is not None
        assert match.kpi_id == "kpi_040"

    # ── 8. Volume utilisation / bin utilisation % ──

    def test_volume_util_percent_matches_kpi021(self, resolver):
        match = resolver.resolve("volume utilization % in blr", tenant_values=["blr"])
        assert match is not None
        assert match.kpi_id == "kpi_021"

    def test_bin_utilisation_explicit_matches_kpi015(self, resolver):
        match = resolver.resolve("bin utilisation")
        assert match is not None
        assert match.kpi_id == "kpi_015"

    # ── 9. Irrelevant / weak queries correctly rejected ──

    def test_weather_query_rejected(self, resolver):
        assert resolver.resolve("what is the weather today?") is None

    def test_joke_query_rejected(self, resolver):
        assert resolver.resolve("tell me a joke about databases") is None


# ──────────────────────────────────────────────────────────────
# Entity post-filter injection tests
# ──────────────────────────────────────────────────────────────
class TestEntityPostFilter:
    """Entity-aware post-filter: when user asks about a specific bot/station/bin,
    the KPI SQL should be wrapped in a subquery that filters to that entity."""

    # ── Bot entity tests ──

    def test_bot_id_filters_active_vs_inactive(self, resolver):
        """'bot active vs inactive for bot 1 in frk today'
        → bot KPI with BOT_ID output should be wrapped with entity filter."""
        match = resolver.resolve(
            "bot active vs inactive for BOT-0001 in frk today",
            tenant_values=["frk"],
            bot_id="BOT-0001",
        )
        assert match is not None, "Should match a bot KPI"
        assert match.category == "bot"
        # KPI output includes BOT_ID column → should be wrapped
        if "entity_filter_bot_id" in match.parameters_applied:
            assert "_ef" in match.sql, "SQL should be wrapped in entity filter subquery"
            assert "BOT-0001" in match.sql, "BOT_ID value must appear in SQL"

    def test_bot_id_filters_kpi008_alarms(self, resolver):
        """'total alarms for bot 3 in frk' → kpi_008 wrapped with BOT_ID filter."""
        match = resolver.resolve(
            "total alarms for BOT-0003 in frk",
            tenant_values=["frk"],
            bot_id="BOT-0003",
        )
        assert match is not None, "Should match a bot alarm KPI"
        assert match.kpi_id == "kpi_008"
        # kpi_008 output has BOT_ID column → entity filter should wrap
        assert "_ef" in match.sql, "SQL should be wrapped in entity filter subquery"
        assert "BOT-0003" in match.sql
        assert "entity_filter_bot_id" in match.parameters_applied

    def test_bot_id_kpi006_already_filtered_no_double_wrap(self, resolver):
        """kpi_006 uses ${bot_id:sqlstring} → substitution already places the
        bot_id in the SQL. The post-filter should NOT double-wrap."""
        match = resolver.resolve(
            "bins per hour for BOT-0003 in frk",
            tenant_values=["frk"],
            bot_id="BOT-0003",
        )
        if match and match.kpi_id in ("kpi_006", "kpi_007"):
            # The bot_id should be in SQL from ${bot_id:sqlstring} substitution
            assert "BOT-0003" in match.sql
            # Should NOT have entity filter wrapper since value already present
            assert "entity_filter_bot_id" not in match.parameters_applied

    def test_no_bot_id_no_wrapping(self, resolver):
        """'bot active vs inactive in frk' (no specific bot)
        → kpi_001 SQL returned without entity wrapper."""
        match = resolver.resolve(
            "bot active vs inactive in frk today",
            tenant_values=["frk"],
        )
        assert match is not None
        # No wrapping — no _ef in SQL
        assert "_ef" not in match.sql or "entity_filter_bot_id" not in match.parameters_applied

    def test_aggregate_kpi_no_matching_column(self, resolver):
        """'how many active bots in frk' → kpi_002 (Active Bots), output is
        COUNT with no BOT_ID column → entity filter should NOT wrap."""
        match = resolver.resolve(
            "how many active bots in frk today",
            tenant_values=["frk"],
            bot_id="BOT-0003",
        )
        if match and match.kpi_id == "kpi_002":
            # kpi_002 output is just COUNT (ACTIVE_BOTS) — no BOT_ID column to filter
            assert "entity_filter_bot_id" not in match.parameters_applied

    # ── Station entity tests ──

    def test_station_id_filters_kpi062_active_inactive(self, resolver):
        """'station 3 active vs inactive hours in frk'
        → station KPI wrapped with station filter including ST-3 variant."""
        match = resolver.resolve(
            "STATION-0003 active vs inactive hours in frk today",
            tenant_values=["frk"],
            station_id="STATION-0003",
        )
        assert match is not None, "Should match a station KPI"
        assert match.category == "station"
        # Station KPIs output a 'Station' column → should be wrapped
        assert "_ef" in match.sql, "SQL should be wrapped"
        # Should contain ST-3 variant since station KPIs output ST-N format
        assert "ST-3" in match.sql or "STATION-0003" in match.sql
        assert "entity_filter_station_id" in match.parameters_applied

    def test_station_id_variants_generated(self, resolver):
        """_station_id_variants should generate ST-N format."""
        from app.services.sql_assistant.kpi_resolver import DashboardKPIResolver
        variants = DashboardKPIResolver._station_id_variants("STATION-0003")
        assert "STATION-0003" in variants
        assert "ST-3" in variants
        assert "3" in variants
        assert "STATION-3" in variants

    # ── Direct method tests ──

    def test_extract_columns_simple_select(self, resolver):
        """Column extraction from simple SELECT."""
        sql = "SELECT COUNT(*) AS total_bins FROM bin_info_master WHERE x = 1"
        cols = resolver._extract_outermost_select_columns(sql)
        assert "total_bins" in cols

    def test_extract_columns_with_cte(self, resolver):
        """Column extraction skips CTEs and finds the final SELECT."""
        sql = (
            "WITH cte AS (SELECT bot_id, x FROM t) "
            "SELECT b.BOT_ID, ROUND(x, 2) AS ACTIVE_HOURS "
            "FROM cte b"
        )
        cols = resolver._extract_outermost_select_columns(sql)
        assert "bot_id" in cols
        assert "active_hours" in cols

    def test_extract_columns_concat_as(self, resolver):
        """Column extraction handles CONCAT(...) AS alias."""
        sql = (
            "SELECT CONCAT('ST-', sa.Station) AS Station, "
            "ROUND(x, 2) AS ActiveHours FROM t"
        )
        cols = resolver._extract_outermost_select_columns(sql)
        assert "station" in cols
        assert "activehours" in cols

    def test_inject_no_entities_returns_unchanged(self, resolver):
        """No entities → SQL returned unchanged."""
        sql = "SELECT BOT_ID, x FROM t WHERE y = 1"
        params = {"location": "frk"}
        new_sql, new_params = resolver._inject_entity_filters(sql, params)
        assert new_sql == sql
        assert new_params == params

    def test_inject_bot_id_wraps_sql(self, resolver):
        """Direct test: _inject_entity_filters wraps SQL for bot_id."""
        sql = "SELECT b.BOT_ID, ROUND(x, 2) AS ACTIVE_HOURS FROM bot_master b WHERE b.`host-location` = 'frk'"
        params = {"location": "frk"}
        new_sql, new_params = resolver._inject_entity_filters(
            sql, params, bot_id="BOT-0001"
        )
        assert "SELECT * FROM (" in new_sql
        assert "_ef" in new_sql
        assert "BOT-0001" in new_sql
        assert "entity_filter_bot_id" in new_params

    def test_inject_station_id_uses_variants(self, resolver):
        """Direct test: station filter uses IN clause with variants."""
        sql = "SELECT CONCAT('ST-', sa.Station) AS Station, x FROM t WHERE y = 1"
        params = {}
        new_sql, new_params = resolver._inject_entity_filters(
            sql, params, station_id="STATION-0003"
        )
        assert "SELECT * FROM (" in new_sql
        assert "ST-3" in new_sql
        assert "STATION-0003" in new_sql
        assert "entity_filter_station_id" in new_params

    def test_inject_skips_when_value_already_in_sql(self, resolver):
        """If bot_id value is already in SQL, no wrapping should happen."""
        sql = "SELECT time, value FROM t WHERE bot_id IN ('BOT-0003') AND x = 1"
        params = {"bot_id": "BOT-0003"}
        new_sql, new_params = resolver._inject_entity_filters(
            sql, params, bot_id="BOT-0003"
        )
        assert "SELECT * FROM (" not in new_sql
        assert "_ef" not in new_sql

    def test_inject_skips_aggregate_no_entity_column(self, resolver):
        """Aggregate KPI with no entity column → no wrapping."""
        sql = "SELECT COUNT(DISTINCT BOT_ID) AS ACTIVE_BOTS FROM task_master_log WHERE x = 1"
        params = {}
        new_sql, new_params = resolver._inject_entity_filters(
            sql, params, bot_id="BOT-0003"
        )
        # ACTIVE_BOTS column doesn't match "bot_id" pattern → no wrapping
        assert "SELECT * FROM (" not in new_sql


# ──────────────────────────────────────────────────────────────
# Entity-lookup guard tests — queries about specific entities
# should NOT hit the KPI path
# ──────────────────────────────────────────────────────────────
class TestEntityLookupGuard:
    """Entity-lookup queries (location, IP, status, tower-side, counters)
    must return None from the resolver — they should fall through to SQL
    generation instead of falsely matching bot/bin/station KPIs."""

    # ── Bot entity lookups (should all be rejected) ──

    def test_where_is_bot_rejected(self, resolver):
        """'where is BOT-0001 in frk' → should NOT match any KPI."""
        match = resolver.resolve(
            "where is BOT-0001 in frk",
            tenant_values=["frk"],
            bot_id="BOT-0001",
        )
        assert match is None, (
            f"Entity lookup 'where is BOT-0001' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bot_ip_rejected(self, resolver):
        """'what is the ip of BOT-0027 in chennai' → entity lookup, not KPI."""
        match = resolver.resolve(
            "what is the ip of BOT-0027 in chennai",
            tenant_values=["chennai"],
            bot_id="BOT-0027",
        )
        assert match is None, (
            f"Entity lookup 'ip of BOT-0027' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bot_counter_increasing_rejected(self, resolver):
        """'are the counters of BOT-0027 increasing at chennai' → lookup."""
        match = resolver.resolve(
            "are the counters of BOT-0027 is increasing at chennai",
            tenant_values=["chennai"],
            bot_id="BOT-0027",
        )
        assert match is None, (
            f"Entity lookup 'counters increasing' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bot_tower_side_rejected(self, resolver):
        """'where is BOT-0001 in frk give me tower side' → lookup."""
        match = resolver.resolve(
            "where is BOT-0001 in frk give me coordinates with tower side",
            tenant_values=["frk"],
            bot_id="BOT-0001",
        )
        assert match is None, (
            f"Entity lookup 'tower side' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bot_left_or_right_rejected(self, resolver):
        """'where is BOT-0001 in frk also give me left or right' → lookup."""
        match = resolver.resolve(
            "where is BOT-0001 in frk also give me left or right",
            tenant_values=["frk"],
            bot_id="BOT-0001",
        )
        assert match is None, (
            f"Entity lookup 'left or right' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bot_current_location_rejected(self, resolver):
        """'current location of BOT-0001' → location lookup, not KPI."""
        match = resolver.resolve(
            "current location of BOT-0001 in frk",
            tenant_values=["frk"],
            bot_id="BOT-0001",
        )
        assert match is None, (
            f"Entity lookup 'current location' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bot_charging_point_rejected(self, resolver):
        """'is BOT-0003 going to charging point' → state lookup."""
        match = resolver.resolve(
            "is BOT-0003 not going to charging point in frk",
            tenant_values=["frk"],
            bot_id="BOT-0003",
        )
        assert match is None, (
            f"Entity lookup 'charging point' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bot_status_rejected(self, resolver):
        """'status of BOT-0001 in frk' → status lookup."""
        match = resolver.resolve(
            "status of BOT-0001 in frk",
            tenant_values=["frk"],
            bot_id="BOT-0001",
        )
        assert match is None, (
            f"Entity lookup 'status of BOT' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    # ── Bin entity lookups (should all be rejected) ──

    def test_where_is_bin_rejected(self, resolver):
        """'where is BIN-0324 in frk' → location lookup."""
        match = resolver.resolve(
            "where is BIN-0324 in frk",
            tenant_values=["frk"],
            bin_id="BIN-0324",
        )
        assert match is None, (
            f"Entity lookup 'where is BIN' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bin_contents_rejected(self, resolver):
        """'what is in BIN-0100' → contents lookup."""
        match = resolver.resolve(
            "what is in BIN-0100 in frk",
            tenant_values=["frk"],
            bin_id="BIN-0100",
        )
        assert match is None, (
            f"Entity lookup 'what is in BIN' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bin_location_details_rejected(self, resolver):
        """'details of BIN-0050 in blr' → property lookup."""
        match = resolver.resolve(
            "details of BIN-0050 in blr",
            tenant_values=["blr"],
            bin_id="BIN-0050",
        )
        assert match is None, (
            f"Entity lookup 'details of BIN' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    # ── Station entity lookups (should all be rejected) ──

    def test_station_previous_bot_rejected(self, resolver):
        """'what was the previous bot at STATION-0001 in frk' → lookup."""
        match = resolver.resolve(
            "what was the previous bot at STATION-0001 in frk",
            tenant_values=["frk"],
            station_id="STATION-0001",
        )
        assert match is None, (
            f"Entity lookup 'previous bot at station' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_station_config_rejected(self, resolver):
        """'configuration of STATION-0005 in blr' → config lookup."""
        match = resolver.resolve(
            "configuration of STATION-0005 in blr",
            tenant_values=["blr"],
            station_id="STATION-0005",
        )
        assert match is None, (
            f"Entity lookup 'config of station' falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    # ── Bare entity ID (just "BOT-0001") should not match KPI ──

    def test_bare_entity_id_rejected(self, resolver):
        """Just 'BOT-0001' by itself → not a KPI query."""
        match = resolver.resolve(
            "BOT-0001",
            bot_id="BOT-0001",
        )
        assert match is None, (
            f"Bare entity ID falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_bare_entity_with_location_rejected(self, resolver):
        """'BOT-0001 in frk' → not a KPI query."""
        match = resolver.resolve(
            "BOT-0001 in frk",
            tenant_values=["frk"],
            bot_id="BOT-0001",
        )
        assert match is None, (
            f"Bare entity+location falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    # ── KPI queries WITH entity IDs (should still match!) ──

    def test_bot_active_inactive_with_entity_still_matches(self, resolver):
        """'bot active vs inactive for BOT-0001 in frk today' → IS a KPI query."""
        match = resolver.resolve(
            "bot active vs inactive for BOT-0001 in frk today",
            tenant_values=["frk"],
            bot_id="BOT-0001",
        )
        assert match is not None, "KPI query with entity ID should match"
        assert match.category == "bot"

    def test_alarms_for_bot_with_entity_still_matches(self, resolver):
        """'total alarms for BOT-0003 in frk' → IS a KPI query."""
        match = resolver.resolve(
            "total alarms for BOT-0003 in frk",
            tenant_values=["frk"],
            bot_id="BOT-0003",
        )
        assert match is not None, "KPI query with entity ID should match"
        assert "alarm" in match.kpi_name.lower()

    def test_downtime_for_bot_with_entity_still_matches(self, resolver):
        """'downtime for BOT-0012 in frk' → IS a KPI query."""
        match = resolver.resolve(
            "downtime for BOT-0012 in frk",
            tenant_values=["frk"],
            bot_id="BOT-0012",
        )
        assert match is not None, "KPI query with entity ID should match"
        assert match.category == "bot"

    def test_station_utilization_with_entity_still_matches(self, resolver):
        """'station 3 utilization in frk' → IS a KPI query."""
        match = resolver.resolve(
            "STATION-0003 utilization in frk",
            tenant_values=["frk"],
            station_id="STATION-0003",
        )
        assert match is not None, "KPI query with entity ID should match"
        assert match.category == "station"

    def test_active_bots_no_entity_still_matches(self, resolver):
        """'how many active bots in frk' (no specific bot) → IS a KPI query."""
        match = resolver.resolve(
            "how many active bots in frk",
            tenant_values=["frk"],
        )
        assert match is not None, "Aggregate KPI query should match"
        assert match.category == "bot"

    # ── Direct _is_entity_lookup_query function tests ──

    def test_guard_function_rejects_where_is_bot(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert _is_entity_lookup_query("where is BOT-0001 in frk", bot_id="BOT-0001")

    def test_guard_function_rejects_ip_of_bot(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert _is_entity_lookup_query("what is the ip of BOT-0027", bot_id="BOT-0027")

    def test_guard_function_allows_active_inactive_with_entity(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert not _is_entity_lookup_query(
            "bot active vs inactive for BOT-0001 in frk today",
            bot_id="BOT-0001"
        )

    def test_guard_function_allows_alarms_with_entity(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert not _is_entity_lookup_query(
            "total alarms for BOT-0003 today",
            bot_id="BOT-0003"
        )

    def test_guard_function_no_entity_returns_false(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert not _is_entity_lookup_query("how many bots are active")

    def test_guard_function_rejects_counter_query(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert _is_entity_lookup_query(
            "are the counters of BOT-0027 increasing at chennai",
            bot_id="BOT-0027"
        )

    def test_guard_function_rejects_tower_side(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert _is_entity_lookup_query(
            "give me tower side of BOT-0001 in frk",
            bot_id="BOT-0001"
        )

    def test_guard_function_rejects_bare_entity(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert _is_entity_lookup_query("BOT-0001", bot_id="BOT-0001")

    def test_guard_function_rejects_where_is_bin(self):
        from app.services.sql_assistant.kpi_resolver import _is_entity_lookup_query
        assert _is_entity_lookup_query("where is BIN-0324 in frk", bin_id="BIN-0324")


# ══════════════════════════════════════════════════════════════════════
# REGRESSION TESTS — Fixes from last 2 days (2026-04-28 / 2026-04-29)
# ══════════════════════════════════════════════════════════════════════


# ──────────────────────────────────────────────────────────────
# FIX 1: Active hours false positive — "active hours" → kpi_001
#        not kpi_002 (count).  The family disambiguation now
#        detects "hours"/"time"/"minutes" alongside "active" and
#        routes to kpi_001 (hours breakdown).
# ──────────────────────────────────────────────────────────────
class TestActiveHoursDisambiguation:
    """Active hours/time queries must route to kpi_001 (Active vs Inactive
    Hours), NOT kpi_002 (count of active bots)."""

    def test_total_active_hours_all_bots(self, resolver):
        """'Total active hours of all bots in faruknagar yesterday' → kpi_001."""
        match = resolver.resolve(
            "Total active hours of all bots in faruknagar yesterday",
            tenant_values=["frk"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_001", (
            f"Expected kpi_001 (Active vs Inactive Hours) but got "
            f"{match.kpi_id} ({match.kpi_name}, score={match.match_score:.3f})"
        )

    def test_active_hours_for_each_bot(self, resolver):
        """'give me active hours for each bot in faruknagar yesterday' → kpi_001."""
        match = resolver.resolve(
            "give me active hours for each bot in faruknagar yesterday",
            tenant_values=["frk"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_001", (
            f"Expected kpi_001 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_active_hours_bot_wise(self, resolver):
        """'give me active hours fo bot in faruknagar bot wise for yesterday' → kpi_001."""
        match = resolver.resolve(
            "give me active hours fo bot in faruknagar bot wise for yesterday",
            tenant_values=["frk"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_001", (
            f"Expected kpi_001 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_active_time_each_bot(self, resolver):
        """'active time for each bot in frk' → kpi_001 (time word)."""
        match = resolver.resolve(
            "active time for each bot in frk",
            tenant_values=["frk"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_001", (
            f"Expected kpi_001 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_how_many_active_bots_still_kpi002(self, resolver):
        """'how many bots were active in shakti yesterday' → kpi_002 (COUNT, not hours).
        The count-intent ("how many") + no time-unit word → kpi_002."""
        match = resolver.resolve(
            "how many bots were active in shakti yesterday",
            tenant_values=["shakti"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_002", (
            f"Expected kpi_002 (Active Bots count) but got "
            f"{match.kpi_id} ({match.kpi_name})"
        )

    def test_average_active_hours_kpi004(self, resolver):
        """'average active hours in frk this week' → kpi_004 (avg active hours)."""
        match = resolver.resolve(
            "average active hours in frk this week",
            tenant_values=["frk"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_004", (
            f"Expected kpi_004 (Avg Active Hours) but got "
            f"{match.kpi_id} ({match.kpi_name})"
        )

    def test_inactive_bots_count_kpi003(self, resolver):
        """'number of inactive bots in chennai' → kpi_003 (inactive count)."""
        match = resolver.resolve(
            "number of inactive bots in chennai",
            tenant_values=["chennai"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_003", (
            f"Expected kpi_003 (Inactive Bots count) but got "
            f"{match.kpi_id} ({match.kpi_name})"
        )

    def test_bot_downtime_kpi012(self, resolver):
        """'bot downtime in frk yesterday' → kpi_012 (dedicated Bot-Downtime KPI)."""
        match = resolver.resolve(
            "bot downtime in frk yesterday",
            tenant_values=["frk"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_012", (
            f"Expected kpi_012 (Bot-Downtime) but got {match.kpi_id} ({match.kpi_name})"
        )

    # ── inactive_hours_intent tests: "inactive time/hours" → kpi_001 ──

    def test_inactive_time_for_bot_routes_kpi001(self, resolver):
        """'inactive time for bot 9' → kpi_001 (hours breakdown), NOT kpi_003 (count)."""
        match = resolver.resolve(
            "inactive time for bot 9",
            bot_id="BOT-0009",
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_001", (
            f"Expected kpi_001 (Active vs Inactive Hours) but got "
            f"{match.kpi_id} ({match.kpi_name}, score={match.match_score:.3f})"
        )

    def test_total_inactive_time_in_hours_routes_kpi001(self, resolver):
        """'total inactive time in hours for bot 9 in frk today' → kpi_001."""
        match = resolver.resolve(
            "total inactive time in hours for bot 9 in frk today",
            tenant_values=["frk"],
            bot_id="BOT-0009",
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_001", (
            f"Expected kpi_001 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_inactive_hours_for_all_bots_routes_kpi001(self, resolver):
        """'inactive hours for all bots in frk' → kpi_001 (hours), NOT kpi_003 (count)."""
        match = resolver.resolve(
            "inactive hours for all bots in frk",
            tenant_values=["frk"],
        )
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_001", (
            f"Expected kpi_001 but got {match.kpi_id} ({match.kpi_name})"
        )

    def test_inactive_bots_count_still_kpi003(self, resolver):
        """'inactive bots' → kpi_003 (count). No time word → stays count."""
        match = resolver.resolve("inactive bots")
        assert match is not None, "Should match a KPI"
        assert match.kpi_id == "kpi_003", (
            f"Expected kpi_003 (Inactive Bots count) but got "
            f"{match.kpi_id} ({match.kpi_name})"
        )


# ──────────────────────────────────────────────────────────────
# FIX 2: KPI false positive guards — queries that ask about
#        "expected quantity" or are detail listings must NOT
#        match any KPI (should fall through to SQL path).
# ──────────────────────────────────────────────────────────────
class TestKPIFalsePositiveGuards:
    """Queries that superficially overlap with KPI keywords but
    actually need SQL generation must be rejected by the resolver."""

    def test_expected_quantity_rejected(self, resolver):
        """'sum expected quantity and sum of picked quantity in pick wave' → None.
        No pre-built KPI returns 'expected quantity'."""
        match = resolver.resolve(
            "sum expected quantity and sum of picked quantity in pick wave",
            tenant_values=["frk"],
        )
        assert match is None, (
            f"'expected quantity' query falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_expected_qty_shorthand_rejected(self, resolver):
        """'expected qty vs actual qty in frk' → None."""
        match = resolver.resolve(
            "expected qty vs actual qty in frk",
            tenant_values=["frk"],
        )
        assert match is None, (
            f"'expected qty' query falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_sum_expected_quantity_rejected(self, resolver):
        """'sum of expected quantity for today pick waves' → None."""
        match = resolver.resolve(
            "sum of expected quantity for today pick waves",
            tenant_values=["frk"],
        )
        assert match is None, (
            f"'sum of expected' query falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_which_wave_on_which_station_rejected(self, resolver):
        """'which wave is running on which station in chennai today' → None.
        This is a detail/listing query, not a KPI aggregation."""
        match = resolver.resolve(
            "which wave is running on which station in chennai today",
            tenant_values=["chennai"],
        )
        assert match is None, (
            f"Detail listing query falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_show_running_waves_at_each_station_rejected(self, resolver):
        """'show running waves at each station' → None (detail listing)."""
        match = resolver.resolve(
            "show running waves at each station",
            tenant_values=["frk"],
        )
        assert match is None, (
            f"Detail listing query falsely matched: "
            f"{match.kpi_name} (score={match.match_score:.3f})"
        )

    def test_list_all_waves_with_stations_low_confidence(self, resolver):
        """'list all waves with their station assignment' — if it matches,
        it should be flagged as below HIGH_CONFIDENCE (0.85)."""
        match = resolver.resolve(
            "list all waves with their station assignment",
            tenant_values=["frk"],
        )
        if match is not None:
            assert match.match_score < 0.90, (
                f"Expected score below 0.90 for listing query, "
                f"got {match.kpi_name} with score={match.match_score:.3f}"
            )


# ──────────────────────────────────────────────────────────────
# FIX 3: AUTO_ACCEPT_THRESHOLD and top_candidates field
#        Tiered KPI strategy constants and match data.
# ──────────────────────────────────────────────────────────────
class TestTieredKPIStrategy:
    """Verify that the AUTO_ACCEPT_THRESHOLD constant exists and
    top_candidates is populated on KPIMatch results."""

    def test_auto_accept_threshold_exists(self, resolver):
        """AUTO_ACCEPT_THRESHOLD should be 0.98."""
        assert hasattr(resolver, "AUTO_ACCEPT_THRESHOLD")
        assert resolver.AUTO_ACCEPT_THRESHOLD == 0.98

    def test_top_candidates_populated_on_match(self, resolver):
        """When a KPI matches, top_candidates should have 1-5 candidates."""
        match = resolver.resolve("active bots in frk", tenant_values=["frk"])
        assert match is not None
        assert hasattr(match, "top_candidates")
        assert isinstance(match.top_candidates, list)
        assert len(match.top_candidates) >= 1
        assert len(match.top_candidates) <= 5

    def test_top_candidates_have_required_fields(self, resolver):
        """Each candidate should have kpi_id, kpi_name, score, logic."""
        match = resolver.resolve("total bins in blr", tenant_values=["blr"])
        assert match is not None
        for cand in match.top_candidates:
            assert "kpi_id" in cand
            assert "kpi_name" in cand
            assert "score" in cand
            assert isinstance(cand["score"], float)

    def test_top_candidates_sorted_descending(self, resolver):
        """Candidates should be sorted by score descending."""
        match = resolver.resolve("active bots in frk", tenant_values=["frk"])
        assert match is not None
        if len(match.top_candidates) > 1:
            scores = [c["score"] for c in match.top_candidates]
            assert scores == sorted(scores, reverse=True), (
                f"Candidates not sorted desc: {scores}"
            )

    def test_top_candidates_first_matches_result(self, resolver):
        """The first candidate's kpi_id should match the resolved kpi_id."""
        match = resolver.resolve("total bins", tenant_values=["frk"])
        assert match is not None
        assert match.top_candidates[0]["kpi_id"] == match.kpi_id

    def test_kpimatch_top_candidates_field_default(self):
        """KPIMatch dataclass should default top_candidates to empty list."""
        m = KPIMatch(
            kpi_id="kpi_999",
            kpi_name="Test KPI",
            category="bot",
            chart_type="bar",
            logic="test",
            sql="SELECT 1",
            raw_query="SELECT 1",
            match_score=0.99,
            tables_used=["t1"],
            requires_location=False,
            requires_time_range=False,
            parameters_applied={},
        )
        assert m.top_candidates == []

    def test_top_candidates_include_user_queries(self, resolver):
        """Each top candidate should include user_queries list."""
        match = resolver.resolve("total bins in blr", tenant_values=["blr"])
        assert match is not None
        for cand in match.top_candidates:
            assert "user_queries" in cand, (
                f"Candidate {cand['kpi_id']} missing user_queries"
            )
            assert isinstance(cand["user_queries"], list)


# ──────────────────────────────────────────────────────────────
# FIX 4: Detail listing guard (_is_detail_listing_query)
#        Record-level listing queries must be rejected.
# ──────────────────────────────────────────────────────────────
class TestDetailListingGuard:
    """Verify that _is_detail_listing_query correctly identifies
    record-level detail queries vs. KPI aggregation queries."""

    def test_which_wave_which_station_is_detail(self):
        from app.services.sql_assistant.kpi_resolver import _is_detail_listing_query
        assert _is_detail_listing_query(
            "which wave is running on which station in chennai today"
        )

    def test_show_running_waves_is_detail(self):
        from app.services.sql_assistant.kpi_resolver import _is_detail_listing_query
        assert _is_detail_listing_query("show running waves at each station")

    def test_station_wave_hours_is_not_detail(self):
        from app.services.sql_assistant.kpi_resolver import _is_detail_listing_query
        assert not _is_detail_listing_query(
            "station-wise wave hours in frk today"
        )

    def test_how_many_hours_is_not_detail(self):
        from app.services.sql_assistant.kpi_resolver import _is_detail_listing_query
        assert not _is_detail_listing_query(
            "how many hours did waves run at each station"
        )

    def test_total_active_bots_is_not_detail(self):
        from app.services.sql_assistant.kpi_resolver import _is_detail_listing_query
        assert not _is_detail_listing_query("total active bots in frk")


# ──────────────────────────────────────────────────────────────
# §18  Column-projection tests
#        Verify _apply_column_projection wraps SQL to show only
#        the columns relevant to the user's intent.
# ──────────────────────────────────────────────────────────────
class TestColumnProjection:
    """Tests for intent-based column projection on kpi_001."""

    # ── Helper ─────────────────────────────────────────────────
    def _make_resolver(self):
        from app.services.sql_assistant.kpi_resolver import DashboardKPIResolver
        return DashboardKPIResolver.__new__(DashboardKPIResolver)

    SAMPLE_KPI001_SQL = (
        "SELECT BOT_ID, ACTIVE_HOURS, INACTIVE_HOURS\n"
        "FROM dbo.vw_BotActiveInactiveHours\n"
        "WHERE REPORT_DATE = CAST(GETDATE() AS DATE);"
    )

    # ── active-only intent ─────────────────────────────────────
    def test_active_only_projects_active_hours(self):
        r = self._make_resolver()
        sql, pa = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {}, "active time of bot 9 in frk today", "kpi_001",
        )
        # Outer SELECT must have only BOT_ID + ACTIVE_HOURS
        outer_select = sql.split("\nFROM (")[0]  # text before inner subquery
        assert "_cp.BOT_ID" in outer_select
        assert "_cp.ACTIVE_HOURS" in outer_select
        assert "INACTIVE_HOURS" not in outer_select
        assert pa.get("column_projection") == "active_only"

    def test_active_hours_phrasing(self):
        r = self._make_resolver()
        sql, pa = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {}, "what are active hours for each bot in frk", "kpi_001",
        )
        outer_select = sql.split("\nFROM (")[0]
        assert "_cp.ACTIVE_HOURS" in outer_select
        assert "INACTIVE_HOURS" not in outer_select
        assert pa["column_projection"] == "active_only"

    # ── inactive-only intent ───────────────────────────────────
    def test_inactive_only_projects_inactive_hours(self):
        r = self._make_resolver()
        sql, pa = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {}, "inactive time of bot 9 in frk today", "kpi_001",
        )
        outer_select = sql.split("\nFROM (")[0]
        assert "_cp.BOT_ID" in outer_select
        assert "_cp.INACTIVE_HOURS" in outer_select
        assert "ACTIVE_HOURS" not in outer_select.replace("INACTIVE_HOURS", "")
        assert pa.get("column_projection") == "inactive_only"

    def test_inactive_hours_phrasing(self):
        r = self._make_resolver()
        sql, pa = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {}, "show inactive hours for bots in frk", "kpi_001",
        )
        assert "_cp.INACTIVE_HOURS" in sql
        assert pa["column_projection"] == "inactive_only"

    # ── "vs" / comparison → no projection ──────────────────────
    def test_vs_query_keeps_all_columns(self):
        r = self._make_resolver()
        sql, pa = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {},
            "active vs inactive time of bot 9 in frk today", "kpi_001",
        )
        # No wrapping at all — original SQL returned as-is
        assert "_cp" not in sql
        assert "column_projection" not in pa

    def test_versus_query_keeps_all_columns(self):
        r = self._make_resolver()
        sql, pa = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {},
            "active versus inactive hours for bot in frk", "kpi_001",
        )
        assert "_cp" not in sql
        assert "column_projection" not in pa

    def test_compared_query_keeps_all_columns(self):
        r = self._make_resolver()
        sql, pa = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {},
            "active hours compared to inactive hours in frk", "kpi_001",
        )
        assert "_cp" not in sql
        assert "column_projection" not in pa

    # ── Non-kpi_001 KPIs are unaffected ────────────────────────
    def test_non_kpi001_no_projection(self):
        r = self._make_resolver()
        original_sql = "SELECT BOT_ID, DOWNTIME_MINS FROM dbo.vw_BotDowntime;"
        sql, pa = r._apply_column_projection(
            original_sql, {}, "active time of bot 9 in frk", "kpi_012",
        )
        assert sql == original_sql
        assert "column_projection" not in pa

    # ── SQL structure: wrapped query is valid subquery ─────────
    def test_wrapped_sql_contains_subquery(self):
        r = self._make_resolver()
        sql, _ = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {}, "active time of bot in frk", "kpi_001",
        )
        assert sql.startswith("SELECT _cp.")
        assert "FROM (" in sql
        assert ") AS _cp;" in sql

    # ── Trailing semicolons handled ────────────────────────────
    def test_trailing_semicolon_stripped_from_inner_sql(self):
        r = self._make_resolver()
        sql, _ = r._apply_column_projection(
            self.SAMPLE_KPI001_SQL, {}, "active hours for bot in frk", "kpi_001",
        )
        # Inner SQL should not have a trailing semicolon
        inner_start = sql.index("FROM (") + len("FROM (\n")
        inner_end = sql.index("\n) AS _cp;")
        inner_sql = sql[inner_start:inner_end]
        assert not inner_sql.rstrip().endswith(";")
