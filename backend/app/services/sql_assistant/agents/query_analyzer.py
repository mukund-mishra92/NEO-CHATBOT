"""
Agent 1: Query Analyzer
Understands user intent, identifies metrics, time ranges, and query complexity.
"""

import json
import logging
from typing import Any, Dict

from .state import SQLAgentState

logger = logging.getLogger(__name__)

QUERY_ANALYZER_PROMPT = """You are a Query Analysis Agent for a NEO automated warehouse (ASRS) system.
Your ONLY job is to analyze the user's question and identify exactly what data they need.

You are NOT writing SQL. You are decomposing the question into structured components.

## WAREHOUSE DOMAIN CONTEXT
This is an Automated Storage & Retrieval System (ASRS) warehouse with:
- **Bots**: Autonomous robots that move inventory. Key states: ENABLED/DISABLED, IS_ACTIVE (running), IS_BYPASSED (excluded from operations)
- **Bins**: Storage locations in the warehouse grid. Have physical dimensions, can hold inventory
- **Inventory**: SKUs stored in bins. Tracked by quantity, weight, volume
- **Stations**: Pick/put/charge stations where bots interact with humans or charge
- **Tasks/Missions**: Movement orders assigned to bots
- **Alarms**: System alerts and errors

## COMMON METRIC DEFINITIONS
- "total bots" = ALL bots, NO status filter
- "active bots" = WHERE STATUS = 'ENABLED' (or IS_ACTIVE=1 depending on context)
- "available bots" = WHERE IS_ACTIVE = 1 AND IS_BYPASSED = 0
- "charging bots" = bots currently at charging stations
- "error/alarmed bots" = bots with active alarms
- "inventory volume" or "occupied volume" = physical space occupied by items (length × width × height × quantity)
- "volume utilization" = percentage of bin capacity used
- "audit marked bins" = bins flagged for audit (REMARK = 'AUDIT_MARKED' in live_inventory_master)
- "bin utilization" = what fraction of bins contain inventory

## YOUR TASK
Given the user question and domain knowledge, output a JSON analysis:

```json
{{
    "query_intent": "Clear statement of what the user wants to know",
    "query_type": "aggregation|listing|comparison|time_series|breakdown",
    "identified_metrics": ["list of specific metrics needed"],
    "time_range": "any time constraint mentioned, or 'none'",
    "location_filter": "specific warehouse/location mentioned, or 'all'",
    "complexity": "simple|moderate|complex",
    "analysis_notes": "Key observations that will help SQL generation"
}}
```

## IMPORTANT RULES
1. Be PRECISE about what metric is being asked. "total bots" ≠ "active bots" ≠ "available bots"
2. If the user says "at <location>", that's a warehouse/site filter
3. If asking about "volume" — determine if they mean quantity, physical volume (m³), or utilization (%)
4. Time ranges: "today", "this week", "last 7 days", "yesterday" etc. — extract explicitly
5. "breakdown by" or "per" or "each" = GROUP BY query
"""


def build_query_analyzer_messages(state: SQLAgentState) -> list:
    """Build the messages for the Query Analyzer agent."""
    messages = [
        {"role": "system", "content": QUERY_ANALYZER_PROMPT},
    ]

    # Add domain knowledge as context if available
    user_content = f"## USER QUESTION\n{state['clean_question']}"

    if state.get("domain_knowledge"):
        user_content += f"\n\n## AVAILABLE DOMAIN KNOWLEDGE\n{state['domain_knowledge']}"

    if state.get("entity_context"):
        user_content += f"\n\n## RESOLVED ENTITIES\n{state['entity_context']}"

    messages.append({"role": "user", "content": user_content})
    return messages


def parse_analyzer_response(response_text: str) -> Dict[str, Any]:
    """Parse the Query Analyzer agent's response into structured data."""
    try:
        # Try to extract JSON from the response
        text = response_text.strip()

        # Handle markdown code blocks
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0].strip()
        elif "```" in text:
            text = text.split("```")[1].split("```")[0].strip()

        result = json.loads(text)

        return {
            "query_intent": result.get("query_intent", ""),
            "query_type": result.get("query_type", "aggregation"),
            "identified_metrics": result.get("identified_metrics", []),
            "time_range": result.get("time_range", "none"),
            "complexity": result.get("complexity", "moderate"),
            "analysis_notes": result.get("analysis_notes", ""),
        }
    except (json.JSONDecodeError, IndexError, KeyError) as e:
        logger.warning(f"Failed to parse analyzer response: {e}")
        return {
            "query_intent": response_text[:200],
            "query_type": "aggregation",
            "identified_metrics": [],
            "time_range": "none",
            "complexity": "moderate",
            "analysis_notes": f"Parse failed, raw: {response_text[:300]}",
        }
