"""
Tests for the Agentic SQL Generation Pipeline.
Tests the 4 agents individually + orchestrator integration.
"""

import json
import pytest
from unittest.mock import MagicMock, patch, PropertyMock

# ── Import agents ─────────────────────────────────────────
from backend.app.services.sql_assistant.agents.state import SQLAgentState
from backend.app.services.sql_assistant.agents.query_analyzer import (
    build_query_analyzer_messages,
    parse_analyzer_response,
)
from backend.app.services.sql_assistant.agents.schema_filter_agent import (
    build_schema_filter_messages,
    parse_schema_filter_response,
)
from backend.app.services.sql_assistant.agents.sql_writer import (
    build_sql_writer_messages,
    parse_sql_writer_response,
)
from backend.app.services.sql_assistant.agents.sql_reviewer import (
    build_sql_reviewer_messages,
    parse_reviewer_response,
)
from backend.app.services.sql_assistant.agents.orchestrator import (
    AgenticSQLOrchestrator,
)


# ── Fixtures ──────────────────────────────────────────────

@pytest.fixture
def sample_state():
    """Minimal valid SQLAgentState for testing."""
    return {
        "question": "total bots at shakti",
        "clean_question": "total bots at shakti",
        "selected_tables": ["bot_master"],
        "filtered_schema": {
            "bot_master": {
                "columns": ["BOT_ID", "STATUS", "IS_ACTIVE", "IS_BYPASSED", "host-location"],
                "description": "Master table for all bots in the warehouse",
                "key_business_attributes": ["BOT_ID", "STATUS"],
                "frequently_joined_with": ["task_mission_log"],
                "supports_analytics": ["bot counts", "fleet health"],
            }
        },
        "entity_context": "`host-location` = 'SHAKTI'",
        "domain_knowledge": "## DOMAIN FORMULAS\nTotal Bot Count: COUNT(*) FROM bot_master with NO status filters",
        "conversation_history": [],
        "multi_tenant_config": {"enabled": True, "tenant_column": "host-location"},
        # Agent outputs
        "query_intent": "",
        "query_type": "",
        "identified_metrics": [],
        "time_range": "",
        "complexity": "",
        "analysis_notes": "",
        "tables_to_use": [],
        "join_plan": [],
        "mandatory_filters": [],
        "optional_filters": [],
        "formula_to_apply": "",
        "sql_pattern": "",
        "schema_plan_notes": "",
        "generated_sql": "",
        "sql_confidence": 0.0,
        "sql_assumptions": [],
        "sql_warnings": [],
        "review_passed": False,
        "review_issues": [],
        "review_suggestions": "",
        "corrected_sql": "",
        "iteration_count": 0,
        "max_iterations": 2,
        "final_sql": "",
        "final_confidence": 0.0,
        "error": "",
    }


# ══════════════════════════════════════════════════════════
# AGENT 1: Query Analyzer
# ══════════════════════════════════════════════════════════

class TestQueryAnalyzer:
    """Tests for the Query Analyzer agent."""

    def test_build_messages_has_system_and_user(self, sample_state):
        msgs = build_query_analyzer_messages(sample_state)
        assert len(msgs) == 2
        assert msgs[0]["role"] == "system"
        assert msgs[1]["role"] == "user"
        assert "total bots at shakti" in msgs[1]["content"]

    def test_build_messages_includes_domain_knowledge(self, sample_state):
        msgs = build_query_analyzer_messages(sample_state)
        assert "DOMAIN FORMULAS" in msgs[1]["content"]

    def test_build_messages_includes_entity_context(self, sample_state):
        msgs = build_query_analyzer_messages(sample_state)
        assert "SHAKTI" in msgs[1]["content"]

    def test_parse_valid_json(self):
        response = json.dumps({
            "query_intent": "Count all bots at SHAKTI warehouse",
            "query_type": "aggregation",
            "identified_metrics": ["total bot count"],
            "time_range": "none",
            "complexity": "simple",
            "analysis_notes": "User wants total count, no status filter",
        })
        result = parse_analyzer_response(response)
        assert result["query_type"] == "aggregation"
        assert result["complexity"] == "simple"
        assert "total bot count" in result["identified_metrics"]

    def test_parse_json_in_code_block(self):
        response = '```json\n{"query_intent": "test", "query_type": "listing"}\n```'
        result = parse_analyzer_response(response)
        assert result["query_intent"] == "test"
        assert result["query_type"] == "listing"

    def test_parse_invalid_json_returns_defaults(self):
        result = parse_analyzer_response("This is not JSON at all")
        assert result["query_type"] == "aggregation"
        assert result["complexity"] == "moderate"
        assert "Parse failed" in result["analysis_notes"]


# ══════════════════════════════════════════════════════════
# AGENT 2: Schema & Filter
# ══════════════════════════════════════════════════════════

class TestSchemaFilterAgent:
    """Tests for the Schema & Filter agent."""

    def test_build_messages_includes_schema(self, sample_state):
        # Set analysis outputs
        sample_state["query_intent"] = "Total bot count"
        sample_state["query_type"] = "aggregation"
        msgs = build_schema_filter_messages(sample_state)
        assert len(msgs) == 2
        assert "bot_master" in msgs[0]["content"]
        assert "BOT_ID" in msgs[0]["content"]

    def test_build_messages_includes_analysis(self, sample_state):
        sample_state["query_intent"] = "Total bot count"
        msgs = build_schema_filter_messages(sample_state)
        assert "Total bot count" in msgs[0]["content"]

    def test_parse_valid_plan(self):
        response = json.dumps({
            "tables_to_use": ["bot_master"],
            "join_plan": [],
            "mandatory_filters": ["`host-location` = 'SHAKTI'"],
            "optional_filters": [],
            "formula_to_apply": "COUNT(*)",
            "sql_pattern": "simple_select",
            "select_columns": ["COUNT(*) AS total_bots"],
            "group_by": [],
            "order_by": "",
            "limit": "none",
            "schema_plan_notes": "Simple count, no joins needed",
        })
        result = parse_schema_filter_response(response)
        assert result["tables_to_use"] == ["bot_master"]
        assert result["formula_to_apply"] == "COUNT(*)"
        assert len(result["mandatory_filters"]) == 1

    def test_parse_invalid_returns_defaults(self):
        result = parse_schema_filter_response("garbled output")
        assert result["tables_to_use"] == []
        assert result["sql_pattern"] == "simple_select"


# ══════════════════════════════════════════════════════════
# AGENT 3: SQL Writer
# ══════════════════════════════════════════════════════════

class TestSQLWriter:
    """Tests for the SQL Writer agent."""

    def test_build_messages_includes_plan(self, sample_state):
        sample_state["tables_to_use"] = ["bot_master"]
        sample_state["formula_to_apply"] = "COUNT(*)"
        msgs = build_sql_writer_messages(sample_state)
        assert "bot_master" in msgs[0]["content"]
        assert "COUNT(*)" in msgs[0]["content"]

    def test_build_messages_retry_includes_feedback(self, sample_state):
        sample_state["iteration_count"] = 1
        sample_state["review_issues"] = ["Missing host-location filter"]
        sample_state["generated_sql"] = "SELECT COUNT(*) FROM bot_master"
        msgs = build_sql_writer_messages(sample_state)
        assert "PREVIOUS ATTEMPT FAILED" in msgs[1]["content"]
        assert "Missing host-location" in msgs[1]["content"]

    def test_parse_valid_sql_response(self):
        response = json.dumps({
            "sql": "SELECT COUNT(*) AS total_bots FROM bot_master WHERE `host-location` = 'SHAKTI'",
            "tables_used": ["bot_master"],
            "columns_used": ["bot_master.BOT_ID"],
            "primary_keys_used": [],
            "assumptions": ["No status filter for total count"],
            "warnings": [],
            "needs_followup": False,
            "followup_questions": [],
            "is_read_only": True,
            "confidence": 0.95,
        })
        result = parse_sql_writer_response(response)
        assert "SELECT COUNT(*)" in result["generated_sql"]
        assert result["sql_confidence"] == 0.95

    def test_parse_extracts_raw_sql_on_json_failure(self):
        response = "Here is the SQL:\nSELECT COUNT(*) FROM bot_master\nDone!"
        result = parse_sql_writer_response(response)
        assert "SELECT COUNT(*)" in result["generated_sql"]
        assert result["sql_confidence"] == 0.5

    def test_parse_empty_sql_returns_error(self):
        response = json.dumps({"sql": "", "confidence": 0.0})
        result = parse_sql_writer_response(response)
        assert "error" in result


# ══════════════════════════════════════════════════════════
# AGENT 4: SQL Reviewer
# ══════════════════════════════════════════════════════════

class TestSQLReviewer:
    """Tests for the SQL Reviewer agent."""

    def test_build_messages_includes_sql_and_plan(self, sample_state):
        sample_state["generated_sql"] = "SELECT COUNT(*) FROM bot_master"
        sample_state["tables_to_use"] = ["bot_master"]
        msgs = build_sql_reviewer_messages(sample_state)
        assert "SELECT COUNT(*)" in msgs[0]["content"]
        assert "bot_master" in msgs[0]["content"]

    def test_parse_review_passed(self):
        response = json.dumps({
            "review_passed": True,
            "issues": [],
            "suggestions": "",
            "corrected_sql": "",
            "confidence_adjustment": 0.05,
        })
        result = parse_reviewer_response(response)
        assert result["review_passed"] is True
        assert result["review_issues"] == []

    def test_parse_review_failed_with_issues(self):
        response = json.dumps({
            "review_passed": False,
            "issues": ["Missing host-location in JOIN", "Added unnecessary IS_ACTIVE filter"],
            "suggestions": "Remove IS_ACTIVE=1 filter; add host-location to ON clause",
            "corrected_sql": "SELECT COUNT(*) FROM bot_master bm WHERE bm.`host-location` = 'SHAKTI'",
            "confidence_adjustment": -0.1,
        })
        result = parse_reviewer_response(response)
        assert result["review_passed"] is False
        assert len(result["review_issues"]) == 2
        assert "SELECT COUNT(*)" in result["corrected_sql"]

    def test_parse_invalid_defaults_to_passed(self):
        result = parse_reviewer_response("totally broken output")
        assert result["review_passed"] is True  # Conservative: assume pass if can't parse


# ══════════════════════════════════════════════════════════
# ORCHESTRATOR
# ══════════════════════════════════════════════════════════

class TestAgenticSQLOrchestrator:
    """Tests for the AgenticSQLOrchestrator."""

    def test_resolve_from_config_returns_defaults(self):
        """Config resolution should return provider and model."""
        provider, model = AgenticSQLOrchestrator._resolve_from_config()
        assert provider in ("openai", "groq")
        assert isinstance(model, str)

    @patch.dict("os.environ", {"OPENAI_API_KEY": ""}, clear=False)
    def test_init_without_api_key_gracefully_fails(self):
        """Should not crash when API key is missing."""
        orch = AgenticSQLOrchestrator(provider="openai", model="gpt-5.2")
        assert orch.llm is None

    def test_is_available_false_without_llm(self):
        orch = AgenticSQLOrchestrator.__new__(AgenticSQLOrchestrator)
        orch.llm = None
        orch._graph = None
        orch._graph_built = False
        orch.max_iterations = 2
        assert orch.is_available() is False

    @patch("backend.app.services.sql_assistant.agents.orchestrator.LANGGRAPH_AVAILABLE", True)
    def test_graph_builds_when_llm_available(self):
        """Graph compilation should succeed with a mock LLM."""
        orch = AgenticSQLOrchestrator.__new__(AgenticSQLOrchestrator)
        orch.llm = MagicMock()
        orch._graph = None
        orch._graph_built = False
        orch.max_iterations = 2
        orch.temperature = 0.0
        graph = orch.graph
        assert graph is not None

    @patch("backend.app.services.sql_assistant.agents.orchestrator.LANGGRAPH_AVAILABLE", True)
    def test_full_pipeline_mock(self, sample_state):
        """Full pipeline with mocked LLM responses."""
        orch = AgenticSQLOrchestrator.__new__(AgenticSQLOrchestrator)
        orch.max_iterations = 2
        orch.temperature = 0.0
        orch._graph = None
        orch._graph_built = False

        # Mock LLM with sequential responses
        mock_llm = MagicMock()
        call_count = [0]
        responses = [
            # Agent 1: Analyzer
            json.dumps({
                "query_intent": "Total bot count at SHAKTI",
                "query_type": "aggregation",
                "identified_metrics": ["total bot count"],
                "time_range": "none",
                "complexity": "simple",
                "analysis_notes": "No status filter needed",
            }),
            # Agent 2: Schema & Filter
            json.dumps({
                "tables_to_use": ["bot_master"],
                "join_plan": [],
                "mandatory_filters": ["`host-location` = 'SHAKTI'"],
                "optional_filters": [],
                "formula_to_apply": "COUNT(*)",
                "sql_pattern": "simple_select",
                "schema_plan_notes": "Simple aggregation",
            }),
            # Agent 3: SQL Writer
            json.dumps({
                "sql": "SELECT COUNT(*) AS total_bots FROM bot_master bm WHERE bm.`host-location` = 'SHAKTI'",
                "tables_used": ["bot_master"],
                "columns_used": ["bot_master.BOT_ID"],
                "primary_keys_used": [],
                "assumptions": ["No status filter for total"],
                "warnings": [],
                "needs_followup": False,
                "followup_questions": [],
                "is_read_only": True,
                "confidence": 0.95,
            }),
            # Agent 4: Reviewer
            json.dumps({
                "review_passed": True,
                "issues": [],
                "suggestions": "",
                "corrected_sql": "",
                "confidence_adjustment": 0.0,
            }),
        ]

        def mock_invoke(messages):
            resp = MagicMock()
            resp.content = responses[call_count[0] % len(responses)]
            call_count[0] += 1
            return resp

        mock_llm.invoke = mock_invoke
        orch.llm = mock_llm

        result = orch.run(
            question="total bots at shakti",
            clean_question="total bots at shakti",
            selected_tables=["bot_master"],
            filtered_schema=sample_state["filtered_schema"],
            entity_context="`host-location` = 'SHAKTI'",
            domain_knowledge="Total Bot Count: COUNT(*) with NO status filters",
        )

        assert result["sql"] != ""
        assert "SELECT" in result["sql"]
        assert "COUNT(*)" in result["sql"]
        assert result["source"] == "agentic_sql_pipeline"
        assert result.get("review_passed") is True

    @patch("backend.app.services.sql_assistant.agents.orchestrator.LANGGRAPH_AVAILABLE", True)
    def test_retry_on_review_failure(self, sample_state):
        """Pipeline should retry when reviewer rejects the SQL."""
        orch = AgenticSQLOrchestrator.__new__(AgenticSQLOrchestrator)
        orch.max_iterations = 2
        orch.temperature = 0.0
        orch._graph = None
        orch._graph_built = False

        mock_llm = MagicMock()
        call_count = [0]
        responses = [
            # Agent 1: Analyzer
            json.dumps({
                "query_intent": "Total bot count",
                "query_type": "aggregation",
                "identified_metrics": ["total bot count"],
                "time_range": "none",
                "complexity": "simple",
                "analysis_notes": "",
            }),
            # Agent 2: Schema & Filter
            json.dumps({
                "tables_to_use": ["bot_master"],
                "join_plan": [],
                "mandatory_filters": [],
                "optional_filters": [],
                "formula_to_apply": "COUNT(*)",
                "sql_pattern": "simple_select",
                "schema_plan_notes": "",
            }),
            # Agent 3 (attempt 1): SQL Writer — BAD SQL
            json.dumps({
                "sql": "SELECT COUNT(*) FROM bot_master WHERE IS_ACTIVE = 1",
                "tables_used": ["bot_master"],
                "columns_used": [],
                "primary_keys_used": [],
                "assumptions": [],
                "warnings": [],
                "needs_followup": False,
                "followup_questions": [],
                "is_read_only": True,
                "confidence": 0.7,
            }),
            # Agent 4 (attempt 1): Reviewer — REJECTS
            json.dumps({
                "review_passed": False,
                "issues": ["Added IS_ACTIVE=1 but user asked for total bots"],
                "suggestions": "Remove the IS_ACTIVE filter",
                "corrected_sql": "",
                "confidence_adjustment": -0.2,
            }),
            # Agent 3 (attempt 2): SQL Writer — FIXED SQL
            json.dumps({
                "sql": "SELECT COUNT(*) AS total_bots FROM bot_master bm WHERE bm.`host-location` = 'SHAKTI'",
                "tables_used": ["bot_master"],
                "columns_used": [],
                "primary_keys_used": [],
                "assumptions": [],
                "warnings": [],
                "needs_followup": False,
                "followup_questions": [],
                "is_read_only": True,
                "confidence": 0.92,
            }),
            # Agent 4 (attempt 2): Reviewer — PASSES
            json.dumps({
                "review_passed": True,
                "issues": [],
                "suggestions": "",
                "corrected_sql": "",
                "confidence_adjustment": 0.0,
            }),
        ]

        def mock_invoke(messages):
            resp = MagicMock()
            resp.content = responses[call_count[0] % len(responses)]
            call_count[0] += 1
            return resp

        mock_llm.invoke = mock_invoke
        orch.llm = mock_llm

        result = orch.run(
            question="total bots at shakti",
            clean_question="total bots at shakti",
            selected_tables=["bot_master"],
            filtered_schema=sample_state["filtered_schema"],
            entity_context="`host-location` = 'SHAKTI'",
            domain_knowledge="Total Bot Count: COUNT(*) with NO status filters",
        )

        assert result["sql"] != ""
        assert result["iterations"] == 2  # Went through 2 review cycles
        assert result.get("review_passed") is True


# ══════════════════════════════════════════════════════════
# MESSAGE BUILDING EDGE CASES
# ══════════════════════════════════════════════════════════

class TestEdgeCases:
    """Edge cases in message building and parsing."""

    def test_empty_domain_knowledge(self, sample_state):
        sample_state["domain_knowledge"] = ""
        msgs = build_query_analyzer_messages(sample_state)
        assert len(msgs) == 2  # Still produces valid messages

    def test_empty_schema(self, sample_state):
        sample_state["filtered_schema"] = {}
        sample_state["query_intent"] = "test"
        msgs = build_schema_filter_messages(sample_state)
        assert "No schema available" in msgs[0]["content"]

    def test_sql_writer_no_plan(self, sample_state):
        msgs = build_sql_writer_messages(sample_state)
        assert len(msgs) == 2  # Still builds messages

    def test_reviewer_no_sql(self, sample_state):
        sample_state["generated_sql"] = ""
        msgs = build_sql_reviewer_messages(sample_state)
        assert len(msgs) == 2

    def test_parse_json_with_extra_text(self):
        """Parser should handle JSON surrounded by commentary."""
        response = "Sure! Here's the analysis:\n```json\n{\"query_intent\":\"test\",\"query_type\":\"listing\"}\n```\nLet me know!"
        result = parse_analyzer_response(response)
        assert result["query_intent"] == "test"
