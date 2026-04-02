"""
Query Feedback System
Collects user feedback on generated SQL queries and automatically improves documentation
"""

import logging
import json
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any
import re

logger = logging.getLogger(__name__)


class QueryFeedbackCollector:
    """Collects and processes user feedback on SQL queries"""
    
    def __init__(self):
        self.data_dir = Path(__file__).parent.parent / "data" / "database"
        self.feedback_file = self.data_dir / "query_feedback.jsonl"
        self.quick_ref_file = self.data_dir / "quick_reference.md"
        self.changelog_file = self.data_dir / "CHANGELOG.md"
        
        # Ensure feedback file exists
        self.feedback_file.parent.mkdir(parents=True, exist_ok=True)
        if not self.feedback_file.exists():
            self.feedback_file.touch()
    
    def record_feedback(
        self,
        query: str,
        sql_generated: str,
        user_question: str,
        feedback_type: str,  # 'positive', 'negative', 'corrected'
        corrected_sql: Optional[str] = None,
        error_message: Optional[str] = None,
        session_id: Optional[str] = None,
        tables_used: Optional[list] = None
    ) -> Dict[str, Any]:
        """
        Record user feedback on a query
        
        Args:
            query: Original user question
            sql_generated: SQL query that was generated
            user_question: Cleaned/processed user question
            feedback_type: 'positive', 'negative', 'corrected'
            corrected_sql: If user provided correction
            error_message: If query failed
            session_id: User session identifier
            tables_used: List of tables involved in query
            
        Returns:
            Feedback record dictionary
        """
        feedback_record = {
            'timestamp': datetime.now().isoformat(),
            'session_id': session_id,
            'user_question': user_question,
            'sql_generated': sql_generated,
            'feedback_type': feedback_type,
            'corrected_sql': corrected_sql,
            'error_message': error_message,
            'tables_used': tables_used or self._extract_tables(sql_generated),
            'query_complexity': len(tables_used or []) if tables_used else 1
        }
        
        # Append to feedback file
        try:
            with open(self.feedback_file, 'a', encoding='utf-8') as f:
                f.write(json.dumps(feedback_record) + '\n')
            
            logger.info(f"✅ Recorded {feedback_type} feedback for query: {user_question[:50]}")
            
            # If positive and complex (2+ tables), consider adding to quick reference
            if feedback_type == 'positive' and feedback_record['query_complexity'] >= 2:
                self._check_for_documentation(feedback_record)
            
            return feedback_record
            
        except Exception as e:
            logger.error(f"❌ Error recording feedback: {e}")
            return feedback_record
    
    def _extract_tables(self, sql: str) -> list:
        """Extract table names from SQL query"""
        try:
            # Simple regex to find table names after FROM and JOIN
            tables = set()
            
            # Match FROM table_name
            from_matches = re.findall(r'FROM\s+([a-zA-Z_][a-zA-Z0-9_]*)', sql, re.IGNORECASE)
            tables.update(from_matches)
            
            # Match JOIN table_name
            join_matches = re.findall(r'JOIN\s+([a-zA-Z_][a-zA-Z0-9_]*)', sql, re.IGNORECASE)
            tables.update(join_matches)
            
            return list(tables)
        except Exception as e:
            logger.error(f"Error extracting tables: {e}")
            return []
    
    def _check_for_documentation(self, feedback_record: Dict[str, Any]):
        """Check if query pattern should be added to documentation"""
        try:
            # Get recent positive feedback for similar patterns
            similar_count = self._count_similar_positive_feedback(
                feedback_record['tables_used'],
                feedback_record['user_question']
            )
            
            # If 3+ similar positive feedbacks, suggest adding to docs
            if similar_count >= 3:
                logger.info(f"🎯 Query pattern has {similar_count} positive feedbacks - Consider documenting!")
                self._suggest_documentation(feedback_record)
            
        except Exception as e:
            logger.error(f"Error checking for documentation: {e}")
    
    def _count_similar_positive_feedback(self, tables: list, question: str) -> int:
        """Count similar positive feedback entries"""
        try:
            count = 0
            with open(self.feedback_file, 'r', encoding='utf-8') as f:
                for line in f:
                    if line.strip():
                        record = json.loads(line)
                        if (record['feedback_type'] == 'positive' and
                            set(record.get('tables_used', [])) == set(tables)):
                            count += 1
            return count
        except Exception as e:
            logger.error(f"Error counting similar feedback: {e}")
            return 0
    
    def _suggest_documentation(self, feedback_record: Dict[str, Any]):
        """Log suggestion to add pattern to documentation"""
        suggestion_file = self.data_dir / "documentation_suggestions.txt"
        
        try:
            with open(suggestion_file, 'a', encoding='utf-8') as f:
                f.write(f"\n{'='*80}\n")
                f.write(f"Suggestion Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"User Question: {feedback_record['user_question']}\n")
                f.write(f"Tables Used: {', '.join(feedback_record['tables_used'])}\n")
                f.write(f"SQL Pattern:\n{feedback_record['sql_generated']}\n")
                f.write(f"Positive Feedback Count: 3+\n")
                f.write(f"\n✅ ACTION: Consider adding to quick_reference.md\n")
                f.write(f"{'='*80}\n")
            
            logger.info(f"📝 Documentation suggestion logged to {suggestion_file}")
            
        except Exception as e:
            logger.error(f"Error logging documentation suggestion: {e}")
    
    def get_feedback_stats(self) -> Dict[str, Any]:
        """Get statistics about collected feedback"""
        stats = {
            'total_feedback': 0,
            'positive': 0,
            'negative': 0,
            'corrected': 0,
            'common_tables': {},
            'common_patterns': []
        }
        
        try:
            with open(self.feedback_file, 'r', encoding='utf-8') as f:
                for line in f:
                    if line.strip():
                        record = json.loads(line)
                        stats['total_feedback'] += 1
                        stats[record['feedback_type']] = stats.get(record['feedback_type'], 0) + 1
                        
                        # Track table usage
                        for table in record.get('tables_used', []):
                            stats['common_tables'][table] = stats['common_tables'].get(table, 0) + 1
            
            # Sort common tables
            stats['common_tables'] = dict(sorted(
                stats['common_tables'].items(),
                key=lambda x: x[1],
                reverse=True
            )[:10])
            
        except Exception as e:
            logger.error(f"Error getting feedback stats: {e}")
        
        return stats
    
    def get_top_positive_patterns(self, limit: int = 10) -> list:
        """Get top positive query patterns that should be documented"""
        patterns = {}
        
        try:
            with open(self.feedback_file, 'r', encoding='utf-8') as f:
                for line in f:
                    if line.strip():
                        record = json.loads(line)
                        if record['feedback_type'] == 'positive':
                            # Create pattern key from tables
                            tables_key = tuple(sorted(record.get('tables_used', [])))
                            
                            if tables_key not in patterns:
                                patterns[tables_key] = {
                                    'count': 0,
                                    'tables': record.get('tables_used', []),
                                    'example_question': record['user_question'],
                                    'example_sql': record['sql_generated'],
                                    'complexity': record.get('query_complexity', 1)
                                }
                            
                            patterns[tables_key]['count'] += 1
            
            # Sort by count and return top patterns
            sorted_patterns = sorted(
                patterns.values(),
                key=lambda x: (x['count'], x['complexity']),
                reverse=True
            )
            
            return sorted_patterns[:limit]
            
        except Exception as e:
            logger.error(f"Error getting top patterns: {e}")
            return []
    
    def auto_update_quick_reference(self, min_positive_feedback: int = 5) -> bool:
        """
        Automatically update quick_reference.md with proven patterns
        
        Args:
            min_positive_feedback: Minimum positive feedback count to auto-add
            
        Returns:
            True if updates were made
        """
        try:
            top_patterns = self.get_top_positive_patterns(limit=20)
            
            # Filter patterns with enough positive feedback
            patterns_to_add = [
                p for p in top_patterns 
                if p['count'] >= min_positive_feedback and p['complexity'] >= 2
            ]
            
            if not patterns_to_add:
                logger.info("No patterns meet criteria for auto-documentation")
                return False
            
            # Read current quick reference
            with open(self.quick_ref_file, 'r', encoding='utf-8') as f:
                current_content = f.read()
            
            # Check if pattern already documented
            new_patterns = []
            for pattern in patterns_to_add:
                tables_str = ', '.join(pattern['tables'])
                if tables_str not in current_content:
                    new_patterns.append(pattern)
            
            if not new_patterns:
                logger.info("All top patterns already documented")
                return False
            
            # Append new patterns to quick reference
            with open(self.quick_ref_file, 'a', encoding='utf-8') as f:
                f.write(f"\n\n---\n")
                f.write(f"## Auto-Generated Patterns (Added: {datetime.now().strftime('%Y-%m-%d')})\n")
                f.write(f"_These patterns were automatically added based on positive user feedback_\n\n")
                
                for pattern in new_patterns:
                    f.write(f"### Pattern: {' + '.join(pattern['tables'])}\n")
                    f.write(f"**Positive Feedback:** {pattern['count']} users\n")
                    f.write(f"**Example Question:** {pattern['example_question']}\n\n")
                    f.write(f"**Proven SQL:**\n```sql\n{pattern['example_sql']}\n```\n\n")
            
            # Log to changelog
            self._log_auto_update(new_patterns)
            
            logger.info(f"✅ Auto-updated quick_reference.md with {len(new_patterns)} new patterns")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error auto-updating quick reference: {e}")
            return False
    
    def _log_auto_update(self, patterns: list):
        """Log auto-update to changelog"""
        try:
            with open(self.changelog_file, 'a', encoding='utf-8') as f:
                f.write(f"\n\n### {datetime.now().strftime('%Y-%m-%d')} - Automated System\n")
                f.write(f"**Change Type:** Auto-Update from User Feedback\n")
                f.write(f"**Query Types:** {len(patterns)} new proven patterns\n")
                f.write(f"**Why:** Patterns received 5+ positive user feedbacks\n")
                f.write(f"**SQL Added:** Yes\n")
                f.write(f"**Tested:** Yes (by users)\n\n")
                f.write(f"**Patterns Added:**\n")
                for pattern in patterns:
                    f.write(f"- {' + '.join(pattern['tables'])} ({pattern['count']} positive feedbacks)\n")
        except Exception as e:
            logger.error(f"Error logging auto-update: {e}")


# Global instance
feedback_collector = QueryFeedbackCollector()

