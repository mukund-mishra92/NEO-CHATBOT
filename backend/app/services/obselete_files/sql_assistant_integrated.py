"""
SQL Assistant Service - INTEGRATED VERSION with SQLEngine
Convert natural language to SQL queries with prioritized generation strategies

FLOW:
1. Check session cache (in-memory)
2. Check classified queries (JSONL file)  
3. Check chat history (MySQL patterns)
4a. Generate with SQLEngine (PRIORITY - schema-registry-driven)
4b. Retry with feedback up to 3 attempts
4c. Fallback to LLM if SQLEngine fails
5. Execute & validate
6. Store for future reuse

Author: Integrated with SQLEngine (universal, schema-registry-driven)
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

from ..llm_service import LLMService
from ..rlhf_service import RLHFService
from ..chat_history_service import ChatHistoryService
from ..sql_engine import SQLEngine
from ...models.schemas import ChatRequest, ChatResponse, ChatbotType, SQLQueryRequest, SQLQueryResponse
from app.core.config import settings
from ...utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)


class SQLAssistantService:
    """
    Integrated SQL Assistant with SQLEngine priority
    
    Features:
    - Session cache (in-memory, last 10 queries per session)
    - Classified queries (human-verified JSONL file)
    - Chat history patterns (MySQL learning)
    - SQLEngine as primary SQL generator (schema-registry-driven)
    - Retry with feedback (up to 3 attempts)
    - LLM fallback (only if SQLEngine fails)
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
        
        # Initialize SQLEngine (PRIORITY GENERATOR — universal, schema-registry-driven)
        try:
            csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
            openai_api_key = settings.OPENAI_API_KEY
            if not openai_api_key:
                raise ValueError("OPENAI_API_KEY not configured")
            
            openai_model = os.getenv("OPENAI_SQL_MODEL", "gpt-5.2")
            
            self.sql_engine = SQLEngine(
                api_key=openai_api_key,
                model=openai_model,
                schema_csv_path=str(csv_path),
                db_config=self.db_config,
            )
            logger.info(f"✅ SQLEngine initialized (model: {openai_model}, tables: {len(self.sql_engine.registry.tables)})")
        except Exception as e:
            logger.warning(f"⚠️ SQLEngine unavailable, will use LLM only: {e}")
            self.sql_engine = None
        
        # Initialize vector store for SQL examples
        try:
            from ..knowledge_base.vector_store_service import VectorStoreService
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
            from ..query_classification_service import QueryClassificationService
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
        
        # Load table priority validations from user feedback
        self.table_validations = self._load_table_validations()
        logger.info(f"✅ Loaded {len(self.table_validations)} table priority validation rules")
        
        # Load business rules from config
        self.business_rules = self._load_business_rules()
        logger.info(f"✅ Loaded {len(self.business_rules)} business rules from config")
        
        # Configuration
        self.max_retry_attempts = 3
        self.high_confidence_threshold = 0.94
        self.acceptable_confidence_threshold = 0.75
        self.session_cache_similarity_threshold = 0.85
        self.classified_query_similarity_threshold = 0.85
        
        logger.info(f"🎯 Integrated SQL Assistant initialized with SQLEngine priority")
        logger.info(f"   Max retry attempts: {self.max_retry_attempts}")
        logger.info(f"   High confidence threshold: {self.high_confidence_threshold:.0%}")
        logger.info(f"   Acceptable confidence threshold: {self.acceptable_confidence_threshold:.0%}")
    
    def _load_schema_parser(self):
        """Load schema parser from JSON file"""
        try:
            from ...utils.schema_parser import SchemaParser
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
    
    def _load_table_validations(self) -> Dict[str, Dict[str, Any]]:
        """Load table priority validations from JSONL file (user feedback from table_priority_analyzer)"""
        validations_path = settings.DATA_DIR / "database" / "table_priority_validations.jsonl"
        validation_rules = {}
        
        if not validations_path.exists():
            logger.info("ℹ️ No table priority validations file found")
            return validation_rules
        
        try:
            with open(validations_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    
                    entry = json.loads(line)
                    query = entry.get('query', '').lower().strip()
                    table = entry.get('table_name', '')
                    is_correct = entry.get('is_correct', False)
                    
                    if not query or not table:
                        continue
                    
                    if query not in validation_rules:
                        validation_rules[query] = {
                            'correct_tables': [],
                            'incorrect_tables': [],
                            'query_pattern': query
                        }
                    
                    if is_correct and table not in validation_rules[query]['correct_tables']:
                        validation_rules[query]['correct_tables'].append(table)
                    elif not is_correct and table not in validation_rules[query]['incorrect_tables']:
                        validation_rules[query]['incorrect_tables'].append(table)
            
            logger.info(f"✅ Loaded {len(validation_rules)} unique validated query patterns")
            return validation_rules
            
        except Exception as e:
            logger.warning(f"⚠️ Error loading table validations: {e}")
            return {}
    
    def _load_business_rules(self) -> Dict[str, Any]:
        """Load business rules from config/sql_assistant_config.json"""
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        if not config_path.exists():
            logger.info("ℹ️ No business rules config file found")
            return {}
        
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                business_rules = config.get("business_rules", {})
                logger.info(f"✅ Loaded {len(business_rules)} business rules from config")
                return business_rules
        except Exception as e:
            logger.warning(f"⚠️ Error loading business rules: {e}")
            return {}
    
    def _check_business_rules(self, question: str) -> Optional[Dict[str, Any]]:
        """Check if question matches any business rules and return the matched rule"""
        if not self.business_rules:
            return None
        
        question_lower = question.lower()
        matched_rules = []
        
        for rule_name, rule_config in self.business_rules.items():
            triggers = rule_config.get("triggers", [])
            hit_count = sum(1 for trigger in triggers if trigger.lower() in question_lower)
            
            if hit_count > 0:
                logger.info(f"🔴 BUSINESS RULE MATCHED: {rule_name} ({hit_count} triggers)")
                matched_rules.append({
                    'rule_name': rule_name,
                    'hit_count': hit_count,
                    'config': rule_config
                })
        
        if not matched_rules:
            return None
        
        # Sort by hit count (most specific first) and return the best match
        matched_rules.sort(key=lambda r: r['hit_count'], reverse=True)
        best_match = matched_rules[0]
        
        logger.info(f"🎯 Using business rule: {best_match['rule_name']}")
        return best_match['config']
    
    def _check_table_validation_rules(self, question: str) -> Optional[Dict[str, Any]]:
        """Check if question matches any user-validated table priority rules"""
        if not self.table_validations:
            return None
        
        question_lower = question.lower().strip()
        
        # First check for exact match
        if question_lower in self.table_validations:
            logger.info(f"🎯 EXACT TABLE VALIDATION MATCH: {question_lower}")
            return self.table_validations[question_lower]
        
        # Check for high similarity matches (>= 85%)
        best_match = None
        best_similarity = 0.0
        
        for validated_query, rules in self.table_validations.items():
            similarity = self._calculate_similarity(question, validated_query)
            
            if similarity >= 0.85 and similarity > best_similarity:
                best_similarity = similarity
                best_match = rules
        
        if best_match:
            logger.info(f"🎯 TABLE VALIDATION MATCH (similarity: {best_similarity:.2%})")
            logger.info(f"   Matched pattern: {best_match['query_pattern']}")
            logger.info(f"   Required tables: {best_match['correct_tables']}")
            logger.info(f"   Forbidden tables: {best_match['incorrect_tables']}")
            return best_match
        
        return None
    
    def _extract_tables_from_sql(self, sql: str) -> List[str]:
        """Extract table names from SQL query"""
        import re
        tables = []
        
        # Pattern to find table names after FROM and JOIN
        # Matches: FROM table_name, FROM table_name alias, JOIN table_name, etc.
        patterns = [
            r'FROM\s+`?(\w+)`?(?:\s+(?:AS\s+)?\w+)?',
            r'JOIN\s+`?(\w+)`?(?:\s+(?:AS\s+)?\w+)?',
        ]
        
        sql_upper = sql.upper()
        sql_clean = sql  # Keep original case for table name extraction
        
        for pattern in patterns:
            matches = re.finditer(pattern, sql_clean, re.IGNORECASE)
            for match in matches:
                table_name = match.group(1)
                if table_name.upper() not in ['SELECT', 'WHERE', 'ON', 'AND', 'OR']:
                    tables.append(table_name)
        
        return list(set(tables))  # Remove duplicates
    
    def _get_table_columns_list(self, table_name: str) -> List[str]:
        """Get list of column names for a table"""
        try:
            if self.schema_parser and table_name in self.schema_parser.tables:
                return [col['field'] for col in self.schema_parser.tables[table_name]]
            return []
        except Exception:
            return []
    
    def _get_table_columns_from_db(self, table_name: str) -> List[str]:
        """Query actual database for table columns"""
        try:
            conn = pymysql.connect(**self.db_config, connect_timeout=5)
            try:
                with conn.cursor() as cursor:
                    cursor.execute(f"DESCRIBE `{table_name}`")
                    columns = [row[0] for row in cursor.fetchall()]
                    return columns
            finally:
                conn.close()
        except Exception as e:
            logger.debug(f"Could not get columns for {table_name}: {e}")
            return []
    
    def _find_similar_table(self, table_name: str) -> Optional[str]:
        """Find similar table name in schema if exact match fails"""
        if not self.schema_parser:
            return None
        
        table_lower = table_name.lower()
        available_tables = self.schema_parser.get_table_names()
        
        # Check for exact match first
        for t in available_tables:
            if t.lower() == table_lower:
                return t
        
        # Check for partial matches
        for t in available_tables:
            # Check if table name is contained in schema table or vice versa
            if table_lower in t.lower() or t.lower() in table_lower:
                return t
            # Check for underscored versions (WMS_ORDER_REQUEST_DATA -> wms_to_wcs_order_request_data)
            table_parts = set(table_lower.split('_'))
            schema_parts = set(t.lower().split('_'))
            overlap = len(table_parts & schema_parts)
            if overlap >= 3:  # At least 3 matching parts
                return t
        
        return None
    
    def _enhance_error_feedback(self, error: str, sql: str) -> str:
        """Enhance error feedback with actual schema information"""
        enhanced = f"ERROR: {error}\n\n"
        
        # Extract tables from failed SQL
        tables = self._extract_tables_from_sql(sql)
        
        if tables:
            enhanced += "CORRECT TABLE COLUMNS (from database):\n"
            for table in tables:
                # Try direct from DB first
                columns = self._get_table_columns_from_db(table)
                
                if not columns:
                    # Try to find similar table name
                    similar_table = self._find_similar_table(table)
                    if similar_table:
                        columns = self._get_table_columns_from_db(similar_table)
                        if columns:
                            enhanced += f"\nNOTE: You used '{table}' but correct name is '{similar_table}'!\n"
                            table = similar_table
                
                if columns:
                    enhanced += f"\n{table} columns:\n  {', '.join(columns)}\n"
            
            enhanced += "\nCRITICAL: Use ONLY the exact table names and columns listed above."
        
        return enhanced
    
    def _auto_correct_sql_tables(self, sql: str) -> Tuple[str, List[str]]:
        """
        Auto-correct table names in SQL if they don't match actual schema.
        Returns corrected SQL and list of corrections made.
        """
        corrections = []
        corrected_sql = sql
        
        # Extract tables from SQL
        tables = self._extract_tables_from_sql(sql)
        
        for table in tables:
            # Check if table exists exactly
            columns = self._get_table_columns_from_db(table)
            
            if not columns:
                # Try to find similar table name
                similar_table = self._find_similar_table(table)
                if similar_table:
                    # Verify the similar table actually exists in DB
                    similar_columns = self._get_table_columns_from_db(similar_table)
                    if similar_columns:
                        # Replace table name in SQL (case-insensitive)
                        pattern = rf'\b{re.escape(table)}\b'
                        corrected_sql = re.sub(pattern, similar_table, corrected_sql, flags=re.IGNORECASE)
                        corrections.append(f"'{table}' -> '{similar_table}'")
                        logger.info(f"🔧 Auto-corrected table name: {table} -> {similar_table}")
        
        return corrected_sql, corrections
    
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
        
        IMPORTANT: Only returns cached query if:
        1. High similarity (>= 85%)
        2. Time parameters match (e.g., "one week" vs "one month")
        3. Key entities match (e.g., same station, bot, etc.)
        
        Returns:
            Tuple of (sql, confidence, metadata) if found, None otherwise
        """
        if not session_id or session_id not in self.session_query_cache:
            return None
        
        cached_queries = self.session_query_cache[session_id]
        
        # Extract time parameters from current question
        current_time_params = self._extract_time_parameters(question)
        
        for cached in cached_queries[-10:]:  # Last 10 queries
            similarity = self._calculate_similarity(question, cached['question'])
            
            if similarity >= self.session_cache_similarity_threshold:
                # CRITICAL: Check if time parameters changed
                cached_time_params = self._extract_time_parameters(cached['question'])
                
                if current_time_params != cached_time_params:
                    logger.info(f"⚠️ SESSION CACHE: Similar question but different time parameters")
                    logger.info(f"   Cached time: {cached_time_params}")
                    logger.info(f"   Current time: {current_time_params}")
                    continue  # Skip this cache entry
                
                logger.info(f"🎯 SESSION CACHE HIT! Similarity: {similarity:.2%}")
                logger.info(f"   Cached Q: {cached['question'][:60]}")
                logger.info(f"   Current Q: {question[:60]}")
                
                # Boost confidence by 10% for cached queries
                confidence = min(0.98, cached.get('confidence', 0.8) + 0.10)
                
                # Apply entity substitution (e.g., BOT-0007 → BOT-0021)
                sql = self._substitute_entities_in_sql(cached['sql'], cached['question'], question)
                
                return (
                    sql,
                    confidence,
                    {
                        'source': 'session_cache',
                        'original_question': cached['question'],
                        'similarity': similarity,
                        'cache_timestamp': cached.get('timestamp')
                    }
                )
        
        return None
    
    def _extract_time_parameters(self, question: str) -> Dict[str, str]:
        """
        Extract time-related parameters from question.
        
        Returns:
            Dict with time parameters (e.g., {'period': 'one week', 'unit': 'week', 'count': '1'})
        """
        import re
        
        question_lower = question.lower()
        time_params = {}
        
        # Pattern: "last X days/weeks/months/hours"
        last_pattern = r'last\s+(\w+)\s+(day|days|week|weeks|month|months|hour|hours|year|years)'
        match = re.search(last_pattern, question_lower)
        if match:
            time_params['period'] = f"last {match.group(1)} {match.group(2)}"
            time_params['count'] = match.group(1)
            time_params['unit'] = match.group(2)
            return time_params
        
        # Pattern: "past X days/weeks/months"
        past_pattern = r'past\s+(\w+)\s+(day|days|week|weeks|month|months|hour|hours)'
        match = re.search(past_pattern, question_lower)
        if match:
            time_params['period'] = f"past {match.group(1)} {match.group(2)}"
            time_params['count'] = match.group(1)
            time_params['unit'] = match.group(2)
            return time_params
        
        # Pattern: "yesterday", "today", "this week", "this month"
        simple_patterns = [
            'yesterday', 'today', 'this week', 'this month', 'this year',
            'last week', 'last month', 'last year'
        ]
        for pattern in simple_patterns:
            if pattern in question_lower:
                time_params['period'] = pattern
                return time_params
        
        # No time parameter found
        return time_params
    
    # ========================================
    # ENTITY SUBSTITUTION FOR CLASSIFIED QUERIES
    # ========================================
    
    def _extract_entities_from_question(self, question: str) -> Dict[str, str]:
        """
        Extract entity values from question text using regex patterns.
        
        Returns:
            Dict mapping entity types to their values (e.g., {'BOT_ID': 'BOT-0021'})
        """
        entities = {}
        
        # BOT_ID extraction (e.g., "bot 21" → "BOT-0021", "BOT-0007" → "BOT-0007")
        bot_canon_re = re.compile(r"\bBOT-\d{4}\b", re.IGNORECASE)
        bot_num_re = re.compile(r"\b(?:bot|b)\s*[-_ ]?\s*(\d{1,4})\b", re.IGNORECASE)
        
        # Check for canonical format first (BOT-0008)
        m = bot_canon_re.search(question)
        if m:
            entities['BOT_ID'] = m.group(0).upper()
        else:
            # Try to extract number (e.g., "bot 8", "bot21", "b21")
            m = bot_num_re.search(question)
            if m:
                n = int(m.group(1))
                entities['BOT_ID'] = f"BOT-{n:04d}"  # Normalize to BOT-0008
        
        # STATION_ID extraction
        station_num_re = re.compile(r"\b(?:station|stn|st)\s*[-_ ]?\s*(\d{1,4})\b", re.IGNORECASE)
        m = station_num_re.search(question)
        if m:
            entities['STATION_ID'] = f"STATION-{int(m.group(1)):04d}"
        
        # WAVE_ID extraction
        wave_num_re = re.compile(r"\b(?:wave|wv)\s*[-_ ]?\s*(\d{1,6})\b", re.IGNORECASE)
        m = wave_num_re.search(question)
        if m:
            entities['WAVE_ID'] = f"WAVE-{int(m.group(1)):06d}"
        
        # BIN_ID extraction
        bin_num_re = re.compile(r"\b(?:bin|bn)\s*[-_ ]?\s*(\d{1,10})\b", re.IGNORECASE)
        m = bin_num_re.search(question)
        if m:
            entities['BIN_ID'] = str(int(m.group(1)))
        
        return entities
    
    def _substitute_entities_in_sql(self, sql: str, original_question: str, current_question: str) -> str:
        """
        Substitute entity values in SQL query when current question has different entities.
        
        Example:
            Original Q: "What is the position of bot 7?"
            Current Q:  "What is the position of bot 21?"
            SQL before: WHERE bm.BOT_ID = 'BOT-0007'
            SQL after:  WHERE bm.BOT_ID = 'BOT-0021'
        
        Args:
            sql: Original SQL query from classified query
            original_question: Original question that generated the SQL
            current_question: Current user question
        
        Returns:
            Modified SQL with substituted entity values
        """
        # Extract entities from both questions
        original_entities = self._extract_entities_from_question(original_question)
        current_entities = self._extract_entities_from_question(current_question)
        
        # If no entities found in either question, return original SQL
        if not original_entities and not current_entities:
            return sql
        
        # Substitute each entity type
        modified_sql = sql
        substitutions_made = []
        
        for entity_type in ['BOT_ID', 'STATION_ID', 'WAVE_ID', 'BIN_ID']:
            original_value = original_entities.get(entity_type)
            current_value = current_entities.get(entity_type)
            
            # Only substitute if both questions have this entity type and values differ
            if original_value and current_value and original_value != current_value:
                # Replace in SQL (case-insensitive, handle quotes)
                patterns = [
                    (f"= '{original_value}'", f"= '{current_value}'"),
                    (f'= "{original_value}"', f'= "{current_value}"'),
                    (f"= {original_value}", f"= {current_value}"),
                    (f"IN ('{original_value}')", f"IN ('{current_value}')"),
                ]
                
                for old_pattern, new_pattern in patterns:
                    if old_pattern in modified_sql:
                        modified_sql = modified_sql.replace(old_pattern, new_pattern)
                        substitutions_made.append(f"{entity_type}: {original_value} → {current_value}")
        
        if substitutions_made:
            logger.info(f"🔄 Entity substitution applied: {', '.join(substitutions_made)}")
            logger.info(f"   Original SQL: {sql[:100]}...")
            logger.info(f"   Modified SQL: {modified_sql[:100]}...")
        
        return modified_sql
    
    # ========================================
    # STEP 2: CHECK CLASSIFIED QUERIES
    # ========================================
    
    def _check_classified_queries(self, question: str) -> Optional[Tuple[str, float, Dict]]:
        """
        Check classified queries file (ONLY human-verified queries)
        
        CRITICAL: Only returns queries that have been:
        1. Classified as 'correct' by human review
        2. OR present in learned_patterns.json as validated pattern
        
        Returns:
            Tuple of (sql, confidence, metadata) if found, None otherwise
        """
        if not self.classification_service:
            return None
        
        try:
            # Load classified queries
            classified_file = settings.DATA_DIR / "classification" / "classified_queries.jsonl"
            if not classified_file.exists():
                return None
            
            # Load learned patterns (human-validated queries)
            learned_patterns_file = settings.DATA_DIR / "classification" / "learned_patterns.json"
            learned_patterns = {}
            if learned_patterns_file.exists():
                with open(learned_patterns_file, 'r', encoding='utf-8') as f:
                    learned_patterns = json.load(f)
            
            with open(classified_file, 'r', encoding='utf-8') as f:
                classified = [json.loads(line) for line in f if line.strip()]
            
            for query_record in classified:
                # VALIDATION 1: Skip if not human-validated
                classification = query_record.get('classification', 'unclassified')
                query_id = query_record.get('query_id', '')
                
                # Only use queries that are:
                # 1. Classified as 'correct' 
                # 2. OR have source='manual_correction' (manually added correct queries)
                # 3. OR present in learned_patterns.json
                is_validated = (
                    classification == 'correct' or
                    classification == 'bin_presentation' or  # Specific validated categories
                    query_record.get('metadata', {}).get('source') == 'manual_correction' or
                    query_id in learned_patterns
                )
                
                if not is_validated:
                    # Skip unvalidated queries
                    continue
                
                # Handle both 'query' and 'user_query' field names
                user_query = query_record.get('query') or query_record.get('user_query') or query_record.get('question', '')
                if not user_query:
                    continue
                    
                similarity = self._calculate_similarity(question, user_query)
                
                if similarity >= self.classified_query_similarity_threshold:
                    logger.info(f"📚 VALIDATED QUERY HIT! Similarity: {similarity:.2%}")
                    logger.info(f"   Classification: {classification}")
                    logger.info(f"   Validated Q: {user_query[:60]}")
                    logger.info(f"   Current Q: {question[:60]}")
                    
                    # High confidence for human-verified queries + 10% boost
                    confidence = min(0.98, 0.85 + (similarity * 0.1))
                    
                    # Get SQL from different possible field names
                    sql = query_record.get('sql') or query_record.get('generated_sql', '')
                    if not sql:
                        continue
                    
                    # Apply entity substitution (e.g., BOT-0007 → BOT-0021)
                    sql = self._substitute_entities_in_sql(sql, user_query, question)
                    
                    return (
                        sql,
                        confidence,
                        {
                            'source': 'validated_classified_queries',
                            'original_question': user_query,
                            'similarity': similarity,
                            'classification': classification,
                            'validated': True
                        }
                    )
            
            logger.info("📚 No validated classified query match found")
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
        previous_sql: Optional[str] = None,
        retry_count: int = 0
    ) -> Tuple[Optional[str], float, Dict]:
        """
        Generate SQL using SQLEngine (schema-registry-driven, universal).
        
        Returns:
            Tuple of (sql, confidence, metadata)
        """
        if not self.sql_engine:
            return None, 0.0, {'error': 'sql_engine not available'}
        
        # Check for table validation rules before generating
        validation_match = self._check_table_validation_rules(question)
        
        # ALSO check for business rules (from config)
        business_rule = self._check_business_rules(question)
        
        # Combine validation rules and business rules
        forbidden_tables = []
        required_tables = []
        
        if validation_match:
            forbidden_tables.extend(validation_match.get('incorrect_tables', []))
            required_tables.extend(validation_match.get('correct_tables', []))
        
        if business_rule:
            # Business rule might have forbidden_tables or required_table/required_tables
            forbidden_tables.extend(business_rule.get('forbidden_tables', []))
            if 'required_table' in business_rule:
                required_tables.append(business_rule['required_table'])
            if 'required_tables' in business_rule:
                required_tables.extend(business_rule['required_tables'])
        
        # Remove duplicates
        forbidden_tables = list(set(forbidden_tables))
        required_tables = list(set(required_tables))
        
        # If we have validation rules, add them as additional feedback guidance
        enhanced_feedback = feedback
        # If we have validation rules OR business rules, add them as guidance
        if forbidden_tables or required_tables:
            if retry_count == 0:
                # First attempt - soft guidance
                validation_guidance = "\n\n🎯 TABLE SELECTION RULES (CRITICAL - MUST FOLLOW):\n"
                if validation_match:
                    validation_guidance += f"   User validated pattern: '{validation_match['query_pattern']}'\n"
                if business_rule:
                    validation_guidance += f"   Business rule: '{business_rule.get('description', 'N/A')}'\n"
                if required_tables:
                    validation_guidance += f"   ✅ REQUIRED TABLES: {', '.join(required_tables)}\n"
                if forbidden_tables:
                    validation_guidance += f"   ❌ FORBIDDEN TABLES (DO NOT USE): {', '.join(forbidden_tables)}\n"
                validation_guidance += "\n   These rules are mandatory and must be followed exactly!"
            else:
                # Retry attempt - MUCH stronger enforcement
                validation_guidance = "\n\n🚨🚨🚨 CRITICAL ERROR - RETRY WITH CORRECT TABLES 🚨🚨🚨\n"
                validation_guidance += f"   YOU USED WRONG TABLES IN PREVIOUS ATTEMPT!\n"
                if forbidden_tables:
                    validation_guidance += f"   ❌❌❌ NEVER EVER USE: {', '.join(forbidden_tables)} ❌❌❌\n"
                if required_tables:
                    validation_guidance += f"   ✅✅✅ YOU MUST USE ONLY: {', '.join(required_tables)} ✅✅✅\n"
                validation_guidance += "\n   DO NOT use ANY table from the FORBIDDEN list!"
                validation_guidance += "\n   ONLY use tables from the REQUIRED list!\n"
                validation_guidance += "\n   IGNORE SchemaRegistry suggestions if they conflict with this!"
            
            if enhanced_feedback:
                enhanced_feedback += "\n" + validation_guidance
            else:
                enhanced_feedback = validation_guidance
            
            logger.info(f"📋 Adding table rules guidance (retry={retry_count})")
            logger.info(f"   Required: {required_tables}")
            logger.info(f"   Forbidden: {forbidden_tables}")
        
        try:
            result = self.sql_engine.generate(
                question=question,
                enable_entity_resolution=True,
                feedback=enhanced_feedback,
                previous_sql=previous_sql,
            )
            
            if result and result.get('sql'):
                sql = result['sql']
                confidence = result.get('confidence', 0.75)
                tables_used = result.get('tables_used', [])
                
                # HARD CHECK: If validation rules or business rules exist, enforce them strictly
                if (forbidden_tables or required_tables) and retry_count < 2:  # Allow up to 2 retries
                    # Check for forbidden table usage
                    violated = [t for t in tables_used if t in forbidden_tables]
                    if violated:
                        logger.error(f"❌ VALIDATION VIOLATION! SQL uses forbidden tables: {violated}")
                        logger.error(f"   Tables used: {tables_used}")
                        logger.error(f"   Forbidden: {forbidden_tables}")
                        logger.info(f"🔄 Retrying generation with stronger constraints (attempt {retry_count + 2})...")
                        
                        # Recursive retry with much stronger feedback
                        return self._generate_sql_with_nl_generator(
                            question=question,
                            feedback=f"PREVIOUS ATTEMPT COMPLETELY FAILED! You used FORBIDDEN tables: {', '.join(violated)}. These tables are absolutely NOT ALLOWED! Required tables: {', '.join(required_tables) if required_tables else 'any except forbidden'}",
                            previous_sql=sql,
                            retry_count=retry_count + 1
                        )
                    
                    # Check if required tables are used (if specified)
                    if required_tables:
                        has_required = any(t in tables_used for t in required_tables)
                        if not has_required:
                            logger.error(f"❌ VALIDATION VIOLATION! SQL doesn't use required tables: {required_tables}")
                            logger.error(f"   Tables used: {tables_used}")
                            logger.error(f"   Required: {required_tables}")
                            logger.info(f"🔄 Retrying generation with stronger constraints (attempt {retry_count + 2})...")
                            
                            return self._generate_sql_with_nl_generator(
                                question=question,
                                feedback=f"PREVIOUS ATTEMPT FAILED! You MUST use one of these tables: {', '.join(required_tables)}. You used: {', '.join(tables_used)}. This is WRONG!",
                                previous_sql=sql,
                                retry_count=retry_count + 1
                            )
                
                logger.info(f"✅ SQLEngine generated SQL (confidence: {confidence:.2%})")
                logger.info(f"   Tables used: {', '.join(tables_used)}")
                logger.info(f"   SQL: {sql[:100]}...")
                
                return (
                    sql,
                    confidence,
                    {
                        'source': 'sql_engine',
                        'tables_used': tables_used,
                        'columns_used': result.get('columns_used', []),
                        'assumptions': result.get('assumptions', []),
                        'warnings': result.get('warnings', []),
                        'is_read_only': result.get('is_read_only', True),
                        'domains_matched': result.get('domains_matched', []),
                        'selected_tables': result.get('selected_tables', []),
                        'resolved_entities': result.get('resolved_entities', {}),
                        'validation_applied': (validation_match is not None) or (business_rule is not None),
                        'business_rule_matched': business_rule.get('rule_name') if business_rule else None,
                        'retry_count': retry_count,
                    }
                )
            else:
                logger.warning("⚠️ SQLEngine returned no SQL")
                return None, 0.0, {'error': 'No SQL generated'}
        
        except Exception as e:
            logger.error(f"❌ SQLEngine error: {e}")
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
        """Build system prompt with relevant schema and verified corrections"""
        # Get relevant schema tables based on question
        schema_text = self._get_relevant_schema(question, max_tables=8)
        
        prompt = f"""You are a senior MySQL 8.x query generator for the NEO Automated Warehouse (ASRS) Management System.

AVAILABLE SCHEMA:
{schema_text}

❌ CRITICAL SCHEMA CORRECTIONS (VERIFIED 2026-02-09):
- ❌ NO 'article_master' table! Use 'article_registered' (or alias: sku_master)
- ❌ bot_master has NO BOT_NAME column - only BOT_ID (varchar(50))
- ❌ store_bin_master has NO AISLE_ID/TOWER_ID - must join location_master via LOCATION_ID
- ❌ task_master_log PK is LOG_ID (not TASK_MASTER_LOG_ID)
- ❌ live_inventory_master has NO EXPIRY_DATE - use sku_batch_master.EXPIRY_DATE
- ✓ bot_master.STATUS enum: 'ENABLED', 'DISABLED' (NOT 'ACTIVE'/'INACTIVE')
- ✓ location_master.AISLE_NUMBER: 'A01'-'A24', 'RA01'-'RA03', 'URA01'-'URA04'
- ✓ location_master.TOWER_NUMBER: 'T01'-'T10'

MANDATORY RULES:
1. Return ONLY the SQL query - no explanations, no markdown
2. Use ONLY tables and columns from SCHEMA above
3. Verify every column exists before using it
4. For Aisle/Tower: JOIN store_bin_master → location_master ON LOCATION_ID
5. For SKU names: JOIN live_inventory_master → article_registered ON ARTICLE_ID = SKU_ID
6. For expiry dates: JOIN sku_batch_master ON SKU_ID AND BATCH_ID (compound key!)
7. Always filter: live_inventory_master.IS_ACTIVE = 1 AND QUANTITY > 0
8. Use proper MySQL syntax with table aliases (bm, tml, lim, ar, sbm, lm)
9. Default LIMIT 100 unless user asks for "all"
10. READ-ONLY queries only (SELECT/WITH) - no INSERT/UPDATE/DELETE"""
        
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
    
    def _validate_sql_structure(self, sql_query: str) -> Tuple[bool, Optional[str]]:
        """Validate SQL structure using EXPLAIN without executing"""
        try:
            conn = pymysql.connect(**self.db_config, connect_timeout=5)
            try:
                with conn.cursor() as cursor:
                    # Use EXPLAIN to validate syntax and column/table existence
                    cursor.execute(f"EXPLAIN {sql_query}")
                    return True, None
            finally:
                conn.close()
        except pymysql.Error as e:
            error_msg = str(e)
            return False, error_msg
        except Exception as e:
            return False, str(e)
    
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
            'previous_results': [],
            'previous_sql': None,
            'previous_question': None
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
            # Store the most recent query for follow-up detection
            if recent_queries:
                context['previous_sql'] = recent_queries[-1]['sql']
                context['previous_question'] = recent_queries[-1]['question']
        
        return context
    
    def _is_followup_question(self, question: str) -> bool:
        """Detect if the current question is a follow-up to a previous query
        
        IMPORTANT: Only return True if question explicitly references previous query.
        Don't treat questions as followups just because they share similar words.
        """
        question_lower = question.lower()
        
        # Strong followup indicators - explicitly reference previous query
        strong_indicators = [
            'from that', 'from those', 'from the result', 'from above',
            'of those results', 'of them', 'of the above', 'those results', 'that result',
            'the same query', 'the same result', 'same but', 'same query but',
            'from previous', 'previous query', 'previous result',
            'instead of that', 'rather than that',
        ]
        
        # Check for strong indicators first
        if any(indicator in question_lower for indicator in strong_indicators):
            return True
        
        # Weak indicators - only consider followup if:
        # 1. Question is very short (< 30 chars) AND
        # 2. Contains modification words
        if len(question) < 30:
            weak_indicators = [
                'only show', 'just show', 'also show', 'also add',
                'filter by', 'filter it', 'sort by', 'order by',
                'limit to', 'add column', 'remove column',
            ]
            if any(indicator in question_lower for indicator in weak_indicators):
                return True
        
        # Default: treat as NEW independent question
        return False
        question_lower = question.lower().strip()
        
        for indicator in followup_indicators:
            if indicator in question_lower:
                return True
        
        # Also check if question is very short and starts with action words
        short_actions = ['show', 'display', 'get', 'list', 'add', 'remove', 'exclude', 'include', 'filter']
        words = question_lower.split()
        if len(words) <= 15 and words and words[0] in short_actions:
            # Check if it lacks a clear subject (table/entity reference)
            data_subjects = ['alarm', 'bot', 'station', 'order', 'tote', 'task', 'user', 'inventory', 'product']
            has_subject = any(subj in question_lower for subj in data_subjects)
            if not has_subject:
                return True
        
        return False
    
    def _enhance_question_with_context(
        self, 
        question: str, 
        conversation_context: Dict[str, Any]
    ) -> str:
        """
        Enhance a follow-up question with context from previous queries.
        This creates a ChatGPT-like context understanding for SQL generation.
        """
        if not conversation_context.get('previous_sql') or not conversation_context.get('previous_question'):
            return question
        
        previous_sql = conversation_context['previous_sql']
        previous_question = conversation_context['previous_question']
        
        # Build enhanced question with context
        enhanced_question = f"""CONTEXT FROM PREVIOUS QUERY:
The user previously asked: "{previous_question}"
Which was answered with this SQL:
```sql
{previous_sql}
```

CURRENT FOLLOW-UP REQUEST:
{question}

INSTRUCTIONS:
This is a follow-up question that MODIFIES or REFINES the previous query.
- Keep the same base tables and WHERE conditions from the previous query
- Apply the user's modifications (different columns, additional filters, sorting, etc.)
- Generate a new SQL query that incorporates these changes
"""
        
        logger.info(f"🔗 Enhanced follow-up question with previous context")
        return enhanced_question
    
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
        4a. Generate with SQLEngine (schema-registry-driven, PRIORITY)
        4b. Retry with feedback (up to 3 attempts)
        4c. Fallback to LLM if all SQLEngine attempts fail
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
            
            # Get session for context (managed by endpoint)
            session_id = chat_request.session_id
            if session_id:
                # Session already managed by endpoint
                pass
            else:
                session_id = None
            
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
                
                # Check if this is a follow-up question and enhance with context
                question_to_use = question
                is_followup = self._is_followup_question(question)
                
                if is_followup and conversation_context.get('previous_sql'):
                    logger.info("🔗 Detected FOLLOW-UP question - enhancing with previous context")
                    question_to_use = self._enhance_question_with_context(question, conversation_context)
                    metadata['is_followup'] = True
                    metadata['previous_question'] = conversation_context.get('previous_question')
                
                # Try SQLEngine first (up to 3 attempts with feedback)
                feedback = None
                previous_sql = None
                
                for attempt in range(self.max_retry_attempts):
                    logger.info(f"🔄 Attempt {attempt + 1}/{self.max_retry_attempts} with SQLEngine...")
                    
                    # Generate with SQLEngine (using enhanced question for follow-ups)
                    sql_query, confidence, metadata = self._generate_sql_with_nl_generator(
                        question_to_use,
                        feedback=feedback,
                        previous_sql=previous_sql
                    )
                    
                    if not sql_query:
                        logger.warning(f"⚠️ SQLEngine failed on attempt {attempt + 1}")
                        continue
                    
                    # Auto-correct table names if needed
                    corrected_sql, corrections = self._auto_correct_sql_tables(sql_query)
                    if corrections:
                        logger.info(f"🔧 Auto-corrected table names: {', '.join(corrections)}")
                        sql_query = corrected_sql
                        metadata['table_corrections'] = corrections
                    
                    # Pre-validate SQL structure before execution
                    is_valid, validation_error = self._validate_sql_structure(sql_query)
                    
                    if not is_valid:
                        logger.warning(f"⚠️ SQL validation failed on attempt {attempt + 1}: {validation_error}")
                        # Enhance feedback with correct schema info
                        if 'Unknown column' in str(validation_error) or "doesn't exist" in str(validation_error):
                            feedback = self._enhance_error_feedback(str(validation_error), sql_query)
                            logger.info(f"📋 Enhanced feedback with schema info for validation error")
                        else:
                            feedback = str(validation_error)
                        previous_sql = sql_query
                        continue
                    
                    # Execute validated query
                    results, error = self._execute_query_safe(sql_query)
                    
                    if error:
                        logger.warning(f"⚠️ Execution error on attempt {attempt + 1}: {error}")
                        # Enhance feedback with actual column names for column errors
                        if 'Unknown column' in str(error):
                            feedback = self._enhance_error_feedback(str(error), sql_query)
                            logger.info(f"📋 Enhanced feedback with schema info for column error")
                        else:
                            feedback = str(error)
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
                
                # If all SQLEngine attempts failed, fallback to LLM
                if not sql_query or confidence < 0.30:
                    logger.warning("⚠️ All SQLEngine attempts failed or very low confidence - falling back to LLM")
                    
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
                # Note: Session management is handled by the endpoint
                
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
        
        # Add source information (without emojis)
        source = metadata.get('source', 'generated')
        source_display = {
            'session_cache': 'Retrieved from session cache',
            'classified_queries': 'Retrieved from classified queries',
            'chat_history': 'Retrieved from chat history',
            'nl_to_sql_generator': 'Generated with SQL Engine',
            'sql_engine': 'Generated with SQL Engine',
            'llm_fallback': 'Generated with LLM'
        }.get(source, 'Generated')
        response_parts.append(f"*{source_display}*\n")
        
        # Add results in table format
        if not results:
            response_parts.append("No results found for your query.")
        else:
            # Show appropriate number of results
            display_limit = min(len(results), 200)
            display_results = results[:display_limit]
            
            response_parts.append(f"**Found {len(results)} result(s)** (showing first {display_limit}):\n")
            
            # Create markdown table
            if display_results:
                columns = list(display_results[0].keys())
                
                # Table header
                header = "| " + " | ".join(columns) + " |"
                separator = "| " + " | ".join(["---"] * len(columns)) + " |"
                
                table_rows = [header, separator]
                
                # Table data rows
                for row in display_results:
                    values = []
                    for col in columns:
                        val = row.get(col, '')
                        # Handle None and format values
                        if val is None:
                            val = ''
                        else:
                            val = str(val)
                            # Truncate long values
                            if len(val) > 50:
                                val = val[:47] + '...'
                        values.append(val)
                    table_rows.append("| " + " | ".join(values) + " |")
                
                response_parts.append("\n".join(table_rows))
        
        # Add SQL query
        response_parts.append(f"\n\n**SQL Query:**\n```sql\n{sql_query}\n```")
        
        # Add confidence (formatted percentage)
        response_parts.append(f"\n**Confidence:** {confidence:.0%}")
        
        return "\n".join(response_parts)
    
    def _create_error_response(self, error_message: str, session_id: Optional[str]) -> ChatResponse:
        """Create error response"""
        return ChatResponse(
            response=f"**Error:** {error_message}",
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
