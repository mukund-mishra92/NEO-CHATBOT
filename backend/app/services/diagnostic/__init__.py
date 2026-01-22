"""
Diagnostic Support Service Package
Modular diagnostic support with CSV loading, search, sessions, and reporting

Public API:
- DiagnosticSupportService: Main service class (backward compatible)

Internal Modules (can be imported if needed):
- csv_loader: CSVLoader class
- issue_search: IssueSearchEngine class
- session_manager: SessionManager class
- report_formatter: ReportFormatter class
- text_utils: Utility functions for text processing
"""

from .core import DiagnosticSupportService

# Public API - maintains backward compatibility
__all__ = ['DiagnosticSupportService']

# Version info
__version__ = '2.0.0'  # Refactored modular version
