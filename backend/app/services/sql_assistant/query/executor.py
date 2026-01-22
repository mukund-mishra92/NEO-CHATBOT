"""
Query Executor Module
Safe SQL query execution with timeout and security checks
"""

import logging
import pymysql
import pandas as pd
import re
from typing import List, Dict, Any, Tuple, Optional

logger = logging.getLogger(__name__)


class QueryExecutor:
    """
    Executes SQL queries safely with security checks and timeouts
    """
    
    def __init__(self, db_config: Dict[str, Any]):
        """
        Initialize query executor
        
        Args:
            db_config: Database connection configuration
        """
        self.db_config = db_config
        self.dangerous_patterns = [
            r'\bDROP\s+TABLE\b',
            r'\bDROP\s+DATABASE\b',
            r'\bDELETE\s+FROM\b',
            r'\bTRUNCATE\b',
            r'\bALTER\s+TABLE\b',
            r'\bCREATE\s+TABLE\b',
            r'\bINSERT\s+INTO\b',
            r'\bUPDATE\s+\w+\s+SET\b'
        ]
        logger.info("✅ QueryExecutor initialized")
    
    def execute_query_safe(self, sql_query: str, session_id: Optional[str] = None,
                          blacklisted_tables: Optional[List[Dict]] = None) -> Tuple[List[Dict[str, Any]], Optional[str]]:
        """
        Execute SQL query with safety checks
        
        Args:
            sql_query: SQL query to execute
            session_id: Optional session ID for tracking
            blacklisted_tables: List of tables to avoid (from user feedback)
            
        Returns:
            Tuple of (results, error_message)
        """
        try:
            # Check blacklisted tables
            if blacklisted_tables:
                error = self._check_blacklisted_tables(sql_query, blacklisted_tables)
                if error:
                    return [], error
            
            # Security check for dangerous operations
            if self._is_dangerous_query(sql_query):
                return [], "Query contains dangerous operation (DROP, DELETE, etc.)"
            
            # Execute with timeout
            results = self._execute_with_timeout(sql_query)
            
            logger.info(f"✅ Query executed: {len(results)} rows returned")
            return results, None
            
        except pymysql.Error as e:
            error_msg = str(e)
            logger.error(f"❌ Database error: {error_msg}")
            return [], error_msg
        except Exception as e:
            error_msg = str(e)
            logger.error(f"❌ Execution error: {error_msg}")
            return [], error_msg
    
    def _check_blacklisted_tables(self, sql_query: str, blacklisted_tables: List[Dict]) -> Optional[str]:
        """Check if query uses blacklisted tables"""
        sql_lower = sql_query.lower()
        
        for failed in blacklisted_tables:
            blacklisted_table = failed['table'].lower()
            # Use word boundaries to avoid false positives
            if re.search(r'\b' + re.escape(blacklisted_table) + r'\b', sql_lower):
                error_msg = (f"❌ QUERY USES BLACKLISTED TABLE '{failed['table']}' - "
                           f"{failed['reason']}. USER EXPLICITLY SAID THIS TABLE "
                           f"{failed['reason'].upper()}!")
                logger.error(error_msg)
                return error_msg
        
        return None
    
    def _is_dangerous_query(self, sql_query: str) -> bool:
        """Check if query contains dangerous operations"""
        query_upper = sql_query.upper()
        
        for pattern in self.dangerous_patterns:
            if re.search(pattern, query_upper):
                logger.warning(f"⚠️ Dangerous pattern detected: {pattern}")
                return True
        
        return False
    
    def _execute_with_timeout(self, sql_query: str) -> List[Dict[str, Any]]:
        """Execute query with timeout"""
        conn = pymysql.connect(**self.db_config, connect_timeout=5)
        
        try:
            df = pd.read_sql(sql_query, conn)
            results = df.to_dict('records')
            return results
        finally:
            conn.close()
    
    def test_connection(self) -> bool:
        """Test database connection"""
        try:
            conn = pymysql.connect(**self.db_config, connect_timeout=5)
            conn.close()
            logger.info("✅ Database connection successful")
            return True
        except Exception as e:
            logger.error(f"❌ Database connection failed: {e}")
            return False
    
    def get_distinct_column_values(self, table_name: str, column_name: str, 
                                  limit: int = 50) -> List[str]:
        """
        Get distinct values from a column
        Used for value validation
        
        Args:
            table_name: Table name
            column_name: Column name
            limit: Maximum values to return
            
        Returns:
            List of distinct values
        """
        try:
            query = f"SELECT DISTINCT {column_name} FROM {table_name} WHERE {column_name} IS NOT NULL LIMIT {limit};"
            results, error = self.execute_query_safe(query)
            
            if error:
                logger.error(f"Error querying distinct values: {error}")
                return []
            
            values = []
            for row in results:
                value = row.get(column_name)
                if value is not None:
                    values.append(str(value))
            
            logger.info(f"📊 Found {len(values)} distinct values for {table_name}.{column_name}")
            return values
            
        except Exception as e:
            logger.error(f"Error getting distinct values: {e}")
            return []
