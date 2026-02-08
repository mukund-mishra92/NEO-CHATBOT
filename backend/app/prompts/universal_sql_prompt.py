"""
Universal SQL Generation Prompt for NEO Warehouse Database
=============================================================
Works for ANY query type without per-query business rules.
Teaches the LLM HOW to construct queries autonomously using
schema context, relationships, enums, and column facts from
the SchemaRegistry.

The LLM is given:
    1. Full table schemas (columns + types + PKs)
    2. JOIN relationships between selected tables
    3. Valid enum values for WHERE filters
    4. Critical column facts (non-existent columns, cross-refs)
    5. Multi-hop join paths for complex queries
    6. Entity resolution data (BOT-0008, STATION_ID, etc.)

Author: NEO Chatbot Team
Date: 2026-02-08
"""


SYSTEM_PROMPT = """You are a senior MySQL 8.x Text-to-SQL generator for the NEO automated warehouse (ASRS) system.

YOUR ROLE:
Generate ONE precise, read-only SQL query that answers the user's question.
You have access to complete schema context — tables, columns, types, JOINs, and valid enum values.

ABSOLUTE RULES:
1. ONLY use tables and columns from the SCHEMA CONTEXT provided below.
2. ONLY SELECT statements. No INSERT, UPDATE, DELETE, DROP, ALTER, CREATE.
3. Before using ANY column, verify it exists in the SCHEMA CONTEXT.
4. Use the TABLE RELATIONSHIPS section for JOIN conditions — never guess join keys.
5. Use the ENUM/VALID VALUES section for correct WHERE filter strings.
6. Read the CRITICAL COLUMN FACTS section — it lists columns that DO NOT EXIST.

SQL BEST PRACTICES:
- Always use table aliases for readability (e.g., lim, sm, sbm, lm, tml).
- Use explicit JOIN ON syntax, never comma-joins.
- For aggregations, include GROUP BY for every non-aggregated SELECT column.
- For time-based queries, use the appropriate timestamp column from the schema.
- Default LIMIT 100 unless the user asks for all data or a specific count.
- Use DATE(timestamp_col) for date filtering, not string comparisons.
- Use CURDATE() for "today", DATE_SUB(CURDATE(), INTERVAL n DAY) for "last N days".
- For "yesterday": DATE(col) = DATE_SUB(CURDATE(), INTERVAL 1 DAY).
- For counts/aggregations, ORDER BY the count DESC unless user specifies otherwise.

COMMON PATTERNS IN THIS DATABASE:
- Inventory by SKU name: JOIN live_inventory_master.ARTICLE_ID = sku_master.SKU_ID
- Bin physical location: JOIN store_bin_master.LOCATION_ID = location_master.LOCATION_ID
- Expiry date: JOIN via sku_batch_master (compound key: SKU_ID + BATCH_ID)
- Bin presentations: COUNT tasks from task_master_log with TASK_TYPE filter
- Bot info: bot_master has NO BOT_NAME column, use BOT_ID
- Station: hw_station_master has STATION_ID and STATION_ALIAS_NAME

RESPONSE FORMAT:
Return valid JSON with this exact structure:
{
    "sql": "SELECT ...",
    "tables_used": ["table1", "table2"],
    "columns_used": ["table1.col1", "table2.col2"],
    "primary_keys_used": ["table1.pk"],
    "assumptions": ["any assumptions made"],
    "warnings": ["any potential issues"],
    "needs_followup": false,
    "followup_questions": [],
    "is_read_only": true,
    "confidence": 0.85
}
"""


def build_universal_prompt(
    schema_context: str,
    relationship_text: str = "",
    enum_text: str = "",
    path_text: str = "",
    column_facts: str = "",
    entity_context: str = "",
) -> str:
    """
    Build the complete system prompt by combining the universal instructions
    with the dynamic schema context from SchemaRegistry.

    Args:
        schema_context:    TABLE/COLUMNS/PK blocks for selected tables
        relationship_text: JOIN ON clauses between selected tables
        enum_text:         Valid enum values for WHERE filters
        path_text:         Multi-hop join paths
        column_facts:      Critical column truths
        entity_context:    Resolved entity info (BOT_ID, STATION_ID, etc.)

    Returns:
        Complete system prompt string for the LLM.
    """
    parts = [SYSTEM_PROMPT]

    # Schema context
    parts.append("\n" + "=" * 80)
    parts.append("SCHEMA CONTEXT (ONLY these tables/columns are available)")
    parts.append("=" * 80)
    parts.append(schema_context)

    # Relationships
    if relationship_text:
        parts.append("\n" + relationship_text)

    # Enum values
    if enum_text:
        parts.append("\n" + enum_text)

    # Multi-hop paths
    if path_text:
        parts.append("\n" + path_text)

    # Column facts
    if column_facts:
        parts.append("\n" + column_facts)

    # Entity resolution
    if entity_context:
        parts.append("\nENTITY RESOLUTION:")
        parts.append("- If RESOLVED_ENTITIES are provided, use those EXACT values.")
        parts.append("- If RESOLVED_CANDIDATES with multiple matches, set needs_followup=true.")
        parts.append(entity_context)

    return "\n".join(parts)
