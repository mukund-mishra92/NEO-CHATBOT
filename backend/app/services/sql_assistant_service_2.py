import json
import re
import pymysql
from typing import Dict, Any, List, Optional
from difflib import SequenceMatcher

from app.core.config import settings
from app.services.llm_service import LLMService
from app.utils.schema_parser import get_schema_parser


class SQLAssistantService:
    """
    GPT-5.2-level SQL Assistant Service (FULL & COMPATIBLE)
    ------------------------------------------------------
    - Schema-first
    - Plan-based
    - Deterministic SQL compiler
    - Validation + retry loop
    - Data-aware confidence scoring
    - UI / API compatible
    """

    MAX_PLAN_ATTEMPTS = 3

    # ============================================================
    # INIT
    # ============================================================

    def __init__(self):
        self.llm = LLMService()
        self.schema = get_schema_parser()
        self.db_config = {
            "host": settings.DB_HOST,
            "port": settings.DB_PORT,
            "user": settings.DB_USER,
            "password": settings.DB_PASSWORD,
            "database": settings.DB_NAME,
        }

    # ============================================================
    # MAIN ENTRY POINT
    # ============================================================

    def process_query(self, user_query: str) -> Dict[str, Any]:
        """
        Main NL → SQL entry point
        Returns SQL + data + confidence
        """
        last_error = None

        for attempt in range(1, self.MAX_PLAN_ATTEMPTS + 1):
            try:
                plan = self._generate_sql_plan(user_query, last_error)
                resolved_plan = self._resolve_plan(plan)
                sql = self._compile_sql(resolved_plan)
                results = self._execute_sql(sql)

                confidence, issues = self._validate_results(
                    user_query, resolved_plan, results
                )

                if confidence >= 0.75:
                    return {
                        "sql": sql,
                        "data": results,
                        "confidence": confidence,
                        "issues": issues,
                        "attempts": attempt,
                    }

                last_error = "; ".join(issues) if issues else "Low confidence result"

            except Exception as e:
                last_error = str(e)

        return {
            "error": "Unable to generate confident SQL result",
            "last_error": last_error,
        }

    # ============================================================
    # LLM → SQL PLAN (JSON ONLY)
    # ============================================================

    def _generate_sql_plan(self, query: str, feedback: Optional[str]) -> Dict[str, Any]:
        feedback_block = f"\nPREVIOUS ISSUE:\n{feedback}\n" if feedback else ""

        system_prompt = f"""
You are a SQL planner.

ABSOLUTE RULES:
- DO NOT generate SQL
- DO NOT invent tables or columns
- ONLY return valid JSON
- Fix previous mistakes if feedback is provided
- If ambiguous, set "needs_clarification": true

AVAILABLE TABLES:
{", ".join(self.schema.get_table_names())}

PLAN FORMAT:
{{
  "tables": [],
  "select": [],
  "filters": [
    {{"column": "", "op": "=", "value": ""}}
  ],
  "limit": 100,
  "needs_clarification": false
}}

{feedback_block}
"""

        response = self.llm.generate_response(
            messages=[{"role": "user", "content": query}],
            system_prompt=system_prompt,
            temperature=0.1,
            max_tokens=800,
        )

        return json.loads(self._extract_json(response))

    # ============================================================
    # PLAN RESOLUTION (SCHEMA AUTHORITY)
    # ============================================================

    def _resolve_plan(self, plan: Dict[str, Any]) -> Dict[str, Any]:
        if plan.get("needs_clarification"):
            raise ValueError("Ambiguous query – clarification required")

        resolved = {
            "tables": [],
            "select": [],
            "filters": [],
            "limit": int(plan.get("limit", 100)),
        }

        # Tables
        for table in plan.get("tables", []):
            if table not in self.schema.tables:
                raise ValueError(f"Invalid table: {table}")
            resolved["tables"].append(table)

        if not resolved["tables"]:
            raise ValueError("No valid tables resolved")

        # Columns
        for col in plan.get("select", []):
            resolved["select"].append(
                self._resolve_column(col, resolved["tables"])
            )

        # Filters
        for f in plan.get("filters", []):
            col = self._resolve_column(f["column"], resolved["tables"])
            self._validate_value_type(col, f["value"])
            resolved["filters"].append({
                "column": col,
                "op": f["op"],
                "value": f["value"]
            })

        return resolved

    # ============================================================
    # COLUMN RESOLUTION (FUZZY + HARD)
    # ============================================================

    def _resolve_column(self, user_col: str, tables: List[str]) -> str:
        candidates = []
        for table in tables:
            for c in self.schema.tables[table]:
                candidates.append(c["field"])

        # Exact match
        for c in candidates:
            if c.lower() == user_col.lower():
                return c

        # Fuzzy match
        best, score = None, 0.0
        for c in candidates:
            s = SequenceMatcher(None, user_col.lower(), c.lower()).ratio()
            if s > score:
                best, score = c, s

        if score >= 0.75:
            return best

        raise ValueError(f"Unknown column: {user_col}")

    # ============================================================
    # TYPE VALIDATION
    # ============================================================

    def _validate_value_type(self, column: str, value: Any):
        col_meta = None
        for cols in self.schema.tables.values():
            for c in cols:
                if c["field"] == column:
                    col_meta = c
                    break

        if not col_meta:
            raise ValueError(f"Column metadata missing: {column}")

        t = col_meta["type"].upper()
        if "INT" in t and not str(value).isdigit():
            raise ValueError(f"Invalid INT value for {column}: {value}")

    # ============================================================
    # SQL COMPILER (DETERMINISTIC)
    # ============================================================

    def _compile_sql(self, plan: Dict[str, Any]) -> str:
        table = plan["tables"][0]
        select_clause = ", ".join(plan["select"]) if plan["select"] else "*"

        sql = f"SELECT {select_clause} FROM {table}"

        if plan["filters"]:
            conditions = []
            for f in plan["filters"]:
                v = f["value"]
                if isinstance(v, str):
                    v = f"'{v}'"
                conditions.append(f"{f['column']} {f['op']} {v}")
            sql += " WHERE " + " AND ".join(conditions)

        sql += f" LIMIT {plan['limit']}"
        return sql + ";"

    # ============================================================
    # SQL EXECUTION
    # ============================================================

    def _execute_sql(self, sql: str) -> List[Dict[str, Any]]:
        conn = pymysql.connect(**self.db_config)
        try:
            with conn.cursor(pymysql.cursors.DictCursor) as cur:
                cur.execute(sql)
                return cur.fetchall()
        finally:
            conn.close()

    # ============================================================
    # RESULT VALIDATION (DATA-AWARE)
    # ============================================================

    def _validate_results(
        self,
        query: str,
        plan: Dict[str, Any],
        results: List[Dict[str, Any]]
    ) -> (float, List[str]):

        issues = []
        confidence = 0.5

        if not results:
            return 0.3, ["No rows returned"]

        confidence += 0.15

        if len(results) <= 1000:
            confidence += 0.15

        first_row = results[0]
        non_null_ratio = sum(v is not None for v in first_row.values()) / len(first_row)

        if non_null_ratio >= 0.7:
            confidence += 0.15
        else:
            issues.append("High null ratio in result")

        tokens = query.lower().split()
        if any(any(tok in col.lower() for tok in tokens) for col in first_row.keys()):
            confidence += 0.1
        else:
            issues.append("Columns weakly match query intent")

        return min(confidence, 0.95), issues

    # ============================================================
    # SCHEMA INTROSPECTION (UI / API)
    # ============================================================

    def get_schema_info(self) -> Dict[str, Any]:
        try:
            tables = self.schema.get_table_names()
            table_details = {
                table: [
                    {
                        "column": c["field"],
                        "type": c.get("type"),
                        "key": c.get("key"),
                    }
                    for c in self.schema.tables.get(table, [])
                ]
                for table in tables
            }

            return {
                "database": settings.DB_NAME,
                "total_tables": len(tables),
                "tables": tables,
                "table_details": table_details,
            }

        except Exception as e:
            return {"error": f"Error getting schema tables: {str(e)}"}

    # ============================================================
    # HEALTH CHECK (SERVER)
    # ============================================================

    def health_check(self) -> Dict[str, Any]:
        try:
            conn = pymysql.connect(**self.db_config, connect_timeout=3)
            conn.close()
            return {
                "status": "ok",
                "database": "reachable",
                "tables_loaded": len(self.schema.get_table_names()),
            }
        except Exception as e:
            return {
                "status": "error",
                "database": "unreachable",
                "error": str(e),
            }

    # ============================================================
    # CAPABILITIES (UI HINTS)
    # ============================================================

    def get_capabilities(self) -> Dict[str, Any]:
        return {
            "supports_plan_based_sql": True,
            "schema_first": True,
            "fuzzy_column_matching": True,
            "validation_loop": True,
            "max_plan_attempts": self.MAX_PLAN_ATTEMPTS,
            "returns_sql_and_data": True,
        }

    # ============================================================
    # UTIL
    # ============================================================

    def _extract_json(self, text: str) -> str:
        match = re.search(r"\{.*\}", text, re.S)
        if not match:
            raise ValueError("No JSON found in LLM response")
        return match.group(0)
