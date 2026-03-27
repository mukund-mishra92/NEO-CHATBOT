"""
NEO Chatbot Services package.

Intentionally does NOT import concrete services here to avoid
circular imports and stale paths. Always import services directly, e.g.:

    from app.services.knowledge_base.knowledge_base_service import KnowledgeBaseService
    from app.services.sql_assistant.sql_assistant import SQLAssistantService
    from app.services.diagnostic.diagnostic_service import DiagnosticService
"""

__all__: list[str] = []