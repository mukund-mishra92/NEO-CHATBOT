"""
LLM Judge Module
Uses LLM as judge to evaluate query quality and suggest improvements
"""

import logging
import json
from typing import Dict, Any, List

logger = logging.getLogger(__name__)


class LLMJudge:
    """
    LLM-as-Judge for SQL query quality assessment
    """
    
    def __init__(self, llm_service, schema_validator):
        """
        Initialize LLM Judge
        
        Args:
            llm_service: LLM service for generation
            schema_validator: SchemaValidator for validation
        """
        self.llm_service = llm_service
        self.schema_validator = schema_validator
        self.max_refinement_iterations = 3
        self.judge_confidence_threshold = 0.90
        logger.info("✅ LLMJudge initialized")
    
    def judge_query_quality(self, question: str, sql_query: str, 
                          results: List[Dict[str, Any]], schema_context: str,
                          iteration: int) -> Dict[str, Any]:
        """
        Evaluate query quality and suggest improvements
        
        Args:
            question: User's question
            sql_query: Generated SQL
            results: Query results
            schema_context: Relevant schema
            iteration: Current iteration number
            
        Returns:
            Judgment dict with is_satisfactory, confidence, issues, suggestions
        """
        try:
            # Prepare result summary
            result_summary = self._prepare_result_summary(results)
            
            # Validate query
            validation_msg = self._validate_query(sql_query)
            
            # Build judge prompt
            judge_prompt = self._build_judge_prompt(
                question, sql_query, result_summary, schema_context,
                validation_msg, iteration)
            
            # Get LLM judgment
            response = self.llm_service.generate_response(
                messages=[{"role": "user", "content": judge_prompt}],
                system_prompt="You are an expert SQL quality judge. Be critical but constructive. Return valid JSON only.",
                max_tokens=800,
                temperature=0.2
            )
            
            # Parse JSON response
            judgment = self._parse_judgment_response(response)
            
            logger.info(f"🧑‍⚖️ Judge (iter {iteration}): satisfactory={judgment.get('is_satisfactory')}, "
                       f"confidence={judgment.get('confidence'):.2f}")
            
            return judgment
            
        except Exception as e:
            logger.error(f"❌ Error in query judgment: {e}")
            return self._get_default_judgment()
    
    def _prepare_result_summary(self, results: List[Dict[str, Any]]) -> str:
        """Prepare concise summary of results"""
        if not results:
            return "**No results returned** (0 rows)"
        
        row_count = len(results)
        columns = list(results[0].keys()) if results else []
        
        summary = f"**Row Count:** {row_count}\n"
        summary += f"**Columns:** {', '.join(columns)}\n\n"
        
        # Sample data
        if row_count > 0:
            summary += "**Sample Data (first 3 rows):**\n"
            for i, row in enumerate(results[:3], 1):
                summary += f"\nRow {i}:\n"
                for col, val in row.items():
                    summary += f"  - {col}: {val}\n"
        
        # Data quality
        if row_count > 0:
            first_row = results[0]
            null_count = sum(1 for v in first_row.values() if v is None)
            summary += f"\n**Data Quality:** {null_count}/{len(first_row)} null values\n"
        
        return summary
    
    def _validate_query(self, sql_query: str) -> str:
        """Validate query and return validation message"""
        validation_msg = ""
        
        # Validate tables
        tables_valid, invalid_tables = self.schema_validator.validate_sql_tables(sql_query)
        
        # Validate columns
        columns_valid, invalid_columns = self.schema_validator.validate_sql_columns(sql_query)
        
        # Validate values
        values_valid, invalid_values = self.schema_validator.validate_query_values(sql_query)
        
        if not tables_valid or not columns_valid or not values_valid:
            validation_msg = "\n**⚠️ CRITICAL: QUERY HAS VALIDATION ERRORS!**\n"
            
            if not tables_valid:
                similar = [f"{t} → {self.schema_validator.find_similar_valid_tables(t)}" 
                          for t in invalid_tables]
                validation_msg += f"\nInvalid tables: {', '.join(invalid_tables)}\n"
                validation_msg += f"Similar tables: {', '.join(similar)}\n"
            
            if not columns_valid:
                validation_msg += f"\nInvalid columns: {', '.join(invalid_columns)}\n"
            
            if not values_valid:
                for issue in invalid_values:
                    validation_msg += (f"\n❌ {issue['table']}.{issue['column']} = "
                                     f"'{issue['filter_value']}' (not found!)\n")
                    validation_msg += f"   Actual values: {', '.join([str(v) for v in issue['actual_values'][:10]])}\n"
        
        return validation_msg
    
    def _build_judge_prompt(self, question: str, sql_query: str, 
                          result_summary: str, schema_context: str,
                          validation_msg: str, iteration: int) -> str:
        """Build prompt for judge"""
        return f"""You are an expert SQL query evaluator. Analyze the following:

**User's Question:** {question}

**Generated SQL:**
```sql
{sql_query}
```

{validation_msg}

**Execution Results:**
{result_summary}

**Available Schema:**
{schema_context}

**Current Iteration:** {iteration}/{self.max_refinement_iterations}

**Evaluate query quality on:**
1. **Table/Column/Value Validity**: Do they exist in schema and database?
2. **JOIN Validity**: Are JOINs correct and complete?
3. **Correctness**: Does it answer the question?
4. **Result Quality**: Do results make sense?

**Respond in JSON:**
{{
    "is_satisfactory": true/false,
    "confidence": 0.0-1.0,
    "issues": ["issue 1", ...],
    "suggestions": ["suggestion 1", ...],
    "improved_query": "IMPROVED SQL or null"
}}

**Rules:**
- If invalid tables/columns/values: is_satisfactory=false, confidence=0.2
- If missing/wrong JOINs: is_satisfactory=false, confidence=0.3
- If confidence >= 0.85: is_satisfactory=true
- improved_query must use ONLY valid schema elements"""
    
    def _parse_judgment_response(self, response: str) -> Dict[str, Any]:
        """Parse LLM judgment response"""
        try:
            json_text = response.strip()
            if "```json" in json_text:
                json_text = json_text.split("```json")[1].split("```")[0].strip()
            elif "```" in json_text:
                json_text = json_text.split("```")[1].split("```")[0].strip()
            
            return json.loads(json_text)
        except Exception as e:
            logger.error(f"Error parsing judgment: {e}")
            return self._get_default_judgment()
    
    def _get_default_judgment(self) -> Dict[str, Any]:
        """Return neutral judgment on error"""
        return {
            'is_satisfactory': True,
            'confidence': 0.5,
            'issues': [],
            'suggestions': [],
            'improved_query': None
        }
