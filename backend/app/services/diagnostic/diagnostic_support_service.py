"""
NEO Diagnostic Support Service
Provides intelligent troubleshooting based on historical support logs
"""

import pandas as pd
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime
import re

logger = logging.getLogger(__name__)


class DiagnosticSupportService:
    """
    Intelligent diagnostic support for NEO system issues
    Uses historical support logs to provide solutions
    """
    
    def __init__(self):
        self.bot_level_issues: List[Dict[str, Any]] = []
        self.station_level_issues: List[Dict[str, Any]] = []
        self.support_logs_path = Path(__file__).parent.parent / "data" / "support" / "support_logs"
        
        # Load support logs
        self._load_support_logs()
        
        logger.info(f"✅ Diagnostic Support Service initialized")
        logger.info(f"   Bot-level issues: {len(self.bot_level_issues)}")
        logger.info(f"   Station-level issues: {len(self.station_level_issues)}")
    
    def _clean_text(self, text: str) -> str:
        """Remove special characters and clean text"""
        if pd.isna(text) or not isinstance(text, str):
            return ""
        
        # Remove bullet points and special characters
        text = re.sub(r'[��������]', '', text)
        text = re.sub(r'\s+', ' ', text)
        return text.strip()
    
    def _load_support_logs(self):
        """Load support logs from CSV files"""
        try:
            # Load Bot Level Issues
            bot_csv_path = self.support_logs_path / "NEO Support Logs(Bot Level).csv"
            if bot_csv_path.exists():
                # Try different encodings
                for encoding in ['utf-8', 'latin1', 'cp1252', 'iso-8859-1']:
                    try:
                        df_bot = pd.read_csv(bot_csv_path, skiprows=1, encoding=encoding)
                        logger.info(f"✅ Successfully loaded bot CSV with {encoding} encoding")
                        break
                    except UnicodeDecodeError:
                        continue
                else:
                    logger.error(f"❌ Could not decode bot CSV with any encoding")
                    return
                
                for _, row in df_bot.iterrows():
                    if pd.notna(row.iloc[0]):  # Check if S NO exists
                        issue = {
                            'id': int(row.iloc[0]) if pd.notna(row.iloc[0]) else 0,
                            'problem': self._clean_text(str(row.iloc[1])),
                            'severity': self._clean_text(str(row.iloc[2])),
                            'solution': self._clean_text(str(row.iloc[3])),
                            'sql_query': self._clean_text(str(row.iloc[4])),
                            'outcome': self._clean_text(str(row.iloc[5])),
                            'reported_to_dev': self._clean_text(str(row.iloc[6])),
                            'type': 'BOT_LEVEL'
                        }
                        
                        if issue['problem']:  # Only add if problem statement exists
                            self.bot_level_issues.append(issue)
                
                logger.info(f"✅ Loaded {len(self.bot_level_issues)} bot-level issues")
            
            # Load Station Level Issues
            station_csv_path = self.support_logs_path / "NEO Support Logs(Station Level ).csv"
            if station_csv_path.exists():
                # Try different encodings
                for encoding in ['utf-8', 'latin1', 'cp1252', 'iso-8859-1']:
                    try:
                        df_station = pd.read_csv(station_csv_path, skiprows=1, encoding=encoding)
                        logger.info(f"✅ Successfully loaded station CSV with {encoding} encoding")
                        break
                    except UnicodeDecodeError:
                        continue
                else:
                    logger.error(f"❌ Could not decode station CSV with any encoding")
                    return
                
                for _, row in df_station.iterrows():
                    if pd.notna(row.iloc[0]):
                        issue = {
                            'id': int(row.iloc[0]) if pd.notna(row.iloc[0]) else 0,
                            'problem': self._clean_text(str(row.iloc[1])),
                            'severity': self._clean_text(str(row.iloc[2])),
                            'scenario': self._clean_text(str(row.iloc[3])),
                            'solution': self._clean_text(str(row.iloc[4])),
                            'sql_query': self._clean_text(str(row.iloc[5])),
                            'outcome': self._clean_text(str(row.iloc[6])),
                            'reported_to_dev': self._clean_text(str(row.iloc[7])),
                            'type': 'STATION_LEVEL'
                        }
                        
                        if issue['problem']:
                            self.station_level_issues.append(issue)
                
                logger.info(f"✅ Loaded {len(self.station_level_issues)} station-level issues")
        
        except Exception as e:
            logger.error(f"❌ Error loading support logs: {e}")
            import traceback
            traceback.print_exc()
    
    def search_issue(self, query: str, issue_type: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Search for matching issues based on query
        
        Args:
            query: Search query (problem description, keywords)
            issue_type: Filter by type ('BOT_LEVEL', 'STATION_LEVEL', or None for all)
        
        Returns:
            List of matching issues with relevance scores
        """
        query_lower = query.lower()
        query_terms = set(query_lower.split())
        
        results = []
        
        # Combine issues based on filter
        issues_to_search = []
        if issue_type == 'BOT_LEVEL':
            issues_to_search = self.bot_level_issues
        elif issue_type == 'STATION_LEVEL':
            issues_to_search = self.station_level_issues
        else:
            issues_to_search = self.bot_level_issues + self.station_level_issues
        
        # Search and score
        for issue in issues_to_search:
            problem_text = issue['problem'].lower()
            solution_text = issue.get('solution', '').lower()
            
            # Calculate relevance score
            score = 0
            
            # Exact phrase match (highest priority)
            if query_lower in problem_text:
                score += 100
            
            # Individual term matches in problem
            problem_terms = set(problem_text.split())
            matching_terms = query_terms & problem_terms
            score += len(matching_terms) * 10
            
            # Term matches in solution
            solution_terms = set(solution_text.split())
            solution_matches = query_terms & solution_terms
            score += len(solution_matches) * 5
            
            # Severity boost
            if issue['severity'].lower() == 'high':
                score += 2
            
            if score > 0:
                results.append({
                    **issue,
                    'relevance_score': score
                })
        
        # Sort by relevance
        results.sort(key=lambda x: x['relevance_score'], reverse=True)
        
        return results[:10]  # Return top 10 matches
    
    def get_issue_by_id(self, issue_id: int, issue_type: str) -> Optional[Dict[str, Any]]:
        """Get specific issue by ID and type"""
        issues = self.bot_level_issues if issue_type == 'BOT_LEVEL' else self.station_level_issues
        
        for issue in issues:
            if issue['id'] == issue_id:
                return issue
        
        return None
    
    def get_all_issues(self, severity: Optional[str] = None) -> Dict[str, List[Dict[str, Any]]]:
        """
        Get all issues, optionally filtered by severity
        
        Args:
            severity: Filter by severity ('High', 'Medium', 'Low', or None for all)
        
        Returns:
            Dictionary with bot_level and station_level issues
        """
        bot_issues = self.bot_level_issues
        station_issues = self.station_level_issues
        
        if severity:
            severity_lower = severity.lower()
            bot_issues = [i for i in bot_issues if i['severity'].lower() == severity_lower]
            station_issues = [i for i in station_issues if i['severity'].lower() == severity_lower]
        
        return {
            'bot_level': bot_issues,
            'station_level': station_issues,
            'total_count': len(bot_issues) + len(station_issues)
        }
    
    def get_diagnostic_recommendations(self, symptoms: List[str]) -> Dict[str, Any]:
        """
        Get diagnostic recommendations based on multiple symptoms
        
        Args:
            symptoms: List of observed symptoms/issues
        
        Returns:
            Comprehensive diagnostic report with solutions
        """
        all_matches = []
        
        for symptom in symptoms:
            matches = self.search_issue(symptom)
            all_matches.extend(matches)
        
        # Remove duplicates and sort by relevance
        unique_matches = {}
        for match in all_matches:
            key = f"{match['type']}_{match['id']}"
            if key not in unique_matches or match['relevance_score'] > unique_matches[key]['relevance_score']:
                unique_matches[key] = match
        
        sorted_matches = sorted(unique_matches.values(), key=lambda x: x['relevance_score'], reverse=True)
        
        return {
            'symptoms_analyzed': symptoms,
            'total_matches': len(sorted_matches),
            'recommended_solutions': sorted_matches[:5],  # Top 5 recommendations
            'severity_breakdown': self._get_severity_breakdown(sorted_matches),
            'requires_developer': self._check_developer_involvement(sorted_matches)
        }
    
    def _get_severity_breakdown(self, issues: List[Dict[str, Any]]) -> Dict[str, int]:
        """Get count of issues by severity"""
        breakdown = {'High': 0, 'Medium': 0, 'Low': 0}
        
        for issue in issues:
            severity = issue.get('severity', 'Low')
            if severity in breakdown:
                breakdown[severity] += 1
        
        return breakdown
    
    def _check_developer_involvement(self, issues: List[Dict[str, Any]]) -> bool:
        """Check if any issue requires developer involvement"""
        for issue in issues:
            if issue.get('reported_to_dev', '').upper() == 'Y':
                return True
        return False
    
    def get_sql_solutions(self, problem_keywords: str) -> List[Dict[str, Any]]:
        """
        Get issues that have SQL query solutions
        
        Args:
            problem_keywords: Keywords to search
        
        Returns:
            List of issues with SQL queries
        """
        matches = self.search_issue(problem_keywords)
        
        sql_solutions = []
        for match in matches:
            if match.get('sql_query') and match['sql_query'].strip():
                sql_solutions.append({
                    'problem': match['problem'],
                    'severity': match['severity'],
                    'sql_query': match['sql_query'],
                    'solution_steps': match['solution'],
                    'type': match['type']
                })
        
        return sql_solutions
    
    def format_diagnostic_report(self, issue: Dict[str, Any]) -> str:
        """
        Format issue into readable diagnostic report
        
        Args:
            issue: Issue dictionary
        
        Returns:
            Formatted text report
        """
        report = f"""
╔═══════════════════════════════════════════════════════════════
║ DIAGNOSTIC REPORT - {issue['type'].replace('_', ' ')}
╠═══════════════════════════════════════════════════════════════

📌 PROBLEM:
{issue['problem']}

⚠️ SEVERITY: {issue['severity']}

🔧 SOLUTION STEPS:
{issue['solution']}
"""
        
        if issue.get('scenario'):
            report += f"""
📋 SCENARIO:
{issue['scenario']}
"""
        
        if issue.get('sql_query') and issue['sql_query'].strip():
            report += f"""
💻 SQL QUERY:
{issue['sql_query']}
"""
        
        if issue.get('outcome'):
            report += f"""
✅ EXPECTED OUTCOME:
{issue['outcome']}
"""
        
        if issue.get('reported_to_dev', '').upper() == 'Y':
            report += f"""
⚡ NOTE: This issue has been escalated to developers
"""
        
        report += "\n╚═══════════════════════════════════════════════════════════════\n"
        
        return report
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get diagnostic support statistics"""
        all_issues = self.bot_level_issues + self.station_level_issues
        
        high_severity = sum(1 for i in all_issues if i['severity'].lower() == 'high')
        medium_severity = sum(1 for i in all_issues if i['severity'].lower() == 'medium')
        low_severity = sum(1 for i in all_issues if i['severity'].lower() == 'low')
        
        with_sql = sum(1 for i in all_issues if i.get('sql_query', '').strip())
        reported_to_dev = sum(1 for i in all_issues if i.get('reported_to_dev', '').upper() == 'Y')
        
        return {
            'total_issues': len(all_issues),
            'bot_level_count': len(self.bot_level_issues),
            'station_level_count': len(self.station_level_issues),
            'severity': {
                'high': high_severity,
                'medium': medium_severity,
                'low': low_severity
            },
            'with_sql_solutions': with_sql,
            'reported_to_developers': reported_to_dev
        }

