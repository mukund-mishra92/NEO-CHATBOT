"""
Database Schema Parser
Parses schema.json file (SQL dump) to extract table and column information.
"""

from typing import Dict, List, Tuple
from pathlib import Path
import re
import json


class SchemaParser:
    """Parser for JSON/SQL database schema files."""
    
    def __init__(self, schema_file_path: str):
        """
        Initialize the schema parser.
        
        Args:
            schema_file_path: Path to the JSON schema file (SQL dump)
        """
        self.schema_file_path = Path(schema_file_path)
        self.tables: Dict[str, List[Dict[str, str]]] = {}
        
    def parse(self) -> Dict[str, List[Dict[str, str]]]:
        """
        Parse the JSON/SQL schema file and extract table structures.
        
        Returns:
            Dictionary mapping table names to list of column dictionaries
        """
        if not self.schema_file_path.exists():
            raise FileNotFoundError(f"Schema file not found: {self.schema_file_path}")
        
        with open(self.schema_file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Extract CREATE TABLE statements using regex
        table_pattern = r'CREATE TABLE `(\w+)` \((.*?)\) ENGINE='
        matches = re.finditer(table_pattern, content, re.DOTALL | re.IGNORECASE)
        
        for match in matches:
            table_name = match.group(1)
            columns_sql = match.group(2)
            
            # Parse column definitions
            columns = self._parse_columns_from_sql(columns_sql)
            if columns:
                self.tables[table_name] = columns
        
        return self.tables
    
    def _parse_columns_from_sql(self, columns_sql: str) -> List[Dict[str, str]]:
        """
        Parse column information from CREATE TABLE SQL definition.
        
        Args:
            columns_sql: SQL column definitions string
            
        Returns:
            List of column dictionaries with field details
        """
        columns = []
        
        # Split by lines, filter out PRIMARY KEY, KEY, CONSTRAINT lines
        lines = [line.strip() for line in columns_sql.split('\n') 
                if line.strip() and not line.strip().startswith(('PRIMARY KEY', 'KEY', 'UNIQUE KEY', 'CONSTRAINT'))]
        
        for line in lines:
            if not line or line.startswith('--'):
                continue
                
            # Extract column name (between backticks)
            col_match = re.match(r'`(\w+)`\s+(.+)', line)
            if col_match:
                col_name = col_match.group(1)
                col_definition = col_match.group(2).rstrip(',')
                
                # Parse data type
                type_match = re.match(r'(\w+(?:\([^)]+\))?)', col_definition)
                data_type = type_match.group(1) if type_match else 'UNKNOWN'
                
                # Check constraints
                is_nullable = 'NOT NULL' not in col_definition.upper()
                is_auto_increment = 'AUTO_INCREMENT' in col_definition.upper()
                is_primary_key = 'PRIMARY KEY' in col_definition.upper()
                
                # Extract comment
                comment_match = re.search(r"COMMENT '([^']*)'", col_definition)
                comment = comment_match.group(1) if comment_match else ''
                
                # Extract default value
                default_match = re.search(r"DEFAULT\s+([^\s,]+)", col_definition, re.IGNORECASE)
                default_value = default_match.group(1) if default_match else ''
                
                columns.append({
                    'field': col_name,
                    'type': data_type,
                    'null': 'YES' if is_nullable else 'NO',
                    'key': 'PRI' if is_primary_key else '',
                    'default': default_value,
                    'extra': 'auto_increment' if is_auto_increment else '',
                    'comment': comment
                })
        
        return columns
    
    def _clean_text(self, text: str) -> str:
        """Clean extracted text."""
        return text.strip().replace('\xa0', '').replace('(NULL)', '')
    
    def get_table_schema(self, table_name: str) -> str:
        """
        Get formatted schema for a specific table.
        
        Args:
            table_name: Name of the table
            
        Returns:
            Formatted schema string
        """
        if table_name not in self.tables:
            return ""
        
        columns = self.tables[table_name]
        schema_lines = [f"Table: {table_name}"]
        schema_lines.append("Columns:")
        
        for col in columns:
            key_info = f" [{col['key']}]" if col['key'] else ""
            null_info = " NULL" if col['null'] == 'YES' else " NOT NULL"
            extra_info = f" {col['extra']}" if col['extra'] else ""
            
            schema_lines.append(
                f"  - {col['field']}: {col['type']}{key_info}{null_info}{extra_info}"
            )
        
        return "\n".join(schema_lines)
    
    def get_all_schemas(self) -> str:
        """
        Get formatted schema for all tables.
        
        Returns:
            Formatted schema string for all tables
        """
        all_schemas = []
        for table_name in sorted(self.tables.keys()):
            all_schemas.append(self.get_table_schema(table_name))
        
        return "\n\n".join(all_schemas)
    
    def get_compact_schema(self) -> str:
        """
        Get compact schema suitable for LLM system prompts.
        Only includes essential information.
        
        Returns:
            Compact schema string
        """
        compact_lines = ["Database Schema:"]
        
        for table_name in sorted(self.tables.keys()):
            columns = self.tables[table_name]
            
            # Get primary key and important columns
            pk_cols = [c['field'] for c in columns if c['key'] == 'PRI']
            col_list = [f"{c['field']} ({c['type']})" for c in columns]
            
            pk_info = f" [PK: {', '.join(pk_cols)}]" if pk_cols else ""
            compact_lines.append(f"\n{table_name}{pk_info}:")
            compact_lines.append(f"  {', '.join(col_list)}")
        
        return "\n".join(compact_lines)
    
    def get_table_names(self) -> List[str]:
        """Get list of all table names."""
        return sorted(self.tables.keys())
    
    def search_tables(self, keyword: str) -> List[str]:
        """
        Search for tables containing a keyword in their name.
        
        Args:
            keyword: Search keyword
            
        Returns:
            List of matching table names
        """
        keyword_lower = keyword.lower()
        return [
            table for table in self.tables.keys()
            if keyword_lower in table.lower()
        ]


def get_schema_parser() -> SchemaParser:
    """
    Get initialized schema parser with default schema file.
    
    Returns:
        SchemaParser instance
    """
    # Go up to project root: backend/app -> backend -> root
    schema_file = Path(__file__).parent.parent.parent.parent / "data" / "database" / "schema.json"
    parser = SchemaParser(str(schema_file))
    parser.parse()
    return parser
