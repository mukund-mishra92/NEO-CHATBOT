"""
Chat History Service - Comprehensive logging and learning for SQL Assistant
Stores all chat interactions and provides analytics for system improvement
"""

import logging
import uuid
import json
import time
import pymysql
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path
from collections import defaultdict, Counter

logger = logging.getLogger(__name__)


class ChatHistoryService:
    """
    Comprehensive chat history service that:
    - Logs every SQL assistant interaction
    - Tracks query success/failure patterns
    - Learns from corrections (automatic and manual)
    - Provides analytics for system improvement
    - Suggests optimizations based on historical data
    """
    
    def __init__(self, db_config: Dict[str, Any]):
        """Initialize chat history service with database connection"""
        self.db_config = db_config
        self._ensure_tables_exist()
        logger.info("✅ Chat History Service initialized")
    
    def _get_connection(self, retry_attempts: int = 3, connect_timeout: int = 20):
        """Get database connection with retry logic for slow remote servers
        
        Args:
            retry_attempts: Number of connection attempts (default: 3)
            connect_timeout: Connection timeout in seconds (default: 20)
            
        Returns:
            pymysql.Connection object
            
        Raises:
            pymysql.err.OperationalError: If all connection attempts fail
        """
        last_error = None
        
        for attempt in range(1, retry_attempts + 1):
            try:
                if attempt > 1:
                    logger.info(f"🔄 DB connection attempt {attempt}/{retry_attempts}...")
                
                conn = pymysql.connect(
                    host=self.db_config['host'],
                    port=self.db_config['port'],
                    user=self.db_config['user'],
                    password=self.db_config['password'],
                    database=self.db_config['database'],
                    charset='utf8mb4',
                    connect_timeout=connect_timeout,
                    read_timeout=30,
                    write_timeout=30
                )
                
                if attempt > 1:
                    logger.info(f"✅ DB connection successful on attempt {attempt}")
                
                return conn
                
            except Exception as e:
                last_error = e
                if attempt < retry_attempts:
                    wait_time = 1.0 * attempt  # Incremental backoff: 1s, 2s, 3s
                    logger.warning(f"⚠️ DB connection failed (attempt {attempt}/{retry_attempts}): {e}")
                    logger.info(f"⏳ Waiting {wait_time}s before retry...")
                    time.sleep(wait_time)
                else:
                    logger.error(f"❌ All {retry_attempts} connection attempts failed")
        
        # All attempts failed
        raise last_error
    
    def _ensure_tables_exist(self):
        """Create chat history tables if they don't exist"""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            # Main chat log table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS chatbot_chat_history (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    chat_id VARCHAR(100) UNIQUE NOT NULL,
                    session_id VARCHAR(100) NOT NULL,
                    user_id VARCHAR(255) DEFAULT NULL,
                    chatbot_type VARCHAR(50) NOT NULL,
                    user_query TEXT NOT NULL,
                    assistant_response TEXT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    confidence_score DECIMAL(5,4),
                    response_time_ms INT,
                    INDEX idx_session_id (session_id),
                    INDEX idx_user_id (user_id),
                    INDEX idx_chatbot_type (chatbot_type),
                    INDEX idx_timestamp (timestamp)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            # Add user_id column if table already exists without it (compatible with all MySQL versions)
            try:
                cursor.execute("""
                    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE()
                      AND TABLE_NAME = 'chatbot_chat_history'
                      AND COLUMN_NAME = 'user_id'
                """)
                if cursor.fetchone()[0] == 0:
                    cursor.execute("ALTER TABLE chatbot_chat_history ADD COLUMN user_id VARCHAR(255) DEFAULT NULL AFTER session_id")
                    cursor.execute("ALTER TABLE chatbot_chat_history ADD INDEX idx_user_id (user_id)")
                    logger.info("✅ Added user_id column to chatbot_chat_history")
            except Exception as e:
                logger.warning(f"⚠️ Could not add user_id to chatbot_chat_history: {e}")
            
            # SQL query details table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS chatbot_sql_queries (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    chat_id VARCHAR(100) NOT NULL,
                    session_id VARCHAR(100) NOT NULL,
                    user_id VARCHAR(255) DEFAULT NULL,
                    user_query TEXT NOT NULL,
                    generated_sql TEXT,
                    execution_status ENUM('success', 'failed', 'not_executed') DEFAULT 'not_executed',
                    error_message TEXT,
                    rows_returned INT,
                    execution_time_ms INT,
                    tables_used JSON,
                    columns_used JSON,
                    intent VARCHAR(50),
                    entities JSON,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (chat_id) REFERENCES chatbot_chat_history(chat_id) ON DELETE CASCADE,
                    INDEX idx_chat_id (chat_id),
                    INDEX idx_session_id (session_id),
                    INDEX idx_user_id_sql (user_id),
                    INDEX idx_execution_status (execution_status),
                    INDEX idx_timestamp (timestamp)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            # Add user_id column to chatbot_sql_queries if table already exists without it
            try:
                cursor.execute("""
                    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE()
                      AND TABLE_NAME = 'chatbot_sql_queries'
                      AND COLUMN_NAME = 'user_id'
                """)
                if cursor.fetchone()[0] == 0:
                    cursor.execute("ALTER TABLE chatbot_sql_queries ADD COLUMN user_id VARCHAR(255) DEFAULT NULL AFTER session_id")
                    cursor.execute("ALTER TABLE chatbot_sql_queries ADD INDEX idx_user_id_sql (user_id)")
                    logger.info("✅ Added user_id column to chatbot_sql_queries")
            except Exception as e:
                logger.warning(f"⚠️ Could not add user_id to chatbot_sql_queries: {e}")
            
            # Column corrections table (automatic and manual)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS chatbot_column_corrections (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    chat_id VARCHAR(100),
                    session_id VARCHAR(100) NOT NULL,
                    table_name VARCHAR(255) NOT NULL,
                    wrong_column VARCHAR(255) NOT NULL,
                    correct_column VARCHAR(255) NOT NULL,
                    correction_type ENUM('automatic', 'manual', 'feedback') DEFAULT 'automatic',
                    similarity_score DECIMAL(5,4),
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_chat_id (chat_id),
                    INDEX idx_table_name (table_name),
                    INDEX idx_wrong_column (wrong_column),
                    INDEX idx_timestamp (timestamp)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)
            
            # User feedback table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS chatbot_feedback (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    chat_id VARCHAR(100) NOT NULL,
                    session_id VARCHAR(100) NOT NULL,
                    feedback_type ENUM('positive', 'negative', 'neutral') NOT NULL,
                    rating INT,
                    comment TEXT,
                    feedback_category VARCHAR(100),
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (chat_id) REFERENCES chatbot_chat_history(chat_id) ON DELETE CASCADE,
                    INDEX idx_chat_id (chat_id),
                    INDEX idx_feedback_type (feedback_type),
                    INDEX idx_timestamp (timestamp)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)
            
            # Query patterns table (learned patterns)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS chatbot_query_patterns (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    pattern_type VARCHAR(50) NOT NULL,
                    pattern_key VARCHAR(255) NOT NULL,
                    pattern_value TEXT NOT NULL,
                    frequency INT DEFAULT 1,
                    success_rate DECIMAL(5,4),
                    avg_confidence DECIMAL(5,4),
                    last_used DATETIME DEFAULT CURRENT_TIMESTAMP,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    UNIQUE KEY unique_pattern (pattern_type, pattern_key),
                    INDEX idx_pattern_type (pattern_type),
                    INDEX idx_frequency (frequency),
                    INDEX idx_success_rate (success_rate)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info("✅ Chat history tables created/verified")
            
        except Exception as e:
            logger.error(f"❌ Error creating chat history tables: {e}", exc_info=True)
    
    def log_chat_interaction(
        self,
        session_id: str,
        chatbot_type: str,
        user_query: str,
        assistant_response: str,
        confidence_score: float,
        response_time_ms: int,
        user_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Log a chat interaction
        
        Returns:
            chat_id: Unique identifier for this chat
        """
        try:
            chat_id = str(uuid.uuid4())
            
            conn = self._get_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                INSERT INTO chatbot_chat_history 
                (chat_id, session_id, user_id, chatbot_type, user_query, assistant_response, 
                 confidence_score, response_time_ms)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                chat_id, session_id, user_id, chatbot_type, user_query, 
                assistant_response, confidence_score, response_time_ms
            ))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info(f"💾 Logged chat interaction: {chat_id} (user={user_id})")
            return chat_id
            
        except Exception as e:
            logger.error(f"❌ Error logging chat interaction: {e}", exc_info=True)
            return ""

    def get_user_chat_sessions(self, user_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        """
        Get grouped chat sessions for a specific user (identified by email).
        Returns a list of sessions, each with session_id, first query preview,
        chatbot_type, message_count, and timestamp range.
        """
        try:
            conn = self._get_connection()
            cursor = conn.cursor(pymysql.cursors.DictCursor)

            cursor.execute("""
                SELECT
                    session_id,
                    chatbot_type,
                    MIN(timestamp) AS started_at,
                    MAX(timestamp) AS last_message_at,
                    COUNT(*) AS message_count,
                    SUBSTRING(MIN(CONCAT(LPAD(id, 20, '0'), user_query)), 21) AS first_query
                FROM chatbot_chat_history
                WHERE user_id = %s
                GROUP BY session_id, chatbot_type
                ORDER BY MAX(timestamp) DESC
                LIMIT %s
            """, (user_id, limit))

            sessions = cursor.fetchall()
            cursor.close()
            conn.close()

            return [dict(row) for row in sessions]

        except Exception as e:
            logger.error(f"❌ Error getting user chat sessions: {e}", exc_info=True)
            return []

    def get_session_messages(self, session_id: str, user_id: str = None, limit: int = 100) -> List[Dict[str, Any]]:
        """
        Get all messages for a specific session, optionally scoped to a user_id.
        """
        try:
            conn = self._get_connection()
            cursor = conn.cursor(pymysql.cursors.DictCursor)

            if user_id:
                cursor.execute("""
                    SELECT chat_id, user_query, assistant_response, timestamp,
                           confidence_score, chatbot_type
                    FROM chatbot_chat_history
                    WHERE session_id = %s AND user_id = %s
                    ORDER BY timestamp ASC
                    LIMIT %s
                """, (session_id, user_id, limit))
            else:
                cursor.execute("""
                    SELECT chat_id, user_query, assistant_response, timestamp,
                           confidence_score, chatbot_type
                    FROM chatbot_chat_history
                    WHERE session_id = %s
                    ORDER BY timestamp ASC
                    LIMIT %s
                """, (session_id, limit))

            messages = cursor.fetchall()
            cursor.close()
            conn.close()

            return [dict(row) for row in messages]

        except Exception as e:
            logger.error(f"❌ Error getting session messages: {e}", exc_info=True)
            return []

    def delete_session(self, session_id: str) -> int:
        """
        Permanently delete all records for a session from chatbot_chat_history.
        Related chatbot_sql_queries rows are removed automatically via ON DELETE CASCADE.
        Returns the number of deleted rows.
        """
        try:
            conn = self._get_connection()
            cursor = conn.cursor()

            cursor.execute(
                "DELETE FROM chatbot_chat_history WHERE session_id = %s",
                (session_id,)
            )
            deleted = cursor.rowcount

            conn.commit()
            cursor.close()
            conn.close()

            logger.info(f"🗑️ Deleted {deleted} messages for session {session_id}")
            return deleted

        except Exception as e:
            logger.error(f"❌ Error deleting session {session_id}: {e}", exc_info=True)
            return 0
    
    def log_sql_query(
        self,
        chat_id: str,
        session_id: str,
        user_query: str,
        generated_sql: str,
        execution_status: str,
        error_message: Optional[str] = None,
        rows_returned: Optional[int] = None,
        execution_time_ms: Optional[int] = None,
        tables_used: Optional[List[str]] = None,
        columns_used: Optional[List[str]] = None,
        intent: Optional[str] = None,
        entities: Optional[List[str]] = None,
        user_id: Optional[str] = None
    ):
        """Log SQL query details"""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                INSERT INTO chatbot_sql_queries 
                (chat_id, session_id, user_id, user_query, generated_sql, execution_status, 
                 error_message, rows_returned, execution_time_ms, tables_used, 
                 columns_used, intent, entities)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                chat_id, session_id, user_id, user_query, generated_sql, execution_status,
                error_message, rows_returned, execution_time_ms,
                json.dumps(tables_used or []),
                json.dumps(columns_used or []),
                intent,
                json.dumps(entities or [])
            ))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info(f"💾 Logged SQL query for chat: {chat_id} (user={user_id})")
            
        except Exception as e:
            logger.error(f"❌ Error logging SQL query: {e}", exc_info=True)
    
    def log_column_correction(
        self,
        session_id: str,
        table_name: str,
        wrong_column: str,
        correct_column: str,
        correction_type: str = 'automatic',
        similarity_score: Optional[float] = None,
        chat_id: Optional[str] = None
    ):
        """Log column name correction"""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                INSERT INTO chatbot_column_corrections 
                (chat_id, session_id, table_name, wrong_column, correct_column, 
                 correction_type, similarity_score)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (
                chat_id, session_id, table_name, wrong_column, correct_column,
                correction_type, similarity_score
            ))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info(f"💾 Logged column correction: {wrong_column} → {correct_column}")
            
        except Exception as e:
            logger.error(f"❌ Error logging column correction: {e}", exc_info=True)
    
    def log_feedback(
        self,
        chat_id: str,
        session_id: str,
        feedback_type: str,
        rating: Optional[int] = None,
        comment: Optional[str] = None,
        feedback_category: Optional[str] = None
    ):
        """Log user feedback"""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                INSERT INTO chatbot_feedback 
                (chat_id, session_id, feedback_type, rating, comment, feedback_category)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (chat_id, session_id, feedback_type, rating, comment, feedback_category))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info(f"💾 Logged feedback for chat: {chat_id}")
            
        except Exception as e:
            logger.error(f"❌ Error logging feedback: {e}", exc_info=True)
    
    def update_query_pattern(
        self,
        pattern_type: str,
        pattern_key: str,
        pattern_value: str,
        success: bool,
        confidence: float
    ):
        """Update or create a query pattern"""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            # Check if pattern exists
            cursor.execute("""
                SELECT id, frequency, success_rate, avg_confidence 
                FROM chatbot_query_patterns 
                WHERE pattern_type = %s AND pattern_key = %s
            """, (pattern_type, pattern_key))
            
            result = cursor.fetchone()
            
            if result:
                # Update existing pattern
                pattern_id, frequency, success_rate, avg_confidence = result
                new_frequency = frequency + 1
                new_success_rate = ((success_rate * frequency) + (1.0 if success else 0.0)) / new_frequency
                new_avg_confidence = ((avg_confidence * frequency) + confidence) / new_frequency
                
                cursor.execute("""
                    UPDATE chatbot_query_patterns 
                    SET frequency = %s, success_rate = %s, avg_confidence = %s, 
                        last_used = NOW(), pattern_value = %s
                    WHERE id = %s
                """, (new_frequency, new_success_rate, new_avg_confidence, pattern_value, pattern_id))
            else:
                # Create new pattern
                cursor.execute("""
                    INSERT INTO chatbot_query_patterns 
                    (pattern_type, pattern_key, pattern_value, frequency, 
                     success_rate, avg_confidence)
                    VALUES (%s, %s, %s, 1, %s, %s)
                """, (
                    pattern_type, pattern_key, pattern_value,
                    1.0 if success else 0.0, confidence
                ))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.debug(f"💾 Updated query pattern: {pattern_type}:{pattern_key}")
            
        except Exception as e:
            logger.error(f"❌ Error updating query pattern: {e}", exc_info=True)
    
    def get_learned_column_mappings(self, min_frequency: int = 3) -> Dict[str, List[Dict]]:
        """
        Get learned column name mappings from historical corrections
        
        Returns:
            {table_name: [{wrong: str, correct: str, frequency: int, confidence: float}]}
        """
        try:
            conn = self._get_connection()
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            
            cursor.execute("""
                SELECT 
                    table_name,
                    wrong_column,
                    correct_column,
                    COUNT(*) as frequency,
                    AVG(similarity_score) as avg_similarity
                FROM chatbot_column_corrections
                WHERE correction_type IN ('automatic', 'manual')
                GROUP BY table_name, wrong_column, correct_column
                HAVING frequency >= %s
                ORDER BY table_name, frequency DESC
            """, (min_frequency,))
            
            mappings = defaultdict(list)
            for row in cursor.fetchall():
                mappings[row['table_name']].append({
                    'wrong': row['wrong_column'],
                    'correct': row['correct_column'],
                    'frequency': row['frequency'],
                    'confidence': float(row['avg_similarity']) if row['avg_similarity'] else 0.0
                })
            
            cursor.close()
            conn.close()
            
            logger.info(f"📚 Retrieved column mappings for {len(mappings)} tables")
            return dict(mappings)
            
        except Exception as e:
            logger.error(f"❌ Error getting column mappings: {e}", exc_info=True)
            return {}
    
    def get_common_query_patterns(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Get most common successful query patterns"""
        try:
            conn = self._get_connection()
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            
            cursor.execute("""
                SELECT 
                    pattern_type,
                    pattern_key,
                    pattern_value,
                    frequency,
                    success_rate,
                    avg_confidence
                FROM chatbot_query_patterns
                WHERE success_rate > 0.7
                ORDER BY frequency DESC, success_rate DESC
                LIMIT %s
            """, (limit,))
            
            patterns = cursor.fetchall()
            cursor.close()
            conn.close()
            
            logger.info(f"📊 Retrieved {len(patterns)} common query patterns")
            return patterns
            
        except Exception as e:
            logger.error(f"❌ Error getting query patterns: {e}", exc_info=True)
            return []
    
    def get_query_analytics(self, days: int = 7) -> Dict[str, Any]:
        """Get analytics for SQL queries"""
        try:
            conn = self._get_connection()
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            
            cutoff_date = datetime.now() - timedelta(days=days)
            
            # Overall stats
            cursor.execute("""
                SELECT 
                    COUNT(*) as total_queries,
                    SUM(CASE WHEN execution_status = 'success' THEN 1 ELSE 0 END) as successful_queries,
                    SUM(CASE WHEN execution_status = 'failed' THEN 1 ELSE 0 END) as failed_queries,
                    AVG(execution_time_ms) as avg_execution_time,
                    AVG(rows_returned) as avg_rows_returned
                FROM chatbot_sql_queries
                WHERE timestamp >= %s
            """, (cutoff_date,))
            
            overall = cursor.fetchone()
            
            # Most used tables
            cursor.execute("""
                SELECT 
                    JSON_UNQUOTE(JSON_EXTRACT(tables_used, '$[0]')) as table_name,
                    COUNT(*) as usage_count
                FROM chatbot_sql_queries
                WHERE timestamp >= %s AND tables_used IS NOT NULL
                GROUP BY table_name
                ORDER BY usage_count DESC
                LIMIT 10
            """, (cutoff_date,))
            
            top_tables = cursor.fetchall()
            
            # Most common intents
            cursor.execute("""
                SELECT 
                    intent,
                    COUNT(*) as count,
                    AVG(CASE WHEN execution_status = 'success' THEN 1 ELSE 0 END) as success_rate
                FROM chatbot_sql_queries
                WHERE timestamp >= %s AND intent IS NOT NULL
                GROUP BY intent
                ORDER BY count DESC
            """, (cutoff_date,))
            
            intents = cursor.fetchall()
            
            # Error patterns
            cursor.execute("""
                SELECT 
                    error_message,
                    COUNT(*) as error_count
                FROM chatbot_sql_queries
                WHERE timestamp >= %s AND execution_status = 'failed'
                GROUP BY error_message
                ORDER BY error_count DESC
                LIMIT 10
            """, (cutoff_date,))
            
            errors = cursor.fetchall()
            
            cursor.close()
            conn.close()
            
            success_rate = 0.0
            if overall['total_queries'] > 0:
                success_rate = (overall['successful_queries'] / overall['total_queries']) * 100
            
            analytics = {
                'period_days': days,
                'total_queries': overall['total_queries'] or 0,
                'successful_queries': overall['successful_queries'] or 0,
                'failed_queries': overall['failed_queries'] or 0,
                'success_rate': round(success_rate, 2),
                'avg_execution_time_ms': round(overall['avg_execution_time'] or 0, 2),
                'avg_rows_returned': round(overall['avg_rows_returned'] or 0, 2),
                'top_tables': [dict(row) for row in top_tables],
                'common_intents': [dict(row) for row in intents],
                'common_errors': [dict(row) for row in errors]
            }
            
            logger.info(f"📊 Query analytics: {analytics['total_queries']} queries, {analytics['success_rate']}% success rate")
            return analytics
            
        except Exception as e:
            logger.error(f"❌ Error getting query analytics: {e}", exc_info=True)
            return {
                'total_queries': 0,
                'successful_queries': 0,
                'failed_queries': 0,
                'success_rate': 0.0,
                'top_tables': [],
                'common_intents': [],
                'common_errors': []
            }
    
    def get_improvement_suggestions(self) -> Dict[str, List[str]]:
        """Get suggestions for system improvement based on historical data"""
        try:
            suggestions = {
                'column_mappings': [],
                'entity_table_mappings': [],
                'common_errors': [],
                'optimization_tips': []
            }
            
            # Suggest column mappings that should be added
            learned_mappings = self.get_learned_column_mappings(min_frequency=5)
            for table, mappings in learned_mappings.items():
                for mapping in mappings[:3]:  # Top 3 per table
                    suggestions['column_mappings'].append(
                        f"Add mapping: {table}.{mapping['wrong']} → {mapping['correct']} "
                        f"(used {mapping['frequency']} times)"
                    )
            
            # Analyze failed queries for patterns
            conn = self._get_connection()
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            
            # Find entities with low success rates
            cursor.execute("""
                SELECT 
                    entities,
                    COUNT(*) as query_count,
                    AVG(CASE WHEN execution_status = 'success' THEN 1 ELSE 0 END) as success_rate
                FROM chatbot_sql_queries
                WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                    AND entities IS NOT NULL
                GROUP BY entities
                HAVING query_count >= 5 AND success_rate < 0.5
                ORDER BY query_count DESC
                LIMIT 5
            """)
            
            low_success_entities = cursor.fetchall()
            for row in low_success_entities:
                entities = json.loads(row['entities'])
                suggestions['entity_table_mappings'].append(
                    f"Review table mappings for entities: {', '.join(entities)} "
                    f"(success rate: {row['success_rate']*100:.1f}%)"
                )
            
            # Common error messages
            cursor.execute("""
                SELECT 
                    error_message,
                    COUNT(*) as error_count
                FROM chatbot_sql_queries
                WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                    AND execution_status = 'failed'
                    AND error_message IS NOT NULL
                GROUP BY error_message
                ORDER BY error_count DESC
                LIMIT 5
            """)
            
            common_errors = cursor.fetchall()
            for row in common_errors:
                error_msg = row['error_message'][:100]
                suggestions['common_errors'].append(
                    f"Frequent error ({row['error_count']}x): {error_msg}"
                )
            
            cursor.close()
            conn.close()
            
            # General optimization tips
            analytics = self.get_query_analytics(days=30)
            if analytics['success_rate'] < 70:
                suggestions['optimization_tips'].append(
                    f"Overall success rate is low ({analytics['success_rate']}%). "
                    "Consider reviewing table selection and column matching logic."
                )
            
            if analytics['avg_execution_time_ms'] > 1000:
                suggestions['optimization_tips'].append(
                    f"Average query execution time is high ({analytics['avg_execution_time_ms']:.0f}ms). "
                    "Consider adding query optimization hints or reviewing generated SQL."
                )
            
            logger.info(f"💡 Generated {sum(len(v) for v in suggestions.values())} improvement suggestions")
            return suggestions
            
        except Exception as e:
            logger.error(f"❌ Error getting improvement suggestions: {e}", exc_info=True)
            return {
                'column_mappings': [],
                'entity_table_mappings': [],
                'common_errors': [],
                'optimization_tips': []
            }
    
    def learn_from_similar_queries(self, user_query: str, limit: int = 5) -> Dict[str, Any]:
        """
        Learn from similar queries in history to improve current query generation
        Returns successful examples and common failure patterns
        """
        try:
            conn = self._get_connection()
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            
            # Find similar successful queries using keyword matching
            keywords = [word.lower() for word in user_query.split() if len(word) > 3]
            
            learning_data = {
                'successful_examples': [],
                'failed_patterns': [],
                'table_suggestions': set(),
                'column_suggestions': {}
            }
            
            if not keywords:
                return learning_data
            
            # Build LIKE conditions for keyword matching (use sq.user_query to avoid ambiguity)
            like_conditions = " OR ".join(["sq.user_query LIKE %s"] * len(keywords))
            like_params = [f"%{kw}%" for kw in keywords]
            
            # Get successful queries with similar keywords
            query = f"""
                SELECT 
                    sq.user_query,
                    sq.generated_sql,
                    sq.tables_used,
                    sq.columns_used,
                    sq.rows_returned,
                    sq.intent,
                    ch.confidence_score
                FROM chatbot_sql_queries sq
                JOIN chatbot_chat_history ch ON sq.chat_id = ch.chat_id
                WHERE sq.execution_status = 'success'
                AND sq.rows_returned > 0
                AND ({like_conditions})
                ORDER BY ch.timestamp DESC, ch.confidence_score DESC
                LIMIT %s
            """
            
            cursor.execute(query, like_params + [limit])
            successful = cursor.fetchall()
            
            for row in successful:
                learning_data['successful_examples'].append({
                    'query': row['user_query'],
                    'sql': row['generated_sql'],
                    'tables': json.loads(row['tables_used']) if row['tables_used'] else [],
                    'columns': json.loads(row['columns_used']) if row['columns_used'] else [],
                    'rows': row['rows_returned'],
                    'confidence': float(row['confidence_score']) if row['confidence_score'] else 0
                })
                
                # Collect table suggestions
                if row['tables_used']:
                    learning_data['table_suggestions'].update(json.loads(row['tables_used']))
            
            # Get failed queries with similar keywords to learn what NOT to do
            # Note: Use sq.user_query explicitly to avoid ambiguity
            query = f"""
                SELECT 
                    sq.user_query,
                    sq.generated_sql,
                    sq.error_message,
                    sq.tables_used
                FROM chatbot_sql_queries sq
                WHERE sq.execution_status = 'failed'
                AND ({like_conditions})
                ORDER BY sq.timestamp DESC
                LIMIT %s
            """
            
            cursor.execute(query, like_params + [limit])
            failed = cursor.fetchall()
            
            for row in failed:
                learning_data['failed_patterns'].append({
                    'query': row['user_query'],
                    'sql': row['generated_sql'],
                    'error': row['error_message'],
                    'tables': json.loads(row['tables_used']) if row['tables_used'] else []
                })
            
            # Get column corrections for involved tables
            if learning_data['table_suggestions']:
                placeholders = ",".join(["%s"] * len(learning_data['table_suggestions']))
                cursor.execute(f"""
                    SELECT 
                        table_name,
                        wrong_column,
                        correct_column,
                        COUNT(*) as frequency
                    FROM chatbot_column_corrections
                    WHERE table_name IN ({placeholders})
                    GROUP BY table_name, wrong_column, correct_column
                    ORDER BY frequency DESC
                    LIMIT 20
                """, list(learning_data['table_suggestions']))
                
                corrections = cursor.fetchall()
                for corr in corrections:
                    table = corr['table_name']
                    if table not in learning_data['column_suggestions']:
                        learning_data['column_suggestions'][table] = []
                    learning_data['column_suggestions'][table].append({
                        'wrong': corr['wrong_column'],
                        'correct': corr['correct_column'],
                        'frequency': corr['frequency']
                    })
            
            cursor.close()
            conn.close()
            
            # Convert set to list for JSON serialization
            learning_data['table_suggestions'] = list(learning_data['table_suggestions'])
            
            logger.info(f"📚 Learned from history: {len(learning_data['successful_examples'])} successful, "
                       f"{len(learning_data['failed_patterns'])} failed patterns")
            
            return learning_data
            
        except Exception as e:
            logger.error(f"❌ Error learning from similar queries: {e}", exc_info=True)
            return {
                'successful_examples': [],
                'failed_patterns': [],
                'table_suggestions': [],
                'column_suggestions': {}
            }
    
    def get_session_history(self, session_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        """Get chat history for a specific session"""
        try:
            conn = self._get_connection()
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            
            cursor.execute("""
                SELECT 
                    ch.chat_id,
                    ch.user_query,
                    ch.assistant_response,
                    ch.confidence_score,
                    ch.timestamp,
                    sq.generated_sql,
                    sq.execution_status,
                    sq.rows_returned
                FROM chatbot_chat_history ch
                LEFT JOIN chatbot_sql_queries sq ON ch.chat_id = sq.chat_id
                WHERE ch.session_id = %s
                ORDER BY ch.timestamp DESC
                LIMIT %s
            """, (session_id, limit))
            
            history = cursor.fetchall()
            cursor.close()
            conn.close()
            
            return [dict(row) for row in history]
            
        except Exception as e:
            logger.error(f"❌ Error getting session history: {e}", exc_info=True)
            return []

