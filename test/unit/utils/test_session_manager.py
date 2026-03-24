"""
Unit Tests — UnifiedSessionManager
Target: backend/app/utils/session_manager.py

Fully in-memory — no mocking needed.

Tests:
  - Session creation and retrieval
  - Message lifecycle (add, get history)
  - LLM context formatting
  - Session end/delete
  - Old session cleanup
  - Active session listing
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.utils.session_manager import UnifiedSessionManager, SessionType


@pytest.fixture
def manager():
    return UnifiedSessionManager()


# ===================================================================
# SESSION LIFECYCLE
# ===================================================================
class TestSessionLifecycle:

    def test_create_session_returns_id(self, manager):
        sid = manager.create_session(SessionType.SQL_ASSISTANT)
        assert isinstance(sid, str)
        assert len(sid) > 0

    def test_get_session_found(self, manager):
        sid = manager.create_session(SessionType.SQL_ASSISTANT)
        session = manager.get_session(sid)
        assert session is not None
        assert session["session_type"] == "sql_assistant"

    def test_get_session_not_found(self, manager):
        assert manager.get_session("nonexistent") is None

    def test_create_with_initial_message(self, manager):
        sid = manager.create_session(
            SessionType.KNOWLEDGE_BASE,
            initial_message="hello"
        )
        session = manager.get_session(sid)
        assert session["message_count"] == 1

    def test_create_with_metadata(self, manager):
        sid = manager.create_session(
            SessionType.GENERAL,
            metadata={"user_id": "test@example.com"}
        )
        session = manager.get_session(sid)
        assert session["context"]["user_id"] == "test@example.com"


# ===================================================================
# MESSAGE OPERATIONS
# ===================================================================
class TestMessages:

    def test_add_message(self, manager):
        sid = manager.create_session()
        result = manager.add_message(sid, "user", "hello")
        assert result is True

    def test_add_message_invalid_session(self, manager):
        result = manager.add_message("invalid", "user", "hello")
        assert result is False

    def test_message_count_updates(self, manager):
        sid = manager.create_session()
        manager.add_message(sid, "user", "q1")
        manager.add_message(sid, "assistant", "a1")
        session = manager.get_session(sid)
        assert session["message_count"] == 2

    def test_message_metadata(self, manager):
        sid = manager.create_session()
        manager.add_message(sid, "user", "hello", metadata={"confidence": 0.9})
        history = manager.get_conversation_history(sid)
        assert history[0]["metadata"]["confidence"] == 0.9


# ===================================================================
# CONVERSATION HISTORY
# ===================================================================
class TestConversationHistory:

    def test_get_full_history(self, manager):
        sid = manager.create_session()
        manager.add_message(sid, "user", "q1")
        manager.add_message(sid, "assistant", "a1")
        manager.add_message(sid, "user", "q2")
        history = manager.get_conversation_history(sid)
        assert len(history) == 3

    def test_get_last_n(self, manager):
        sid = manager.create_session()
        for i in range(10):
            manager.add_message(sid, "user", f"msg-{i}")
        history = manager.get_conversation_history(sid, last_n=3)
        assert len(history) == 3
        assert history[0]["content"] == "msg-7"

    def test_empty_history(self, manager):
        sid = manager.create_session()
        history = manager.get_conversation_history(sid)
        assert history == []

    def test_invalid_session_returns_empty(self, manager):
        history = manager.get_conversation_history("invalid")
        assert history == []


# ===================================================================
# LLM CONTEXT
# ===================================================================
class TestLLMContext:

    def test_context_format(self, manager):
        sid = manager.create_session()
        manager.add_message(sid, "user", "hello")
        manager.add_message(sid, "assistant", "hi there")
        context = manager.get_context_for_llm(sid, max_messages=10)
        assert isinstance(context, list)
        assert len(context) == 2
        assert context[0]["role"] == "user"
        assert context[0]["content"] == "hello"

    def test_context_limited(self, manager):
        sid = manager.create_session()
        for i in range(20):
            manager.add_message(sid, "user", f"msg-{i}")
        context = manager.get_context_for_llm(sid, max_messages=5)
        assert len(context) == 5


# ===================================================================
# END / DELETE SESSION
# ===================================================================
class TestEndDelete:

    def test_end_session(self, manager):
        sid = manager.create_session()
        result = manager.end_session(sid)
        assert result is True
        session = manager.get_session(sid)
        assert session["active"] is False

    def test_delete_session(self, manager):
        sid = manager.create_session()
        result = manager.delete_session(sid)
        assert result is True
        assert manager.get_session(sid) is None

    def test_delete_nonexistent(self, manager):
        result = manager.delete_session("invalid")
        assert result is False


# ===================================================================
# CLEANUP OLD SESSIONS
# ===================================================================
class TestCleanup:

    def test_clear_old_sessions(self, manager):
        sid = manager.create_session()
        # Fresh session should not be cleared with 24h max
        cleared = manager.clear_old_sessions(max_age_hours=24)
        assert cleared == 0
        assert manager.get_session(sid) is not None


# ===================================================================
# LIST ACTIVE SESSIONS
# ===================================================================
class TestListActive:

    def test_list_all_active(self, manager):
        manager.create_session(SessionType.SQL_ASSISTANT)
        manager.create_session(SessionType.KNOWLEDGE_BASE)
        sessions = manager.list_active_sessions()
        assert len(sessions) == 2

    def test_list_by_type(self, manager):
        manager.create_session(SessionType.SQL_ASSISTANT)
        manager.create_session(SessionType.KNOWLEDGE_BASE)
        manager.create_session(SessionType.SQL_ASSISTANT)
        sessions = manager.list_active_sessions(session_type=SessionType.SQL_ASSISTANT)
        assert len(sessions) == 2
