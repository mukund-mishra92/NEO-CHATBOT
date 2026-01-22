"""
Issue Search Engine for Diagnostic Support
Handles searching, scoring, and filtering support issues
"""

import logging
from typing import List, Dict, Optional, Any

logger = logging.getLogger(__name__)


class IssueSearchEngine:
    """Intelligent search for support issues with relevance scoring"""
    
    def __init__(self, bot_level_issues: List[Dict[str, Any]], station_level_issues: List[Dict[str, Any]]):
        """
        Initialize search engine
        
        Args:
            bot_level_issues: List of bot-level issue dictionaries
            station_level_issues: List of station-level issue dictionaries
        """
        self.bot_level_issues = bot_level_issues
        self.station_level_issues = station_level_issues
        
        # Stop words for better search relevance
        self.stop_words = {'the', 'a', 'an', 'is', 'are', 'was', 'were', 'on', 'in', 'at', 'to', 'for', 'of', 'and', 'or', 'any'}
        
        # Key phrases that indicate specific issues
        self.key_phrases = [
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
        
        # Diagnostic terms get higher weight
        self.diagnostic_terms = {'stopped', 'error', 'alarm', 'failed', 'stuck', 'issue', 'problem', 'bot', 'station'}
    
    def search(self, query: str, issue_type: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Search for matching issues
        
        Args:
            query: Search query (problem description, keywords)
            issue_type: Filter by type ('BOT_LEVEL', 'STATION_LEVEL', or None for all)
        
        Returns:
            List of matching issues with relevance scores (top 10)
        """
        query_lower = query.lower()
        query_terms = set([w for w in query_lower.split() if w not in self.stop_words])
        
        # Determine which issues to search
        if issue_type == 'BOT_LEVEL':
            issues_to_search = self.bot_level_issues
        elif issue_type == 'STATION_LEVEL':
            issues_to_search = self.station_level_issues
        else:
            issues_to_search = self.bot_level_issues + self.station_level_issues
        
        logger.info(f"🔍 Searching for: '{query}' | Terms: {query_terms} | Searching {len(issues_to_search)} issues")
        
        # Score each issue
        results = []
        for issue in issues_to_search:
            score, reasons = self._calculate_relevance(query_lower, query_terms, issue)
            
            if score > 0:
                results.append({
                    **issue,
                    'relevance_score': score,
                    'match_reasons': reasons
                })
        
        # Sort by relevance
        results.sort(key=lambda x: x['relevance_score'], reverse=True)
        
        # Log results
        if results:
            logger.info(f"📊 Top match: Score={results[0]['relevance_score']}, Problem='{results[0]['problem'][:60]}...'")
            logger.info(f"   Reasons: {results[0].get('match_reasons', [])}")
        else:
            logger.warning(f"⚠️ No matches found for: '{query}'")
        
        return results[:10]  # Return top 10
    
    def _calculate_relevance(self, query_lower: str, query_terms: set, issue: Dict[str, Any]) -> tuple[int, List[str]]:
        """
        Calculate relevance score for an issue
        
        Returns:
            Tuple of (score, match_reasons)
        """
        problem_text = issue['problem'].lower()
        solution_text = issue.get('solution', '').lower()
        
        score = 0
        match_reasons = []
        
        # Key phrase matches (very high priority)
        for phrase in self.key_phrases:
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
        
        # Individual term matches in problem
        problem_terms = set([w for w in problem_text.split() if w not in self.stop_words])
        matching_terms = query_terms & problem_terms
        
        # Weight diagnostic terms higher
        diagnostic_matches = matching_terms & self.diagnostic_terms
        score += len(diagnostic_matches) * 20  # Higher weight
        score += len(matching_terms - diagnostic_matches) * 10  # Regular terms
        
        if matching_terms:
            match_reasons.append(f"Terms: {', '.join(list(matching_terms)[:5])}")
        
        # Term matches in solution
        solution_terms = set([w for w in solution_text.split() if w not in self.stop_words])
        solution_matches = query_terms & solution_terms
        score += len(solution_matches) * 5
        
        # Severity boost
        if issue['severity'].lower() == 'high':
            score += 5
        
        return score, match_reasons
    
    def get_by_id(self, issue_id: int, issue_type: str) -> Optional[Dict[str, Any]]:
        """Get specific issue by ID and type"""
        issues = self.bot_level_issues if issue_type == 'BOT_LEVEL' else self.station_level_issues
        
        for issue in issues:
            if issue['id'] == issue_id:
                return issue
        
        return None
    
    def get_all(self, severity: Optional[str] = None) -> Dict[str, List[Dict[str, Any]]]:
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
    
    def get_recommendations(self, symptoms: List[str]) -> Dict[str, Any]:
        """
        Get diagnostic recommendations based on multiple symptoms
        
        Args:
            symptoms: List of observed symptoms/issues
        
        Returns:
            Comprehensive diagnostic report with solutions
        """
        all_matches = []
        
        for symptom in symptoms:
            matches = self.search(symptom)
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
            'recommended_solutions': sorted_matches[:5],  # Top 5
            'severity_breakdown': self._get_severity_breakdown(sorted_matches),
            'requires_developer': self._check_developer_involvement(sorted_matches)
        }
    
    def get_sql_solutions(self, problem_keywords: str) -> List[Dict[str, Any]]:
        """
        Get issues that have SQL query solutions
        
        Args:
            problem_keywords: Keywords to search
        
        Returns:
            List of issues with SQL queries
        """
        matches = self.search(problem_keywords)
        
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
