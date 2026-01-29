"""
SQL Assistant Package
Natural language to SQL query generation and execution
Modular architecture for maintainability and extensibility

Version: 4.0.0 (GPT-4 Multi-Layer Architecture)
"""

from .phase_1_core import SQLAssistantService
from .gpt4_core import SQLAssistantGPT4Service  # NEW: GPT-4 Architecture

__version__ = '4.0.0'

__all__ = [
    'SQLAssistantService',  # Legacy Phase 3 service
    'SQLAssistantGPT4Service'  # NEW: GPT-4 service (recommended)
]

