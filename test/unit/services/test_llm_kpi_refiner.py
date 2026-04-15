"""
Tests for the LLM-based KPI query refinement feature.

These tests mock the OpenAI client to verify prompt construction,
response parsing, and KPI selection/modification logic without
making actual API calls.
"""
import sys
import json
from pathlib import Path
from unittest.mock import MagicMock, patch
from dataclasses import dataclass, field
from typing import List, Dict, Any

sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

import pytest


# ─────────────────────────────────────────────────────────────
# Lightweight stubs so we don't need the full SQLAssistantService
# ─────────────────────────────────────────────────────────────

@dataclass
class KPIMatch:
    kpi_id: str
    kpi_name: str
    category: str
    chart_type: str
    logic: str
    sql: str
    raw_query: str
    match_score: float
    tables_used: List[str]
    requires_location: bool
    requires_time_range: bool
    parameters_applied: Dict[str, str] = field(default_factory=dict)
    top_candidates: List[Dict[str, Any]] = field(default_factory=list)


@dataclass
class FakeKPIEntry:
    id: str
    kpi_name: str
    category: str
    chart_type: str
    logic: str
    query: str
    requires_location: bool
    requires_time_range: bool
    tables_used: List[str]
    user_queries: List[str] = field(default_factory=list)


def _make_kpi_entries():
    """Return minimal KPI entries for kpi_001 and kpi_003."""
    return [
        FakeKPIEntry(
            id="kpi_001",
            kpi_name="Active vs Inactive hours for bot",
            category="bot",
            chart_type="bar chart",
            logic="Returns Active vs Inactive hours per bot.",
            query="SELECT BOT_ID, ACTIVE_HOURS, INACTIVE_HOURS FROM vw_hours WHERE loc='$location';",
            requires_location=True,
            requires_time_range=True,
            tables_used=["bot_master", "task_master_log"],
            user_queries=["What are the active vs inactive hours for bots in frk?", "Show bot active hours"],
        ),
        FakeKPIEntry(
            id="kpi_003",
            kpi_name="Number of Inactive Bots",
            category="bot",
            chart_type="stat",
            logic="Returns count of inactive bots.",
            query="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master WHERE loc='$location';",
            requires_location=True,
            requires_time_range=True,
            tables_used=["bot_master", "task_master_log"],
            user_queries=["How many bots are inactive?", "Number of inactive bots in chennai"],
        ),
        FakeKPIEntry(
            id="kpi_002",
            kpi_name="Active number of Bots",
            category="bot",
            chart_type="stat",
            logic="Returns count of active bots.",
            query="SELECT COUNT(DISTINCT BOT_ID) AS ACTIVE_BOTS FROM task_master_log;",
            requires_location=True,
            requires_time_range=True,
            tables_used=["task_master_log"],
            user_queries=["How many bots are active?", "Active bot count in frk"],
        ),
    ]


def _make_top_candidates():
    """Top candidates as kpi_resolver populates them."""
    return [
        {
            "kpi_id": "kpi_003",
            "kpi_name": "Number of Inactive Bots",
            "score": 0.72,
            "logic": "Returns count of inactive bots.",
            "tables_used": ["bot_master", "task_master_log"],
            "chart_type": "stat",
            "user_queries": ["How many bots are inactive?", "Number of inactive bots in chennai"],
        },
        {
            "kpi_id": "kpi_001",
            "kpi_name": "Active vs Inactive hours for bot",
            "score": 0.68,
            "logic": "Returns Active vs Inactive hours per bot.",
            "tables_used": ["bot_master", "task_master_log"],
            "chart_type": "bar chart",
            "user_queries": ["What are the active vs inactive hours for bots in frk?", "Show bot active hours"],
        },
        {
            "kpi_id": "kpi_002",
            "kpi_name": "Active number of Bots",
            "score": 0.61,
            "logic": "Returns count of active bots.",
            "tables_used": ["task_master_log"],
            "chart_type": "stat",
            "user_queries": ["How many bots are active?", "Active bot count in frk"],
        },
    ]


def _build_service_stub(llm_response_json: dict):
    """
    Create a stub that has everything _llm_refine_kpi_query needs:
    - sql_engine.openai_client  (mocked)
    - sql_engine.model          (str)
    - kpi_resolver.kpis         (list of FakeKPIEntry)
    - kpi_resolver._substitute_params  (identity)
    - kpi_resolver._inject_entity_filters (identity)
    - schema                    (dict of table→columns)
    """
    # Import the actual method from sql_assistant
    from app.services.sql_assistant.sql_assistant import SQLAssistantService

    svc = MagicMock(spec=SQLAssistantService)

    # Bind real methods to the mock
    svc._llm_refine_kpi_query = SQLAssistantService._llm_refine_kpi_query.__get__(svc)
    svc._build_kpi_refiner_table_context = SQLAssistantService._build_kpi_refiner_table_context.__get__(svc)
    svc._extract_output_columns = SQLAssistantService._extract_output_columns
    svc._fix_wrapper_column_quoting = SQLAssistantService._fix_wrapper_column_quoting
    svc._KPI_REFINE_SCHEMA = SQLAssistantService._KPI_REFINE_SCHEMA

    # Mock OpenAI client
    mock_resp = MagicMock()
    mock_resp.output_text = json.dumps(llm_response_json)
    svc.sql_engine = MagicMock()
    svc.sql_engine.openai_client = MagicMock()
    svc.sql_engine.openai_client.responses.create.return_value = mock_resp
    svc.sql_engine.model = "gpt-5.2"

    # Mock KPI resolver
    svc.kpi_resolver = MagicMock()
    svc.kpi_resolver.kpis = _make_kpi_entries()
    # _substitute_params returns (sql_as_is, empty_params)
    svc.kpi_resolver._substitute_params.side_effect = (
        lambda query, *a, **kw: (query, {})
    )
    # _inject_entity_filters returns (sql_as_is, params_as_is)
    svc.kpi_resolver._inject_entity_filters.side_effect = (
        lambda sql, params, **kw: (sql, params)
    )

    # Schema: table → list of column name strings
    svc.schema = {
        "bot_master": ["BOT_ID", "host-location", "BOT_TYPE"],
        "task_master_log": ["BOT_ID", "TASK_ID", "STATUS", "LOGGED_TIMESTAMP", "host-location"],
    }

    # Typed schema (from Table_information.csv) — needed by _build_kpi_refiner_table_context
    svc._schema_typed = {
        "bot_master": {
            "columns_typed": "BOT_ID(varchar(10)), host-location(varchar(60)), BOT_TYPE(varchar(20))",
            "primary_key": "BOT_ID, host-location",
            "description": "Master table for bots",
        },
        "task_master_log": {
            "columns_typed": "BOT_ID(varchar(10)), TASK_ID(bigint), STATUS(varchar(50)), LOGGED_TIMESTAMP(datetime), host-location(varchar(60))",
            "primary_key": "TASK_ID, host-location",
            "description": "Log table for bot tasks",
        },
    }

    # Business context (from table_descriptions.json) — needed by _build_kpi_refiner_table_context
    svc.business_context = {}

    return svc


# ─────────────────────────────────────────────────────────────
# ─  Tests
# ─────────────────────────────────────────────────────────────

class TestLLMKPIRefinerBasics:
    """Core unit tests for _llm_refine_kpi_query."""

    def _kpi_match(self, kpi_id="kpi_003", score=0.72):
        return KPIMatch(
            kpi_id=kpi_id,
            kpi_name="Number of Inactive Bots",
            category="bot",
            chart_type="stat",
            logic="Returns count of inactive bots.",
            sql="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master;",
            raw_query="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master;",
            match_score=score,
            tables_used=["bot_master", "task_master_log"],
            requires_location=True,
            requires_time_range=True,
            parameters_applied={},
            top_candidates=_make_top_candidates(),
        )

    def test_llm_selects_different_kpi(self):
        """LLM switches from kpi_003 to kpi_001 for 'inactive time' query."""
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": (
                "SELECT _cp.BOT_ID, _cp.INACTIVE_HOURS FROM (\n"
                "SELECT BOT_ID, ACTIVE_HOURS, INACTIVE_HOURS "
                "FROM vw_hours WHERE loc='$location';\n"
                ") AS _cp;"
            ),
            "chart_type": "bar chart",
            "explanation": "User asks for inactive TIME, not inactive COUNT.",
        }
        svc = _build_service_stub(llm_resp)
        result = svc._llm_refine_kpi_query(
            user_query="what is the inactive time of bot 9 in frk today",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from="2026-04-09 00:00:00",
            time_to="2026-04-09 23:59:59",
            all_sites=False,
        )
        assert result is not None
        assert result["kpi_id"] == "kpi_001"
        assert "INACTIVE_HOURS" in result["sql"]
        assert result["chart_type"] == "bar chart"

    def test_llm_confirms_original_kpi(self):
        """LLM confirms the original KPI when it fits."""
        llm_resp = {
            "selected_kpi_id": "kpi_003",
            "sql": "SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master WHERE loc='frk';",
            "chart_type": "stat",
            "explanation": "User asks for count of inactive bots.",
        }
        svc = _build_service_stub(llm_resp)
        result = svc._llm_refine_kpi_query(
            user_query="how many inactive bots in frk today",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from="2026-04-09 00:00:00",
            time_to="2026-04-09 23:59:59",
            all_sites=False,
        )
        assert result is not None
        assert result["kpi_id"] == "kpi_003"

    def test_llm_rejects_all_returns_none(self):
        """LLM says NONE → returns None (fall through to SQL gen)."""
        llm_resp = {
            "selected_kpi_id": "NONE",
            "sql": "",
            "chart_type": "",
            "explanation": "No KPI matches this query.",
        }
        svc = _build_service_stub(llm_resp)
        result = svc._llm_refine_kpi_query(
            user_query="what is the weather in frk",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        assert result is None

    def test_llm_returns_invalid_kpi_id(self):
        """LLM returns a kpi_id not in candidates → returns None."""
        llm_resp = {
            "selected_kpi_id": "kpi_999",
            "sql": "SELECT 1;",
            "chart_type": "stat",
            "explanation": "Invalid.",
        }
        svc = _build_service_stub(llm_resp)
        result = svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        assert result is None

    def test_no_openai_client_returns_none(self):
        """If no OpenAI client available, gracefully returns None."""
        svc = _build_service_stub({})
        svc.sql_engine.openai_client = None
        result = svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        assert result is None

    def test_empty_top_candidates_returns_none(self):
        """If no top candidates, returns None."""
        match = self._kpi_match()
        match.top_candidates = []
        svc = _build_service_stub({})
        result = svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=match,
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        assert result is None

    def test_api_error_returns_none(self):
        """If the OpenAI call throws, gracefully returns None."""
        svc = _build_service_stub({})
        svc.sql_engine.openai_client.responses.create.side_effect = Exception("timeout")
        result = svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        assert result is None


class TestLLMKPIRefinerPrompt:
    """Verify the prompt sent to the LLM contains the right info."""

    def _kpi_match(self):
        return KPIMatch(
            kpi_id="kpi_003",
            kpi_name="Number of Inactive Bots",
            category="bot",
            chart_type="stat",
            logic="Returns count of inactive bots.",
            sql="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master;",
            raw_query="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master;",
            match_score=0.72,
            tables_used=["bot_master", "task_master_log"],
            requires_location=True,
            requires_time_range=True,
            parameters_applied={},
            top_candidates=_make_top_candidates(),
        )

    def test_prompt_contains_user_query(self):
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9 in frk today",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        # Check the prompt sent to LLM
        call_args = svc.sql_engine.openai_client.responses.create.call_args
        prompt = call_args.kwargs.get("input") or call_args[1].get("input")
        assert "inactive time of bot 9 in frk today" in prompt

    def test_prompt_contains_all_candidate_sqls(self):
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        call_args = svc.sql_engine.openai_client.responses.create.call_args
        prompt = call_args.kwargs.get("input") or call_args[1].get("input")
        # All 3 candidates' SQL should appear
        assert "kpi_003" in prompt
        assert "kpi_001" in prompt
        assert "kpi_002" in prompt

    def test_prompt_contains_table_schema(self):
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        call_args = svc.sql_engine.openai_client.responses.create.call_args
        prompt = call_args.kwargs.get("input") or call_args[1].get("input")
        assert "TABLE: bot_master" in prompt
        assert "BOT_ID" in prompt

    def test_uses_structured_json_output(self):
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        call_args = svc.sql_engine.openai_client.responses.create.call_args
        text_format = call_args.kwargs.get("text") or call_args[1].get("text")
        assert text_format["format"]["type"] == "json_schema"
        assert text_format["format"]["name"] == "kpi_refinement"
        assert text_format["format"]["strict"] is True

    def test_calls_substitute_params_for_each_candidate(self):
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from="2026-04-09 00:00:00",
            time_to="2026-04-09 23:59:59",
            all_sites=False,
        )
        # _substitute_params should be called 3 times (once per candidate)
        assert svc.kpi_resolver._substitute_params.call_count == 3

    def test_prompt_contains_grounding_constraint(self):
        """Prompt must tell LLM to always pick from candidates, not return NONE."""
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="total inactive time for bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        call_args = svc.sql_engine.openai_client.responses.create.call_args
        prompt = call_args.kwargs.get("input") or call_args[1].get("input")
        assert "MUST pick one" in prompt or "MUST pick" in prompt
        assert "NEVER invent new tables" in prompt

    def test_prompt_includes_user_queries(self):
        """Prompt must include example user queries from the KPI registry."""
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="inactive time for bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        call_args = svc.sql_engine.openai_client.responses.create.call_args
        prompt = call_args.kwargs.get("input") or call_args[1].get("input")
        # Should contain example questions from the registry
        assert "Example user questions" in prompt
        assert "How many bots are inactive?" in prompt


class TestLLMKPIRefinerResult:
    """Verify the result dict structure returned by _llm_refine_kpi_query."""

    def _kpi_match(self):
        return KPIMatch(
            kpi_id="kpi_003",
            kpi_name="Number of Inactive Bots",
            category="bot",
            chart_type="stat",
            logic="Returns count of inactive bots.",
            sql="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master;",
            raw_query="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master;",
            match_score=0.72,
            tables_used=["bot_master", "task_master_log"],
            requires_location=True,
            requires_time_range=True,
            parameters_applied={},
            top_candidates=_make_top_candidates(),
        )

    def test_result_has_required_keys(self):
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT BOT_ID, INACTIVE_HOURS FROM vw;",
            "chart_type": "bar chart",
            "explanation": "Switched to hours KPI.",
        }
        svc = _build_service_stub(llm_resp)
        result = svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        assert result is not None
        for key in ("kpi_id", "kpi_name", "sql", "chart_type",
                     "explanation", "tables_used", "logic", "score"):
            assert key in result, f"Missing key: {key}"

    def test_result_preserves_candidate_metadata(self):
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        result = svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        assert result["kpi_name"] == "Active vs Inactive hours for bot"
        assert result["tables_used"] == ["bot_master", "task_master_log"]
        assert result["score"] == 0.68  # from top_candidates

    def test_result_sql_comes_from_llm(self):
        custom_sql = "SELECT _cp.BOT_ID, _cp.INACTIVE_HOURS FROM (SELECT * FROM vw) AS _cp;"
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": custom_sql,
            "chart_type": "bar chart",
            "explanation": "Column projection applied.",
        }
        svc = _build_service_stub(llm_resp)
        result = svc._llm_refine_kpi_query(
            user_query="inactive time of bot 9",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        # The SQL should be exactly what the LLM returned
        assert result["sql"] == custom_sql


class TestUnitConversionPrompt:
    """The prompt must instruct the LLM to apply unit/derived-value conversions."""

    def _kpi_match(self):
        return KPIMatch(
            kpi_id="kpi_003",
            kpi_name="Number of Inactive Bots",
            category="bot",
            chart_type="stat",
            logic="Returns count of inactive bots.",
            sql="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master;",
            raw_query="SELECT COUNT(*) AS INACTIVE_BOTS FROM bot_master;",
            match_score=0.72,
            tables_used=["bot_master", "task_master_log"],
            requires_location=True,
            requires_time_range=True,
            parameters_applied={},
            top_candidates=_make_top_candidates(),
        )

    def test_prompt_contains_unit_conversion_rule(self):
        """Prompt must contain the unit conversion instruction block."""
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="how many hours bot 27 was down today in frk",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from="2026-04-15 00:00:00",
            time_to="2026-04-15 23:59:59",
            all_sites=False,
        )
        call_args = svc.sql_engine.openai_client.responses.create.call_args
        prompt = call_args.kwargs.get("input") or call_args[1].get("input")
        # Must mention unit conversion
        assert "UNIT / DERIVED VALUE CONVERSION" in prompt
        # Must mention specific conversions
        assert "minutes" in prompt.lower() and "hours" in prompt.lower()
        assert "/ 60" in prompt
        assert "ROUND" in prompt

    def test_prompt_contains_output_columns(self):
        """Prompt must list OUTPUT COLUMNS for each candidate."""
        llm_resp = {
            "selected_kpi_id": "kpi_001",
            "sql": "SELECT 1;",
            "chart_type": "bar chart",
            "explanation": "test",
        }
        svc = _build_service_stub(llm_resp)
        svc._llm_refine_kpi_query(
            user_query="inactive hours for bots",
            kpi_match=self._kpi_match(),
            tenant_values=["frk"],
            time_from=None,
            time_to=None,
            all_sites=False,
        )
        call_args = svc.sql_engine.openai_client.responses.create.call_args
        prompt = call_args.kwargs.get("input") or call_args[1].get("input")
        assert "OUTPUT COLUMNS" in prompt

    def test_extract_output_columns_basic(self):
        """Static method extracts aliases from a final SELECT."""
        from app.services.sql_assistant.sql_assistant import SQLAssistantService
        sql = (
            "WITH cte AS (SELECT x FROM y) "
            "SELECT activity_date AS time, BOT_ID, "
            "downtime_seconds/60 AS Downtime "
            "FROM daily_downtime"
        )
        cols = SQLAssistantService._extract_output_columns(sql)
        assert "time" in cols
        assert "Downtime" in cols

    def test_extract_output_columns_backtick_aliases(self):
        """Handles backtick-quoted aliases."""
        from app.services.sql_assistant.sql_assistant import SQLAssistantService
        sql = (
            "SELECT SUM(x) AS `Total occupied weight (kg)` "
            "FROM inventory"
        )
        cols = SQLAssistantService._extract_output_columns(sql)
        assert "Total occupied weight (kg)" in cols
