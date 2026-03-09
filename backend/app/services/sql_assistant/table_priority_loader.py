"""
Table Priority Loader
Loads validation history from table_priority_validations.jsonl
and applies boosts/penalties during table selection
"""

import json
import logging
from pathlib import Path
from typing import Dict, List, Set
from collections import defaultdict

logger = logging.getLogger(__name__)


class TablePriorityLoader:
    """
    Loads table priority validations and provides boost/penalty multipliers
    """

    def __init__(self, validations_file: Path):
        """
        Args:
            validations_file: Path to table_priority_validations.jsonl
        """
        self.validations_file = validations_file
        self.query_to_correct_tables: Dict[str, Set[str]] = defaultdict(set)
        self.query_to_incorrect_tables: Dict[str, Set[str]] = defaultdict(set)
        
        if validations_file.exists():
            self._load_validations()
        else:
            logger.warning(f"⚠️ Table priority validations file not found: {validations_file}")

    def _load_validations(self):
        """Load validations from JSONL file"""
        try:
            count_correct = 0
            count_incorrect = 0
            with open(self.validations_file, 'r', encoding='utf-8-sig') as f:
                for line in f:
                    if line.strip():
                        record = json.loads(line)
                        query = record['query'].lower().strip()
                        table = record['table_name']
                        is_correct = record['is_correct']
                        
                        if is_correct:
                            self.query_to_correct_tables[query].add(table)
                            count_correct += 1
                        else:
                            self.query_to_incorrect_tables[query].add(table)
                            count_incorrect += 1
            
            logger.info(f"✅ Loaded table priority validations: {count_correct} correct, {count_incorrect} incorrect for {len(self.query_to_correct_tables)} queries")
        except Exception as e:
            logger.error(f"❌ Error loading table priority validations: {e}")

    def get_table_multiplier(self, query: str, table: str) -> float:
        """
        Get priority multiplier for a table given a query
        
        Returns:
            10.0 if table is validated as correct for this query
            0.01 if table is validated as incorrect for this query
            1.0 otherwise (no validation data)
        """
        query_lower = query.lower().strip()
        
        # Exact match
        if table in self.query_to_correct_tables.get(query_lower, set()):
            return 10.0
        
        if table in self.query_to_incorrect_tables.get(query_lower, set()):
            return 0.01
        
        # Partial match (if query contains key phrases)
        for validated_query, correct_tables in self.query_to_correct_tables.items():
            if self._is_similar_query(query_lower, validated_query):
                if table in correct_tables:
                    return 5.0  # Partial boost
        
        for validated_query, incorrect_tables in self.query_to_incorrect_tables.items():
            if self._is_similar_query(query_lower, validated_query):
                if table in incorrect_tables:
                    return 0.1  # Partial penalty
        
        return 1.0  # No validation data

    def _is_similar_query(self, query1: str, query2: str) -> bool:
        """
        Check if two queries are similar (simple keyword matching)
        """
        # Extract key words (ignore common words)
        common_words = {'give', 'me', 'show', 'get', 'all', 'the', 'a', 'an', 'what', 'is', 'are', 'for'}
        
        words1 = set(query1.split()) - common_words
        words2 = set(query2.split()) - common_words
        
        # If more than 50% words match, consider similar
        if not words1 or not words2:
            return False
        
        intersection = words1 & words2
        union = words1 | words2
        
        return len(intersection) / len(union) > 0.5

    def get_validated_tables_for_query(self, query: str) -> Dict[str, List[str]]:
        """
        Get correct and incorrect tables for a query
        
        Returns:
            {
                "correct": [list of correct tables],
                "incorrect": [list of incorrect tables]
            }
        """
        query_lower = query.lower().strip()
        
        # Try exact match first
        if query_lower in self.query_to_correct_tables or query_lower in self.query_to_incorrect_tables:
            correct_list = list(self.query_to_correct_tables.get(query_lower, []))
            incorrect_list = list(self.query_to_incorrect_tables.get(query_lower, []))
            logger.info(f"🔍 Exact match for '{query_lower}': correct={correct_list}, incorrect={incorrect_list}")
            return {
                "correct": correct_list,
                "incorrect": incorrect_list
            }
        
        # Fall back to similarity matching
        correct_tables = set()
        incorrect_tables = set()
        matched_queries = []
        
        for validated_query, tables in self.query_to_correct_tables.items():
            if self._is_similar_query(query_lower, validated_query):
                correct_tables.update(tables)
                matched_queries.append(validated_query)
                logger.info(f"🔍 Similar query match: '{validated_query}' -> correct: {tables}")
        
        # IMPORTANT: Also collect incorrect tables from similar queries
        # This prevents LLM from using commonly wrong tables like sku_master
        for validated_query in matched_queries:
            if validated_query in self.query_to_incorrect_tables:
                incorrect_tables.update(self.query_to_incorrect_tables[validated_query])
                logger.info(f"🔍 Found incorrect tables for '{validated_query}' -> {self.query_to_incorrect_tables[validated_query]}")
        
        return {
            "correct": list(correct_tables),
            "incorrect": list(incorrect_tables)
        }
