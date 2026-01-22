"""
Session Cache Module
Manages session-based query caching and corrections
"""

import logging
from typing import Dict, Any, List, Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class SessionCache:
    """
    Manages session-level caching of queries, corrections, and failed tables
    """
    
    def __init__(self):
        """Initialize session cache"""
        self.session_query_cache: Dict[str, List[Dict[str, Any]]] = {}
        self.session_corrections: Dict[str, Dict[str, Any]] = {}
        logger.info("✅ SessionCache initialized")
    
    def store_successful_query(self, session_id: str, question: str, 
                              sql: str, results_count: int, 
                              sample_data: Optional[List[Dict]] = None):
        """
        Store successful query in session cache
        
        Args:
            session_id: Session identifier
            question: User's question
            sql: Generated SQL
            results_count: Number of results returned
            sample_data: Sample rows (first 3)
        """
        if not session_id:
            return
        
        if session_id not in self.session_query_cache:
            self.session_query_cache[session_id] = []
        
        self.session_query_cache[session_id].append({
            'question': question,
            'sql': sql,
            'results_count': results_count,
            'sample_data': sample_data[:3] if sample_data else [],
            'timestamp': datetime.now().isoformat()
        })
        
        # Keep only last 10 queries
        if len(self.session_query_cache[session_id]) > 10:
            self.session_query_cache[session_id] = self.session_query_cache[session_id][-10:]
        
        logger.info(f"📝 Stored successful query for session {session_id}")
    
    def get_session_queries(self, session_id: str, limit: int = 3) -> List[Dict[str, Any]]:
        """Get recent successful queries for session"""
        if session_id not in self.session_query_cache:
            return []
        
        return self.session_query_cache[session_id][-limit:]
    
    def store_correction(self, session_id: str, wrong: str, correct: str):
        """
        Store user correction
        
        Args:
            session_id: Session identifier
            wrong: Incorrect value/name
            correct: Correct value/name
        """
        if not session_id:
            return
        
        if session_id not in self.session_corrections:
            self.session_corrections[session_id] = {'corrections': []}
        
        self.session_corrections[session_id]['corrections'].append({
            'wrong': wrong,
            'correct': correct,
            'timestamp': datetime.now().isoformat()
        })
        
        logger.info(f"🔧 Stored correction: '{wrong}' → '{correct}'")
    
    def store_failed_table(self, session_id: str, table_name: str, reason: str):
        """
        Store information about tables that failed or don't exist
        
        Args:
            session_id: Session identifier
            table_name: Table that failed
            reason: Reason for failure
        """
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
    
    def get_failed_tables(self, session_id: str) -> List[Dict[str, Any]]:
        """Get failed/blacklisted tables for session"""
        if session_id not in self.session_corrections:
            return []
        
        return self.session_corrections[session_id].get('failed_tables', [])
    
    def get_corrections(self, session_id: str) -> List[Dict[str, Any]]:
        """Get user corrections for session"""
        if session_id not in self.session_corrections:
            return []
        
        return self.session_corrections[session_id].get('corrections', [])
    
    def clear_session(self, session_id: str):
        """Clear all data for a session"""
        if session_id in self.session_query_cache:
            del self.session_query_cache[session_id]
        if session_id in self.session_corrections:
            del self.session_corrections[session_id]
        
        logger.info(f"🗑️ Cleared session: {session_id}")
