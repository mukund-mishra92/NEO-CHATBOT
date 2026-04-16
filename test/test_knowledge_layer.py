"""
Tests for KnowledgeLayer — Domain Knowledge Service
=====================================================
Tests the matching, formatting, and integration logic.
"""

import json
import os
import pytest
import tempfile
from pathlib import Path


# ──────────────────────────────────────────────
# Fixtures
# ──────────────────────────────────────────────

@pytest.fixture
def knowledge_dir(tmp_path):
    """Create a temporary knowledge directory with minimal test data."""
    
    # table_usage_patterns.json
    table_patterns = {
        "patterns": [
            {
                "id": "tup_001",
                "topic": "bot_task_lifecycle",
                "description": "Bot task lifecycle and active time calculations.",
                "trigger_keywords": ["bot task", "active hours", "task duration", "bot utilization"],
                "primary_tables": ["task_master_log"],
                "archive_tables": ["task_master_log_archive"],
                "join_tables": [],
                "join_conditions": [],
                "requires_archive_union": True,
                "requires_time_range": True,
                "timestamp_columns": ["TASK_START_TIMESTAMP", "TASK_COMPLETE_TIMESTAMP"],
                "notes": "Use archive UNION ALL for historical queries."
            },
            {
                "id": "tup_002",
                "topic": "station_ipp",
                "description": "Items Per Person calculation at pick stations.",
                "trigger_keywords": ["ipp", "items per person", "pick productivity", "station efficiency"],
                "primary_tables": ["pick_wave_order_master", "order_bin_mapping_log"],
                "archive_tables": ["pick_wave_order_master_archive", "order_bin_mapping_log_archive"],
                "join_tables": ["stock_audit_wave_order_master"],
                "join_conditions": ["pick_wave_order_master.ORDER_BIN_ID = order_bin_mapping_log.ORDER_BIN_ID"],
                "requires_archive_union": True,
                "requires_time_range": True,
                "timestamp_columns": ["PICK_START_TIMESTAMP", "PICK_TIMESTAMP"],
                "notes": "Cap each bin interval at 180 seconds. Subtract mid-wave audit time."
            },
            {
                "id": "tup_003",
                "topic": "inventory_count",
                "description": "Live inventory counts and bin occupancy.",
                "trigger_keywords": ["inventory count", "bin count", "sku count", "how many bins"],
                "primary_tables": ["live_inventory"],
                "archive_tables": [],
                "join_tables": ["sku_master"],
                "join_conditions": ["live_inventory.ARTICLE_ID = sku_master.ARTICLE_ID"],
                "requires_archive_union": False,
                "requires_time_range": False,
                "timestamp_columns": [],
                "notes": "Snapshot table. Filter VIRTUAL_BIN and no-sku."
            }
        ]
    }
    
    # business_filters.json
    business_filters = {
        "filters": [
            {
                "id": "bf_001",
                "table": "live_inventory",
                "filter": "Bin_Type <> 'VIRTUAL_BIN'",
                "reason": "Virtual bins are system placeholders, not real bins.",
                "applies_to": ["inventory", "bin count"],
                "severity": "critical"
            },
            {
                "id": "bf_002",
                "table": "task_master_log",
                "filter": "task_type <> 'Manual'",
                "reason": "Manual tasks are not bot-driven.",
                "applies_to": ["bot tasks", "active hours"],
                "severity": "critical"
            },
            {
                "id": "bf_003",
                "table": "pick_wave_order_master",
                "filter": "STATUS NOT IN ('PENDING', 'PICK_STARTED')",
                "reason": "Only completed picks have valid timestamps.",
                "applies_to": ["pick metrics", "ipp"],
                "severity": "critical"
            }
        ],
        "forbidden_table_combinations": [
            {
                "wrong_table": "article_master",
                "correct_table": "sku_master",
                "reason": "article_master does not exist in this schema."
            }
        ],
        "forbidden_columns": [
            {
                "table": "bin_info_master",
                "columns": ["AISLE_ID", "TOWER_ID"],
                "use_instead": "ZONE_ID, SECTION",
                "reason": "These columns do not exist."
            }
        ]
    }
    
    # sql_patterns.json
    sql_patterns = {
        "patterns": [
            {
                "id": "sp_001",
                "name": "archive_union_all",
                "description": "UNION ALL between current and archive tables.",
                "when_to_use": "Any query involving historical/time-range data.",
                "trigger_keywords": ["today", "yesterday", "last week", "date range", "historical"],
                "template": "SELECT ... FROM table UNION ALL SELECT ... FROM table_archive",
                "rules": ["Both SELECTs must have identical columns."],
                "common_archive_pairs": [
                    ["task_master_log", "task_master_log_archive"]
                ]
            },
            {
                "id": "sp_004",
                "name": "obml_sequenced",
                "description": "LEAD() window for ON_STATION→OPERATION_COMPLETED pairing.",
                "when_to_use": "Station productivity, bin presentation, IPP.",
                "trigger_keywords": ["station productive", "bin presentation", "ipp", "on station"],
                "template": "LEAD(STATUS) OVER (PARTITION BY STATION_ID, ORDER_BIN_ID ORDER BY UPDATED_TIMESTAMP)",
                "rules": ["Filter TYPE = 'RACK_PICK'", "Filter STATUS IN ('ON_STATION', 'OPERATION_COMPLETED')"]
            }
        ]
    }
    
    # domain_formulas.json
    domain_formulas = {
        "formulas": [
            {
                "id": "df_001",
                "name": "Net IPP (Pick)",
                "description": "Net picking productivity.",
                "formula": "Net_IPP = SUM(items_picked) / (SUM(actual_picking_seconds) / 3600)",
                "components": {
                    "items_picked": "COUNT from pick_wave_order_master",
                    "actual_picking_seconds": "LEAST(interval, 180)"
                },
                "tables": ["pick_wave_order_master", "order_bin_mapping_log"],
                "critical_rules": ["Cap each bin interval at 180 seconds"],
                "applies_to": ["net ipp", "pick efficiency", "pick productivity"]
            },
            {
                "id": "df_010",
                "name": "Volume Utilization",
                "description": "Percentage of bin volume used by items.",
                "formula": "Volume = (SUM(item_vol) / bin_vol) * 100",
                "components": {
                    "bin_volume": "81 x 57 x 42.5 x 0.95 cm^3"
                },
                "tables": ["live_inventory", "sku_master"],
                "critical_rules": ["Filter Bin_Type <> VIRTUAL_BIN"],
                "applies_to": ["volume utilization", "bin volume", "space usage"]
            }
        ]
    }
    
    # column_selection_rules.json
    column_rules = {
        "table_columns": [
            {
                "table": "task_master_log",
                "primary_key": "TASK_ID",
                "timestamp_columns": ["TASK_START_TIMESTAMP", "TASK_COMPLETE_TIMESTAMP"],
                "key_columns": ["BOT_ID", "TASK_TYPE", "SOURCE_LOCATION"],
                "host_location_column": "`host-location`",
                "common_filters": ["task_type <> 'Manual'"],
                "notes": "Has archive table."
            },
            {
                "table": "live_inventory",
                "primary_key": None,
                "timestamp_columns": ["LAST_UPDATED_TIMESTAMP"],
                "key_columns": ["BIN_ID", "ARTICLE_ID", "QTY", "Bin_Type"],
                "host_location_column": "`host-location`",
                "common_filters": ["Bin_Type <> 'VIRTUAL_BIN'", "ARTICLE_ID <> 'no-sku'"],
                "notes": "Snapshot table. No archive."
            }
        ],
        "global_rules": {
            "host_location": {
                "column_name": "`host-location`",
                "note": "Always wrap in backticks."
            }
        }
    }
    
    # Write all files
    for filename, data in [
        ("table_usage_patterns.json", table_patterns),
        ("business_filters.json", business_filters),
        ("sql_patterns.json", sql_patterns),
        ("domain_formulas.json", domain_formulas),
        ("column_selection_rules.json", column_rules),
    ]:
        with open(tmp_path / filename, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    
    return str(tmp_path)


@pytest.fixture
def knowledge_layer(knowledge_dir):
    """Create KnowledgeLayer instance from test data."""
    from app.services.sql_assistant.knowledge_layer import KnowledgeLayer
    return KnowledgeLayer(knowledge_dir=knowledge_dir)


# ──────────────────────────────────────────────
# Tests: Loading
# ──────────────────────────────────────────────

class TestKnowledgeLayerLoading:
    
    def test_loads_all_knowledge_files(self, knowledge_layer):
        assert len(knowledge_layer.table_usage_patterns) == 3
        assert len(knowledge_layer.business_filters.get("filters", [])) == 3
        assert len(knowledge_layer.sql_patterns) == 2
        assert len(knowledge_layer.domain_formulas) == 2
        assert len(knowledge_layer.column_rules) == 2

    def test_handles_missing_files_gracefully(self, tmp_path):
        """KnowledgeLayer should not crash if knowledge directory is empty."""
        from app.services.sql_assistant.knowledge_layer import KnowledgeLayer
        layer = KnowledgeLayer(knowledge_dir=str(tmp_path))
        assert len(layer.table_usage_patterns) == 0
        assert len(layer.sql_patterns) == 0
        assert len(layer.domain_formulas) == 0

    def test_column_rules_indexed_by_table(self, knowledge_layer):
        assert "task_master_log" in knowledge_layer.column_rules
        assert "live_inventory" in knowledge_layer.column_rules
        assert "nonexistent_table" not in knowledge_layer.column_rules


# ──────────────────────────────────────────────
# Tests: Matching
# ──────────────────────────────────────────────

class TestKnowledgeLayerMatching:

    def test_match_table_patterns_by_keyword(self, knowledge_layer):
        """Keyword triggers should match table usage patterns."""
        patterns = knowledge_layer._match_table_usage_patterns(
            "show me bot active hours today",
            ["task_master_log"]
        )
        assert len(patterns) >= 1
        topics = [p["topic"] for p in patterns]
        assert "bot_task_lifecycle" in topics

    def test_match_table_patterns_by_table_overlap(self, knowledge_layer):
        """Table overlap should boost pattern scores."""
        patterns = knowledge_layer._match_table_usage_patterns(
            "some generic question",
            ["pick_wave_order_master", "order_bin_mapping_log"]
        )
        assert len(patterns) >= 1
        topics = [p["topic"] for p in patterns]
        assert "station_ipp" in topics

    def test_match_business_filters(self, knowledge_layer):
        """Business filters should match by table name."""
        filters = knowledge_layer._match_business_filters(
            ["live_inventory", "sku_master"]
        )
        assert len(filters) >= 1
        tables = [f["table"] for f in filters]
        assert "live_inventory" in tables

    def test_no_business_filters_for_unrelated_tables(self, knowledge_layer):
        """Should return nothing for tables with no filters."""
        filters = knowledge_layer._match_business_filters(
            ["some_random_table"]
        )
        assert len(filters) == 0

    def test_match_sql_patterns_by_keyword(self, knowledge_layer):
        """SQL patterns should match by keyword triggers."""
        patterns = knowledge_layer._match_sql_patterns(
            "show me station ipp today",
            ["pick_wave_order_master"]
        )
        assert len(patterns) >= 1
        names = [p["name"] for p in patterns]
        assert "obml_sequenced" in names

    def test_match_archive_pattern_boosted(self, knowledge_layer):
        """Archive UNION ALL pattern should be boosted when archive tables present."""
        patterns = knowledge_layer._match_sql_patterns(
            "show data from yesterday",
            ["task_master_log", "task_master_log_archive"]
        )
        assert len(patterns) >= 1
        assert patterns[0]["name"] == "archive_union_all"

    def test_match_formulas(self, knowledge_layer):
        """Domain formulas should match by applies_to terms."""
        formulas = knowledge_layer._match_formulas(
            "what is the net ipp for station 5"
        )
        assert len(formulas) >= 1
        names = [f["name"] for f in formulas]
        assert "Net IPP (Pick)" in names

    def test_match_formulas_volume(self, knowledge_layer):
        """Volume utilization formula should match."""
        formulas = knowledge_layer._match_formulas(
            "show volume utilization"
        )
        assert len(formulas) >= 1
        names = [f["name"] for f in formulas]
        assert "Volume Utilization" in names

    def test_match_column_rules(self, knowledge_layer):
        """Column rules should match by table name."""
        rules = knowledge_layer._match_column_rules(
            ["task_master_log", "live_inventory"]
        )
        assert len(rules) == 2
        tables = [r["table"] for r in rules]
        assert "task_master_log" in tables
        assert "live_inventory" in tables


# ──────────────────────────────────────────────
# Tests: Formatting
# ──────────────────────────────────────────────

class TestKnowledgeLayerFormatting:

    def test_format_table_patterns_not_empty(self, knowledge_layer):
        patterns = knowledge_layer._match_table_usage_patterns(
            "bot active hours", ["task_master_log"]
        )
        text = knowledge_layer._format_table_patterns(patterns)
        assert "TABLE USAGE GUIDANCE" in text
        assert "task_master_log" in text

    def test_format_business_filters_includes_forbidden(self, knowledge_layer):
        filters = knowledge_layer._match_business_filters(["live_inventory"])
        text = knowledge_layer._format_business_filters(filters)
        assert "MANDATORY BUSINESS FILTERS" in text
        assert "VIRTUAL_BIN" in text
        assert "FORBIDDEN TABLE MISTAKES" in text
        assert "article_master" in text

    def test_format_sql_patterns_includes_template(self, knowledge_layer):
        patterns = knowledge_layer._match_sql_patterns(
            "show data from yesterday", ["task_master_log_archive"]
        )
        text = knowledge_layer._format_sql_patterns(patterns)
        assert "SQL PATTERNS" in text
        assert "UNION ALL" in text

    def test_format_formulas_includes_critical_rules(self, knowledge_layer):
        formulas = knowledge_layer._match_formulas("net ipp")
        text = knowledge_layer._format_formulas(formulas)
        assert "DOMAIN FORMULAS" in text
        assert "180 seconds" in text

    def test_format_column_guidance(self, knowledge_layer):
        rules = knowledge_layer._match_column_rules(["task_master_log"])
        text = knowledge_layer._format_column_guidance(rules)
        assert "COLUMN GUIDANCE" in text
        assert "TASK_START_TIMESTAMP" in text

    def test_format_empty_returns_empty(self, knowledge_layer):
        assert knowledge_layer._format_table_patterns([]) == ""
        assert knowledge_layer._format_business_filters([]) == ""
        assert knowledge_layer._format_sql_patterns([]) == ""
        assert knowledge_layer._format_formulas([]) == ""
        assert knowledge_layer._format_column_guidance([]) == ""


# ──────────────────────────────────────────────
# Tests: Main API
# ──────────────────────────────────────────────

class TestKnowledgeLayerAPI:

    def test_get_knowledge_for_prompt_returns_content(self, knowledge_layer):
        """Should return non-empty domain knowledge for relevant queries."""
        result = knowledge_layer.get_knowledge_for_prompt(
            "show me net ipp for station 5 today",
            ["pick_wave_order_master", "order_bin_mapping_log"]
        )
        assert len(result) > 0
        assert "DOMAIN KNOWLEDGE" in result
        assert "production queries" in result

    def test_get_knowledge_for_prompt_empty_for_unrelated(self, knowledge_layer):
        """Should return empty for completely unrelated queries."""
        result = knowledge_layer.get_knowledge_for_prompt(
            "tell me a joke",
            ["unrelated_table"]
        )
        assert result == ""

    def test_get_additional_tables_suggests_archive(self, knowledge_layer):
        """Should suggest archive tables when query needs historical data."""
        additional = knowledge_layer.get_additional_tables(
            "show bot active hours yesterday",
            ["task_master_log"]
        )
        assert "task_master_log_archive" in additional

    def test_get_additional_tables_suggests_join_tables(self, knowledge_layer):
        """Should suggest join tables when missing from selection."""
        additional = knowledge_layer.get_additional_tables(
            "show ipp for station",
            ["pick_wave_order_master"]
        )
        # Should suggest order_bin_mapping_log and stock_audit_wave_order_master
        assert "order_bin_mapping_log" in additional or "stock_audit_wave_order_master" in additional

    def test_get_additional_tables_empty_when_complete(self, knowledge_layer):
        """Should return nothing if all tables already selected."""
        additional = knowledge_layer.get_additional_tables(
            "inventory count",
            ["live_inventory", "sku_master"]
        )
        # All primary + join tables already in selection
        assert len(additional) == 0


# ──────────────────────────────────────────────
# Tests: build_universal_prompt integration
# ──────────────────────────────────────────────

class TestPromptIntegration:

    def test_domain_knowledge_param_included(self):
        """build_universal_prompt should include domain_knowledge when provided."""
        from app.prompts.universal_sql_prompt import build_universal_prompt
        
        result = build_universal_prompt(
            schema_context="TABLE: test_table\nCOLUMNS: id, name",
            domain_knowledge="## TEST DOMAIN KNOWLEDGE\nSome guidance here."
        )
        assert "TEST DOMAIN KNOWLEDGE" in result
        assert "Some guidance here" in result

    def test_domain_knowledge_param_empty(self):
        """build_universal_prompt should work fine with empty domain_knowledge."""
        from app.prompts.universal_sql_prompt import build_universal_prompt
        
        result = build_universal_prompt(
            schema_context="TABLE: test_table\nCOLUMNS: id, name",
            domain_knowledge=""
        )
        assert "SCHEMA CONTEXT" in result
        # No domain knowledge section should appear
        assert "DOMAIN KNOWLEDGE" not in result

    def test_domain_knowledge_placed_before_entity_context(self):
        """Domain knowledge should appear before the dynamic entity context in the prompt."""
        from app.prompts.universal_sql_prompt import build_universal_prompt
        
        unique_dk_marker = "UNIQUE_DK_MARKER_12345"
        unique_ec_marker = "UNIQUE_EC_MARKER_67890"
        
        result = build_universal_prompt(
            schema_context="TABLE: test",
            entity_context=unique_ec_marker,
            domain_knowledge=unique_dk_marker,
        )
        dk_pos = result.index(unique_dk_marker)
        ec_pos = result.index(unique_ec_marker)
        assert dk_pos < ec_pos, "Domain knowledge should appear before entity context values"
