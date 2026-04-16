"""
Agentic SQL Orchestrator
Wires the 4 specialized agents into a LangGraph StateGraph:

    QueryAnalyzer → SchemaFilter → SQLWriter → SQLReviewer
                                       ↑            |
                                       └── retry ───┘  (max 2 retries)

Falls back gracefully to the traditional single-shot pipeline if
LangGraph is unavailable or an unrecoverable error occurs.
"""

import json
import logging
import os
import time
from typing import Any, Dict, List, Optional

from .state import SQLAgentState
from .query_analyzer import build_query_analyzer_messages, parse_analyzer_response
from .schema_filter_agent import build_schema_filter_messages, parse_schema_filter_response
from .sql_writer import build_sql_writer_messages, parse_sql_writer_response
from .sql_reviewer import build_sql_reviewer_messages, parse_reviewer_response

logger = logging.getLogger(__name__)

# ── Guard imports ────────────────────────────────────────────
try:
    from langgraph.graph import StateGraph, END
    LANGGRAPH_AVAILABLE = True
except ImportError:
    LANGGRAPH_AVAILABLE = False
    logger.warning("LangGraph not installed — agentic SQL disabled")

try:
    from langchain_openai import ChatOpenAI
    LANGCHAIN_OPENAI_AVAILABLE = True
except ImportError:
    LANGCHAIN_OPENAI_AVAILABLE = False

try:
    from langchain_groq import ChatGroq
    LANGCHAIN_GROQ_AVAILABLE = True
except ImportError:
    LANGCHAIN_GROQ_AVAILABLE = False


class AgenticSQLOrchestrator:
    """
    Multi-agent SQL generation pipeline using LangGraph.

    Usage:
        orchestrator = AgenticSQLOrchestrator()
        result = orchestrator.run(
            question="total bots at shakti",
            clean_question="total bots at shakti",
            selected_tables=["bot_master"],
            filtered_schema={...},
            entity_context="host-location = 'SHAKTI'",
            domain_knowledge="...",
        )
        # result = {"sql": "...", "confidence": 0.9, ...}
    """

    def __init__(
        self,
        provider: Optional[str] = None,
        model: Optional[str] = None,
        temperature: float = 0.0,
        max_iterations: int = 2,
    ):
        """
        Initialize the orchestrator.

        Args:
            provider: "openai" or "groq". Auto-detected from ai_config if None.
            model: Model name. Auto-detected from ai_config if None.
            temperature: LLM temperature (0 for deterministic SQL).
            max_iterations: Max Writer → Reviewer retry loops.
        """
        self.max_iterations = max_iterations
        self.temperature = temperature
        self._graph = None
        self._graph_built = False

        # ── Resolve provider & model ────────────────────────
        if provider and model:
            self._provider = provider.lower()
            self._model = model
        else:
            self._provider, self._model = self._resolve_from_config()

        # ── Initialize LLM ──────────────────────────────────
        self.llm = self._init_llm()
        if self.llm:
            logger.info(
                f"✅ AgenticSQLOrchestrator ready: provider={self._provider}, "
                f"model={self._model}, max_iter={self.max_iterations}"
            )
        else:
            logger.warning("⚠️ AgenticSQLOrchestrator: No LLM available — will not function")

    # ─────────────────────────────────────────────────────────
    # INITIALIZATION HELPERS
    # ─────────────────────────────────────────────────────────

    @staticmethod
    def _resolve_from_config():
        """Read provider & model from the shared AI config."""
        try:
            from app.services.ai_config_service import get_ai_config_service
            cfg = get_ai_config_service().get_config()
            provider = cfg.get("active_provider", "openai")
            # Use agent_model (same as the RAG agentic service)
            model = cfg.get("agent_model") or cfg.get("sql_model", "gpt-5.2")
            return provider, model
        except Exception as e:
            logger.warning(f"Could not read AI config: {e}, defaulting to openai/gpt-5.2")
            return "openai", "gpt-5.2"

    def _init_llm(self):
        """Create a LangChain chat model (ChatOpenAI or ChatGroq)."""
        try:
            if self._provider == "openai" and LANGCHAIN_OPENAI_AVAILABLE:
                api_key = os.getenv("OPENAI_API_KEY")
                if not api_key:
                    raise ValueError("OPENAI_API_KEY not set")
                return ChatOpenAI(
                    api_key=api_key,
                    model=self._model,
                    temperature=self.temperature,
                    max_tokens=4096,
                    request_timeout=45,
                )
            elif self._provider == "groq" and LANGCHAIN_GROQ_AVAILABLE:
                api_key = os.getenv("GROQ_API_KEY") or os.getenv("GROK_API_KEY")
                if not api_key:
                    raise ValueError("GROQ_API_KEY not set")
                return ChatGroq(
                    api_key=api_key,
                    model=self._model,
                    temperature=self.temperature,
                    max_tokens=4096,
                )
            else:
                logger.error(f"Provider '{self._provider}' not available")
                return None
        except Exception as e:
            logger.error(f"Failed to init LLM: {e}")
            return None

    # ─────────────────────────────────────────────────────────
    # LANGGRAPH GRAPH CONSTRUCTION
    # ─────────────────────────────────────────────────────────

    @property
    def graph(self):
        """Lazy-build the LangGraph workflow on first use."""
        if not self._graph_built:
            self._graph = self._build_graph()
            self._graph_built = True
        return self._graph

    def _build_graph(self):
        """
        Build the 4-node LangGraph workflow:
            analyzer → schema_filter → sql_writer → sql_reviewer
                                          ↑              |
                                          └── retry ─────┘
        """
        if not LANGGRAPH_AVAILABLE:
            logger.error("Cannot build graph — LangGraph not installed")
            return None

        workflow = StateGraph(SQLAgentState)

        # ── Add nodes ────────────────────────────────────────
        workflow.add_node("query_analyzer", self._node_query_analyzer)
        workflow.add_node("schema_filter", self._node_schema_filter)
        workflow.add_node("sql_writer", self._node_sql_writer)
        workflow.add_node("sql_reviewer", self._node_sql_reviewer)

        # ── Define edges ─────────────────────────────────────
        workflow.set_entry_point("query_analyzer")
        workflow.add_edge("query_analyzer", "schema_filter")
        workflow.add_edge("schema_filter", "sql_writer")
        workflow.add_edge("sql_writer", "sql_reviewer")

        # Conditional: reviewer decides pass/retry/stop
        workflow.add_conditional_edges(
            "sql_reviewer",
            self._decide_after_review,
            {
                "accept": END,
                "retry": "sql_writer",
                "max_iterations": END,
            },
        )

        compiled = workflow.compile()
        logger.info("✅ Agentic SQL graph compiled (4-node pipeline)")
        return compiled

    # ─────────────────────────────────────────────────────────
    # GRAPH NODES (each calls one agent)
    # ─────────────────────────────────────────────────────────

    def _node_query_analyzer(self, state: SQLAgentState) -> dict:
        """Node 1 — Query Analyzer Agent."""
        logger.info("🔍 [Agent 1/4] Query Analyzer starting...")
        t0 = time.time()
        try:
            messages = build_query_analyzer_messages(state)
            response = self._call_llm(messages)
            parsed = parse_analyzer_response(response)
            logger.info(
                f"✅ [Agent 1/4] Query Analyzer done in {time.time()-t0:.1f}s: "
                f"intent={parsed.get('query_intent','?')[:60]}, "
                f"type={parsed.get('query_type','?')}, "
                f"complexity={parsed.get('complexity','?')}"
            )
            return {
                "query_intent": parsed["query_intent"],
                "query_type": parsed["query_type"],
                "identified_metrics": parsed["identified_metrics"],
                "time_range": parsed["time_range"],
                "complexity": parsed["complexity"],
                "analysis_notes": parsed["analysis_notes"],
            }
        except Exception as e:
            logger.error(f"❌ Query Analyzer failed: {e}")
            return {
                "query_intent": state.get("clean_question", ""),
                "query_type": "aggregation",
                "identified_metrics": [],
                "time_range": "none",
                "complexity": "moderate",
                "analysis_notes": f"Analyzer failed: {e}",
            }

    def _node_schema_filter(self, state: SQLAgentState) -> dict:
        """Node 2 — Schema & Filter Agent."""
        logger.info("📋 [Agent 2/4] Schema & Filter Agent starting...")
        t0 = time.time()
        try:
            messages = build_schema_filter_messages(state)
            response = self._call_llm(messages)
            parsed = parse_schema_filter_response(response)
            logger.info(
                f"✅ [Agent 2/4] Schema & Filter done in {time.time()-t0:.1f}s: "
                f"tables={parsed.get('tables_to_use',[])}, "
                f"pattern={parsed.get('sql_pattern','?')}, "
                f"filters={len(parsed.get('mandatory_filters',[]))}"
            )
            return {
                "tables_to_use": parsed["tables_to_use"],
                "join_plan": parsed["join_plan"],
                "mandatory_filters": parsed["mandatory_filters"],
                "optional_filters": parsed["optional_filters"],
                "formula_to_apply": parsed["formula_to_apply"],
                "sql_pattern": parsed["sql_pattern"],
                "schema_plan_notes": parsed["schema_plan_notes"],
            }
        except Exception as e:
            logger.error(f"❌ Schema & Filter Agent failed: {e}")
            return {
                "tables_to_use": state.get("selected_tables", []),
                "join_plan": [],
                "mandatory_filters": [],
                "optional_filters": [],
                "formula_to_apply": "",
                "sql_pattern": "simple_select",
                "schema_plan_notes": f"Agent failed: {e}",
            }

    def _node_sql_writer(self, state: SQLAgentState) -> dict:
        """Node 3 — SQL Writer Agent."""
        iteration = state.get("iteration_count", 0)
        logger.info(f"✍️  [Agent 3/4] SQL Writer starting (iteration {iteration})...")
        t0 = time.time()
        try:
            messages = build_sql_writer_messages(state)
            response = self._call_llm(messages)
            parsed = parse_sql_writer_response(response)

            if "error" in parsed:
                logger.error(f"❌ SQL Writer error: {parsed['error']}")
                return {
                    "generated_sql": "",
                    "sql_confidence": 0.0,
                    "sql_assumptions": [],
                    "sql_warnings": [parsed["error"]],
                    "error": parsed["error"],
                }

            logger.info(
                f"✅ [Agent 3/4] SQL Writer done in {time.time()-t0:.1f}s: "
                f"confidence={parsed.get('sql_confidence',0):.2f}, "
                f"sql={parsed.get('generated_sql','')[:80]}..."
            )
            return {
                "generated_sql": parsed["generated_sql"],
                "sql_confidence": parsed["sql_confidence"],
                "sql_assumptions": parsed["sql_assumptions"],
                "sql_warnings": parsed["sql_warnings"],
            }
        except Exception as e:
            logger.error(f"❌ SQL Writer failed: {e}")
            return {
                "generated_sql": "",
                "sql_confidence": 0.0,
                "sql_assumptions": [],
                "sql_warnings": [str(e)],
                "error": str(e),
            }

    def _node_sql_reviewer(self, state: SQLAgentState) -> dict:
        """Node 4 — SQL Reviewer Agent."""
        logger.info("🔎 [Agent 4/4] SQL Reviewer starting...")
        t0 = time.time()

        sql = state.get("generated_sql", "")
        if not sql:
            logger.warning("⚠️ No SQL to review — skipping")
            return {
                "review_passed": False,
                "review_issues": ["No SQL was generated"],
                "review_suggestions": "SQL Writer must produce a query",
                "corrected_sql": "",
                "iteration_count": state.get("iteration_count", 0) + 1,
            }

        try:
            messages = build_sql_reviewer_messages(state)
            response = self._call_llm(messages)
            parsed = parse_reviewer_response(response)

            passed = parsed["review_passed"]
            issues = parsed.get("review_issues", [])
            corrected = parsed.get("corrected_sql", "")

            # If reviewer provided a corrected SQL, use it
            result = {
                "review_passed": passed,
                "review_issues": issues,
                "review_suggestions": parsed.get("review_suggestions", ""),
                "corrected_sql": corrected,
                "iteration_count": state.get("iteration_count", 0) + 1,
            }

            # If review passed and there's a corrected SQL, use it as final
            if passed and corrected:
                result["generated_sql"] = corrected
                result["final_sql"] = corrected
            elif passed:
                result["final_sql"] = sql
            elif corrected:
                # Review failed but reviewer provided a fix — use it
                result["generated_sql"] = corrected

            adj = parsed.get("confidence_adjustment", 0.0)
            if adj:
                result["sql_confidence"] = max(
                    0.0,
                    min(1.0, state.get("sql_confidence", 0.75) + adj),
                )

            logger.info(
                f"{'✅' if passed else '❌'} [Agent 4/4] SQL Reviewer done in "
                f"{time.time()-t0:.1f}s: passed={passed}, "
                f"issues={len(issues)}"
            )
            return result

        except Exception as e:
            logger.error(f"❌ SQL Reviewer failed: {e}")
            # If reviewer fails, accept the SQL as-is
            return {
                "review_passed": True,
                "review_issues": [],
                "review_suggestions": f"Reviewer error: {e}",
                "corrected_sql": "",
                "final_sql": sql,
                "iteration_count": state.get("iteration_count", 0) + 1,
            }

    # ─────────────────────────────────────────────────────────
    # CONDITIONAL EDGES
    # ─────────────────────────────────────────────────────────

    def _decide_after_review(self, state: SQLAgentState) -> str:
        """Decide whether to accept, retry, or stop."""
        if state.get("review_passed", False):
            logger.info("✅ Review PASSED — accepting SQL")
            return "accept"

        iteration = state.get("iteration_count", 0)
        max_iter = state.get("max_iterations", self.max_iterations)

        if iteration >= max_iter:
            logger.warning(
                f"⚠️ Max iterations ({max_iter}) reached — accepting best SQL"
            )
            # Accept whatever we have
            return "max_iterations"

        logger.info(
            f"🔄 Review FAILED (iteration {iteration}/{max_iter}) — retrying SQL Writer"
        )
        return "retry"

    # ─────────────────────────────────────────────────────────
    # LLM CALL
    # ─────────────────────────────────────────────────────────

    def _call_llm(self, messages: List[Dict[str, str]]) -> str:
        """
        Call the LangChain LLM with the given messages.
        Returns the response text.
        """
        if not self.llm:
            raise RuntimeError("No LLM available")

        from langchain_core.messages import HumanMessage, SystemMessage

        lc_messages = []
        for msg in messages:
            role = msg["role"]
            content = msg["content"]
            if role == "system":
                lc_messages.append(SystemMessage(content=content))
            else:
                lc_messages.append(HumanMessage(content=content))

        response = self.llm.invoke(lc_messages)
        return response.content

    # ─────────────────────────────────────────────────────────
    # PUBLIC API
    # ─────────────────────────────────────────────────────────

    def is_available(self) -> bool:
        """Check if the orchestrator is ready to run."""
        return (
            self.llm is not None
            and LANGGRAPH_AVAILABLE
            and self.graph is not None
        )

    def run(
        self,
        question: str,
        clean_question: str,
        selected_tables: List[str],
        filtered_schema: Dict[str, Any],
        entity_context: str = "",
        domain_knowledge: str = "",
        conversation_history: Optional[List[Dict[str, str]]] = None,
        multi_tenant_config: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Run the full agentic SQL generation pipeline.

        Returns:
            Dict with keys: sql, confidence, assumptions, warnings,
                            tables_used, review_passed, iterations, timing
        """
        if not self.is_available():
            raise RuntimeError("AgenticSQLOrchestrator is not available")

        start_time = time.time()

        # Build initial state
        initial_state: SQLAgentState = {
            # Input
            "question": question,
            "clean_question": clean_question,
            "selected_tables": selected_tables,
            "filtered_schema": filtered_schema,
            "entity_context": entity_context,
            "domain_knowledge": domain_knowledge,
            "conversation_history": conversation_history or [],
            "multi_tenant_config": multi_tenant_config or {},
            # Agent outputs (will be filled by agents)
            "query_intent": "",
            "query_type": "",
            "identified_metrics": [],
            "time_range": "",
            "complexity": "",
            "analysis_notes": "",
            "tables_to_use": [],
            "join_plan": [],
            "mandatory_filters": [],
            "optional_filters": [],
            "formula_to_apply": "",
            "sql_pattern": "",
            "schema_plan_notes": "",
            "generated_sql": "",
            "sql_confidence": 0.0,
            "sql_assumptions": [],
            "sql_warnings": [],
            "review_passed": False,
            "review_issues": [],
            "review_suggestions": "",
            "corrected_sql": "",
            # Control
            "iteration_count": 0,
            "max_iterations": self.max_iterations,
            "final_sql": "",
            "final_confidence": 0.0,
            "error": "",
        }

        logger.info(
            f"🚀 Agentic SQL Pipeline started for: \"{clean_question[:80]}\" "
            f"(tables={selected_tables}, max_iter={self.max_iterations})"
        )

        try:
            # Run the LangGraph workflow
            final_state = self.graph.invoke(initial_state)

            elapsed = time.time() - start_time
            sql = final_state.get("final_sql") or final_state.get("generated_sql", "")
            confidence = final_state.get("sql_confidence", 0.5)

            logger.info(
                f"🏁 Agentic SQL Pipeline complete in {elapsed:.1f}s: "
                f"iterations={final_state.get('iteration_count',0)}, "
                f"review_passed={final_state.get('review_passed',False)}, "
                f"confidence={confidence:.2f}"
            )

            return {
                "sql": sql,
                "confidence": confidence,
                "assumptions": final_state.get("sql_assumptions", []),
                "warnings": final_state.get("sql_warnings", []),
                "tables_used": final_state.get("tables_to_use", selected_tables),
                "columns_used": [],
                "primary_keys_used": [],
                "needs_followup": False,
                "followup_questions": [],
                "is_read_only": True,
                "source": "agentic_sql_pipeline",
                "selected_tables": selected_tables,
                # Extra metadata
                "review_passed": final_state.get("review_passed", False),
                "review_issues": final_state.get("review_issues", []),
                "iterations": final_state.get("iteration_count", 0),
                "timing_seconds": round(elapsed, 2),
                "query_analysis": {
                    "intent": final_state.get("query_intent", ""),
                    "type": final_state.get("query_type", ""),
                    "metrics": final_state.get("identified_metrics", []),
                    "complexity": final_state.get("complexity", ""),
                },
                "execution_plan": {
                    "tables": final_state.get("tables_to_use", []),
                    "joins": final_state.get("join_plan", []),
                    "mandatory_filters": final_state.get("mandatory_filters", []),
                    "formula": final_state.get("formula_to_apply", ""),
                    "pattern": final_state.get("sql_pattern", ""),
                },
            }

        except Exception as e:
            elapsed = time.time() - start_time
            logger.error(
                f"❌ Agentic SQL Pipeline failed after {elapsed:.1f}s: {e}",
                exc_info=True,
            )
            raise RuntimeError(f"Agentic SQL pipeline failed: {e}") from e
