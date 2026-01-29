import json
import re
import logging
from .semantic_frame import SemanticFrame

logger = logging.getLogger(__name__)


class SemanticFrameExtractor:
    def __init__(self, llm_service):
        self.llm = llm_service

    def extract(self, question: str, schema_summary: str) -> SemanticFrame:
        prompt = f"""You are a SQL planning assistant.

DO NOT generate SQL. DO NOT use JOINs.

Return ONLY valid JSON (no markdown, no explanation) with these exact keys:
{{
  "base_table": "table_name",
  "dimensions": ["col1", "col2"],
  "metrics": ["COUNT(*)", "SUM(col)"],
  "filters": ["col > value"],
  "group_by": ["col1"],
  "order_by": ["col1 DESC"],
  "limit": 100
}}

Available Schema:
{schema_summary}

User Question: {question}

JSON Response:"""

        response = self.llm.generate_response(
            messages=[{"role": "user", "content": prompt}],
            temperature=0.1
        )

        logger.info(f"🤖 LLM Response: {response[:500]}")

        # Extract JSON from response (handle markdown code blocks)
        json_str = self._extract_json(response)
        
        try:
            data = json.loads(json_str)
        except json.JSONDecodeError as e:
            logger.error(f"❌ Failed to parse JSON: {e}\nResponse: {json_str}")
            raise ValueError(f"LLM returned invalid JSON: {str(e)}")

        return SemanticFrame(
            base_table=data.get("base_table", ""),
            dimensions=data.get("dimensions", []),
            metrics=data.get("metrics", []),
            filters=data.get("filters", []),
            group_by=data.get("group_by", []),
            order_by=data.get("order_by", []),
            limit=data.get("limit", 100)
        )
    
    def _extract_json(self, text: str) -> str:
        """Extract JSON from text, handling markdown code blocks"""
        text = text.strip()
        
        # Try to extract from markdown code block
        json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, re.DOTALL)
        if json_match:
            return json_match.group(1)
        
        # Try to find JSON object directly
        json_match = re.search(r'\{.*\}', text, re.DOTALL)
        if json_match:
            return json_match.group(0)
        
        return text
