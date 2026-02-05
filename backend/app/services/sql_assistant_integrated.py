"""
SQL Assistant Service - INTEGRATED VERSION with nl_to_sql_generator.py
Convert natural language to SQL queries with prioritized generation strategies

FLOW:
1. Check session cache (in-memory)
2. Check classified queries (JSONL file)  
3. Check chat history (MySQL patterns)
4a. Generate with nl_to_sql_generator.py (PRIORITY - CSV-based)
4b. Retry with feedback up to 3 attempts
4c. Fallback to LLM if CSV generator fails
5. Execute & validate
6. Store for future reuse

Author: Integrated with nl_to_sql_generator.py priority
Date: February 2026
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
from difflib import SequenceMatcher

from .llm_service import LLMService
from .rlhf_service import RLHFService
from .chat_history_service import ChatHistoryService
from .nl_to_sql_generator import NLToSQLGenerator
from ..models.schemas import ChatRequest, ChatResponse, ChatbotType, SQLQueryRequest, SQLQueryResponse
from app.core.config import settings
from ..utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)


class SQLAssistantService:
    """
    Integrated SQL Assistant with nl_to_sql_generator priority
    
    Features:
    - Session cache (in-memory, last 10 queries per session)
    - Classified queries (human-verified JSONL file)
    - Chat history patterns (MySQL learning)
    - nl_to_sql_generator.py as primary SQL generator
    - Retry with feedback (up to 3 attempts)
    - LLM fallback (only if CSV generator fails)
    - Execution & validation
    - Result storage (session, classification, MySQL)
    """
    
    def __init__(self):
        """Initialize integrated SQL assistant service"""
        self.llm_service = LLMService()
        self.rlhf_service = RLHFService()
        self.session_manager = get_session_manager()
        self.schema_parser = self._load_schema_parser()
        self.db_config = {
            'host': settings.DB_HOST,
            'port': settings.DB_PORT,
            'user': settings.DB_USER,
            'password': settings.DB_PASSWORD,
            'database': settings.DB_NAME
        }
        
        # Initialize nl_to_sql_generator (PRIORITY GENERATOR)
        try:
            csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
            # NLToSQLGenerator expects: api_key, model, schema_csv_path, db_config
            openai_api_key = settings.OPENAI_API_KEY
            if not openai_api_key:
                raise ValueError("OPENAI_API_KEY not configured")
            
            # Use gpt-5.2 as default model for SQL generation
            openai_model = os.getenv("OPENAI_SQL_MODEL", "gpt-5.2")
            
            # Pass DB config for entity resolution
            self.nl_sql_generator = NLToSQLGenerator(
                api_key=openai_api_key,
                model=openai_model,
                schema_csv_path=str(csv_path),
                db_config=self.db_config
            )
            logger.info(f"✅ nl_to_sql_generator initialized with entity resolution (model: {openai_model})")
        except Exception as e:
            logger.warning(f"⚠️ nl_to_sql_generator unavailable, will use LLM only: {e}")
            self.nl_sql_generator = None
        
        # Initialize vector store for SQL examples
        try:
            from .vector_store_service import VectorStoreService
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
        
        # Initialize query classification service
        try:
            from .query_classification_service import QueryClassificationService
            classification_storage = settings.DATA_DIR / "classification"
            self.classification_service = QueryClassificationService(classification_storage)
            logger.info("✅ Query classification service enabled")
        except Exception as e:
            logger.warning(f"⚠️ Query classification service unavailable: {e}")
            self.classification_service = None
        
        # Session-based caches
        self.session_query_cache: Dict[str, List[Dict[str, Any]]] = {}
        self.session_corrections: Dict[str, Dict[str, Any]] = {}
        
        # Test database connection (non-blocking, log warning if fails)
        logger.info(f"🔌 Testing database connection to {self.db_config['host']}:{self.db_config['port']}...")
        self.db_available = self._test_db_connection()
        
        if not self.db_available:
            logger.warning("⚠️ Database connection test failed - SQL execution will be disabled")
            logger.warning("⚠️ Entity resolution and query validation will be skipped")
            logger.warning(f"⚠️ Check DB credentials: host={self.db_config['host']}, port={self.db_config['port']}, user={self.db_config['user']}")
        
        # Load available tables
        self.available_tables = self._get_available_tables()
        logger.info(f"✅ Cached {len(self.available_tables)} available tables")
        
        # Configuration
        self.max_retry_attempts = 3
        self.high_confidence_threshold = 0.94
        self.acceptable_confidence_threshold = 0.75
        self.session_cache_similarity_threshold = 0.85
        self.classified_query_similarity_threshold = 0.85
        
        logger.info(f"🎯 Integrated SQL Assistant initialized with nl_to_sql_generator priority")
        logger.info(f"   Max retry attempts: {self.max_retry_attempts}")
        logger.info(f"   High confidence threshold: {self.high_confidence_threshold:.0%}")
        logger.info(f"   Acceptable confidence threshold: {self.acceptable_confidence_threshold:.0%}")
    
    def _load_schema_parser(self):
        """Load schema parser from JSON file"""
        try:
            from ..utils.schema_parser import SchemaParser
            schema_path = settings.DATA_DIR / "database" / "schema.json"
            if schema_path.exists():
                return SchemaParser(str(schema_path))
            return None
        except Exception as e:
            logger.warning(f"⚠️ Could not load schema parser: {e}")
            return None
    
    def _test_db_connection(self) -> bool:
        """Test database connectivity with retry for slow remote servers"""
        max_attempts = 3
        last_error = None
        
        for attempt in range(1, max_attempts + 1):
            try:
                if attempt > 1:
                    logger.info(f"🔄 DB test attempt {attempt}/{max_attempts}...")
                
                conn = pymysql.connect(
                    host=self.db_config['host'],
                    port=self.db_config['port'],
                    user=self.db_config['user'],
                    password=self.db_config['password'],
                    database=self.db_config['database'],
                    connect_timeout=20,  # Increased for remote server
                    charset='utf8mb4'
                )
                conn.close()
                
                if attempt > 1:
                    logger.info(f"✅ Database connection successful on attempt {attempt}")
                else:
                    logger.info("✅ Database connection test successful")
                
                return True
                
            except Exception as e:
                last_error = e
                if attempt < max_attempts:
                    wait_time = 1.0 * attempt
                    logger.warning(f"⚠️ DB connection failed (attempt {attempt}/{max_attempts}): {e}")
                    logger.info(f"⏳ Waiting {wait_time}s before retry...")
                    import time
                    time.sleep(wait_time)
        
        # All attempts failed
        logger.error(f"❌ Database connection test failed after {max_attempts} attempts: {last_error}")
        logger.error(f"   DB config: host={self.db_config['host']}, port={self.db_config['port']}, user={self.db_config['user']}, db={self.db_config['database']}")
        return False
    
    def _get_available_tables(self) -> set:
        """Get set of all available tables from schema"""
        try:
            if self.schema_parser:
                return set(self.schema_parser.get_table_names())
            return set()
        except Exception as e:
            logger.error(f"❌ Error getting available tables: {e}")
            return set()
    
    def _calculate_similarity(self, query1: str, query2: str) -> float:
        """Calculate similarity between two queries with entity-aware matching
        
        Returns 0.0 if queries ask about different entities (bot vs station vs wave)
        """
        q1_lower = query1.lower()
        q2_lower = query2.lower()
        
        # Define key entities that should NOT be confused
        entity_groups = [
            ['bot', 'bots', 'robot', 'robots'],
            ['station', 'stations', 'workstation', 'workstations'],
            ['wave', 'waves', 'batch', 'batches'],
            ['bin', 'bins', 'tote', 'totes', 'container'],
            ['order', 'orders', 'sku', 'skus', 'article', 'articles'],
            ['alarm', 'alarms', 'alert', 'alerts', 'error', 'errors'],
        ]
        
        # Check if queries mention different entities
        q1_entities = set()
        q2_entities = set()
        
        for group in entity_groups:
            for entity in group:
                if entity in q1_lower:
                    q1_entities.add(group[0])  # Use first word as canonical form
                if entity in q2_lower:
                    q2_entities.add(group[0])
        
        # If both queries mention entities but they're DIFFERENT, return 0
        if q1_entities and q2_entities and q1_entities != q2_entities:
            logger.debug(f"❌ Entity mismatch: {q1_entities} vs {q2_entities} - returning 0% similarity")
            return 0.0
        
        # Otherwise use character-level similarity
        return SequenceMatcher(None, q1_lower, q2_lower).ratio()
    
    # ========================================
    # STEP 1: CHECK SESSION CACHE
    # ========================================
    
    def _check_session_cache(self, question: str, session_id: Optional[str]) -> Optional[Tuple[str, float, Dict]]:
        """
        Check session cache for similar queries (last 10 queries in THIS session)
        
        Returns:
            Tuple of (sql, confidence, metadata) if found, None otherwise
        """
        if not session_id or session_id not in self.session_query_cache:
            return None
        
        cached_queries = self.session_query_cache[session_id]
        
        for cached in cached_queries[-10:]:  # Last 10 queries
            similarity = self._calculate_similarity(question, cached['question'])
            
            if similarity >= self.session_cache_similarity_threshold:
                logger.info(f"🎯 SESSION CACHE HIT! Similarity: {similarity:.2%}")
                logger.info(f"   Cached Q: {cached['question'][:60]}")
                logger.info(f"   Current Q: {question[:60]}")
                
                # Boost confidence by 10% for cached queries
                confidence = min(0.98, cached.get('confidence', 0.8) + 0.10)
                
                return (
                    cached['sql'],
                    confidence,
                    {
                        'source': 'session_cache',
                        'original_question': cached['question'],
                        'similarity': similarity,
                        'cache_timestamp': cached.get('timestamp')
                    }
                )
        
        return None
    
    # ========================================
    # STEP 2: CHECK CLASSIFIED QUERIES
    # ========================================
    
    def _check_classified_queries(self, question: str) -> Optional[Tuple[str, float, Dict]]:
        """
        Check classified queries file (human-verified queries)
        
        Returns:
            Tuple of (sql, confidence, metadata) if found, None otherwise
        """
        if not self.classification_service:
            return None
        
        try:
            # Load all classified queries from JSONL file
            classified_file = settings.DATA_DIR / "classification" / "classified_queries.jsonl"
            if not classified_file.exists():
                return None
            
            with open(classified_file, 'r', encoding='utf-8') as f:
                classified = [json.loads(line) for line in f if line.strip()]
            
            for query_record in classified:
                # Handle both 'query' and 'user_query' field names
                user_query = query_record.get('query') or query_record.get('user_query') or query_record.get('question', '')
                if not user_query:
                    continue
                    
                similarity = self._calculate_similarity(question, user_query)
                
                if similarity >= self.classified_query_similarity_threshold:
                    logger.info(f"📚 CLASSIFIED QUERY HIT! Similarity: {similarity:.2%}")
                    logger.info(f"   Classified Q: {user_query[:60]}")
                    logger.info(f"   Current Q: {question[:60]}")
                    
                    # High confidence for human-verified queries + 10% boost
                    confidence = min(0.98, 0.85 + (similarity * 0.1))
                    
                    # Get SQL from different possible field names
                    sql = query_record.get('sql') or query_record.get('generated_sql', '')
                    if not sql:
                        continue
                    
                    return (
                        sql,
                        confidence,
                        {
                            'source': 'classified_queries',
                            'original_question': user_query,
                            'similarity': similarity,
                            'classification': query_record.get('category')
                        }
                    )
        except Exception as e:
            logger.warning(f"⚠️ Error checking classified queries: {e}")
        
        return None
    
    # ========================================
    # STEP 3: CHECK CHAT HISTORY PATTERNS
    # ========================================
    
    def _check_chat_history_patterns(self, question: str) -> Optional[Tuple[str, float, Dict]]:
        """
        Check chat history for successful patterns
        
        Returns:
            Tuple of (sql, confidence, metadata) if found, None otherwise
        """
        if not self.chat_history_service:
            return None
        
        try:
            # Get common query patterns from chat history
            patterns = self.chat_history_service.get_common_query_patterns(limit=50)
            
            best_match = None
            best_similarity = 0.0
            
            for pattern in patterns:
                user_query = pattern.get('pattern_key', '')
                if not user_query:
                    continue
                    
                similarity = self._calculate_similarity(question, user_query)
                
                if similarity > best_similarity and similarity >= 0.80:
                    best_similarity = similarity
                    best_match = pattern
            
            if best_match:
                logger.info(f"📊 CHAT HISTORY PATTERN HIT! Similarity: {best_similarity:.2%}")
                logger.info(f"   Historical pattern: {best_match.get('pattern_key', '')[:60]}")
                logger.info(f"   Current Q: {question[:60]}")
                
                # Calculate confidence based on pattern frequency and similarity  
                frequency_score = min(0.2, best_match.get('success_count', 1) * 0.05)
                confidence = min(0.90, 0.65 + (best_similarity * 0.15) + frequency_score)
                
                # Pattern value might contain SQL or table names
                pattern_value = best_match.get('pattern_value', '')
                
                return (
                    None,  # No direct SQL from patterns, used for context only
                    confidence,
                    {
                        'source': 'chat_history',
                        'pattern_key': best_match.get('pattern_key', ''),
                        'pattern_value': pattern_value,
                        'similarity': best_similarity,
                        'frequency': best_match.get('success_count', 1),
                        'avg_confidence': best_match.get('avg_confidence', 0.0)
                    }
                )
        except Exception as e:
            logger.warning(f"⚠️ Error checking chat history patterns: {e}")
        
        return None
    
    # ========================================
    # STEP 4: GENERATE NEW SQL
    # ========================================
    
    def _generate_sql_with_nl_generator(
        self, 
        question: str, 
        feedback: Optional[str] = None,
        previous_sql: Optional[str] = None
    ) -> Tuple[Optional[str], float, Dict]:
        """
        Generate SQL using nl_to_sql_generator.py (CSV-based TF-IDF)
        
        Returns:
            Tuple of (sql, confidence, metadata)
        """
        if not self.nl_sql_generator:
            return None, 0.0, {'error': 'nl_sql_generator not available'}
        
        try:
            # Build prompt with feedback if provided
            if feedback and previous_sql:
                enhanced_question = f"""{question}

PREVIOUS ATTEMPT FEEDBACK:
SQL: {previous_sql}
Issue: {feedback}

Generate improved SQL query addressing the feedback."""
            else:
                enhanced_question = question
            
            # Generate SQL with nl_to_sql_generator
            result = self.nl_sql_generator.generate(enhanced_question)
            
            if result and result.get('sql'):
                sql = result['sql']
                confidence = result.get('confidence', 0.75)
                
                logger.info(f"✅ nl_to_sql_generator generated SQL (confidence: {confidence:.2%})")
                logger.info(f"   SQL: {sql[:100]}...")
                
                return (
                    sql,
                    confidence,
                    {
                        'source': 'nl_to_sql_generator',
                        'tables_used': result.get('tables_used', []),
                        'columns_used': result.get('columns_used', []),
                        'assumptions': result.get('assumptions', []),
                        'warnings': result.get('warnings', []),
                        'is_read_only': result.get('is_read_only', True)
                    }
                )
            else:
                logger.warning("⚠️ nl_to_sql_generator returned no SQL")
                return None, 0.0, {'error': 'No SQL generated'}
        
        except Exception as e:
            logger.error(f"❌ nl_to_sql_generator error: {e}")
            return None, 0.0, {'error': str(e)}
    
    def _generate_sql_with_llm(
        self,
        question: str,
        strategy: str = 'direct',
        context: Optional[Dict[str, Any]] = None
    ) -> Optional[str]:
        """
        Generate SQL using LLM (FALLBACK ONLY)
        
        Returns:
            SQL query string or None
        """
        try:
            # Get dynamic system prompt with schema
            system_prompt = self._get_system_prompt(question, context)
            
            if strategy == 'direct':
                prompt = f"Convert to SQL: {question}"
            elif strategy == 'with_context':
                prompt = f"""User question: {question}

Generate MySQL query to answer this question. Return ONLY the SQL."""
            else:  # simplified
                prompt = f"Generate simple SQL for: {question}. Keep it basic with proper table names."
            
            messages = [{"role": "user", "content": prompt}]
            
            response = self.llm_service.generate_response(
                messages=messages,
                system_prompt=system_prompt,
                max_tokens=300,
                temperature=0.1
            )
            
            sql_query = self._extract_sql_query(response)
            logger.info(f"✅ LLM generated SQL with strategy: {strategy}")
            return sql_query
            
        except Exception as e:
            logger.error(f"❌ LLM SQL generation error with strategy {strategy}: {e}")
            return None
    
    def _get_system_prompt(self, question: str, context: Optional[Dict[str, Any]] = None) -> str:
        """Build system prompt with relevant schema"""
        # Get relevant schema tables based on question
        schema_text = self._get_relevant_schema(question, max_tables=8)
        
        prompt = f"""You are a MySQL query generator for the NEO Warehouse Management System.

AVAILABLE SCHEMA:
{schema_text}

RULES:
1. Return ONLY the SQL query, no explanations
2. Use proper MySQL syntax
3. Use actual table and column names from schema
4. Keep queries efficient and simple
5. Use JOINs when querying multiple tables"""
        
        # Add conversation context if available
        if context:
            context_prompt = self._build_context_prompt(context)
            if context_prompt:
                prompt += f"\n\n{context_prompt}"
        
        return prompt
    
    def _get_relevant_schema(self, question: str, max_tables: int = 8) -> str:
        """Get relevant table schemas based on question keywords"""
        if not self.schema_parser:
            return "Schema not available"
        
        # Extract keywords from question
        keywords = set(re.findall(r'\b\w{3,}\b', question.lower()))
        
        # Score tables by keyword matches
        table_scores = []
        for table_name in self.schema_parser.get_table_names():
            score = 0
            table_lower = table_name.lower()
            
            # Direct table name mention
            if any(keyword in table_lower for keyword in keywords):
                score += 10
            
            # Column name matches
            columns = self.schema_parser.get_table_columns(table_name)
            for col in columns:
                if any(keyword in col.lower() for keyword in keywords):
                    score += 2
            
            if score > 0:
                table_scores.append((table_name, score))
        
        # Sort and get top tables
        table_scores.sort(key=lambda x: x[1], reverse=True)
        top_tables = [t for t, s in table_scores[:max_tables]]
        
        # If no matches, return top frequently used tables
        if not top_tables:
            top_tables = ['bot_master', 'task_log', 'location_master'][:max_tables]
        
        # Build schema text
        schema_parts = []
        for table in top_tables:
            schema = self.schema_parser.get_table_schema(table)
            schema_parts.append(schema)
        
        return "\n\n".join(schema_parts)
    
    def _extract_sql_query(self, response: str) -> Optional[str]:
        """Extract SQL query from LLM response"""
        if not response:
            return None
        
        # Remove markdown code blocks
        response = re.sub(r'```sql\s*', '', response, flags=re.IGNORECASE)
        response = re.sub(r'```\s*', '', response)
        
        # Extract SQL query
        lines = response.strip().split('\n')
        sql_lines = []
        
        for line in lines:
            line = line.strip()
            # Skip comments and explanations
            if line.startswith('--') or line.startswith('#'):
                continue
            if line:
                sql_lines.append(line)
        
        sql = ' '.join(sql_lines).strip()
        
        # Basic validation
        if sql and any(keyword in sql.upper() for keyword in ['SELECT', 'SHOW', 'DESC', 'EXPLAIN']):
            return sql
        
        return None
    
    def _build_context_prompt(self, context: Dict[str, Any]) -> str:
        """Build context prompt from conversation history"""
        prompt_parts = []
        
        if context.get('corrections'):
            prompt_parts.append("\n🔧 USER CORRECTIONS (CRITICAL):")
            for corr in context['corrections'][-3:]:
                prompt_parts.append(f"  - Use '{corr['correct']}' NOT '{corr['wrong']}'")
        
        if context.get('failed_tables'):
            prompt_parts.append("\n🚨 DO NOT USE THESE TABLES:")
            for failed in context['failed_tables'][-3:]:
                prompt_parts.append(f"  - ❌ {failed['table']} - {failed['reason']}")
        
        return "\n".join(prompt_parts) if prompt_parts else ""
    
    # ========================================
    # STEP 5: EXECUTE & VALIDATE
    # ========================================
    
    def _execute_query_safe(self, sql_query: str) -> Tuple[List[Dict[str, Any]], Optional[str]]:
        """Execute SQL query safely with timeout and validation"""
        try:
            # Security check - prevent dangerous operations
            dangerous_patterns = [
                r'\bDROP\s+TABLE\b',
                r'\bDROP\s+DATABASE\b',
                r'\bDELETE\s+FROM\b',
                r'\bTRUNCATE\b',
                r'\bALTER\s+TABLE\b',
                r'\bCREATE\s+TABLE\b',
                r'\bINSERT\s+INTO\b',
                r'\bUPDATE\s+\w+\s+SET\b'
            ]
            
            query_upper = sql_query.upper()
            for pattern in dangerous_patterns:
                if re.search(pattern, query_upper):
                    return [], f"Query contains dangerous operation: {pattern}"
            
            # Execute query
            conn = pymysql.connect(**self.db_config, connect_timeout=5)
            
            try:
                df = pd.read_sql(sql_query, conn)
                results = df.to_dict('records')
                
                logger.info(f"✅ Query executed: {len(results)} rows returned")
                return results, None
                
            finally:
                conn.close()
                
        except pymysql.Error as e:
            error_msg = str(e)
            logger.error(f"❌ Database error: {error_msg}")
            return [], error_msg
        except Exception as e:
            error_msg = str(e)
            logger.error(f"❌ Execution error: {error_msg}")
            return [], error_msg
    
    def _validate_results(
        self,
        results: List[Dict[str, Any]],
        question: str,
        sql_query: str
    ) -> Tuple[float, str]:
        """
        Validate query results and calculate confidence score
        
        Returns:
            Tuple of (confidence_score, validation_message)
        """
        confidence = 0.5  # Base confidence
        messages = []
        
        # Check 1: Results exist
        if not results:
            return 0.3, "No results returned - query might be too restrictive"
        
        confidence += 0.1
        messages.append(f"✅ {len(results)} results found")
        
        # Check 2: Reasonable result count
        if 1 <= len(results) <= 1000:
            confidence += 0.15
            messages.append("✅ Result count looks reasonable")
        elif len(results) > 10000:
            confidence -= 0.1
            messages.append("⚠️ Very large result set")
        
        # Check 3: Results have data (not all nulls)
        if results:
            first_row = results[0]
            non_null_values = sum(1 for v in first_row.values() if v is not None)
            
            if non_null_values >= len(first_row) * 0.7:
                confidence += 0.15
                messages.append("✅ Results contain meaningful data")
            else:
                confidence -= 0.05
                messages.append("⚠️ Many null values in results")
        
        # Check 4: Column names make sense
        if results:
            columns = list(results[0].keys())
            if len(columns) > 0:
                confidence += 0.10
                messages.append(f"✅ Query returns {len(columns)} columns")
        
        return min(0.95, confidence), " | ".join(messages)
    
    # ========================================
    # STEP 6: STORE FOR FUTURE REUSE
    # ========================================
    
    def _store_successful_query(
        self,
        session_id: str,
        question: str,
        sql: str,
        results_count: int,
        confidence: float,
        sample_data: List[Dict] = None
    ):
        """Store successful query in session cache"""
        if not session_id:
            return
        
        if session_id not in self.session_query_cache:
            self.session_query_cache[session_id] = []
        
        self.session_query_cache[session_id].append({
            'question': question,
            'sql': sql,
            'results_count': results_count,
            'confidence': confidence,
            'sample_data': sample_data[:3] if sample_data else [],
            'timestamp': datetime.now().isoformat()
        })
        
        # Keep only last 10 queries per session
        if len(self.session_query_cache[session_id]) > 10:
            self.session_query_cache[session_id] = self.session_query_cache[session_id][-10:]
        
        logger.info(f"💾 Stored successful query in session cache (total: {len(self.session_query_cache[session_id])})")
    
    def _extract_conversation_context(
        self,
        conversation_history: Optional[List],
        session_id: Optional[str]
    ) -> Dict[str, Any]:
        """Extract conversation context for SQL generation"""
        context = {
            'corrections': [],
            'failed_tables': [],
            'previous_results': []
        }
        
        # Get session-specific corrections
        if session_id and session_id in self.session_corrections:
            context['corrections'].extend(self.session_corrections[session_id].get('corrections', []))
            context['failed_tables'].extend(self.session_corrections[session_id].get('failed_tables', []))
        
        # Get cached successful queries
        if session_id and session_id in self.session_query_cache:
            recent_queries = self.session_query_cache[session_id][-3:]
            for query_info in recent_queries:
                context['previous_results'].append({
                    'question': query_info['question'],
                    'sql': query_info['sql'],
                    'results_count': query_info.get('results_count', 0)
                })
        
        return context
    
    # ========================================
    # MAIN PROCESS QUERY METHOD
    # ========================================
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Process natural language query with integrated caching and generation
        
        COMPLETE FLOW:
        1. Check session cache (in-memory, 85% similarity)
        2. Check classified queries (JSONL file, 85% similarity)
        3. Check chat history patterns (MySQL, 80% similarity)
        4a. Generate with nl_to_sql_generator.py (CSV-based, PRIORITY)
        4b. Retry with feedback (up to 3 attempts)
        4c. Fallback to LLM if all nl_to_sql attempts fail
        5. Execute & validate (with confidence scoring)
        6. Store for future reuse (session cache + classification + chat history)
        
        Args:
            chat_request: User's chat request
            
        Returns:
            Chat response with validated query results
        """
        start_time = datetime.now()
        
        try:
            logger.info(f"🔍 Processing SQL query: {chat_request.message[:50]}...")
            
            # Get or create session
            session_id = chat_request.session_id
            if not session_id or not self.session_manager.get_session(session_id):
                session_id = self.session_manager.create_session(
                    session_type=SessionType.SQL_ASSISTANT,
                    initial_message=chat_request.message
                )
                logger.info(f"🆕 Created new session: {session_id}")
            else:
                self.session_manager.add_message(session_id, 'user', chat_request.message)
            
            if not self.db_available:
                error_msg = "Database connection is not available."
                return self._create_error_response(error_msg, session_id)
            
            question = chat_request.message
            sql_query = None
            confidence = 0.0
            metadata = {}
            
            # ========================================
            # STEP 1: CHECK SESSION CACHE
            # ========================================
            logger.info("📋 STEP 1: Checking session cache...")
            cache_result = self._check_session_cache(question, session_id)
            if cache_result:
                sql_query, confidence, metadata = cache_result
                logger.info(f"✨ Using cached query from session (confidence: {confidence:.2%})")
            
            # ========================================
            # STEP 2: CHECK CLASSIFIED QUERIES
            # ========================================
            if not sql_query:
                logger.info("📚 STEP 2: Checking classified queries...")
                classified_result = self._check_classified_queries(question)
                if classified_result:
                    sql_query, confidence, metadata = classified_result
                    logger.info(f"✨ Using classified query (confidence: {confidence:.2%})")
            
            # ========================================
            # STEP 3: CHECK CHAT HISTORY PATTERNS
            # ========================================
            if not sql_query:
                logger.info("📊 STEP 3: Checking chat history patterns...")
                history_result = self._check_chat_history_patterns(question)
                if history_result:
                    sql_query, confidence, metadata = history_result
                    logger.info(f"✨ Using chat history pattern (confidence: {confidence:.2%})")
            
            # ========================================
            # STEP 4: GENERATE NEW SQL
            # ========================================
            if not sql_query:
                logger.info("🤖 STEP 4: Generating new SQL...")
                
                # Get conversation context
                conversation_context = self._extract_conversation_context(
                    chat_request.conversation_history,
                    session_id
                )
                
                # Try nl_to_sql_generator first (up to 3 attempts with feedback)
                feedback = None
                previous_sql = None
                
                for attempt in range(self.max_retry_attempts):
                    logger.info(f"🔄 Attempt {attempt + 1}/{self.max_retry_attempts} with nl_to_sql_generator...")
                    
                    # Generate with nl_to_sql_generator
                    sql_query, confidence, metadata = self._generate_sql_with_nl_generator(
                        question,
                        feedback=feedback,
                        previous_sql=previous_sql
                    )
                    
                    if not sql_query:
                        logger.warning(f"⚠️ nl_to_sql_generator failed on attempt {attempt + 1}")
                        continue
                    
                    # Execute and validate
                    results, error = self._execute_query_safe(sql_query)
                    
                    if error:
                        logger.warning(f"⚠️ Execution error on attempt {attempt + 1}: {error}")
                        feedback = error
                        previous_sql = sql_query
                        continue
                    
                    # Validate results
                    validation_confidence, validation_msg = self._validate_results(results, question, sql_query)
                    
                    # Combine generator confidence with validation confidence
                    combined_confidence = (confidence * 0.6) + (validation_confidence * 0.4)
                    
                    logger.info(f"📊 Confidence: generator={confidence:.2%}, validation={validation_confidence:.2%}, combined={combined_confidence:.2%}")
                    
                    # If high confidence, skip retry
                    if combined_confidence >= self.high_confidence_threshold:
                        logger.info(f"🚀 HIGH CONFIDENCE ({combined_confidence:.2%}) - Using result!")
                        confidence = combined_confidence
                        metadata['validation_message'] = validation_msg
                        metadata['attempt'] = attempt + 1
                        break
                    
                    # If acceptable confidence, use it
                    elif combined_confidence >= self.acceptable_confidence_threshold:
                        logger.info(f"✅ ACCEPTABLE CONFIDENCE ({combined_confidence:.2%}) - Using result")
                        confidence = combined_confidence
                        metadata['validation_message'] = validation_msg
                        metadata['attempt'] = attempt + 1
                        break
                    
                    # Low confidence - retry with feedback
                    else:
                        logger.warning(f"⚠️ LOW CONFIDENCE ({combined_confidence:.2%}) - Retrying with feedback")
                        feedback = f"Low confidence ({combined_confidence:.2%}): {validation_msg}"
                        previous_sql = sql_query
                        
                        # On last attempt, keep the result anyway
                        if attempt == self.max_retry_attempts - 1:
                            logger.warning(f"⚠️ Last attempt - using result despite low confidence")
                            confidence = combined_confidence
                            metadata['validation_message'] = validation_msg
                            metadata['attempt'] = attempt + 1
                            break
                
                # If all nl_to_sql_generator attempts failed, fallback to LLM
                if not sql_query or confidence < 0.30:
                    logger.warning("⚠️ All nl_to_sql_generator attempts failed or very low confidence - falling back to LLM")
                    
                    strategies = ['direct', 'with_context', 'simplified']
                    for strategy in strategies:
                        logger.info(f"🔄 LLM fallback with strategy: {strategy}")
                        
                        sql_query = self._generate_sql_with_llm(question, strategy, conversation_context)
                        
                        if sql_query:
                            results, error = self._execute_query_safe(sql_query)
                            
                            if not error:
                                confidence, validation_msg = self._validate_results(results, question, sql_query)
                                metadata = {
                                    'source': 'llm_fallback',
                                    'strategy': strategy,
                                    'validation_message': validation_msg
                                }
                                
                                if confidence >= self.acceptable_confidence_threshold:
                                    logger.info(f"✅ LLM fallback successful (confidence: {confidence:.2%})")
                                    break
            
            # ========================================
            # STEP 5: EXECUTE & FORMAT RESULTS
            # ========================================
            if sql_query:
                logger.info(f"⚡ STEP 5: Executing final SQL query...")
                results, error = self._execute_query_safe(sql_query)
                
                if error:
                    return self._create_error_response(f"Query execution error: {error}", session_id)
                
                # Format response
                response_text = self._format_results(results, question, sql_query, confidence, metadata)
                
                # ========================================
                # STEP 6: STORE FOR FUTURE REUSE
                # ========================================
                logger.info(f"💾 STEP 6: Storing successful query...")
                
                # Store in session cache
                self._store_successful_query(
                    session_id,
                    question,
                    sql_query,
                    len(results),
                    confidence,
                    results[:3]
                )
                
                # Log to chat history (MySQL)
                if self.chat_history_service:
                    try:
                        response_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
                        
                        chat_id = self.chat_history_service.log_chat_interaction(
                            session_id=session_id,
                            chatbot_type="sql_assistant",
                            user_query=question,
                            assistant_response=response_text,
                            confidence_score=confidence,
                            response_time_ms=response_time_ms
                        )
                        
                        self.chat_history_service.log_sql_query(
                            chat_id=chat_id,
                            session_id=session_id,
                            user_query=question,
                            generated_sql=sql_query,
                            execution_status='success',
                            rows_returned=len(results),
                            execution_time_ms=response_time_ms
                        )
                    except Exception as e:
                        logger.warning(f"⚠️ Failed to log to chat history: {e}")
                
                # Store in classification file (if confidence >= 50%)
                if self.classification_service and confidence >= 0.50:
                    try:
                        # Extract tables from metadata if available
                        tables_used = metadata.get('tables_used', []) if metadata else []
                        
                        self.classification_service.store_query(
                            session_id=session_id,
                            user_query=question,
                            generated_sql=sql_query,
                            execution_status='success',
                            rows_returned=len(results),
                            confidence=confidence,
                            tables_used=tables_used,
                            metadata=metadata
                        )
                        logger.info(f"📝 Stored in classified queries (confidence: {confidence:.2%})")
                    except Exception as e:
                        logger.warning(f"⚠️ Failed to store in classified queries: {e}")
                
                # Add to session messages
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
                        **metadata
                    }
                )
            
            else:
                return self._create_error_response("Failed to generate SQL query", session_id)
        
        except Exception as e:
            logger.error(f"❌ Error processing query: {e}", exc_info=True)
            return self._create_error_response(str(e), session_id)
    
    def _format_results(
        self,
        results: List[Dict[str, Any]],
        question: str,
        sql_query: str,
        confidence: float,
        metadata: Dict
    ) -> str:
        """Format query results into readable response"""
        response_parts = []
        
        # Add source information
        source = metadata.get('source', 'generated')
        if source == 'session_cache':
            response_parts.append("💾 *Retrieved from session cache*\n")
        elif source == 'classified_queries':
            response_parts.append("📚 *Retrieved from classified queries*\n")
        elif source == 'chat_history':
            response_parts.append("📊 *Retrieved from chat history*\n")
        elif source == 'nl_to_sql_generator':
            response_parts.append("🤖 *Generated with nl_to_sql_generator*\n")
        elif source == 'llm_fallback':
            response_parts.append("🔄 *Generated with LLM fallback*\n")
        
        # Add results
        if not results:
            response_parts.append("No results found for your query.")
        elif len(results) <= 10:
            # Show all results for small datasets
            response_parts.append(f"**Found {len(results)} result(s):**\n")
            for i, row in enumerate(results, 1):
                response_parts.append(f"\n**Result {i}:**")
                for key, value in row.items():
                    response_parts.append(f"  • {key}: {value}")
        else:
            # Show summary for large datasets
            response_parts.append(f"**Found {len(results)} results** (showing first 5):\n")
            for i, row in enumerate(results[:5], 1):
                response_parts.append(f"\n**Result {i}:**")
                for key, value in row.items():
                    response_parts.append(f"  • {key}: {value}")
            response_parts.append(f"\n... and {len(results) - 5} more results")
        
        # Add SQL query
        response_parts.append(f"\n\n**SQL Query:**\n```sql\n{sql_query}\n```")
        
        # Add confidence
        response_parts.append(f"\n*Confidence: {confidence:.0%}*")
        
        return "\n".join(response_parts)
    
    def _create_error_response(self, error_message: str, session_id: Optional[str]) -> ChatResponse:
        """Create error response"""
        return ChatResponse(
            response=f"❌ {error_message}",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            sources=[],
            confidence_score=0.0,
            metadata={'error': error_message}
        )
    
    def get_schema_info(self) -> Dict[str, Any]:
        """Get database schema information for diagnostic service"""
        return {
            "total_tables": len(self._extract_table_names()),
            "tables": self._extract_table_names()[:20],  # Return first 20 tables
            "llm_provider": self.llm_service.get_provider_info() if self.llm_service else {},
            "db_available": self.db_available
        }
    
    def _extract_table_names(self) -> List[str]:
        """Extract table names from schema parser"""
        try:
            if self.schema_parser:
                return self.schema_parser.get_table_names()
            return []
        except Exception as e:
            logger.error(f"❌ Error extracting table names: {e}")
            return []
