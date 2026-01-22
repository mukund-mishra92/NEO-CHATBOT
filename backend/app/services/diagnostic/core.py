"""
Diagnostic Support Service - Main Coordinator
Orchestrates CSV loading, search, sessions, and reporting
"""

import logging
from pathlib import Path
from typing import Dict, List, Optional, Any

from .csv_loader import CSVLoader
from .issue_search import IssueSearchEngine
from .session_manager import SessionManager
from .report_formatter import ReportFormatter

logger = logging.getLogger(__name__)


class DiagnosticSupportService:
    """
    Intelligent diagnostic support for NEO system issues
    Uses historical support logs to provide solutions
    
    This is a refactored version with modular components:
    - CSVLoader: Loads bot/station CSV files
    - IssueSearchEngine: Search and scoring logic
    - SessionManager: Step-by-step diagnostic workflow
    - ReportFormatter: Output formatting
    """
    
    def __init__(self):
        """Initialize diagnostic support service"""
        # Point to project-root data/support/support_logs
        self.support_logs_path = (
            Path(__file__).parent.parent.parent.parent.parent / "data" / "support" / "support_logs"
        )
        
        # Load CSV files
        loader = CSVLoader(self.support_logs_path)
        self.bot_level_issues, self.station_level_issues = loader.load_all()
        
        # Initialize components
        self.search_engine = IssueSearchEngine(self.bot_level_issues, self.station_level_issues)
        self.session_manager = SessionManager(self.bot_level_issues, self.station_level_issues)
        self.report_formatter = ReportFormatter(self.bot_level_issues, self.station_level_issues)
        
        logger.info("✅ Diagnostic Support Service initialized")
        logger.info(f"   Bot-level issues: {len(self.bot_level_issues)}")
        logger.info(f"   Station-level issues: {len(self.station_level_issues)}")
    
    # ==================== Search Methods ====================
    
    def search_issue(self, query: str, issue_type: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Search for matching issues based on query
        
        Args:
            query: Search query (problem description, keywords)
            issue_type: Filter by type ('BOT_LEVEL', 'STATION_LEVEL', or None for all)
        
        Returns:
            List of matching issues with relevance scores
        """
        return self.search_engine.search(query, issue_type)
    
    def get_issue_by_id(self, issue_id: int, issue_type: str) -> Optional[Dict[str, Any]]:
        """Get specific issue by ID and type"""
        return self.search_engine.get_by_id(issue_id, issue_type)
    
    def get_all_issues(self, severity: Optional[str] = None) -> Dict[str, List[Dict[str, Any]]]:
        """
        Get all issues, optionally filtered by severity
        
        Args:
            severity: Filter by severity ('High', 'Medium', 'Low', or None for all)
        
        Returns:
            Dictionary with bot_level and station_level issues
        """
        return self.search_engine.get_all(severity)
    
    def get_diagnostic_recommendations(self, symptoms: List[str]) -> Dict[str, Any]:
        """
        Get diagnostic recommendations based on multiple symptoms
        
        Args:
            symptoms: List of observed symptoms/issues
        
        Returns:
            Comprehensive diagnostic report with solutions
        """
        return self.search_engine.get_recommendations(symptoms)
    
    def get_sql_solutions(self, problem_keywords: str) -> List[Dict[str, Any]]:
        """
        Get issues that have SQL query solutions
        
        Args:
            problem_keywords: Keywords to search
        
        Returns:
            List of issues with SQL queries
        """
        return self.search_engine.get_sql_solutions(problem_keywords)
    
    # ==================== Session Methods ====================
    
    def start_diagnostic_session(self, issue_id: int, issue_type: str = "bot_level") -> Dict[str, Any]:
        """
        Start a step-by-step diagnostic session
        
        Args:
            issue_id: ID of the issue
            issue_type: "bot_level" or "station_level"
        
        Returns:
            Session data with first step
        """
        return self.session_manager.start_session(issue_id, issue_type)
    
    def get_session_status(self, session_id: str) -> Dict[str, Any]:
        """Get current session status"""
        return self.session_manager.get_status(session_id)
    
    def submit_step_feedback(self, session_id: str, is_fixed: bool, feedback_notes: str = "") -> Dict[str, Any]:
        """Submit feedback for current step"""
        return self.session_manager.submit_feedback(session_id, is_fixed, feedback_notes)
    
    def close_session(self, session_id: str) -> Dict[str, Any]:
        """Close a diagnostic session"""
        return self.session_manager.close_session(session_id)
    
    # ==================== Reporting Methods ====================
    
    def format_diagnostic_report(self, issue: Dict[str, Any]) -> str:
        """
        Format issue into readable diagnostic report
        
        Args:
            issue: Issue dictionary
        
        Returns:
            Formatted text report
        """
        return self.report_formatter.format_diagnostic_report(issue)
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get diagnostic support statistics"""
        return self.report_formatter.get_statistics()
