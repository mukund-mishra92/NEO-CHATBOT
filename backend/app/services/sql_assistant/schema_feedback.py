"""
Schema-Aware Feedback Generator
Analyzes SQL errors and provides intelligent feedback with closest matches
"""

import re
import logging
from typing import Dict, List, Tuple, Optional
from difflib import SequenceMatcher

logger = logging.getLogger(__name__)


class SchemaFeedbackGenerator:
    """
    Generates intelligent feedback for SQL errors by finding closest table/column matches
    """

    def __init__(self, schema: Dict[str, List[str]]):
        """
        Args:
            schema: Dict mapping table_name -> list of column names
        """
        self.schema = schema
        self.all_tables = list(schema.keys())
        self.table_to_columns = schema

    def generate_feedback(self, error: str, sql: str) -> str:
        """
        Generate smart feedback based on error type
        
        Args:
            error: The error message from validation or execution
            sql: The failed SQL query
            
        Returns:
            Enhanced feedback with suggestions
        """
        error_lower = error.lower()
        
        # Check for missing LIMIT
        if "limit" in error_lower and "required" in error_lower:
            return "Add LIMIT clause at the end of your query. Example: LIMIT 100"
        
        # Check for unknown table
        if "doesn't exist" in error_lower or "unknown table" in error_lower or "no such table" in error_lower:
            return self._handle_unknown_table(error, sql)
        
        # Check for unknown column
        if "unknown column" in error_lower or "no such column" in error_lower or "ambiguous" in error_lower:
            return self._handle_unknown_column(error, sql)
        
        # Check for syntax error
        if "syntax error" in error_lower or "near" in error_lower:
            return self._handle_syntax_error(error, sql)
        
        # Generic error with SQL context
        return f"{error}\n\nQuery attempted:\n{sql[:200]}..."

    def _handle_unknown_table(self, error: str, sql: str) -> str:
        """Handle unknown table errors"""
        # Extract table name from error
        table_pattern = r"table[s]?\s+['\"]?(\w+)['\"]?"
        match = re.search(table_pattern, error, re.IGNORECASE)
        
        if not match:
            # Try to extract from SQL
            tables_in_sql = self._extract_tables_from_sql(sql)
            if tables_in_sql:
                wrong_table = tables_in_sql[0]
            else:
                return f"Table not found. {error}"
        else:
            wrong_table = match.group(1)
        
        # Find closest match
        closest_matches = self._find_closest_tables(wrong_table, top_k=3)
        
        feedback = f"❌ Table '{wrong_table}' does not exist.\n\n"
        feedback += "✅ Did you mean one of these tables?\n"
        for i, (table, similarity) in enumerate(closest_matches, 1):
            cols = ", ".join(self.table_to_columns[table][:5])
            feedback += f"  {i}. {table} ({similarity:.0%} match)\n"
            feedback += f"     Columns: {cols}...\n"
        
        feedback += "\n💡 Use one of the suggested tables instead."
        return feedback

    def _handle_unknown_column(self, error: str, sql: str) -> str:
        """Handle unknown column errors"""
        # Extract column name from error
        column_pattern = r"column[s]?\s+['\"]?(\w+\.)?(\w+)['\"]?"
        match = re.search(column_pattern, error, re.IGNORECASE)
        
        if not match:
            return f"Column not found. {error}"
        
        wrong_column = match.group(2)
        table_prefix = match.group(1).rstrip('.') if match.group(1) else None
        
        # Find table context
        if table_prefix:
            target_tables = [table_prefix]
        else:
            target_tables = self._extract_tables_from_sql(sql)
        
        if not target_tables:
            return f"Column '{wrong_column}' not found. {error}"
        
        # Find closest columns across relevant tables
        suggestions = []
        for table in target_tables:
            if table in self.table_to_columns:
                closest_cols = self._find_closest_columns(
                    wrong_column, 
                    self.table_to_columns[table],
                    top_k=2
                )
                suggestions.extend([(table, col, sim) for col, sim in closest_cols])
        
        # Sort by similarity
        suggestions.sort(key=lambda x: x[2], reverse=True)
        
        feedback = f"❌ Column '{wrong_column}' does not exist.\n\n"
        feedback += "✅ Did you mean one of these columns?\n"
        for i, (table, col, similarity) in enumerate(suggestions[:5], 1):
            feedback += f"  {i}. {table}.{col} ({similarity:.0%} match)\n"
        
        feedback += f"\n💡 Check the table schema and use the correct column name."
        return feedback

    def _handle_syntax_error(self, error: str, sql: str) -> str:
        """Handle syntax errors"""
        feedback = f"❌ SQL Syntax Error: {error}\n\n"
        feedback += "Common issues:\n"
        feedback += "  • Missing or extra commas\n"
        feedback += "  • Incorrect JOIN syntax\n"
        feedback += "  • Missing closing parenthesis\n"
        feedback += "  • Invalid WHERE clause\n"
        feedback += "  • Missing SELECT keyword\n"
        feedback += f"\n💡 Review the SQL syntax and fix the error."
        return feedback

    def _extract_tables_from_sql(self, sql: str) -> List[str]:
        """Extract table names from SQL query"""
        tables = []
        
        # Pattern for FROM clause
        from_pattern = r'\bFROM\s+([a-zA-Z_][a-zA-Z0-9_]*)'
        from_matches = re.findall(from_pattern, sql, re.IGNORECASE)
        tables.extend(from_matches)
        
        # Pattern for JOIN clauses
        join_pattern = r'\bJOIN\s+([a-zA-Z_][a-zA-Z0-9_]*)'
        join_matches = re.findall(join_pattern, sql, re.IGNORECASE)
        tables.extend(join_matches)
        
        # Remove duplicates and filter valid tables
        tables = list(set(tables))
        return [t for t in tables if t in self.all_tables]

    def _find_closest_tables(self, table_name: str, top_k: int = 3) -> List[Tuple[str, float]]:
        """Find closest matching table names"""
        similarities = []
        for table in self.all_tables:
            similarity = self._similarity(table_name.lower(), table.lower())
            similarities.append((table, similarity))
        
        similarities.sort(key=lambda x: x[1], reverse=True)
        return similarities[:top_k]

    def _find_closest_columns(self, column_name: str, columns: List[str], top_k: int = 3) -> List[Tuple[str, float]]:
        """Find closest matching column names"""
        similarities = []
        for col in columns:
            similarity = self._similarity(column_name.lower(), col.lower())
            if similarity > 0.3:  # Only suggest if somewhat similar
                similarities.append((col, similarity))
        
        similarities.sort(key=lambda x: x[1], reverse=True)
        return similarities[:top_k]

    def _similarity(self, str1: str, str2: str) -> float:
        """Calculate similarity between two strings"""
        return SequenceMatcher(None, str1, str2).ratio()


def get_detailed_error_info(error: Exception, sql: str) -> Tuple[str, Optional[str], Optional[str]]:
    """
    Extract detailed error information
    
    Returns:
        (error_message, error_type, problematic_element)
    """
    error_str = str(error)
    error_type = None
    element = None
    
    if "doesn't exist" in error_str.lower() or "unknown table" in error_str.lower():
        error_type = "unknown_table"
        match = re.search(r"table[s]?\s+['\"]?(\w+)['\"]?", error_str, re.IGNORECASE)
        element = match.group(1) if match else None
    
    elif "unknown column" in error_str.lower():
        error_type = "unknown_column"
        match = re.search(r"column[s]?\s+['\"]?(\w+\.)?(\w+)['\"]?", error_str, re.IGNORECASE)
        element = match.group(2) if match else None
    
    elif "syntax" in error_str.lower():
        error_type = "syntax_error"
    
    return error_str, error_type, element
