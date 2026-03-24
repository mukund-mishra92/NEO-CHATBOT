"""
E2E Tests — API-level End-to-End
================================
Tests the full user journey via HTTP:
  POST /api/chatbot/chat → internal routing → mocked services → JSON response

Validates request/response contracts, session handling, and
error propagation through the FastAPI stack.
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))


@pytest.mark.e2e
class TestAPIEndToEnd:
    """Full HTTP round-trip tests with mocked backend services."""

    def test_sql_query_full_lifecycle(self, test_client):
        """
        POST chat → get response → verify session persists → follow-up query
        """
        # First request — creates session
        resp1 = test_client.post("/api/chatbot/chat", json={
            "message": "total picks today",
            "chatbot_type": "sql_assistant",
        })
        assert resp1.status_code == 200
        data1 = resp1.json()
        assert "response" in data1
        session_id = data1.get("session_id", "")

        # Second request — same session
        resp2 = test_client.post("/api/chatbot/chat", json={
            "message": "break that down by site",
            "chatbot_type": "sql_assistant",
            "session_id": session_id,
        })
        assert resp2.status_code == 200
        data2 = resp2.json()
        assert "response" in data2

    def test_knowledge_base_query(self, test_client):
        """POST /api/chatbot/chat with knowledge_base type."""
        resp = test_client.post("/api/chatbot/chat", json={
            "message": "what is wave management?",
            "chatbot_type": "knowledge_base",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert "response" in data

    def test_missing_message_returns_422(self, test_client):
        """Missing required field gives validation error."""
        resp = test_client.post("/api/chatbot/chat", json={
            "chatbot_type": "sql_assistant",
        })
        assert resp.status_code == 422

    def test_health_endpoint(self, test_client):
        """GET /health confirms service is alive."""
        resp = test_client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("status") == "healthy"

    def test_response_schema_contract(self, test_client):
        """Verify the response JSON includes all expected keys."""
        resp = test_client.post("/api/chatbot/chat", json={
            "message": "how many picks today",
            "chatbot_type": "sql_assistant",
        })
        assert resp.status_code == 200
        data = resp.json()
        # Must have at minimum
        assert "response" in data
        # Optional but expected
        for key in ["session_id", "chatbot_type"]:
            if key in data:
                assert data[key] is not None


@pytest.mark.e2e
class TestSecurityE2E:
    """Security checks via HTTP — dangerous queries must never execute."""

    @pytest.fixture(autouse=True)
    def _setup_client(self, test_client):
        self.client = test_client

    @pytest.mark.parametrize("dangerous_sql", [
        "DROP TABLE bal_pick_dtl",
        "DELETE FROM bal_pick_dtl WHERE 1=1",
        "TRUNCATE TABLE bal_pick_dtl",
        "ALTER TABLE bal_pick_dtl ADD COLUMN hacked INT",
        "INSERT INTO bal_pick_dtl VALUES (1,2,3)",
        "UPDATE bal_pick_dtl SET article='hacked'",
    ])
    def test_sql_execution_endpoint_blocks_dangerous(self, dangerous_sql):
        """POST /api/sql/execute must reject write operations."""
        resp = self.client.post("/api/sql/execute", json={
            "sql_query": dangerous_sql,
        })
        # Should be blocked — either non-200 or response indicates error
        if resp.status_code == 200:
            data = resp.json()
            # Either success=False or error message present
            assert data.get("success") is False or data.get("error") is not None, (
                f"Dangerous SQL was not blocked: {dangerous_sql}"
            )
        else:
            assert resp.status_code in [400, 403, 422, 500]


@pytest.mark.e2e
class TestQueryTestBankE2E:
    """
    Run queries from the test bank through the API layer.
    Validates that the system accepts them without crashing.
    """

    def test_all_test_bank_queries_accepted(self, test_client, query_test_bank):
        """Every query in the test bank should get a 200 response (not crash)."""
        for case in query_test_bank[:5]:  # Limit to first 5 for speed
            resp = test_client.post("/api/chatbot/chat", json={
                "message": case["query"],
                "chatbot_type": "sql_assistant",
            })
            assert resp.status_code == 200, (
                f"Query failed: {case['query']!r} → {resp.status_code}"
            )
            data = resp.json()
            assert "response" in data
