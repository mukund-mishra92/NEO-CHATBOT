"""
Agent 3: SQL Writer
Takes the execution plan and writes the actual SQL query.
Focused prompt — only SQL generation, not analysis.
"""

import json
import logging
from typing import Any, Dict

from .state import SQLAgentState

logger = logging.getLogger(__name__)

SQL_WRITER_PROMPT = """You are an expert MySQL 8.x SQL Writer for a NEO warehouse system.

You receive a detailed execution plan and must write ONLY the SQL query.
The plan has already been verified by a Schema Agent — trust it.

## ABSOLUTE RULES
1. Generate ONLY valid MySQL 8.x SELECT statements
2. Use ONLY the tables and columns from the provided schema
3. Follow the execution plan precisely — use the specified tables, joins, filters, and formulas
4. Always backtick-quote column names that contain special characters (like `host-location`)
5. Add appropriate LIMIT (default: 1000 for listings, omit for single-row aggregations)
6. NEVER generate INSERT, UPDATE, DELETE, DROP, or any DDL
7. Use table aliases for readability (bm=bot_master, lim=live_inventory_master, etc.)

## MULTI-TENANT RULES
- EVERY JOIN must include `t1.`host-location` = t2.`host-location`` in the ON clause
- For site-specific queries: add `WHERE table.`host-location` = '<value>'`
- For "all sites" queries: NO host-location filter
- For "breakdown by location": include `host-location` in SELECT and GROUP BY
- NEVER use COUNT(DISTINCT single_id) — IDs are only unique per host-location
  Use COUNT(*) or COUNT(DISTINCT col1, col2) with composite key

## SQL BEST PRACTICES
- Use meaningful aliases
- Put each JOIN on its own line
- Put each WHERE condition on its own line
- Use COALESCE for nullable aggregations: COALESCE(SUM(...), 0)
- Date functions: DATE(NOW()), DATE_SUB(NOW(), INTERVAL 7 DAY), etc.
- For percentage: ROUND(value * 100, 2) or ROUND(value * 100 / total, 2)

## EXECUTION PLAN
{execution_plan}

## AVAILABLE SCHEMA (only use these tables and columns)
{schema_context}

## ENTITY CONTEXT (values to use in WHERE)
{entity_context}

## RESPONSE FORMAT
Return a JSON object:
```json
{{
    "sql": "SELECT ... FROM ... WHERE ...",
    "tables_used": ["table1", "table2"],
    "columns_used": ["table1.col1", "table2.col2"],
    "primary_keys_used": ["table1.pk"],
    "assumptions": ["list of assumptions"],
    "warnings": ["any warnings"],
    "needs_followup": false,
    "followup_questions": [],
    "is_read_only": true,
    "confidence": 0.9
}}
```
"""


def build_sql_writer_messages(state: SQLAgentState) -> list:
    """Build messages for the SQL Writer agent."""

    # Build execution plan summary
    plan = {
        "query_intent": state.get("query_intent", ""),
        "query_type": state.get("query_type", ""),
        "tables_to_use": state.get("tables_to_use", []),
        "join_plan": state.get("join_plan", []),
        "mandatory_filters": state.get("mandatory_filters", []),
        "optional_filters": state.get("optional_filters", []),
        "formula_to_apply": state.get("formula_to_apply", ""),
        "sql_pattern": state.get("sql_pattern", "simple_select"),
        "schema_plan_notes": state.get("schema_plan_notes", ""),
    }

    # Include extra planning details from Schema Agent
    for key in ("_select_columns", "_group_by", "_order_by", "_limit"):
        val = state.get(key)
        if val:
            plan[key.lstrip("_")] = val

    execution_plan = json.dumps(plan, indent=2)

    # Build schema context
    schema_lines = []
    for table, info in state.get("filtered_schema", {}).items():
        cols = info.get("columns", [])
        schema_lines.append(f"### {table}\nColumns: {', '.join(cols)}\n")
    schema_context = "\n".join(schema_lines) if schema_lines else "No schema"

    entity_context = state.get("entity_context", "No entities resolved")

    # If this is a retry, include review feedback
    retry_context = ""
    if state.get("iteration_count", 0) > 0 and state.get("review_issues"):
        retry_context = (
            f"\n\n## PREVIOUS ATTEMPT FAILED REVIEW\n"
            f"Issues found: {json.dumps(state['review_issues'])}\n"
            f"Suggestions: {state.get('review_suggestions', 'none')}\n"
            f"Previous SQL: {state.get('generated_sql', 'none')}\n"
            f"FIX THESE ISSUES in your new SQL."
        )

    prompt = SQL_WRITER_PROMPT.format(
        execution_plan=execution_plan,
        schema_context=schema_context,
        entity_context=entity_context,
    )

    messages = [
        {"role": "system", "content": prompt},
        {
            "role": "user",
            "content": (
                f"Write SQL for: \"{state['clean_question']}\"{retry_context}"
            ),
        },
    ]
    return messages


def parse_sql_writer_response(response_text: str) -> Dict[str, Any]:
    """Parse the SQL Writer agent's response."""
    try:
        text = response_text.strip()
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0].strip()
        elif "```" in text:
            text = text.split("```")[1].split("```")[0].strip()

        result = json.loads(text)

        sql = result.get("sql", "").strip()
        if not sql:
            return {"error": "No SQL generated"}

        return {
            "generated_sql": sql,
            "sql_confidence": result.get("confidence", 0.75),
            "sql_assumptions": result.get("assumptions", []),
            "sql_warnings": result.get("warnings", []),
            "tables_used": result.get("tables_used", []),
            "columns_used": result.get("columns_used", []),
            "needs_followup": result.get("needs_followup", False),
            "followup_questions": result.get("followup_questions", []),
        }
    except (json.JSONDecodeError, IndexError, KeyError) as e:
        # Try to extract raw SQL from the response
        logger.warning(f"Failed to parse SQL writer JSON: {e}")

        # Look for SELECT statement directly
        text = response_text.strip()
        for prefix in ("SELECT", "WITH", "select", "with"):
            idx = text.find(prefix)
            if idx >= 0:
                raw_sql = text[idx:].split("```")[0].strip().rstrip(";") + ""
                return {
                    "generated_sql": raw_sql,
                    "sql_confidence": 0.5,
                    "sql_assumptions": ["Extracted raw SQL from unparseable response"],
                    "sql_warnings": ["Response was not valid JSON"],
                    "tables_used": [],
                    "columns_used": [],
                    "needs_followup": False,
                    "followup_questions": [],
                }

        return {"error": f"Could not extract SQL: {response_text[:300]}"}
