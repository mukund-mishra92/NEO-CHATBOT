"""Query Package
SQL query generation, execution, and validation.

Exports both legacy (Phase 1/2 + Phase 3) and the newer GPT SQL pipeline components.
"""

# Phase 1/2 legacy components
from .extractor import QueryExtractor
from .generator import QueryGenerator

# Phase 3 components
from .semantic_frame import SemanticFrame
from .semantic_frame_extractor import SemanticFrameExtractor
from .semantic_frame_validator import SemanticFrameValidator
from .base_table_resolver import BaseTableResolver
from .sql_template_builder import SQLTemplateBuilder
from .sql_join_injector import SQLJoinInjector
from .executor import QueryExecutor
from .validator import QueryValidator

# GPT SQL pipeline components
from .gpt4_query_generator import GPT4QueryGenerator
from .enhanced_sql_validator import EnhancedSQLValidator
from .result_formatter import ResultFormatter

__all__ = [
    # Phase 1/2
    "QueryExtractor",
    "QueryGenerator",
    # Phase 3
    "SemanticFrame",
    "SemanticFrameExtractor",
    "SemanticFrameValidator",
    "BaseTableResolver",
    "SQLTemplateBuilder",
    "SQLJoinInjector",
    "QueryExecutor",
    "QueryValidator",
    # GPT
    "GPT4QueryGenerator",
    "EnhancedSQLValidator",
    "ResultFormatter",
]

__version__ = "4.0.0"
