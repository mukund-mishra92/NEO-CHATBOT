"""
SQL Assistant Service - Main Coordinator
Orchestrates all SQL assistant components for natural language to SQL conversion
"""

import logging
import uuid
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime

from ..llm_service import LLMService
from ..rlhf_service import RLHFService
from ..chat_history_service import ChatHistoryService
from ...models.schemas import ChatRequest, ChatResponse, ChatbotType, SQLQueryRequest, SQLQueryResponse
from ...core.config import settings

# Import all specialized components
from .schema import SchemaParser, SchemaValidator, SchemaDiscovery
from .query import QueryExtractor, QueryGenerator, QueryExecutor, QueryValidator
from .intent import IntentClassifier, TemporalClassifier
from .context import SessionCache, ConversationContext
from .judge import LLMJudge
from .prompts import PromptBuilder

logger = logging.getLogger(__name__)


class SQLAssistantService:
    """
    Main coordinator for SQL Assistant service
    Orchestrates schema, query, intent, context, judge, and prompt components
    
    Features:
    - Natural language to SQL conversion with context awareness
    - Multi-strategy query generation (direct, with_context, simplified)
    - Intent and temporal classification for smarter routing
    - Schema validation and JOIN path discovery
    - LLM-as-Judge self-refinement for quality assurance
    - Session-based caching and correction tracking
    - RLHF integration for continuous improvement
    """
    
    def __init__(self):
        """Initialize SQL assistant service with all components"""
        # Core services
        self.llm_service = LLMService()
        self.rlhf_service = RLHFService()
        
        # Database configuration
        self.db_config = {
            'host': settings.DB_HOST,
            'port': settings.DB_PORT,
            'user': settings.DB_USER,
            'password': settings.DB_PASSWORD,
            'database': settings.DB_NAME
        }
        
        # Initialize schema components
        self.schema_parser = SchemaParser()
        self.schema_validator = SchemaValidator(self.schema_parser)
        self.schema_discovery = SchemaDiscovery(self.schema_parser, self.llm_service)
        
        # Initialize query components
        self.query_extractor = QueryExtractor()
        self.query_executor = QueryExecutor(self.db_config)
        self.query_validator = QueryValidator()
        
        # Initialize intent components
        self.intent_classifier = IntentClassifier()
        self.temporal_classifier = TemporalClassifier()
        
        # Initialize context components
        self.session_cache = SessionCache()
        self.conversation_context = ConversationContext(self.session_cache)
        
        # Initialize judge and prompt components
        self.llm_judge = LLMJudge(self.llm_service, self.schema_validator)
        self.prompt_builder = PromptBuilder(
            self.schema_discovery,
            self.intent_classifier,
            self.temporal_classifier,
            self.conversation_context
        )
        
        # Initialize query generator with dependencies
        self.query_generator = QueryGenerator(self.llm_service, self.prompt_builder)
        
        # LLM-as-Judge configuration
        self.max_refinement_iterations = 3
        self.judge_confidence_threshold = 0.90
        
        # Initialize vector store for SQL examples
        try:
            from ..vector_store_service import VectorStoreService
            self.vector_store = VectorStoreService()
            logger.info("✅ Vector store available for SQL examples")
        except Exception as e:
            logger.warning(f"⚠️ Vector store unavailable: {e}")
            self.vector_store = None
        
        # Initialize chat history service
        try:
            self.chat_history_service = ChatHistoryService(self.db_config)
            logger.info("✅ Chat history logging enabled")
        except Exception as e:
            logger.warning(f"⚠️ Chat history service unavailable: {e}")
            self.chat_history_service = None
        
        # Test database connection
        self.db_available = self.query_executor.test_connection()
        
        # Cache available tables for validation
        self.available_tables = self.schema_parser.get_available_tables()
        
        logger.info(f"✅ SQL Assistant Service initialized | DB Available: {self.db_available} | Tables: {len(self.available_tables)}")
    
    # ===== PUBLIC API METHODS =====
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Main entry point: Process natural language query with intelligent SQL generation
        
        Workflow:
        1. Extract conversation context and user corrections
        2. Classify intent and temporal scope
        3. Generate SQL with appropriate strategy
        4. Execute and validate results
        5. Retry with different strategy if needed
        6. Apply LLM-as-Judge self-refinement
        
        Args:
            chat_request: User's chat request with conversation_history
            
        Returns:
            Chat response with validated query results
        """
        start_time = datetime.now()
        chat_id = None
        
        try:
            logger.info(f"🔍 Processing SQL query: {chat_request.message[:50]}...")
            
            if not self.db_available:
                return self._create_error_response(
                    "Database connection is not available. Please check your database configuration.",
                    chat_request.session_id,
                    chat_request.message
                )
            
            # Check for negative feedback
            if self._is_negative_feedback(chat_request.message):
                return self._handle_negative_feedback(chat_request)
            
            # Detect user corrections
            is_correction = self._detect_user_correction(chat_request.message, chat_request.session_id)
            if is_correction and chat_request.session_id:
                return self._handle_correction_acknowledgment(chat_request)
            
            # Log chat to database
            if self.chat_history_service:
                try:
                    chat_id = self.chat_history_service.log_chat(
                        session_id=chat_request.session_id or str(uuid.uuid4()),
                        message=chat_request.message,
                        response="",  # Will update after processing
                        chatbot_type=ChatbotType.SQL_ASSISTANT.value,
                        sources=[],
                        confidence_score=0.0,
                        metadata={}
                    )
                except Exception as e:
                    logger.warning(f"⚠️ Failed to log chat: {e}")
            
            # Extract conversation context
            context = self.conversation_context.extract_conversation_context(
                chat_request.conversation_history or [],
                chat_request.session_id
            )
            
            # Classify intent and temporal scope
            intent_info = self.intent_classifier.classify_query_intent(chat_request.message)
            temporal_info = self.temporal_classifier.classify_temporal_scope(chat_request.message)
            
            logger.info(f"📊 Intent: {intent_info.get('intent', 'unknown')} | Temporal: {temporal_info['scope']}")
            
            # Try multiple strategies
            strategies = ['direct', 'with_context', 'simplified']
            best_response = None
            best_confidence = 0.0
            best_sql = None
            best_results = []
            
            for strategy in strategies:
                logger.info(f"🔄 Trying strategy: {strategy}")
                
                # Generate SQL with just the required parameters
                sql_result = self.query_generator.generate_sql_with_strategy(
                    question=chat_request.message,
                    strategy=strategy,
                    context=context
                )
                
                if not sql_result or 'sql' not in sql_result:
                    continue
                
                sql_query = sql_result['sql']
                
                # Validate SQL against schema
                tables_valid, invalid_tables = self.schema_validator.validate_sql_tables(sql_query)
                if not tables_valid:
                    logger.warning(f"⚠️ Invalid tables in SQL: {invalid_tables}")
                    continue
                
                columns_valid, invalid_columns = self.schema_validator.validate_sql_columns(sql_query)
                if not columns_valid:
                    logger.warning(f"⚠️ Invalid columns in SQL: {invalid_columns}")
                    continue
                
                # Execute query
                logger.info(f"🔍 Executing SQL: {sql_query[:200]}..." if len(sql_query) > 200 else f"🔍 Executing SQL: {sql_query}")
                results, error = self.query_executor.execute_query_safe(sql_query)
                if error:
                    logger.warning(f"⚠️ Query execution failed: {error}")
                    continue
                
                # Auto-correction: If 0 results and no error, try case-insensitive version
                if len(results) == 0 and not error and "WHERE" in sql_query.upper():
                    logger.info(f"🔧 0 results - attempting auto-correction for case sensitivity...")
                    corrected_sql = self._auto_correct_query(sql_query)
                    if corrected_sql != sql_query:
                        logger.info(f"🔄 Retrying with corrected SQL: {corrected_sql[:200]}...")
                        results, error = self.query_executor.execute_query_safe(corrected_sql)
                        if not error and len(results) > 0:
                            logger.info(f"✅ Auto-correction successful! Found {len(results)} rows")
                            sql_query = corrected_sql  # Use corrected query
                
                # Build execution result dict
                execution_result = {
                    'success': True,
                    'results': results,
                    'row_count': len(results)
                }
                
                # Validate results - returns tuple (confidence, message)
                confidence, validation_message = self.query_validator.validate_results(
                    results=execution_result['results'],
                    question=chat_request.message,
                    sql_query=sql_query
                )
                
                logger.info(f"✅ Strategy {strategy} confidence: {confidence:.2f} - {validation_message}")
                
                if confidence > best_confidence:
                    best_confidence = confidence
                    best_sql = sql_query
                    best_results = execution_result['results']
                    best_response = self.query_validator.format_results_with_confidence(
                        results=execution_result['results'],
                        sql_query=sql_query,
                        question=chat_request.message,
                        confidence=confidence,
                        validation_msg=validation_message
                    )
                
                # If confidence is high enough, stop trying strategies
                if confidence >= 0.85:
                    break
            
            # If no successful result, return helpful error
            if not best_response:
                return self._create_error_response(
                    "I couldn't generate a valid SQL query for your question. Please rephrase or provide more details.",
                    chat_request.session_id,
                    chat_request.message
                )
            
            # Apply LLM-as-Judge refinement if confidence is medium
            if 0.60 <= best_confidence < 0.90:
                refined_response = self._apply_judge_refinement(
                    chat_request.message,
                    best_response,
                    chat_request.conversation_history or [],
                    chat_request.session_id
                )
                if refined_response and refined_response.confidence_score > best_confidence:
                    best_response = refined_response
                    best_confidence = refined_response.confidence_score
            
            # Cache successful query
            if chat_request.session_id and best_sql:
                self.session_cache.store_successful_query(
                    session_id=chat_request.session_id,
                    question=chat_request.message,
                    sql=best_sql,
                    results_count=len(best_results),
                    sample_data=best_results[:3] if best_results else None
                )
            
            # Update chat history with final response
            if self.chat_history_service and chat_id:
                try:
                    self.chat_history_service.update_chat(
                        chat_id=chat_id,
                        response=best_response if isinstance(best_response, str) else best_response.response,
                        confidence_score=best_confidence,
                        metadata={'strategies_tried': strategies}
                    )
                except Exception as e:
                    logger.warning(f"⚠️ Failed to update chat: {e}")
            
            # Return formatted response
            if isinstance(best_response, ChatResponse):
                return best_response
            else:
                return ChatResponse(
                    response=best_response,
                    chatbot_type=ChatbotType.SQL_ASSISTANT,
                    session_id=chat_request.session_id or str(uuid.uuid4()),
                    sources=[],
                    confidence_score=best_confidence
                )
        
        except Exception as e:
            logger.error(f"❌ Error processing query: {e}", exc_info=True)
            return self._create_error_response(
                f"An error occurred while processing your query: {str(e)}",
                chat_request.session_id,
                chat_request.message
            )
        finally:
            duration = (datetime.now() - start_time).total_seconds()
            logger.info(f"⏱️ Query processed in {duration:.2f}s")
    
    # ===== HELPER METHODS =====
    
    def _is_negative_feedback(self, message: str) -> bool:
        """Check if message is pure negative feedback without details"""
        negative_words = {'no', 'wrong', 'incorrect', 'nope', 'not right', 'bad', 'fail'}
        message_lower = message.lower().strip()
        return message_lower in negative_words or len(message_lower.split()) <= 2
    
    def _handle_negative_feedback(self, chat_request: ChatRequest) -> ChatResponse:
        """Handle pure negative feedback by asking for clarification"""
        return ChatResponse(
            response="""I understand the previous result wasn't correct. To help you better, please clarify:

1. **What was wrong?** (e.g., "wrong table", "wrong columns", "no data")
2. **What are you looking for?** (e.g., "I need bot charging data", "show me alternative table")
3. **Any hints?** (e.g., "the table is empty", "check bot_master table")

**Example responses:**
- "The dashboard_log_bot_charging table is empty, find data in another table"
- "I need to find which bots are at charging stations 37 and 38"
- "Use bot_master table instead"

I'm here to help - just tell me what you need! 💡""",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=chat_request.session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            metadata={
                'type': 'clarification_request',
                'reason': 'negative_feedback_without_details'
            }
        )
    
    def _detect_user_correction(self, message: str, session_id: Optional[str]) -> bool:
        """Detect if user is providing a correction"""
        correction_keywords = [
            'empty', 'no data', 'wrong table', 'wrong column', 'incorrect table',
            'use instead', 'try table', 'check table', 'not this', 'alternative'
        ]
        message_lower = message.lower()
        return any(keyword in message_lower for keyword in correction_keywords)
    
    def _handle_correction_acknowledgment(self, chat_request: ChatRequest) -> ChatResponse:
        """Acknowledge user corrections and ask them to restate question"""
        corrections_data = self.session_cache.get_session_corrections(chat_request.session_id)
        
        acknowledgment = "✅ **Got it! I've noted your corrections:**\n\n"
        
        if corrections_data.get('failed_tables'):
            acknowledgment += "**Tables I will NOT use:**\n"
            for failed in corrections_data['failed_tables'][-3:]:
                acknowledgment += f"- ❌ `{failed['table']}` - {failed['reason']}\n"
            acknowledgment += "\n"
        
        if corrections_data.get('corrections'):
            acknowledgment += "**Column/field corrections:**\n"
            for corr in corrections_data['corrections'][-3:]:
                acknowledgment += f"- Use `{corr['correct']}` instead of `{corr['wrong']}`\n"
            acknowledgment += "\n"
        
        acknowledgment += "📝 **What I'll do now:**\n"
        acknowledgment += "- Use alternative tables from the schema\n"
        acknowledgment += "- Apply your corrections to all future queries\n"
        acknowledgment += "- Find the data you need using correct tables\n\n"
        acknowledgment += "🔄 **Please restate your question**, and I'll generate a corrected query."
        
        return ChatResponse(
            response=acknowledgment,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=chat_request.session_id,
            sources=[],
            confidence_score=0.0,
            metadata={'type': 'correction_acknowledgment'}
        )
    
    def _apply_judge_refinement(
        self,
        question: str,
        initial_response: Any,
        conversation_history: List[Dict[str, Any]],
        session_id: Optional[str]
    ) -> Optional[ChatResponse]:
        """Apply LLM-as-Judge refinement to improve query quality"""
        try:
            logger.info("⚖️ Applying LLM-as-Judge refinement...")
            
            # Extract SQL from response
            sql_query = self.query_extractor.extract_sql_query(
                initial_response if isinstance(initial_response, str) else initial_response.response
            )
            
            if not sql_query:
                return None
            
            # Judge the query
            judgment = self.llm_judge.judge_query_quality(
                sql_query=sql_query,
                question=question,
                conversation_history=conversation_history,
                session_id=session_id
            )
            
            if judgment and judgment['confidence'] > 0.90:
                logger.info(f"✨ Judge approved query with confidence {judgment['confidence']:.2f}")
                if 'improved_sql' in judgment and judgment['improved_sql'] != sql_query:
                    # Re-execute improved query
                    execution_result = self.query_executor.execute_query_safe(judgment['improved_sql'])
                    if execution_result['success']:
                        validation = self.query_validator.validate_results(
                            results=execution_result['results'],
                            row_count=execution_result['row_count'],
                            sql_query=judgment['improved_sql'],
                            question=question
                        )
                        
                        formatted_response = self.query_validator.format_results_with_confidence(
                            execution_result['results'],
                            execution_result['row_count'],
                            judgment['improved_sql'],
                            validation['confidence'],
                            validation.get('warnings', [])
                        )
                        
                        return ChatResponse(
                            response=formatted_response,
                            chatbot_type=ChatbotType.SQL_ASSISTANT,
                            session_id=session_id or str(uuid.uuid4()),
                            sources=[],
                            confidence_score=validation['confidence'],
                            metadata={'judge_refined': True}
                        )
            
            return None
        
        except Exception as e:
            logger.error(f"❌ Error in judge refinement: {e}")
            return None
    
    def _create_error_response(self, error_message: str, session_id: Optional[str], original_message: str) -> ChatResponse:
        """Create standardized error response"""
        return ChatResponse(
            response=error_message,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            metadata={'error': True, 'original_message': original_message}
        )
    
    # ===== BACKWARD COMPATIBILITY DELEGATION METHODS =====
    # These methods delegate to the new modular components
    
    def get_available_tables(self) -> set:
        """Get set of all available tables"""
        return self.schema_parser.get_available_tables()
    
    def get_table_columns(self, table_name: str) -> List[str]:
        """Get columns for a specific table"""
        return self.schema_parser.get_table_columns(table_name)
    
    def get_full_table_schema(self, table_name: str) -> str:
        """Get full schema for a table"""
        return self.schema_parser.get_full_table_schema(table_name)
    
    def validate_sql_tables(self, sql_query: str) -> Tuple[bool, List[str]]:
        """Validate tables in SQL query"""
        return self.schema_validator.validate_sql_tables(sql_query)
    
    def validate_sql_columns(self, sql_query: str) -> Tuple[bool, List[str]]:
        """Validate columns in SQL query"""
        return self.schema_validator.validate_sql_columns(sql_query)
    
    def execute_query_safe(self, sql_query: str) -> Dict[str, Any]:
        """Execute SQL query safely"""
        return self.query_executor.execute_query_safe(sql_query)
    
    def extract_sql_query(self, text: str) -> Optional[str]:
        """Extract SQL query from text"""
        return self.query_extractor.extract_sql_query(text)
    
    def classify_query_intent(self, query: str) -> Dict[str, Any]:
        """Classify query intent"""
        return self.intent_classifier.classify_query_intent(query)
    
    def classify_temporal_scope(self, query: str) -> Dict[str, Any]:
        """Classify temporal scope of query"""
        return self.temporal_classifier.classify_temporal_scope(query)
    
    def get_relevant_schema(self, question: str, conversation_history: List[Dict[str, Any]] = None) -> str:
        """Get relevant schema for question"""
        return self.schema_discovery.get_relevant_schema(question, conversation_history)
    
    def get_join_paths(self, tables: List[str]) -> List[Dict[str, Any]]:
        """Get JOIN paths between tables"""
        return self.schema_discovery.get_join_paths(tables)
    
    def get_schema_info(self) -> Dict[str, Any]:
        """Get comprehensive schema information"""
        return self.schema_parser.get_schema_info()
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get SQL Assistant statistics"""
        return {
            "total_tables": len(self.available_tables),
            "db_available": self.db_available,
            "cache_enabled": True,
            "vector_store_available": self.vector_store is not None,
            "chat_history_available": self.chat_history_service is not None
        }
    
    def get_schema_info(self) -> Dict[str, Any]:
        """Get comprehensive schema information"""
        return self.schema_parser.get_schema_info()
    
    def _auto_correct_query(self, sql_query: str) -> str:
        """
        Auto-correct common SQL issues like case sensitivity in WHERE clauses
        
        Args:
            sql_query: Original SQL query
            
        Returns:
            Corrected SQL query
        """
        import re
        
        corrected = sql_query
        
        # Pattern to find WHERE conditions with string literals
        # Matches: WHERE column = 'value' or WHERE column IN ('value1', 'value2')
        where_pattern = r"(WHERE\s+\w+\s*=\s*'[^']+')|(WHERE\s+\w+\s+IN\s*\([^)]+\))"
        
        # Convert string comparisons to UPPER() for case-insensitive matching
        def replace_where(match):
            clause = match.group(0)
            # Extract column name and value
            if ' = ' in clause:
                parts = clause.split(' = ')
                if len(parts) == 2:
                    col_part = parts[0].replace('WHERE ', '').strip()
                    val_part = parts[1].strip()
                    return f"WHERE UPPER({col_part}) = UPPER({val_part})"
            return clause
        
        # Apply correction
        corrected = re.sub(where_pattern, replace_where, corrected, flags=re.IGNORECASE)
        
        if corrected != sql_query:
            logger.info(f"🔧 Auto-corrected query for case-insensitive matching")
        
        return corrected
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get SQL assistant statistics"""
        return {
            'total_tables': len(self.available_tables),
            'database_available': self.db_available,
            'cache_enabled': True,
            'judge_enabled': True,
            'vector_store_available': self.vector_store is not None,
            'chat_history_available': self.chat_history_service is not None
        }
