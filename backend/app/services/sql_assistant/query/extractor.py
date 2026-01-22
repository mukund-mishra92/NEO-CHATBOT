"""
Query Extractor Module
Extracts SQL queries from LLM responses
"""

import logging
import re
from typing import Optional

logger = logging.getLogger(__name__)


class QueryExtractor:
    """
    Extracts SQL queries from various text formats
    """
    
    def __init__(self):
        """Initialize query extractor"""
        self.sql_keywords = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'WITH']
        logger.info("✅ QueryExtractor initialized")
    
    def extract_sql_query(self, response: str) -> Optional[str]:
        """
        Extract SQL query from LLM response
        Handles markdown code blocks and plain SQL
        
        Args:
            response: LLM response text
            
        Returns:
            Extracted SQL query or None
        """
        try:
            # Strategy 1: Look for SQL code blocks (```sql)
            sql_from_block = self._extract_from_code_block(response)
            if sql_from_block:
                return sql_from_block
            
            # Strategy 2: Look for SQL keywords
            sql_from_keywords = self._extract_from_keywords(response)
            if sql_from_keywords:
                return sql_from_keywords
            
            return None
            
        except Exception as e:
            logger.error(f"❌ Error extracting SQL query: {e}")
            return None
    
    def _extract_from_code_block(self, response: str) -> Optional[str]:
        """Extract SQL from markdown code blocks"""
        try:
            if "```sql" in response.lower():
                start = response.lower().find("```sql") + 6
                end = response.find("```", start)
                if end > start:
                    sql = response[start:end].strip()
                    logger.debug(f"Extracted SQL from code block: {sql[:50]}...")
                    return sql
            return None
        except Exception as e:
            logger.error(f"Error extracting from code block: {e}")
            return None
    
    def _extract_from_keywords(self, response: str) -> Optional[str]:
        """Extract SQL by finding SQL keywords"""
        try:
            lines = response.split('\n')
            sql_lines = []
            in_query = False
            
            for line in lines:
                upper_line = line.strip().upper()
                
                # Start collecting when we see SQL keyword
                if any(upper_line.startswith(kw) for kw in self.sql_keywords):
                    in_query = True
                
                if in_query:
                    sql_lines.append(line)
                    # Stop at semicolon
                    if line.strip().endswith(';'):
                        break
            
            if sql_lines:
                sql = '\n'.join(sql_lines).strip()
                logger.debug(f"Extracted SQL from keywords: {sql[:50]}...")
                return sql
            
            return None
            
        except Exception as e:
            logger.error(f"Error extracting from keywords: {e}")
            return None
    
    def clean_sql_query(self, sql_query: str) -> str:
        """
        Clean and normalize SQL query
        Remove comments, extra whitespace, etc.
        
        Args:
            sql_query: Raw SQL query
            
        Returns:
            Cleaned SQL query
        """
        try:
            # Remove single-line comments
            sql_query = re.sub(r'--.*$', '', sql_query, flags=re.MULTILINE)
            
            # Remove multi-line comments
            sql_query = re.sub(r'/\*.*?\*/', '', sql_query, flags=re.DOTALL)
            
            # Normalize whitespace
            sql_query = ' '.join(sql_query.split())
            
            # Remove trailing semicolon if present (we'll add it back later if needed)
            sql_query = sql_query.rstrip(';').strip()
            
            return sql_query
            
        except Exception as e:
            logger.error(f"Error cleaning SQL query: {e}")
            return sql_query
