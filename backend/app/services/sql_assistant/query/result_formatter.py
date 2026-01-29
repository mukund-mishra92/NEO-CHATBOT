"""
Result Formatter - Layer 4
Formats SQL query results into well-structured tables with confidence scoring
"""

import logging
from typing import List, Dict, Any, Optional
from datetime import datetime, date
import json

logger = logging.getLogger(__name__)


class ResultFormatter:
    """
    Layer 4: Format SQL results into structured, readable tables
    - Creates markdown tables for display
    - Adds confidence scoring
    - Handles various data types
    - Provides clear explanations
    """

    def __init__(self):
        self.max_display_rows = 100
        self.max_column_width = 50

    def format_results(
        self,
        results: List[Dict[str, Any]],
        sql_query: str,
        question: str,
        validation_details: Dict[str, Any],
        generation_metadata: Dict[str, Any]
    ) -> str:
        """
        Format query results into a structured response
        
        Args:
            results: Query results from database
            sql_query: The SQL query that was executed
            question: Original user question
            validation_details: Validation metrics
            generation_metadata: Query generation metadata
            
        Returns:
            Formatted response string with table and metadata
        """
        if not results:
            return self._format_empty_results(sql_query, question)
        
        # Calculate confidence
        confidence = self._calculate_confidence(
            results,
            validation_details,
            generation_metadata
        )
        
        # Build formatted response
        response_parts = []
        
        # Header with confidence
        response_parts.append(self._build_header(question, confidence, len(results)))
        
        # Results table
        response_parts.append(self._build_results_table(results))
        
        # Summary statistics
        if len(results) > 1:
            response_parts.append(self._build_summary_stats(results))
        
        # Query information (collapsed by default in UI)
        response_parts.append(self._build_query_info(
            sql_query,
            generation_metadata,
            confidence
        ))
        
        return "\n\n".join(response_parts)

    def _calculate_confidence(
        self,
        results: List[Dict[str, Any]],
        validation_details: Dict[str, Any],
        generation_metadata: Dict[str, Any]
    ) -> float:
        """Calculate confidence score for results"""
        confidence = 1.0
        
        # Reduce confidence for retries
        if generation_metadata.get("attempt", 1) > 1:
            confidence -= 0.15 * (generation_metadata["attempt"] - 1)
        
        # Reduce confidence for empty results
        if not results:
            confidence -= 0.3
        
        # Reduce confidence if validation had issues
        if not validation_details.get("joins_valid", True):
            confidence -= 0.1
        
        # Boost confidence for successful execution
        if validation_details.get("executed", False):
            confidence += 0.1
        
        # Boost confidence if using advanced model (o1)
        if generation_metadata.get("model") == "o1":
            confidence += 0.05
        
        # Cap confidence between 0 and 1
        confidence = max(0.0, min(1.0, confidence))
        
        return round(confidence, 2)

    def _build_header(self, question: str, confidence: float, row_count: int) -> str:
        """Build response header with confidence indicator"""
        confidence_emoji = "🟢" if confidence >= 0.8 else "🟡" if confidence >= 0.6 else "🔴"
        
        header = f"""## 📊 Query Results

**Question:** {question}

**Status:** {confidence_emoji} Confidence: {confidence:.0%} | **Results:** {row_count} row(s) found"""
        
        return header

    def _build_results_table(self, results: List[Dict[str, Any]]) -> str:
        """Build markdown table from results"""
        if not results:
            return "*No results found*"
        
        # Limit display rows
        display_results = results[:self.max_display_rows]
        has_more = len(results) > self.max_display_rows
        
        # Get column names from first row
        columns = list(display_results[0].keys())
        
        # Build table header
        table_lines = []
        
        # Column headers
        header_row = "| " + " | ".join(self._format_header(col) for col in columns) + " |"
        table_lines.append(header_row)
        
        # Separator
        separator = "| " + " | ".join("---" for _ in columns) + " |"
        table_lines.append(separator)
        
        # Data rows
        for row in display_results:
            row_data = []
            for col in columns:
                value = row.get(col)
                row_data.append(self._format_cell_value(value))
            
            row_line = "| " + " | ".join(row_data) + " |"
            table_lines.append(row_line)
        
        table = "\n".join(table_lines)
        
        # Add truncation notice
        if has_more:
            table += f"\n\n*Showing {self.max_display_rows} of {len(results)} total rows*"
        
        return table

    def _build_summary_stats(self, results: List[Dict[str, Any]]) -> str:
        """Build summary statistics"""
        stats = []
        
        # Count total rows
        stats.append(f"**Total Rows:** {len(results)}")
        
        # Find numeric columns and calculate stats
        columns = list(results[0].keys())
        
        for col in columns:
            # Check if column has numeric values
            values = [row[col] for row in results if row[col] is not None]
            
            if not values:
                continue
            
            # Try to convert to numbers
            try:
                numeric_values = [float(v) for v in values if self._is_numeric(v)]
                
                if numeric_values and len(numeric_values) > 1:
                    avg = sum(numeric_values) / len(numeric_values)
                    total = sum(numeric_values)
                    
                    stats.append(
                        f"**{col}:** Total = {self._format_number(total)}, "
                        f"Average = {self._format_number(avg)}"
                    )
            except (ValueError, TypeError):
                continue
        
        if len(stats) > 1:
            return "### 📈 Summary Statistics\n\n" + "\n".join(stats)
        
        return ""

    def _build_query_info(
        self,
        sql_query: str,
        metadata: Dict[str, Any],
        confidence: float
    ) -> str:
        """Build query information section"""
        info_parts = []
        
        info_parts.append("### 🔍 Query Details")
        info_parts.append("")
        
        # Query metadata
        info_parts.append("**Generation Info:**")
        info_parts.append(f"- Model: {metadata.get('model', 'unknown')}")
        info_parts.append(f"- Attempt: {metadata.get('attempt', 1)}")
        info_parts.append(f"- Generation Time: {metadata.get('generation_time', 0):.2f}s")
        info_parts.append(f"- Confidence: {confidence:.0%}")
        info_parts.append("")
        
        # SQL query
        info_parts.append("**Executed SQL:**")
        info_parts.append("```sql")
        info_parts.append(self._format_sql(sql_query))
        info_parts.append("```")
        
        return "\n".join(info_parts)

    def _format_empty_results(self, sql_query: str, question: str) -> str:
        """Format response for empty results"""
        response = f"""## 📊 Query Results

**Question:** {question}

**Status:** 🟡 No results found

The query executed successfully but returned no matching records. This could mean:
- The filter conditions are too restrictive
- The data you're looking for doesn't exist in the database
- There might be a mismatch in the query logic

**Executed SQL:**
```sql
{self._format_sql(sql_query)}
```

**Suggestions:**
- Try broadening your search criteria
- Check if the data exists with a simpler query
- Verify the filter conditions are correct
"""
        return response

    def _format_header(self, column_name: str) -> str:
        """Format column header"""
        # Convert snake_case to Title Case
        words = column_name.replace('_', ' ').split()
        return ' '.join(word.capitalize() for word in words)

    def _format_cell_value(self, value: Any) -> str:
        """Format a single cell value"""
        if value is None:
            return "*NULL*"
        
        # Handle different data types
        if isinstance(value, (datetime, date)):
            return value.strftime("%Y-%m-%d %H:%M:%S") if isinstance(value, datetime) else value.strftime("%Y-%m-%d")
        
        if isinstance(value, bool):
            return "✓" if value else "✗"
        
        if isinstance(value, (int, float)):
            return self._format_number(value)
        
        # String value - truncate if too long
        str_value = str(value)
        if len(str_value) > self.max_column_width:
            return str_value[:self.max_column_width-3] + "..."
        
        return str_value

    def _format_number(self, value: float) -> str:
        """Format numeric value"""
        if isinstance(value, int) or value == int(value):
            return f"{int(value):,}"
        return f"{value:,.2f}"

    def _format_sql(self, sql_query: str) -> str:
        """Format SQL query for display"""
        # Basic SQL formatting (indentation)
        keywords = ['SELECT', 'FROM', 'WHERE', 'JOIN', 'LEFT JOIN', 'RIGHT JOIN', 
                   'INNER JOIN', 'GROUP BY', 'ORDER BY', 'HAVING', 'LIMIT']
        
        formatted = sql_query
        for keyword in keywords:
            # Add newline before keywords (except SELECT at start)
            if keyword != 'SELECT':
                formatted = formatted.replace(f' {keyword} ', f'\n{keyword} ')
                formatted = formatted.replace(f' {keyword.lower()} ', f'\n{keyword} ')
        
        return formatted

    def _is_numeric(self, value: Any) -> bool:
        """Check if value is numeric"""
        try:
            float(value)
            return True
        except (ValueError, TypeError):
            return False
