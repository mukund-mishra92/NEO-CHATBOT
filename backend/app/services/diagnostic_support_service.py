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
import uuid
import json

logger = logging.getLogger(__name__)


class DiagnosticSupportService:
    """
    Intelligent diagnostic support for NEO system issues
    Uses historical support logs to provide solutions
    """
    
    def __init__(self):
        self.bot_level_issues: List[Dict[str, Any]] = []
        self.station_level_issues: List[Dict[str, Any]] = []
        # Point to the project-root data/support/support_logs (not backend/app/data/...)
        # backend/app/services -> parent.parent is backend/app; need four parents to reach repo root
        self.support_logs_path = (
            Path(__file__).parent.parent.parent.parent / "data" / "support" / "support_logs"
        )
        
        # Session management for step-by-step diagnostics
        self.active_sessions: Dict[str, Dict[str, Any]] = {}
        
        # Load support logs
        self._load_support_logs()
        
        logger.info(f"✅ Diagnostic Support Service initialized")
        logger.info(f"   Bot-level issues: {len(self.bot_level_issues)}")
        logger.info(f"   Station-level issues: {len(self.station_level_issues)}")
    
    def _clean_text(self, text: str) -> str:
        """Remove special characters and clean text"""
        if pd.isna(text) or not isinstance(text, str):
            return ""
        
        # Normalize quotes, dashes, bullets, non-breaking spaces
        replacements = {
            '\u2018': "'", '\u2019': "'", '\u201C': '"', '\u201D': '"',  # curly quotes
            '\u2013': '-', '\u2014': '-',                                    # en/em dashes
            '\u00A0': ' ',                                                   # non-breaking space
            '\u2022': ' ', '\u00B7': ' ', '\u25CF': ' ',                    # bullets: • · ●
        }
        for k, v in replacements.items():
            text = text.replace(k, v)

        # Remove remaining unknown replacement char , , etc.
        text = re.sub(r'[\uFFFD\u0000]', '', text)

        # Collapse whitespace
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
        
        # Remove stop words for better matching
        stop_words = {'the', 'a', 'an', 'is', 'are', 'was', 'were', 'on', 'in', 'at', 'to', 'for', 'of', 'and', 'or', 'any'}
        query_terms = set([w for w in query_lower.split() if w not in stop_words])
        
        # Key phrases that indicate specific issues (higher priority)
        key_phrases = [
            'stopped without error',
            'stopped without any error',
            'not moving',
            'stuck',
            'alarm',
            'battery low',
            'communication lost',
            'communication issue',
            'task failed',
            'lidar issue'
        ]
        
        results = []
        
        # Combine issues based on filter
        issues_to_search = []
        if issue_type == 'BOT_LEVEL':
            issues_to_search = self.bot_level_issues
        elif issue_type == 'STATION_LEVEL':
            issues_to_search = self.station_level_issues
        else:
            issues_to_search = self.bot_level_issues + self.station_level_issues
        
        logger.info(f"🔍 Searching for: '{query}' | Terms: {query_terms} | Searching {len(issues_to_search)} issues")
        
        # Search and score
        for issue in issues_to_search:
            problem_text = issue['problem'].lower()
            solution_text = issue.get('solution', '').lower()
            
            # Calculate relevance score
            score = 0
            match_reasons = []
            
            # Check for key phrase matches (very high priority)
            for phrase in key_phrases:
                if phrase in query_lower and phrase in problem_text:
                    score += 80
                    match_reasons.append(f"Key phrase: '{phrase}'")
                    break
            
            # Exact phrase match (highest priority)
            if query_lower in problem_text or problem_text in query_lower:
                score += 100
                match_reasons.append("Exact phrase")
            
            # Partial phrase matching (3+ consecutive words)
            query_words = query_lower.split()
            if len(query_words) >= 3:
                for i in range(len(query_words) - 2):
                    three_word_phrase = ' '.join(query_words[i:i+3])
                    if three_word_phrase in problem_text:
                        score += 50
                        match_reasons.append(f"3-word: '{three_word_phrase}'")
                        break
            
            # Individual term matches in problem (with higher weight for diagnostic terms)
            problem_terms = set([w for w in problem_text.split() if w not in stop_words])
            matching_terms = query_terms & problem_terms
            
            # Diagnostic terms get higher weight
            diagnostic_terms = {'stopped', 'error', 'alarm', 'failed', 'stuck', 'issue', 'problem', 'bot', 'station'}
            diagnostic_matches = matching_terms & diagnostic_terms
            score += len(diagnostic_matches) * 20  # Higher weight
            score += len(matching_terms - diagnostic_matches) * 10  # Regular terms
            
            if matching_terms:
                match_reasons.append(f"Terms: {', '.join(list(matching_terms)[:5])}")
            
            # Term matches in solution
            solution_terms = set([w for w in solution_text.split() if w not in stop_words])
            solution_matches = query_terms & solution_terms
            score += len(solution_matches) * 5
            
            # Severity boost
            if issue['severity'].lower() == 'high':
                score += 5
            
            if score > 0:
                results.append({
                    **issue,
                    'relevance_score': score,
                    'match_reasons': match_reasons
                })
        
        # Sort by relevance
        results.sort(key=lambda x: x['relevance_score'], reverse=True)
        
        # Log top matches for debugging
        if results:
            logger.info(f"📊 Top match: Score={results[0]['relevance_score']}, Problem='{results[0]['problem'][:60]}...'")
            logger.info(f"   Reasons: {results[0].get('match_reasons', [])}")
        else:
            logger.warning(f"⚠️ No matches found for: '{query}'")
        
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

    def parse_solution_steps(self, solution_text: str) -> List[str]:
        """
        Parse solution text into individual steps
        Supports numbered lists like "1.", "2." or "Step 1:", "Step 2:"
        Also splits on common bullet characters (•, ·, -) if present
        """
        if not solution_text or pd.isna(solution_text):
            return []
        
        # Clean the text
        solution_text = self._clean_text(str(solution_text))
        
        # First, try bullet characters explicitly (they may have been normalized to spaces)
        bullet_split = re.split(r'(?:\n|\r|\s){0,}\u2022|\u00B7|\*|-\s+', solution_text)
        bullet_steps = [s.strip() for s in bullet_split if isinstance(s, str) and s.strip()]
        if len(bullet_steps) > 1:
            return bullet_steps

        # Try different patterns for numbered steps
        patterns = [
            r'(?:^|\n)(\d+)\.\s*([^\n]+)',  # 1. Step text
            r'(?:^|\n)Step\s*(\d+):\s*([^\n]+)',  # Step 1: text
            r'(?:^|\n)(\d+)\)\s*([^\n]+)',  # 1) Step text
        ]
        
        steps = []
        for pattern in patterns:
            matches = re.findall(pattern, solution_text, re.MULTILINE | re.IGNORECASE)
            if matches:
                steps = [step_text.strip() for _, step_text in matches]
                break
        
        # If no numbered pattern found, try splitting by newlines
        if not steps:
            lines = [line.strip() for line in re.split(r'[\n\r]+', solution_text) if line.strip()]
            if len(lines) > 1:
                steps = lines
            else:
                # Single step solution
                steps = [solution_text]
        
        return steps

    def parse_sql_queries(self, sql_text: str) -> List[str]:
        """
        Parse SQL query text into individual queries
        - Normalizes curly quotes to ASCII
        - Splits by semicolon or blank lines
        - Cleans each query
        """
        if not sql_text or pd.isna(sql_text):
            return []
        
        # Normalize quotes/dashes and keep newlines for better splitting
        raw = str(sql_text)
        raw = raw.replace('\u2018', "'").replace('\u2019', "'").replace('\u201C', '"').replace('\u201D', '"')
        raw = raw.replace('\u2013', '-').replace('\u2014', '-')
        # Unify whitespace
        raw = raw.replace('\r', '\n')

        # First split by semicolon, keeping multi-line queries
        parts = []
        for chunk in raw.split(';'):
            cleaned = self._clean_text(chunk)
            if cleaned:
                parts.append(cleaned)

        # If semicolons not present, split by double newlines as a fallback
        if len(parts) <= 1:
            parts = [self._clean_text(x) for x in re.split(r'\n\s*\n+', raw) if self._clean_text(x)]
        
        queries = [p for p in parts if p]
        
        return queries

    def start_diagnostic_session(self, issue_id: int, issue_type: str = "bot_level") -> Dict[str, Any]:
        """
        Start a step-by-step diagnostic session for a specific issue
        Returns session ID and first step information
        """
        # Find the issue
        issues = self.bot_level_issues if issue_type == "bot_level" else self.station_level_issues
        # CSV loader stores the numeric id under 'id'
        issue = next((i for i in issues if i.get('id') == issue_id), None)
        
        if not issue:
            return {
                'success': False,
                'error': f'Issue {issue_id} not found in {issue_type} issues'
            }
        
        # Parse solution steps and SQL queries
        solution_steps = self.parse_solution_steps(issue.get('solution', ''))
        sql_queries = self.parse_sql_queries(issue.get('sql_query', ''))
        
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

    def get_session_status(self, session_id: str) -> Dict[str, Any]:
        """Get current status of a diagnostic session"""
        session = self.active_sessions.get(session_id)
        
        if not session:
            return {
                'success': False,
                'error': 'Session not found or expired'
            }
        
        current_idx = session['current_step']
        solution_steps = session['solution_steps']
        sql_queries = session['sql_queries']
        
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

    def submit_step_feedback(self, session_id: str, is_fixed: bool, feedback_notes: str = "") -> Dict[str, Any]:
        """
        Submit feedback for current step and move to next step if not fixed
        Returns next step or completion status
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
        
        # Record feedback in history
        step_record = {
            'step_number': current_idx + 1,
            'step_text': solution_steps[current_idx] if current_idx < len(solution_steps) else None,
            'sql_query': sql_queries[current_idx] if current_idx < len(sql_queries) else None,
            'is_fixed': is_fixed,
            'feedback_notes': feedback_notes,
            'timestamp': datetime.now().isoformat()
        }
        session['history'].append(step_record)
        
        # If issue is fixed, complete the session
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
        
        # Check if all steps are exhausted
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
        """Close a diagnostic session"""
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
