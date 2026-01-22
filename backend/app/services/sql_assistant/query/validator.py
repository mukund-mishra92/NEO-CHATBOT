"""
Query Validator Module
Validates query results and calculates confidence scores
"""

import logging
from typing import List, Dict, Any, Tuple

logger = logging.getLogger(__name__)


class QueryValidator:
    """
    Validates SQL query results and calculates confidence scores
    """
    
    def __init__(self):
        """Initialize query validator"""
        logger.info("✅ QueryValidator initialized")
    
    def validate_results(self, results: List[Dict[str, Any]], question: str, 
                        sql_query: str) -> Tuple[float, str]:
        """
        Validate query results and calculate confidence score
        
        Args:
            results: Query results
            question: Original question
            sql_query: Generated SQL query
            
        Returns:
            Tuple of (confidence_score, validation_message)
        """
        confidence = 0.5  # Base confidence
        messages = []
        
        # Check 1: Results exist
        if not results:
            return 0.3, "No results returned - query might be too restrictive or data doesn't exist"
        
        confidence += 0.1
        messages.append(f"✅ {len(results)} results found")
        
        # Check 2: Reasonable result count
        if 1 <= len(results) <= 1000:
            confidence += 0.15
            messages.append("✅ Result count looks reasonable")
        elif len(results) > 10000:
            confidence -= 0.1
            messages.append("⚠️ Very large result set - might need filtering")
        
        # Check 3: Results have data (not all nulls)
        if results:
            first_row = results[0]
            non_null_values = sum(1 for v in first_row.values() if v is not None)
            
            if non_null_values >= len(first_row) * 0.7:  # 70% non-null
                confidence += 0.15
                messages.append("✅ Results contain meaningful data")
            else:
                confidence -= 0.05
                messages.append("⚠️ Many null values in results")
        
        # Check 4: Column names make sense
        if results:
            columns = list(results[0].keys())
            relevant_keywords = question.lower().split()
            
            column_relevance = sum(
                1 for col in columns 
                for keyword in relevant_keywords 
                if keyword in col.lower()
            )
            
            if column_relevance > 0:
                confidence += 0.10
                messages.append("✅ Column names match question context")
        
        # Cap confidence at 0.95 (never 100% sure)
        confidence = min(confidence, 0.95)
        
        validation_msg = " | ".join(messages)
        logger.info(f"📊 Validation confidence: {confidence:.2f}")
        
        return confidence, validation_msg
    
    def format_results_with_confidence(self, results: List[Dict[str, Any]], 
                                      sql_query: str, question: str,
                                      confidence: float, validation_msg: str) -> str:
        """
        Format results with confidence indicators
        
        Args:
            results: Query results
            sql_query: SQL query used
            question: Original question
            confidence: Confidence score
            validation_msg: Validation message
            
        Returns:
            Formatted results string
        """
        try:
            output_lines = []
            
            # Add confidence indicator
            if confidence >= 0.8:
                output_lines.append(f"✅ HIGH CONFIDENCE ({confidence:.0%}) - Results are reliable")
            elif confidence >= 0.6:
                output_lines.append(f"⚠️ MEDIUM CONFIDENCE ({confidence:.0%}) - Results may need verification")
            else:
                output_lines.append(f"❌ LOW CONFIDENCE ({confidence:.0%}) - Results should be verified")
            
            output_lines.append(f"\n📋 Validation: {validation_msg}")
            output_lines.append(f"\n🔍 SQL Query:\n{sql_query}")
            output_lines.append(f"\n📊 Results ({len(results)} rows):")
            
            # Format first few results
            for i, row in enumerate(results[:10], 1):
                output_lines.append(f"\nRow {i}:")
                for key, value in row.items():
                    output_lines.append(f"  {key}: {value}")
            
            if len(results) > 10:
                output_lines.append(f"\n... and {len(results) - 10} more rows")
            
            return "\n".join(output_lines)
            
        except Exception as e:
            logger.error(f"Error formatting results: {e}")
            return f"Results: {len(results)} rows\nSQL: {sql_query}"
