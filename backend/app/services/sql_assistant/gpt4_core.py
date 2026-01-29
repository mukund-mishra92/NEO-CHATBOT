"""
SQL Assistant Service - GPT-4 Multi-Layer Architecture (NEW)
Layer 1: GPT-4 Query Generation with full schema
Layer 2: Enhanced Validation
Layer 3: GPT-4 Extended Thinking Retry
Layer 4: Result Formatting
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
from ..chat_history_service import ChatHistoryService
from ...models.schemas import ChatRequest, ChatResponse, ChatbotType
from ...core.config import settings

# Schema
from .schema import SchemaParser, SchemaValidator

# Query - NEW GPT-4 Architecture
from .query import QueryExecutor
from .query.gpt4_query_generator import GPT4QueryGenerator
from .query.enhanced_sql_validator import EnhancedSQLValidator
from .query.result_formatter import ResultFormatter

# Schema Graph
from data.database.schema_graph_loader import SchemaGraphLoader

logger = logging.getLogger(__name__)


class SQLAssistantGPT4Service:
    """
    SQL Assistant – GPT-4 Multi-Layer Architecture
    
    Flow:
    1. GPT-4 generates SQL with full schema context
    2. Enhanced validator checks SQL and provides feedback
    3. If validation fails, retry with GPT-4 extended thinking
    4. Format results in structured tables
    """

    def __init__(self):
        logger.info("🚀 Initializing SQL Assistant with GPT-4 Architecture...")
        
        # Core services
        self.llm_service = LLMService()
        
        # Verify OpenAI is available
        if not self.llm_service.openai_api_key:
            logger.warning("⚠️ OPENAI_API_KEY not found! GPT-4 features will not work.")
            logger.warning("   Please add OPENAI_API_KEY to your .env file")

        # DB config
        self.db_config = {
            "host": settings.DB_HOST,
            "port": settings.DB_PORT,
            "user": settings.DB_USER,
            "password": settings.DB_PASSWORD,
            "database": settings.DB_NAME,
        }

        # Schema components
        self.schema_parser = SchemaParser()
        self.schema_validator = SchemaValidator(self.schema_parser)
        self.schema_graph = SchemaGraphLoader.load()

        # Query executor
        self.query_executor = QueryExecutor(self.db_config)

        # NEW: GPT-4 Multi-Layer Components
        self.query_generator = GPT4QueryGenerator(
            self.llm_service,
            self.schema_parser,
            self.schema_graph
        )
        
        self.validator = EnhancedSQLValidator(
            self.schema_parser,
            self.schema_validator,
            self.schema_graph,
            self.query_executor
        )
        
        self.result_formatter = ResultFormatter()

        # Chat history
        try:
            self.chat_history_service = ChatHistoryService(self.db_config)
        except Exception:
            self.chat_history_service = None

        self.db_available = self.query_executor.test_connection()
        self.available_tables = self.schema_parser.get_available_tables()

        logger.info(
            f"✅ SQL Assistant (GPT-4) initialized | "
            f"DB: {self.db_available} | "
            f"Tables: {len(self.available_tables)} | "
            f"OpenAI: {bool(self.llm_service.openai_api_key)}"
        )

    # =====================================================
    # MAIN ENTRY POINT - NEW GPT-4 ARCHITECTURE
    # =====================================================

    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Process SQL query using GPT-4 multi-layer architecture
        """
        start_time = datetime.now()
        
        try:
            if not self.db_available:
                return self._create_error_response(
                    "Database is not available. Please check connection settings.",
                    chat_request.session_id,
                    chat_request.message,
                )
            
            if not self.llm_service.openai_api_key:
                return self._create_error_response(
                    "OpenAI API key not configured. This service requires GPT-4 access.",
                    chat_request.session_id,
                    chat_request.message,
                )

            question = chat_request.message
            conversation_history = chat_request.conversation_history or []
            
            logger.info(f"🔍 Processing query: {question}")

            # -------------------------------------------------
            # 🎯 LAYERS 1-3: GENERATION, VALIDATION, CONFIDENCE-BASED RETRY
            # -------------------------------------------------
            max_retries = 2  # total attempts = 1 initial + max_retries
            max_attempts = max_retries + 1

            # Agentic verification threshold (e.g., 90 -> 0.90)
            confidence_threshold = (
                settings.AGENTIC_VERIFICATION_THRESHOLD / 100.0
                if settings.AGENTIC_MODE_ENABLED
                else 0.0
            )

            sql_query = ""
            generation_metadata: Dict[str, Any] = {}
            results = None
            validation_details: Dict[str, Any] = {}
            error_feedback = ""
            success = False
            confidence = 0.0
            previous_error: Optional[str] = None

            for attempt in range(1, max_attempts + 1):
                logger.info(
                    f"📝 Layer 1: Generating SQL with GPT-4 (attempt {attempt}/{max_attempts})..."
                )

                sql_query, generation_metadata = self.query_generator.generate_query(
                    question=question,
                    conversation_history=conversation_history,
                    attempt=attempt,
                    previous_error=previous_error,
                )

                logger.info(f"✅ Generated SQL (attempt {attempt}): {sql_query[:100]}...")

                # Layer 2: Validation & execution
                logger.info("🔍 Layer 2: Validating and executing SQL...")
                success, results, error_feedback, validation_details = (
                    self.validator.validate_and_execute(
                        sql_query=sql_query,
                        question=question,
                    )
                )

                if not success:
                    # Validation failed – retry with extended thinking
                    logger.warning(
                        f"⚠️ Validation failed on attempt {attempt}. "
                        f"Will retry with extended thinking if attempts remain."
                    )
                    logger.info(f"Error feedback: {error_feedback[:200]}...")
                    previous_error = error_feedback

                    if attempt >= max_attempts:
                        break
                    continue

                # Validation passed – compute confidence
                confidence = self.result_formatter._calculate_confidence(
                    results,
                    validation_details,
                    generation_metadata,
                )

                logger.info(
                    f"✅ Validation succeeded on attempt {attempt} | "
                    f"confidence={confidence:.2f} | threshold={confidence_threshold:.2f}"
                )

                # If agentic mode is disabled or confidence is high enough, stop here
                if not settings.AGENTIC_MODE_ENABLED or confidence_threshold <= 0.0:
                    break
                if confidence >= confidence_threshold:
                    break

                # Confidence too low – treat as table/column selection issue and retry
                logger.warning(
                    f"🟡 Confidence {confidence:.2%} is below threshold "
                    f"{confidence_threshold:.2%}. Retrying with extended thinking..."
                )

                previous_error = (
                    f"Previous attempt produced low-confidence results (confidence={confidence:.2%}). "
                    "Likely suboptimal table and column selection. Re-evaluate which tables and "
                    "columns best answer the question, prefer the most relevant business tables, "
                    "and correct any join or filter logic issues."
                )

                if attempt >= max_attempts:
                    break

            # If still failed after all attempts, return error
            if not success:
                error_msg = (
                    f"Failed to generate valid SQL query after {generation_metadata.get('attempt', max_attempts)} attempts.\n\n"
                    f"**Last Error:**\n{error_feedback}\n\n"
                    f"**Last SQL Attempt:**\n```sql\n{sql_query}\n```"
                )
                return self._create_error_response(
                    error_msg,
                    chat_request.session_id,
                    chat_request.message,
                )

            # -------------------------------------------------
            # 📊 LAYER 4: RESULT FORMATTING
            # -------------------------------------------------
            logger.info("📊 Layer 4: Formatting results...")

            response_text = self.result_formatter.format_results(
                results=results,
                sql_query=sql_query,
                question=question,
                validation_details=validation_details,
                generation_metadata=generation_metadata,
            )
            
            # Save to chat history
            if self.chat_history_service:
                try:
                    self.chat_history_service.save_message(
                        session_id=chat_request.session_id or str(uuid.uuid4()),
                        message=question,
                        response=response_text,
                        chatbot_type=ChatbotType.SQL_ASSISTANT,
                        metadata={
                            "sql_query": sql_query,
                            "confidence": confidence,
                            "attempts": generation_metadata.get("attempt", 1),
                            "model": generation_metadata.get("model"),
                            "row_count": len(results) if results else 0
                        }
                    )
                except Exception as e:
                    logger.warning(f"Failed to save chat history: {e}")
            
            return ChatResponse(
                response=response_text,
                chatbot_type=ChatbotType.SQL_ASSISTANT,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                sources=[],
                confidence_score=confidence,
                metadata={
                    "sql_query": sql_query,
                    "attempts": generation_metadata.get("attempt", 1),
                    "model": generation_metadata.get("model"),
                    "row_count": len(results) if results else 0,
                    "execution_time": (datetime.now() - start_time).total_seconds()
                }
            )

        except Exception as e:
            logger.error(f"❌ SQL Assistant error: {e}", exc_info=True)
            return self._create_error_response(
                f"An unexpected error occurred: {str(e)}",
                chat_request.session_id,
                chat_request.message,
            )

        finally:
            elapsed = (datetime.now() - start_time).total_seconds()
            logger.info(f"⏱️ Total query processing time: {elapsed:.2f}s")

    # =====================================================
    # HELPERS
    # =====================================================

    def _create_error_response(
        self,
        error_message: str,
        session_id: Optional[str],
        original_message: str,
    ) -> ChatResponse:
        """Create error response"""
        return ChatResponse(
            response=f"❌ **Error:**\n\n{error_message}",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            metadata={"error": True, "original_message": original_message},
        )

    # Backward compatibility (used by UI / startup hooks)
    def get_schema_info(self) -> Dict[str, Any]:
        """Get schema information"""
        return self.schema_parser.get_schema_info()
