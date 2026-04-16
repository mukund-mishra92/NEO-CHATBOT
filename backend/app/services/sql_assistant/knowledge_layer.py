"""
KnowledgeLayer — Domain Knowledge Service for SQL Generation
==============================================================
Loads structured domain knowledge extracted from 101 production KPI queries
and injects relevant context into the SQL generation prompt.

Knowledge files (data/domain_knowledge/):
    - table_usage_patterns.json   → topic → required tables, joins, archive info
    - business_filters.json       → mandatory WHERE conditions per table
    - sql_patterns.json           → reusable CTE/window-function templates
    - domain_formulas.json        → how to calculate key metrics (IPP, BPH, etc.)
    - column_selection_rules.json → per-table column guidance, forbidden columns

Usage:
    layer = KnowledgeLayer()
    knowledge_text = layer.get_knowledge_for_prompt(question, matched_tables)
    # → inject knowledge_text into build_universal_prompt as domain_knowledge param
"""

import json
import logging
import os
from pathlib import Path
from typing import Dict, List, Optional, Set

logger = logging.getLogger(__name__)


class KnowledgeLayer:
    """
    Loads domain knowledge JSON files and provides prompt-ready context
    based on a user query and matched tables.
    """

    def __init__(self, knowledge_dir: Optional[str] = None):
        if knowledge_dir:
            self.knowledge_dir = Path(knowledge_dir)
        else:
            # Default: data/domain_knowledge relative to project root
            # __file__ is backend/app/services/sql_assistant/knowledge_layer.py
            # parents: [0]=sql_assistant, [1]=services, [2]=app, [3]=backend, [4]=project root
            self.knowledge_dir = (
                Path(__file__).resolve().parents[4] / "data" / "domain_knowledge"
            )

        self.table_usage_patterns: List[dict] = []
        self.business_filters: dict = {}
        self.sql_patterns: List[dict] = []
        self.domain_formulas: List[dict] = []
        self.column_rules: dict = {}
        self.config_business_rules: Dict[str, dict] = {}

        self._load_all()

    # ──────────────────────────────────────────────
    # LOADING
    # ──────────────────────────────────────────────

    def _load_json(self, filename: str) -> dict:
        path = self.knowledge_dir / filename
        if not path.exists():
            logger.warning(f"⚠️ Knowledge file not found: {path}")
            return {}
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"❌ Failed to load {filename}: {e}")
            return {}

    def _load_all(self):
        # Table usage patterns
        data = self._load_json("table_usage_patterns.json")
        self.table_usage_patterns = data.get("patterns", [])

        # Business filters
        self.business_filters = self._load_json("business_filters.json")

        # SQL patterns
        data = self._load_json("sql_patterns.json")
        self.sql_patterns = data.get("patterns", [])

        # Domain formulas
        data = self._load_json("domain_formulas.json")
        self.domain_formulas = data.get("formulas", [])

        # Column selection rules
        data = self._load_json("column_selection_rules.json")
        self.column_rules_list = data.get("table_columns", [])
        self.column_global_rules = data.get("global_rules", {})
        # Index by table name for fast lookup
        self.column_rules = {
            item["table"]: item for item in self.column_rules_list
        }

        # Load business rules from config (previously DEAD CODE — now activated)
        self._load_config_business_rules()

        loaded_counts = {
            "table_usage_patterns": len(self.table_usage_patterns),
            "business_filters": len(self.business_filters.get("filters", [])),
            "sql_patterns": len(self.sql_patterns),
            "domain_formulas": len(self.domain_formulas),
            "column_rules": len(self.column_rules),
            "config_business_rules": len(self.config_business_rules),
        }
        logger.info(f"📚 KnowledgeLayer loaded: {loaded_counts}")

    def _load_config_business_rules(self):
        """
        Load business rules from config/sql_assistant_config.json.
        Previously only 'triggers' and 'required_table' were consumed.
        Now we activate: required_filters, join_condition, forbidden_columns,
        grouping_options, notes, critical_notes.
        """
        config_path = (
            Path(__file__).resolve().parents[3] / "config" / "sql_assistant_config.json"
        )
        if not config_path.exists():
            logger.info("ℹ️ No sql_assistant_config.json for business rules")
            return
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                config = json.load(f)
            self.config_business_rules = config.get("business_rules", {})
            logger.info(
                f"📋 Loaded {len(self.config_business_rules)} config business rules"
            )
        except Exception as e:
            logger.warning(f"⚠️ Failed to load config business rules: {e}")

    # ──────────────────────────────────────────────
    # MATCHING
    # ──────────────────────────────────────────────

    def _match_table_usage_patterns(
        self, question_lower: str, matched_tables: List[str]
    ) -> List[dict]:
        """Find table usage patterns relevant to the query."""
        results = []
        table_set = set(t.lower() for t in matched_tables)

        for pattern in self.table_usage_patterns:
            # Check keyword triggers
            keywords = pattern.get("trigger_keywords", [])
            keyword_hits = sum(
                1 for kw in keywords if kw.lower() in question_lower
            )

            # Check if primary tables overlap with matched tables
            primary = pattern.get("primary_tables", [])
            table_overlap = sum(
                1 for t in primary if t.lower() in table_set
            )

            # Score: keyword hits + table overlap
            score = keyword_hits * 2 + table_overlap
            if score > 0:
                results.append((score, pattern))

        # Sort by score descending, return top 5
        results.sort(key=lambda x: x[0], reverse=True)
        return [p for _, p in results[:5]]

    def _match_business_filters(
        self, matched_tables: List[str], question_lower: str = ""
    ) -> List[dict]:
        """
        Find business filters that apply to the matched tables AND the query.

        Context-aware: a filter is only included if:
        1. Its table is in the matched tables, AND
        2. At least one of its `applies_to` keywords appears in the question,
           OR the filter has severity == 'CRITICAL' (always included for safety).

        This prevents e.g. IS_ACTIVE=1 from being injected for "total bots"
        queries where the user wants ALL bots.
        """
        filters = self.business_filters.get("filters", [])
        table_set = set(t.lower() for t in matched_tables)

        results = []
        for f in filters:
            table = f.get("table", "").lower()
            if table not in table_set:
                continue

            severity = f.get("severity", "").upper()
            applies_to = f.get("applies_to", [])

            # CRITICAL filters always apply when the table is matched
            if severity == "CRITICAL":
                results.append(f)
                continue

            # Non-critical filters: require keyword context match
            if question_lower and applies_to:
                has_context = any(
                    term.lower() in question_lower for term in applies_to
                )
                if has_context:
                    results.append(f)

        return results

    def _match_sql_patterns(
        self, question_lower: str, matched_tables: List[str]
    ) -> List[dict]:
        """Find SQL patterns relevant to the query."""
        results = []
        table_set = set(t.lower() for t in matched_tables)

        for pattern in self.sql_patterns:
            keywords = pattern.get("trigger_keywords", [])
            keyword_hits = sum(
                1 for kw in keywords if kw.lower() in question_lower
            )

            # Also check if archive tables are in matched tables
            # (signals need for UNION ALL pattern)
            archive_signal = any("archive" in t for t in table_set)

            score = keyword_hits
            if archive_signal and pattern.get("id") == "sp_001":
                score += 3  # Strong boost for archive union pattern

            if score > 0:
                results.append((score, pattern))

        results.sort(key=lambda x: x[0], reverse=True)
        return [p for _, p in results[:4]]

    def _match_formulas(
        self, question_lower: str
    ) -> List[dict]:
        """Find domain formulas relevant to the query."""
        results = []
        for formula in self.domain_formulas:
            applies_to = formula.get("applies_to", [])
            hits = sum(
                1 for term in applies_to if term.lower() in question_lower
            )
            if hits > 0:
                results.append((hits, formula))

        results.sort(key=lambda x: x[0], reverse=True)
        return [f for _, f in results[:3]]

    def _match_column_rules(
        self, matched_tables: List[str]
    ) -> List[dict]:
        """Find column rules for the matched tables."""
        results = []
        for table in matched_tables:
            rule = self.column_rules.get(table)
            if rule:
                results.append(rule)
        return results

    def _match_config_business_rules(
        self, question_lower: str
    ) -> List[dict]:
        """
        Match question against config business_rules using their triggers.
        Returns rules with their rich metadata (required_filters, join_condition, 
        forbidden_columns, notes, critical_notes, grouping_options).
        These fields were previously DEAD CODE — now activated.
        """
        results = []
        for rule_name, rule_config in self.config_business_rules.items():
            triggers = rule_config.get("triggers", [])
            hit_count = sum(
                1 for t in triggers if t.lower() in question_lower
            )
            if hit_count > 0:
                # Only include rules that have useful metadata beyond triggers
                has_useful_metadata = any(
                    rule_config.get(field)
                    for field in [
                        "required_filters", "join_condition",
                        "forbidden_columns", "notes", "critical_notes",
                        "grouping_options",
                    ]
                )
                if has_useful_metadata:
                    results.append((hit_count, rule_name, rule_config))

        results.sort(key=lambda x: x[0], reverse=True)
        return [(name, config) for _, name, config in results[:5]]

    # ──────────────────────────────────────────────
    # FORMATTING FOR PROMPT
    # ──────────────────────────────────────────────

    def _format_table_patterns(self, patterns: List[dict]) -> str:
        if not patterns:
            return ""
        lines = ["## TABLE USAGE GUIDANCE (from production queries)\n"]
        for p in patterns:
            lines.append(f"**{p.get('topic', 'unknown')}**: {p.get('description', '')}")
            
            primary = p.get("primary_tables", [])
            if primary:
                lines.append(f"  Primary tables: {', '.join(primary)}")

            archive = p.get("archive_tables", [])
            if archive:
                lines.append(f"  Archive tables (UNION ALL needed): {', '.join(archive)}")

            joins = p.get("join_conditions", [])
            if joins:
                lines.append(f"  Join conditions: {'; '.join(joins)}")

            notes = p.get("notes", "")
            if notes:
                lines.append(f"  Note: {notes}")

            lines.append("")

        return "\n".join(lines)

    def _format_business_filters(self, filters: List[dict]) -> str:
        if not filters:
            return ""
        lines = ["## MANDATORY BUSINESS FILTERS (apply these WHERE conditions)\n"]
        for f in filters:
            severity = f.get("severity", "").upper()
            marker = "CRITICAL" if severity == "CRITICAL" else "RECOMMENDED"
            lines.append(
                f"  [{marker}] {f.get('table', '')}: {f.get('filter', '')} "
                f"— {f.get('reason', '')}"
            )
        
        # Add forbidden tables/columns
        forbidden_tables = self.business_filters.get("forbidden_table_combinations", [])
        if forbidden_tables:
            lines.append("\n## FORBIDDEN TABLE MISTAKES")
            for ft in forbidden_tables:
                lines.append(
                    f"  - WRONG: {ft.get('wrong_table', '')} → "
                    f"CORRECT: {ft.get('correct_table', '')} — {ft.get('reason', '')}"
                )

        forbidden_cols = self.business_filters.get("forbidden_columns", [])
        if forbidden_cols:
            lines.append("\n## FORBIDDEN COLUMN MISTAKES")
            for fc in forbidden_cols:
                lines.append(
                    f"  - {fc.get('table', '')}: Columns {fc.get('columns', [])} "
                    f"DO NOT EXIST → Use {fc.get('use_instead', '')} — {fc.get('reason', '')}"
                )

        return "\n".join(lines)

    def _format_sql_patterns(self, patterns: List[dict]) -> str:
        if not patterns:
            return ""
        lines = ["## SQL PATTERNS (use these proven templates)\n"]
        for p in patterns:
            lines.append(f"### {p.get('name', '')}: {p.get('description', '')}")
            lines.append(f"When to use: {p.get('when_to_use', '')}")
            
            template = p.get("template", "")
            if template:
                lines.append(f"```sql\n{template}\n```")

            rules = p.get("rules", [])
            for r in rules:
                lines.append(f"  - {r}")

            lines.append("")

        return "\n".join(lines)

    def _format_formulas(self, formulas: List[dict]) -> str:
        if not formulas:
            return ""
        lines = ["## DOMAIN FORMULAS (calculate metrics correctly)\n"]
        for f in formulas:
            lines.append(f"### {f.get('name', '')}")
            lines.append(f"  {f.get('description', '')}")
            lines.append(f"  Formula: {f.get('formula', '')}")
            
            components = f.get("components", {})
            if components:
                for k, v in components.items():
                    lines.append(f"    - {k}: {v}")

            rules = f.get("critical_rules", [])
            if rules:
                lines.append("  Critical rules:")
                for r in rules:
                    lines.append(f"    - {r}")

            tables = f.get("tables", [])
            if tables:
                lines.append(f"  Required tables: {', '.join(tables)}")

            lines.append("")

        return "\n".join(lines)

    def _format_column_guidance(self, column_rules: List[dict]) -> str:
        if not column_rules:
            return ""
        lines = ["## COLUMN GUIDANCE (per table)\n"]
        for rule in column_rules:
            table = rule.get("table", "")
            lines.append(f"**{table}**:")
            
            ts_cols = rule.get("timestamp_columns", [])
            if ts_cols:
                lines.append(f"  Timestamp columns: {', '.join(ts_cols)}")
            
            key_cols = rule.get("key_columns", [])
            if key_cols:
                lines.append(f"  Key columns: {', '.join(key_cols)}")
            
            filters = rule.get("common_filters", [])
            if filters:
                lines.append(f"  Common filters: {', '.join(filters)}")
            
            forbidden = rule.get("forbidden_columns", [])
            if forbidden:
                lines.append(f"  FORBIDDEN columns (don't exist!): {', '.join(forbidden)}")
            
            notes = rule.get("notes", "")
            if notes:
                lines.append(f"  Note: {notes}")

            lines.append("")

        return "\n".join(lines)

    def _format_config_business_rules(
        self, matched_rules: List[tuple]
    ) -> str:
        """Format matched config business rules for the prompt."""
        if not matched_rules:
            return ""
        lines = ["## BUSINESS RULES (from config — verified constraints)\n"]
        for rule_name, config in matched_rules:
            desc = config.get("description", rule_name)
            lines.append(f"### Rule: {desc}")

            # Required filters
            req_filters = config.get("required_filters", [])
            if req_filters:
                lines.append("  Required WHERE filters:")
                for rf in req_filters:
                    lines.append(f"    - {rf}")

            # Join condition
            join_cond = config.get("join_condition", "")
            if join_cond:
                lines.append(f"  Required JOIN: {join_cond}")

            # Forbidden columns
            forbidden = config.get("forbidden_columns", [])
            if forbidden:
                lines.append(f"  FORBIDDEN columns: {', '.join(forbidden)}")

            # Grouping options
            grouping = config.get("grouping_options", {})
            if grouping:
                lines.append("  Grouping options:")
                for group_name, group_cols in grouping.items():
                    if isinstance(group_cols, list):
                        lines.append(
                            f"    - {group_name}: {', '.join(group_cols)}"
                        )
                    else:
                        lines.append(f"    - {group_name}: {group_cols}")

            # Notes / critical notes
            notes = config.get("notes", "")
            if notes:
                lines.append(f"  IMPORTANT: {notes}")

            critical_notes = config.get("critical_notes", [])
            if critical_notes:
                for cn in critical_notes:
                    lines.append(f"  CRITICAL: {cn}")

            lines.append("")

        return "\n".join(lines)

    # ──────────────────────────────────────────────
    # MAIN PUBLIC API
    # ──────────────────────────────────────────────

    def get_knowledge_for_prompt(
        self,
        question: str,
        matched_tables: List[str],
    ) -> str:
        """
        Build domain knowledge context for the SQL generation prompt.

        Args:
            question: User's natural language question
            matched_tables: Tables selected by the table selector

        Returns:
            Formatted string ready to inject into the system prompt.
            Empty string if no relevant knowledge found.
        """
        question_lower = question.lower()

        # 1. Match relevant knowledge
        table_patterns = self._match_table_usage_patterns(question_lower, matched_tables)
        business_filters = self._match_business_filters(matched_tables, question_lower)
        sql_patterns = self._match_sql_patterns(question_lower, matched_tables)
        formulas = self._match_formulas(question_lower)
        column_rules = self._match_column_rules(matched_tables)
        config_rules = self._match_config_business_rules(question_lower)

        # 2. Format into prompt sections
        sections = []

        tp_text = self._format_table_patterns(table_patterns)
        if tp_text:
            sections.append(tp_text)

        bf_text = self._format_business_filters(business_filters)
        if bf_text:
            sections.append(bf_text)

        sp_text = self._format_sql_patterns(sql_patterns)
        if sp_text:
            sections.append(sp_text)

        fm_text = self._format_formulas(formulas)
        if fm_text:
            sections.append(fm_text)

        cg_text = self._format_column_guidance(column_rules)
        if cg_text:
            sections.append(cg_text)

        br_text = self._format_config_business_rules(config_rules)
        if br_text:
            sections.append(br_text)

        if not sections:
            return ""

        header = (
            "\n" + "=" * 80 + "\n"
            "DOMAIN KNOWLEDGE (from verified production queries)\n"
            "Use this knowledge to guide your SQL generation — these patterns "
            "are battle-tested against real warehouse data.\n"
            + "=" * 80 + "\n"
        )

        return header + "\n".join(sections)

    def get_additional_tables(
        self,
        question: str,
        current_tables: List[str],
    ) -> List[str]:
        """
        Suggest additional tables that should be included based on domain knowledge.
        
        For example, if the query is about "active hours" and only task_master_log
        is selected, this may suggest task_master_log_archive too.

        Args:
            question: User's natural language question
            current_tables: Tables already selected

        Returns:
            List of additional table names to consider adding.
        """
        question_lower = question.lower()
        current_set = set(t.lower() for t in current_tables)
        suggestions: Set[str] = set()

        patterns = self._match_table_usage_patterns(question_lower, current_tables)

        for pattern in patterns:
            # Add archive tables if the pattern requires them
            if pattern.get("requires_archive_union"):
                for archive_table in pattern.get("archive_tables", []):
                    if archive_table.lower() not in current_set:
                        suggestions.add(archive_table)

            # Add join tables if missing
            for join_table in pattern.get("join_tables", []):
                if join_table.lower() not in current_set:
                    suggestions.add(join_table)

            # Add primary tables if missing
            for primary in pattern.get("primary_tables", []):
                if primary.lower() not in current_set:
                    suggestions.add(primary)

        if suggestions:
            logger.info(
                f"📚 KnowledgeLayer suggests additional tables: {suggestions}"
            )

        return list(suggestions)
