"""
Schema Validator Module  
Validates SQL queries against database schema (tables, columns, values)
"""

import logging
import re
from typing import List, Dict, Any, Tuple
from difflib import get_close_matches

logger = logging.getLogger(__name__)


class SchemaValidator:
    """
    Validates SQL queries against schema
    Checks tables, columns, and values exist in database
    """
    
    def __init__(self, schema_parser, query_executor=None):
        """
        Initialize validator
        
        Args:
            schema_parser: SchemaParser instance
            query_executor: QueryExecutor instance (optional, for value validation)
        """
        self.schema_parser = schema_parser
        self.query_executor = query_executor
        logger.info("✅ SchemaValidator initialized")
    
    def extract_tables_from_sql(self, sql_query: str) -> List[str]:
        """Extract table names from SQL query"""
        # Match FROM and JOIN clauses
        patterns = [
            r'FROM\s+([`\"]?(\w+)[`\"]?)',
            r'JOIN\s+([`\"]?(\w+)[`\"]?)',
            r'INTO\s+([`\"]?(\w+)[`\"]?)'
        ]
        
        tables = []
        for pattern in patterns:
            matches = re.findall(pattern, sql_query, re.IGNORECASE)
            for match in matches:
                # match is a tuple, get the table name (second group)
                table = match[1] if len(match) > 1 else match[0]
                tables.append(table)
        
        return list(set(tables))
    
    def extract_columns_from_sql(self, sql_query: str) -> Dict[str, List[str]]:
        """Extract columns referenced in SQL query grouped by table"""
        column_refs = {}
        
        # Extract table aliases first
        alias_pattern = r'FROM\s+(\w+)\s+(?:AS\s+)?(\w+)|JOIN\s+(\w+)\s+(?:AS\s+)?(\w+)'
        aliases = {}  # alias -> table_name
        for match in re.finditer(alias_pattern, sql_query, re.IGNORECASE):
            if match.group(1):  # FROM clause
                table = match.group(1)
                alias = match.group(2) if match.group(2) else table
                aliases[alias] = table
            elif match.group(3):  # JOIN clause
                table = match.group(3)
                alias = match.group(4) if match.group(4) else table
                aliases[alias] = table
        
        # Extract column references (table.column or alias.column)
        column_pattern = r'(\w+)\.(\w+)'
        for match in re.finditer(column_pattern, sql_query):
            table_or_alias = match.group(1)
            column = match.group(2)
            
            # Resolve alias to actual table name
            table_name = aliases.get(table_or_alias, table_or_alias)
            
            if table_name not in column_refs:
                column_refs[table_name] = []
            if column not in column_refs[table_name]:
                column_refs[table_name].append(column)
        
        return column_refs
    
    def extract_where_conditions(self, sql_query: str) -> List[tuple]:
        """Extract column=value conditions from WHERE clause"""
        try:
            # Find WHERE clause
            where_match = re.search(r'WHERE\s+(.+?)(?:GROUP BY|ORDER BY|LIMIT|HAVING|;|$)', 
                                   sql_query, re.IGNORECASE | re.DOTALL)
            if not where_match:
                return []
            
            where_clause = where_match.group(1)
            
            # Extract simple equality conditions: column = 'value' or column = "value"
            # Pattern: column_name = 'value' or table.column = 'value'
            pattern = r"([\w.]+)\s*=\s*['\"]([ ^'\"]+)['\"]"
            matches = re.findall(pattern, where_clause, re.IGNORECASE)
            
            conditions = []
            for col_ref, value in matches:
                # Remove table alias if present (e.g., bm.status -> status)
                if '.' in col_ref:
                    col_name = col_ref.split('.')[-1]
                else:
                    col_name = col_ref
                
                conditions.append((col_name.upper(), value))
            
            return conditions
            
        except Exception as e:
            logger.error(f"Error extracting WHERE conditions: {e}")
            return []
    
    def validate_sql_tables(self, sql_query: str) -> Tuple[bool, List[str]]:
        """
        Validate that all tables in SQL query actually exist
        
        Returns:
            Tuple of (all_valid, invalid_tables)
        """
        tables_in_query = self.extract_tables_from_sql(sql_query)
        invalid_tables = [t for t in tables_in_query 
                         if not self.schema_parser.validate_table_exists(t)]
        
        if invalid_tables:
            logger.warning(f"⚠️ SQL uses non-existent tables: {invalid_tables}")
            return False, invalid_tables
        
        return True, []
    
    def validate_sql_columns(self, sql_query: str) -> Tuple[bool, List[str]]:
        """Validate that all columns in SQL query exist in their respective tables"""
        column_refs = self.extract_columns_from_sql(sql_query)
        invalid_columns = []
        
        for table_name, columns in column_refs.items():
            if not self.schema_parser.validate_table_exists(table_name):
                continue  # Table validation will catch this
            
            for column in columns:
                if not self.schema_parser.validate_column_exists(table_name, column):
                    invalid_columns.append(f"{table_name}.{column}")
        
        if invalid_columns:
            logger.warning(f"⚠️ SQL uses non-existent columns: {invalid_columns}")
            return False, invalid_columns
        
        return True, []
    
    def validate_query_values(self, sql_query: str) -> Tuple[bool, List[dict]]:
        """
        Validate that values in WHERE clause actually exist in the database
        Requires query_executor to be available
        """
        if not self.query_executor:
            logger.debug("Query executor not available, skipping value validation")
            return True, []
        
        try:
            # Extract table names to know which tables are being queried
            tables = self.extract_tables_from_sql(sql_query)
            if not tables:
                return True, []  # No tables, can't validate
            
            # Extract WHERE conditions
            conditions = self.extract_where_conditions(sql_query)
            if not conditions:
                return True, []  # No WHERE conditions, nothing to validate
            
            invalid_values = []
            
            # For each condition, check if the value exists in the column
            for column_name, filter_value in conditions:
                # Try to find which table this column belongs to
                table_found = None
                for table in tables:
                    if self.schema_parser.validate_column_exists(table, column_name):
                        table_found = table
                        break
                
                if not table_found:
                    continue  # Column validation will catch this
                
                # Get actual distinct values from the database
                actual_values = self.query_executor.get_distinct_column_values(
                    table_found, column_name)
                
                if actual_values:
                    # Check if filter value exists in actual values (case-insensitive)
                    actual_values_upper = [v.upper() for v in actual_values]
                    if filter_value.upper() not in actual_values_upper:
                        invalid_values.append({
                            'table': table_found,
                            'column': column_name,
                            'filter_value': filter_value,
                            'actual_values': actual_values[:20]  # Limit to 20 for display
                        })
            
            if invalid_values:
                logger.warning(f"⚠️ Query uses filter values that don't exist: {len(invalid_values)}")
                for issue in invalid_values:
                    logger.warning(f"  ❌ {issue['table']}.{issue['column']} = '{issue['filter_value']}' (not found)")
                    logger.warning(f"     ✓ Actual values: {issue['actual_values']}")
                return False, invalid_values
            
            return True, []
            
        except Exception as e:
            logger.error(f"Error validating query values: {e}")
            return True, []  # Don't block on validation errors
    
    def find_similar_valid_tables(self, invalid_table: str, limit: int = 3) -> List[str]:
        """Find similar table names using fuzzy matching"""
        available_tables = list(self.schema_parser.get_available_tables())
        similar = get_close_matches(invalid_table, available_tables, n=limit, cutoff=0.6)
        return similar
    
    def extract_and_correct_column_names(self, question: str) -> Tuple[str, List[Dict[str, str]]]:
        """
        Extract potential column names from question and suggest corrections
        
        Returns:
            (corrected_question, corrections_list)
        """
        try:
            corrected_question = question
            corrections = []
            
            # Common column name patterns to look for
            column_keywords = ['column', 'field', 'attribute']
            
            # Extract quoted strings that might be column names
            quoted_pattern = r'["\']([^"\']+)["\']'
            for match in re.finditer(quoted_pattern, question):
                potential_column = match.group(1)
                
                # Try to find this column in any table
                for table_name in self.schema_parser.get_available_tables():
                    closest = self.schema_parser.find_closest_column_name(
                        potential_column, table_name)
                    
                    if closest and closest.lower() != potential_column.lower():
                        corrections.append({
                            'original': potential_column,
                            'corrected': closest,
                            'table': table_name
                        })
                        # Replace in question
                        corrected_question = corrected_question.replace(
                            f'"{potential_column}"', f'"{closest}"')
                        corrected_question = corrected_question.replace(
                            f"'{potential_column}'", f"'{closest}'")
                        break
            
            return corrected_question, corrections
            
        except Exception as e:
            logger.error(f"Error extracting/correcting column names: {e}")
            return question, []
