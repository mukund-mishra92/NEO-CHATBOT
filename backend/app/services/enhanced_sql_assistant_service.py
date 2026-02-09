"""
Enhanced SQL Assistant Service - Integrated with NL-to-SQL Generator
Uses CSV-driven schema retrieval with TF-IDF for first-level SQL generation,
then falls back to LLM-based generation for complex queries.
"""

import logging
import uuid
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime
import os
import json
import pymysql
import pandas as pd
import re

from .llm_service import LLMService
from .rlhf_service import RLHFService
from .chat_history_service import ChatHistoryService
from .nl_to_sql_generator import NLToSQLGenerator, is_read_only_sql
from ..models.schemas import ChatRequest, ChatResponse, ChatbotType, SQLQueryRequest, SQLQueryResponse
from app.core.config import settings
from ..utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)


class EnhancedSQLAssistantService:
    """
    Enhanced SQL Assistant Service with two-tier query generation:
    
    Tier 1 (Fast & Deterministic): 
        - Uses NLToSQLGenerator with CSV-based schema retrieval
        - TF-IDF matching for relevant tables
        - Structured JSON output with strict schema
        - Best for straightforward queries
    
    Tier 2 (Flexible & Contextual):
        - Falls back to LLM-based generation for complex queries
        - Uses conversation context and user corrections
        - Handles ambiguous queries with clarification
        - Self-improving with RLHF feedback
    
    Features:
    - Automatic tier selection based on query complexity
    - Validates results with confidence scoring
    - Retries with different strategies if needed
    - Returns formatted results only when confident
    - Session-based query caching and corrections
    """
    
    def __init__(self):
        """Initialize enhanced SQL assistant service"""
        self.llm_service = LLMService()
        self.rlhf_service = RLHFService()
        self.session_manager = get_session_manager()
        
        # Database configuration
        self.db_config = {
            'host': settings.DB_HOST,
            'port': settings.DB_PORT,
            'user': settings.DB_USER,
            'password': settings.DB_PASSWORD,
            'database': settings.DB_NAME
        }
        
        # Initialize Tier 1: NL-to-SQL Generator
        self.nl_to_sql_generator = None
        self._initialize_nl_to_sql_generator()
        
        # Initialize supporting services
        self._initialize_supporting_services()
        
        # Configuration
        self.max_refinement_iterations = 3
        self.judge_confidence_threshold = 0.90
        self.tier1_confidence_threshold = 0.75  # Switch to Tier 2 if below this
        
        # Session caches
        self.session_query_cache: Dict[str, List[Dict[str, Any]]] = {}
        self.session_corrections: Dict[str, Dict[str, Any]] = {}
        
        # Test database connection and load tables
        self.db_available = self._test_db_connection()
        self.available_tables = self._get_available_tables()
        
        logger.info(f"✅ Enhanced SQL Assistant initialized with {len(self.available_tables)} tables")
    
    def _initialize_nl_to_sql_generator(self):
        """Initialize the CSV-based NL-to-SQL generator (Tier 1)"""
        try:
            # Look for schema CSV in multiple locations
            schema_csv_paths = [
                settings.DATA_DIR / "database" / "Table_information.csv",
                settings.DATA_DIR / "database" / "schema.csv",
                "data/database/Table_information.csv",
                "Table_information.csv"
            ]
            
            schema_csv_path = None
            for path in schema_csv_paths:
                if os.path.exists(str(path)):
                    schema_csv_path = str(path)
                    break
            
            if not schema_csv_path:
                logger.warning("⚠️ Schema CSV not found. Tier 1 generator disabled.")
                logger.warning(f"   Searched: {[str(p) for p in schema_csv_paths]}")
                return
            
            # Initialize NLToSQLGenerator
            self.nl_to_sql_generator = NLToSQLGenerator(
                api_key=settings.OPENAI_API_KEY,
                model=settings.OPENAI_MODEL,
                schema_csv_path=schema_csv_path
            )
            logger.info(f"✅ Tier 1 NL-to-SQL Generator initialized with schema: {schema_csv_path}")
            
        except Exception as e:
            logger.error(f"❌ Failed to initialize NL-to-SQL Generator: {e}")
            self.nl_to_sql_generator = None
    
    def _initialize_supporting_services(self):
        """Initialize vector store, chat history, and classification services"""
        # Vector store for SQL examples
        try:
            from .vector_store_service import VectorStoreService
            self.vector_store = VectorStoreService()
            logger.info("✅ Vector store available")
        except Exception as e:
            logger.warning(f"⚠️ Vector store unavailable: {e}")
            self.vector_store = None
        
        # Chat history service
        try:
            self.chat_history_service = ChatHistoryService(self.db_config)
            logger.info("✅ Chat history logging enabled")
        except Exception as e:
            logger.warning(f"⚠️ Chat history unavailable: {e}")
            self.chat_history_service = None
        
        # Query classification service
        try:
            from .query_classification_service import QueryClassificationService
            classification_storage = settings.DATA_DIR / "classification"
            self.classification_service = QueryClassificationService(classification_storage)
            logger.info("✅ Query classification enabled")
        except Exception as e:
            logger.warning(f"⚠️ Query classification unavailable: {e}")
            self.classification_service = None
    
    def _test_db_connection(self) -> bool:
        """Test database connectivity"""
        try:
            conn = pymysql.connect(**self.db_config, connect_timeout=5)
            conn.close()
            logger.info("✅ Database connection successful")
            return True
        except Exception as e:
            logger.error(f"❌ Database connection failed: {e}")
            return False
    
    def _get_available_tables(self) -> List[str]:
        """Get list of available tables from database"""
        try:
            conn = pymysql.connect(**self.db_config)
            cursor = conn.cursor()
            cursor.execute("SHOW TABLES")
            tables = [row[0] for row in cursor.fetchall()]
            cursor.close()
            conn.close()
            return tables
        except Exception as e:
            logger.error(f"❌ Error getting tables: {e}")
            return []
    
    def _should_use_tier1(self, question: str, context: Optional[Dict[str, Any]] = None) -> bool:
        """
        Determine if we should use Tier 1 (NL-to-SQL Generator) or Tier 2 (LLM-based)
        
        Tier 1 is preferred for:
        - Simple SELECT queries
        - Questions without complex joins or subqueries
        - First-time queries (no context)
        
        Tier 2 is preferred for:
        - Complex analytical queries
        - Queries requiring conversation context
        - Queries with user corrections
        - Follow-up questions
        """
        if not self.nl_to_sql_generator:
            return False  # Tier 1 not available
        
        # Check if there's conversation context suggesting complexity
        if context:
            if context.get('has_corrections'):
                return False  # User corrections need context
            if context.get('is_followup'):
                return False  # Follow-ups need context
        
        # Check query complexity indicators
        question_lower = question.lower()
        
        # Complex query patterns suggest Tier 2
        complex_patterns = [
            'previous query',
            'last result',
            'wrong',
            'incorrect',
            'fix',
            'instead',
            'not that',
            'rather than',
            'combine',
            'merge',
            'union',
            'intersection',
            'difference'
        ]
        
        if any(pattern in question_lower for pattern in complex_patterns):
            logger.info("🔀 Complex pattern detected - using Tier 2")
            return False
        
        # Default to Tier 1 for simple queries
        return True
    
    def _generate_sql_tier1(self, question: str) -> Optional[Dict[str, Any]]:
        """
        Generate SQL using Tier 1: NL-to-SQL Generator
        Returns structured response with SQL, metadata, and confidence
        """
        try:
            logger.info("🚀 Tier 1: Using NL-to-SQL Generator")
            result = self.nl_to_sql_generator.generate(question)
            
            logger.info(f"📊 Tier 1 result: confidence={result.get('confidence', 0):.2f}")
            logger.info(f"   Tables: {result.get('tables_used', [])}")
            logger.info(f"   Needs followup: {result.get('needs_followup', False)}")
            
            return result
            
        except Exception as e:
            logger.error(f"❌ Tier 1 generation failed: {e}")
            return None
    
    def _generate_sql_tier2(
        self, 
        question: str, 
        context: Optional[Dict[str, Any]] = None,
        previous_attempts: Optional[List[str]] = None
    ) -> Optional[str]:
        """
        Generate SQL using Tier 2: LLM-based generation with full context
        Falls back to this when Tier 1 fails or query is complex
        """
        try:
            logger.info("🔄 Tier 2: Using LLM-based generation")
            
            # Build enhanced system prompt with schema and context
            system_prompt = self._build_tier2_system_prompt(question, context)
            
            # Build user prompt with examples and corrections
            user_prompt = self._build_tier2_user_prompt(question, context, previous_attempts)
            
            messages = [{"role": "user", "content": user_prompt}]
            
            response = self.llm_service.generate_response(
                messages=messages,
                system_prompt=system_prompt,
                max_tokens=500,
                temperature=0.1
            )
            
            sql_query = self._extract_sql_query(response)
            
            if sql_query:
                logger.info(f"✅ Tier 2 generated SQL: {sql_query[:100]}...")
            
            return sql_query
            
        except Exception as e:
            logger.error(f"❌ Tier 2 generation failed: {e}")
            return None
    
    def _build_tier2_system_prompt(self, question: str, context: Optional[Dict[str, Any]]) -> str:
        """Build system prompt for Tier 2 generation with verified schema corrections"""
        prompt = """You are a senior MySQL 8.x SQL generator for NEO Automated Warehouse (ASRS).

❌ CRITICAL SCHEMA CORRECTIONS (VERIFIED 2026-02-09 - MANDATORY):
1. ❌ NO 'article_master' table! Use 'article_registered' OR 'sku_master'
2. ❌ bot_master has NO 'BOT_NAME' column - only BOT_ID (varchar(50))
3. ❌ store_bin_master has NO 'AISLE_ID/TOWER_ID' - join location_master via LOCATION_ID
4. ❌ task_master_log PK is 'LOG_ID' (NOT 'TASK_MASTER_LOG_ID')
5. ❌ live_inventory_master has NO 'EXPIRY_DATE' - use sku_batch_master.EXPIRY_DATE
6. ✓ bot_master.STATUS: 'ENABLED', 'DISABLED' (NOT 'ACTIVE'/'INACTIVE')
7. ✓ location_master.AISLE_NUMBER: 'A01'-'A24', TOWER_NUMBER: 'T01'-'T10'

MANDATORY RULES:
1. Generate ONLY read-only SELECT queries (no INSERT/UPDATE/DELETE)
2. Use proper MySQL 8.x syntax with table aliases (bm, tml, lim, ar, sbm, lm)
3. Verify every column exists in AVAILABLE TABLES before using
4. For Aisle/Tower: store_bin_master → location_master via LOCATION_ID
5. For SKU names: live_inventory_master → article_registered via ARTICLE_ID = SKU_ID
6. For expiry: sku_batch_master with compound key (SKU_ID + BATCH_ID)
7. Filter active inventory: WHERE IS_ACTIVE = 1 AND QUANTITY > 0
8. Add default LIMIT 100 for safety
9. Return ONLY the SQL query - no explanations, no markdown

"""
        
        # Add table list
        if self.available_tables:
            prompt += f"AVAILABLE TABLES ({len(self.available_tables)} total):\n{', '.join(sorted(self.available_tables[:25]))}\n"
            if len(self.available_tables) > 25:
                prompt += f"... and {len(self.available_tables) - 25} more\n"
            prompt += "\n"
        
        # Add blacklisted tables from user feedback
        if context and context.get('blacklisted_tables'):
            prompt += "⚠️ DO NOT USE (user confirmed these are wrong/empty/irrelevant):\n"
            for table in context['blacklisted_tables']:
                prompt += f"  ❌ {table}\n"
            prompt += "\n"
        
        # Add user corrections
        if context and context.get('user_corrections'):
            prompt += "🔧 USER CORRECTIONS (APPLY THESE):\n"
            for corr in context.get('user_corrections', [])[-3:]:  # Last 3
                prompt += f"  - Use '{corr.get('correct')}' NOT '{corr.get('wrong')}'\n"
            prompt += "\n"
        
        return prompt
    
    def _build_tier2_user_prompt(
        self,
        question: str,
        context: Optional[Dict[str, Any]],
        previous_attempts: Optional[List[str]]
    ) -> str:
        """Build user prompt for Tier 2 generation"""
        prompt = f"USER QUESTION: {question}\n\n"
        
        if previous_attempts:
            prompt += "PREVIOUS ATTEMPTS (avoid these):\n"
            for i, attempt in enumerate(previous_attempts[-3:], 1):
                prompt += f"{i}. {attempt}\n"
            prompt += "\n"
        
        prompt += "Generate MySQL query to answer the question. Return ONLY the SQL."
        return prompt
    
    def _extract_sql_query(self, response: str) -> Optional[str]:
        """Extract SQL query from LLM response"""
        if not response:
            return None
        
        # Try to extract from code blocks
        import re
        code_block_match = re.search(r'```(?:sql)?\s*\n(.*?)\n```', response, re.DOTALL | re.IGNORECASE)
        if code_block_match:
            return code_block_match.group(1).strip()
        
        # Try to find SELECT statement
        select_match = re.search(r'(SELECT\s+.+?;?)\s*$', response, re.DOTALL | re.IGNORECASE)
        if select_match:
            sql = select_match.group(1).strip()
            if sql.endswith(';'):
                sql = sql[:-1].strip()
            return sql
        
        # If response looks like SQL, return as-is
        if response.strip().upper().startswith('SELECT'):
            sql = response.strip()
            if sql.endswith(';'):
                sql = sql[:-1].strip()
            return sql
        
        return None
    
    def _execute_query_safe(
        self, 
        sql_query: str, 
        session_id: Optional[str] = None
    ) -> Tuple[List[Dict[str, Any]], Optional[str]]:
        """Execute SQL query safely with validation"""
        try:
            # Check blacklisted tables
            if session_id and session_id in self.session_corrections:
                failed_tables = self.session_corrections[session_id].get('failed_tables', [])
                if failed_tables:
                    sql_lower = sql_query.lower()
                    for failed in failed_tables:
                        if re.search(r'\b' + re.escape(failed['table'].lower()) + r'\b', sql_lower):
                            return [], f"Query uses blacklisted table: {failed['table']}"
            
            # Security check
            if not is_read_only_sql(sql_query):
                return [], "Query must be read-only (SELECT only)"
            
            # Execute query
            conn = pymysql.connect(**self.db_config, connect_timeout=5)
            try:
                df = pd.read_sql(sql_query, conn)
                results = df.to_dict('records')
                logger.info(f"✅ Query executed: {len(results)} rows")
                return results, None
            finally:
                conn.close()
                
        except Exception as e:
            logger.error(f"❌ Execution error: {e}")
            return [], str(e)
    
    def _validate_results(
        self,
        results: List[Dict[str, Any]],
        question: str,
        sql_query: str,
        tier1_metadata: Optional[Dict[str, Any]] = None
    ) -> Tuple[float, str]:
        """Validate query results and calculate confidence score"""
        confidence = 0.5
        messages = []
        
        # Use Tier 1 confidence if available
        if tier1_metadata:
            tier1_confidence = tier1_metadata.get('confidence', 0)
            confidence = max(confidence, tier1_confidence)
            if tier1_metadata.get('needs_followup'):
                confidence *= 0.8
                messages.append("⚠️ Query may need clarification")
        
        # Check results
        if not results:
            return 0.3, "No results - query may be too restrictive"
        
        confidence += 0.1
        messages.append(f"✅ {len(results)} results found")
        
        # Check result count
        if 1 <= len(results) <= 1000:
            confidence += 0.15
        elif len(results) > 10000:
            confidence -= 0.1
        
        # Check data quality
        if results:
            first_row = results[0]
            non_null = sum(1 for v in first_row.values() if v is not None)
            if non_null >= len(first_row) * 0.7:
                confidence += 0.15
        
        confidence = min(confidence, 1.0)
        return confidence, " | ".join(messages)
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Process natural language query with two-tier SQL generation
        
        Workflow:
        1. Determine complexity and choose tier
        2. Try Tier 1 (NL-to-SQL Generator) for simple queries
        3. Fall back to Tier 2 (LLM) if needed
        4. Execute and validate results
        5. Retry with different strategy if low confidence
        6. Return formatted results
        """
        start_time = datetime.now()
        
        try:
            logger.info(f"🔍 Processing query: {chat_request.message[:50]}...")
            
            # Get or create session
            session_id = chat_request.session_id
            if not session_id or not self.session_manager.get_session(session_id):
                session_id = self.session_manager.create_session(
                    session_type=SessionType.SQL_ASSISTANT,
                    initial_message=chat_request.message
                )
            
            if not self.db_available:
                return self._create_error_response(
                    "Database not available",
                    session_id
                )
            
            # Build context
            context = self._build_query_context(session_id)
            
            # Determine which tier to use
            use_tier1 = self._should_use_tier1(chat_request.message, context)
            
            sql_query = None
            tier1_metadata = None
            
            # Try Tier 1 first
            if use_tier1:
                tier1_result = self._generate_sql_tier1(chat_request.message)
                if tier1_result:
                    sql_query = tier1_result.get('sql')
                    tier1_metadata = tier1_result
                    
                    # Check if Tier 1 suggests followup
                    if tier1_result.get('needs_followup'):
                        logger.info("🔀 Tier 1 needs followup - falling back to Tier 2")
                        sql_query = None
            
            # Fall back to Tier 2 if needed
            if not sql_query:
                sql_query = self._generate_sql_tier2(
                    chat_request.message,
                    context=context
                )
            
            if not sql_query:
                return self._create_error_response(
                    "Could not generate valid SQL query",
                    session_id
                )
            
            # Execute query
            results, error = self._execute_query_safe(sql_query, session_id)
            
            if error:
                return self._create_error_response(
                    f"Query execution failed: {error}",
                    session_id,
                    metadata={'sql_query': sql_query, 'error': error}
                )
            
            # Validate results
            confidence, validation_msg = self._validate_results(
                results,
                chat_request.message,
                sql_query,
                tier1_metadata
            )
            
            logger.info(f"📊 Final confidence: {confidence:.2f} | {validation_msg}")
            
            # Format response
            response_text = self._format_results(
                results,
                sql_query,
                confidence,
                tier1_metadata
            )
            
            # Store in session
            self.session_manager.add_message(session_id, 'assistant', response_text)
            
            return ChatResponse(
                response=response_text,
                chatbot_type=ChatbotType.SQL_ASSISTANT,
                session_id=session_id,
                sources=[],
                confidence_score=confidence,
                metadata={
                    'sql_query': sql_query,
                    'row_count': len(results),
                    'tier': 'tier1' if use_tier1 and tier1_metadata else 'tier2',
                    'tier1_metadata': tier1_metadata,
                    'execution_time': (datetime.now() - start_time).total_seconds()
                }
            )
            
        except Exception as e:
            logger.error(f"❌ Query processing failed: {e}", exc_info=True)
            return self._create_error_response(str(e), chat_request.session_id)
    
    def _build_query_context(self, session_id: str) -> Dict[str, Any]:
        """Build context for query generation"""
        context = {}
        
        if session_id in self.session_corrections:
            corrections = self.session_corrections[session_id]
            context['blacklisted_tables'] = [
                f['table'] for f in corrections.get('failed_tables', [])
            ]
            context['has_corrections'] = True
        
        return context
    
    def _format_results(
        self,
        results: List[Dict[str, Any]],
        sql_query: str,
        confidence: float,
        tier1_metadata: Optional[Dict[str, Any]]
    ) -> str:
        """Format query results for display"""
        response = f"**Query Results ({len(results)} rows)**\n\n"
        
        if tier1_metadata:
            if tier1_metadata.get('assumptions'):
                response += "**Assumptions:**\n"
                for assumption in tier1_metadata['assumptions']:
                    response += f"- {assumption}\n"
                response += "\n"
        
        if len(results) == 0:
            response += "*No data found*\n"
        elif len(results) <= 10:
            # Show all results
            df = pd.DataFrame(results)
            response += f"```\n{df.to_string(index=False)}\n```\n"
        else:
            # Show first 5 and summary
            df_preview = pd.DataFrame(results[:5])
            response += f"```\n{df_preview.to_string(index=False)}\n... and {len(results) - 5} more rows\n```\n"
        
        response += f"\n**SQL Query:**\n```sql\n{sql_query}\n```\n"
        response += f"\n*Confidence: {confidence:.0%}*"
        
        return response
    
    def _create_error_response(
        self,
        error_msg: str,
        session_id: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> ChatResponse:
        """Create error response"""
        return ChatResponse(
            response=f"❌ **Error:** {error_msg}",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            metadata=metadata or {}
        )
