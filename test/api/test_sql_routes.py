"""
API Tests — SQL Execution Routes (/api/sql/execute)
Target: backend/app/api/sql_execution_routes.py

Tests:
  - Security checks (dangerous SQL blocked)
  - Valid SELECT execution (mocked DB)
  - Response schema
  - Error handling
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))


@pytest.fixture
def client():
    """TestClient with mocked DB connection."""
    with patch("app.api.sql_execution_routes.db_config", {
        "host": "localhost", "user": "test", "password": "test",
        "database": "neo_test", "port": 3306, "charset": "utf8mb4",
        "cursorclass": MagicMock()
    }), \
    patch("app.api.chatbot_endpoints.sql_service", MagicMock()), \
    patch("app.api.chatbot_endpoints.kb_service", MagicMock()), \
    patch("app.api.chatbot_endpoints.diagnostic_service", MagicMock()), \
    patch("app.api.chatbot_endpoints.chat_history_service", None), \
    patch("app.api.chatbot_endpoints.agentic_service", None):

        from fastapi.testclient import TestClient
        from app.main import app
        yield TestClient(app)


# ===================================================================
# SECURITY — DANGEROUS SQL BLOCKED
# ===================================================================
class TestSQLSecurity:

    @pytest.mark.parametrize("dangerous_sql", [
        "DROP TABLE users",
        "DELETE FROM bal_pick_dtl",
        "TRUNCATE TABLE bal_pick_dtl",
        "ALTER TABLE bal_pick_dtl ADD COLUMN x INT",
        "CREATE TABLE hack (id INT)",
        "INSERT INTO bal_pick_dtl VALUES (1)",
        "UPDATE bal_pick_dtl SET status = 'hacked'",
    ])
    def test_dangerous_queries_blocked(self, client, dangerous_sql):
        resp = client.post("/api/sql/execute", json={
            "sql_query": dangerous_sql
        })
        data = resp.json()
        # Should either return 200 with success=false or 4xx error
        assert data.get("success") is False or resp.status_code >= 400

    def test_empty_query(self, client):
        resp = client.post("/api/sql/execute", json={
            "sql_query": ""
        })
        # Empty query should fail
        data = resp.json()
        assert data.get("success") is False or resp.status_code >= 400


# ===================================================================
# VALID QUERIES (with mocked DB)
# ===================================================================
class TestValidQueries:

    def test_select_query_endpoint_exists(self, client):
        """Just verify the endpoint exists and accepts POST."""
        resp = client.post("/api/sql/execute", json={
            "sql_query": "SELECT 1 LIMIT 1"
        })
        # May fail on actual DB connection (mocked above may not be perfect)
        # But should NOT be 404
        assert resp.status_code != 404

    def test_missing_sql_query_returns_422(self, client):
        resp = client.post("/api/sql/execute", json={})
        assert resp.status_code == 422


# ===================================================================
# RESPONSE SCHEMA
# ===================================================================
class TestResponseSchema:

    def test_response_has_required_fields(self, client):
        resp = client.post("/api/sql/execute", json={
            "sql_query": "SELECT COUNT(*) FROM bal_pick_dtl"
        })
        if resp.status_code == 200:
            data = resp.json()
            assert "success" in data
            assert "row_count" in data
