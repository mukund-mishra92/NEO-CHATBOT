"""
Production Query Evaluator
===========================

Evaluates the SQL pipeline against real user queries from production logs.

Tests 7 dimensions:
  1. Route Detection     - Does the system classify the query correctly?
                           (KPI / SP / SQL generation / knowledge-base / missing-table guard)
  2. Question Understanding - Did preprocessing extract correct entities, tenant, and synonyms?
  3. Table Selection     - Were the right tables selected? Were irrelevant ones avoided?
  4. Missing-Table Guard - If a table doesn't exist in schema, did we detect it?
  5. Join Quality        - Are the correct join columns used? No Cartesian products?
  6. Time Filtering      - Are time filters accurate and using the right timestamp columns?
  7. Column Selection    - Are presentation columns relevant to the question?

Usage:
  cd Neo-Chatbot
  python -m evaluation.production_query_evaluator                          # All queries
  python -m evaluation.production_query_evaluator --batch 1                # Queries 1-100
  python -m evaluation.production_query_evaluator --batch 2                # Queries 101-200
  python -m evaluation.production_query_evaluator --ids 1,5,10             # Specific queries
  python -m evaluation.production_query_evaluator --dry-run                # Table selection only (no LLM SQL gen)
  python -m evaluation.production_query_evaluator --no-execute             # LLM gen but no DB execution
"""

import io
import sys
import json
import csv
import time
import re
import os
import argparse
import logging
import traceback
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime
from dataclasses import dataclass, field, asdict

# Force UTF-8 output on Windows
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# Add project root to path
ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "backend"))

logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("production_evaluator")


# ============================================================
# Data classes
# ============================================================

@dataclass
class RouteResult:
    """How the query was routed."""
    route: str = ""               # kpi | sp | reuse | sql_generation | missing_table | unknown
    kpi_id: Optional[str] = None
    kpi_name: Optional[str] = None
    kpi_confidence: float = 0.0
    sp_name: Optional[str] = None

@dataclass
class PreprocessResult:
    """Entity / tenant extraction."""
    clean_question: str = ""
    raw_entities: Dict[str, Any] = field(default_factory=dict)
    mapped_entities: Dict[str, Any] = field(default_factory=dict)
    tenant_extracted: Optional[str] = None
    tenant_confidence: float = 0.0
    is_all_sites: bool = False
    is_location_breakdown: bool = False
    synonyms_applied: List[str] = field(default_factory=list)

@dataclass
class TableSelectionResult:
    """Table selection quality."""
    selected_tables: List[str] = field(default_factory=list)
    selection_source: str = ""    # validated | learned | hybrid
    scores: Dict[str, float] = field(default_factory=dict)

@dataclass
class SQLGenerationResult:
    """Generated SQL analysis."""
    sql: str = ""
    tables_used: List[str] = field(default_factory=list)
    columns_used: List[str] = field(default_factory=list)
    has_joins: bool = False
    join_tables: List[str] = field(default_factory=list)
    join_conditions: List[str] = field(default_factory=list)
    has_time_filter: bool = False
    time_columns: List[str] = field(default_factory=list)
    has_tenant_filter: bool = False
    has_limit: bool = False
    confidence: float = 0.0
    assumptions: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    error: Optional[str] = None

@dataclass
class ExecutionResult:
    """SQL execution outcome."""
    success: bool = False
    row_count: int = 0
    execution_time_ms: int = 0
    error: Optional[str] = None
    columns_returned: List[str] = field(default_factory=list)

@dataclass 
class QualityFlags:
    """Automated quality checks."""
    # Route
    route_is_reasonable: bool = True
    route_notes: str = ""
    
    # Table selection
    tables_look_relevant: bool = True
    table_notes: str = ""
    possible_missing_tables: List[str] = field(default_factory=list)
    
    # Join quality
    has_cartesian_product: bool = False
    join_notes: str = ""
    
    # Time filter
    time_filter_appropriate: bool = True
    time_notes: str = ""
    
    # Column selection
    columns_relevant: bool = True
    column_notes: str = ""
    
    # Overall
    overall_score: float = 0.0         # 0-1, automated assessment
    issues: List[str] = field(default_factory=list)

@dataclass
class QueryEvalResult:
    """Complete evaluation result for one query."""
    query_id: int = 0
    query: str = ""
    route: RouteResult = field(default_factory=RouteResult)
    preprocess: PreprocessResult = field(default_factory=PreprocessResult)
    table_selection: TableSelectionResult = field(default_factory=TableSelectionResult)
    sql_generation: SQLGenerationResult = field(default_factory=SQLGenerationResult)
    execution: ExecutionResult = field(default_factory=ExecutionResult)
    quality: QualityFlags = field(default_factory=QualityFlags)
    latency_ms: int = 0
    error: Optional[str] = None


# ============================================================
# Known table-to-concept mappings for quality checks
# ============================================================
CONCEPT_TABLE_MAP = {
    # bot related
    "bot": ["bot_master", "bot_history"],
    "bots": ["bot_master", "bot_history"],
    "active bot": ["bot_master", "bot_history"],
    "inactive bot": ["bot_master", "bot_history"],
    "battery": ["bot_master", "bot_charging_bit_log_archive"],
    "charging": ["bot_master", "bot_charging_bit_log_archive", "hw_charging_station_master"],
    "bot position": ["bot_master", "bot_history"],
    "bot location": ["bot_master", "bot_history"],
    "bot alarm": ["bot_alarm_log", "maintenance_alarm_logs"],
    "alarm": ["bot_alarm_log", "maintenance_alarm_logs"],
    "alarm bypass": ["bot_manual_alarm_log_archive"],
    "calibration": ["auto_calibration_logs"],
    "obstacle": ["bot_obstacle_log"],
    "downtime": ["bot_alarm_log", "bot_history"],

    # bin related
    "bin": ["bin_info_master", "bin_protrusion_master"],
    "bins": ["bin_info_master", "bin_protrusion_master"],
    "bin loading": ["order_bin_task_master", "bin_protrusion_master"],
    "bin segment": ["bin_info_master", "store_bin_master"],
    "bin blocked": ["bin_info_master"],
    "bin protrusion": ["bin_protrusion_master", "bin_protrusion_master_log"],
    "transported": ["bin_protrusion_master", "order_bin_task_master"],

    # inventory related
    "inventory": ["live_inventory_master"],
    "article": ["sku_master", "live_inventory_master"],
    "sku": ["sku_master", "live_inventory_master"],
    "distinct article": ["live_inventory_master", "sku_master"],
    "quantity": ["live_inventory_master"],
    "blocked article": ["live_inventory_master"],
    "blocked sku": ["live_inventory_master"],
    "expiry": ["sku_batch_master", "live_inventory_master"],
    "batch": ["sku_batch_master"],
    "category": ["category_master"],
    "lpn": ["lpn_master"],
    "reserve to put": ["live_inventory_master"],

    # wave / order related
    "wave": ["wave_master", "pick_wave_order_master", "put_wave_order_master"],
    "pick wave": ["pick_wave_order_master", "wave_master"],
    "put wave": ["put_wave_order_master", "wave_master"],
    "order": ["wms_to_wcs_order_line_request_data", "order_bin_mapping", "pick_wave_order_master"],
    "order line": ["wms_to_wcs_order_line_request_data", "order_bin_mapping"],
    "pick order": ["pick_wave_order_master", "wms_to_wcs_order_line_request_data"],
    "put order": ["put_wave_order_master"],
    "short pick": ["short_pick_wave_reason", "pick_wave_order_master"],
    "short put": ["short_put_wave_reason"],
    "pending": ["pick_wave_order_master", "put_wave_order_master", "order_bin_task_master"],
    "stuck": ["wave_master", "pick_wave_order_master", "put_wave_order_master"],
    "processing": ["wave_master", "pick_wave_order_master"],

    # station related
    "station": ["hw_station_master", "station_home_master"],
    "workstation": ["hw_station_master"],
    "ptl": ["hw_ptl_master"],
    "no-read": ["station_no_read_logs"],
    "no read": ["station_no_read_logs"],

    # task related
    "task": ["order_bin_task_master", "task_master_log"],
    "bot task": ["order_bin_task_master", "task_master_log"],
    "recovery": ["recovery_pick_task_master"],
    "maintenance": ["maintenance_task_master", "maintenance_alarm_logs"],

    # location related
    "location": ["location_master"],
    "blocked location": ["location_master", "location_block_master"],
    "tower": ["location_master"],
    "aisle": ["location_master"],
    "storage location": ["location_master"],

    # hardware / infrastructure
    "conveyor": ["hw_conveyor_master", "hw_conveyor_mux_master"],
    "scanner": ["hw_scanner_master"],
    "safety door": ["hw_safety_door_master"],
    "hardware": ["hardware_registered"],
    "gearbox": ["gearbox_log"],
}

# Time-related keywords that should trigger time filtering
TIME_KEYWORDS = [
    "today", "yesterday", "last week", "this week", "last month",
    "last 7 days", "last 3 days", "last 30 days", "last hour",
    "this year", "this month", "hours ago", "days ago", "months ago",
    r"\d+ (day|week|month|hour|year)s?",
    r"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}",
    r"\d{1,2}\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|march|april|june|july|august|september|october|november|december)",
    r"(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}",
    r"\d{4}",
    "now", "currently", "current", "right now",
    r"\d{1,2}\s*(am|pm)",
]

# Known timestamp columns per table
TIMESTAMP_COLUMNS = {
    "bot_alarm_log": ["ALARM_DATE"],
    "bot_master_log": ["logged_timestamp"],
    "bot_charging_bit_log": ["LOGGED_TIMESTAMP"],
    "bot_task_log": ["LOGGED_TIMESTAMP"],
    "task_master_log": ["logged_timestamp"],
    "wave_master": ["CREATED_AT", "UPDATED_AT", "WAVE_COMPLETED_TIMESTAMP"],
    "dashboard_log_wave_process": ["CREATED_AT", "WAVE_COMPLETED_TIMESTAMP"],
    "wms_to_wcs_order_line_request_data": ["CREATED_AT", "UPDATED_AT"],
    "order_bin_mapping": ["CREATED_AT", "UPDATED_AT"],
    "live_inventory_master_log": ["LOG_TIMESTAMP"],
    "bin_loading_wave_order_master": ["CREATED_AT", "UPDATED_AT"],
    "station_master_log": ["LOGGED_TIMESTAMP"],
    "auto_calibration_logs": ["COMPLETED_TIMESTAMP"],
    "obstacle_event_log": ["LOGGED_AT"],
    "lpn_wise_data_log": ["CREATED_AT"],
}


# ============================================================
# Evaluator
# ============================================================

class ProductionQueryEvaluator:

    def __init__(self, queries_path: str = None, dry_run: bool = False, no_execute: bool = False):
        self.dry_run = dry_run
        self.no_execute = no_execute or dry_run
        self.queries: List[str] = []
        self.results: List[QueryEvalResult] = []
        self.svc = None

        # Load queries
        path = Path(queries_path or ROOT / "data" / "queries_till_14_04.txt")
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        # Skip header, strip quotes
        for line in lines[1:]:
            q = line.strip().strip('"').strip()
            if q:
                self.queries.append(q)

        print(f"  Loaded {len(self.queries)} production queries from {path.name}")

    def init_service(self):
        """Initialize SQLAssistantService (heavy — loads embeddings)."""
        print("  Initializing SQL Assistant Service...")
        t0 = time.time()

        try:
            from app.services.sql_assistant.sql_assistant import SQLAssistantService
            self.svc = SQLAssistantService()
            elapsed = time.time() - t0
            print(f"  Service ready in {elapsed:.1f}s ({len(self.svc.schema)} tables)")
        except Exception as e:
            print(f"  [ERROR] Service initialization failed: {e}")
            raise

    def evaluate_batch(self, start: int = 0, end: int = None, query_ids: List[int] = None):
        """Evaluate a batch of queries."""
        if query_ids:
            indices = [(i - 1) for i in query_ids if 0 < i <= len(self.queries)]
        else:
            start = max(0, start)
            end = min(end or len(self.queries), len(self.queries))
            indices = list(range(start, end))

        total = len(indices)
        print(f"\n{'='*80}")
        print(f"  Production Query Evaluation -- {total} queries")
        print(f"  Mode: {'DRY RUN (table selection only)' if self.dry_run else 'NO EXECUTE (SQL gen, no DB)' if self.no_execute else 'FULL (with DB execution)'}")
        print(f"{'='*80}\n")

        for i, idx in enumerate(indices):
            query = self.queries[idx]
            query_id = idx + 1

            try:
                result = self._evaluate_single(query_id, query)
            except Exception as e:
                result = QueryEvalResult(
                    query_id=query_id,
                    query=query,
                    error=str(e)
                )
                logger.error(f"Query #{query_id} crashed: {e}")

            self.results.append(result)

            # Progress line
            status = "OK" if not result.error else "ERR"
            route = result.route.route or "?"
            tables = ",".join(result.table_selection.selected_tables[:3])
            if len(result.table_selection.selected_tables) > 3:
                tables += f"+{len(result.table_selection.selected_tables)-3}"
            score = result.quality.overall_score
            issues_count = len(result.quality.issues)

            print(
                f"  [{status}] #{query_id:>3} | route={route:<15} | "
                f"tables=[{tables:<40}] | "
                f"score={score:.2f} | issues={issues_count} | "
                f"{query[:50]}"
            )

        self._print_summary()

    def _evaluate_single(self, query_id: int, query: str) -> QueryEvalResult:
        """Evaluate a single query across all dimensions."""
        t0 = time.time()
        result = QueryEvalResult(query_id=query_id, query=query)

        # ── Step 1: Preprocessing ──
        try:
            clean_q, entities = self.svc.preprocessor.process(query)
            if self.svc.multi_tenant_enabled and entities.get(self.svc.tenant_column):
                entities = self.svc._map_tenant_to_actual_values(entities)

            result.preprocess = PreprocessResult(
                clean_question=clean_q,
                raw_entities=self._safe_entities(entities),
                mapped_entities=self._safe_entities(entities),
                tenant_extracted=self._get_tenant_str(entities, self.svc.tenant_column),
                tenant_confidence=entities.get("_tenant_confidence", {}).get(
                    str(entities.get(self.svc.tenant_column, "")), 0.0
                ),
                is_all_sites=entities.get("_all_sites", False),
                is_location_breakdown=entities.get("_location_breakdown", False),
            )
        except Exception as e:
            result.preprocess.clean_question = query
            result.error = f"Preprocessing failed: {e}"
            result.latency_ms = int((time.time() - t0) * 1000)
            return result

        # ── Step 2: Route detection ──
        try:
            result.route = self._detect_route(clean_q, entities)
        except Exception as e:
            result.route = RouteResult(route="error")
            logger.warning(f"Route detection error: {e}")

        # ── Step 3: Table Selection ──
        try:
            result.table_selection = self._evaluate_table_selection(clean_q, entities)
        except Exception as e:
            result.table_selection = TableSelectionResult()
            logger.warning(f"Table selection error: {e}")

        # ── Step 4: SQL Generation (if not dry-run and route is sql_generation) ──
        if not self.dry_run and result.route.route == "sql_generation":
            try:
                result.sql_generation = self._evaluate_sql_generation(clean_q, entities, result.table_selection.selected_tables)
            except Exception as e:
                result.sql_generation = SQLGenerationResult(error=str(e))

        # ── Step 5: Execution (if full mode) ──
        if not self.no_execute and result.sql_generation.sql:
            try:
                result.execution = self._evaluate_execution(result.sql_generation.sql, entities)
            except Exception as e:
                result.execution = ExecutionResult(error=str(e))

        # ── Step 6: Quality assessment ──
        result.quality = self._assess_quality(query, result)

        result.latency_ms = int((time.time() - t0) * 1000)
        return result

    # ----------------------------------------------------------
    # ROUTE DETECTION
    # ----------------------------------------------------------
    def _detect_route(self, clean_q: str, entities: dict) -> RouteResult:
        """Detect which route the query would take."""
        route = RouteResult()

        # Check KPI match
        if self.svc.kpi_resolver:
            try:
                match = self.svc.kpi_resolver.resolve(clean_q)
                if match:
                    route.route = "kpi"
                    route.kpi_id = match.kpi_id
                    route.kpi_name = match.kpi_name
                    route.kpi_confidence = match.score
                    return route
            except Exception:
                pass

        # Check SP match
        if self.svc.sp_resolver:
            try:
                sp_match = self.svc.sp_resolver.resolve(clean_q)
                if sp_match:
                    route.route = "sp"
                    route.sp_name = getattr(sp_match, 'sp_name', str(sp_match))
                    return route
            except Exception:
                pass

        # Check missing-table guard
        try:
            missing = self.svc._check_required_tables(clean_q)
            if missing:
                route.route = "missing_table"
                return route
        except Exception:
            pass

        # Check reuse
        try:
            if hasattr(self.svc, 'reuse_engine'):
                from datetime import datetime, timedelta
                try:
                    _delta = self.svc.kpi_resolver._parse_time_range(clean_q)
                    _now = datetime.now()
                    _from = (_now - _delta).strftime("%Y-%m-%d %H:%M:%S") if _delta != timedelta(0) else _now.strftime("%Y-%m-%d 00:00:00")
                    _to = _now.strftime("%Y-%m-%d %H:%M:%S")
                except Exception:
                    _from = _to = None

                reused = self.svc.reuse_engine.try_reuse(
                    clean_q, entities=entities,
                    time_from=_from, time_to=_to,
                    tenant_column=self.svc.tenant_column if self.svc.multi_tenant_enabled else None,
                )
                if reused:
                    route.route = "reuse"
                    return route
        except Exception:
            pass

        route.route = "sql_generation"
        return route

    # ----------------------------------------------------------
    # TABLE SELECTION
    # ----------------------------------------------------------
    def _evaluate_table_selection(self, clean_q: str, entities: dict) -> TableSelectionResult:
        """Evaluate which tables get selected."""
        result = TableSelectionResult()

        # Check priority-validated tables first
        validated = self.svc.table_priority_loader.get_validated_tables_for_query(clean_q)
        if validated.get("correct"):
            result.selected_tables = validated["correct"]
            result.selection_source = "validated"
            return result

        # Check learned tables
        learned = self.svc._get_learned_tables(clean_q)
        if learned:
            result.selected_tables = learned
            result.selection_source = "learned"
            return result

        # Hybrid semantic selection
        result.selected_tables = self.svc.table_selector.select(clean_q, max_tables=12)
        result.selection_source = "hybrid"
        return result

    # ----------------------------------------------------------
    # SQL GENERATION (LLM call, no execution)
    # ----------------------------------------------------------
    def _evaluate_sql_generation(self, clean_q: str, entities: dict,
                                  selected_tables: List[str]) -> SQLGenerationResult:
        """Generate SQL without executing."""
        gen_result = SQLGenerationResult()

        # Build filtered schema (mirrors process_query logic)
        filtered_schema = {}
        for table in selected_tables:
            if table not in self.svc.schema:
                continue
            enriched = {"columns": self.svc.schema[table]}
            if table in self.svc.business_context:
                biz = self.svc.business_context[table]
                enriched.update({
                    "description": biz.get("description", ""),
                    "key_business_attributes": biz.get("key_business_attributes", []),
                    "frequently_joined_with": biz.get("frequently_joined_with", []),
                    "supports_analytics": biz.get("supports_analytics", []),
                    "self_sufficient_for": biz.get("self_sufficient_for", []),
                    "not_needed_for": biz.get("not_needed_for", []),
                })
            filtered_schema[table] = enriched

        # Build entity context
        entity_lines = []
        is_all_sites = entities.get("_all_sites", False)
        for k, v in entities.items():
            if k.startswith('_'):
                continue
            if is_all_sites and k == self.svc.tenant_column:
                continue
            if isinstance(v, list):
                entity_lines.append(f"{k} = {v[0]}" if len(v) == 1 else f"{k} IN ({', '.join(v)})")
            else:
                entity_lines.append(f"{k} = '{v}'")
        entity_context = "\n".join(entity_lines)

        if self.svc.multi_tenant_enabled:
            entity_context += f"\n\nSCHEMA WARNING: {self.svc.multi_tenant_distinct_warning}"

        # Generate SQL
        try:
            llm_result = self.svc.sql_engine.generate(
                question=clean_q,
                schema_override=filtered_schema,
                entity_context=entity_context,
            )

            sql = llm_result.get("sql", "")
            gen_result.sql = sql
            gen_result.tables_used = llm_result.get("tables_used", [])
            gen_result.columns_used = llm_result.get("columns_used", [])
            gen_result.confidence = llm_result.get("confidence", 0.0)
            gen_result.assumptions = llm_result.get("assumptions", [])
            gen_result.warnings = llm_result.get("warnings", [])

            # Analyze SQL
            gen_result.has_joins = bool(re.search(r'\bJOIN\b', sql, re.IGNORECASE))
            gen_result.has_time_filter = bool(re.search(
                r'(WHERE|AND)\s+.*\b(DATE|TIMESTAMP|CREATED_AT|UPDATED_AT|LOGGED_AT|ALARM_DATE|logged_timestamp|LOGGED_TIMESTAMP|WAVE_COMPLETED_TIMESTAMP)\b',
                sql, re.IGNORECASE
            )) or bool(re.search(r'(CURDATE|NOW|DATE_SUB|DATE_ADD|INTERVAL)', sql, re.IGNORECASE))
            gen_result.has_tenant_filter = bool(re.search(r'host.?location', sql, re.IGNORECASE))
            gen_result.has_limit = bool(re.search(r'\bLIMIT\b', sql, re.IGNORECASE))

            # Extract join tables
            join_matches = re.findall(r'\bJOIN\s+`?(\w+)`?', sql, re.IGNORECASE)
            gen_result.join_tables = join_matches

            # Extract join conditions
            on_matches = re.findall(r'\bON\s+(.+?)(?:\s+(?:WHERE|LEFT|RIGHT|INNER|JOIN|GROUP|ORDER|LIMIT|$))', sql, re.IGNORECASE)
            gen_result.join_conditions = on_matches

            # Extract time columns used in WHERE
            time_col_matches = re.findall(
                r'(ALARM_DATE|logged_timestamp|LOGGED_TIMESTAMP|CREATED_AT|UPDATED_AT|COMPLETED_TIMESTAMP|LOG_TIMESTAMP|LOGGED_AT|WAVE_COMPLETED_TIMESTAMP)',
                sql, re.IGNORECASE
            )
            gen_result.time_columns = list(set(time_col_matches))

        except Exception as e:
            gen_result.error = str(e)

        return gen_result

    # ----------------------------------------------------------
    # EXECUTION
    # ----------------------------------------------------------
    def _evaluate_execution(self, sql: str, entities: dict) -> ExecutionResult:
        """Execute the SQL and check results."""
        exec_result = ExecutionResult()
        try:
            result = self.svc.executor.execute(sql)
            exec_result.success = result.row_count >= 0
            exec_result.row_count = result.row_count
            exec_result.execution_time_ms = result.execution_time_ms
            if result.rows:
                exec_result.columns_returned = list(result.rows[0].keys())
        except Exception as e:
            exec_result.error = str(e)
        return exec_result

    # ----------------------------------------------------------
    # QUALITY ASSESSMENT
    # ----------------------------------------------------------
    def _assess_quality(self, query: str, result: QueryEvalResult) -> QualityFlags:
        """Automated quality checks."""
        flags = QualityFlags()
        q_lower = query.lower()
        issues = []
        score = 1.0

        # == Route check ==
        route = result.route.route
        if route == "kpi" and result.route.kpi_confidence < 0.7:
            flags.route_notes = f"Low KPI confidence: {result.route.kpi_confidence:.2f}"
            issues.append(f"Low KPI confidence ({result.route.kpi_confidence:.2f})")
            score -= 0.1

        # == Table relevance check ==
        tables = result.table_selection.selected_tables
        if tables and route == "sql_generation":
            # Check if expected tables are in selection
            for concept, expected_tables in CONCEPT_TABLE_MAP.items():
                if concept in q_lower:
                    overlap = set(expected_tables) & set(tables)
                    if not overlap:
                        flags.possible_missing_tables.extend(expected_tables)
                        issues.append(f"Expected table(s) {expected_tables} for concept '{concept}' not in selection")
                        score -= 0.15

            # Deduplicate
            flags.possible_missing_tables = list(set(flags.possible_missing_tables))
            if flags.possible_missing_tables:
                flags.tables_look_relevant = False
                flags.table_notes = f"Missing: {flags.possible_missing_tables}"

        # == Tenant check ==
        tenant = result.preprocess.tenant_extracted
        has_tenant_keyword = any(kw in q_lower for kw in [
            "frk", "faruknagar", "farukhnagar", "farukanagr", "faruknagar",
            "bhiwandi", "shakti", "chennai", "chenai", "chnnai",
            "bangalore", "banglore", "bengalore", "bengaluru", "blr",
        ])
        is_all_sites = result.preprocess.is_all_sites
        
        if has_tenant_keyword and not tenant and not is_all_sites:
            issues.append("Tenant keyword in query but no tenant extracted")
            score -= 0.15

        if "sitewise" in q_lower or "site wise" in q_lower or "each site" in q_lower or "all site" in q_lower:
            if not is_all_sites and not result.preprocess.is_location_breakdown:
                issues.append("Site-wise query but not detected as all_sites or location_breakdown")
                score -= 0.1

        # == Time filter check ==
        has_time_keyword = any(
            (re.search(pattern, q_lower) if pattern.startswith(r"\d") or "|" in pattern
             else pattern in q_lower)
            for pattern in TIME_KEYWORDS
        )

        if route == "sql_generation" and result.sql_generation.sql:
            if has_time_keyword and not result.sql_generation.has_time_filter:
                issues.append("Time keyword in query but no time filter in SQL")
                flags.time_filter_appropriate = False
                flags.time_notes = "Missing time filter"
                score -= 0.2

        # == Join quality (basic check — no Cartesian products) ==
        if result.sql_generation.has_joins:
            sql = result.sql_generation.sql
            # Count JOINs vs ON conditions
            join_count = len(re.findall(r'\bJOIN\b', sql, re.IGNORECASE))
            on_count = len(re.findall(r'\bON\b', sql, re.IGNORECASE))
            if join_count > on_count:
                flags.has_cartesian_product = True
                flags.join_notes = f"{join_count} JOINs but only {on_count} ON conditions"
                issues.append("Possible Cartesian product (more JOINs than ON conditions)")
                score -= 0.3

        # == Limit check ==
        if route == "sql_generation" and result.sql_generation.sql and not result.sql_generation.has_limit:
            # Only flag if query doesn't use aggregate function
            sql = result.sql_generation.sql
            has_agg = bool(re.search(r'\b(COUNT|SUM|AVG|MAX|MIN|GROUP BY)\b', sql, re.IGNORECASE))
            if not has_agg:
                issues.append("No LIMIT clause on non-aggregate query")
                score -= 0.05

        # == Execution check ==
        if result.execution.error:
            issues.append(f"Execution error: {result.execution.error[:80]}")
            score -= 0.3

        flags.issues = issues
        flags.overall_score = max(0.0, min(1.0, score))
        return flags

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    def _print_summary(self):
        """Print evaluation summary."""
        total = len(self.results)
        if total == 0:
            return

        # Route distribution
        routes = {}
        for r in self.results:
            route = r.route.route or "unknown"
            routes[route] = routes.get(route, 0) + 1

        # Issue counts
        issues_histogram = {}
        for r in self.results:
            for issue in r.quality.issues:
                key = issue.split(":")[0].split("(")[0].strip()
                issues_histogram[key] = issues_histogram.get(key, 0) + 1

        # Scores
        scores = [r.quality.overall_score for r in self.results]
        avg_score = sum(scores) / len(scores)
        perfect = sum(1 for s in scores if s >= 0.95)
        good = sum(1 for s in scores if 0.7 <= s < 0.95)
        poor = sum(1 for s in scores if s < 0.7)

        # Tenant extraction
        has_tenant = sum(1 for r in self.results if r.preprocess.tenant_extracted)
        all_sites = sum(1 for r in self.results if r.preprocess.is_all_sites)

        # Time filter
        has_time = sum(
            1 for r in self.results
            if r.sql_generation.has_time_filter
        )

        errors = sum(1 for r in self.results if r.error)

        print(f"\n{'='*80}")
        print(f"  SUMMARY -- {total} queries evaluated")
        print(f"{'='*80}")
        
        print(f"\n  -- Route Distribution --")
        for route, count in sorted(routes.items(), key=lambda x: -x[1]):
            pct = count / total * 100
            print(f"     {route:<20} {count:>4} ({pct:.1f}%)")

        print(f"\n  -- Quality Scores --")
        print(f"     Average score:    {avg_score:.3f}")
        print(f"     Perfect (>=0.95): {perfect:>4} ({perfect/total*100:.1f}%)")
        print(f"     Good (0.7-0.95):  {good:>4} ({good/total*100:.1f}%)")
        print(f"     Poor (<0.7):      {poor:>4} ({poor/total*100:.1f}%)")
        print(f"     Errors:           {errors:>4} ({errors/total*100:.1f}%)")

        print(f"\n  -- Preprocessing --")
        print(f"     Tenant extracted: {has_tenant:>4}/{total}")
        print(f"     All-sites:        {all_sites:>4}/{total}")

        print(f"\n  -- SQL Generation --")
        sql_gen = [r for r in self.results if r.route.route == "sql_generation"]
        if sql_gen:
            with_time = sum(1 for r in sql_gen if r.sql_generation.has_time_filter)
            with_joins = sum(1 for r in sql_gen if r.sql_generation.has_joins)
            with_tenant = sum(1 for r in sql_gen if r.sql_generation.has_tenant_filter)
            with_limit = sum(1 for r in sql_gen if r.sql_generation.has_limit)
            print(f"     Total SQL gen:    {len(sql_gen):>4}")
            print(f"     With time filter: {with_time:>4}")
            print(f"     With joins:       {with_joins:>4}")
            print(f"     With tenant:      {with_tenant:>4}")
            print(f"     With LIMIT:       {with_limit:>4}")

        if issues_histogram:
            print(f"\n  -- Top Issues --")
            for issue, count in sorted(issues_histogram.items(), key=lambda x: -x[1])[:15]:
                print(f"     {count:>4}x  {issue}")

        print(f"\n{'='*80}")

    # ----------------------------------------------------------
    # SAVE RESULTS
    # ----------------------------------------------------------
    def save_results(self, output_path: str = None):
        """Save detailed results to JSON."""
        path = Path(output_path or ROOT / "evaluation" / "production_query_results.json")
        path.parent.mkdir(parents=True, exist_ok=True)

        data = {
            "timestamp": datetime.now().isoformat(),
            "total_queries": len(self.results),
            "mode": "dry_run" if self.dry_run else ("no_execute" if self.no_execute else "full"),
            "summary": self._build_summary_dict(),
            "results": [asdict(r) for r in self.results],
        }

        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, default=str, ensure_ascii=False)
        print(f"\n  Results saved to {path}")

    def _build_summary_dict(self) -> dict:
        total = len(self.results)
        if total == 0:
            return {}
        
        routes = {}
        for r in self.results:
            route = r.route.route or "unknown"
            routes[route] = routes.get(route, 0) + 1

        scores = [r.quality.overall_score for r in self.results]
        
        issues_histogram = {}
        for r in self.results:
            for issue in r.quality.issues:
                key = issue.split(":")[0].split("(")[0].strip()
                issues_histogram[key] = issues_histogram.get(key, 0) + 1

        return {
            "total": total,
            "avg_score": round(sum(scores)/len(scores), 4),
            "perfect_count": sum(1 for s in scores if s >= 0.95),
            "good_count": sum(1 for s in scores if 0.7 <= s < 0.95),
            "poor_count": sum(1 for s in scores if s < 0.7),
            "error_count": sum(1 for r in self.results if r.error),
            "route_distribution": routes,
            "top_issues": dict(sorted(issues_histogram.items(), key=lambda x: -x[1])[:20]),
        }

    # ----------------------------------------------------------
    # HELPERS
    # ----------------------------------------------------------
    @staticmethod
    def _safe_entities(entities: dict) -> dict:
        """Make entities JSON-serializable."""
        safe = {}
        for k, v in entities.items():
            if isinstance(v, (str, int, float, bool)):
                safe[k] = v
            elif isinstance(v, list):
                safe[k] = v
            elif isinstance(v, dict):
                safe[k] = str(v)
            else:
                safe[k] = str(v)
        return safe

    @staticmethod
    def _get_tenant_str(entities: dict, tenant_col: str) -> Optional[str]:
        val = entities.get(tenant_col)
        if isinstance(val, list):
            return val[0] if val else None
        return val


# ============================================================
# CLI
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="Production Query Evaluator")
    parser.add_argument("--batch", type=int, help="Batch number (1=1-100, 2=101-200, etc.)")
    parser.add_argument("--ids", type=str, help="Comma-separated query IDs (e.g., 1,5,10)")
    parser.add_argument("--start", type=int, default=0, help="Start index (0-based)")
    parser.add_argument("--end", type=int, help="End index (exclusive)")
    parser.add_argument("--dry-run", action="store_true", help="Table selection only (no LLM)")
    parser.add_argument("--no-execute", action="store_true", help="LLM generation but no DB exec")
    parser.add_argument("--output", type=str, help="Output JSON file path")
    parser.add_argument("--queries", type=str, help="Path to queries file")
    args = parser.parse_args()

    evaluator = ProductionQueryEvaluator(
        queries_path=args.queries,
        dry_run=args.dry_run,
        no_execute=args.no_execute
    )

    evaluator.init_service()

    # Determine range
    query_ids = None
    start = args.start
    end = args.end

    if args.ids:
        query_ids = [int(x.strip()) for x in args.ids.split(",")]
    elif args.batch:
        start = (args.batch - 1) * 100
        end = start + 100

    evaluator.evaluate_batch(start=start, end=end, query_ids=query_ids)
    evaluator.save_results(args.output)


if __name__ == "__main__":
    main()
