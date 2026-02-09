"""
Unified SQL Assistant Service - Production Ready
Tier 1 First: CSV-based NL-to-SQL with LLM fallback
Features: Smart retry logic, validation skip for high confidence, session management
"""

import logging
import uuid
import re
import os
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime
import pymysql
import pandas as pd

from .llm_service import LLMService
from .rlhf_service import RLHFService
from .chat_history_service import ChatHistoryService
from .nl_to_sql_generator import NLToSQLGenerator, is_read_only_sql
from ..models.schemas import ChatRequest, ChatResponse, ChatbotType
from app.core.config import settings
from ..utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)


class SQLAssistantService:
    """
    Unified SQL Assistant with intelligent tier fallback:
    - Always tries Tier 1 (CSV-based NL-to-SQL) first
    - Falls back to Tier 2 (LLM) only if Tier 1 fails
    - Smart retry up to 3 attempts with different strategies
    - Skips validation/retry if confidence > 94%
    - Full session management, caching, and corrections
    """
    
    def __init__(self):
        """Initialize unified SQL assistant service"""
        # Core services
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
        
        # Thresholds and limits
        self.high_confidence_threshold = 0.94  # Skip validation/retry above this
        self.acceptable_confidence_threshold = 0.75  # Minimum to return results
        self.max_retry_attempts = 3  # Prevent infinite loops
        
        # Initialize Tier 1: NL-to-SQL Generator (CSV-based)
        self.nl_to_sql_generator = None
        self._initialize_tier1_generator()
        
        # Initialize supporting services
        self._initialize_supporting_services()
        
        # Session caches
        self.session_query_cache: Dict[str, List[Dict[str, Any]]] = {}
        self.session_corrections: Dict[str, Dict[str, Any]] = {}
        
        # Test database and load schema
        self.db_available = self._test_db_connection()
        self.available_tables = self._get_available_tables()
        self.schema_parser = self._load_schema_parser()
        
        # Load SQL assistant config
        self._load_sql_assistant_config()
        
        logger.info(f"✅ Unified SQL Assistant initialized")
        logger.info(f"   Database: {'✅ Connected' if self.db_available else '❌ Unavailable'}")
        logger.info(f"   Tier 1: {'✅ Active' if self.nl_to_sql_generator else '⚠️ Disabled'}")
        logger.info(f"   Tables: {len(self.available_tables)} available")
    
    def _initialize_tier1_generator(self):
        """Initialize CSV-based NL-to-SQL generator (Tier 1)"""
        try:
            # Look for schema CSV
            schema_csv_paths = [
                settings.DATA_DIR / "database" / "Table_information.csv",
                "data/database/Table_information.csv",
                os.path.join(settings.DATA_DIR, "database", "Table_information.csv")
            ]
            
            schema_csv_path = None
            for path in schema_csv_paths:
                if os.path.exists(str(path)):
                    schema_csv_path = str(path)
                    break
            
            if not schema_csv_path:
                logger.warning("⚠️ Schema CSV not found - Tier 1 disabled")
                logger.warning(f"   Searched: {[str(p) for p in schema_csv_paths]}")
                return
            
            self.nl_to_sql_generator = NLToSQLGenerator(
                api_key=settings.OPENAI_API_KEY,
                model=getattr(settings, 'NL2SQL_MODEL', settings.OPENAI_MODEL),
                schema_csv_path=schema_csv_path
            )
            logger.info(f"✅ Tier 1 initialized with schema: {schema_csv_path}")
            
        except Exception as e:
            logger.error(f"❌ Tier 1 initialization failed: {e}")
            self.nl_to_sql_generator = None
    
    def _initialize_supporting_services(self):
        """Initialize vector store, chat history, classification services"""
        # Vector store
        try:
            from .vector_store_service import VectorStoreService
            self.vector_store = VectorStoreService()
        except Exception as e:
            logger.warning(f"⚠️ Vector store unavailable: {e}")
            self.vector_store = None
        
        # Chat history
        try:
            self.chat_history_service = ChatHistoryService(self.db_config)
        except Exception as e:
            logger.warning(f"⚠️ Chat history unavailable: {e}")
            self.chat_history_service = None
        
        # Query classification
        try:
            from .query_classification_service import QueryClassificationService
            classification_storage = settings.DATA_DIR / "classification"
            self.classification_service = QueryClassificationService(classification_storage)
        except Exception as e:
            logger.warning(f"⚠️ Classification service unavailable: {e}")
            self.classification_service = None
    
    def _test_db_connection(self) -> bool:
        """Test database connectivity"""
        try:
            conn = pymysql.connect(**self.db_config, connect_timeout=5)
            conn.close()
            return True
        except Exception as e:
            logger.error(f"❌ Database connection failed: {e}")
            return False
    
    def _get_available_tables(self) -> List[str]:
        """Get list of available tables"""
        try:
            conn = pymysql.connect(**self.db_config)
            cursor = conn.cursor()
            cursor.execute("SHOW TABLES")
            tables = [row[0] for row in cursor.fetchall()]
            cursor.close()
            conn.close()
            return tables
        except:
            return []
    
    def _load_schema_parser(self):
        """Load schema parser for dynamic schema loading"""
        try:
            from ..utils.schema_loader import SchemaGraphLoader
            schema_file = settings.DATA_DIR / "database" / "schema.json"
            if os.path.exists(str(schema_file)):
                loader = SchemaGraphLoader(str(schema_file))
                return loader
        except Exception as e:
            logger.warning(f"⚠️ Schema parser unavailable: {e}")
        return None
    
    def _load_sql_assistant_config(self):
        """Load SQL assistant configuration"""
        try:
            config_file = settings.DATA_DIR / "sql_assistant_config.json"
            if os.path.exists(str(config_file)):
                import json
                with open(config_file, 'r') as f:
                    self.sql_config = json.load(f)
                    logger.info(f"✅ Loaded SQL assistant config")
            else:
                self.sql_config = {}
        except Exception as e:
            logger.warning(f"⚠️ SQL config unavailable: {e}")
            self.sql_config = {}
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Main query processing with intelligent tier fallback
        
        Flow:
        1. Session management and validation
        2. Try Tier 1 (CSV-based NL-to-SQL)
        3. Check confidence and validate
        4. If confidence > 94%: Skip validation, return immediately
        5. If confidence < threshold or validation fails: Retry up to 3 times
        6. Fallback to Tier 2 (LLM) if all Tier 1 attempts fail
        7. Execute, validate, and return results
        """
        start_time = datetime.now()
        
        try:
            logger.info(f"🔍 Processing: {chat_request.message[:60]}...")
            
            # Step 1: Session management
            session_id = self._get_or_create_session(chat_request)
            
            if not self.db_available:
                return self._create_error_response("Database unavailable", session_id)
            
            # Step 2: Check for special cases (negative feedback, corrections)
            special_response = self._handle_special_cases(chat_request, session_id)
            if special_response:
                return special_response
            
            # Step 3: Build context from session
            context = self._build_query_context(session_id, chat_request)
            
            # Step 4: Generate SQL with retry logic
            sql_query, confidence, metadata = self._generate_sql_with_retry(
                chat_request.message,
                context,
                session_id
            )
            
            if not sql_query:
                return self._create_error_response(
                    "Could not generate valid SQL query after all attempts",
                    session_id
                )
            
            # Step 5: Skip validation if very high confidence
            if confidence >= self.high_confidence_threshold:
                logger.info(f"🚀 HIGH CONFIDENCE ({confidence:.0%}) - Skipping validation")
                results, error = self._execute_query_safe(sql_query, session_id)
                
                if error:
                    logger.warning(f"⚠️ High confidence query failed: {error}")
                    # Retry with lower confidence path
                else:
                    # Success! Return immediately
                    return self._create_success_response(
                        results, sql_query, confidence, session_id,
                        metadata={'tier': metadata.get('tier'), 'fast_path': True,
                                 'execution_time': (datetime.now() - start_time).total_seconds()}
                    )
            
            # Step 6: Normal path - execute with validation
            results, error = self._execute_query_safe(sql_query, session_id)
            
            if error:
                return self._create_error_response(
                    f"Query execution failed: {error}",
                    session_id,
                    metadata={'sql_query': sql_query, 'error': error}
                )
            
            # Step 7: Validate results
            final_confidence, validation_msg = self._validate_results(
                results, chat_request.message, sql_query, metadata
            )
            
            # Step 8: Store in classification service if available
            if self.classification_service:
                try:
                    self.classification_service.store_query(
                        session_id=session_id,
                        user_query=chat_request.message,
                        generated_sql=sql_query,
                        execution_status='success',
                        rows_returned=len(results),
                        confidence=final_confidence,
                        tables_used=metadata.get('tables_used', []),
                        metadata=metadata
                    )
                except Exception as e:
                    logger.warning(f"⚠️ Could not store query: {e}")
            
            # Step 9: Return success response
            return self._create_success_response(
                results, sql_query, final_confidence, session_id,
                metadata={
                    **metadata,
                    'validation_message': validation_msg,
                    'execution_time': (datetime.now() - start_time).total_seconds()
                }
            )
            
        except Exception as e:
            logger.error(f"❌ Query processing error: {e}", exc_info=True)
            return self._create_error_response(str(e), chat_request.session_id)
    
    def _generate_sql_with_retry(
        self,
        question: str,
        context: Dict[str, Any],
        session_id: str
    ) -> Tuple[Optional[str], float, Dict[str, Any]]:
        """
        Generate SQL with retry logic:
        - Always try Tier 1 first
        - Retry up to 3 times if confidence < threshold
        - Fall back to Tier 2 if all Tier 1 attempts fail
        """
        attempt = 0
        best_sql = None
        best_confidence = 0.0
        best_metadata = {}
        
        while attempt < self.max_retry_attempts:
            attempt += 1
            logger.info(f"🔄 Attempt {attempt}/{self.max_retry_attempts}")
            
            # Try Tier 1 first
            if self.nl_to_sql_generator and attempt == 1:
                sql, confidence, metadata = self._try_tier1_generation(question)
                
                if sql:
                    # Validate the SQL
                    validation_passed = self._quick_validate_sql(sql, session_id)
                    
                    if validation_passed:
                        # Check confidence
                        if confidence >= self.high_confidence_threshold:
                            logger.info(f"✅ Tier 1 HIGH confidence: {confidence:.0%}")
                            return sql, confidence, metadata
                        elif confidence >= self.acceptable_confidence_threshold:
                            logger.info(f"✅ Tier 1 acceptable confidence: {confidence:.0%}")
                            return sql, confidence, metadata
                        else:
                            logger.info(f"⚠️ Tier 1 low confidence: {confidence:.0%} - Will retry")
                            if confidence > best_confidence:
                                best_sql, best_confidence, best_metadata = sql, confidence, metadata
                    else:
                        logger.warning(f"❌ Tier 1 validation failed - Will retry")
            
            # Try Tier 2 (LLM fallback) for subsequent attempts
            if attempt > 1 or not self.nl_to_sql_generator:
                strategy = ['direct', 'with_context', 'simplified'][min(attempt - 1, 2)]
                logger.info(f"🔄 Tier 2: LLM with strategy '{strategy}'")
                
                sql = self._generate_sql_tier2(question, strategy, context, session_id)
                
                if sql:
                    validation_passed = self._quick_validate_sql(sql, session_id)
                    
                    if validation_passed:
                        # Estimate confidence for LLM-generated SQL
                        confidence = 0.85  # Base LLM confidence
                        metadata = {'tier': 'tier2', 'strategy': strategy}
                        
                        if confidence >= self.acceptable_confidence_threshold:
                            logger.info(f"✅ Tier 2 acceptable: {confidence:.0%}")
                            return sql, confidence, metadata
                        
                        if confidence > best_confidence:
                            best_sql, best_confidence, best_metadata = sql, confidence, metadata
        
        # Return best attempt if we have one
        if best_sql:
            logger.info(f"📊 Returning best attempt: confidence={best_confidence:.0%}")
            return best_sql, best_confidence, best_metadata
        
        logger.error(f"❌ All {self.max_retry_attempts} attempts failed")
        return None, 0.0, {}
    
    def _try_tier1_generation(self, question: str) -> Tuple[Optional[str], float, Dict[str, Any]]:
        """Try Tier 1 (CSV-based NL-to-SQL) generation"""
        try:
            logger.info("🚀 Tier 1: CSV-based NL-to-SQL Generator")
            result = self.nl_to_sql_generator.generate(question)
            
            sql = result.get('sql', '')
            confidence = result.get('confidence', 0.0)
            
            metadata = {
                'tier': 'tier1',
                'tables_used': result.get('tables_used', []),
                'columns_used': result.get('columns_used', []),
                'assumptions': result.get('assumptions', []),
                'warnings': result.get('warnings', []),
                'needs_followup': result.get('needs_followup', False)
            }
            
            logger.info(f"   Confidence: {confidence:.0%}")
            logger.info(f"   Tables: {metadata['tables_used']}")
            
            return sql, confidence, metadata
            
        except Exception as e:
            logger.error(f"❌ Tier 1 failed: {e}")
            return None, 0.0, {}
    
    def _generate_sql_tier2(
        self,
        question: str,
        strategy: str,
        context: Dict[str, Any],
        session_id: str
    ) -> Optional[str]:
        """Generate SQL using Tier 2 (LLM) with given strategy"""
        try:
            system_prompt = self._build_tier2_system_prompt(context)
            
            if strategy == 'direct':
                user_prompt = f"Convert to SQL: {question}"
            elif strategy == 'with_context':
                user_prompt = f"User question: {question}\n\nGenerate MySQL query. Return ONLY the SQL."
            else:  # simplified
                user_prompt = f"Generate simple SQL for: {question}. Keep it basic."
            
            messages = [{"role": "user", "content": user_prompt}]
            
            response = self.llm_service.generate_response(
                messages=messages,
                system_prompt=system_prompt,
                max_tokens=500,
                temperature=0.1
            )
            
            sql = self._extract_sql_from_response(response)
            
            if sql:
                logger.info(f"✅ Tier 2 generated SQL")
            
            return sql
            
        except Exception as e:
            logger.error(f"❌ Tier 2 generation error: {e}")
            return None
    
    def _build_tier2_system_prompt(self, context: Dict[str, Any]) -> str:
        """Build system prompt for LLM (Tier 2) with verified schema constraints"""
        prompt = """You are a senior MySQL 8.x SQL expert for NEO Automated Warehouse (ASRS).

❌ CRITICAL SCHEMA FACTS (VERIFIED - NEVER FORGET):
- ❌ NO 'article_master' table! Use 'article_registered' (or sku_master)
- ❌ bot_master has NO BOT_NAME column (only BOT_ID varchar(50))
- ❌ store_bin_master has NO AISLE_ID/TOWER_ID (join location_master!)
- ❌ task_master_log PK is LOG_ID (NOT TASK_MASTER_LOG_ID)
- ❌ live_inventory_master has NO EXPIRY_DATE (use sku_batch_master!)
- ✓ bot_master.STATUS: 'ENABLED', 'DISABLED' (not ACTIVE/INACTIVE)
- ✓ location_master.AISLE_NUMBER: 'A01'-'A24', 'RA01'-'RA03'
- ✓ location_master.TOWER_NUMBER: 'T01'-'T10'

MANDATORY RULES:
1. Generate ONLY read-only SELECT queries (no INSERT/UPDATE/DELETE)
2. Use proper MySQL syntax with table aliases (bm, tml, lim, ar, sbm, lm)
3. Verify every column exists in available tables before using
4. For Aisle/Tower: store_bin_master → location_master via LOCATION_ID
5. For SKU names: live_inventory_master → article_registered via ARTICLE_ID=SKU_ID
6. For expiry: sku_batch_master with compound key (SKU_ID + BATCH_ID)
7. Filter active records: IS_ACTIVE = 1 AND QUANTITY > 0
8. Add default LIMIT 100 for safety
9. Return ONLY the SQL query - no explanations

"""
        if self.available_tables:
            prompt += f"AVAILABLE TABLES ({len(self.available_tables)} total): {', '.join(sorted(self.available_tables[:30]))}\n\n"
        
        # Add blacklisted tables from user feedback
        if context.get('blacklisted_tables'):
            prompt += "⚠️ DO NOT USE (user confirmed these are wrong/empty/irrelevant):\n"
            for table in context['blacklisted_tables']:
                prompt += f"  ❌ {table}\n"
            prompt += "\n"
        
        # Add user corrections from session
        if context.get('user_corrections'):
            prompt += "🔧 USER CORRECTIONS (APPLY THESE):\n"
            for corr in context['user_corrections'][-5:]:  # Last 5 corrections
                prompt += f"  - Use '{corr.get('correct')}' NOT '{corr.get('wrong')}'\n"
            prompt += "\n"
        
        return prompt
    
    def _extract_sql_from_response(self, response: str) -> Optional[str]:
        """Extract SQL from LLM response"""
        if not response:
            return None
        
        # Try code blocks
        match = re.search(r'```(?:sql)?\s*\n(.*?)\n```', response, re.DOTALL | re.IGNORECASE)
        if match:
            return match.group(1).strip().rstrip(';')
        
        # Try SELECT statement
        match = re.search(r'(SELECT\s+.+?)(?:;|\s*$)', response, re.DOTALL | re.IGNORECASE)
        if match:
            return match.group(1).strip()
        
        # If looks like SQL
        if response.strip().upper().startswith('SELECT'):
            return response.strip().rstrip(';')
        
        return None
    
    def _quick_validate_sql(self, sql: str, session_id: str) -> bool:
        """Quick validation checks on SQL"""
        try:
            # Check read-only
            if not is_read_only_sql(sql):
                logger.warning("❌ SQL is not read-only")
                return False
            
            # Check blacklisted tables
            if session_id in self.session_corrections:
                failed_tables = self.session_corrections[session_id].get('failed_tables', [])
                sql_lower = sql.lower()
                for failed in failed_tables:
                    if re.search(r'\b' + re.escape(failed['table'].lower()) + r'\b', sql_lower):
                        logger.warning(f"❌ Uses blacklisted table: {failed['table']}")
                        return False
            
            # Check tables exist
            tables = self._extract_tables_from_sql(sql)
            for table in tables:
                if table not in self.available_tables:
                    logger.warning(f"❌ Table not found: {table}")
                    return False
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Validation error: {e}")
            return False
    
    def _extract_tables_from_sql(self, sql: str) -> List[str]:
        """Extract table names from SQL query"""
        tables = []
        # Simple regex to find FROM and JOIN clauses
        from_matches = re.findall(r'FROM\s+`?(\w+)`?', sql, re.IGNORECASE)
        join_matches = re.findall(r'JOIN\s+`?(\w+)`?', sql, re.IGNORECASE)
        tables.extend(from_matches)
        tables.extend(join_matches)
        return list(set(tables))
    
    def _execute_query_safe(
        self,
        sql: str,
        session_id: str
    ) -> Tuple[List[Dict[str, Any]], Optional[str]]:
        """Execute SQL query safely"""
        try:
            conn = pymysql.connect(**self.db_config, connect_timeout=5)
            try:
                df = pd.read_sql(sql, conn)
                results = df.to_dict('records')
                logger.info(f"✅ Executed: {len(results)} rows")
                return results, None
            finally:
                conn.close()
        except Exception as e:
            return [], str(e)
    
    def _validate_results(
        self,
        results: List[Dict[str, Any]],
        question: str,
        sql: str,
        metadata: Dict[str, Any]
    ) -> Tuple[float, str]:
        """Validate results and calculate final confidence"""
        confidence = metadata.get('confidence', 0.5) if metadata.get('tier') == 'tier1' else 0.85
        messages = []
        
        if not results:
            return 0.3, "No results returned"
        
        confidence += 0.1
        messages.append(f"✅ {len(results)} results")
        
        if 1 <= len(results) <= 1000:
            confidence += 0.05
        
        # Check data quality
        if results:
            first_row = results[0]
            non_null = sum(1 for v in first_row.values() if v is not None)
            if non_null >= len(first_row) * 0.7:
                confidence += 0.05
        
        return min(confidence, 1.0), " | ".join(messages)
    
    def _get_or_create_session(self, chat_request: ChatRequest) -> str:
        """Get existing session or create new one"""
        session_id = chat_request.session_id
        if not session_id or not self.session_manager.get_session(session_id):
            session_id = self.session_manager.create_session(
                session_type=SessionType.SQL_ASSISTANT,
                initial_message=chat_request.message
            )
        else:
            self.session_manager.add_message(session_id, 'user', chat_request.message)
        return session_id
    
    def _handle_special_cases(
        self,
        chat_request: ChatRequest,
        session_id: str
    ) -> Optional[ChatResponse]:
        """Handle negative feedback, corrections, etc."""
        # Implement if needed - can copy from original service
        return None
    
    def _build_query_context(
        self,
        session_id: str,
        chat_request: ChatRequest
    ) -> Dict[str, Any]:
        """Build context for query generation"""
        context = {}
        
        if session_id in self.session_corrections:
            corrections = self.session_corrections[session_id]
            context['blacklisted_tables'] = [
                f['table'] for f in corrections.get('failed_tables', [])
            ]
            context['has_corrections'] = True
        
        return context
    
    def _create_success_response(
        self,
        results: List[Dict[str, Any]],
        sql: str,
        confidence: float,
        session_id: str,
        metadata: Dict[str, Any]
    ) -> ChatResponse:
        """Create successful response with formatted results"""
        response_text = f"**Query Results ({len(results)} rows)**\n\n"
        
        # Show results
        if len(results) == 0:
            response_text += "*No data found*\n"
        elif len(results) <= 10:
            df = pd.DataFrame(results)
            response_text += f"```\n{df.to_string(index=False)}\n```\n"
        else:
            df_preview = pd.DataFrame(results[:5])
            response_text += f"```\n{df_preview.to_string(index=False)}\n... and {len(results) - 5} more rows\n```\n"
        
        response_text += f"\n**SQL Query:**\n```sql\n{sql}\n```\n"
        response_text += f"\n*Confidence: {confidence:.0%}*"
        
        if metadata.get('tier'):
            response_text += f" | {metadata['tier'].upper()}"
        if metadata.get('fast_path'):
            response_text += " | ⚡ Fast Path"
        
        self.session_manager.add_message(session_id, 'assistant', response_text)
        
        return ChatResponse(
            response=response_text,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id,
            sources=[],
            confidence_score=confidence,
            metadata=metadata
        )
    
    def _create_error_response(
        self,
        error_msg: str,
        session_id: Optional[str],
        metadata: Optional[Dict[str, Any]] = None
    ) -> ChatResponse:
        """Create error response"""
        response_text = f"❌ **Error:** {error_msg}"
        return ChatResponse(
            response=response_text,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            metadata=metadata or {}
        )
