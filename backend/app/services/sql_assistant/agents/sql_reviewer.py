"""
Agent 4: SQL Reviewer
Reviews generated SQL for correctness against the execution plan and domain rules.
Can pass, fail with suggestions, or directly correct the SQL.
"""

import json
import logging
from typing import Any, Dict

from .state import SQLAgentState

logger = logging.getLogger(__name__)

SQL_REVIEWER_PROMPT = """You are an expert SQL Reviewer for a NEO warehouse system.
Your job is to review a generated SQL query for correctness.

## REVIEW CHECKLIST

### 1. Schema Correctness
- All table names exist in the provided schema
- All column names exist in their respective tables
- JOINs reference correct columns

### 2. Multi-Tenant Compliance
- Every JOIN includes `host-location` equality: `t1.`host-location` = t2.`host-location``
- Site-specific queries have the correct `host-location` filter
- No COUNT(DISTINCT single_id) — must use COUNT(*) or composite DISTINCT

### 3. Business Logic Correctness
- "total bots" → NO IS_ACTIVE or STATUS filter
- "active bots" → STATUS = 'ENABLED' is present
- "available bots" → IS_ACTIVE = 1 AND IS_BYPASSED = 0
- Volume calculations use correct 2-step conversion: (H*L*W)/1000 for cm³, then /1000000 for m³. MUST use 3-table JOIN.
- Mandatory filters from the execution plan are present in the SQL

### 4. Filter Accuracy
- Entity values (location, etc.) are correctly applied
- Time range filters match the user's request
- No unnecessary filters that would narrow results incorrectly

### 5. SQL Quality
- Query is read-only (SELECT only)
- Has appropriate LIMIT (listings ≤ 1000, aggregations can omit)
- Column aliases are meaningful
- No syntax errors

## COMMON MISTAKES TO CATCH
1. Adding IS_ACTIVE=1 when user asked for "total" bots
2. Missing host-location in JOIN ON clause
3. Wrong table name (hw_bot_master → should be bot_master)
4. COUNT(DISTINCT BOT_ID) instead of COUNT(*) in multi-tenant
5. Volume formula missing /1000 (mm³→cm³) or /1000000 (cm³→m³) conversion
6b. Using Audit_Mark_Status instead of REMARK for audit queries
6. Missing COALESCE for nullable aggregations
7. Using live_inventory instead of live_inventory_master
8. Date filter logic errors (wrong interval, missing DATE())

## GENERATED SQL TO REVIEW
```sql
{sql}
```

## EXECUTION PLAN (what the SQL should implement)
{execution_plan}

## SCHEMA (allowed tables and columns)
{schema_context}

## ENTITY CONTEXT
{entity_context}

## RESPONSE FORMAT
Return JSON:
```json
{{
    "review_passed": true/false,
    "issues": ["list of specific issues found"],
    "suggestions": "Specific fixes to apply",
    "corrected_sql": "If you can fix it, provide the corrected SQL. Otherwise empty string.",
    "confidence_adjustment": 0.0
}}
```

IMPORTANT: If there are no issues, set review_passed to true and issues to [].
Only fail the review for REAL problems that would cause wrong results or errors.
Minor style preferences are NOT failures.
"""


def build_sql_reviewer_messages(state: SQLAgentState) -> list:
    """Build messages for the SQL Reviewer agent."""

    sql = state.get("generated_sql", "")

    plan = {
        "query_intent": state.get("query_intent", ""),
        "query_type": state.get("query_type", ""),
        "identified_metrics": state.get("identified_metrics", []),
        "tables_to_use": state.get("tables_to_use", []),
        "join_plan": state.get("join_plan", []),
        "mandatory_filters": state.get("mandatory_filters", []),
        "optional_filters": state.get("optional_filters", []),
        "formula_to_apply": state.get("formula_to_apply", ""),
    }
    execution_plan = json.dumps(plan, indent=2)

    # Build schema context
    schema_lines = []
    for table, info in state.get("filtered_schema", {}).items():
        cols = info.get("columns", [])
        schema_lines.append(f"{table}: {', '.join(cols)}")
    schema_context = "\n".join(schema_lines) if schema_lines else "No schema"

    entity_context = state.get("entity_context", "No entities")

    prompt = SQL_REVIEWER_PROMPT.format(
        sql=sql,
        execution_plan=execution_plan,
        schema_context=schema_context,
        entity_context=entity_context,
    )

    messages = [
        {"role": "system", "content": prompt},
        {
            "role": "user",
            "content": (
                f"Review this SQL for the question: \"{state['clean_question']}\"\n"
                f"Does it correctly answer the question?"
            ),
        },
    ]
    return messages


def parse_reviewer_response(response_text: str) -> Dict[str, Any]:
    """Parse the SQL Reviewer agent's response."""
    try:
        text = response_text.strip()
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0].strip()
        elif "```" in text:
            text = text.split("```")[1].split("```")[0].strip()

        result = json.loads(text)

        return {
            "review_passed": result.get("review_passed", True),
            "review_issues": result.get("issues", []),
            "review_suggestions": result.get("suggestions", ""),
            "corrected_sql": result.get("corrected_sql", ""),
            "confidence_adjustment": result.get("confidence_adjustment", 0.0),
        }
    except (json.JSONDecodeError, IndexError, KeyError) as e:
        logger.warning(f"Failed to parse reviewer response: {e}")
        # If we can't parse, assume it passed (conservative)
        return {
            "review_passed": True,
            "review_issues": [],
            "review_suggestions": f"Parse failed: {response_text[:200]}",
            "corrected_sql": "",
            "confidence_adjustment": 0.0,
        }
