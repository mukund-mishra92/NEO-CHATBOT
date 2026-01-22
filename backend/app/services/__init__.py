"""
NEO Chatbot Services
Core business logic and AI services
"""

from .llm_service import LLMService
from .vector_store_service import VectorStoreService
from .knowledge_base_service import KnowledgeBaseService
from .diagnostic_service import DiagnosticService
from .agentic_service import AgenticService, get_agentic_service

# Support both old and new import paths for refactored services
# Diagnostic Support Service
# Old: from app.services.diagnostic_support_service import DiagnosticSupportService
# New: from app.services.diagnostic import DiagnosticSupportService
from .diagnostic import DiagnosticSupportService

# SQL Assistant Service  
# Old: from app.services.sql_assistant_service import SQLAssistantService
# New: from app.services.sql_assistant import SQLAssistantService
from .sql_assistant import SQLAssistantService

__all__ = [
    'LLMService',
    'VectorStoreService',
    'KnowledgeBaseService',
    'SQLAssistantService',
    'DiagnosticService',
    'DiagnosticSupportService',  # Backward compatibility
    'AgenticService',
    'get_agentic_service'
]

