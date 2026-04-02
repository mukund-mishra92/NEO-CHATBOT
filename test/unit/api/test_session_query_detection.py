"""
Unit Tests — _is_session_query helper
Target: backend/app/api/chatbot_endpoints.py :: _is_session_query()

Pure function — tests pattern matching for session/history queries.
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))


@pytest.fixture(scope="module")
def is_session_query():
    """Import the pure function with heavy services mocked."""
    with patch("app.api.chatbot_endpoints.KnowledgeBaseService", MagicMock()), \
         patch("app.api.chatbot_endpoints.SQLAssistantService", MagicMock()), \
         patch("app.api.chatbot_endpoints.DiagnosticService", MagicMock()), \
         patch("app.api.chatbot_endpoints.ChatHistoryService", MagicMock()), \
         patch("app.api.chatbot_endpoints.get_agentic_service", MagicMock(return_value=None)), \
         patch("app.api.chatbot_endpoints.settings") as mock_settings:

        mock_settings.AGENTIC_MODE_ENABLED = False
        mock_settings.DB_HOST = "localhost"
        mock_settings.DB_PORT = 3306
        mock_settings.DB_USER = "test"
        mock_settings.DB_PASSWORD = "test"
        mock_settings.DB_NAME = "neo_test"

        from app.api.chatbot_endpoints import _is_session_query
        yield _is_session_query


# ===================================================================
# POSITIVE CASES — should detect as session query
# ===================================================================
class TestSessionQueryPositive:

    @pytest.mark.parametrize("query", [
        "What have we discussed?",
        "what did we discuss",
        "summarize our conversation",
        "what did I ask earlier",
        "recap our conversation",
        "what topics have we covered",
        "chat history",
        "session history",
        "conversation history",
        "refresh my memory",
        "what was my question",
        "previous questions",
        "tell me what we discussed",
    ])
    def test_session_patterns_detected(self, is_session_query, query):
        assert is_session_query(query) is True


# ===================================================================
# NEGATIVE CASES — should NOT detect as session query
# ===================================================================
class TestSessionQueryNegative:

    @pytest.mark.parametrize("query", [
        "show total picks today",
        "how many bots active",
        "top 5 articles at bhiwandi",
        "compare frk and shakti",
        "hello",
        "what is bot 4 doing",
    ])
    def test_non_session_queries_pass(self, is_session_query, query):
        assert is_session_query(query) is False
