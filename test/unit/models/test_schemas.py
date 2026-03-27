"""
Unit Tests — Pydantic Schemas
Target: backend/app/models/schemas.py

Tests:
  - ChatRequest validation (required fields, defaults)
  - ChatResponse serialization
  - ChatbotType enum values
  - Edge cases (missing fields, invalid types)
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.models.schemas import (
    ChatRequest, ChatResponse, ChatbotType,
    ChatMessage, MessageRole, SourceDocument,
)


# ===================================================================
# CHATBOT TYPE ENUM
# ===================================================================
class TestChatbotType:

    def test_knowledge_base(self):
        assert ChatbotType.KNOWLEDGE_BASE == "knowledge_base"

    def test_sql_assistant(self):
        assert ChatbotType.SQL_ASSISTANT == "sql_assistant"

    def test_diagnostic(self):
        assert ChatbotType.DIAGNOSTIC == "diagnostic"

    def test_general(self):
        assert ChatbotType.GENERAL == "general"


# ===================================================================
# CHAT REQUEST VALIDATION
# ===================================================================
class TestChatRequest:

    def test_minimal_request(self):
        req = ChatRequest(message="hello")
        assert req.message == "hello"
        assert req.chatbot_type == ChatbotType.GENERAL

    def test_full_request(self):
        req = ChatRequest(
            message="show picks",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id="sess-123",
            user_id="user@test.com"
        )
        assert req.chatbot_type == ChatbotType.SQL_ASSISTANT
        assert req.session_id == "sess-123"
        assert req.user_id == "user@test.com"

    def test_missing_message_raises(self):
        with pytest.raises(Exception):
            ChatRequest()

    def test_conversation_history_default_empty(self):
        req = ChatRequest(message="hi")
        assert req.conversation_history == []

    def test_with_conversation_history(self):
        history = [
            ChatMessage(role=MessageRole.USER, content="hello"),
            ChatMessage(role=MessageRole.ASSISTANT, content="hi"),
        ]
        req = ChatRequest(message="next question", conversation_history=history)
        assert len(req.conversation_history) == 2


# ===================================================================
# CHAT RESPONSE
# ===================================================================
class TestChatResponse:

    def test_minimal_response(self):
        resp = ChatResponse(
            response="Here are the results",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
        )
        assert resp.response == "Here are the results"
        assert resp.sql_query is None
        assert resp.sources == []

    def test_sql_response(self):
        resp = ChatResponse(
            response="Query results",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            sql_query="SELECT COUNT(*) FROM bal_pick_dtl",
            confidence_score=0.92,
            query_results=[{"count": 42}]
        )
        assert resp.sql_query is not None
        assert resp.confidence_score == 0.92

    def test_kb_response_with_sources(self):
        sources = [
            SourceDocument(
                document_name="guide.pdf",
                content_snippet="Chapter 1...",
                relevance_score=0.85,
                document_type="pdf"
            )
        ]
        resp = ChatResponse(
            response="Answer from docs",
            chatbot_type=ChatbotType.KNOWLEDGE_BASE,
            sources=sources
        )
        assert len(resp.sources) == 1
        assert resp.sources[0].document_name == "guide.pdf"


# ===================================================================
# CHAT MESSAGE
# ===================================================================
class TestChatMessage:

    def test_user_message(self):
        msg = ChatMessage(role=MessageRole.USER, content="hello")
        assert msg.role == "user"
        assert msg.content == "hello"
        assert msg.timestamp is not None

    def test_assistant_message(self):
        msg = ChatMessage(role=MessageRole.ASSISTANT, content="hi")
        assert msg.role == "assistant"

    def test_message_metadata(self):
        msg = ChatMessage(
            role=MessageRole.USER,
            content="test",
            metadata={"source": "api"}
        )
        assert msg.metadata["source"] == "api"
