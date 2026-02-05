"""
SQL Assistant Service - Convert natural language to SQL queries and execute them
Helps users query the database using plain English with validation and retry logic
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
from ..models.schemas import ChatRequest, ChatResponse, ChatbotType, SQLQueryRequest, SQLQueryResponse
from app.core.config import settings
from ..utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)


def extract_explicit_tables(question: str, available_tables: set) -> set:
    """
    Detect tables explicitly mentioned by the user.
    """
    q = question.lower()
    return {t for t in available_tables if t.lower() in q}


def extract_tables_from_sql(sql: str) -> set:
    """
    Extract table names from SQL (FROM / JOIN).
    """
    if not sql:
        return set()

    tables = set()
    tokens = sql.replace("\n", " ").split()
    for i, tok in enumerate(tokens):
        if tok.upper() in ("FROM", "JOIN") and i + 1 < len(tokens):
            tables.add(tokens[i + 1].strip(","))
    return tables


class SQLAssistantService:
    """
    Service for SQL query generation, execution, and validation
    Features:
    - Converts natural language to SQL
    - Executes queries on actual database
    - Validates results with confidence scoring
    - Retries with different strategies if needed
    - Returns formatted results only when confident
    - Dynamic schema loading to avoid token limits
    """
    
    def __init__(self):
        """Initialize SQL assistant service with database connection"""
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
        
        # LLM-as-Judge configuration for self-improving queries
        self.max_refinement_iterations = 3  # Maximum number of self-refinement loops
        self.judge_confidence_threshold = 0.90  # Stop iterating if judge confidence exceeds this
        
        # Initialize vector store for SQL examples
        try:
            from .vector_store_service import VectorStoreService
            self.vector_store = VectorStoreService()
            logger.info("✅ Vector store available for SQL examples")
        except Exception as e:
            logger.warning(f"⚠️ Vector store unavailable: {e}")
            self.vector_store = None
        
        # Initialize chat history service for comprehensive logging
        try:
            self.chat_history_service = ChatHistoryService(self.db_config)
            logger.info("✅ Chat history logging enabled")
        except Exception as e:
            logger.warning(f"⚠️ Chat history service unavailable: {e}")
            self.chat_history_service = None
        
        # Initialize query classification service for learning from labeled data
        try:
            from .query_classification_service import QueryClassificationService
            classification_storage = settings.DATA_DIR / "classification"
            self.classification_service = QueryClassificationService(classification_storage)
            logger.info("✅ Query classification service enabled")
        except Exception as e:
            logger.warning(f"⚠️ Query classification service unavailable: {e}")
            self.classification_service = None
        
        # Session-based query cache: stores successful queries per session
        self.session_query_cache: Dict[str, List[Dict[str, Any]]] = {}
        
        # Session-based corrections: stores user corrections per session
        self.session_corrections: Dict[str, Dict[str, Any]] = {}
        
        # Test database connection
        self.db_available = self._test_db_connection()
        
        # Load and cache available tables for validation
        self.available_tables = self._get_available_tables()
        logger.info(f"✅ Cached {len(self.available_tables)} available tables for validation")

        # Load external SQL assistant configuration (entities, tables, joins, temporal rules)
        self._load_sql_assistant_config()
        
        # Safe logging that handles None schema_parser
        table_count = len(self.schema_parser.get_table_names()) if self.schema_parser else 0
        logger.info(f"✅ SQL Assistant Service initialized | DB Available: {self.db_available} | Tables: {table_count}")

    
    def _load_schema_parser(self):
        """Load schema parser"""
        try:
            from ..utils.schema_parser import get_schema_parser
            parser = get_schema_parser()
            logger.info(f"✅ Loaded schema parser with {len(parser.get_table_names())} tables")
            return parser
        except Exception as e:
            logger.error(f"❌ Error loading schema parser: {e}")
            return None

    def _load_sql_assistant_config(self) -> None:
        """Load SQL assistant domain configuration from config/sql_assistant_config.json.

        This externalizes entity keywords, temporal indicators, entity→table mappings,
        and predefined joins so they can be tuned without changing code.
        """
        # Default empty structures; code will fall back to built-in mappings if these stay empty
        self.entity_keywords: Dict[str, List[str]] = {}
        self.operation_keywords: Dict[str, List[str]] = {}
        self.time_filter_keywords: List[str] = []
        self.temporal_indicators: Dict[str, List[str]] = {}
        self.entity_table_map_config: Dict[str, List[str]] = {}
        self.predefined_joins_config: List[Dict[str, Any]] = []

        try:
            # BASE_DIR/config/sql_assistant_config.json → derive from DATA_DIR
            config_dir = settings.DATA_DIR.parent / "config"
            config_path = config_dir / "sql_assistant_config.json"

            if not config_path.exists():
                logger.info(f"ℹ️ SQL assistant config not found at {config_path}, using built-in defaults")
                return

            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)

            self.entity_keywords = cfg.get("entity_keywords", {}) or {}
            self.operation_keywords = cfg.get("operation_keywords", {}) or {}
            self.time_filter_keywords = cfg.get("time_filter_keywords", []) or []
            self.temporal_indicators = cfg.get("temporal_indicators", {}) or {}
            self.entity_table_map_config = cfg.get("entity_tables", {}) or {}
            self.predefined_joins_config = cfg.get("predefined_joins", []) or []

            logger.info(f"✅ Loaded SQL assistant config from {config_path}")

        except Exception as e:
            logger.warning(f"⚠️ Failed to load SQL assistant config, using built-in defaults: {e}")
    
    def _get_available_tables(self) -> set:
        """Get set of all available tables from schema for fast validation"""
        try:
            if self.schema_parser:
                tables = set(self.schema_parser.get_table_names())
                return tables
            return set()
        except Exception as e:
            logger.error(f"❌ Error getting available tables: {e}")
            return set()
    
    def _get_table_columns(self, table_name: str) -> List[str]:
        """Get list of column names for a specific table"""
        try:
            if self.schema_parser and table_name in self.schema_parser.tables:
                columns = self.schema_parser.tables[table_name]
                return [col['field'] for col in columns]
            return []
        except Exception as e:
            logger.error(f"❌ Error getting columns for {table_name}: {e}")
            return []
    
    def _get_full_table_schema(self, table_name: str) -> str:
        """Get full schema with columns for a table"""
        try:
            if self.schema_parser:
                return self.schema_parser.get_table_schema(table_name)
            return ""
        except Exception as e:
            logger.error(f"❌ Error getting schema for {table_name}: {e}")
            return ""
    
    def _get_distinct_column_values(self, table_name: str, column_name: str, limit: int = 50) -> List[str]:
        """Query database to get actual distinct values for a column"""
        try:
            # Validate table and column exist first
            if not self._validate_table_exists(table_name):
                logger.warning(f"⚠️ Table {table_name} does not exist")
                return []
            
            if not self._validate_column_exists(table_name, column_name):
                logger.warning(f"⚠️ Column {column_name} does not exist in {table_name}")
                return []
            
            # Query for distinct values
            query = f"SELECT DISTINCT {column_name} FROM {table_name} WHERE {column_name} IS NOT NULL LIMIT {limit};"
            results, error = self._execute_query_safe(query)
            
            if error:
                logger.error(f"Error querying distinct values for {table_name}.{column_name}: {error}")
                return []
            
            # Extract values from results
            values = []
            for row in results:
                value = row.get(column_name)
                if value is not None:
                    values.append(str(value))
            
            logger.info(f"📊 Found {len(values)} distinct values for {table_name}.{column_name}: {values[:10]}")
            return values
            
        except Exception as e:
            logger.error(f"Error getting distinct values for {table_name}.{column_name}: {e}")
            return []
    
    def _extract_where_conditions(self, sql_query: str) -> List[tuple]:
        """Extract column=value conditions from WHERE clause"""
        try:
            import re
            
            # Find WHERE clause
            where_match = re.search(r'WHERE\s+(.+?)(?:GROUP BY|ORDER BY|LIMIT|HAVING|;|$)', sql_query, re.IGNORECASE | re.DOTALL)
            if not where_match:
                return []
            
            where_clause = where_match.group(1)
            
            # Extract simple equality conditions: column = 'value' or column = "value"
            # Pattern: column_name = 'value' or table.column = 'value'
            pattern = r"([\w.]+)\s*=\s*['\"]([ ^'\"]+)['\"]"
            matches = re.findall(pattern, where_clause, re.IGNORECASE)
            
            conditions = []
            for col_ref, value in matches:
                # Remove table alias if present (e.g., bm.status -> status)
                if '.' in col_ref:
                    col_name = col_ref.split('.')[-1]
                else:
                    col_name = col_ref
                
                conditions.append((col_name.upper(), value))
            
            return conditions
            
        except Exception as e:
            logger.error(f"Error extracting WHERE conditions: {e}")
            return []
    
    def _validate_query_values(self, sql_query: str) -> tuple[bool, List[dict]]:
        """Validate that values in WHERE clause actually exist in the database"""
        try:
            # Extract table names to know which tables are being queried
            tables = self._extract_tables_from_sql(sql_query)
            if not tables:
                return True, []  # No tables, can't validate
            
            # Extract WHERE conditions
            conditions = self._extract_where_conditions(sql_query)
            if not conditions:
                return True, []  # No WHERE conditions, nothing to validate
            
            invalid_values = []
            
            # For each condition, check if the value exists in the column
            for column_name, filter_value in conditions:
                # Try to find which table this column belongs to
                table_found = None
                for table in tables:
                    if self._validate_column_exists(table, column_name):
                        table_found = table
                        break
                
                if not table_found:
                    continue  # Column validation will catch this
                
                # Get actual distinct values from the database
                actual_values = self._get_distinct_column_values(table_found, column_name)
                
                if actual_values:
                    # Check if filter value exists in actual values (case-insensitive)
                    actual_values_upper = [v.upper() for v in actual_values]
                    if filter_value.upper() not in actual_values_upper:
                        invalid_values.append({
                            'table': table_found,
                            'column': column_name,
                            'filter_value': filter_value,
                            'actual_values': actual_values[:20]  # Limit to 20 for display
                        })
            
            if invalid_values:
                logger.warning(f"⚠️ Query uses filter values that don't exist in database: {len(invalid_values)} issues")
                for issue in invalid_values:
                    logger.warning(f"  ❌ {issue['table']}.{issue['column']} = '{issue['filter_value']}' (not found)")
                    logger.warning(f"     ✓ Actual values: {issue['actual_values']}")
                return False, invalid_values
            
            return True, []
            
        except Exception as e:
            logger.error(f"Error validating query values: {e}")
            return True, []  # Don't block on validation errors
    
    def _validate_column_exists(self, table_name: str, column_name: str) -> bool:
        """Check if a column exists in a specific table"""
        columns = self._get_table_columns(table_name)
        return column_name in columns
    
    def _extract_columns_from_sql(self, sql_query: str) -> Dict[str, List[str]]:
        """Extract columns referenced in SQL query grouped by table"""
        import re
        column_refs = {}
        
        # Extract table aliases first
        alias_pattern = r'FROM\s+(\w+)\s+(?:AS\s+)?(\w+)|JOIN\s+(\w+)\s+(?:AS\s+)?(\w+)'
        aliases = {}  # alias -> table_name
        for match in re.finditer(alias_pattern, sql_query, re.IGNORECASE):
            if match.group(1):  # FROM clause
                table = match.group(1)
                alias = match.group(2) if match.group(2) else table
                aliases[alias] = table
            elif match.group(3):  # JOIN clause
                table = match.group(3)
                alias = match.group(4) if match.group(4) else table
                aliases[alias] = table
        
        # Extract column references (table.column or alias.column)
        column_pattern = r'(\w+)\.(\w+)'
        for match in re.finditer(column_pattern, sql_query):
            table_or_alias = match.group(1)
            column = match.group(2)
            
            # Resolve alias to actual table name
            table_name = aliases.get(table_or_alias, table_or_alias)
            
            if table_name not in column_refs:
                column_refs[table_name] = []
            if column not in column_refs[table_name]:
                column_refs[table_name].append(column)
        
        return column_refs
    
    def _validate_sql_columns(self, sql_query: str) -> Tuple[bool, List[str]]:
        """Validate that all columns in SQL query exist in their respective tables"""
        column_refs = self._extract_columns_from_sql(sql_query)
        invalid_columns = []
        
        for table_name, columns in column_refs.items():
            if not self._validate_table_exists(table_name):
                continue  # Table validation will catch this
            
            for column in columns:
                if not self._validate_column_exists(table_name, column):
                    invalid_columns.append(f"{table_name}.{column}")
        
        if invalid_columns:
            logger.warning(f"⚠️ SQL uses non-existent columns: {invalid_columns}")
            return False, invalid_columns
        
        return True, []
    
    def _validate_table_exists(self, table_name: str) -> bool:
        """Check if a table actually exists in the database schema"""
        return table_name in self.available_tables
    
    def _extract_tables_from_sql(self, sql_query: str) -> List[str]:
        """Extract table names from SQL query"""
        import re
        # Match FROM and JOIN clauses
        patterns = [
            r'FROM\s+([`\"]?(\w+)[`\"]?)',
            r'JOIN\s+([`\"]?(\w+)[`\"]?)',
            r'INTO\s+([`\"]?(\w+)[`\"]?)'
        ]
        
        tables = []
        for pattern in patterns:
            matches = re.findall(pattern, sql_query, re.IGNORECASE)
            for match in matches:
                # match is a tuple, get the table name (second group)
                table = match[1] if len(match) > 1 else match[0]
                tables.append(table)
        
        return list(set(tables))
    
    def _validate_sql_tables(self, sql_query: str) -> Tuple[bool, List[str]]:
        """
        Validate that all tables in SQL query actually exist.
        
        Returns:
            Tuple of (all_valid, invalid_tables)
        """
        tables_in_query = self._extract_tables_from_sql(sql_query)
        invalid_tables = [t for t in tables_in_query if not self._validate_table_exists(t)]
        
        if invalid_tables:
            logger.warning(f"⚠️ SQL uses non-existent tables: {invalid_tables}")
            return False, invalid_tables
        
        return True, []
    
    def _find_similar_valid_tables(self, invalid_table: str, limit: int = 3) -> List[str]:
        from difflib import get_close_matches
        similar = get_close_matches(invalid_table, list(self.available_tables), n=limit, cutoff=0.6)
        return similar
    
    def _find_sql_examples(self, question: str, top_k: int = 3) -> List[Dict[str, Any]]:
        """
        Search vector store for similar SQL queries from codebase
        Returns relevant SQL file examples that can help generate better queries
        """
        if not self.vector_store:
            return []
        
        try:
            # Generate embedding for the question
            query_embedding = self.llm_service.generate_embedding(question)
            
            # Search for SQL code files
            results = self.vector_store.search(
                query_embedding=query_embedding,
                top_k=top_k * 2,  # Get more, then filter
                filter_metadata={'type': 'code', 'language': 'sql'},
                min_similarity=0.4
            )
            
            # Extract SQL examples
            sql_examples = []
            for result in results[:top_k]:
                doc = result.get('document', {})
                metadata = doc.get('metadata', {})
                content = doc.get('content', '')
                
                # Extract actual SQL from the content
                sql_lines = [line for line in content.split('\n') if line.strip() and not line.strip().startswith('--')]
                sql_code = '\n'.join(sql_lines)
                
                if sql_code and len(sql_code) > 20:
                    sql_examples.append({
                        'filename': metadata.get('filename', 'unknown'),
                        'sql': sql_code[:500],  # Limit length
                        'similarity': result.get('similarity', 0),
                        'context': metadata.get('chunk_context', {})
                    })
            
            if sql_examples:
                logger.info(f"📚 Found {len(sql_examples)} similar SQL examples from codebase")
            
            return sql_examples
            
        except Exception as e:
            logger.warning(f"⚠️ Error searching SQL examples: {e}")
            return []
    
    def _classify_query_intent(self, query: str) -> Dict[str, Any]:
        """
        Classify the intent and entities in the user's query.
        Helps identify which tables and columns are needed.
        
        Returns:
            {
                'intent': 'count' | 'retrieve' | 'aggregate' | 'filter' | 'metadata',
                'entities': ['bin', 'order', 'sku', 'bot'],
                'operations': ['count', 'sum', 'average'],
                'time_filter': True/False,
                'join_needed': True/False,
                'is_metadata_query': True/False
            }
        """
        query_lower = query.lower()
        
        # Check if this is a METADATA query (about schema, not data)
        is_metadata_query = any(phrase in query_lower for phrase in [
            'column names', 'columns in', 'columns available', 'what columns',
            'describe table', 'show columns', 'table structure', 'schema of',
            'fields in', 'list columns', 'show fields', 'what fields',
            'show me all the column', 'show me all column'
        ])
        
        # Detect intent
        intent = 'retrieve'  # default
        if is_metadata_query:
            intent = 'metadata'
        elif any(word in query_lower for word in ['how many', 'count', 'number of', 'total']):
            intent = 'count'
        elif any(word in query_lower for word in ['sum', 'total quantity', 'total amount']):
            intent = 'aggregate'
        elif any(word in query_lower for word in ['average', 'mean', 'avg']):
            intent = 'aggregate'
        elif any(word in query_lower for word in ['show', 'list', 'get', 'display', 'details']):
            intent = 'retrieve'
        
        # Detect entities (domain concepts) - comprehensive mapping based on actual schema
        entities = []
        entity_map = {
            # Bin and location management (14 tables)
            'bin': ['bin', 'bins', 'location', 'locations', 'zone', 'zones', 'aisle', 'rack', 
                   'bin_info', 'bin_configuration', 'bin_loading', 'bin_velocity', 'bin_mapping'],
            
            # Bot and robot operations (9 tables)
            'bot': ['bot', 'bots', 'robot', 'robots', 'agv', 'charging', 'battery', 
                   'bot_master', 'robot_charge', 'bot_velocity', 'bot_alarm'],
            
            # Order management (17 tables)
            'order': ['order', 'orders', 'shipment', 'delivery', 'order_master', 
                     'order_mapping', 'order_bin', 'order_detail', 'order_line'],
            
            # Wave operations (30 tables)
            'wave': ['wave', 'waves', 'pick_wave', 'put_wave', 'wave_order', 
                    'wave_station', 'wave_rule', 'wave_mapping', 'wave_detail'],
            
            # SKU and article management (13 tables)
            'sku': ['sku', 'article', 'product', 'item', 'sku_master', 
                   'article_proximity', 'sku_recommendations', 'sku_velocity'],
            
            # Inventory management (13 tables)
            'inventory': ['inventory', 'stock', 'live_inventory', 'stock_audit', 
                         'stock_location', 'stock_movement', 'inventory_master'],
            
            # Pick operations (11 tables)
            'pick': ['pick', 'picks', 'picking', 'picker', 'pick_wave', 'pick_task', 
                    'pick_station', 'pick_order', 'pick_detail', 'pick_bin'],
            
            # Put operations (12 tables)
            'put': ['put', 'puts', 'putting', 'putaway', 'put_wave', 'put_task', 
                   'put_station', 'put_order', 'put_detail', 'put_bin'],
            
            # Station operations (5 tables)
            'station': ['station', 'stations', 'workstation', 'hw_station', 
                       'station_master', 'station_pick', 'station_put', 'station_rule'],
            
            # Task management (13 tables)
            'task': ['task', 'tasks', 'job', 'jobs', 'task_master', 'pick_task', 
                    'put_task', 'maintenance_task', 'task_mapping'],
            
            # Alarms and errors (9 tables)
            'alarm': ['alarm', 'alarms', 'alert', 'alerts', 'error', 'errors', 
                     'alarm_master', 'bot_alarm', 'integration_error'],
            
            # Maintenance operations (5 tables)
            'maintenance': ['maintenance', 'repair', 'service', 'maintenance_task', 
                           'maintenance_log', 'maintenance_schedule'],
            
            # User management (4 tables)
            'user': ['user', 'users', 'operator', 'picker', 'packer', 'user_master', 
                    'user_rule', 'user_mapping'],
            
            # Dashboard and monitoring (28 tables)
            'dashboard': ['dashboard', 'monitor', 'monitoring', 'dashboard_bot', 
                         'dashboard_order', 'dashboard_inventory'],
            
            # Charging operations (4 tables)
            'charging': ['charging', 'charge', 'battery', 'robot_charge', 
                        'charging_station', 'charging_log'],
            
            # Conveyor systems (2 tables)
            'conveyor': ['conveyor', 'conveyors', 'conveyor_system', 'conveyor_configuration'],
            
            # Logs and audit trail (38 tables)
            'log': ['log', 'logs', 'history', 'audit', 'tracking', 'trace', 
                   'alarm_log', 'charge_log', 'integration_log', 'bot_log'],
            
            # Master data tables (44 tables)
            'master': ['master', 'config', 'configuration', 'setting', 'settings', 
                      'rule', 'rules', 'mapping', 'api_master', 'zone_master'],
            
            # Analysis and velocity (7 tables)
            'velocity': ['velocity', 'speed', 'frequency', 'analysis', 'bin_velocity', 
                        'bot_velocity', 'sku_velocity', 'velocity_analysis'],
        }
        
        for entity, keywords in entity_map.items():
            if any(kw in query_lower for kw in keywords):
                entities.append(entity)
        
        # Detect if JOIN might be needed
        join_needed = len(entities) > 1 or any(phrase in query_lower for phrase in [
            'with', 'and', 'along with', 'including', 'details of'
        ])
        
        # Detect operations
        operations = []
        if 'count' in query_lower or 'how many' in query_lower:
            operations.append('count')
        if 'sum' in query_lower or 'total' in query_lower:
            operations.append('sum')
        if 'average' in query_lower or 'avg' in query_lower:
            operations.append('average')
        if 'group' in query_lower or 'by' in query_lower:
            operations.append('group_by')
        
        # Detect time filter
        time_filter = any(word in query_lower for word in [
            'today', 'yesterday', 'week', 'month', 'year', 'recent', 'last', 'past'
        ])
        
        # Detect temporal scope (historical vs current)
        temporal_scope = self._classify_temporal_scope(query)
        
        return {
            'intent': intent,
            'entities': entities,
            'operations': operations,
            'time_filter': time_filter,
            'join_needed': join_needed,
            'is_metadata_query': is_metadata_query,
            'temporal_scope': temporal_scope  # NEW: historical vs current
        }
    
    def _classify_temporal_scope(self, query: str) -> Dict[str, Any]:
        """
        Classify whether query needs historical log tables or current state tables.
        
        CRITICAL BUSINESS LOGIC:
        - Historical queries (e.g., "all tasks performed till now") → Use *_log tables
        - Current queries (e.g., "what is bot doing now") → Use regular tables
        
        Returns:
            {
                'scope': 'historical' | 'current' | 'both',
                'confidence': 0.0-1.0,
                'indicators': [list of matching keywords],
                'table_preference': 'log' | 'current' | 'both'
            }
        """
        query_lower = query.lower()
        
        # Historical indicators - strong signals for log tables
        historical_indicators = [
            # Explicit log references
            'check the log', 'from log', 'in the log', 'log table', 'historical',
            
            # Past tense and completion
            'have done', 'has done', 'have performed', 'has performed', 
            'have completed', 'has completed', 'was doing', 'were doing',
            'did', 'performed', 'completed', 'finished',
            
            # Time range indicators
            'till now', 'till today', 'till date', 'until now', 'up to now',
            'since', 'from', 'between', 'in the past', 'previously',
            'all the task performed', 'all task done', 'all tasks executed',
            
            # Aggregate history
            'total', 'all time', 'ever', 'lifetime', 'complete history',
            'how many times', 'number of times', 'count of',
            
            # Audit/tracking
            'audit', 'track', 'trace', 'history of', 'record of'
        ]
        
        # Current state indicators - signals for live tables
        current_indicators = [
            # Present tense
            'is doing', 'are doing', 'is performing', 'are performing',
            'is running', 'are running', 'is executing', 'are executing',
            
            # Current state
            'current', 'currently', 'now', 'right now', 'at the moment',
            'present', 'today', 'active', 'ongoing', 'in progress',
            
            # Assignment/allocation
            'assigned to', 'allocated to', 'working on',
            
            # Latest/recent
            'latest', 'most recent', 'newest', 'last assigned'
        ]
        
        # Count matches
        historical_matches = [ind for ind in historical_indicators if ind in query_lower]
        current_matches = [ind for ind in current_indicators if ind in query_lower]
        
        # Determine scope
        historical_score = len(historical_matches)
        current_score = len(current_matches)
        
        if historical_score > current_score:
            scope = 'historical'
            table_preference = 'log'
            confidence = min(0.95, 0.6 + (historical_score * 0.1))
        elif current_score > historical_score:
            scope = 'current'
            table_preference = 'current'
            confidence = min(0.95, 0.6 + (current_score * 0.1))
        elif historical_score == current_score and historical_score > 0:
            scope = 'both'
            table_preference = 'both'
            confidence = 0.5
        else:
            # No clear indicators - default based on verb tense
            if any(word in query_lower for word in ['has', 'have', 'had', 'was', 'were', 'did']):
                scope = 'historical'
                table_preference = 'log'
                confidence = 0.4
            else:
                scope = 'current'
                table_preference = 'current'
                confidence = 0.5
        
        return {
            'scope': scope,
            'confidence': confidence,
            'historical_indicators': historical_matches,
            'current_indicators': current_matches,
            'table_preference': table_preference
        }
    
    def _build_temporal_table_guidance(self, temporal_info: Dict[str, Any], query: str) -> str:
        """
        Build guidance for LLM about which table types to use based on temporal scope.
        
        CRITICAL: Routes queries to appropriate tables (log vs current)
        """
        if not temporal_info:
            return ""
        
        scope = temporal_info.get('scope', 'current')
        preference = temporal_info.get('table_preference', 'current')
        confidence = temporal_info.get('confidence', 0.5)
        
        guidance_parts = []
        
        if scope == 'historical' and confidence > 0.6:
            guidance_parts.append("\n" + "="*80)
            guidance_parts.append("🕐 TEMPORAL SCOPE DETECTED: HISTORICAL/PAST QUERY")
            guidance_parts.append("="*80)
            guidance_parts.append("\n⚠️⚠️⚠️ CRITICAL TABLE SELECTION RULE ⚠️⚠️⚠️")
            guidance_parts.append(f"User Query: \"{query}\"")
            guidance_parts.append(f"\nDetected indicators: {', '.join(temporal_info.get('historical_indicators', []))}")
            guidance_parts.append(f"\n✅ USE LOG/HISTORICAL TABLES for this query:")
            guidance_parts.append("   - task_detail_log (NOT task_detail) → For ALL tasks performed till now")
            guidance_parts.append("   - bot_master_log (NOT bot_master) → For historical bot states")
            guidance_parts.append("   - bin_info_master_log → For historical bin states")
            guidance_parts.append("   - order_line_log → For historical order data")
            guidance_parts.append("   - alarm_log → For historical alarms")
            guidance_parts.append("   - charge_log → For historical charging data")
            guidance_parts.append("\n❌ DO NOT use current state tables like:")
            guidance_parts.append("   - task_detail (only shows current/active tasks)")
            guidance_parts.append("   - bot_master (only shows current bot state)")
            guidance_parts.append("\n💡 REASON: User asked for COMPLETE HISTORY, not just current state")
            guidance_parts.append(f"   Confidence: {confidence:.0%}")
            guidance_parts.append("="*80 + "\n")
            
        elif scope == 'current' and confidence > 0.6:
            guidance_parts.append("\n" + "="*80)
            guidance_parts.append("⏱️ TEMPORAL SCOPE DETECTED: CURRENT STATE QUERY")
            guidance_parts.append("="*80)
            guidance_parts.append("\n⚠️⚠️⚠️ CRITICAL TABLE SELECTION RULE ⚠️⚠️⚠️")
            guidance_parts.append(f"User Query: \"{query}\"")
            guidance_parts.append(f"\nDetected indicators: {', '.join(temporal_info.get('current_indicators', []))}")
            guidance_parts.append(f"\n✅ USE CURRENT STATE TABLES for this query:")
            guidance_parts.append("   - task_detail → For current/active tasks")
            guidance_parts.append("   - bot_master → For current bot states")
            guidance_parts.append("   - bin_info_master → For current bin states")
            guidance_parts.append("   - live_inventory_master → For current inventory")
            guidance_parts.append("\n❌ DO NOT use log tables unless specifically asked:")
            guidance_parts.append("   - Avoid task_detail_log (contains all historical data, will be slow)")
            guidance_parts.append("\n💡 REASON: User asked for CURRENT/ACTIVE state only")
            guidance_parts.append(f"   Confidence: {confidence:.0%}")
            guidance_parts.append("="*80 + "\n")
            
        elif scope == 'both':
            guidance_parts.append("\n📊 TEMPORAL SCOPE: Query may need BOTH current and historical data")
            guidance_parts.append("   → Consider using UNION or separate queries for current + historical")
        
        # Add common log table mappings
        if preference == 'log':
            guidance_parts.append("\n📋 COMMON TABLE MAPPINGS (Current → Log):")
            guidance_parts.append("   • task_detail → task_detail_log")
            guidance_parts.append("   • bot_master → bot_master_log")
            guidance_parts.append("   • bin_info_master → bin_info_master_log")
            guidance_parts.append("   • order data → order_line_log")
            guidance_parts.append("   • alarms → alarm_log")
            guidance_parts.append("   • charging → charge_log\n")
        
        return "\n".join(guidance_parts) if guidance_parts else ""
    
    def _get_tables_for_entities(self, entities: List[str]) -> Dict[str, List[str]]:
        """
        Map domain entities to actual database tables.
        
        Args:
            entities: List of domain concepts ['bin', 'order', 'sku']
            
        Returns:
            Dict mapping entity to list of relevant tables
        """
        # Comprehensive entity to table mapping (based on actual schema - 162 tables)
        entity_table_map = {
            # Bin and location management (14 tables)
            'bin': [
                'bin_configuration',
                'bin_info_master',
                'live_inventory_master',
                'order_bin_mapping',
                'bin_velocity_scores',
                'location_master',
                'location_block_master',
                'bin_loading_wave_order_master',
                'order_bin_task_master',
                'store_bin_master'
            ],
            
            # Bot and robot operations (9 tables)
            'bot': [
                'bot_master',
                'bot_master_log',
                'bot_alarm_log',
                'bot_charging_bit_log',
                'dashboard_bot_master',
                'robot_charge_log',
                'dashboard_log_bot_charging',
                'bot_manual_alarm_log'
            ],
            
            # Order management (17 tables)
            'order': [
                'wms_to_wcs_order_line_request_data',
                'order_bin_mapping',
                'pick_wave_order_master',
                'put_wave_order_master',
                'bin_loading_wave_order_master',
                'stock_audit_wave_order_master',
                'order_bin_task_master',
                'lpn_pick_wave_order_mapping',
                'order_bin_mapping_log'
            ],
            
            # Wave operations (29 tables)
            'wave': [
                'pick_wave_order_master',
                'put_wave_order_master',
                'bin_loading_wave_order_master',
                'stock_audit_wave_order_master',
                'pick_wave_wms_data',
                'put_wave_wms_data',
                'wave_station_rule_mapping',
                'dashboard_log_wave_process',
                'lpn_pick_wave_order_mapping',
                'short_pick_wave_reason',
                'short_put_wave_reason'
            ],
            
            # SKU and article management (13 tables)
            'sku': [
                'sku_master',
                'articles_registered',
                'article_registered',
                'article_proximity_score',
                'sku_recommendations',
                'sku_velocity_scores',
                'sku_velocity_history',
                'sku_batch_master',
                'sku_ean_mapping',
                'live_inventory_master'
            ],
            
            # Inventory management (13 tables)
            'inventory': [
                'live_inventory_master',
                'live_inventory_master_log',
                'stock_audit_bin_data_push',
                'stock_audit_bin_segments',
                'stock_audit_list',
                'stock_audit_wave_order_master',
                'stock_audit_wave_wms_data',
                'lpn_master_stock_audit'
            ],
            
            # Pick operations (11 tables)
            'pick': [
                'pick_wave_order_master',
                'station_pick_task_master',
                'pick_wave_wms_data',
                'lpn_pick_wave_order_mapping',
                'pick_rule_master',
                'recovery_pick_task_master',
                'short_pick_wave_reason'
            ],
            
            # Put/Putaway operations (7 tables)
            'put': [
                'put_wave_order_master',
                'put_wave_wms_data',
                'short_put_wave_reason',
                'put_wave_order_master_archive',
                'put_wave_wms_data_archive'
            ],
            
            # Station operations (5 tables)
            'station': [
                'hw_station_master',
                'station_pick_task_master',
                'hw_charging_station_master',
                'station_home_master',
                'wave_station_rule_mapping'
            ],
            
            # Task management (13 tables)
            'task': [
                'station_pick_task_master',
                'maintenance_task_master',
                'dashboard_log_maintenance_task_master',
                'order_bin_task_master',
                'recovery_pick_task_master',
                'task_master',
                'task_detail',
                'dashboard_manual_task_master',
                'mining_job_logs',
                'velocity_calculation_jobs'
            ],
            
            # Alarms and errors (9 tables)
            'alarm': [
                'alarm_master',
                'bot_alarm_log',
                'bot_manual_alarm_log',
                'integration_error_logs',
                'dashboard_log_error_api',
                'maintenance_alarm_logs',
                'manual_alarm_master',
                'pseudo_bot_alarm_log'
            ],
            
            # Maintenance operations (5 tables)
            'maintenance': [
                'maintenance_task_master',
                'dashboard_log_maintenance_task_master',
                'hw_maintenance_master',
                'maintenance_alarm_logs',
                'hw_maintenance_scanner_multiplexer_master'
            ],
            
            # User management (4 tables)
            'user': [
                'dashboard_user_master',
                'dashboard_user_role_setting_mapping',
                'dashboard_log_user_login_attempts',
                'dashboard_table_header_json_user_mapping'
            ],
            
            # Dashboard and monitoring (28 tables - top 10 most relevant)
            'dashboard': [
                'dashboard_bot_master',
                'dashboard_log_bot_charging',
                'dashboard_log_maintenance_task_master',
                'dashboard_log_wave_process',
                'dashboard_log_error_api',
                'dashboard_config',
                'dashboard_user_master',
                'dashboard_master_data',
                'dashboard_menu_master',
                'dashboard_access_master'
            ],
            
            # Charging operations (4 tables)
            'charging': [
                'robot_charge_log',
                'bot_charging_bit_log',
                'dashboard_log_bot_charging',
                'hw_charging_station_master'
            ],
            
            # Conveyor systems (2 tables)
            'conveyor': [
                'hw_conveyor_master',
                'hw_conveyor_mux_master'
            ],
            
            # Logs and audit trail (38 tables - top 12 most relevant)
            'log': [
                'bot_alarm_log',
                'bot_master_log',
                'bot_charging_bit_log',
                'robot_charge_log',
                'live_inventory_master_log',
                'order_bin_mapping_log',
                'task_master_log',
                'task_detail_log',
                'mining_job_logs',
                'sku_velocity_log',
                'integration_error_logs',
                'dashboard_log_wave_process'
            ],
            
            # Master data tables (73 tables - top 15 most important)
            'master': [
                'bot_master',
                'sku_master',
                'bin_info_master',
                'alarm_master',
                'config_master',
                'location_master',
                'hw_station_master',
                'api_master',
                'task_master',
                'maintenance_task_master',
                'pick_rule_master',
                'zone_master',
                'category_master',
                'sku_batch_master',
                'store_bin_master'
            ],
            
            # Velocity and analysis (7 tables)
            'velocity': [
                'sku_velocity_scores',
                'bin_velocity_scores',
                'sku_velocity_history',
                'sku_velocity_log',
                'sku_velocity_state',
                'velocity_calculation_config',
                'velocity_calculation_jobs'
            ],
        }
        
        result = {}
        for entity in entities:
            if entity in entity_table_map:
                result[entity] = entity_table_map[entity]
        
        return result
    
    def _get_join_paths(self, tables: List[str]) -> List[Dict[str, Any]]:
        """
        INTELLIGENT JOIN PATH DETECTION - Three-tier strategy:
        
        TIER 1: Experience-based predefined relationships (highest priority)
        TIER 2: Automatic FK discovery from database schema
        TIER 3: LLM-based implicit JOIN detection for complex queries
        
        Args:
            tables: List of table names that need to be joined
            
        Returns:
            List of JOIN path dictionaries with confidence scores
        """
        all_join_paths = []
        
        # ========================================================================
        # TIER 1: EXPERIENCE-BASED PREDEFINED JOINS (Highest Confidence: 0.95)
        # ========================================================================
        # These are battle-tested JOIN patterns from production experience
        predefined_relationships = [
            {
                'table1': 'wms_to_wcs_order_line_request_data',
                'table2': 'sku_master',
                'join_on': 'ARTICLE_ID = SKU_ID',
                'description': 'Orders to SKU details',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'order_bin_mapping',
                'table2': 'bin_info_master',
                'join_on': 'BIN_ID = BIN_ID',
                'description': 'Order-Bin mapping to bin details',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'bin_info_master',
                'table2': 'bin_configuration',
                'join_on': 'BIN_BARCODE = bin_id',
                'description': 'Bin info to bin configuration',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'live_inventory_master',
                'table2': 'sku_master',
                'join_on': 'ARTICLE_ID = SKU_ID',
                'description': 'Inventory to SKU details',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'bot_master',
                'table2': 'bot_alarm_log',
                'join_on': 'BOT_ID = BOT_ID',
                'description': 'Bots to their alarms',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'dashboard_log_maintenance_task_master',
                'table2': 'bot_master',
                'join_on': 'MAINTENANCE_POINT_BOT_ID = BOT_ID',
                'description': 'Maintenance tasks to bots',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'task_detail',
                'table2': 'bot_master',
                'join_on': 'BOT_ID = BOT_ID',
                'description': 'Tasks to bots',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'task_detail_log',
                'table2': 'bot_master',
                'join_on': 'BOT_ID = BOT_ID',
                'description': 'Historical tasks to bots',
                'confidence': 0.95,
                'source': 'predefined'
            },
            {
                'table1': 'bin_info_master',
                'table2': 'location_master',
                'join_on': 'ZONE_ID = ZONE_ID',
                'description': 'Bins to locations via zone',
                'confidence': 0.90,
                'source': 'predefined'
            },
            {
                'table1': 'live_inventory_master',
                'table2': 'bin_info_master',
                'join_on': 'BIN_ID = BIN_ID',
                'description': 'Inventory to bins',
                'confidence': 0.95,
                'source': 'predefined'
            },
        ]
        
        # Check predefined relationships
        for join in predefined_relationships:
            if join['table1'] in tables and join['table2'] in tables:
                all_join_paths.append(join)
                logger.debug(f"✅ TIER 1: Found predefined join {join['table1']} → {join['table2']}")
        
        # ========================================================================
        # TIER 2: AUTOMATIC FK DISCOVERY FROM SCHEMA (Medium Confidence: 0.75)
        # ========================================================================
        discovered_joins = self._discover_joins_from_schema(tables)
        for join in discovered_joins:
            # Check if not already in predefined (avoid duplicates)
            is_duplicate = any(
                p['table1'] == join['table1'] and p['table2'] == join['table2']
                for p in all_join_paths
            )
            if not is_duplicate:
                all_join_paths.append(join)
                logger.debug(f"✅ TIER 2: Discovered FK join {join['table1']} → {join['table2']}")
        
        # ========================================================================
        # TIER 3: LLM-BASED IMPLICIT JOIN DETECTION (Lower Confidence: 0.60)
        # ========================================================================
        # Only use for complex queries where TIER 1 & 2 didn't find enough paths
        if len(all_join_paths) < len(tables) - 1:  # Need at least N-1 joins for N tables
            llm_joins = self._detect_implicit_joins_with_llm(tables)
            for join in llm_joins:
                # Check if not already found
                is_duplicate = any(
                    p['table1'] == join['table1'] and p['table2'] == join['table2']
                    for p in all_join_paths
                )
                if not is_duplicate:
                    all_join_paths.append(join)
                    logger.debug(f"✅ TIER 3: LLM detected join {join['table1']} → {join['table2']}")
        
        # Sort by confidence (highest first)
        all_join_paths.sort(key=lambda x: x.get('confidence', 0.5), reverse=True)
        
        if all_join_paths:
            logger.info(f"🔗 Found {len(all_join_paths)} JOIN paths using all tiers")
        
        return all_join_paths
    
    def _discover_joins_from_schema(self, tables: List[str]) -> List[Dict[str, Any]]:
        """
        TIER 2: Discover JOIN relationships from database schema.
        
        Uses column name matching patterns:
        - *_ID columns likely join with ID columns
        - Same column names in different tables likely join
        
        Returns:
            List of discovered JOIN paths with confidence scores
        """
        discovered_joins = []
        
        try:
            if not self.schema_parser:
                return discovered_joins
            
            # For each pair of tables, find matching columns
            for i, table1 in enumerate(tables):
                for table2 in tables[i+1:]:
                    # Get columns for both tables
                    cols1 = self.schema_parser.tables.get(table1, [])
                    cols2 = self.schema_parser.tables.get(table2, [])
                    
                    if not cols1 or not cols2:
                        continue
                    
                    col1_names = {c['field']: c for c in cols1}
                    col2_names = {c['field']: c for c in cols2}
                    
                    # Strategy 1: Exact column name match
                    common_cols = set(col1_names.keys()) & set(col2_names.keys())
                    for col in common_cols:
                        # Prioritize ID columns
                        if 'ID' in col or col.endswith('_id'):
                            discovered_joins.append({
                                'table1': table1,
                                'table2': table2,
                                'join_on': f'{col} = {col}',
                                'description': f'Auto-discovered via matching column: {col}',
                                'confidence': 0.80,
                                'source': 'schema_discovery'
                            })
                            break  # One join per table pair
                    
                    # Strategy 2: Foreign key pattern (table1.TABLE2_ID = table2.ID)
                    for col1_name, col1_info in col1_names.items():
                        # Check if col1 references table2 (e.g., BOT_ID in task_detail → BOT_ID in bot_master)
                        if col1_name in col2_names:
                            # Check if it's a key column
                            if col2_names[col1_name].get('key') == 'PRI' or 'ID' in col1_name:
                                discovered_joins.append({
                                    'table1': table1,
                                    'table2': table2,
                                    'join_on': f'{col1_name} = {col1_name}',
                                    'description': f'Auto-discovered FK pattern: {col1_name}',
                                    'confidence': 0.75,
                                    'source': 'schema_discovery'
                                })
                                break
            
            if discovered_joins:
                logger.info(f"📊 Schema discovery found {len(discovered_joins)} potential JOINs")
            
        except Exception as e:
            logger.warning(f"⚠️ Schema-based JOIN discovery failed: {e}")
        
        return discovered_joins
    
    def _detect_implicit_joins_with_llm(self, tables: List[str]) -> List[Dict[str, Any]]:
        """
        TIER 3: Use LLM to detect implicit JOIN paths for complex queries.
        
        This handles cases where:
        - Tables need multi-hop joins (A→B→C)
        - Relationships aren't obvious from column names
        - Business logic requires specific join patterns
        
        Returns:
            List of LLM-suggested JOIN paths with lower confidence
        """
        llm_joins = []
        
        try:
            if len(tables) < 2:
                return llm_joins
            
            # Get schema info for these tables
            table_schemas = {}
            for table in tables:
                cols = self.schema_parser.tables.get(table, [])
                col_list = [f"{c['field']} ({c['type']})" for c in cols[:10]]
                table_schemas[table] = col_list
            
            # Ask LLM to find JOIN paths
            llm_prompt = f"""Analyze these database tables and identify how they should be joined.

**Tables to join:** {', '.join(tables)}

**Table Schemas:**
{chr(10).join([f'{t}: {", ".join(cols)}' for t, cols in table_schemas.items()])}

**Task:** Identify JOIN relationships between these tables.

**Rules:**
- Only suggest JOINs where column names/types match
- Prefer ID columns for joins
- Consider multi-hop paths if needed (A→B→C)
- Return ONLY valid, executable JOIN conditions

**Respond in JSON format:**
{{
    "joins": [
        {{
            "table1": "table_name_1",
            "table2": "table_name_2",
            "join_on": "table1.column = table2.column",
            "reasoning": "why this join makes sense"
        }}
    ]
}}
"""
            
            response = self.llm_service.generate_response(
                messages=[{"role": "user", "content": llm_prompt}],
                system_prompt="You are a database schema expert. Analyze table structures and suggest valid JOIN paths. Return JSON only.",
                max_tokens=500,
                temperature=0.1
            )
            
            # Parse response
            import json
            json_text = response.strip()
            if "```json" in json_text:
                json_text = json_text.split("```json")[1].split("```")[0].strip()
            elif "```" in json_text:
                json_text = json_text.split("```")[1].split("```")[0].strip()
            
            result = json.loads(json_text)
            
            for join in result.get('joins', []):
                llm_joins.append({
                    'table1': join['table1'],
                    'table2': join['table2'],
                    'join_on': join['join_on'],
                    'description': f"LLM-detected: {join.get('reasoning', 'implicit relationship')}",
                    'confidence': 0.60,  # Lower confidence for LLM suggestions
                    'source': 'llm_detection'
                })
            
            if llm_joins:
                logger.info(f"🤖 LLM detected {len(llm_joins)} implicit JOIN paths")
            
        except Exception as e:
            logger.warning(f"⚠️ LLM-based JOIN detection failed: {e}")
        
        return llm_joins
    
    def _get_relevant_schema(self, query: str, max_tables: int = 10) -> str:
        """
        INTELLIGENT schema selection based on query intent and entities.
        Uses semantic understanding to find the right tables.
        
        Args:
            query: User's natural language query
            max_tables: Maximum number of tables to include
            
        Returns:
            Compact schema string with relevant tables + JOIN hints
        """
        if not self.schema_parser:
            return self._get_default_schema()
        
        # Step 1: Classify query intent
        intent_info = self._classify_query_intent(query)
        logger.info(f"🎯 Query intent: {intent_info['intent']}, entities: {intent_info['entities']}")
        
        # Step 2: Get tables for identified entities
        entity_tables = self._get_tables_for_entities(intent_info['entities'])
        
        # Step 3: Combine all relevant tables
        relevant_tables = set()
        for entity, tables in entity_tables.items():
            relevant_tables.update(tables)
        
        # Step 4: Also try keyword matching as fallback
        query_lower = query.lower()
        keywords = re.findall(r'\b\w+\b', query_lower)
        all_tables = self.schema_parser.get_table_names()
        
        for keyword in keywords:
            matching_tables = self.schema_parser.search_tables(keyword)
            relevant_tables.update(matching_tables[:2])
        
        # If no tables found, include most common tables
        if not relevant_tables:
            common_tables = [
                'wms_to_wcs_order_line_request_data',
                'sku_recommendations',
                'mining_job_logs',
                'bin_velocity_scores',
                'article_proximity_score',
                'alarm_master',
                'bin_configuration'
            ]
            for table in common_tables:
                if table in all_tables:
                    relevant_tables.add(table)
        
        # Limit to max_tables
        relevant_tables = list(relevant_tables)[:max_tables]
        
        # Step 5: Get JOIN paths if multiple tables (THREE-TIER STRATEGY)
        join_hints = []
        if len(relevant_tables) > 1:
            join_paths = self._get_join_paths(relevant_tables)
            if join_paths:
                join_hints.append("\n🔗 INTELLIGENT JOIN PATH DETECTION (Three-Tier Strategy):")
                join_hints.append("   TIER 1: Experience-based (95% confidence) → Battle-tested production joins")
                join_hints.append("   TIER 2: Schema discovery (75% confidence) → Auto-detected from column names")
                join_hints.append("   TIER 3: LLM detection (60% confidence) → AI-suggested implicit joins")
                join_hints.append("\n📍 SUGGESTED JOIN PATHS FOR THIS QUERY:")
                
                # Group by source tier
                predefined = [j for j in join_paths if j.get('source') == 'predefined']
                discovered = [j for j in join_paths if j.get('source') == 'schema_discovery']
                llm_detected = [j for j in join_paths if j.get('source') == 'llm_detection']
                
                if predefined:
                    join_hints.append("  ✅ TIER 1 - PREDEFINED (Use these first!):")
                    for join in predefined:
                        confidence_pct = int(join.get('confidence', 0.95) * 100)
                        join_hints.append(f"     • {join['table1']} JOIN {join['table2']} ON {join['join_on']}")
                        join_hints.append(f"       {join['description']} [{confidence_pct}% confidence]")
                
                if discovered:
                    join_hints.append("  📊 TIER 2 - AUTO-DISCOVERED:")
                    for join in discovered:
                        confidence_pct = int(join.get('confidence', 0.75) * 100)
                        join_hints.append(f"     • {join['table1']} JOIN {join['table2']} ON {join['join_on']}")
                        join_hints.append(f"       {join['description']} [{confidence_pct}% confidence]")
                
                if llm_detected:
                    join_hints.append("  🤖 TIER 3 - LLM-DETECTED (Verify carefully):")
                    for join in llm_detected:
                        confidence_pct = int(join.get('confidence', 0.60) * 100)
                        join_hints.append(f"     • {join['table1']} JOIN {join['table2']} ON {join['join_on']}")
                        join_hints.append(f"       {join['description']} [{confidence_pct}% confidence]")
                
                join_hints.append("\n⚠️ CRITICAL: Always use TIER 1 joins when available. Lower tiers are fallbacks.")

        
        # Build compact schema with semantic information
        schema_lines = [f"📊 Database Schema (Intent: {intent_info['intent']}, Entities: {', '.join(intent_info['entities']) or 'general'})"]
        
        # Add JOIN hints at the top if needed
        if join_hints:
            schema_lines.extend(join_hints)
        
        # Add table schemas
        schema_lines.append("\n📋 RELEVANT TABLES:")
        for table in relevant_tables:
            columns = self.schema_parser.tables.get(table, [])
            pk_cols = [c['field'] for c in columns if c['key'] == 'PRI']
            pk_info = f" [PK: {', '.join(pk_cols)}]" if pk_cols else ""
            
            # Add semantic information for key columns
            semantic_cols = self._add_column_semantics(table, columns[:15])
            
            schema_lines.append(f"\n{table}{pk_info}:")
            schema_lines.append(f"  {semantic_cols}")
            
            if len(columns) > 15:
                schema_lines.append(f"  ... and {len(columns) - 15} more columns")
        
        schema = "\n".join(schema_lines)
        logger.info(f"📋 Using {len(relevant_tables)} relevant tables | JOINs detected: {len(join_paths) if len(relevant_tables) > 1 else 0}")
        return schema
    
    def _add_column_semantics(self, table: str, columns: List[Dict]) -> str:
        """
        Add semantic meaning to columns to help LLM understand their purpose.
        
        Args:
            table: Table name
            columns: List of column dictionaries
            
        Returns:
            Formatted string with columns and their semantic meanings
        """
        # Column semantic hints (what they actually mean)
        column_meanings = {
            'ARTICLE_ID': '(SKU identifier)',
            'BIN_ID': '(bin identifier)',
            'ORDER_ID': '(order identifier)',
            'BOT_ID': '(robot identifier)',
            'QUANTITY': '(item count)',
            'INSERTED_TIMESTAMP': '(creation time)',
            'UPDATED_TIMESTAMP': '(last modified time)',
            'IS_ACTIVE': '(active status: 1=active, 0=inactive)',
            'STATUS': '(current status)',
            'TASK_DONE': '(completion: 1=done, 0=pending)',
        }
        
        col_list = []
        for col in columns:
            field = col['field']
            data_type = col['type']
            semantic = column_meanings.get(field, '')
            
            # Add semantic hint if available
            if semantic:
                col_list.append(f"{field} {semantic}")
            else:
                col_list.append(f"{field} ({data_type})")
        
        return ', '.join(col_list)
    
    def _store_failed_table(self, session_id: str, table_name: str, reason: str):
        """Store information about tables that failed/have no data"""
        if not session_id:
            return
        
        if session_id not in self.session_corrections:
            self.session_corrections[session_id] = {'corrections': [], 'failed_tables': []}
        
        if 'failed_tables' not in self.session_corrections[session_id]:
            self.session_corrections[session_id]['failed_tables'] = []
        
        self.session_corrections[session_id]['failed_tables'].append({
            'table': table_name,
            'reason': reason,
            'timestamp': datetime.now().isoformat()
        })
        
        logger.info(f"📝 Stored failed table: {table_name} ({reason})")
    
    def _suggest_alternative_tables(self, failed_table: str, context: str) -> List[str]:
        """
        Suggest alternative tables based on failed table and context
        Uses table name similarity and column matching
        """
        if not self.schema_parser:
            return []
        
        suggestions = []
        all_tables = self.schema_parser.get_table_names()
        
        # Extract keywords from context
        keywords = set(re.findall(r'\b\w{4,}\b', context.lower()))  # Words 4+ chars
        
        # Find similar table names
        failed_lower = failed_table.lower()
        for table in all_tables:
            table_lower = table.lower()
            
            # Skip the failed table
            if table_lower == failed_lower:
                continue
            
            # Check for similar patterns
            score = 0
            
            # Same prefix/suffix
            if any(part in table_lower for part in failed_lower.split('_') if len(part) > 3):
                score += 2
            
            # Contains context keywords
            table_info = self.schema_parser.get_table_info(table)
            table_text = f"{table} {' '.join([col['field'] for col in table_info])}"
            matching_keywords = keywords & set(re.findall(r'\b\w{4,}\b', table_text.lower()))
            score += len(matching_keywords)
            
            if score > 0:
                suggestions.append((table, score))
        
        # Sort by score and return top 3
        suggestions.sort(key=lambda x: x[1], reverse=True)
        return [table for table, score in suggestions[:3]]
    
    def _is_negative_feedback(self, message: str) -> bool:
        """
        Detect if user is expressing negative feedback/dissatisfaction
        Returns True if message is ONLY negative feedback (not a new question)
        """
        message_lower = message.strip().lower()
        
        # Pure negative feedback patterns (no new question)
        pure_negative_patterns = [
            r'^no[,.\s]*$',
            r'^nope[,.\s]*$',
            r'^wrong[,.\s]*$',
            r'^incorrect[,.\s]*$',
            r'^not right[,.\s]*$',
            r'^this is wrong[,.\s]*$',
            r'^this is not right[,.\s]*$',
            r'^no,?\s*this is not right[,.\s]*$',
            r'^no,?\s*wrong[,.\s]*$',
            r'^that\'?s wrong[,.\s]*$',
            r'^that\'?s not right[,.\s]*$',
        ]
        
        for pattern in pure_negative_patterns:
            if re.match(pattern, message_lower):
                logger.info(f"🚫 Detected pure negative feedback: '{message}'")
                return True
        
        return False
    
    def _detect_user_correction(self, message: str, session_id: Optional[str]) -> bool:
        """
        Detect if user message is a correction/clarification and store it.
        Returns True if it's a correction (so we should handle it specially)
        """
        message_lower = message.lower()
        
        # Patterns that indicate corrections
        correction_indicators = [
            'is wrong', 'not correct', 'should be', 'use instead',
            'correct is', 'the correct', 'actually', 'it\'s actually',
            'column is', 'field is', 'not means', 'doesn\'t mean',
            'table is null', 'table is empty', 'no data in', 'not available in',
            'find in other table', 'check other table', 'different table',
            # CRITICAL: Table existence corrections
            'does not exist', 'doesn\'t exist', 'do not exist', 'don\'t exist',
            'not exist', 'table not available', 'is not available',
            'don\'t use', 'do not use', 'stop using', 'avoid',
            'i told you', 'i already told', 'already told you',
            'making mistake', 'still using', 'again using'
        ]
        
        is_correction = any(indicator in message_lower for indicator in correction_indicators)
        
        if is_correction and session_id:
            # Extract and store correction
            correction_patterns = [
                (r'(\w+)\s+is\s+wrong.*?correct\s+is\s+(\w+)', 'column_name'),
                (r'(\w+)\s+is\s+wrong.*?use\s+(\w+)', 'column_name'),
                (r'not\s+(\w+).*?should\s+be\s+(\w+)', 'column_name'),
                (r'use\s+(\w+)\s+instead', 'instruction'),
                (r'correct\s+is\s+(\w+)', 'column_name'),
                (r'column\s+is\s+(\w+)', 'column_name'),
            ]
            
            for pattern, correction_type in correction_patterns:
                matches = re.finditer(pattern, message_lower, re.IGNORECASE)
                for match in matches:
                    if match.lastindex >= 2:
                        self._store_correction(session_id, match.group(1), match.group(2))
                        logger.info(f"🔧 Stored correction: '{match.group(1)}' → '{match.group(2)}'")
            
            # Check if user says table has no data or doesn't exist
            if any(phrase in message_lower for phrase in ['table is null', 'table is empty', 'no data', 'not ready', 
                                                           'does not exist', 'doesn\'t exist', 'do not exist', 'not available']):
                # Extract table name - multiple patterns
                table_patterns = [
                    r'(?:table\s+)?[\'"`]?([\w_]+)[\'"`]?\s+(?:table\s+)?(?:does\s+not|doesn\'t|do\s+not|don\'t)\s+exist',
                    r'([\w_]+)\s+(?:table\s+)?(?:is\s+)?(?:null|empty|not\s+ready|not\s+available)',
                    r'(?:table|the)\s+[\'"`]?([\w_]+)[\'"`]?\s+(?:is\s+)?(?:not\s+available|doesn\'t\s+exist)',
                    r'(?:avoid|don\'t\s+use|stop\s+using)\s+(?:the\s+)?(?:table\s+)?[\'"`]?([\w_]+)[\'"`]?'
                ]
                
                failed_table = None
                reason = "User correction: table issue"
                
                for pattern in table_patterns:
                    table_match = re.search(pattern, message_lower)
                    if table_match:
                        failed_table = table_match.group(1)
                        
                        # Determine reason based on message
                        if 'doesn\'t exist' in message_lower or 'does not exist' in message_lower or 'not exist' in message_lower:
                            reason = "Table does not exist (USER CONFIRMED)"
                        elif 'empty' in message_lower or 'no data' in message_lower:
                            reason = "Empty/no data (USER CONFIRMED)"
                        elif 'not available' in message_lower:
                            reason = "Not available (USER CONFIRMED)"
                        
                        logger.warning(f"🚫 USER CORRECTION: Table '{failed_table}' - {reason}")
                        self._store_failed_table(session_id, failed_table, reason)
                        break
        
        return is_correction
    
    def _extract_conversation_context(self, conversation_history: Optional[List], session_id: Optional[str]) -> Dict[str, Any]:
        """
        Extract important context from conversation history
        - Previous tables mentioned
        - Column name corrections
        - Successful queries
        - User clarifications
        """
        context = {
            'tables_used': set(),
            'columns_mentioned': {},  # table -> columns
            'corrections': [],
            'successful_queries': [],
            'failed_tables': [],  # Tables that have no data
            'previous_results': [],  # Store actual data from previous queries
            'key_info': []
        }
        
        if not conversation_history:
            # Even without conversation history, check RLHF for past corrections
            try:
                rlhf_corrections = self.rlhf_service.get_sql_corrections(limit=10)
                for rlhf_corr in rlhf_corrections:
                    comment = rlhf_corr.get('comment', '')
                    # Extract correction from comment
                    if 'wrong' in comment.lower() and 'correct' in comment.lower():
                        context['key_info'].append(f"Past correction: {comment[:100]}")
            except Exception as e:
                logger.warning(f"Could not retrieve RLHF corrections: {e}")
            
            return context
        
        # Get session-specific corrections and failed tables
        if session_id and session_id in self.session_corrections:
            context['corrections'].extend(self.session_corrections[session_id].get('corrections', []))
            context['failed_tables'].extend(self.session_corrections[session_id].get('failed_tables', []))
        
        # Get cached successful queries with their actual results
        if session_id and session_id in self.session_query_cache:
            recent_queries = self.session_query_cache[session_id][-3:]  # Last 3
            for query_info in recent_queries:
                context['previous_results'].append({
                    'question': query_info['question'],
                    'sql': query_info['sql'],
                    'results_count': query_info.get('results_count', 0),
                    'sample_data': query_info.get('sample_data', [])  # First few rows
                })
        
        # Process conversation history
        for msg in conversation_history[-10:]:  # Last 10 messages for context
            if isinstance(msg, dict):
                content = str(msg.get('content', '')).lower()
            elif hasattr(msg, 'content'):
                content = str(msg.content).lower()
            else:
                content = str(msg).lower()
            
            # Extract table names mentioned
            if self.schema_parser:
                for table in self.schema_parser.get_table_names():
                    if table.lower() in content:
                        context['tables_used'].add(table)
            
            # Detect corrections (key patterns)
            correction_patterns = [
                (r'(\w+)\s+is\s+wrong.*?correct\s+is\s+(\w+)', 'column_name'),
                (r'(\w+)\s+is\s+wrong.*?use\s+(\w+)', 'column_name'),
                (r'not\s+(\w+).*?should\s+be\s+(\w+)', 'column_name'),
                (r'use\s+(\w+)\s+instead\s+of\s+(\w+)', 'column_name'),
                (r'column\s+is\s+(\w+)\s+not\s+(\w+)', 'column_name'),
            ]
            
            for pattern, correction_type in correction_patterns:
                matches = re.finditer(pattern, content, re.IGNORECASE)
                for match in matches:
                    if match.lastindex >= 2:
                        context['corrections'].append({
                            'wrong': match.group(2) if 'not' in pattern else match.group(1),
                            'correct': match.group(1) if 'column is' in pattern else match.group(2),
                            'type': correction_type
                        })
            
            # Detect clarifications about query logic
            if any(keyword in content for keyword in ['empty bin', 'available bin', 'free bin']):
                context['key_info'].append("User asking about empty/available bins - check ARTICLE_ID='no-sku' in live_inventory_master")
            
            if 'virtual quantity' in content or 'quantity is 0 not means' in content:
                context['key_info'].append("Important: Quantity=0 doesn't mean bin is empty due to virtual quantity allocation")
        
        # Get cached successful queries for this session
        if session_id and session_id in self.session_query_cache:
            context['successful_queries'] = self.session_query_cache[session_id][-3:]  # Last 3 successful queries
        
        logger.info(f"📚 Extracted context: {len(context['tables_used'])} tables, {len(context['corrections'])} corrections, {len(context['key_info'])} insights")
        return context
    
    def _build_context_prompt(self, context: Dict[str, Any]) -> str:
        """Build a prompt section from conversation context"""
        prompt_parts = []
        
        if context['corrections']:
            prompt_parts.append("\n🔧 USER CORRECTIONS (CRITICAL - MUST FOLLOW):")
            for corr in context['corrections']:
                prompt_parts.append(f"  - Use '{corr['correct']}' NOT '{corr['wrong']}'")
        
        if context['failed_tables']:
            prompt_parts.append("\n🚨 CRITICAL: TABLES THAT DO NOT EXIST OR FAILED (ABSOLUTELY DO NOT USE THESE!):")
            prompt_parts.append("⚠️ USER HAS EXPLICITLY TOLD YOU THESE TABLES ARE INVALID - DO NOT USE THEM UNDER ANY CIRCUMSTANCES!")
            for failed in context['failed_tables']:
                prompt_parts.append(f"  - ❌ BLACKLISTED: {failed['table']} ({failed['reason']})")
            prompt_parts.append("\n  🔄 INSTEAD: Find alternative tables with similar data from the schema!")
            prompt_parts.append("  📋 Example: If bin_configuration doesn't exist, use bin_info_master or location_master")
        
        if context['previous_results']:
            prompt_parts.append("\n📊 PREVIOUS QUERY RESULTS IN THIS CONVERSATION:")
            for i, prev in enumerate(context['previous_results'], 1):
                prompt_parts.append(f"  {i}. Q: {prev['question'][:60]}")
                prompt_parts.append(f"     SQL: {prev['sql'][:80]}...")
                prompt_parts.append(f"     Results: {prev['results_count']} rows")
                if prev.get('sample_data'):
                    sample = prev['sample_data'][:2]  # Show 2 sample rows
                    prompt_parts.append(f"     Sample data: {sample}")
            prompt_parts.append("  → Use this data to answer follow-up questions!")
        
        if context['key_info']:
            prompt_parts.append("\n💡 IMPORTANT CONTEXT FROM CONVERSATION:")
            for info in context['key_info']:
                prompt_parts.append(f"  - {info}")
        
        if context['successful_queries']:
            prompt_parts.append("\n✅ SUCCESSFUL QUERY PATTERNS IN THIS SESSION:")
            for i, query_info in enumerate(context['successful_queries'][-2:], 1):
                prompt_parts.append(f"  {i}. Q: {query_info['question'][:50]}...")
                prompt_parts.append(f"     SQL: {query_info['sql'][:80]}...")
        
        if context['tables_used']:
            prompt_parts.append(f"\n📋 TABLES DISCUSSED: {', '.join(sorted(context['tables_used']))}")
        
        return "\n".join(prompt_parts) if prompt_parts else ""
    
    def _store_successful_query(self, session_id: str, question: str, sql: str, results_count: int, sample_data: List[Dict] = None):
        """Store successful query in session cache with sample data"""
        if not session_id:
            return
        
        if session_id not in self.session_query_cache:
            self.session_query_cache[session_id] = []
        
        self.session_query_cache[session_id].append({
            'question': question,
            'sql': sql,
            'results_count': results_count,
            'sample_data': sample_data[:3] if sample_data else [],  # Store first 3 rows
            'forced_tables': list(extract_explicit_tables(question, self.available_tables)),
            'timestamp': pd.Timestamp.now().isoformat()
        })
        
        # Keep only last 10 queries per session
        if len(self.session_query_cache[session_id]) > 10:
            self.session_query_cache[session_id] = self.session_query_cache[session_id][-10:]
    
    def _store_correction(self, session_id: str, wrong: str, correct: str):
        """Store user correction in session"""
        if not session_id:
            return
        
        if session_id not in self.session_corrections:
            self.session_corrections[session_id] = {'corrections': []}
        
        self.session_corrections[session_id]['corrections'].append({
            'wrong': wrong,
            'correct': correct,
            'timestamp': pd.Timestamp.now().isoformat()
        })
    
    def _build_query_guidance(self, intent_info: Dict[str, Any]) -> str:
        """
        Build query-specific guidance based on intent classification.
        Helps LLM understand what type of query to generate.
        """
        guidance_parts = ["\n🎯 QUERY ANALYSIS & GUIDANCE:"]
        
        # Special handling for METADATA queries
        if intent_info.get('is_metadata_query'):
            guidance_parts.append("  🔍 METADATA QUERY DETECTED - User wants schema information, not data!")
            guidance_parts.append("  • Use INFORMATION_SCHEMA.COLUMNS to get column information")
            guidance_parts.append("  • CRITICAL: Add WHERE TABLE_SCHEMA = DATABASE() to filter to current database")
            guidance_parts.append("  • CRITICAL: Use DISTINCT or GROUP BY to avoid duplicate column names")
            guidance_parts.append("  • Show: COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY")
            guidance_parts.append("  • ORDER BY ORDINAL_POSITION for correct column order")
            guidance_parts.append("")
            guidance_parts.append("  ✅ CORRECT PATTERN:")
            guidance_parts.append("     SELECT DISTINCT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY")
            guidance_parts.append("     FROM INFORMATION_SCHEMA.COLUMNS")
            guidance_parts.append("     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'table_name'")
            guidance_parts.append("     ORDER BY ORDINAL_POSITION;")
            return "\n".join(guidance_parts)
        
        # Intent-specific guidance
        if intent_info['intent'] == 'count':
            guidance_parts.append("  • User wants to COUNT something → Use COUNT(*) or COUNT(DISTINCT column)")
            guidance_parts.append("  • Consider GROUP BY if counting by category")
        elif intent_info['intent'] == 'aggregate':
            guidance_parts.append("  • User wants aggregation → Use SUM(), AVG(), MIN(), MAX()")
            guidance_parts.append("  • GROUP BY relevant dimensions")
        elif intent_info['intent'] == 'retrieve':
            guidance_parts.append("  • User wants to view data → Use SELECT with relevant columns")
            guidance_parts.append("  • Add ORDER BY for better readability")
        
        # Entity-specific hints
        if intent_info['entities']:
            entities_str = ', '.join(intent_info['entities'])
            guidance_parts.append(f"  • Entities involved: {entities_str}")
            
            # Specific entity hints
            if 'bin' in intent_info['entities'] and 'empty' in intent_info['entities']:
                guidance_parts.append("  • For empty bins: Use ARTICLE_ID='no-sku' in live_inventory_master")
            
            if 'order' in intent_info['entities'] and 'sku' in intent_info['entities']:
                guidance_parts.append("  • Orders with SKU details: JOIN wms_to_wcs_order_line_request_data with sku_master")
        
        # JOIN guidance
        if intent_info['join_needed']:
            guidance_parts.append("  ⚠️ MULTIPLE TABLES NEEDED → Check 🔗 SUGGESTED JOIN PATHS below")
            guidance_parts.append("  • Ensure JOIN conditions match exact column names and types")
        
        # Time filter guidance
        if intent_info['time_filter']:
            guidance_parts.append("  • Time filter detected → Use INSERTED_TIMESTAMP or UPDATED_TIMESTAMP")
            guidance_parts.append("  • MySQL date functions: DATE_SUB(NOW(), INTERVAL X DAY/WEEK/MONTH)")
        
        return "\n".join(guidance_parts)
    
    def _get_system_prompt(self, query: str, context: Optional[Dict[str, Any]] = None) -> str:
        """Generate system prompt with intelligent schema and conversation context"""
        # Get intelligent schema with JOIN hints and semantic info
        schema = self._get_relevant_schema(query)
        
        # Classify query intent for guidance
        intent_info = self._classify_query_intent(query)
        
        # Build context prompt if available
        context_prompt = ""
        if context:
            context_prompt = self._build_context_prompt(context)
        
        # Build query-specific guidance
        query_guidance = self._build_query_guidance(intent_info)
        
        # Find similar SQL examples from codebase
        sql_examples = self._find_similar_sql_examples(query, top_k=3)
        sql_examples_prompt = ""
        if sql_examples:
            sql_examples_prompt = "\n\n💡 RELEVANT SQL EXAMPLES FROM CODEBASE:"
            for i, example in enumerate(sql_examples, 1):
                sql_examples_prompt += f"\n\n  Example {i} (from {example['filename']}, similarity: {example['similarity']:.2f}):\n"
                sql_examples_prompt += f"  ```sql\n{example['sql']}\n  ```"
            sql_examples_prompt += "\n\n  ⚠️ These are real queries from the codebase. Use them as reference for:"
            sql_examples_prompt += "\n  - Table names and column names (exact spelling)"
            sql_examples_prompt += "\n  - JOIN patterns and relationships"
            sql_examples_prompt += "\n  - WHERE clause patterns"
            sql_examples_prompt += "\n  - Common query structures"
        
        # Learn from historical queries (successful and failed)
        historical_learning = ""
        if self.chat_history_service:
            try:
                learning_data = self.chat_history_service.learn_from_similar_queries(query, limit=3)
                
                if learning_data['successful_examples']:
                    historical_learning += "\n\n🎓 LEARNED FROM SUCCESSFUL SIMILAR QUERIES:"
                    for i, example in enumerate(learning_data['successful_examples'][:2], 1):
                        historical_learning += f"\n\n  Success Example {i}:"
                        historical_learning += f"\n  Question: {example['query']}"
                        historical_learning += f"\n  SQL: {example['sql'][:200]}..."
                        historical_learning += f"\n  Tables used: {', '.join(example['tables'])}"
                        historical_learning += f"\n  Returned {example['rows']} rows (confidence: {example['confidence']:.0%})"
                
                if learning_data['failed_patterns']:
                    historical_learning += "\n\n⚠️ AVOID THESE PATTERNS (FAILED PREVIOUSLY):"
                    for i, fail in enumerate(learning_data['failed_patterns'][:2], 1):
                        historical_learning += f"\n  • Failed attempt: {fail['query']}"
                        historical_learning += f"\n    Used wrong tables: {', '.join(fail['tables'])}"
                        historical_learning += f"\n    Error: {fail['error'][:100] if fail['error'] else 'Unknown'}"
                
                if learning_data['table_suggestions']:
                    historical_learning += f"\n\n💡 Suggested tables for this query: {', '.join(learning_data['table_suggestions'][:5])}"
                
                if learning_data['column_suggestions']:
                    historical_learning += "\n\n🔧 COLUMN NAME CORRECTIONS (FREQUENTLY NEEDED):"
                    for table, corrections in list(learning_data['column_suggestions'].items())[:3]:
                        for corr in corrections[:2]:
                            historical_learning += f"\n  • {table}: Use '{corr['correct']}' NOT '{corr['wrong']}'"
                
            except Exception as e:
                logger.warning(f"⚠️ Could not retrieve historical learning: {e}")
        
        # Build temporal scope guidance (NEW)
        temporal_info = intent_info.get('temporal_scope', {})
        temporal_guidance = self._build_temporal_table_guidance(temporal_info, query)
        
        return f"""You are a SQL expert for the NEO Warehouse Management System.

{context_prompt}

{temporal_guidance}

⚠️⚠️⚠️ CRITICAL: ONLY USE TABLES THAT EXIST ⚠️⚠️⚠️
AVAILABLE TABLES IN DATABASE: {len(self.available_tables)} total
{', '.join(sorted(list(self.available_tables)[:30]))}... (and {len(self.available_tables) - 30} more)

**DO NOT** make up table names or use tables not in the list above!
If you're unsure, use the schema provided which contains only valid tables.
⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️

⚠️⚠️⚠️ CRITICAL: COLUMN NAMES & VALUES ⚠️⚠️⚠️
IMPORTANT KEY TABLE SCHEMAS:

bot_master:
  - Columns: BOT_ID, BOT_NUMBER, STATUS, MODEL, BATTERY_LEVEL, IS_ACTIVE, etc.
  - ⚠️ Use 'STATUS' NOT 'bot_status'
  - ⚠️ STATUS values: Check actual data, NOT 'active'/'inactive'
  
task_master:
  - Columns: TASK_ID, STATUS, BOT_ID, PRIORITY, etc.
  - Check actual STATUS values in database

⚠️ NEVER make up column names - use ONLY columns that exist in schema!
⚠️ NEVER use filter values without checking - query distinct values if unsure!
⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️

⚠️⚠️⚠️ CRITICAL WARNING ⚠️⚠️⚠️
IF THE USER CORRECTION SECTION ABOVE SAYS A TABLE DOESN'T EXIST OR IS BLACKLISTED:
- DO NOT USE THAT TABLE UNDER ANY CIRCUMSTANCES
- FIND AN ALTERNATIVE TABLE FROM THE SCHEMA
- IF YOU USE A BLACKLISTED TABLE, THE QUERY WILL FAIL IMMEDIATELY
⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️

{query_guidance}
{sql_examples_prompt}
{historical_learning}

CRITICAL TABLE RELATIONSHIPS:

1. ORDERS & SKUs:
   - Orders table: wms_to_wcs_order_line_request_data
     Key columns: ORDER_ID, ORDER_LINE_ID, ARTICLE_ID (links to SKU), QUANTITY, INSERTED_TIMESTAMP
   - SKU table: sku_master
     Key columns: SKU_ID (primary key), SKU_NAME, VELOCITY, CATEGORY
   - JOIN: ord.ARTICLE_ID = sm.SKU_ID

2. BINS & LOCATIONS:
   - Bin info: bin_info_master
     Key columns: BIN_ID (int, primary key), BIN_BARCODE, BIN_TYPE, ZONE_ID
   - Location: location_master
     Key columns: LOCATION_ID, LOCATION_NAME, ZONE_ID
   - Order-bin mapping: order_bin_mapping
     Key columns: ORDER_BIN_ID, BIN_ID (int), STATION_ID, TYPE, STATUS, INSERTED_TIMESTAMP
   
3. BINS & ORDERS (Multi-table JOIN):
   - To link orders to bins:
     wms_to_wcs_order_line_request_data → order_bin_mapping → bin_info_master
   - Direct bin-order link: order_bin_mapping.BIN_ID = bin_info_master.BIN_ID
   - For location info: Join bin_info_master with location_master via ZONE_ID

4. SKU RECOMMENDATIONS:
   - Table: sku_recommendations
   - Common columns: sku_id, recommended_sku_id, score, confidence

5. BOT MAINTENANCE TASKS:
   - Table: dashboard_log_maintenance_task_master
   - Key columns: MAINTENANCE_TASK_ID (bigint), MAINTENANCE_POINT_BOT_ID (varchar) ⚠️ NOT BOT_ID!
     MAINTENANCE_PICK_POINT_BOT_ID (varchar), TASK_DONE (0=incomplete, 1=complete),
     INSERTED_TIMESTAMP, MAINTENANCE_ID, IS_MP_BOT_HEALTHY
   - ⚠️ CRITICAL: Column is MAINTENANCE_POINT_BOT_ID, NOT BOT_ID

6. BOT INFORMATION & COUNTS:
   - ⚠️ ALWAYS START WITH: bot_master (main bot registry)
   - Key columns: BOT_ID (varchar, primary key), BOT_IP, BOT_TYPE, STATUS, IS_ACTIVE
   - For bot counts: SELECT COUNT(*) FROM bot_master
   - For active bots: WHERE IS_ACTIVE = 1 or STATUS = 'ACTIVE'
   - Related tables: dashboard_bot_master, bot_master_log, bot_alarm_log
   - ⚠️ CRITICAL: Use bot_master as starting point for ALL bot queries (counts, status, lists)

{schema}

IMPORTANT RULES:
1. Use MySQL syntax (CURDATE(), DATE_SUB(), NOW(), etc.)
2. Always add LIMIT clause (default 100, max 1000)
3. Check data types: bin_info_master.BIN_ID is INT, location_master uses VARCHAR
4. For BOT queries: ALWAYS start from bot_master table
5. For bot counts: COUNT(*) FROM bot_master with appropriate WHERE conditions
6. For dates: use INSERTED_TIMESTAMP, UPDATED_TIMESTAMP, or specific date columns
7. Return ONLY the SQL query, no explanations, no markdown code blocks
8. When joining multiple tables, verify column names match exactly (case-sensitive)
9. For maintenance tasks: Use MAINTENANCE_POINT_BOT_ID, NOT BOT_ID
10. ⚠️ NEVER use tables mentioned in the BLACKLISTED section above!

CRITICAL COLUMN NAME RULES:
⚠️ Common mistakes - ALWAYS use the CORRECT column name:
- live_inventory_master uses: ARTICLE_ID (NOT ArticleId, NOT article_id)
- wms_to_wcs_order_line_request_data uses: ARTICLE_ID (NOT ArticleId)
- For empty/available/free bins: Use ARTICLE_ID='no-sku' in live_inventory_master
- Important: QUANTITY=0 doesn't necessarily mean bin is empty (due to virtual quantity allocation)
- For truly empty bins, use WHERE ARTICLE_ID='no-sku' which indicates no SKU assigned

EXAMPLE QUERIES:

-- Count total bots:
SELECT COUNT(*) AS total_bots FROM bot_master;

-- Count active bots:
SELECT COUNT(*) AS active_bots FROM bot_master WHERE IS_ACTIVE = 1;

-- List all bots with status:
SELECT BOT_ID, BOT_IP, BOT_TYPE, STATUS, IS_ACTIVE 
FROM bot_master 
ORDER BY BOT_ID 
LIMIT 100;

-- Orders with SKU names (2-table JOIN):
SELECT sm.SKU_ID, sm.SKU_NAME, SUM(ord.QUANTITY) AS total_qty 
FROM wms_to_wcs_order_line_request_data ord 
JOIN sku_master sm ON ord.ARTICLE_ID = sm.SKU_ID 
WHERE ord.INSERTED_TIMESTAMP >= DATE_SUB(NOW(), INTERVAL 7 DAY) 
GROUP BY sm.SKU_ID, sm.SKU_NAME 
ORDER BY total_qty DESC LIMIT 5;

-- Bins with most orders:
SELECT bim.BIN_ID, bim.BIN_BARCODE, bim.BIN_TYPE, COUNT(obm.ORDER_BIN_ID) AS order_count
FROM order_bin_mapping obm
JOIN bin_info_master bim ON obm.BIN_ID = bim.BIN_ID
WHERE obm.INSERTED_TIMESTAMP >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY bim.BIN_ID, bim.BIN_BARCODE, bim.BIN_TYPE
ORDER BY order_count DESC LIMIT 10;

-- Incomplete maintenance tasks by bot:
SELECT MAINTENANCE_POINT_BOT_ID AS bot_id, MAINTENANCE_TASK_ID AS task_id, 
       INSERTED_TIMESTAMP AS assigned_date
FROM dashboard_log_maintenance_task_master
WHERE TASK_DONE = 0
ORDER BY INSERTED_TIMESTAMP DESC LIMIT 100;

-- ⚠️ CRITICAL: Count empty/available bins (correct way):
SELECT COUNT(DISTINCT BIN_ID) AS available_bins
FROM live_inventory_master
WHERE ARTICLE_ID = 'no-sku' AND IS_ACTIVE = 1
LIMIT 100;

-- Get list of empty bins:
SELECT BIN_ID
FROM live_inventory_master
WHERE ARTICLE_ID = 'no-sku'
GROUP BY BIN_ID
LIMIT 100;"""
    
    def _test_db_connection(self) -> bool:
        """Test if database connection is available"""
        try:
            conn = pymysql.connect(**self.db_config, connect_timeout=3)
            conn.close()
            logger.info("✅ Database connection successful")
            return True
        except Exception as e:
            logger.warning(f"⚠️ Database connection failed: {e}")
            return False
    
    def _load_database_schema(self) -> str:
        """Load database schema from HTML file"""
        try:
            from ..utils.schema_parser import get_schema_parser
            
            logger.info("🔍 Parsing database schema from HTML file...")
            parser = get_schema_parser()
            
            # Get compact schema for LLM system prompt
            schema = parser.get_compact_schema()
            
            table_count = len(parser.get_table_names())
            logger.info(f"✅ Loaded {table_count} tables from database schema")
            
            return schema
        except Exception as e:
            logger.error(f"❌ Error loading database schema: {e}")
            logger.warning("⚠️ Falling back to default schema")
            return self._get_default_schema()
    
    def _get_default_schema(self) -> str:
        """Get default NEO database schema"""
        return """
-- NEO Warehouse Management System Database Schema

CREATE TABLE order_history (
    order_id VARCHAR(50) PRIMARY KEY,
    sku VARCHAR(50) NOT NULL,
    order_date DATE NOT NULL,
    quantity INT,
    customer_id VARCHAR(50),
    amount DECIMAL(10,2),
    INDEX idx_sku (sku),
    INDEX idx_order_date (order_date)
);

CREATE TABLE sku_recommendations (
    parent_article_id VARCHAR(50),
    child_article_id VARCHAR(50),
    proximity_score DECIMAL(5,3),
    PRIMARY KEY (parent_article_id, child_article_id)
);

CREATE TABLE mining_schedules (
    id INT AUTO_INCREMENT PRIMARY KEY,
    job_name VARCHAR(255),
    schedule_type VARCHAR(50),
    schedule_time TIME,
    min_support DECIMAL(5,3),
    min_confidence DECIMAL(5,3),
    min_lift DECIMAL(5,3),
    is_active BOOLEAN,
    created_at DATETIME,
    last_run_at DATETIME
);

CREATE TABLE mining_job_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    schedule_id INT,
    started_at DATETIME,
    completed_at DATETIME,
    execution_status VARCHAR(50),
    rules_generated INT,
    records_processed INT,
    error_message TEXT,
    FOREIGN KEY (schedule_id) REFERENCES mining_schedules(id)
);

-- Add more tables as needed
"""
    
    def _judge_query_quality(
        self, 
        question: str, 
        sql_query: str, 
        results: List[Dict[str, Any]], 
        schema_context: str,
        iteration: int
    ) -> Dict[str, Any]:
        """
        LLM acts as a judge to evaluate query quality and suggest improvements
        
        Args:
            question: User's natural language question
            sql_query: Generated SQL query
            results: Query execution results
            schema_context: Relevant schema information
            iteration: Current refinement iteration number
            
        Returns:
            Dict with judgment: {
                'is_satisfactory': bool,
                'confidence': float,
                'issues': List[str],
                'suggestions': List[str],
                'improved_query': Optional[str]
            }
        """
        try:
            # Prepare result summary for judge
            result_summary = self._prepare_result_summary_for_judge(results)
            
            # Validate tables, columns, and values in the query
            tables_valid, invalid_tables = self._validate_sql_tables(sql_query)
            columns_valid, invalid_columns = self._validate_sql_columns(sql_query)
            values_valid, invalid_values = self._validate_query_values(sql_query)
            
            validation_msg = ""
            if not tables_valid or not columns_valid or not values_valid:
                validation_msg = "\n**⚠️ CRITICAL: QUERY HAS VALIDATION ERRORS!**\n"
                
                if not tables_valid:
                    similar_tables = []
                    for invalid_table in invalid_tables:
                        similar = self._find_similar_valid_tables(invalid_table)
                        if similar:
                            similar_tables.append(f"{invalid_table} → {similar}")
                    
                    validation_msg += f"""
Invalid tables: {', '.join(invalid_tables)}
Available similar tables: {', '.join(similar_tables)}
"""
                
                if not columns_valid:
                    column_details = []
                    for invalid_col in invalid_columns:
                        if '.' in invalid_col:
                            table, col = invalid_col.split('.', 1)
                            actual_columns = self._get_table_columns(table)
                            if actual_columns:
                                column_details.append(f"  ❌ {invalid_col} (not in {table})")
                                column_details.append(f"     ✓ Available columns: {', '.join(actual_columns[:15])}")
                    
                    validation_msg += f"""
Invalid columns detected:
{chr(10).join(column_details)}
"""
                
                if not values_valid:
                    value_details = []
                    for issue in invalid_values:
                        value_details.append(f"  ❌ {issue['table']}.{issue['column']} = '{issue['filter_value']}' (value not found in database!)")
                        value_details.append(f"     ✓ Actual values in database: {', '.join([str(v) for v in issue['actual_values'][:15]])}")
                    
                    validation_msg += f"""
Invalid filter values detected:
{chr(10).join(value_details)}
"""
            
            table_validation_msg = validation_msg
            
            judge_prompt = f"""You are an expert SQL query evaluator. Analyze the following query and its results.

**User's Question:** {question}

**Generated SQL:**
```sql
{sql_query}
```

{table_validation_msg}

**Execution Results:**
{result_summary}

**Available Schema:**
{schema_context}

**Current Iteration:** {iteration}/{self.max_refinement_iterations}

**Evaluate the query quality:**

0. **Table Validity**: Do ALL tables in the query actually exist in the schema? (CRITICAL CHECK)
0.5. **Column Validity**: Do ALL columns referenced exist in their respective tables? (CRITICAL CHECK)
0.6. **Value Validity**: Do filter values in WHERE clause match ACTUAL data in the database? (CRITICAL CHECK)
0.7. **JOIN Validity** (CRITICAL FOR MULTI-TABLE QUERIES):
   - Are JOIN conditions using correct column names from both tables?
   - Do JOIN column types match (don't join INT with VARCHAR)?
   - Are JOIN conditions using correct table aliases?
   - For multi-table queries, are there enough JOINs to connect all tables?
   - Are JOINs using the right relationship (e.g., BOT_ID = BOT_ID, not BOT_ID = TASK_ID)?
   - Check for Cartesian products (missing JOIN conditions)
1. **Correctness**: Does the SQL correctly answer the user's question?
2. **Schema Alignment**: Are the tables and columns used appropriate for the question?
3. **Result Quality**: Do the results make sense? Right number of rows? Meaningful data?
4. **Optimization**: Could the query be more efficient or accurate?

**Respond in JSON format:**
{{
    "is_satisfactory": true/false,
    "confidence": 0.0-1.0,
    "issues": ["issue 1", "issue 2", ...],
    "suggestions": ["suggestion 1", "suggestion 2", ...],
    "improved_query": "IMPROVED SQL QUERY HERE or null if satisfactory",
    "join_analysis": {{
        "joins_valid": true/false,
        "join_issues": ["join issue 1", "join issue 2", ...],
        "suggested_joins": ["table1 JOIN table2 ON condition", ...]
    }}
}}

**Rules:**
- **If query uses non-existent tables, columns, OR values, set is_satisfactory=false with confidence=0.2**
- **If JOINs are missing, incorrect, or use wrong columns, set is_satisfactory=false with confidence=0.3**
- **If JOIN creates Cartesian product (missing ON condition), this is CRITICAL error**
- **If filter values don't match actual data (e.g., status='active' when actual values are 'ENABLED'/'DISABLED'), this is CRITICAL error**
- If confidence >= 0.85, set is_satisfactory=true
- If results are empty but should have data, check if filter values or JOIN conditions are wrong
- If wrong tables/columns/values/joins used, suggest correct ones from schema and actual data
- improved_query should use ONLY tables, columns, values, and JOINs that exist in the database
- improved_query should be a complete, executable SQL query or null
- For multi-table queries, ALWAYS validate JOIN logic in join_analysis
"""

            response = self.llm_service.generate_response(
                messages=[{"role": "user", "content": judge_prompt}],
                system_prompt="You are an expert SQL quality judge. Be critical but constructive. Return valid JSON only.",
                max_tokens=800,
                temperature=0.2
            )
            
            # Parse JSON response
            import json
            # Extract JSON from response (handle cases where LLM wraps in markdown)
            json_text = response.strip()
            if "```json" in json_text:
                json_text = json_text.split("```json")[1].split("```")[0].strip()
            elif "```" in json_text:
                json_text = json_text.split("```")[1].split("```")[0].strip()
            
            judgment = json.loads(json_text)
            
            logger.info(f"🧑‍⚖️ Judge decision (iteration {iteration}): satisfactory={judgment.get('is_satisfactory')}, confidence={judgment.get('confidence'):.2f}")
            
            return judgment
            
        except Exception as e:
            logger.error(f"❌ Error in query judgment: {e}")
            # Return neutral judgment on error
            return {
                'is_satisfactory': True,  # Don't loop on errors
                'confidence': 0.5,
                'issues': [f"Judge error: {str(e)}"],
                'suggestions': [],
                'improved_query': None
            }
    
    def _prepare_result_summary_for_judge(self, results: List[Dict[str, Any]]) -> str:
        """Prepare a concise summary of results for the judge"""
        if not results:
            return "**No results returned** (0 rows)"
        
        row_count = len(results)
        columns = list(results[0].keys()) if results else []
        
        summary = f"**Row Count:** {row_count}\n"
        summary += f"**Columns:** {', '.join(columns)}\n\n"
        
        # Show sample data (first 3 rows)
        if row_count > 0:
            summary += "**Sample Data (first 3 rows):**\n"
            for i, row in enumerate(results[:3], 1):
                summary += f"\nRow {i}:\n"
                for col, val in row.items():
                    summary += f"  - {col}: {val}\n"
        
        # Data quality indicators
        if row_count > 0:
            first_row = results[0]
            null_count = sum(1 for v in first_row.values() if v is None)
            summary += f"\n**Data Quality:** {null_count}/{len(first_row)} null values in first row\n"
        
        return summary
    
    def _refine_query_with_judge_feedback(
        self,
        question: str,
        original_sql: str,
        judgment: Dict[str, Any],
        schema_context: str,
        conversation_context: Optional[Dict[str, Any]]
    ) -> Optional[str]:
        """
        Generate improved SQL query based on judge feedback
        
        Args:
            question: User's question
            original_sql: Previous SQL attempt
            judgment: Judge's feedback
            schema_context: Schema information
            conversation_context: Conversation history
            
        Returns:
            Improved SQL query or None if can't improve
        """
        try:
            # If judge already provided improved query, use it
            if judgment.get('improved_query') and judgment['improved_query'].strip():
                improved = judgment['improved_query'].strip()
                logger.info(f"📝 Using judge-provided improved query")
                return improved
            
            # Otherwise, generate improvement based on feedback
            issues_text = "\n".join(f"  - {issue}" for issue in judgment.get('issues', []))
            suggestions_text = "\n".join(f"  - {suggestion}" for suggestion in judgment.get('suggestions', []))
            
            refinement_prompt = f"""The previous SQL query needs improvement. Generate a better query.

**User's Question:** {question}

**Previous SQL (needs improvement):**
```sql
{original_sql}
```

**Issues Found:**
{issues_text}

**Suggestions for Improvement:**
{suggestions_text}

**Available Schema:**
{schema_context}

Generate an IMPROVED SQL query that addresses the issues. Return ONLY the SQL query, nothing else.
"""

            system_prompt = self._get_system_prompt(question, conversation_context)
            
            response = self.llm_service.generate_response(
                messages=[{"role": "user", "content": refinement_prompt}],
                system_prompt=system_prompt,
                max_tokens=400,
                temperature=0.1
            )
            
            improved_sql = self._extract_sql_query(response)
            
            if improved_sql and improved_sql.strip() != original_sql.strip():
                logger.info(f"✨ Generated improved query based on feedback")
                return improved_sql
            else:
                logger.warning(f"⚠️ Could not generate meaningful improvement")
                return None
                
        except Exception as e:
            logger.error(f"❌ Error refining query: {e}")
            return None
    
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        """
        Process natural language query with intelligent SQL generation, execution, and validation
        
        Workflow:
        1. Get or create session for conversation memory
        2. Extract conversation context and user corrections
        3. Generate SQL from natural language with context
        4. Execute query on database
        5. Validate results with confidence scoring
        6. Retry with different strategy if low confidence
        7. Return formatted results only when confident
        8. Store conversation in session
        
        Args:
            chat_request: User's chat request with conversation_history
            
        Returns:
            Chat response with validated query results
        """
        start_time = datetime.now()
        chat_id = None
        
        try:
            logger.info(f"🔍 Processing SQL query: {chat_request.message[:50]}...")
            
            # Step 1: Get or create session
            session_id = chat_request.session_id
            if not session_id or not self.session_manager.get_session(session_id):
                session_id = self.session_manager.create_session(
                    session_type=SessionType.SQL_ASSISTANT,
                    initial_message=chat_request.message
                )
                logger.info(f"🆕 Created new SQL Assistant session: {session_id}")
            else:
                # Add user message to existing session
                self.session_manager.add_message(session_id, 'user', chat_request.message)
            
            if not self.db_available:
                error_msg = "Database connection is not available. Please check your database configuration."
                self.session_manager.add_message(session_id, 'assistant', error_msg)
                return self._create_error_response(error_msg, session_id)
            
            # Check if user is giving pure negative feedback (like "no" or "wrong")
            if self._is_negative_feedback(chat_request.message):
                logger.info("🚫 Detected pure negative feedback - asking for clarification")
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
            
            # Detect if user is providing a correction
            is_correction = self._detect_user_correction(chat_request.message, chat_request.session_id)
            
            # If correction detected, acknowledge it and ask user to restate question
            if is_correction and chat_request.session_id:
                failed_tables = self.session_corrections.get(chat_request.session_id, {}).get('failed_tables', [])
                corrections = self.session_corrections.get(chat_request.session_id, {}).get('corrections', [])
                
                acknowledgment = "✅ **Got it! I've noted your corrections:**\n\n"
                
                if failed_tables:
                    acknowledgment += "**Tables I will NOT use:**\n"
                    for failed in failed_tables[-3:]:  # Last 3 corrections
                        acknowledgment += f"- ❌ `{failed['table']}` - {failed['reason']}\n"
                    acknowledgment += "\n"
                
                if corrections:
                    acknowledgment += "**Column/field corrections:**\n"
                    for corr in corrections[-3:]:
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
                    metadata={
                        'type': 'correction_acknowledgment',
                        'failed_tables': [f['table'] for f in failed_tables],
                        'corrections': corrections
                    }
                )
            
            # Auto-correct column names using fuzzy matching
            corrected_message, auto_corrections = self._extract_and_correct_column_names(chat_request.message)
            
            # Store auto-corrections in session for learning
            if auto_corrections and chat_request.session_id:
                for corr in auto_corrections:
                    self._store_correction(chat_request.session_id, corr['wrong'], corr['correct'])
            
            # Use corrected message for SQL generation
            original_message = chat_request.message
            if corrected_message != original_message:
                logger.info(f"📝 Using corrected query: {corrected_message[:80]}...")
                query_to_process = corrected_message
            else:
                query_to_process = original_message
            
            # Detect explicit table intent early
            explicit_tables = extract_explicit_tables(query_to_process, self.available_tables)
            logger.info(f"🔍 Explicit tables detected: {explicit_tables}")
            
            # Extract conversation context and corrections
            conversation_history = chat_request.conversation_history
            if not conversation_history and session_id:
                conversation_history = self.session_manager.get_conversation_history(session_id)

            conversation_context = self._extract_conversation_context(
                conversation_history,
                chat_request.session_id
            )
            
            # Try up to 3 strategies to get confident results
            max_attempts = 3
            strategies = ['direct', 'with_context', 'simplified']
            
            for attempt in range(max_attempts):
                strategy = strategies[min(attempt, len(strategies) - 1)]
                logger.info(f"🔄 Attempt {attempt + 1}/{max_attempts} using strategy: {strategy}")
                
                # Step 1: Generate SQL query with conversation context
                # Use corrected query (with auto-corrected column names)
                sql_query = self._generate_sql_with_strategy(
                    query_to_process, 
                    strategy,
                    conversation_context
                )
                
                if not sql_query:
                    continue
                
                # STEP 1.5: Validate tables AND columns before execution (PROACTIVE VALIDATION)
                tables_valid, invalid_tables = self._validate_sql_tables(sql_query)
                if not tables_valid:
                    logger.error(f"❌ Generated SQL uses non-existent tables: {invalid_tables}")
                    
                    # Find similar valid tables
                    suggestions = []
                    for invalid_table in invalid_tables:
                        similar = self._find_similar_valid_tables(invalid_table, limit=2)
                        if similar:
                            suggestions.append(f"{invalid_table} → try: {', '.join(similar)}")
                    
                    error_msg = f"Query uses non-existent tables: {', '.join(invalid_tables)}."
                    if suggestions:
                        error_msg += f" Similar tables that exist: {'; '.join(suggestions)}"
                    
                    # Skip to next attempt with different strategy
                    logger.warning(f"⚠️ Skipping execution due to invalid tables (attempt {attempt + 1})")
                    
                    # Mark these as failed tables for future attempts
                    if chat_request.session_id:
                        for invalid_table in invalid_tables:
                            self._store_failed_table(
                                chat_request.session_id,
                                invalid_table,
                                "does not exist in schema"
                            )
                    
                    continue  # Try next strategy
                
                logger.info(f"✅ Table validation passed - all tables exist in schema")
                
                # STEP 1.6: Validate columns (NEW)
                columns_valid, invalid_columns = self._validate_sql_columns(sql_query)
                if not columns_valid:
                    logger.error(f"❌ Generated SQL uses non-existent columns: {invalid_columns}")
                    
                    # Provide actual columns for those tables
                    column_hints = []
                    for invalid_col in invalid_columns:
                        if '.' in invalid_col:
                            table, col = invalid_col.split('.', 1)
                            actual_columns = self._get_table_columns(table)
                            if actual_columns:
                                column_hints.append(f"{table} has: {', '.join(actual_columns[:10])}")
                    
                    error_msg = f"Query uses non-existent columns: {', '.join(invalid_columns)}."
                    if column_hints:
                        error_msg += f" Actual columns: {'; '.join(column_hints)}"
                    
                    logger.warning(f"⚠️ Skipping execution due to invalid columns (attempt {attempt + 1})")
                    
                    # Mark in session corrections
                    if chat_request.session_id:
                        if chat_request.session_id not in self.session_corrections:
                            self.session_corrections[chat_request.session_id] = {'corrections': [], 'failed_tables': []}
                        self.session_corrections[chat_request.session_id]['corrections'].append({
                            'wrong': str(invalid_columns),
                            'correct': error_msg
                        })
                    
                    continue  # Try next strategy
                
                logger.info(f"✅ Column validation passed - all columns exist in their tables")
                
                # STEP 1.7: Validate filter values in WHERE clause (CRITICAL!)
                values_valid, invalid_values = self._validate_query_values(sql_query)
                if not values_valid:
                    logger.error(f"❌ Generated SQL uses filter values that don't exist in database!")
                    
                    # Provide actual values for those columns
                    value_hints = []
                    for issue in invalid_values:
                        value_hints.append(
                            f"{issue['table']}.{issue['column']} = '{issue['filter_value']}' (NOT FOUND IN DB)\n" +
                            f"  ✓ Actual values: {', '.join([str(v) for v in issue['actual_values'][:15]])}"
                        )
                    
                    error_msg = "Query uses filter values that don't exist in database:\n" + "\n".join(value_hints)
                    logger.error(f"\n{error_msg}")
                    
                    # Mark in session corrections
                    if chat_request.session_id:
                        if chat_request.session_id not in self.session_corrections:
                            self.session_corrections[chat_request.session_id] = {'corrections': [], 'failed_tables': []}
                        self.session_corrections[chat_request.session_id]['corrections'].append({
                            'wrong': str([f"{issue['filter_value']}" for issue in invalid_values]),
                            'correct': error_msg
                        })
                    
                    continue  # Try next strategy
                
                logger.info(f"✅ Value validation passed - filter values exist in database")
                
                # Step 2: Execute query
                results, error = self._execute_query_safe(sql_query)
                
                if error:
                    logger.warning(f"⚠️ Query execution error (attempt {attempt + 1}): {error}")
                    
                    # Log failed query to chat history
                    if self.chat_history_service and attempt == max_attempts - 1:  # Log on last attempt
                        try:
                            response_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
                            intent_info = self._classify_query_intent(chat_request.message)
                            tables_used = self._extract_tables_from_sql(sql_query)
                            
                            chat_id = self.chat_history_service.log_chat_interaction(
                                session_id=chat_request.session_id or str(uuid.uuid4()),
                                chatbot_type="sql_assistant",
                                user_query=chat_request.message,
                                assistant_response=f"Query failed: {error}",
                                confidence_score=0.0,
                                response_time_ms=response_time_ms
                            )
                            
                            self.chat_history_service.log_sql_query(
                                chat_id=chat_id,
                                session_id=chat_request.session_id or str(uuid.uuid4()),
                                user_query=chat_request.message,
                                generated_sql=sql_query,
                                execution_status='failed',
                                error_message=error[:500],  # Truncate long errors
                                tables_used=tables_used,
                                intent=intent_info.get('intent'),
                                entities=intent_info.get('entities')
                            )
                        except Exception as e:
                            logger.warning(f"⚠️ Failed to log error to chat history: {e}")
                    
                    continue
                
                # ========================================
                # SELF-IMPROVING LOOP WITH LLM AS JUDGE
                # ========================================
                
                # Get schema context for judge
                schema_context = self._get_relevant_schema(query_to_process, max_tables=8)
                
                # Initialize refinement tracking
                current_sql = sql_query
                current_results = results
                best_confidence = 0.0
                best_sql = sql_query
                best_results = results
                refinement_history = []
                
                # Self-refinement loop
                for refinement_iteration in range(1, self.max_refinement_iterations + 1):
                    logger.info(f"🔁 Self-refinement iteration {refinement_iteration}/{self.max_refinement_iterations}")
                    
                    # Step 3a: Validate results (basic validation)
                    confidence, validation_msg = self._validate_results(
                        current_results, 
                        chat_request.message, 
                        current_sql,
                        explicit_tables
                    )
                    
                    logger.info(f"📊 Validation: confidence={confidence:.2f}, msg={validation_msg}")
                    
                    # Track best result so far
                    if confidence > best_confidence:
                        best_confidence = confidence
                        best_sql = current_sql
                        best_results = current_results
                    
                    # Step 3b: LLM Judge evaluates query quality
                    judgment = self._judge_query_quality(
                        question=query_to_process,
                        sql_query=current_sql,
                        results=current_results,
                        schema_context=schema_context,
                        iteration=refinement_iteration
                    )
                    
                    # Track refinement history
                    refinement_history.append({
                        'iteration': refinement_iteration,
                        'sql': current_sql,
                        'confidence': confidence,
                        'judge_confidence': judgment.get('confidence', 0.0),
                        'is_satisfactory': judgment.get('is_satisfactory', False),
                        'issues': judgment.get('issues', []),
                        'suggestions': judgment.get('suggestions', [])
                    })
                    
                    # Check if judge is satisfied with high confidence
                    judge_confidence = judgment.get('confidence', 0.0)
                    is_satisfactory = judgment.get('is_satisfactory', False)
                    
                    logger.info(f"🧑‍⚖️ Judge: satisfactory={is_satisfactory}, confidence={judge_confidence:.2f}")
                    
                    # Exit condition 1: Judge is satisfied AND confidence is high
                    if is_satisfactory and judge_confidence >= self.judge_confidence_threshold:
                        logger.info(f"✅ Judge satisfied with high confidence ({judge_confidence:.2f}) - stopping refinement")
                        break
                    
                    # Exit condition 2: Last iteration
                    if refinement_iteration >= self.max_refinement_iterations:
                        logger.info(f"🛑 Reached max iterations ({self.max_refinement_iterations}) - using best result")
                        # Use best result found across all iterations
                        current_sql = best_sql
                        current_results = best_results
                        confidence = best_confidence
                        break
                    
                    # Exit condition 3: Very high basic confidence
                    if confidence >= 0.90:
                        logger.info(f"✅ Very high confidence ({confidence:.2f}) - stopping refinement")
                        break
                    
                    # Step 3c: Generate improved query based on judge feedback
                    if not is_satisfactory or judge_confidence < self.judge_confidence_threshold:
                        improved_sql = self._refine_query_with_judge_feedback(
                            question=query_to_process,
                            original_sql=current_sql,
                            judgment=judgment,
                            schema_context=schema_context,
                            conversation_context=conversation_context
                        )
                        
                        if improved_sql and improved_sql.strip() != current_sql.strip():
                            logger.info(f"🔄 Executing improved query (iteration {refinement_iteration + 1})")
                            
                            # Execute improved query
                            improved_results, improved_error = self._execute_query_safe(improved_sql)
                            
                            if improved_error:
                                logger.warning(f"⚠️ Improved query failed: {improved_error[:200]}")
                                # Keep current query, don't iterate further on this attempt
                                break
                            else:
                                # Use improved query for next iteration
                                current_sql = improved_sql
                                current_results = improved_results
                                logger.info(f"✨ Improved query executed successfully, continuing refinement")
                        else:
                            logger.info(f"⚠️ Could not generate improved query - stopping refinement")
                            break
                
                # Update to use final refined results
                sql_query = current_sql
                results = current_results
                
                # Log refinement process
                if len(refinement_history) > 1:
                    logger.info(f"📈 Refinement summary: {len(refinement_history)} iterations, final confidence: {best_confidence:.2f}")
                
                # ========================================
                # END OF SELF-IMPROVING LOOP
                # ========================================
                
                # Step 4: Check if confident enough to return
                if best_confidence >= 0.75:  # High confidence threshold
                    # Use the validation message from best result
                    final_validation_msg = f"Query refined through {len(refinement_history)} iterations"
                    
                    response_text = self._format_results_with_confidence(
                        results, 
                        sql_query, 
                        original_message,  # Use original message for display
                        best_confidence,
                        final_validation_msg
                    )
                    
                    # Add refinement information if iterations occurred
                    if len(refinement_history) > 1:
                        refinement_note = f"\n\n🔄 **Query Refinement:** Improved through {len(refinement_history)} iterations for optimal results.\n"
                        response_text = refinement_note + response_text
                    
                    # Add note about auto-corrections if any were made
                    if auto_corrections:
                        correction_notes = []
                        for corr in auto_corrections:
                            correction_notes.append(f"'{corr['wrong']}' → '{corr['correct']}'")
                        response_text = f"ℹ️ Auto-corrected column names: {', '.join(correction_notes)}\n\n{response_text}"
                    
                    # Calculate response time
                    response_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
                    
                    # Classify query intent for analytics
                    intent_info = self._classify_query_intent(chat_request.message)
                    
                    # Extract tables and columns from SQL
                    tables_used = self._extract_tables_from_sql(sql_query)
                    columns_used = self._extract_columns_from_sql(sql_query)
                    
                    # Log to comprehensive chat history
                    if self.chat_history_service:
                        try:
                            # Log main chat interaction
                            chat_id = self.chat_history_service.log_chat_interaction(
                                session_id=chat_request.session_id or str(uuid.uuid4()),
                                chatbot_type="sql_assistant",
                                user_query=chat_request.message,
                                assistant_response=response_text,
                                confidence_score=best_confidence,
                                response_time_ms=response_time_ms
                            )
                            
                            # Log SQL query details
                            self.chat_history_service.log_sql_query(
                                chat_id=chat_id,
                                session_id=chat_request.session_id or str(uuid.uuid4()),
                                user_query=chat_request.message,
                                generated_sql=sql_query,
                                execution_status='success',
                                rows_returned=len(results) if results else 0,
                                execution_time_ms=response_time_ms,
                                tables_used=tables_used,
                                columns_used=columns_used,
                                intent=intent_info.get('intent'),
                                entities=intent_info.get('entities')
                            )
                            
                            # Log auto-corrections
                            for corr in auto_corrections:
                                self.chat_history_service.log_column_correction(
                                    session_id=chat_request.session_id or str(uuid.uuid4()),
                                    table_name=corr.get('table', 'unknown'),
                                    wrong_column=corr['wrong'],
                                    correct_column=corr['correct'],
                                    correction_type='automatic',
                                    similarity_score=corr.get('similarity', 0.0),
                                    chat_id=chat_id
                                )
                            
                            # Update query patterns for learning
                            self.chat_history_service.update_query_pattern(
                                pattern_type='intent',
                                pattern_key=intent_info.get('intent', 'unknown'),
                                pattern_value=chat_request.message[:200],
                                success=True,
                                confidence=confidence
                            )
                            
                            # Log entity-table patterns
                            for entity in intent_info.get('entities', []):
                                if tables_used:
                                    self.chat_history_service.update_query_pattern(
                                        pattern_type='entity_table',
                                        pattern_key=entity,
                                        pattern_value=','.join(tables_used[:3]),
                                        success=True,
                                        confidence=confidence
                                    )
                            
                        except Exception as e:
                            logger.warning(f"⚠️ Failed to log to chat history: {e}")
                    
                    # Store successful query in session cache with sample data
                    self._store_successful_query(
                        chat_request.session_id or str(uuid.uuid4()),
                        chat_request.message,
                        sql_query,
                        len(results) if results else 0,
                        results if results else []
                    )
                    
                    # Record successful query for RLHF learning
                    try:
                        self.rlhf_service.record_feedback(
                            chatbot_type="sql_assistant",
                            query=chat_request.message,
                            response=response_text,
                            feedback_type="neutral",  # Auto-logged on generation
                            rating=None,
                            comment="Auto-generated with high confidence after refinement",
                            metadata={
                                "sql_query": sql_query,
                                "confidence": best_confidence,
                                "row_count": len(results) if results else 0,
                                "strategy": strategy,
                                "attempt": attempt + 1,
                                "refinement_iterations": len(refinement_history),
                                "auto_corrections": auto_corrections if auto_corrections else None
                            }
                        )
                    except Exception as e:
                        logger.warning(f"Failed to record RLHF feedback: {e}")
                    
                    # Add assistant response to session
                    self.session_manager.add_message(
                        session_id,
                        'assistant',
                        response_text,
                        metadata={
                            'sql_query': sql_query,
                            'confidence': best_confidence,
                            'row_count': len(results) if results else 0,
                            'refinement_iterations': len(refinement_history)
                        }
                    )
                    
                    return ChatResponse(
                        response=response_text,
                        chatbot_type=ChatbotType.SQL_ASSISTANT,
                        session_id=session_id,
                        sql_query=sql_query,
                        query_results=results[:100] if results else [],  # Limit to 100 for response
                        confidence_score=best_confidence,
                        sources=[],
                        metadata={
                            'refinement_iterations': len(refinement_history),
                            'refinement_history': refinement_history if len(refinement_history) > 1 else None
                        }
                    )
            
            # If all attempts failed, return query-only response
            logger.warning("⚠️ All attempts failed to produce confident results")
            return self._create_low_confidence_response(
                sql_query if sql_query else "Could not generate SQL",
                chat_request.session_id,
                chat_request.message
            )
            
        except Exception as e:
            logger.error(f"❌ Error processing SQL query: {e}", exc_info=True)
            return self._create_error_response(
                f"I encountered an error: {str(e)}",
                chat_request.session_id
            )
    
    def _extract_sql_query(self, response: str) -> Optional[str]:
        """Extract SQL query from LLM response"""
        try:
            # Look for SQL code blocks
            if "```sql" in response.lower():
                start = response.lower().find("```sql") + 6
                end = response.find("```", start)
                if end > start:
                    return response[start:end].strip()
            
            # Look for SELECT, INSERT, UPDATE, DELETE statements
            lines = response.split('\n')
            sql_keywords = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'WITH']
            
            sql_lines = []
            in_query = False
            
            for line in lines:
                upper_line = line.strip().upper()
                if any(upper_line.startswith(kw) for kw in sql_keywords):
                    in_query = True
                
                if in_query:
                    sql_lines.append(line)
                    if line.strip().endswith(';'):
                        break
            
            if sql_lines:
                return '\n'.join(sql_lines).strip()
            
            return None
        except Exception as e:
            logger.error(f"❌ Error extracting SQL query: {e}")
            return None
    
    def _generate_sql_suggestions(self, query: str) -> List[str]:
        """Generate suggested SQL-related actions"""
        suggestions = []
        
        query_lower = query.lower()
        
        if "top" in query_lower or "best" in query_lower:
            suggestions.extend([
                "Add time period filter",
                "View detailed breakdown",
                "Export results to CSV"
            ])
        elif "count" in query_lower or "how many" in query_lower:
            suggestions.extend([
                "View distribution over time",
                "Compare with previous period",
                "Show detailed list"
            ])
        else:
            suggestions.extend([
                "Refine date range",
                "Add additional filters",
                "View related data"
            ])
        
        return suggestions[:3]
    
    def get_schema_info(self) -> Dict[str, Any]:
        """Get database schema information"""
        return {
            "total_tables": len(self._extract_table_names()),
            "tables": self._extract_table_names()[:20],  # Return first 20 tables
            "llm_provider": self.llm_service.get_provider_info(),
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
    
    # ========================================
    # NEW INTELLIGENT METHODS
    # ========================================
    
    def _find_closest_column_name(self, user_column: str, table_name: str) -> Optional[str]:
        """
        Find the closest matching column name in the given table.
        Uses fuzzy matching to correct common mistakes like:
        - ArticleId → ARTICLE_ID
        - BinId → BIN_ID
        - orderId → ORDER_ID
        
        Args:
            user_column: Column name as user typed it
            table_name: Table to search in
            
        Returns:
            Closest matching column name or None
        """
        if not self.schema_parser or not table_name:
            return None
        
        try:
            # Get columns for the table
            columns = self.schema_parser.tables.get(table_name, [])
            if not columns:
                return None
            
            column_names = [col['field'] for col in columns]
            user_column_lower = user_column.lower()
            
            # Direct match (case-insensitive)
            for col in column_names:
                if col.lower() == user_column_lower:
                    return col
            
            # Fuzzy matching: Calculate similarity scores
            from difflib import SequenceMatcher
            
            def similarity(a: str, b: str) -> float:
                """Calculate similarity ratio between two strings"""
                return SequenceMatcher(None, a.lower(), b.lower()).ratio()
            
            # Score each column
            matches = []
            for col in column_names:
                score = similarity(user_column, col)
                matches.append((col, score))
            
            # Sort by score (highest first)
            matches.sort(key=lambda x: x[1], reverse=True)
            
            # Return best match if similarity is high enough (>0.6)
            if matches and matches[0][1] > 0.6:
                best_match = matches[0][0]
                logger.info(f"🔍 Fuzzy match: '{user_column}' → '{best_match}' (score: {matches[0][1]:.2f})")
                return best_match
            
            return None
            
        except Exception as e:
            logger.error(f"❌ Error finding closest column: {e}")
            return None
    
    def _extract_and_correct_column_names(self, question: str) -> Tuple[str, List[Dict[str, str]]]:
        """
        Extract potential column names from user's query and suggest corrections.
        
        Detects patterns like:
        - "where ArticleId='xyz'"
        - "show me BinId"
        - "order by OrderDate"
        
        Returns:
            Tuple of (corrected_question, list of corrections made)
        """
        corrections = []
        corrected_question = question
        
        if not self.schema_parser:
            return question, corrections
        
        try:
            # Extract table names from question
            question_lower = question.lower()
            tables_mentioned = []
            
            for table in self.schema_parser.get_table_names():
                if table.lower() in question_lower:
                    tables_mentioned.append(table)
            
            if not tables_mentioned:
                return question, corrections
            
            # Pattern to find potential column names in WHERE clauses, ORDER BY, etc.
            # Matches: word followed by = or space (likely column name)
            import re
            column_patterns = [
                r'\bwhere\s+(\w+)\s*[=<>]',  # WHERE column_name =
                r'\band\s+(\w+)\s*[=<>]',    # AND column_name =
                r'\bor\s+(\w+)\s*[=<>]',     # OR column_name =
                r'\border\s+by\s+(\w+)',     # ORDER BY column_name
                r'\bgroup\s+by\s+(\w+)',     # GROUP BY column_name
                r'\bselect\s+(\w+)',         # SELECT column_name
                r'\bshow.*?(\w+Id)',         # show me ArticleId (pattern for Id columns)
                r'\b(\w+Id)\s*[=\'"]',       # ArticleId='value'
                r'\b(\w+_id)\s*[=\'"]',      # article_id='value'
            ]
            
            potential_columns = set()
            for pattern in column_patterns:
                matches = re.finditer(pattern, question, re.IGNORECASE)
                for match in matches:
                    potential_columns.add(match.group(1))
            
            # For each table mentioned, try to find corrections
            for table in tables_mentioned:
                for user_col in potential_columns:
                    # Skip common SQL keywords
                    if user_col.upper() in ['SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'ORDER', 'GROUP', 'BY', 'HAVING']:
                        continue
                    
                    correct_col = self._find_closest_column_name(user_col, table)
                    
                    if correct_col and correct_col != user_col:
                        corrections.append({
                            'table': table,
                            'wrong': user_col,
                            'correct': correct_col
                        })
                        
                        # Replace in question (case-insensitive)
                        corrected_question = re.sub(
                            r'\b' + re.escape(user_col) + r'\b',
                            correct_col,
                            corrected_question,
                            flags=re.IGNORECASE
                        )
            
            if corrections:
                logger.info(f"🔧 Auto-corrected {len(corrections)} column name(s) in query")
                for corr in corrections:
                    logger.info(f"   {corr['table']}: '{corr['wrong']}' → '{corr['correct']}'")
            
            return corrected_question, corrections
            
        except Exception as e:
            logger.error(f"❌ Error extracting column names: {e}")
            return question, corrections
    
    def _generate_sql_with_strategy(self, question: str, strategy: str, context: Optional[Dict[str, Any]] = None) -> Optional[str]:
        """Generate SQL with different strategies and conversation context"""
        try:
            # Get dynamic system prompt with relevant schema and conversation context
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
            return sql_query
            
        except Exception as e:
            logger.error(f"❌ SQL generation error with strategy {strategy}: {e}")
            return None
    
    def _execute_query_safe(self, sql_query: str, session_id: Optional[str] = None) -> Tuple[List[Dict[str, Any]], Optional[str]]:
        """Execute SQL query safely with timeout and error handling"""
        try:
            # CRITICAL: Check if query uses blacklisted tables
            if session_id and session_id in self.session_corrections:
                failed_tables = self.session_corrections[session_id].get('failed_tables', [])
                if failed_tables:
                    sql_lower = sql_query.lower()
                    for failed in failed_tables:
                        blacklisted_table = failed['table'].lower()
                        # Check if blacklisted table is in the query
                        if re.search(r'\b' + re.escape(blacklisted_table) + r'\b', sql_lower):
                            error_msg = f"❌ QUERY USES BLACKLISTED TABLE '{failed['table']}' - {failed['reason']}. USER EXPLICITLY SAID THIS TABLE {failed['reason'].upper()}!"
                            logger.error(error_msg)
                            return [], error_msg
            
            # Security: Prevent dangerous operations (use word boundaries to avoid false positives)
            import re
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
            
            # Execute with timeout
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
        sql_query: str,
        explicit_tables: Optional[set] = None
    ) -> Tuple[float, str]:
        """
        Validate query results and calculate confidence score
        
        Returns:
            Tuple of (confidence_score, validation_message)
        """
        # Check explicit table constraint FIRST
        if explicit_tables:
            sql_tables = extract_tables_from_sql(sql_query)
            if not explicit_tables.issubset(sql_tables):
                return (
                    0.2,
                    f"SQL violates explicit table constraint: expected {explicit_tables}, got {sql_tables}"
                )
        
        confidence = 0.5  # Base confidence
        messages = []
        
        # Check 1: Results exist
        if not results:
            return 0.3, "No results returned - query might be too restrictive or data doesn't exist"
        
        confidence += 0.1
        messages.append(f"✅ {len(results)} results found")
        
        # Check 2: Reasonable result count
        if 1 <= len(results) <= 1000:
            confidence += 0.15
            messages.append("✅ Result count looks reasonable")
        elif len(results) > 10000:
            confidence -= 0.1
            messages.append("⚠️ Very large result set - might need filtering")
        
        # Check 3: Results have data (not all nulls)
        if results:
            first_row = results[0]
            non_null_values = sum(1 for v in first_row.values() if v is not None)
            
            if non_null_values >= len(first_row) * 0.7:  # 70% non-null
                confidence += 0.15
                messages.append("✅ Results contain meaningful data")
            else:
                confidence -= 0.05
                messages.append("⚠️ Many null values in results")
        
        # Check 4: Column names make sense
        if results:
            columns = list(results[0].keys())
            relevant_keywords = question.lower().split()
            
            column_relevance = sum(
                1 for col in columns 
                for keyword in relevant_keywords 
                if keyword in col.lower()
            )
            
            if column_relevance > 0:
                confidence += 0.10
                messages.append("✅ Column names match question context")
        
        # Cap confidence at 0.95 (never 100% sure)
        confidence = min(confidence, 0.95)
        
        validation_msg = " | ".join(messages)
        return confidence, validation_msg
    
    def _format_results_with_confidence(
        self,
        results: List[Dict[str, Any]],
        sql_query: str,
        question: str,
        confidence: float,
        validation_msg: str
    ) -> str:
        """Format results with confidence indicators"""
        
        # Confidence badge (without emojis)
        if confidence >= 0.9:
            confidence_badge = f"**High Confidence:** {confidence * 100:.0f}%"
        elif confidence >= 0.75:
            confidence_badge = f"**Good Confidence:** {confidence * 100:.0f}%"
        else:
            confidence_badge = f"**Moderate Confidence:** {confidence * 100:.0f}%"
        
        response_parts = [
            f"{confidence_badge}\n",
            f"**Found {len(results)} result(s):**\n"
        ]
        
        # Format results as markdown table
        if results:
            columns = list(results[0].keys())
            display_limit = min(len(results), 200)
            
            # Table header
            table = "| " + " | ".join(columns) + " |\n"
            table += "| " + " | ".join(["---"] * len(columns)) + " |\n"
            
            # Table rows
            display_results = results[:display_limit]
            for row in display_results:
                values = []
                for col in columns:
                    val = row.get(col, '')
                    if val is None:
                        val = ''
                    else:
                        val = str(val)
                        # Truncate long values
                        if len(val) > 50:
                            val = val[:47] + '...'
                    values.append(val)
                table += "| " + " | ".join(values) + " |\n"
            
            response_parts.append(table)
            
            if len(results) > display_limit:
                response_parts.append(f"\n*Showing first {display_limit} of {len(results)} results*")
        
        # Add SQL query used
        response_parts.append(f"\n**SQL Query:**\n```sql\n{sql_query}\n```")
        
        # Add validation info
        if validation_msg:
            response_parts.append(f"\n*Validation: {validation_msg}*")
        
        return "\n".join(response_parts)
    
    def _create_error_response(self, message: str, session_id: Optional[str]) -> ChatResponse:
        """Create error response"""
        return ChatResponse(
            response=f"❌ {message}",
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            confidence_score=0.0,
            sources=[]
        )
    
    def _create_low_confidence_response(
        self, 
        sql_query: str, 
        session_id: Optional[str],
        question: str
    ) -> ChatResponse:
        """Create response when confidence is too low"""
        response_text = f"""I generated a SQL query for your question, but I'm not confident in the results.

**Your Question:** {question}

**Generated SQL:**
```sql
{sql_query}
```

**Issue:** The query execution didn't return results I'm confident about. This could mean:
- The data doesn't exist in the specified time range
- The query needs refinement
- The table structure differs from expected

💡 **Suggestions:**
1. Try rephrasing your question with more specific details
2. Check if the data exists for the time period mentioned
3. Review the SQL query above and run it manually if needed

Would you like to try a different question?"""
        
        return ChatResponse(
            response=response_text,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id or str(uuid.uuid4()),
            sql_query=sql_query,
            confidence_score=0.5,
            sources=[]
        )
    
    def _extract_tables_from_sql(self, sql_query: str) -> List[str]:
        """Extract table names from SQL query"""
        try:
            tables = []
            # Simple regex to find table names after FROM and JOIN
            patterns = [
                r'FROM\s+([a-zA-Z_][a-zA-Z0-9_]*)',
                r'JOIN\s+([a-zA-Z_][a-zA-Z0-9_]*)',
                r'INTO\s+([a-zA-Z_][a-zA-Z0-9_]*)',
                r'UPDATE\s+([a-zA-Z_][a-zA-Z0-9_]*)'
            ]
            
            for pattern in patterns:
                matches = re.findall(pattern, sql_query, re.IGNORECASE)
                tables.extend(matches)
            
            # Remove duplicates and filter out SQL keywords
            sql_keywords = {'SELECT', 'WHERE', 'GROUP', 'ORDER', 'HAVING', 'LIMIT', 'AND', 'OR'}
            tables = [t for t in set(tables) if t.upper() not in sql_keywords]
            
            return tables
        except Exception as e:
            logger.error(f"❌ Error extracting tables from SQL: {e}")
            return []
    
    def _find_similar_sql_examples(self, query: str, top_k: int = 3) -> List[Dict[str, Any]]:
        """
        Find similar SQL examples from codebase with multi-tier fallback strategy.
        
        TIER 1: Vector similarity search (best)
        TIER 2: Keyword matching in query text (fallback)
        TIER 3: Common SQL patterns (last resort)
        TIER 4: Empty list (graceful degradation)
        
        Args:
            query: Natural language query
            top_k: Number of examples to return
            
        Returns:
            List of similar SQL examples with metadata
        """
        try:
            # TIER 1: Try vector store if available
            if self.vector_store:
                try:
                    results = self.vector_store.search_sql_examples(query, top_k=top_k)
                    if results and len(results) > 0:
                        logger.debug(f"✅ Found {len(results)} SQL examples via vector search")
                        return results
                except Exception as e:
                    logger.warning(f"⚠️ Vector search failed: {e}, trying fallback")
            
            # TIER 2: Keyword-based matching from common patterns
            logger.debug("📋 Using keyword-based SQL pattern matching")
            patterns = self._get_common_sql_patterns()
            
            # Extract keywords from query
            query_lower = query.lower()
            keywords = []
            if any(word in query_lower for word in ['count', 'how many', 'number of']):
                keywords.append('count')
            if any(word in query_lower for word in ['list', 'show', 'get all', 'find all']):
                keywords.append('list')
            if any(word in query_lower for word in ['join', 'combine', 'with', 'and their']):
                keywords.append('join')
            if any(word in query_lower for word in ['filter', 'where', 'that are', 'with status']):
                keywords.append('filter')
            if any(word in query_lower for word in ['group', 'by', 'per', 'each']):
                keywords.append('group')
            
            # Match patterns to keywords
            matched_patterns = []
            for pattern in patterns:
                pattern_type = pattern.get('type', '')
                if any(kw in pattern_type for kw in keywords):
                    matched_patterns.append(pattern)
            
            # Return top_k matches
            if matched_patterns:
                logger.debug(f"✅ Matched {len(matched_patterns[:top_k])} SQL patterns via keywords")
                return matched_patterns[:top_k]
            
            # TIER 3: Return basic patterns if no keywords match
            logger.debug("📋 Returning basic SQL patterns as fallback")
            return patterns[:top_k]
            
        except Exception as e:
            logger.error(f"❌ Error finding SQL examples: {e}", exc_info=True)
            # TIER 4: Graceful degradation
            return []
    
    def _get_common_sql_patterns(self) -> List[Dict[str, Any]]:
        """
        Get hardcoded common SQL patterns as ultimate fallback.
        
        Returns:
            List of common SQL pattern examples
        """
        return [
            {
                'filename': 'common_patterns.sql',
                'sql': 'SELECT * FROM table_name WHERE status = "ENABLED" LIMIT 10',
                'type': 'filter_list',
                'similarity': 0.7,
                'description': 'Basic filtered list query'
            },
            {
                'filename': 'common_patterns.sql',
                'sql': 'SELECT COUNT(*) as total FROM table_name WHERE condition',
                'type': 'count_filter',
                'similarity': 0.7,
                'description': 'Count with filter'
            },
            {
                'filename': 'common_patterns.sql',
                'sql': '''SELECT t1.*, t2.column_name 
FROM table1 t1 
JOIN table2 t2 ON t1.id = t2.foreign_id 
WHERE t1.status = "ACTIVE"''',
                'type': 'join_filter',
                'similarity': 0.7,
                'description': 'Join two tables with filter'
            },
            {
                'filename': 'common_patterns.sql',
                'sql': 'SELECT category, COUNT(*) as count FROM table_name GROUP BY category ORDER BY count DESC',
                'type': 'group_count',
                'similarity': 0.7,
                'description': 'Group by and count'
            },
            {
                'filename': 'common_patterns.sql',
                'sql': 'SELECT * FROM table_name ORDER BY created_at DESC LIMIT 5',
                'type': 'recent_list',
                'similarity': 0.7,
                'description': 'Get recent records'
            }
        ]
