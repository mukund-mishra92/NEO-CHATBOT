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
    SEMI_AUTO_DIAGNOSTIC = "semi_auto_diagnostic"
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
    user_id: Optional[str] = Field(default=None, description="User email for chat history tracking")
    conversation_history: Optional[List[ChatMessage]] = []
    context: Optional[Dict[str, Any]] = None


class KPISelectionRequest(BaseModel):
    """Request when user selects a KPI from disambiguation options."""
    kpi_id: str = Field(..., description="Selected KPI id, or 'none' for SQL generator fallback")
    original_question: str = Field(..., description="The original user question")
    session_id: Optional[str] = None
    user_id: Optional[str] = None


class SourceDocument(BaseModel):
    """Document source for RAG"""
    document_name: str
    content_snippet: str
    relevance_score: float
    page_number: Optional[int] = None
    document_type: str  # pdf, docx, code, proposal


class ResponseSection(BaseModel):
    """A structured section in an answer (Phase 8)."""
    heading: str
    content: str
    figures: Optional[List[int]] = []  # Figure numbers referenced in this section


class StructuredResponse(BaseModel):
    """Structured answer format (Phase 8) — rich alternative to flat response string."""
    summary: str = ""
    sections: List[ResponseSection] = []
    figures: Optional[List[Dict[str, Any]]] = []  # {figure_number, image_path, caption, ...}
    citations: Optional[List[Dict[str, str]]] = []  # {document, page, snippet}


class ChatResponse(BaseModel):
    """Response from chatbot"""
    response: str
    chatbot_type: ChatbotType
    session_id: Optional[str] = None
    sources: Optional[List[SourceDocument]] = []
    confidence_score: Optional[float] = None
    suggested_actions: Optional[List[str]] = []
    sql_query: Optional[str] = None  # For SQL assistant responses
    query_results: Optional[List[Dict[str, Any]]] = None  # For SQL results
    metadata: Optional[Dict[str, Any]] = None  # Agent metadata (format_decision, etc.)
    images: Optional[List[Dict[str, Any]]] = []  # Multimodal: images to display
    structured_response: Optional[StructuredResponse] = None  # Phase 8: structured answer
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
