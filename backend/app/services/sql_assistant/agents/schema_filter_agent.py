"""
Agent 2: Schema & Filter Selector
Takes the query analysis and domain knowledge, produces a concrete execution plan:
tables, joins, filters, formulas, and SQL pattern.
"""

import json
import logging
from typing import Any, Dict, List

from .state import SQLAgentState

logger = logging.getLogger(__name__)

SCHEMA_FILTER_PROMPT = """You are a Schema & Filter Planning Agent for a NEO warehouse SQL system.
You receive a query analysis and must produce a concrete SQL execution plan.

## YOUR RESPONSIBILITIES
1. **Select exact tables** needed (from the available schema)
2. **Define JOIN conditions** with exact ON clauses (always include host-location equality for multi-tenant)
3. **Identify mandatory WHERE filters** — business rules that MUST be applied
4. **Identify the formula/calculation** if a computed metric is requested
5. **Choose the SQL pattern** (simple SELECT, CTE, subquery, UNION, etc.)

## CRITICAL BUSINESS RULES

### Multi-Tenant Architecture
- Every table has a `host-location` column (the tenant identifier)
- ALL JOINs must include `t1.`host-location` = t2.`host-location`` in the ON clause
- NEVER use COUNT(DISTINCT single_id) — IDs are only unique within a host-location

### Bot Status Filters — GET THIS RIGHT
- "total bots" → NO status filter at all. Just COUNT(*) FROM bot_master
- "active bots" → WHERE STATUS = 'ENABLED'
- "available bots" → WHERE IS_ACTIVE = 1 AND IS_BYPASSED = 0
- "charging bots" → needs JOIN to task_mission_log or station data
- "inactive/disabled bots" → WHERE STATUS = 'DISABLED' or IS_ACTIVE = 0
- NEVER add IS_ACTIVE=1 unless the user specifically asks for "active" or "available" bots

### Inventory Calculations
- Volume in cubic meters: Two-step conversion — dimensions in sku_master are in MILLIMETERS
  1. Item volume cm3 = SUM(Quantity) * ((HEIGHT * LENGTH * WIDTH) / 1000)  (mm3 → cm3)
  2. Total m3 = SUM(cm3_per_bin) / 1000000  (cm3 → m3)
  3. MUST use 3-table JOIN: bin_info_master LEFT JOIN live_inventory_master LEFT JOIN sku_master
- Volume utilization %: occupied_cm3 / bin_capacity_cm3 where capacity = (81.0 * 57.0 * 42.5 * 0.95) cm3 per bin
- Audit marked bins: REMARK = 'AUDIT_MARKED' in live_inventory_master (NOT Audit_Mark_Status)
- Inventory quantity: SUM(Quantity) from live_inventory_master
- Weight: SUM(sku.weight * lim.Quantity)

### Common Table Mappings
- Bot data → bot_master
- Live inventory → live_inventory_master  
- SKU details → sku_master
- Bin info → bin_info_master
- Historical tasks → task_mission_log
- Alarms → alarm_log
- SKU batches → sku_batch_master

## AVAILABLE SCHEMA
{schema_context}

## DOMAIN KNOWLEDGE
{domain_knowledge}

## QUERY ANALYSIS FROM PREVIOUS AGENT
{analysis_context}

## OUTPUT FORMAT
Return a JSON execution plan:
```json
{{
    "tables_to_use": ["table1", "table2"],
    "join_plan": [
        "table1 JOIN table2 ON table1.col = table2.col AND table1.`host-location` = table2.`host-location`"
    ],
    "mandatory_filters": [
        "WHERE condition that MUST be in the SQL"
    ],
    "optional_filters": [
        "WHERE condition that would improve accuracy"
    ],
    "formula_to_apply": "The exact SELECT expression for computed metrics",
    "sql_pattern": "simple_select|cte|subquery|union|window_function",
    "select_columns": ["exact columns to SELECT"],
    "group_by": ["columns to GROUP BY, if any"],
    "order_by": "ORDER BY clause, if any",
    "limit": "LIMIT value or 'none'",
    "schema_plan_notes": "Brief explanation of why this plan is correct"
}}
```

## RULES
1. Only use tables and columns from the AVAILABLE SCHEMA
2. Every JOIN must include host-location equality
3. If a formula exists in domain knowledge, USE IT exactly — don't improvise
4. Be specific with columns — use table.column notation
5. For "total" counts with no qualifier, do NOT add status filters
"""


def build_schema_filter_messages(state: SQLAgentState) -> list:
    """Build messages for the Schema & Filter agent."""

    # Build schema context from filtered_schema
    schema_lines = []
    for table, info in state.get("filtered_schema", {}).items():
        cols = info.get("columns", [])
        desc = info.get("description", "")
        biz = info.get("key_business_attributes", [])
        joins = info.get("frequently_joined_with", [])
        analytics = info.get("supports_analytics", [])

        schema_lines.append(f"### {table}")
        if desc:
            schema_lines.append(f"Description: {desc}")
        if biz:
            schema_lines.append(f"Key attributes: {', '.join(biz)}")
        if joins:
            schema_lines.append(f"Common joins: {', '.join(joins)}")
        if analytics:
            schema_lines.append(f"Analytics: {', '.join(analytics)}")
        schema_lines.append(f"Columns: {', '.join(cols)}")
        schema_lines.append("")

    schema_context = "\n".join(schema_lines) if schema_lines else "No schema available"

    # Build analysis context from Agent 1 output
    analysis_context = json.dumps(
        {
            "query_intent": state.get("query_intent", ""),
            "query_type": state.get("query_type", ""),
            "identified_metrics": state.get("identified_metrics", []),
            "time_range": state.get("time_range", ""),
            "complexity": state.get("complexity", ""),
            "analysis_notes": state.get("analysis_notes", ""),
        },
        indent=2,
    )

    prompt = SCHEMA_FILTER_PROMPT.format(
        schema_context=schema_context,
        domain_knowledge=state.get("domain_knowledge", "No domain knowledge available"),
        analysis_context=analysis_context,
    )

    messages = [
        {"role": "system", "content": prompt},
        {
            "role": "user",
            "content": (
                f"Create an execution plan for: \"{state['clean_question']}\"\n\n"
                f"Entity context:\n{state.get('entity_context', 'none')}"
            ),
        },
    ]
    return messages


def parse_schema_filter_response(response_text: str) -> Dict[str, Any]:
    """Parse the Schema & Filter agent's response."""
    try:
        text = response_text.strip()
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0].strip()
        elif "```" in text:
            text = text.split("```")[1].split("```")[0].strip()

        result = json.loads(text)

        return {
            "tables_to_use": result.get("tables_to_use", []),
            "join_plan": result.get("join_plan", []),
            "mandatory_filters": result.get("mandatory_filters", []),
            "optional_filters": result.get("optional_filters", []),
            "formula_to_apply": result.get("formula_to_apply", ""),
            "sql_pattern": result.get("sql_pattern", "simple_select"),
            "schema_plan_notes": result.get("schema_plan_notes", ""),
            # Pass through extra planning data for SQL Writer
            "_select_columns": result.get("select_columns", []),
            "_group_by": result.get("group_by", []),
            "_order_by": result.get("order_by", ""),
            "_limit": result.get("limit", "none"),
        }
    except (json.JSONDecodeError, IndexError, KeyError) as e:
        logger.warning(f"Failed to parse schema filter response: {e}")
        return {
            "tables_to_use": [],
            "join_plan": [],
            "mandatory_filters": [],
            "optional_filters": [],
            "formula_to_apply": "",
            "sql_pattern": "simple_select",
            "schema_plan_notes": f"Parse failed: {response_text[:300]}",
            "_select_columns": [],
            "_group_by": [],
            "_order_by": "",
            "_limit": "none",
        }
