"""
Shared state definition for the Agentic SQL pipeline.
Passed between agents in the LangGraph StateGraph.
"""

from typing import Any, Dict, List, Optional, TypedDict


class SQLAgentState(TypedDict):
    """State passed between agents in the SQL generation graph."""

    # ── Input (set once, never mutated) ─────────────────────
    question: str                           # Original user question
    clean_question: str                     # Cleaned/normalized question
    selected_tables: List[str]              # Tables selected by table selector
    filtered_schema: Dict[str, Any]         # Enriched schema per table
    entity_context: str                     # Resolved entity context string
    domain_knowledge: str                   # Full domain knowledge from KnowledgeLayer
    conversation_history: List[Dict[str, str]]  # Conversation context
    multi_tenant_config: Dict[str, Any]     # Tenant column, warnings, flags

    # ── Agent 1 output: Query Analysis ──────────────────────
    query_intent: str                       # What metric/data user wants
    query_type: str                         # "aggregation", "listing", "comparison", "time_series"
    identified_metrics: List[str]           # Metrics identified (e.g., "total bots", "volume utilization")
    time_range: str                         # Time range if any
    complexity: str                         # "simple", "moderate", "complex"
    analysis_notes: str                     # Free-form analysis notes

    # ── Agent 2 output: Schema & Filter Plan ────────────────
    tables_to_use: List[str]                # Final table list (may differ from selected_tables)
    join_plan: List[str]                    # JOIN conditions  
    mandatory_filters: List[str]            # WHERE conditions that must be applied
    optional_filters: List[str]             # WHERE conditions that may help
    formula_to_apply: str                   # Specific formula/calculation
    sql_pattern: str                        # SQL pattern to follow (CTE, subquery, etc.)
    schema_plan_notes: str                  # Free-form planning notes

    # ── Agent 3 output: Generated SQL ───────────────────────
    generated_sql: str                      # The SQL query
    sql_confidence: float                   # Writer's confidence (0-1)
    sql_assumptions: List[str]              # Assumptions made
    sql_warnings: List[str]                 # Warnings about the SQL

    # ── Agent 4 output: Review ──────────────────────────────
    review_passed: bool                     # Whether SQL passed review
    review_issues: List[str]                # Issues found
    review_suggestions: str                 # Specific fix suggestions
    corrected_sql: str                      # Corrected SQL (if reviewer fixed it)

    # ── Control flow ────────────────────────────────────────
    iteration_count: int                    # Current retry iteration
    max_iterations: int                     # Max allowed retries (default: 2)
    final_sql: str                          # Final SQL to return
    final_confidence: float                 # Final confidence score
    error: str                              # Error message if pipeline fails
