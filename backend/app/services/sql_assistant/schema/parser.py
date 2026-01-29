"""
Schema Parser Module
Handles schema loading, table/column discovery, and schema querying
"""

import logging
from typing import List, Dict, Any, Set, Optional

logger = logging.getLogger(__name__)


class SchemaParser:
    """
    Schema parser for database introspection and validation
    """
    
    def __init__(self):
        """Initialize schema parser"""
        self.schema_parser = self._load_schema_parser()
        self.available_tables = self._load_available_tables()
        logger.info(f"✅ SchemaParser initialized with {len(self.available_tables)} tables")
    
    def _load_schema_parser(self):
        """Load schema parser from utils"""
        try:
            from ....utils.schema_parser import get_schema_parser
            parser = get_schema_parser()
            table_count = len(parser.get_table_names()) if parser else 0
            logger.info(f"✅ Loaded schema parser with {table_count} tables")
            return parser
        except Exception as e:
            logger.error(f"❌ Error loading schema parser: {e}")
            return None
    
    def _load_available_tables(self) -> Set[str]:
        """Get set of all available tables from schema for fast validation"""
        try:
            if self.schema_parser:
                return set(self.schema_parser.get_table_names())
            return set()
        except Exception as e:
            logger.error(f"❌ Error getting available tables: {e}")
            return set()
    
    def get_available_tables(self) -> Set[str]:
        """Get all available table names"""
        return self.available_tables
    
    def get_table_columns(self, table_name: str) -> List[str]:
        """Get list of column names for a specific table"""
        try:
            if self.schema_parser and table_name in self.schema_parser.tables:
                columns = self.schema_parser.tables[table_name]
                return [col['field'] for col in columns]
            return []
        except Exception as e:
            logger.error(f"❌ Error getting columns for {table_name}: {e}")
            return []
    
    def get_full_table_schema(self, table_name: str) -> str:
        """Get full schema with columns for a table"""
        try:
            if self.schema_parser:
                return self.schema_parser.get_table_schema(table_name)
            return ""
        except Exception as e:
            logger.error(f"❌ Error getting schema for {table_name}: {e}")
            return ""
    
    def validate_table_exists(self, table_name: str) -> bool:
        """Check if a table actually exists in the database schema"""
        return table_name in self.available_tables
    
    def validate_column_exists(self, table_name: str, column_name: str) -> bool:
        """Check if a column exists in a specific table"""
        columns = self.get_table_columns(table_name)
        return column_name in columns
    
    def extract_table_names(self) -> List[str]:
        """Extract list of all table names from schema"""
        try:
            if self.schema_parser:
                return list(self.schema_parser.tables.keys())
            return []
        except Exception as e:
            logger.error(f"❌ Error extracting table names: {e}")
            return []
    
    def find_closest_column_name(self, user_column: str, table_name: str) -> Optional[str]:
        """
        Find the closest matching column name in a table using fuzzy matching
        
        Args:
            user_column: Column name from user query
            table_name: Table to search in
            
        Returns:
            Best matching column name or None
        """
        try:
            from difflib import get_close_matches
            
            # Get available columns for this table
            available_columns = self.get_table_columns(table_name)
            if not available_columns:
                return None
            
            # Try exact match first (case-insensitive)
            user_lower = user_column.lower()
            for col in available_columns:
                if col.lower() == user_lower:
                    return col
            
            # Try fuzzy matching
            matches = get_close_matches(user_column, available_columns, n=1, cutoff=0.6)
            if matches:
                logger.info(f"🔍 Fuzzy match: '{user_column}' -> '{matches[0]}' in {table_name}")
                return matches[0]
            
            return None
            
        except Exception as e:
            logger.error(f"❌ Error finding closest column for '{user_column}' in {table_name}: {e}")
            return None
    
    def add_column_semantics(self, table: str, columns: List[Dict]) -> str:
        """
        Add semantic information about columns to help with query generation
        
        Args:
            table: Table name
            columns: List of column dictionaries with 'field', 'type', etc.
            
        Returns:
            Formatted schema with semantic hints
        """
        try:
            schema_lines = [f"Table: {table}"]
            
            for col in columns:
                col_name = col.get('field', '')
                col_type = col.get('type', 'UNKNOWN')
                
                # Add semantic hints based on column name patterns
                semantic_hints = []
                col_lower = col_name.lower()
                
                if any(x in col_lower for x in ['id', 'code', 'key']):
                    semantic_hints.append("(identifier)")
                if any(x in col_lower for x in ['date', 'time', 'timestamp']):
                    semantic_hints.append("(temporal)")
                if any(x in col_lower for x in ['count', 'qty', 'quantity', 'amount']):
                    semantic_hints.append("(numeric aggregatable)")
                if any(x in col_lower for x in ['status', 'state', 'type']):
                    semantic_hints.append("(categorical)")
                if any(x in col_lower for x in ['name', 'description', 'title']):
                    semantic_hints.append("(descriptive text)")
                
                hint_str = " ".join(semantic_hints) if semantic_hints else ""
                schema_lines.append(f"  - {col_name}: {col_type} {hint_str}")
            
            return "\n".join(schema_lines)
            
        except Exception as e:
            logger.error(f"❌ Error adding column semantics for {table}: {e}")
            return f"Table: {table} (schema unavailable)"
    
    def get_schema_summary(self) -> str:
        """
        Get a text summary of the database schema for LLM prompts
        
        Returns:
            Formatted string with tables and their columns
        """
        try:
            table_names = self.extract_table_names()
            summary_parts = ["Database Schema:\n"]
            
            # Limit to reasonable number of tables to avoid token overflow
            for table in table_names[:30]:
                columns = self.get_table_columns(table)
                if columns:
                    column_list = ", ".join(columns[:15])  # Limit columns too
                    if len(columns) > 15:
                        column_list += f", ... ({len(columns)} total)"
                    summary_parts.append(f"- {table}: {column_list}")
            
            if len(table_names) > 30:
                summary_parts.append(f"\n... and {len(table_names) - 30} more tables")
            
            return "\n".join(summary_parts)
        except Exception as e:
            logger.error(f"❌ Error generating schema summary: {e}")
            return "Database schema unavailable"
    
    def get_schema_info(self) -> Dict[str, Any]:
        """
        Get comprehensive schema information
        
        Returns:
            Dictionary with schema details: tables, table_count, sample_tables
        """
        try:
            table_names = self.extract_table_names()
            
            return {
                'available': True,
                'table_count': len(table_names),
                'tables': table_names[:50],  # Limit to first 50
                'sample_tables': table_names[:10]
            }
        except Exception as e:
            logger.error(f"❌ Error getting schema info: {e}")
            return {
                'available': False,
                'table_count': 0,
                'tables': [],
                'sample_tables': []
            }
