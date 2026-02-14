"""
SQL Engine for NEO Warehouse Database — HYBRID OVERRIDE EDITION
Supports deterministic schema scoping via schema_override.
"""

import json
import logging
import os
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import pymysql
from openai import OpenAI

from app.core.config import settings
from app.services.schema_registry import SchemaRegistry
from app.prompts.universal_sql_prompt import build_universal_prompt

logger = logging.getLogger(__name__)

try:
    import sqlglot
except ImportError:
    sqlglot = None


# ─────────────────────────────────────────────
# SQL SAFETY
# ─────────────────────────────────────────────

_DANGEROUS_SQL_RE = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|grant|revoke|replace)\b",
    re.IGNORECASE,
)


def is_read_only_sql(sql: str) -> bool:
    if not sql or not sql.strip():
        return False
    if _DANGEROUS_SQL_RE.search(sql):
        return False
    if sqlglot:
        try:
            parsed = sqlglot.parse_one(sql, read="mysql")
            return parsed.key.upper() in ("SELECT", "WITH")
        except Exception:
            return False
    return sql.strip().lower().startswith(("select", "with"))


# ─────────────────────────────────────────────
# STRICT JSON SCHEMA
# ─────────────────────────────────────────────

def _make_strict(schema: dict) -> dict:
    if not isinstance(schema, dict):
        return schema
    schema = dict(schema)
    if schema.get("type") == "object":
        props = schema.get("properties", {})
        schema["required"] = list(props.keys())
        schema["additionalProperties"] = False
        for k, v in props.items():
            props[k] = _make_strict(v)
        schema["properties"] = props
    if schema.get("type") == "array" and "items" in schema:
        schema["items"] = _make_strict(schema["items"])
    return schema


RESPONSE_SCHEMA = _make_strict({
    "type": "object",
    "properties": {
        "sql": {"type": "string"},
        "tables_used": {"type": "array", "items": {"type": "string"}},
        "columns_used": {"type": "array", "items": {"type": "string"}},
        "primary_keys_used": {"type": "array", "items": {"type": "string"}},
        "assumptions": {"type": "array", "items": {"type": "string"}},
        "warnings": {"type": "array", "items": {"type": "string"}},
        "needs_followup": {"type": "boolean"},
        "followup_questions": {"type": "array", "items": {"type": "string"}},
        "is_read_only": {"type": "boolean"},
        "confidence": {"type": "number"},
    },
})


# ─────────────────────────────────────────────
# MAIN ENGINE
# ─────────────────────────────────────────────

class SQLEngine:

    def __init__(
        self,
        api_key: str,
        model: str,
        schema_csv_path: Optional[str] = None,
        db_config: Optional[Dict[str, Any]] = None,
    ):
        self.client = OpenAI(api_key=api_key)
        self.model = model
        self.db_config = db_config or {}

        csv_path = schema_csv_path or os.getenv("NEO_SCHEMA_CSV_PATH")
        if csv_path:
            self.registry = SchemaRegistry(csv_path)
        else:
            self.registry = SchemaRegistry()

        logger.info(
            f"SQLEngine initialized: model={model}, "
            f"tables={len(self.registry.tables)}"
        )

    # ─────────────────────────────────────────────
    # GENERATE
    # ─────────────────────────────────────────────

    def generate(
        self,
        question: str,
        enable_entity_resolution: bool = True,
        feedback: Optional[str] = None,
        previous_sql: Optional[str] = None,
        schema_override: Optional[Dict[str, List[str]]] = None,
    ) -> Dict[str, Any]:

        # --------------------------------------------------
        # 1. SCHEMA CONTEXT (OVERRIDE OR REGISTRY)
        # --------------------------------------------------

        if schema_override:
            logger.info(f"🔒 Using schema override with {len(schema_override)} tables")

            schema_lines = []
            for table, columns in schema_override.items():
                col_text = ", ".join(columns[:50])  # limit columns
                schema_lines.append(
                    f"TABLE: {table}\nCOLUMNS: {col_text}\n"
                )

            schema_text = "\n".join(schema_lines)

            ctx = {
                "schema_text": schema_text,
                "relationship_text": "",
                "enum_text": "",
                "path_text": "",
                "column_facts": "",
                "domains_matched": [],
                "selected_tables": list(schema_override.keys()),
            }

        else:
            ctx = self.registry.get_schema_context(question)

        logger.info(
            f"📉 Schema scope size: {len(ctx.get('selected_tables', []))} tables"
        )

        # --------------------------------------------------
        # 2. BUILD PROMPT
        # --------------------------------------------------

        instructions = build_universal_prompt(
            schema_context=ctx["schema_text"],
            relationship_text=ctx.get("relationship_text", ""),
            enum_text=ctx.get("enum_text", ""),
            path_text=ctx.get("path_text", ""),
            column_facts=ctx.get("column_facts", ""),
            entity_context="",
        )

        if feedback and previous_sql:
            instructions += (
                f"\n\nPREVIOUS ATTEMPT FAILED:\n"
                f"SQL: {previous_sql}\n"
                f"ERROR: {feedback}\n"
                f"Fix the error and generate a corrected query.\n"
            )

        # --------------------------------------------------
        # 3. CALL LLM (NO DUPLICATE SCHEMA CONTEXT)
        # --------------------------------------------------

        resp = self.client.responses.create(
            model=self.model,
            instructions=instructions,
            input=f"USER QUESTION:\n{question}",
            text={
                "format": {
                    "type": "json_schema",
                    "name": "sql_response",
                    "strict": True,
                    "schema": RESPONSE_SCHEMA,
                }
            },
        )

        result = json.loads(resp.output_text)

        # --------------------------------------------------
        # 4. SAFETY CHECK
        # --------------------------------------------------

        if not is_read_only_sql(result.get("sql", "")):
            raise ValueError("Generated SQL is not read-only")

        result["source"] = "sql_engine"
        result["selected_tables"] = ctx.get("selected_tables", [])

        return result
