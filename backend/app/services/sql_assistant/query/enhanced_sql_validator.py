"""
Enhanced SQL Validator - Layer 2
Validates SQL queries and provides detailed feedback for retry
"""

import logging
from typing import Tuple, Optional, Dict, Any
import re

logger = logging.getLogger(__name__)


class EnhancedSQLValidator:
    """
    Layer 2: Comprehensive SQL validation
    - Schema validation (tables, columns, relationships)
    - Syntax validation
    - JOIN path validation
    - Result validation
    - Provides detailed feedback for retry
    """

    def __init__(self, schema_parser, schema_validator, schema_graph, query_executor):
        self.schema_parser = schema_parser
        self.schema_validator = schema_validator
        self.schema_graph = schema_graph
        self.query_executor = query_executor

    def validate_and_execute(
        self,
        sql_query: str,
        question: str
    ) -> Tuple[bool, Optional[Any], Optional[str], Dict[str, Any]]:
        """
        Validate and execute SQL query
        
        Args:
            sql_query: SQL query to validate and execute
            question: Original user question for context
            
        Returns:
            Tuple of (success, results, error_feedback, validation_details)
            - success: True if query is valid and executed successfully
            - results: Query results if successful, None otherwise
            - error_feedback: Detailed error message for retry, None if successful
            - validation_details: Dict with validation metrics
        """
        validation_details = {
            "syntax_valid": False,
            "schema_valid": False,
            "joins_valid": False,
            "executed": False,
            "has_results": False,
            "error_type": None
        }
        
        # Step 1: Basic syntax check
        syntax_ok, syntax_error = self._check_syntax(sql_query)
        validation_details["syntax_valid"] = syntax_ok
        
        if not syntax_ok:
            validation_details["error_type"] = "syntax"
            error_feedback = self._build_syntax_error_feedback(syntax_error, sql_query)
            return False, None, error_feedback, validation_details
        
        # Step 2: Schema validation (tables)
        tables_ok, table_errors = self.schema_validator.validate_sql_tables(sql_query)
        if not tables_ok:
            validation_details["error_type"] = "unknown_table"
            error_feedback = self._build_table_error_feedback(table_errors, sql_query)
            return False, None, error_feedback, validation_details
        
        # Step 3: Schema validation (columns)
        columns_ok, column_errors = self.schema_validator.validate_sql_columns(sql_query)
        validation_details["schema_valid"] = columns_ok
        
        if not columns_ok:
            validation_details["error_type"] = "unknown_column"
            error_feedback = self._build_column_error_feedback(column_errors, sql_query)
            return False, None, error_feedback, validation_details
        
        # Step 4: JOIN validation
        joins_ok, join_errors = self._validate_joins(sql_query)
        validation_details["joins_valid"] = joins_ok
        
        if not joins_ok:
            validation_details["error_type"] = "invalid_join"
            error_feedback = self._build_join_error_feedback(join_errors, sql_query)
            return False, None, error_feedback, validation_details
        
        # Step 5: Execute query
        try:
            results, exec_error = self.query_executor.execute_query_safe(sql_query)
            validation_details["executed"] = exec_error is None
            
            if exec_error:
                validation_details["error_type"] = "execution"
                error_feedback = self._build_execution_error_feedback(exec_error, sql_query)
                return False, None, error_feedback, validation_details
            
            # Check if we have results
            validation_details["has_results"] = results and len(results) > 0
            
            # Step 6: Validate results make sense
            if not validation_details["has_results"]:
                # Empty results might be valid, but flag it
                logger.warning("⚠️ Query executed but returned no results")
                validation_details["error_type"] = "empty_results"
            
            return True, results, None, validation_details
            
        except Exception as e:
            validation_details["error_type"] = "execution"
            error_feedback = self._build_execution_error_feedback(str(e), sql_query)
            return False, None, error_feedback, validation_details

    def _check_syntax(self, sql_query: str) -> Tuple[bool, Optional[str]]:
        """Basic SQL syntax checks"""
        sql_upper = sql_query.upper().strip()
        
        # Must start with SELECT or WITH
        if not (sql_upper.startswith('SELECT') or sql_upper.startswith('WITH')):
            return False, "Query must start with SELECT or WITH"
        
        # Check for balanced parentheses
        if sql_query.count('(') != sql_query.count(')'):
            return False, "Unbalanced parentheses in query"
        
        # Check for basic SQL keywords
        if 'FROM' not in sql_upper:
            return False, "Missing FROM clause"
        
        # Check for common syntax errors
        if re.search(r'SELECT\s+FROM', sql_upper):
            return False, "Missing column list after SELECT"
        
        return True, None

    def _validate_joins(self, sql_query: str) -> Tuple[bool, Optional[str]]:
        """Validate JOIN clauses"""
        sql_upper = sql_query.upper()
        
        # Find all JOINs
        join_pattern = r'JOIN\s+(\w+)'
        joins = re.findall(join_pattern, sql_upper)
        
        if not joins:
            # No joins is fine
            return True, None
        
        # Check each JOIN has an ON clause
        # Count JOINs and ONs
        join_count = len(re.findall(r'\bJOIN\b', sql_upper))
        on_count = len(re.findall(r'\bON\b', sql_upper))
        
        if join_count > on_count:
            return False, f"Found {join_count} JOIN(s) but only {on_count} ON clause(s). Each JOIN must have an ON clause."
        
        return True, None

    def _build_syntax_error_feedback(self, error: str, sql_query: str) -> str:
        """Build detailed feedback for syntax errors"""
        feedback = f"""## Syntax Error

**Error:** {error}

**Your Query:**
```sql
{sql_query}
```

**Common Fixes:**
- Ensure query starts with SELECT or WITH
- Check all parentheses are balanced
- Verify FROM clause is present
- Make sure column list is not empty after SELECT
- Check for missing commas between columns
"""
        return feedback

    def _build_table_error_feedback(self, errors: list, sql_query: str) -> str:
        """Build detailed feedback for table errors"""
        available_tables = self.schema_parser.get_available_tables()
        
        feedback = f"""## Unknown Table Error

**Invalid tables in your query:** {', '.join(errors)}

**Your Query:**
```sql
{sql_query}
```

**Available Tables:**
{', '.join(sorted(available_tables))}

**Fix:** Replace the invalid table names with correct table names from the list above.
Check for typos and verify the table exists in the schema.
"""
        return feedback

    def _build_column_error_feedback(self, errors: list, sql_query: str) -> str:
        """Build detailed feedback for column errors"""
        feedback = f"""## Unknown Column Error

**Invalid columns found:** {len(errors)} column(s)

**Your Query:**
```sql
{sql_query}
```

**Issues:**
"""
        for error_detail in errors[:5]:  # Show first 5 errors
            feedback += f"- {error_detail}\n"
        
        # Try to suggest correct column names
        feedback += "\n**Suggestions:**\n"
        for error_detail in errors[:3]:
            table_name = self._extract_table_from_error(error_detail)
            if table_name:
                columns = self.schema_parser.get_table_columns(table_name)
                feedback += f"- Columns available in `{table_name}`: {', '.join(columns[:10])}\n"
        
        return feedback

    def _build_join_error_feedback(self, error: str, sql_query: str) -> str:
        """Build detailed feedback for JOIN errors"""
        feedback = f"""## JOIN Error

**Error:** {error}

**Your Query:**
```sql
{sql_query}
```

**Fix:**
- Each JOIN must have a corresponding ON clause
- Use format: JOIN table_name ON table1.column = table2.column
- Verify the JOIN columns exist in both tables
- Check foreign key relationships in the schema
"""
        return feedback

    def _build_execution_error_feedback(self, error: str, sql_query: str) -> str:
        """Build detailed feedback for execution errors"""
        feedback = f"""## Execution Error

**Database Error:** {error}

**Your Query:**
```sql
{sql_query}
```

**Common Causes:**
- Column name doesn't exist in the table
- Ambiguous column reference (column exists in multiple tables without alias)
- Invalid aggregate function usage
- GROUP BY missing required columns
- Invalid data type comparison
- Syntax error not caught by validator

**Fix:**
- Check the error message carefully
- Verify all column names are correct
- Use table aliases to avoid ambiguity
- Ensure GROUP BY includes all non-aggregated columns
"""
        return feedback

    def _extract_table_from_error(self, error_detail: str) -> Optional[str]:
        """Extract table name from error detail"""
        # Try to extract table name from error message
        match = re.search(r'table[:\s]+(\w+)', error_detail, re.IGNORECASE)
        if match:
            return match.group(1)
        return None
