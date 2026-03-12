"""
Service package marker.

Do NOT import concrete services here to avoid circular imports and
ModuleNotFoundError when paths change.

Always import services directly from their modules, e.g.:

    from app.services.knowledge_base.knowledge_base_service import KnowledgeBaseService
    from app.services.sql_assistant.sql_assistant import SQLAssistantService
    from app.services.diagnostic.diagnostic_service import DiagnosticService
"""

__all__ = []