"""
SQL Assistant Service - Main Coordinator (PHASE 3)
Semantic-Frame–driven SQL generation with deterministic JOINs
"""

import logging
import uuid
from typing import Dict, Any, Optional
from datetime import datetime
import sys
from pathlib import Path

# Ensure project root (where `data/` lives) is on sys.path
PROJECT_ROOT = Path(__file__).resolve().parents[4]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from ..llm_service import LLMService
from ..rlhf_service import RLHFService
from ..chat_history_service import ChatHistoryService
from ...models.schemas import ChatRequest, ChatResponse, ChatbotType
from ...core.config import settings

# Schema
from .schema import SchemaParser, SchemaValidator

# Query
from .query import QueryExecutor, QueryValidator
from .query.semantic_frame_extractor import SemanticFrameExtractor
from .query.sql_template_builder import SQLTemplateBuilder
from .query.semantic_frame_validator import SemanticFrameValidator
from .query.base_table_resolver import BaseTableResolver

# Intent & Context
from .intent import IntentClassifier, TemporalClassifier
from .context import SessionCache, ConversationContext

# Schema Graph
from data.database.schema_graph_loader import SchemaGraphLoader

logger = logging.getLogger(__name__)


class SQLAssistantService:
    """
    SQL Assistant – Phase 3
    Semantic Frame → Schema Graph → SQL Builder → Execution
    """

    def __init__(self):
        # Core services
        self.llm_service = LLMService()
        self.rlhf_service = RLHFService()

        # DB config
        self.db_config = {
            "host": settings.DB_HOST,
            "port": settings.DB_PORT,
            "user": settings.DB_USER,
            "password": settings.DB_PASSWORD,
            "database": settings.DB_NAME,
        }

        # Schema
        self.schema_parser = SchemaParser()
        self.schema_validator = SchemaValidator(self.schema_parser)

        # Intent & context
        self.intent_classifier = IntentClassifier()
        self.temporal_classifier = TemporalClassifier()
        self.session_cache = SessionCache()
        self.conversation_context = ConversationContext(self.session_cache)

        # Semantic frame & SQL builder
        self.semantic_extractor = SemanticFrameExtractor(self.llm_service)
        self.sql_builder = SQLTemplateBuilder()

        # Schema graph
        self.schema_graph = SchemaGraphLoader.load()

        # Execution & validation
        self.query_executor = QueryExecutor(self.db_config)
        self.query_validator = QueryValidator()
        self.frame_validator = SemanticFrameValidator(self.schema_parser)
        self.base_table_resolver = BaseTableResolver(
            self.schema_parser,
            self.schema_graph
        )

        # Chat history
        try:
            self.chat_history_service = ChatHistoryService(self.db_config)
        except Exception:
            self.chat_history_service = None

        self.db_available = self.query_executor.test_connection()
        self.available_tables = self.schema_parser.get_available_tables()

        logger.info(
            f"✅ SQL Assistant (Phase 3) initialized | DB: {self.db_available} | Tables: {len(self.available_tables)}"
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
                    chat_request.message,
                )

            # Context & intent (still useful for prompts / future routing)
            context = self.conversation_context.extract_conversation_context(
                chat_request.conversation_history or [],
                chat_request.session_id,
            )

            intent_info = self.intent_classifier.classify_query_intent(
                chat_request.message
            )
            temporal_info = self.temporal_classifier.classify_temporal_scope(
                chat_request.message
            )

            # -------------------------------------------------
            # 🔥 PHASE 3 CORE FLOW
            # -------------------------------------------------

            schema_summary = self.schema_parser.get_schema_summary()

            # 1️⃣ Semantic Frame Extraction
            frame = self.semantic_extractor.extract(
                question=chat_request.message,
                schema_summary=schema_summary,
            )

            # 🔥 NEW STEP
            resolved_base = self.base_table_resolver.resolve(
                frame,
                chat_request.message
            )

            

            logger.info(f"🧠 Semantic Frame: {frame.__dict__}")

            frame = self.semantic_extractor.extract(
                question=chat_request.message,
                schema_summary=schema_summary,
            )
            frame = self.frame_validator.validate_and_repair(frame)


            # 2️⃣ Resolve JOIN paths (multi-level supported)
            join_path_map = {}

            for dim_table in frame.dimensions:
                path = self.schema_graph.get_join_path(
                    frame.base_table, dim_table
                )
                if not path:
                    raise ValueError(
                        f"No join path from {frame.base_table} to {dim_table}"
                    )
                join_path_map[dim_table] = path

            # 3️⃣ Deterministic SQL build
            final_sql = self.sql_builder.build(
                frame=frame,
                join_path_map=join_path_map,
                schema_graph=self.schema_graph,
            )

            logger.info(f"🧾 Final SQL: {final_sql}")

            # 4️⃣ Validate SQL
            tables_valid, _ = self.schema_validator.validate_sql_tables(final_sql)
            columns_valid, _ = self.schema_validator.validate_sql_columns(final_sql)

            if not tables_valid or not columns_valid:
                raise ValueError("Generated SQL failed schema validation")

            # 5️⃣ Execute
            results, error = self.query_executor.execute_query_safe(final_sql)
            if error:
                raise RuntimeError(error)

            # 6️⃣ Validate results & confidence
            confidence, validation_msg = self.query_validator.validate_results(
                results=results,
                question=chat_request.message,
                sql_query=final_sql,
            )

            response_text = self.query_validator.format_results_with_confidence(
                results=results,
                sql_query=final_sql,
                question=chat_request.message,
                confidence=confidence,
                validation_msg=validation_msg,
            )

            return ChatResponse(
                response=response_text,
                chatbot_type=ChatbotType.SQL_ASSISTANT,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=[],
                confidence_score=confidence,
            )

        except Exception as e:
            logger.error(f"❌ SQL Assistant error: {e}", exc_info=True)
            return self._create_error_response(
                str(e),
                chat_request.session_id,
                chat_request.message,
            )

        finally:
            logger.info(
                f"⏱️ Query processed in {(datetime.now() - start_time).total_seconds():.2f}s"
            )

    # =====================================================
    # HELPERS
    # =====================================================

    def _create_error_response(
        self,
        error_message: str,
        session_id: Optional[str],
        original_message: str,
    ) -> ChatResponse:
        return ChatResponse(
            response=error_message,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            metadata={"error": True, "original_message": original_message},
        )

    # Backward compatibility (used by UI / startup hooks)
    def get_schema_info(self) -> Dict[str, Any]:
        return self.schema_parser.get_schema_info()
