"""
Pydantic models and schemas for NEO Chatbot
"""

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum


class ChatbotType(str, Enum):
    """Type of chatbot interaction"""
    KNOWLEDGE_BASE = "knowledge_base"
    SQL_ASSISTANT = "sql_assistant"
    DIAGNOSTIC = "diagnostic"
    GENERAL = "general"


class MessageRole(str, Enum):
    """Message sender role"""
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"


class ChatMessage(BaseModel):
    """Single chat message"""
    role: MessageRole
    content: str
    timestamp: Optional[datetime] = Field(default_factory=datetime.now)
    metadata: Optional[Dict[str, Any]] = None


class ChatRequest(BaseModel):
    """Request to chatbot"""
    message: str = Field(..., description="User's message/question")
    chatbot_type: Optional[ChatbotType] = Field(default=ChatbotType.GENERAL)
    session_id: Optional[str] = None
    conversation_history: Optional[List[ChatMessage]] = []
    context: Optional[Dict[str, Any]] = None


class SourceDocument(BaseModel):
    """Document source for RAG"""
    document_name: str
    content_snippet: str
    relevance_score: float
    page_number: Optional[int] = None
    document_type: str  # pdf, docx, code, proposal


class ChatResponse(BaseModel):
    """Response from chatbot"""
    response: str
    chatbot_type: ChatbotType
    session_id: str
    sources: Optional[List[SourceDocument]] = []
    confidence_score: Optional[float] = None
    suggested_actions: Optional[List[str]] = []
    sql_query: Optional[str] = None  # For SQL assistant responses
    query_results: Optional[List[Dict[str, Any]]] = None  # For SQL results
    metadata: Optional[Dict[str, Any]] = None  # Agent metadata (format_decision, etc.)
    timestamp: datetime = Field(default_factory=datetime.now)


class DocumentUploadRequest(BaseModel):
    """Request to upload document to knowledge base"""
    document_name: str
    document_type: str  # pdf, docx, txt, code
    category: str  # documentation, code, proposal, support
    content: Optional[str] = None
    file_path: Optional[str] = None


class DiagnosticIssue(BaseModel):
    """System diagnostic issue"""
    issue_id: str
    issue_name: str
    issue_type: str
    severity: str  # critical, high, medium, low
    category: str  # database, scheduler, mining, performance, api, ui
    description: str
    symptoms: List[str]
    root_causes: List[str]
    diagnostic_steps: List[str]
    solutions: List[Dict[str, Any]]
    prevention_tips: List[str]
    detected_at: datetime = Field(default_factory=datetime.now)


class SystemHealthStatus(BaseModel):
    """System health check result"""
    overall_status: str  # healthy, warning, critical
    components: Dict[str, str]
    issues: List[DiagnosticIssue] = []
    timestamp: datetime = Field(default_factory=datetime.now)


class SQLQueryRequest(BaseModel):
    """Request to generate SQL query"""
    natural_language_query: str
    database_context: Optional[Dict[str, Any]] = None
    limit_results: Optional[int] = 100


class SQLQueryResponse(BaseModel):
    """Response with generated SQL query"""
    sql_query: str
    explanation: str
    estimated_rows: Optional[int] = None
    warnings: Optional[List[str]] = []
    results: Optional[List[Dict[str, Any]]] = None
