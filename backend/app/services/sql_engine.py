"""
SQL Engine for NEO Warehouse Database — UNIVERSAL EDITION
============================================================
Replaces nl_to_sql_generator.py with a clean, schema-registry-driven engine.

Architecture:
    SchemaRegistry (table selection, joins, enums, column facts)
        ↓
    Universal SQL Prompt (teaches LLM how to query ANY pattern)
        ↓
    OpenAI GPT structured output (JSON with sql, confidence, etc.)
        ↓
    Safety check (read-only only)

Keeps:
    ✅ Entity resolution (BOT-0008, STATION_ID, etc.) — DB-driven, always accurate
    ✅ Structured JSON output schema
    ✅ Read-only SQL safety check
    ✅ Same public API: generate(question) → Dict

Replaces:
    ❌ TF-IDF table selection → SchemaRegistry domain + keyword matching
    ❌ Business rules from config → SchemaRegistry column facts + enums
    ❌ Hardcoded prompt → Universal prompt + dynamic schema context
    ❌ build_enhanced_prompt → build_universal_prompt

Author: NEO Chatbot Team
Date: 2026-02-08
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


# ─────────────────────────────────────────────────────────────────────────────
# SQL Safety
# ─────────────────────────────────────────────────────────────────────────────

_DANGEROUS_SQL_RE = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|grant|revoke|replace)\b",
    re.IGNORECASE,
)


def is_read_only_sql(sql: str) -> bool:
    """Verify SQL is read-only (SELECT/WITH only)."""
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


# ─────────────────────────────────────────────────────────────────────────────
# OpenAI Strict Schema Helper
# ─────────────────────────────────────────────────────────────────────────────

def _make_strict(schema: dict) -> dict:
    """Make schema OpenAI-strict (required all keys, no additionalProperties)."""
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


# ─────────────────────────────────────────────────────────────────────────────
# DB Connection Helper
# ─────────────────────────────────────────────────────────────────────────────

def _connect(db_config: Dict[str, Any], attempts: int = 3):
    """Stable DB connection with retry."""
    last_error = None
    for i in range(attempts):
        try:
            port = db_config.get("port", 3306)
            if isinstance(port, str):
                port = int(port)
            return pymysql.connect(
                host=db_config.get("host", "localhost"),
                port=port,
                user=db_config.get("user", "root"),
                password=db_config.get("password", ""),
                database=db_config.get("database", "neo"),
                charset="utf8mb4",
                connect_timeout=15,
                read_timeout=30,
                write_timeout=30,
                cursorclass=pymysql.cursors.DictCursor,
                autocommit=True,
            )
        except Exception as e:
            last_error = e
            if i < attempts - 1:
                time.sleep(0.5 * (i + 1))
    raise last_error


def _table_exists(conn, db_name: str, table_name: str) -> bool:
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM information_schema.tables "
                "WHERE table_schema = %s AND table_name = %s LIMIT 1",
                (db_name, table_name),
            )
            return bool(cur.fetchone())
    except Exception:
        return False


def _fetch(conn, query: str, params: tuple, max_rows: int = 10) -> List[dict]:
    try:
        with conn.cursor() as cur:
            cur.execute(query, params)
            return cur.fetchall()[:max_rows]
    except Exception:
        return []


# ─────────────────────────────────────────────────────────────────────────────
# Entity Resolution (kept from nl_to_sql_generator.py — DB-driven, accurate)
# ─────────────────────────────────────────────────────────────────────────────

_BOT_CANON_RE = re.compile(r"\bBOT-\d{4}\b", re.IGNORECASE)
_BOT_NUM_RE = re.compile(r"\b(?:bot|b)\s*[-_ ]?\s*(\d{1,4})\b", re.IGNORECASE)
_STATION_NUM_RE = re.compile(r"\b(?:station|stn|st)\s*[-_ ]?\s*(\d{1,4})\b", re.IGNORECASE)
_WAVE_NUM_RE = re.compile(r"\b(?:wave|wv)\s*[-_ ]?\s*(\d{1,6})\b", re.IGNORECASE)
_BIN_NUM_RE = re.compile(r"\b(?:bin|bn)\s*[-_ ]?\s*(\d{1,10})\b", re.IGNORECASE)
_BARCODE_RE = re.compile(r"\b(?:barcode)\s*[:#-]?\s*([A-Za-z0-9\-_/.]+)\b", re.IGNORECASE)


def _resolve_bot(conn, question: str) -> Tuple[Optional[str], List[str]]:
    warnings: List[str] = []
    m = _BOT_CANON_RE.search(question)
    if m:
        bot_id = m.group(0).upper()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT BOT_ID FROM bot_master WHERE BOT_ID=%s LIMIT 1", (bot_id,))
                row = cur.fetchone()
            return (row["BOT_ID"] if row else bot_id), warnings
        except Exception:
            return bot_id, warnings

    m = _BOT_NUM_RE.search(question)
    if not m:
        return None, warnings
    n = int(m.group(1))
    candidate = f"BOT-{n:04d}"
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT BOT_ID FROM bot_master WHERE BOT_ID=%s LIMIT 1", (candidate,))
            row = cur.fetchone()
        if row:
            return row["BOT_ID"], warnings
        warnings.append(f"BOT {n} not found as {candidate}")
        return candidate, warnings
    except Exception as e:
        warnings.append(f"Bot resolution failed: {e}")
        return candidate, warnings


def _resolve_station(conn, db_name: str, question: str) -> Tuple[Optional[str], List[dict], List[str]]:
    warnings: List[str] = []
    if not _table_exists(conn, db_name, "hw_station_master"):
        return None, [], warnings
    m = _STATION_NUM_RE.search(question)
    if not m:
        return None, [], warnings
    n = int(m.group(1))
    q = """
    SELECT STATION_ID, STATION_ALIAS_NAME
    FROM hw_station_master
    WHERE (
        NULLIF(REGEXP_REPLACE(STATION_ID, '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(STATION_ID, '[^0-9]', '') AS UNSIGNED) = %s
    ) OR (
        NULLIF(REGEXP_REPLACE(STATION_ALIAS_NAME, '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(STATION_ALIAS_NAME, '[^0-9]', '') AS UNSIGNED) = %s
    ) LIMIT 10
    """
    cands = _fetch(conn, q, (n, n))
    unique = sorted({c["STATION_ID"] for c in cands if c.get("STATION_ID")})
    if len(unique) == 1:
        return unique[0], [], warnings
    if len(unique) > 1:
        warnings.append(f"Station {n} ambiguous: {unique}")
        return None, cands, warnings
    warnings.append(f"Station {n} not found")
    return None, [], warnings


def _resolve_wave(conn, db_name: str, question: str) -> Tuple[Optional[str], List[dict], List[str]]:
    warnings: List[str] = []
    m = _WAVE_NUM_RE.search(question)
    if not m:
        return None, [], warnings
    n = int(m.group(1))
    tables = [t for t in ["wave_master", "dashboard_log_wave_process"]
              if _table_exists(conn, db_name, t)]
    if not tables:
        return None, [], warnings
    all_cands: List[dict] = []
    for t in tables:
        q = f"""
        SELECT DISTINCT WAVE_ID FROM {t}
        WHERE NULLIF(REGEXP_REPLACE(WAVE_ID, '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(WAVE_ID, '[^0-9]', '') AS UNSIGNED) = %s
        LIMIT 10
        """
        for c in _fetch(conn, q, (n,)):
            all_cands.append({"WAVE_ID": c.get("WAVE_ID"), "source": t})
    unique = sorted({c["WAVE_ID"] for c in all_cands if c.get("WAVE_ID")})
    if len(unique) == 1:
        return unique[0], [], warnings
    if len(unique) > 1:
        warnings.append(f"Wave {n} ambiguous")
        return None, all_cands, warnings
    warnings.append(f"Wave {n} not found")
    return None, [], warnings


def _resolve_bin(conn, db_name: str, question: str) -> Tuple[Optional[str], Optional[str], List[dict], List[str]]:
    warnings: List[str] = []
    if not _table_exists(conn, db_name, "bin_info_master"):
        return None, None, [], warnings

    m = _BARCODE_RE.search(question)
    if m:
        token = m.group(1)
        cands = _fetch(conn,
            "SELECT BIN_ID, BIN_BARCODE FROM bin_info_master WHERE BIN_BARCODE=%s OR BIN_ID=%s LIMIT 10",
            (token, token))
        if len(cands) == 1:
            return cands[0].get("BIN_ID"), cands[0].get("BIN_BARCODE"), [], warnings
        if len(cands) > 1:
            warnings.append("Barcode ambiguous")
            return None, None, cands, warnings
        warnings.append("Barcode not found")
        return None, None, [], warnings

    m = _BIN_NUM_RE.search(question)
    if not m:
        return None, None, [], warnings
    n = int(m.group(1))
    q = """
    SELECT BIN_ID, BIN_BARCODE FROM bin_info_master
    WHERE (
        NULLIF(REGEXP_REPLACE(CAST(BIN_ID AS CHAR), '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(CAST(BIN_ID AS CHAR), '[^0-9]', '') AS UNSIGNED) = %s
    ) OR (
        NULLIF(REGEXP_REPLACE(CAST(BIN_BARCODE AS CHAR), '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(CAST(BIN_BARCODE AS CHAR), '[^0-9]', '') AS UNSIGNED) = %s
    ) LIMIT 10
    """
    cands = _fetch(conn, q, (n, n))
    if len(cands) == 1:
        return cands[0].get("BIN_ID"), cands[0].get("BIN_BARCODE"), [], warnings
    if len(cands) > 1:
        warnings.append(f"Bin {n} ambiguous")
        return None, None, cands, warnings
    warnings.append(f"Bin {n} not found")
    return None, None, [], warnings


def resolve_entities(question: str, db_config: Dict[str, Any]) -> Dict[str, Any]:
    """Orchestrate entity resolution from the database."""
    resolved: Dict[str, Any] = {"entities": {}, "candidates": {}, "warnings": []}
    try:
        conn = _connect(db_config, attempts=2)
    except Exception as e:
        resolved["warnings"].append(f"DB connection failed: {e}")
        return resolved

    try:
        db_name = db_config.get("database", "neo")

        bot_id, w = _resolve_bot(conn, question)
        if bot_id:
            resolved["entities"]["BOT_ID"] = bot_id
        resolved["warnings"].extend(w)

        station_id, s_cands, w = _resolve_station(conn, db_name, question)
        if station_id:
            resolved["entities"]["STATION_ID"] = station_id
        elif s_cands:
            resolved["candidates"]["STATION_ID"] = s_cands
        resolved["warnings"].extend(w)

        wave_id, w_cands, w = _resolve_wave(conn, db_name, question)
        if wave_id:
            resolved["entities"]["WAVE_ID"] = wave_id
        elif w_cands:
            resolved["candidates"]["WAVE_ID"] = w_cands
        resolved["warnings"].extend(w)

        bin_id, barcode, b_cands, w = _resolve_bin(conn, db_name, question)
        if bin_id:
            resolved["entities"]["BIN_ID"] = bin_id
        if barcode:
            resolved["entities"]["BIN_BARCODE"] = barcode
        elif b_cands:
            resolved["candidates"]["BIN"] = b_cands
        resolved["warnings"].extend(w)
    except Exception as e:
        resolved["warnings"].append(f"Entity resolution error: {e}")
    finally:
        try:
            conn.close()
        except Exception:
            pass
    return resolved


def _inject_entities(question: str, resolved: Dict[str, Any]) -> str:
    """Append resolved entities to the question for the LLM."""
    parts = [question]
    entities = resolved.get("entities", {})
    cands = resolved.get("candidates", {})

    if entities:
        parts.append("\n**RESOLVED_ENTITIES** (use EXACT values in SQL):")
        for k, v in entities.items():
            parts.append(f"- {k} = '{v}'")
    if cands:
        parts.append("\n**RESOLVED_CANDIDATES** (ambiguous; ask follow-up):")
        for k, v in cands.items():
            parts.append(f"- {k}: {json.dumps(v[:3], ensure_ascii=False)}")
    return "\n".join(parts)


# ─────────────────────────────────────────────────────────────────────────────
# SQLEngine — Main Class
# ─────────────────────────────────────────────────────────────────────────────

class SQLEngine:
    """
    Universal SQL generation engine powered by SchemaRegistry.

    Usage::

        engine = SQLEngine(api_key="sk-...", model="gpt-5.2", db_config={...})
        result = engine.generate("how many bins were presented at station 5 today?")
        print(result["sql"])

    Public API is identical to NLToSQLGenerator.generate() so the
    integrated service can swap with minimal changes.
    """

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

        # Initialize schema registry
        csv_path = schema_csv_path or os.getenv("NEO_SCHEMA_CSV_PATH")
        if csv_path:
            self.registry = SchemaRegistry(csv_path)
        else:
            self.registry = SchemaRegistry()  # auto-discovers path

        logger.info(
            f"SQLEngine initialized: model={model}, "
            f"tables={len(self.registry.tables)}"
        )

    def generate(
        self,
        question: str,
        enable_entity_resolution: bool = True,
        feedback: Optional[str] = None,
        previous_sql: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Generate SQL from natural language question.

        Args:
            question: User's natural language question
            enable_entity_resolution: Resolve BOT_ID, STATION_ID, etc. from DB
            feedback: Error feedback from a previous attempt (for retry)
            previous_sql: The SQL from the previous failed attempt

        Returns:
            Dict with sql, confidence, tables_used, etc.
        """
        # 1. Entity resolution
        resolved = {"entities": {}, "candidates": {}, "warnings": []}
        if enable_entity_resolution and self.db_config:
            try:
                resolved = resolve_entities(question, self.db_config)
            except Exception as e:
                resolved["warnings"].append(f"Entity resolution failed: {e}")

        # 2. Enrich question with resolved entities
        question_for_llm = question
        entity_context = ""
        if resolved.get("entities") or resolved.get("candidates"):
            question_for_llm = _inject_entities(question, resolved)
            # Build entity context for prompt
            entity_parts = []
            for k, v in resolved.get("entities", {}).items():
                entity_parts.append(f"  {k} = '{v}'")
            entity_context = "\n".join(entity_parts)

        # 3. Get schema context from registry
        ctx = self.registry.get_schema_context(question_for_llm)

        # 4. Build universal prompt
        instructions = build_universal_prompt(
            schema_context=ctx["schema_text"],
            relationship_text=ctx["relationship_text"],
            enum_text=ctx["enum_text"],
            path_text=ctx["path_text"],
            column_facts=ctx["column_facts"],
            entity_context=entity_context,
        )

        # 5. Add retry feedback if this is a retry attempt
        if feedback and previous_sql:
            instructions += (
                f"\n\nPREVIOUS ATTEMPT FAILED:\n"
                f"SQL: {previous_sql}\n"
                f"ERROR: {feedback}\n"
                f"Fix the error and generate a corrected query.\n"
            )

        # 6. Call LLM
        resp = self.client.responses.create(
            model=self.model,
            instructions=instructions,
            input=(
                f"USER QUESTION:\n{question_for_llm}\n\n"
                f"SCHEMA CONTEXT:\n{ctx['schema_text']}"
            ),
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

        # 7. Safety check
        if not is_read_only_sql(result.get("sql", "")):
            raise ValueError("Generated SQL is not read-only")

        # 8. Add metadata
        result["source"] = "sql_engine"
        result["domains_matched"] = ctx.get("domains_matched", [])
        result["selected_tables"] = ctx.get("selected_tables", [])
        if resolved.get("entities"):
            result["resolved_entities"] = resolved["entities"]
        if resolved.get("warnings"):
            result.setdefault("warnings", []).extend(resolved["warnings"])

        return result

    def get_ranked_tables_for_query(
        self, question: str, top_k: int = 12
    ) -> List[Dict[str, Any]]:
        """
        Get ranked tables for a query (for UI/debugging).
        Uses SchemaRegistry domain matching instead of TF-IDF.
        """
        ctx = self.registry.get_schema_context(question, max_tables=top_k)
        results = []
        for tname in ctx["selected_tables"]:
            info = self.registry.tables.get(tname, {})
            results.append({
                "table_name": tname,
                "description": info.get("description", ""),
                "columns": info.get("columns_raw", ""),
                "primary_key": info.get("pk", ""),
                "category": info.get("category", "general_table"),
            })
        return results
