"""
Semi-Automated Diagnostic Support Service
Interactive problem diagnosis with SQL audit and multi-case verification
"""

import pandas as pd
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
import re
import pymysql
from ..core.config import settings

logger = logging.getLogger(__name__)


class SemiAutomatedDiagnosticService:
    """
    Semi-automated diagnostic support with:
    - Similarity search for problem matching
    - Impact-based solution prioritization
    - SQL query execution for problem audit
    - Multi-case verification with user feedback
    - Next-best suggestions when user says "not correct"
    """
    
    def __init__(self):
        self.bot_level_issues: List[Dict[str, Any]] = []
        self.station_level_issues: List[Dict[str, Any]] = []
        self.support_logs_path = Path(__file__).parent.parent / "data" / "support" / "support_logs"
        
        # Database config
        self.db_config = {
            'host': settings.DB_HOST,
            'port': settings.DB_PORT,
            'user': settings.DB_USER,
            'password': settings.DB_PASSWORD,
            'database': settings.DB_NAME,
            'charset': 'utf8mb4'
        }
        
        self._load_support_logs()
        
        logger.info(f"✅ Semi-Automated Diagnostic Service initialized")
        logger.info(f"   Bot-level: {len(self.bot_level_issues)} | Station-level: {len(self.station_level_issues)}")
    
    def _clean_text(self, text: str) -> str:
        """Clean and normalize text"""
        if pd.isna(text) or not isinstance(text, str):
            return ""
        text = re.sub(r'[��������]', '', text)
        text = re.sub(r'\s+', ' ', text)
        return text.strip()
    
    def _load_support_logs(self):
        """Load support logs from CSV files"""
        try:
            # Bot Level
            bot_csv = self.support_logs_path / "NEO Support Logs(Bot Level).csv"
            if bot_csv.exists():
                for encoding in ['latin1', 'utf-8', 'cp1252']:
                    try:
                        df = pd.read_csv(bot_csv, skiprows=1, encoding=encoding)
                        break
                    except UnicodeDecodeError:
                        continue
                
                for _, row in df.iterrows():
                    if pd.notna(row.iloc[0]):
                        self.bot_level_issues.append({
                            'id': int(row.iloc[0]),
                            'problem': self._clean_text(str(row.iloc[1])),
                            'impact': self._clean_text(str(row.iloc[2])),  # Severity/Impact
                            'solution': self._clean_text(str(row.iloc[3])),
                            'sql_query': self._clean_text(str(row.iloc[4])),
                            'outcome': self._clean_text(str(row.iloc[5])),
                            'dev_escalation': self._clean_text(str(row.iloc[6])),
                            'type': 'BOT_LEVEL'
                        })
            
            # Station Level
            station_csv = self.support_logs_path / "NEO Support Logs(Station Level ).csv"
            if station_csv.exists():
                for encoding in ['latin1', 'utf-8', 'cp1252']:
                    try:
                        df = pd.read_csv(station_csv, skiprows=1, encoding=encoding)
                        break
                    except UnicodeDecodeError:
                        continue
                
                for _, row in df.iterrows():
                    if pd.notna(row.iloc[0]):
                        self.station_level_issues.append({
                            'id': int(row.iloc[0]),
                            'problem': self._clean_text(str(row.iloc[1])),
                            'impact': self._clean_text(str(row.iloc[2])),
                            'scenario': self._clean_text(str(row.iloc[3])),
                            'solution': self._clean_text(str(row.iloc[4])),
                            'sql_query': self._clean_text(str(row.iloc[5])),
                            'outcome': self._clean_text(str(row.iloc[6])),
                            'dev_escalation': self._clean_text(str(row.iloc[7])),
                            'type': 'STATION_LEVEL'
                        })
        
        except Exception as e:
            logger.error(f"❌ Error loading support logs: {e}")
    
    def start_diagnosis(self, user_problem: str) -> Dict[str, Any]:
        """
        Start diagnosis by finding similar problems
        
        Returns:
            {
                'session_id': str,
                'matched_cases': List[case],
                'current_case': case with index,
                'requires_sql_audit': bool
            }
        """
        import uuid
        session_id = str(uuid.uuid4())[:8]
        
        # Find similar problems using keyword matching
        matched_cases = self._find_similar_problems(user_problem)
        
        if not matched_cases:
            return {
                'session_id': session_id,
                'matched_cases': [],
                'message': 'No similar cases found. Please provide more details.'
            }
        
        # Sort by impact (High > Medium > Low)
        matched_cases.sort(key=lambda x: self._impact_priority(x['impact']), reverse=True)
        
        current_case = matched_cases[0]
        
        return {
            'session_id': session_id,
            'total_matches': len(matched_cases),
            'matched_cases': matched_cases,
            'current_case_index': 0,
            'current_case': self._format_case_concise(current_case, 0, len(matched_cases)),
            'requires_sql_audit': bool(current_case.get('sql_query'))
        }
    
    def _find_similar_problems(self, query: str) -> List[Dict[str, Any]]:
        """Find problems matching query keywords"""
        query_lower = query.lower()
        query_terms = set(query_lower.split())
        
        all_issues = self.bot_level_issues + self.station_level_issues
        matches = []
        
        for issue in all_issues:
            problem_lower = issue['problem'].lower()
            
            # Scoring
            score = 0
            if query_lower in problem_lower:
                score += 50
            
            problem_terms = set(problem_lower.split())
            matching_terms = query_terms & problem_terms
            score += len(matching_terms) * 5
            
            if score > 0:
                matches.append({**issue, 'similarity_score': score})
        
        matches.sort(key=lambda x: x['similarity_score'], reverse=True)
        return matches[:5]  # Top 5
    
    def _impact_priority(self, impact: str) -> int:
        """Convert impact to priority score"""
        impact_lower = impact.lower()
        if 'high' in impact_lower:
            return 3
        elif 'medium' in impact_lower:
            return 2
        return 1
    
    def _format_case_concise(self, case: Dict[str, Any], index: int, total: int) -> Dict[str, Any]:
        """Format case in concise, point-to-point format"""
        formatted = {
            'case_number': f"{index + 1}/{total}",
            'type': case['type'],
            'problem': case['problem'],
            'impact': case['impact'],
            'solution': case['solution']
        }
        
        if case.get('scenario'):
            formatted['scenario'] = case['scenario']
        
        if case.get('sql_query'):
            formatted['sql_query'] = case['sql_query']
            formatted['expected_outcome'] = case.get('outcome', '')
        
        return formatted
    
    def execute_sql_audit(self, sql_query: str) -> Dict[str, Any]:
        """
        Execute SQL query to audit the problem
        
        Returns:
            {
                'success': bool,
                'data': List[dict] or error message,
                'row_count': int
            }
        """
        try:
            conn = pymysql.connect(**self.db_config)
            cursor = conn.cursor(pymysql.cursors.DictCursor)
            
            cursor.execute(sql_query)
            results = cursor.fetchall()
            
            cursor.close()
            conn.close()
            
            return {
                'success': True,
                'data': results,
                'row_count': len(results),
                'columns': list(results[0].keys()) if results else []
            }
        
        except Exception as e:
            logger.error(f"❌ SQL audit failed: {e}")
            return {
                'success': False,
                'error': str(e),
                'data': None
            }
    
    def handle_user_feedback(
        self,
        session_data: Dict[str, Any],
        is_correct: bool,
        user_comment: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Handle user feedback and suggest next case if not correct
        
        Args:
            session_data: Current session data with matched_cases
            is_correct: True if solution worked, False if not
            user_comment: Optional user feedback
        
        Returns:
            Next case or success message
        """
        if is_correct:
            return {
                'status': 'resolved',
                'message': 'Problem resolved successfully! ✅',
                'solved_with': session_data['current_case']
            }
        
        # Move to next case
        matched_cases = session_data['matched_cases']
        current_index = session_data['current_case_index']
        next_index = current_index + 1
        
        if next_index >= len(matched_cases):
            return {
                'status': 'exhausted',
                'message': 'All known solutions tried. Escalating to development team.',
                'recommendation': 'Manual investigation required'
            }
        
        next_case = matched_cases[next_index]
        
        return {
            'status': 'next_suggestion',
            'message': 'Trying next possible cause...',
            'current_case_index': next_index,
            'current_case': self._format_case_concise(next_case, next_index, len(matched_cases)),
            'requires_sql_audit': bool(next_case.get('sql_query'))
        }
    
    def analyze_sql_results(
        self,
        case: Dict[str, Any],
        sql_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Analyze SQL audit results against expected outcome
        
        Returns:
            Analysis with recommendations
        """
        if not sql_results['success']:
            return {
                'analysis': 'SQL audit failed to execute',
                'recommendation': 'Check SQL query or database connectivity'
            }
        
        row_count = sql_results['row_count']
        expected_outcome = case.get('outcome', '').lower()
        
        # Parse expected outcome for validation
        analysis = {
            'rows_found': row_count,
            'expected': expected_outcome,
            'data_preview': sql_results['data'][:3] if sql_results['data'] else []
        }
        
        # Simple heuristics
        if row_count == 0:
            analysis['interpretation'] = 'No data found - issue may not exist or already resolved'
        elif 'empty' in expected_outcome or 'zero' in expected_outcome or 'no' in expected_outcome:
            if row_count > 0:
                analysis['interpretation'] = 'Problem confirmed - data exists when it should be empty'
                analysis['status'] = 'problem_confirmed'
        else:
            analysis['interpretation'] = f'{row_count} record(s) found'
            analysis['status'] = 'data_found'
        
        return analysis
    
    def get_session_summary(self, session_data: Dict[str, Any]) -> str:
        """Generate concise session summary"""
        current_case = session_data['current_case']
        
        summary = f"""
**Case {current_case['case_number']}** | {current_case['type']} | Impact: {current_case['impact']}

**Problem:** {current_case['problem']}

**Solution:** {current_case['solution']}
"""
        
        if current_case.get('sql_query'):
            summary += f"""
**Audit SQL:**
```sql
{current_case['sql_query']}
```
**Expected:** {current_case.get('expected_outcome', 'N/A')}
"""
        
        return summary.strip()

