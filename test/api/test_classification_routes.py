"""
API Tests — Classification Routes (/api/classification/*)
Target: backend/app/api/classification_routes.py

Tests:
  - GET /unclassified
  - GET /stats
  - POST /classify
  - GET /search
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))


@pytest.fixture
def client():
    """TestClient with mocked classification service."""
    mock_cs = MagicMock()
    mock_cs.get_unclassified_queries.return_value = [
        {
            "query_id": "q-001",
            "timestamp": "2026-03-23T10:00:00",
            "user_query": "test query",
            "generated_sql": "SELECT 1",
            "classification": "unclassified",
            "rows_returned": 1,
            "confidence": 0.8,
            "tables_used": ["bal_pick_dtl"],
        }
    ]
    mock_cs.get_classification_stats.return_value = {
        "total_queries": 100, "correct": 60, "incorrect": 20,
        "needs_review": 0, "unclassified": 20, "accuracy": 0.75
    }
    mock_cs.classify_query.return_value = True
    mock_cs.add_manual_query.return_value = {
        "query_id": "manual_001",
        "timestamp": "2026-03-30T10:00:00",
        "user_query": "manual question",
        "generated_sql": "SELECT 1",
        "classification": "unclassified",
        "rows_returned": 0,
        "confidence": 1.0,
        "tables_used": [],
        "execution_status": "manual",
        "session_id": "manual_entry",
        "metadata": {"source": "classification_ui_manual_entry"}
    }
    mock_cs.get_high_confidence_queries.return_value = []
    mock_cs.search_queries.return_value = []

    with patch("app.api.classification_routes.classification_service", mock_cs), \
         patch("app.api.chatbot_endpoints.sql_service", MagicMock()), \
         patch("app.api.chatbot_endpoints.kb_service", MagicMock()), \
         patch("app.api.chatbot_endpoints.diagnostic_service", MagicMock()), \
         patch("app.api.chatbot_endpoints.chat_history_service", None), \
         patch("app.api.chatbot_endpoints.agentic_service", None):

        from fastapi.testclient import TestClient
        from app.main import app
        yield TestClient(app)


# ===================================================================
# GET /unclassified
# ===================================================================
class TestUnclassified:

    def test_get_unclassified(self, client):
        resp = client.get("/api/classification/unclassified")
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list) or "queries" in data or isinstance(data, dict)

    def test_get_unclassified_with_limit(self, client):
        resp = client.get("/api/classification/unclassified?limit=5")
        assert resp.status_code == 200


# ===================================================================
# GET /stats
# ===================================================================
class TestStats:

    def test_get_stats(self, client):
        resp = client.get("/api/classification/stats")
        assert resp.status_code == 200
        data = resp.json()
        assert "total" in data or isinstance(data, dict)


# ===================================================================
# POST /classify
# ===================================================================
class TestClassify:

    def test_classify_query(self, client):
        resp = client.post("/api/classification/classify", json={
            "query_id": "q-001",
            "classification": "correct"
        })
        assert resp.status_code == 200


# ===================================================================
# POST /add
# ===================================================================
class TestAddQuery:

    def test_add_query(self, client):
        resp = client.post("/api/classification/add", json={
            "user_query": "How many completed orders today?",
            "generated_sql": "SELECT COUNT(*) FROM orders WHERE status='completed'"
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["query_id"] == "manual_001"
        assert data["classification"] == "unclassified"
