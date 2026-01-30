"""
Unified Session Manager for NEO Chatbot
Manages conversation sessions across all chatbot sections with memory
"""

import uuid
import logging
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
from enum import Enum

logger = logging.getLogger(__name__)


class SessionType(str, Enum):
    """Types of chatbot sessions"""
    KNOWLEDGE_BASE = "knowledge_base"
    SQL_ASSISTANT = "sql_assistant"
    DIAGNOSTIC = "diagnostic"
    SEMI_AUTO_DIAGNOSTIC = "semi_auto_diagnostic"
    INTELLIGENT_DIAGNOSTIC = "intelligent_diagnostic"
    AGENTIC = "agentic"
    GENERAL = "general"


class UnifiedSessionManager:
    """
    Centralized session management for all chatbot interactions
    Provides ChatGPT-like conversation memory across all sections
    """
    
    def __init__(self):
        """Initialize session manager with empty storage"""
        self.sessions: Dict[str, Dict[str, Any]] = {}
        logger.info("✅ Unified Session Manager initialized")
    
    def create_session(self, 
                      session_type: SessionType = SessionType.GENERAL,
                      initial_message: str = None,
                      metadata: Dict[str, Any] = None) -> str:
        """
        Create a new conversation session
        
        Args:
            session_type: Type of chatbot session
            initial_message: First user message (optional)
            metadata: Additional session metadata
            
        Returns:
            session_id: Unique session identifier
        """
        session_id = str(uuid.uuid4())[:12]  # Short readable ID
        
        self.sessions[session_id] = {
            'session_id': session_id,
            'session_type': session_type.value,
            'created_at': datetime.now().isoformat(),
            'last_updated': datetime.now().isoformat(),
            'conversation_history': [],
            'context': metadata or {},
            'active': True,
            'message_count': 0
        }
        
        # Add initial message if provided
        if initial_message:
            self.add_message(session_id, 'user', initial_message)
        
        logger.info(f"🆕 New session created: {session_id} (type: {session_type.value})")
        return session_id
    
    def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """
        Get session data by ID
        
        Args:
            session_id: Session identifier
            
        Returns:
            Session data dict or None if not found
        """
        session = self.sessions.get(session_id)
        if session:
            # Update last accessed time
            session['last_accessed'] = datetime.now().isoformat()
        return session
    
    def add_message(self, 
                   session_id: str, 
                   role: str, 
                   message: str,
                   metadata: Dict[str, Any] = None) -> bool:
        """
        Add a message to conversation history
        
        Args:
            session_id: Session identifier
            role: Message role ('user', 'assistant', 'system')
            message: Message content
            metadata: Additional message metadata (sources, confidence, etc.)
            
        Returns:
            True if successful, False if session not found
        """
        session = self.sessions.get(session_id)
        if not session:
            logger.warning(f"⚠️ Session not found: {session_id}")
            return False
        
        message_data = {
            'role': role,
            'content': message,
            'timestamp': datetime.now().isoformat(),
            'metadata': metadata or {}
        }
        
        session['conversation_history'].append(message_data)
        session['message_count'] = len(session['conversation_history'])
        session['last_updated'] = datetime.now().isoformat()
        
        logger.debug(f"💬 Message added to session {session_id}: {role} ({len(message)} chars)")
        return True
    
    def get_conversation_history(self, 
                                session_id: str, 
                                last_n: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get conversation history for a session
        
        Args:
            session_id: Session identifier
            last_n: Optional limit to last N messages
            
        Returns:
            List of message dicts
        """
        session = self.get_session(session_id)
        if not session:
            return []
        
        history = session['conversation_history']
        if last_n:
            return history[-last_n:]
        return history
    
    def get_context_for_llm(self, 
                           session_id: str, 
                           max_messages: int = 10) -> List[Dict[str, str]]:
        """
        Get conversation history formatted for LLM context
        
        Args:
            session_id: Session identifier
            max_messages: Maximum number of messages to include
            
        Returns:
            List of dicts with 'role' and 'content' keys for LLM
        """
        history = self.get_conversation_history(session_id, last_n=max_messages)
        
        # Format for LLM (OpenAI/Anthropic format)
        llm_context = []
        for msg in history:
            llm_context.append({
                'role': msg['role'],
                'content': msg['content']
            })
        
        return llm_context
    
    def update_context(self, 
                      session_id: str, 
                      context_updates: Dict[str, Any]) -> bool:
        """
        Update session context/metadata
        
        Args:
            session_id: Session identifier
            context_updates: Dict of context values to update
            
        Returns:
            True if successful, False if session not found
        """
        session = self.sessions.get(session_id)
        if not session:
            return False
        
        session['context'].update(context_updates)
        session['last_updated'] = datetime.now().isoformat()
        return True
    
    def end_session(self, session_id: str) -> bool:
        """
        Mark session as inactive (not deleted, for history)
        
        Args:
            session_id: Session identifier
            
        Returns:
            True if successful, False if session not found
        """
        session = self.sessions.get(session_id)
        if not session:
            return False
        
        session['active'] = False
        session['ended_at'] = datetime.now().isoformat()
        logger.info(f"🔚 Session ended: {session_id}")
        return True
    
    def delete_session(self, session_id: str) -> bool:
        """
        Permanently delete a session
        
        Args:
            session_id: Session identifier
            
        Returns:
            True if deleted, False if not found
        """
        if session_id in self.sessions:
            del self.sessions[session_id]
            logger.info(f"🗑️ Session deleted: {session_id}")
            return True
        return False
    
    def list_active_sessions(self, session_type: Optional[SessionType] = None) -> List[Dict[str, Any]]:
        """
        List all active sessions, optionally filtered by type
        
        Args:
            session_type: Optional filter by session type
            
        Returns:
            List of session summary dicts
        """
        active_sessions = []
        
        for session_id, session in self.sessions.items():
            if not session.get('active', True):
                continue
            
            if session_type and session['session_type'] != session_type.value:
                continue
            
            active_sessions.append({
                'session_id': session_id,
                'session_type': session['session_type'],
                'created_at': session['created_at'],
                'message_count': session['message_count'],
                'last_updated': session.get('last_updated')
            })
        
        # Sort by last updated (most recent first)
        active_sessions.sort(key=lambda x: x.get('last_updated', ''), reverse=True)
        return active_sessions
    
    def clear_old_sessions(self, max_age_hours: int = 24) -> int:
        """
        Clear inactive sessions older than specified hours
        
        Args:
            max_age_hours: Maximum age in hours before deletion
            
        Returns:
            Number of sessions cleared
        """
        now = datetime.now()
        to_remove = []
        
        for session_id, session in self.sessions.items():
            # Skip active sessions
            if session.get('active', True):
                continue
            
            # Check if session has ended_at, otherwise use last_updated
            end_time_str = session.get('ended_at') or session.get('last_updated')
            if not end_time_str:
                continue
            
            try:
                end_time = datetime.fromisoformat(end_time_str)
                if (now - end_time) > timedelta(hours=max_age_hours):
                    to_remove.append(session_id)
            except Exception as e:
                logger.warning(f"⚠️ Error parsing timestamp for session {session_id}: {e}")
        
        # Remove old sessions
        for session_id in to_remove:
            del self.sessions[session_id]
        
        if to_remove:
            logger.info(f"🧹 Cleared {len(to_remove)} old sessions")
        
        return len(to_remove)
    
    def get_session_summary(self, session_id: str) -> Optional[str]:
        """
        Generate a human-readable summary of the session
        
        Args:
            session_id: Session identifier
            
        Returns:
            Summary string or None if session not found
        """
        session = self.get_session(session_id)
        if not session:
            return None
        
        summary = f"Session: {session_id}\n"
        summary += f"Type: {session['session_type']}\n"
        summary += f"Created: {session['created_at']}\n"
        summary += f"Messages: {session['message_count']}\n"
        summary += f"Status: {'Active' if session.get('active') else 'Ended'}\n"
        
        # Add context if available
        if session.get('context'):
            summary += "\nContext:\n"
            for key, value in session['context'].items():
                summary += f"  {key}: {value}\n"
        
        return summary
    
    def get_total_sessions(self) -> Dict[str, int]:
        """
        Get statistics about sessions
        
        Returns:
            Dict with session counts
        """
        total = len(self.sessions)
        active = sum(1 for s in self.sessions.values() if s.get('active', True))
        
        # Count by type
        by_type = {}
        for session in self.sessions.values():
            session_type = session['session_type']
            by_type[session_type] = by_type.get(session_type, 0) + 1
        
        return {
            'total': total,
            'active': active,
            'inactive': total - active,
            'by_type': by_type
        }


# Global singleton instance
_session_manager_instance = None


def get_session_manager() -> UnifiedSessionManager:
    """
    Get the global session manager instance (singleton pattern)
    
    Returns:
        UnifiedSessionManager instance
    """
    global _session_manager_instance
    if _session_manager_instance is None:
        _session_manager_instance = UnifiedSessionManager()
    return _session_manager_instance
