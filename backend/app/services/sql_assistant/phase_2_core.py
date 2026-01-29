"""
SQL Assistant Service - Main Coordinator
Orchestrates all SQL assistant components for natural language to SQL conversion
"""

import logging
import uuid
from typing import List, Dict, Any, Optional, Tuple
import sys
from pathlib import Path
from datetime import datetime

# Ensure project root (where `data/` lives) is on sys.path
PROJECT_ROOT = Path(__file__).resolve().parents[4]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from ..llm_service import LLMService
from ..rlhf_service import RLHFService
from ..chat_history_service import ChatHistoryService
from ...models.schemas import ChatRequest, ChatResponse, ChatbotType
from ...core.config import settings

# Schema & Query Components
from .schema import SchemaParser, SchemaValidator, SchemaDiscovery
from .query import QueryExtractor, QueryGenerator, QueryExecutor, QueryValidator
from .query.sql_join_injector import SQLJoinInjector

# Intent & Context
from .intent import IntentClassifier, TemporalClassifier
from .context import SessionCache, ConversationContext

# Judge & Prompt
from .judge import LLMJudge
from .prompts import PromptBuilder

# 🔥 Schema Graph
from data.database.schema_graph_loader import SchemaGraphLoader

logger = logging.getLogger(__name__)

# ... imports unchanged ...

class SQLAssistantService:
    """
    Main coordinator for SQL Assistant service
    """

    def __init__(self):
        # --- unchanged init ---
        self.llm_service = LLMService()
        self.rlhf_service = RLHFService()

        self.db_config = {
            'host': settings.DB_HOST,
            'port': settings.DB_PORT,
            'user': settings.DB_USER,
            'password': settings.DB_PASSWORD,
            'database': settings.DB_NAME
        }

        self.schema_parser = SchemaParser()
        self.schema_validator = SchemaValidator(self.schema_parser)
        self.schema_discovery = SchemaDiscovery(self.schema_parser, self.llm_service)

        self.intent_classifier = IntentClassifier()
        self.temporal_classifier = TemporalClassifier()

        self.session_cache = SessionCache()
        self.conversation_context = ConversationContext(self.session_cache)

        self.prompt_builder = PromptBuilder(
            self.schema_discovery,
            self.intent_classifier,
            self.temporal_classifier,
            self.conversation_context
        )

        self.query_extractor = QueryExtractor()
        self.query_generator = QueryGenerator(self.llm_service, self.prompt_builder)
        self.query_executor = QueryExecutor(self.db_config)
        self.query_validator = QueryValidator()
        self.llm_judge = LLMJudge(self.llm_service, self.schema_validator)

        self.schema_graph = SchemaGraphLoader.load()
        self.sql_join_injector = SQLJoinInjector()

        try:
            self.chat_history_service = ChatHistoryService(self.db_config)
        except Exception:
            self.chat_history_service = None

        self.db_available = self.query_executor.test_connection()
        self.available_tables = self.schema_parser.get_available_tables()

        logger.info(
            f"✅ SQL Assistant initialized | DB: {self.db_available} | Tables: {len(self.available_tables)}"
        )

    # =====================================================
    # MAIN ENTRY POINT
    # =====================================================

    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        start_time = datetime.now()

        try:
            if not self.db_available:
                return self._create_error_response(
                    "Database is not available.",
                    chat_request.session_id,
                    chat_request.message
                )

            context = self.conversation_context.extract_conversation_context(
                chat_request.conversation_history or [],
                chat_request.session_id
            )

            strategies = ['direct', 'with_context', 'simplified']

            best_response = None
            best_confidence = 0.0

            for strategy in strategies:
                sql_result = self.query_generator.generate_sql_with_strategy(
                    question=chat_request.message,
                    strategy=strategy,
                    context=context
                )

                if not sql_result or 'sql' not in sql_result:
                    continue

                base_sql = sql_result['sql']

                # 🔥 FIXED TABLE EXTRACTION
                tables = self._extract_tables_from_sql(base_sql)
                final_sql = base_sql

                if len(tables) == 2:
                    base_table, target_table = tables
                #join_path = schema_graph.get_join_path_for_tables(tables)
                    join_path = self.schema_graph.get_join_path(base_table, target_table)

                    if not join_path:
                        continue

                    final_sql = self.sql_join_injector.inject(
                        base_sql=base_sql,
                        join_path=join_path,
                        schema_graph=self.schema_graph
                    )

                tables_valid, _ = self.schema_validator.validate_sql_tables(final_sql)
                columns_valid, _ = self.schema_validator.validate_sql_columns(final_sql)

                if not tables_valid or not columns_valid:
                    continue

                results, error = self.query_executor.execute_query_safe(final_sql)
                if error:
                    continue

                confidence, validation_msg = self.query_validator.validate_results(
                    results=results,
                    question=chat_request.message,
                    sql_query=final_sql
                )

                if confidence > best_confidence:
                    best_confidence = confidence
                    best_response = self.query_validator.format_results_with_confidence(
                        results=results,
                        sql_query=final_sql,
                        question=chat_request.message,
                        confidence=confidence,
                        validation_msg=validation_msg
                    )

                if confidence >= 0.85:
                    break

            if not best_response:
                return self._create_error_response(
                    "No valid SQL could be generated.",
                    chat_request.session_id,
                    chat_request.message
                )

            return ChatResponse(
                response=best_response,
                chatbot_type=ChatbotType.SQL_ASSISTANT,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=[],
                confidence_score=best_confidence
            )

        except Exception as e:
            logger.error(f"❌ SQL Assistant error: {e}", exc_info=True)
            return self._create_error_response(
                str(e),
                chat_request.session_id,
                chat_request.message
            )

        finally:
            logger.info(
                f"⏱️ Query processed in {(datetime.now() - start_time).total_seconds():.2f}s"
            )

    # =====================================================
    # HELPERS
    # =====================================================

    def _extract_tables_from_sql(self, sql: str) -> List[str]:
        import re
        tables = []

        from_match = re.search(r"\bFROM\s+([a-zA-Z0-9_]+)", sql, re.IGNORECASE)
        if from_match:
            tables.append(from_match.group(1))

        join_matches = re.findall(r"\bJOIN\s+([a-zA-Z0-9_]+)", sql, re.IGNORECASE)
        tables.extend(join_matches)

        return list(dict.fromkeys(tables))

    def _create_error_response(self, error_message: str, session_id: Optional[str], original_message: str) -> ChatResponse:
        return ChatResponse(
            response=error_message,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            metadata={'error': True, 'original_message': original_message}
        )

    def get_schema_info(self) -> Dict[str, Any]:
        return self.schema_parser.get_schema_info()