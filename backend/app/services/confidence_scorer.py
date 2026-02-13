"""
Confidence Scorer - Determine if results are trustworthy
"""
from typing import List, Dict, Tuple
from dataclasses import dataclass
import re

@dataclass
class ConfidenceScore:
    """Confidence scoring breakdown"""
    overall: float  # 0.0 to 1.0
    query_structure: float  # Is SQL well-formed?
    table_relevance: float  # Are tables relevant to question?
    result_plausibility: float  # Do results make sense?
    data_availability: float  # Is lack of data expected?
    
    is_no_data_expected: bool  # True if empty result is legitimate
    explanation: str  # Human-readable explanation

class ConfidenceScorer:
    """
    Score confidence in query results with detailed breakdown
    """
    
    def __init__(self, schema_registry):
        self.schema_registry = schema_registry
    
    def score(
        self,
        question: str,
        sql: str,
        results: List[Dict],
        generation_confidence: float,
        validation_result
    ) -> ConfidenceScore:
        """
        Comprehensive confidence scoring
        
        Returns:
            ConfidenceScore with breakdown and explanation
        """
        # 1. Query Structure Score (from validation)
        query_structure = validation_result.confidence
        
        # 2. Table Relevance Score
        tables_used = self._extract_tables(sql)
        table_relevance = self._score_table_relevance(question, tables_used)
        
        # 3. Result Plausibility Score
        result_plausibility = self._score_result_plausibility(
            question, sql, results
        )
        
        # 4. Data Availability Score (Is empty result expected?)
        data_availability, is_no_data_expected = self._score_data_availability(
            question, sql, results, tables_used
        )
        
        # Weighted average
        overall = (
            query_structure * 0.30 +
            table_relevance * 0.25 +
            result_plausibility * 0.25 +
            data_availability * 0.20
        )
        
        # Generate explanation
        explanation = self._generate_explanation(
            question=question,
            results=results,
            overall=overall,
            is_no_data_expected=is_no_data_expected,
            query_structure=query_structure,
            table_relevance=table_relevance,
            result_plausibility=result_plausibility
        )
        
        return ConfidenceScore(
            overall=overall,
            query_structure=query_structure,
            table_relevance=table_relevance,
            result_plausibility=result_plausibility,
            data_availability=data_availability,
            is_no_data_expected=is_no_data_expected,
            explanation=explanation
        )
    
    def _extract_tables(self, sql: str) -> List[str]:
        """Extract table names from SQL"""
        from_pattern = r'FROM\s+(\w+)'
        join_pattern = r'JOIN\s+(\w+)'
        
        tables = []
        tables.extend(re.findall(from_pattern, sql, re.IGNORECASE))
        tables.extend(re.findall(join_pattern, sql, re.IGNORECASE))
        
        return list(set([t.lower() for t in tables]))
    
    def _score_table_relevance(self, question: str, tables: List[str]) -> float:
        """
        Score how relevant selected tables are to the question
        """
        question_lower = question.lower()
        
        # Define table-keyword mappings
        table_keywords = {
            'customer_master': ['customer', 'client', 'buyer'],
            'sku_master': ['product', 'sku', 'item', 'article'],
            'sales_invoice': ['sales', 'revenue', 'invoice', 'order'],
            'stock_movement': ['inventory', 'stock', 'movement'],
            'task_master': ['task', 'activity', 'job'],
            'bot_master': ['robot', 'bot', 'agv'],
        }
        
        relevance_score = 0.5  # Base score
        
        for table in tables:
            keywords = table_keywords.get(table, [])
            
            # Check if any keyword appears in question
            if any(kw in question_lower for kw in keywords):
                relevance_score += 0.2
            
            # Bonus if table name itself is in question
            if table.replace('_', ' ') in question_lower:
                relevance_score += 0.1
        
        return min(1.0, relevance_score)
    
    def _score_result_plausibility(
        self,
        question: str,
        sql: str,
        results: List[Dict]
    ) -> float:
        """
        Score how plausible the results are
        """
        if not results:
            # No results - plausibility depends on query type
            return 0.5
        
        plausibility = 0.7  # Base score
        
        # Check for aggregation queries
        if any(word in sql.upper() for word in ['COUNT', 'SUM', 'AVG', 'MAX', 'MIN']):
            # Aggregation queries should return 1 row
            if len(results) == 1:
                plausibility += 0.2
        
        # Check for TOP N queries
        if 'LIMIT' in sql.upper() or 'top' in question.lower():
            # Extract limit
            limit_match = re.search(r'LIMIT\s+(\d+)', sql, re.IGNORECASE)
            if limit_match:
                expected_limit = int(limit_match.group(1))
                if len(results) <= expected_limit:
                    plausibility += 0.1
        
        # Check for reasonable data ranges
        for row in results[:5]:  # Sample first 5 rows
            for key, value in row.items():
                # Check for suspicious values
                if isinstance(value, (int, float)):
                    if value < 0 and 'quantity' in key.lower():
                        plausibility -= 0.1  # Negative quantities suspicious
                    if value > 1_000_000 and 'count' in key.lower():
                        plausibility -= 0.05  # Very large counts suspicious
        
        return max(0.0, min(1.0, plausibility))
    
    def _score_data_availability(
        self,
        question: str,
        sql: str,
        results: List[Dict],
        tables: List[str]
    ) -> Tuple[float, bool]:
        """
        Score data availability and determine if empty result is expected
        
        Returns:
            (score, is_no_data_expected)
        """
        # If results exist, data is available
        if results:
            return 1.0, False
        
        # Empty results - determine if this is expected
        is_no_data_expected = False
        
        # Check if query has very specific filters
        has_specific_filter = any([
            re.search(r"WHERE.*=\s*'[^']+'", sql, re.IGNORECASE),  # Exact match filter
            re.search(r"WHERE.*>\s*\d+", sql, re.IGNORECASE),  # Numeric filter
            'AND' in sql.upper(),  # Multiple filters
        ])
        
        if has_specific_filter:
            # Specific filters may legitimately return no data
            is_no_data_expected = True
            score = 0.8
        else:
            # General query with no results is suspicious
            is_no_data_expected = False
            score = 0.3
        
        # Check table types - master tables should have data
        master_tables = [t for t in tables if 'master' in t.lower()]
        if master_tables and not has_specific_filter:
            # Master tables with no filters should have data
            is_no_data_expected = False
            score = 0.2
        
        return score, is_no_data_expected
    
    def _generate_explanation(
        self,
        question: str,
        results: List[Dict],
        overall: float,
        is_no_data_expected: bool,
        query_structure: float,
        table_relevance: float,
        result_plausibility: float
    ) -> str:
        """Generate human-readable explanation"""
        
        if not results:
            if is_no_data_expected:
                if overall >= 0.7:
                    return (
                        "✅ Query executed successfully. No matching records found in the database. "
                        "This is expected given the specific filters in your query. "
                        "The database does not contain data matching these exact criteria."
                    )
                else:
                    return (
                        "⚠️ No results found. The query executed without errors, but returned no data. "
                        "This could mean: (1) No data exists matching your criteria, or "
                        "(2) The query might need adjustment to search the right fields."
                    )
            else:
                return (
                    "⚠️ No results found, which is unexpected for this type of query. "
                    "Possible reasons: (1) Database tables are empty, "
                    "(2) Wrong tables selected, or (3) Query needs refinement. "
                    "Please verify the data exists or try rephrasing your question."
                )
        
        # Results exist
        if overall >= 0.8:
            return (
                f"✅ High confidence results. Found {len(results)} records. "
                "The query appears correct and results look plausible."
            )
        elif overall >= 0.6:
            return (
                f"✓ Found {len(results)} records with acceptable confidence. "
                "Results look reasonable but please verify."
            )
        else:
            return (
                f"⚠️ Found {len(results)} records but confidence is low. "
                "The query may not be optimal or results might need verification."
            )