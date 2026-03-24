"""
NEO Chatbot — Root Test Configuration
======================================
Shared fixtures for all test layers (unit, integration, api, e2e).

Usage:
    pytest test/                  — run everything
    pytest test/unit/             — unit tests only
    pytest test/api/              — API tests only
    pytest -m "not slow"          — skip slow tests
"""

import sys
import os
import json
import pytest
from pathlib import Path
from unittest.mock import MagicMock, patch
from dataclasses import dataclass
from typing import List, Dict, Any

# ---------------------------------------------------------------------------
# PATH SETUP — ensure `backend/` is importable
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).parent.parent
BACKEND_DIR = PROJECT_ROOT / "backend"
sys.path.insert(0, str(BACKEND_DIR))
sys.path.insert(0, str(PROJECT_ROOT))

# ---------------------------------------------------------------------------
# FIXTURES DIR
# ---------------------------------------------------------------------------
FIXTURES_DIR = Path(__file__).parent / "fixtures"


# ===================================================================
# 1. DATA-CLASS HELPERS (mirror backend models without import issues)
# ===================================================================
@dataclass
class MockSQLGenerationResult:
    sql: str
    confidence: float
    explanation: str
    assumptions: List[str]
    metadata: Dict[str, Any]


@dataclass
class MockSQLExecutionResult:
    rows: List[Dict[str, Any]]
    row_count: int
    execution_time_ms: int


# ===================================================================
# 2. SCHEMA FIXTURES
# ===================================================================
@pytest.fixture
def sample_schema():
    """Minimal warehouse schema for unit tests."""
    return {
        "bal_outbound_parcel_scan_dtl": [
            "id", "host-location", "article", "station-id", "bot-id",
            "wave-id", "scan-time", "status", "quantity", "created_at"
        ],
        "bal_inbound_receipt_dtl": [
            "id", "host-location", "article", "receipt-no", "bin-id",
            "quantity", "received_at", "status"
        ],
        "bal_pick_dtl": [
            "id", "host-location", "article", "station-id", "bot-id",
            "wave-id", "pick-time", "status", "quantity"
        ],
        "bal_put_dtl": [
            "id", "host-location", "article", "bin-id",
            "put-time", "status", "quantity"
        ],
        "bal_master_article": [
            "id", "host-location", "article", "description",
            "category", "weight", "dimensions"
        ],
        "bal_master_bot": [
            "id", "host-location", "bot-id", "bot-type",
            "status", "last_seen"
        ],
        "bal_master_station": [
            "id", "host-location", "station-id", "station-type",
            "zone", "status"
        ],
        "bal_master_bin": [
            "id", "host-location", "bin-id", "bin-type",
            "zone", "capacity", "status"
        ],
    }


@pytest.fixture
def sample_table_metadata():
    """Table metadata for table selector tests."""
    return {
        "bal_outbound_parcel_scan_dtl": {
            "description": "Outbound parcel scanning details, tracks items scanned at packing stations",
            "category": "log"
        },
        "bal_inbound_receipt_dtl": {
            "description": "Inbound receipt details for goods received at warehouse",
            "category": "log"
        },
        "bal_pick_dtl": {
            "description": "Pick operation details for order fulfillment",
            "category": "log"
        },
        "bal_put_dtl": {
            "description": "Put-away operation details for storing items in bins",
            "category": "log"
        },
        "bal_master_article": {
            "description": "Master data for articles/SKUs/products",
            "category": "master"
        },
        "bal_master_bot": {
            "description": "Master data for robots/bots in the warehouse",
            "category": "master"
        },
        "bal_master_station": {
            "description": "Master data for workstations in the warehouse",
            "category": "master"
        },
        "bal_master_bin": {
            "description": "Master data for bins/containers in the warehouse",
            "category": "master"
        },
    }


# ===================================================================
# 3. LLM / GENERATION MOCK FIXTURES
# ===================================================================
@pytest.fixture
def mock_generation_result():
    """Factory for SQLGenerationResult-like objects."""
    def _make(sql="SELECT 1", confidence=0.9, tables_used=None):
        return MockSQLGenerationResult(
            sql=sql,
            confidence=confidence,
            explanation="Test explanation",
            assumptions=["test assumption"],
            metadata={"tables_used": tables_used or [], "source": "test"}
        )
    return _make


@pytest.fixture
def mock_execution_result():
    """Factory for SQLExecutionResult-like objects."""
    def _make(rows=None, row_count=None, execution_time_ms=50):
        rows = rows or [{"id": 1, "article": "ART-001"}]
        return MockSQLExecutionResult(
            rows=rows,
            row_count=row_count if row_count is not None else len(rows),
            execution_time_ms=execution_time_ms
        )
    return _make


@pytest.fixture
def mock_llm_response():
    """Canned LLM response payloads (for sql_engine tests)."""
    return {
        "simple_select": {
            "sql": "SELECT article, quantity FROM bal_outbound_parcel_scan_dtl WHERE `host-location` = 'frk' LIMIT 100",
            "confidence": 0.92,
            "explanation": "Selecting articles and quantities from outbound scan",
            "assumptions": ["Using frk tenant"],
            "tables_used": ["bal_outbound_parcel_scan_dtl"]
        },
        "aggregation": {
            "sql": "SELECT COUNT(*) AS total FROM bal_pick_dtl WHERE `host-location` = 'shakti'",
            "confidence": 0.95,
            "explanation": "Counting all pick records for shakti",
            "assumptions": ["Aggregation query - no LIMIT needed"],
            "tables_used": ["bal_pick_dtl"]
        },
        "join_query": {
            "sql": (
                "SELECT p.article, m.description, COUNT(*) AS picks "
                "FROM bal_pick_dtl p "
                "JOIN bal_master_article m ON p.article = m.article AND p.`host-location` = m.`host-location` "
                "WHERE p.`host-location` = 'frk' "
                "GROUP BY p.article, m.description "
                "ORDER BY picks DESC LIMIT 10"
            ),
            "confidence": 0.88,
            "explanation": "Top 10 picked articles with descriptions",
            "assumptions": ["Joining on article + host-location composite key"],
            "tables_used": ["bal_pick_dtl", "bal_master_article"]
        }
    }


# ===================================================================
# 4. TENANT FIXTURES
# ===================================================================
@pytest.fixture
def tenant_value_mappings():
    """Predefined tenant value mappings."""
    return {
        "_note": "Actual DB values: BLR, chennai, frk, shakti",
        "bangalore": "BLR",
        "bengaluru": "BLR",
        "blr": "BLR",
        "faridabad": "frk",
        "frk": "frk",
        "bhiwandi": "shakti",
        "biwandi": "shakti",
        "shakti": "shakti",
        "chennai": "chennai",
    }


@pytest.fixture
def actual_tenant_values():
    """DB tenant values as they appear in `host-location` column."""
    return ["BLR", "chennai", "frk", "shakti"]


# ===================================================================
# 5. QUERY TEST BANK
# ===================================================================
@pytest.fixture
def query_test_bank():
    """Load the full query test bank from fixtures/query_cases.json."""
    path = FIXTURES_DIR / "query_cases.json"
    if path.exists():
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    # Inline fallback
    return [
        {
            "query": "show total picks today",
            "intent": {"aggregation": "count", "time_filter": "today"},
            "expected_tables": ["bal_pick_dtl"],
            "tenant": None
        },
        {
            "query": "top 5 articles picked at bhiwandi last week",
            "intent": {"aggregation": "count", "time_filter": "last_week", "limit": 5},
            "expected_tables": ["bal_pick_dtl"],
            "tenant": "shakti"
        },
    ]


# ===================================================================
# 6. SERVICE MOCK FACTORIES
# ===================================================================
@pytest.fixture
def mock_executor():
    """Mock SQLExecutor."""
    executor = MagicMock()
    executor.execute.return_value = MockSQLExecutionResult(
        rows=[{"id": 1, "count": 42}],
        row_count=1,
        execution_time_ms=35,
    )
    return executor


@pytest.fixture
def mock_classification_service():
    """Mock QueryClassificationService."""
    svc = MagicMock()
    svc.find_similar_classified_query.return_value = None
    svc.store_query.return_value = "q-001"
    return svc


@pytest.fixture
def mock_validator():
    """Mock SQLValidator that always passes."""
    v = MagicMock()
    v.validate.return_value = None
    return v


@pytest.fixture
def mock_schema_validator(sample_schema):
    """Mock SchemaValidator that always passes."""
    sv = MagicMock()
    sv.validate.return_value = None
    return sv


# ===================================================================
# 7. SETTINGS OVERRIDE
# ===================================================================
@pytest.fixture
def test_settings(tmp_path):
    """Patched settings pointing at temp directories."""
    with patch("app.core.config.settings") as mock_settings:
        mock_settings.MULTI_TENANT_ENABLED = True
        mock_settings.TENANT_COLUMN = "host-location"
        mock_settings.DEFAULT_TENANT = "frk"
        mock_settings.TENANT_EXTRACTION_THRESHOLD = 0.65
        mock_settings.TENANT_DEFAULT_BEHAVIOR = "smart_aggregate"
        mock_settings.DATA_DIR = tmp_path
        mock_settings.DB_HOST = "localhost"
        mock_settings.DB_PORT = 3306
        mock_settings.DB_USER = "test"
        mock_settings.DB_PASSWORD = "test"
        mock_settings.DB_NAME = "neo_test"
        mock_settings.OPENAI_API_KEY = "test-key"
        mock_settings.GROQ_API_KEY = "test-key"
        mock_settings.AGENTIC_MODE_ENABLED = False
        yield mock_settings


# ===================================================================
# 8. FASTAPI TEST CLIENT
# ===================================================================
@pytest.fixture
def test_client():
    """
    FastAPI TestClient — imports the real app but patches heavy services.
    Use for API-layer tests only.
    """
    from fastapi.testclient import TestClient

    # Patch heavy services that attempt real DB / LLM connections at import
    with patch("app.api.chatbot_endpoints.sql_service") as mock_sql, \
         patch("app.api.chatbot_endpoints.kb_service") as mock_kb, \
         patch("app.api.chatbot_endpoints.diagnostic_service") as mock_diag, \
         patch("app.api.chatbot_endpoints.chat_history_service", None):

        mock_sql.process_query.return_value = MagicMock(
            response="Test SQL response",
            chatbot_type="sql_assistant",
            session_id="test-session",
            confidence_score=0.9,
            sql_query="SELECT 1",
            query_results=[],
            sources=[],
            suggested_actions=[],
            metadata={},
        )
        mock_kb.process_query.return_value = MagicMock(
            response="Test KB response",
            chatbot_type="knowledge_base",
            session_id="test-session",
            confidence_score=0.85,
            sources=[],
            suggested_actions=[],
            sql_query=None,
            query_results=None,
            metadata={},
        )

        from app.main import app
        client = TestClient(app)
        yield client


# ===================================================================
# 9. PYTEST MARKERS REGISTRATION
# ===================================================================
def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "slow: marks tests as slow (> 5 s)")
    config.addinivalue_line("markers", "integration: requires real DB or heavy services")
    config.addinivalue_line("markers", "e2e: end-to-end pipeline tests")
    config.addinivalue_line("markers", "api: FastAPI endpoint tests")
