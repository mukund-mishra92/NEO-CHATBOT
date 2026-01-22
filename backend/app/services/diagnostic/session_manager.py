"""
Session Manager for Step-by-Step Diagnostic Workflow
Manages diagnostic sessions with step navigation and feedback
"""

import uuid
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional

from .text_utils import parse_solution_steps, parse_sql_queries

logger = logging.getLogger(__name__)


class SessionManager:
    """Manages step-by-step diagnostic sessions"""
    
    def __init__(self, bot_level_issues: List[Dict[str, Any]], station_level_issues: List[Dict[str, Any]]):
        """
        Initialize session manager
        
        Args:
            bot_level_issues: Bot-level issue records
            station_level_issues: Station-level issue records
        """
        self.bot_level_issues = bot_level_issues
        self.station_level_issues = station_level_issues
        self.active_sessions: Dict[str, Dict[str, Any]] = {}
    
    def start_session(self, issue_id: int, issue_type: str = "bot_level") -> Dict[str, Any]:
        """
        Start a step-by-step diagnostic session
        
        Args:
            issue_id: ID of the issue
            issue_type: "bot_level" or "station_level"
        
        Returns:
            Session data with first step
        """
        # Find the issue
        issues = self.bot_level_issues if issue_type == "bot_level" else self.station_level_issues
        issue = next((i for i in issues if i.get('id') == issue_id), None)
        
        if not issue:
            return {
                'success': False,
                'error': f'Issue {issue_id} not found in {issue_type} issues'
            }
        
        # Parse solution steps and SQL queries
        solution_steps = parse_solution_steps(issue.get('solution', ''))
        sql_queries = parse_sql_queries(issue.get('sql_query', ''))
        
        # Create session
        session_id = str(uuid.uuid4())
        session = {
            'session_id': session_id,
            'issue_id': issue_id,
            'issue_type': issue_type,
            'problem': issue.get('problem', ''),
            'severity': issue.get('severity', ''),
            'solution_steps': solution_steps,
            'sql_queries': sql_queries,
            'current_step': 0,
            'total_steps': len(solution_steps),
            'status': 'active',
            'created_at': datetime.now().isoformat(),
            'history': []
        }
        
        self.active_sessions[session_id] = session
        
        # Return first step
        return {
            'success': True,
            'session_id': session_id,
            'problem': session['problem'],
            'severity': session['severity'],
            'total_steps': session['total_steps'],
            'current_step': {
                'step_number': 1,
                'step_text': solution_steps[0] if solution_steps else 'No solution steps available',
                'sql_query': sql_queries[0] if sql_queries else None,
                'has_sql': bool(sql_queries)
            }
        }
    
    def get_status(self, session_id: str) -> Dict[str, Any]:
        """
        Get current session status
        
        Args:
            session_id: Session ID
        
        Returns:
            Current step and session status
        """
        session = self.active_sessions.get(session_id)
        
        if not session:
            return {
                'success': False,
                'error': 'Session not found or expired'
            }
        
        current_idx = session['current_step']
        solution_steps = session['solution_steps']
        sql_queries = session['sql_queries']
        
        # Check if completed
        if current_idx >= len(solution_steps):
            return {
                'success': True,
                'session_id': session_id,
                'status': 'completed',
                'message': 'All diagnostic steps completed',
                'history': session['history']
            }
        
        return {
            'success': True,
            'session_id': session_id,
            'status': session['status'],
            'problem': session['problem'],
            'severity': session['severity'],
            'current_step': {
                'step_number': current_idx + 1,
                'total_steps': session['total_steps'],
                'step_text': solution_steps[current_idx],
                'sql_query': sql_queries[current_idx] if current_idx < len(sql_queries) else None,
                'has_sql': current_idx < len(sql_queries)
            },
            'history': session['history']
        }
    
    def submit_feedback(self, session_id: str, is_fixed: bool, feedback_notes: str = "") -> Dict[str, Any]:
        """
        Submit feedback for current step
        
        Args:
            session_id: Session ID
            is_fixed: Whether issue is resolved
            feedback_notes: Optional notes
        
        Returns:
            Next step or completion status
        """
        session = self.active_sessions.get(session_id)
        
        if not session:
            return {
                'success': False,
                'error': 'Session not found or expired'
            }
        
        current_idx = session['current_step']
        solution_steps = session['solution_steps']
        sql_queries = session['sql_queries']
        
        # Record feedback
        step_record = {
            'step_number': current_idx + 1,
            'step_text': solution_steps[current_idx] if current_idx < len(solution_steps) else None,
            'sql_query': sql_queries[current_idx] if current_idx < len(sql_queries) else None,
            'is_fixed': is_fixed,
            'feedback_notes': feedback_notes,
            'timestamp': datetime.now().isoformat()
        }
        session['history'].append(step_record)
        
        # If fixed, mark as resolved
        if is_fixed:
            session['status'] = 'resolved'
            session['completed_at'] = datetime.now().isoformat()
            
            return {
                'success': True,
                'session_id': session_id,
                'status': 'resolved',
                'message': f'✅ Issue resolved at step {current_idx + 1}',
                'total_steps_used': current_idx + 1,
                'history': session['history']
            }
        
        # Move to next step
        session['current_step'] += 1
        next_idx = session['current_step']
        
        # Check if all steps exhausted
        if next_idx >= len(solution_steps):
            session['status'] = 'unresolved'
            session['completed_at'] = datetime.now().isoformat()
            
            return {
                'success': True,
                'session_id': session_id,
                'status': 'unresolved',
                'message': '⚠️ All diagnostic steps completed but issue not resolved. May need to escalate.',
                'total_steps': len(solution_steps),
                'history': session['history']
            }
        
        # Return next step
        return {
            'success': True,
            'session_id': session_id,
            'status': 'active',
            'message': f'Moving to step {next_idx + 1}',
            'next_step': {
                'step_number': next_idx + 1,
                'total_steps': session['total_steps'],
                'step_text': solution_steps[next_idx],
                'sql_query': sql_queries[next_idx] if next_idx < len(sql_queries) else None,
                'has_sql': next_idx < len(sql_queries)
            },
            'history': session['history']
        }
    
    def close_session(self, session_id: str) -> Dict[str, Any]:
        """
        Close a diagnostic session
        
        Args:
            session_id: Session ID to close
        
        Returns:
            Final session status
        """
        if session_id in self.active_sessions:
            session = self.active_sessions.pop(session_id)
            return {
                'success': True,
                'message': 'Session closed',
                'final_status': session.get('status'),
                'history': session.get('history', [])
            }
        
        return {
            'success': False,
            'error': 'Session not found'
        }
