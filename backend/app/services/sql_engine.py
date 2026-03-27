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
        provider: str = "openai",
        schema_csv_path: Optional[str] = None,
        db_config: Optional[Dict[str, Any]] = None,
    ):
        self.provider = provider.lower().strip()
        self.openai_client = None
        self.groq_client = None

        if self.provider == "groq":
            if not api_key:
                raise ValueError("GROQ_API_KEY is not set but GROQ provider is selected in AI Config!")
            try:
                from groq import Groq
                self.groq_client = Groq(api_key=api_key)
                logger.info(f"✅ Successfully initialized GROQ client with model: {model}")
            except ImportError as exc:
                raise ValueError(f"❌ GROQ library not installed. Please install groq package: {exc}")
            except Exception as exc:
                raise ValueError(f"❌ GROQ initialization failed: {exc}. Check GROQ_API_KEY and network connection.")

        if self.provider == "openai":
            if not api_key:
                raise ValueError("OPENAI_API_KEY is not set but OPENAI provider is selected!")
            self.openai_client = OpenAI(api_key=api_key)
            logger.info(f"✅ Successfully initialized OpenAI client with model: {model}")

        self.model = model
        self.db_config = db_config or {}

        csv_path = schema_csv_path or os.getenv("NEO_SCHEMA_CSV_PATH")
        if csv_path:
            self.registry = SchemaRegistry(csv_path)
        else:
            self.registry = SchemaRegistry()

        logger.info(
            "SQLEngine initialized: provider=%s, model=%s, tables=%s",
            self.provider,
            model,
            len(self.registry.tables),
        )

    # ─────────────────────────────────────────────
    # GENERATE
    # ─────────────────────────────────────────────

    # def generate(
    #     self,
    #     question: str,
    #     enable_entity_resolution: bool = True,
    #     feedback: Optional[str] = None,
    #     previous_sql: Optional[str] = None,
    #     schema_override: Optional[Dict[str, List[str]]] = None,
    # ) -> Dict[str, Any]:

    def generate(
        self,
        question: str,
        enable_entity_resolution: bool = True,
        feedback: Optional[str] = None,
        previous_sql: Optional[str] = None,
        schema_override: Optional[Dict[str, List[str]]] = None,
        entity_context: Optional[str] = None,
        conversation_history: Optional[List[Dict[str, str]]] = None,
    ) -> Dict[str, Any]:

        # --------------------------------------------------
        # 1. SCHEMA CONTEXT (OVERRIDE OR REGISTRY)
        # --------------------------------------------------

        if schema_override:
            logger.info(f"🔒 Using schema override with {len(schema_override)} tables")

            schema_lines = []
            # for table, columns in schema_override.items():
            #     col_text = ", ".join(columns[:50])  # limit columns
            #     schema_lines.append(
            #         f"TABLE: {table}\nCOLUMNS: {col_text}\n"
            #     )

            for table, table_info in schema_override.items():

                # Handle backward compatibility
                if isinstance(table_info, list):
                    columns = table_info
                    description = ""
                    business_attributes = []
                    joins = []
                    analytics = []
                    self_sufficient = []
                    not_needed = []
                else:
                    columns = table_info.get("columns", [])
                    description = table_info.get("description", "")
                    business_attributes = table_info.get("key_business_attributes", [])
                    joins = table_info.get("frequently_joined_with", [])
                    analytics = table_info.get("supports_analytics", [])
                    self_sufficient = table_info.get("self_sufficient_for", [])
                    not_needed = table_info.get("not_needed_for", [])

                col_text = ", ".join(columns[:50])

                table_block = f"TABLE: {table}\n"

                if description:
                    table_block += f"DESCRIPTION: {description}\n"

                if business_attributes:
                    table_block += (
                        "KEY BUSINESS ATTRIBUTES: "
                        + "; ".join(business_attributes[:5])
                        + "\n"
                    )

                if joins:
                    table_block += (
                        "COMMON JOINS: "
                        + ", ".join(joins[:5])
                        + "\n"
                    )

                if analytics:
                    table_block += (
                        "ANALYTICS USE CASES: "
                        + "; ".join(analytics[:5])
                        + "\n"
                    )

                if self_sufficient:
                    table_block += (
                        "SELF-SUFFICIENT FOR (no JOIN needed): "
                        + "; ".join(self_sufficient[:5])
                        + "\n"
                    )

                if not_needed:
                    table_block += (
                        "⚠️ NOT NEEDED FOR: "
                        + "; ".join(not_needed[:5])
                        + "\n"
                    )

                table_block += f"COLUMNS: {col_text}\n"

                schema_lines.append(table_block)


            schema_text = "\n".join(schema_lines)

            # ctx = {
            #     "schema_text": schema_text,
            #     "relationship_text": "",
            #     "enum_text": "",
            #     "path_text": "",
            #     "column_facts": "",
            #     "domains_matched": [],
            #     "selected_tables": list(schema_override.keys()),
            # }

            # Preserve relationship intelligence from registry
            base_ctx = self.registry.get_schema_context(question)

            ctx = {
                "schema_text": schema_text,
                "relationship_text": base_ctx.get("relationship_text", ""),
                "enum_text": base_ctx.get("enum_text", ""),
                "path_text": base_ctx.get("path_text", ""),
                "column_facts": base_ctx.get("column_facts", ""),
                "domains_matched": base_ctx.get("domains_matched", []),
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

        # instructions = build_universal_prompt(
        #     schema_context=ctx["schema_text"],
        #     relationship_text=ctx.get("relationship_text", ""),
        #     enum_text=ctx.get("enum_text", ""),
        #     path_text=ctx.get("path_text", ""),
        #     column_facts=ctx.get("column_facts", ""),
        #     entity_context="",
        # )
        instructions = build_universal_prompt(
            schema_context=ctx["schema_text"],
            relationship_text=ctx.get("relationship_text", ""),
            enum_text=ctx.get("enum_text", ""),
            path_text=ctx.get("path_text", ""),
            column_facts=ctx.get("column_facts", ""),
            entity_context=entity_context or "",
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

        # Build conversation context for multi-turn support
        conv_context = ""
        if conversation_history and len(conversation_history) > 1:
            # Take recent history (last 10 messages, excluding the current question)
            recent = conversation_history[:-1][-10:]
            conv_parts = []
            for msg in recent:
                role = msg.get("role", "")
                content = msg.get("content", "").strip()
                if not content:
                    continue
                if role == "user":
                    # Summarize to keep token usage low
                    conv_parts.append(f"User asked: {content[:200]}")
                elif role == "assistant":
                    # Extract just the SQL and key info, skip full markdown tables
                    lines = content.split("\n")
                    summary_lines = []
                    for line in lines:
                        if line.startswith("```sql"):
                            summary_lines.append(line)
                        elif line.startswith("```") and summary_lines:
                            summary_lines.append(line)
                            break
                        elif summary_lines:
                            summary_lines.append(line)
                        elif "Rows Returned:" in line:
                            summary_lines.append(line)
                    if summary_lines:
                        conv_parts.append(f"Assistant responded with: {chr(10).join(summary_lines)}")
                    else:
                        conv_parts.append(f"Assistant responded: {content[:150]}")

            if conv_parts:
                conv_context = (
                    "\n\nCONVERSATION HISTORY (use this to resolve references like "
                    "'it', 'that', 'the same', 'its', 'those', etc.):\n"
                    + "\n".join(conv_parts)
                    + "\n\nIMPORTANT: If the user's current question contains pronouns or "
                    "references (it, its, that, those, the same, etc.), resolve them using "
                    "the conversation history above. For example, if user previously asked "
                    "about 'bot 7' and now asks 'tell me its position', interpret it as "
                    "'tell me the position of bot 7'.\n"
                )

        if self.provider == "groq" and self.groq_client:
            groq_prompt = (
                f"{instructions}"
                f"{conv_context}\n\n"
                "Return ONLY valid JSON following this schema keys exactly: "
                "sql, tables_used, columns_used, primary_keys_used, assumptions, warnings, "
                "needs_followup, followup_questions, is_read_only, confidence.\n"
                f"USER QUESTION:\n{question}"
            )
            groq_resp = self.groq_client.chat.completions.create(
                model=self.model,
                temperature=0,
                messages=[{"role": "user", "content": groq_prompt}],
            )
            content = (groq_resp.choices[0].message.content or "").strip()
            if content.startswith("```"):
                content = content.strip("`")
                content = content.replace("json", "", 1).strip()
            if not content:
                raise ValueError("Empty model response")
            try:
                result = json.loads(content)
            except json.JSONDecodeError as e:
                raise ValueError(f"Invalid JSON response: {e}\\nRaw response: {content}")
        else:
            openai_input = f"{conv_context}\nUSER QUESTION:\n{question}" if conv_context else f"USER QUESTION:\n{question}"
            resp = self.openai_client.responses.create(
                model=self.model,
                instructions=instructions,
                input=openai_input,
                temperature=0,
                timeout=60,
                text={
                    "format": {
                        "type": "json_schema",
                        "name": "sql_response",
                        "strict": True,
                        "schema": RESPONSE_SCHEMA,
                    }
                },
            )

            if not resp.output_text:
                raise ValueError("Empty model response")
            try:
                result = json.loads(resp.output_text)
            except json.JSONDecodeError as e:
                raise ValueError(f"Invalid JSON response: {e}\nRaw response: {resp.output_text}")

        # --------------------------------------------------
        # 4. SAFETY CHECK
        # --------------------------------------------------

        if not is_read_only_sql(result.get("sql", "")):
            raise ValueError("Generated SQL is not read-only")

        result["source"] = "sql_engine"
        result["selected_tables"] = ctx.get("selected_tables", [])

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
