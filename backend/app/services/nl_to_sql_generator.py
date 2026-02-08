# app/services/nl_to_sql_generator.py

import os
import json
import re
import time
import pandas as pd
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from openai import OpenAI
import pymysql

from app.core.config import settings

try:
    import sqlglot
except ImportError:
    sqlglot = None


# ----------------------------
# SQL safety
# ----------------------------
DANGEROUS_SQL_RE = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|grant|revoke|replace)\b",
    re.IGNORECASE,
)

def is_read_only_sql(sql: str) -> bool:
    if not sql or not sql.strip():
        return False
    if DANGEROUS_SQL_RE.search(sql):
        return False
    if sqlglot:
        try:
            parsed = sqlglot.parse_one(sql, read="mysql")
            return parsed.key.upper() in ("SELECT", "WITH")
        except Exception:
            return False
    return sql.strip().lower().startswith(("select", "with"))


# ----------------------------
# Strict schema helper
# ----------------------------
def make_openai_strict(schema: dict) -> dict:
    if not isinstance(schema, dict):
        return schema

    schema = dict(schema)
    if schema.get("type") == "object":
        props = schema.get("properties", {})
        schema["required"] = list(props.keys())
        schema["additionalProperties"] = False
        for k, v in props.items():
            props[k] = make_openai_strict(v)
        schema["properties"] = props

    if schema.get("type") == "array" and "items" in schema:
        schema["items"] = make_openai_strict(schema["items"])

    return schema


# ----------------------------
# Response schema
# ----------------------------
BASE_RESPONSE_SCHEMA = {
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
}

STRICT_RESPONSE_SCHEMA = make_openai_strict(BASE_RESPONSE_SCHEMA)


# ----------------------------
# CSV-based schema RAG
# ----------------------------
def load_table_summary(csv_path: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path)
    required = [
        "Table_name",
        "Table_description",
        "Table_columns(Data type)",
        "Primary_key",
    ]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"Schema CSV missing columns: {missing}")
    return df.fillna("")


def build_retriever(df: pd.DataFrame):
    """Build TF-IDF retriever including table category information"""
    # Include category in the document if available
    if 'Table_category' in df.columns:
        docs = (
            df["Table_name"] + " | " +
            df["Table_description"] + " | " +
            df["Table_columns(Data type)"] + " | PK: " +
            df["Primary_key"] + " | Category: " +
            df["Table_category"]
        ).tolist()
    else:
        docs = (
            df["Table_name"] + " | " +
            df["Table_description"] + " | " +
            df["Table_columns(Data type)"] + " | PK: " +
            df["Primary_key"]
        ).tolist()

    vec = TfidfVectorizer(ngram_range=(1, 2), min_df=1)
    X = vec.fit_transform(docs)
    return vec, X


def pick_relevant_tables(
    question: str,
    df: pd.DataFrame,
    vec,
    X,
    top_k: int = 8,
    validation_rules: Optional[Dict] = None,
    custom_priorities: Optional[Dict[str, float]] = None
) -> pd.DataFrame:
    """Pick relevant tables with priority-aware scoring and validation rules
    
    Applies table category priorities to improve selection:
    - Master tables (bot_master, station_master): 2.0x boost for current state queries
    - Telemetry/log tables: 0.3x penalty for business queries
    - Entity-specific filtering (bot queries → prefer bot_* tables)
    - Validation rules: Apply manual corrections from UI
    
    Args:
        question: User's natural language query
        df: DataFrame with table information
        vec: TF-IDF vectorizer
        X: TF-IDF matrix
        top_k: Number of tables to return
        validation_rules: Dict with correct/incorrect tables per query
        custom_priorities: Custom category priority multipliers
    """
    question_lower = question.lower().strip()
    
    # Step 0: Check validation rules first (manual overrides)
    if validation_rules and question_lower in validation_rules:
        rules = validation_rules[question_lower]
        correct_tables = rules.get('correct_tables', [])
        incorrect_tables = rules.get('incorrect_tables', [])
        
        # If we have validated correct tables, boost them heavily
        if correct_tables:
            # Start with TF-IDF but apply strong manual boosts
            qv = vec.transform([question])
            sims = cosine_similarity(qv, X).flatten()
            
            for idx in range(len(df)):
                table_name = df.iloc[idx]['Table_name']
                if table_name in correct_tables:
                    sims[idx] *= 10.0  # Massive boost for validated correct tables
                elif table_name in incorrect_tables:
                    sims[idx] *= 0.01  # Near-zero for validated incorrect tables
            
            # Return boosted results
            idxs = sims.argsort()[::-1][:top_k]
            picked = df.iloc[idxs].copy()
            picked["score"] = sims[idxs]
            return picked
    
    # Step 1: Standard TF-IDF similarity
    qv = vec.transform([question])
    sims = cosine_similarity(qv, X).flatten()
    
    # Step 2: Detect entity type and query intent
    entity_type = None
    is_current_state_query = any(word in question_lower for word in ['current', 'latest', 'now', 'status', 'position', 'state'])
    is_historical_query = any(word in question_lower for word in ['history', 'log', 'past', 'archive', 'trend', 'over time'])
    
    if 'bot' in question_lower:
        entity_type = 'bot'
    elif 'station' in question_lower:
        entity_type = 'station'
    elif 'wave' in question_lower:
        entity_type = 'wave'
    elif 'bin' in question_lower or 'barcode' in question_lower:
        entity_type = 'bin'
    
    # Step 3: Apply priority boosts based on table category
    if 'Table_category' in df.columns:
        # Use custom priorities if provided, otherwise defaults
        if custom_priorities:
            category_priorities = custom_priorities.copy()
        else:
            category_priorities = {
                'bot_master': 2.5,
                'station_master': 2.5,
                'wave_master': 2.0,
                'bin_master': 2.0,
                'order_master': 2.0,
                'config_master': 1.5,
                'transaction_table': 1.2,
                'telemetry_table': 0.3,  # Low priority for business queries
                'log_table': 0.5,         # Low priority unless historical query
                'general_table': 1.0
            }
        
        # Adjust priorities based on query intent
        if is_historical_query:
            # Historical queries should prefer log tables
            category_priorities['log_table'] = 2.0
            category_priorities['telemetry_table'] = 1.5
            category_priorities['bot_master'] = 0.8  # Master has current, not historical
        
        if is_current_state_query:
            # Current state queries strongly prefer master tables
            category_priorities['bot_master'] = 3.0
            category_priorities['station_master'] = 3.0
            category_priorities['telemetry_table'] = 0.2
            category_priorities['log_table'] = 0.2
        
        # Apply category-based boosts
        for idx in range(len(df)):
            category = df.iloc[idx].get('Table_category', 'general_table')
            multiplier = category_priorities.get(category, 1.0)
            sims[idx] *= multiplier
    
    # Step 4: Apply entity-specific filtering
    if entity_type:
        entity_boost = 1.5
        for idx in range(len(df)):
            table_name_lower = df.iloc[idx]['Table_name'].lower()
            # Boost tables matching entity type
            if entity_type in table_name_lower:
                sims[idx] *= entity_boost
    
    # Step 5: Select top_k tables
    idxs = sims.argsort()[::-1][:top_k]
    picked = df.iloc[idxs].copy()
    picked["score"] = sims[idxs]
    
    return picked


def build_schema_context(picked_df: pd.DataFrame) -> str:
    blocks = []
    for _, r in picked_df.iterrows():
        blocks.append(
            f"TABLE: {r['Table_name']}\n"
            f"DESCRIPTION: {r['Table_description']}\n"
            f"COLUMNS: {r['Table_columns(Data type)']}\n"
            f"PRIMARY KEY: {r['Primary_key']}\n"
        )
    return "\n---\n".join(blocks)


# ----------------------------
# DB Connection Helper
# ----------------------------
def connect_neo(db_config: Dict[str, Any], attempts: int = 3):
    """Stable DB connection with retry"""
    last_error = None
    for i in range(attempts):
        try:
            # Ensure port is int
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
                connect_timeout=15,  # Increased timeout for remote DB
                read_timeout=30,
                write_timeout=30,
                cursorclass=pymysql.cursors.DictCursor,
                autocommit=True,
            )
        except Exception as e:
            last_error = e
            if i < attempts - 1:
                time.sleep(0.5 * (i + 1))  # backoff
    raise last_error


def table_exists(conn, db_name: str, table_name: str) -> bool:
    """Check if table exists in database"""
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM information_schema.tables WHERE table_schema = %s AND table_name = %s LIMIT 1",
                (db_name, table_name)
            )
            return bool(cur.fetchone())
    except Exception:
        return False


def fetch_candidates(conn, query: str, params: tuple, max_rows: int = 10) -> List[dict]:
    """Execute query and return limited results"""
    try:
        with conn.cursor() as cur:
            cur.execute(query, params)
            rows = cur.fetchall()
        return rows[:max_rows]
    except Exception:
        return []


# ----------------------------
# Entity Resolution (from main 1.py)
# ----------------------------
BOT_CANON_RE = re.compile(r"\bBOT-\d{4}\b", re.IGNORECASE)
BOT_NUM_RE = re.compile(r"\b(?:bot|b)\s*[-_ ]?\s*(\d{1,4})\b", re.IGNORECASE)

def resolve_bot(conn, question: str) -> Tuple[Optional[str], List[str]]:
    """Resolve bot ID from question (e.g., 'bot 8' → 'BOT-0008')"""
    warnings = []

    # Check for canonical format first (BOT-0008)
    m = BOT_CANON_RE.search(question)
    if m:
        bot_id = m.group(0).upper()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT BOT_ID FROM bot_master WHERE BOT_ID=%s LIMIT 1", (bot_id,))
                row = cur.fetchone()
            return (row["BOT_ID"] if row else bot_id), warnings
        except Exception:
            return bot_id, warnings

    # Try to extract number (e.g., "bot 8")
    m = BOT_NUM_RE.search(question)
    if not m:
        return None, warnings

    n = int(m.group(1))
    candidate = f"BOT-{n:04d}"  # Normalize to BOT-0008

    try:
        with conn.cursor() as cur:
            cur.execute("SELECT BOT_ID FROM bot_master WHERE BOT_ID=%s LIMIT 1", (candidate,))
            row = cur.fetchone()

        if row:
            return row["BOT_ID"], warnings

        warnings.append(f"BOT number {n} not found as {candidate}; using normalized candidate anyway.")
        return candidate, warnings
    except Exception as e:
        warnings.append(f"Bot resolution failed: {e}")
        return candidate, warnings


STATION_NUM_RE = re.compile(r"\b(?:station|stn|st)\s*[-_ ]?\s*(\d{1,4})\b", re.IGNORECASE)

def resolve_station(conn, db_name: str, question: str) -> Tuple[Optional[str], List[dict], List[str]]:
    """Resolve station ID from question"""
    warnings = []
    if not table_exists(conn, db_name, "hw_station_master"):
        warnings.append("hw_station_master table not found; station resolution skipped.")
        return None, [], warnings

    m = STATION_NUM_RE.search(question)
    if not m:
        return None, [], warnings
    n = int(m.group(1))

    q = """
    SELECT STATION_ID, STATION_ALIAS_NAME
    FROM hw_station_master
    WHERE (
        NULLIF(REGEXP_REPLACE(STATION_ID, '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(STATION_ID, '[^0-9]', '') AS UNSIGNED) = %s
    )
    OR (
        NULLIF(REGEXP_REPLACE(STATION_ALIAS_NAME, '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(STATION_ALIAS_NAME, '[^0-9]', '') AS UNSIGNED) = %s
    )
    LIMIT 10
    """
    cands = fetch_candidates(conn, q, (n, n))

    unique_ids = sorted({c["STATION_ID"] for c in cands if c.get("STATION_ID")})
    if len(unique_ids) == 1:
        return unique_ids[0], [], warnings
    if len(unique_ids) > 1:
        warnings.append(f"Station {n} is ambiguous; multiple matches found.")
        return None, cands, warnings

    warnings.append(f"Station {n} not found in hw_station_master.")
    return None, [], warnings


WAVE_NUM_RE = re.compile(r"\b(?:wave|wv)\s*[-_ ]?\s*(\d{1,6})\b", re.IGNORECASE)

def resolve_wave(conn, db_name: str, question: str) -> Tuple[Optional[str], List[dict], List[str]]:
    """Resolve wave ID from question"""
    warnings = []
    wave_tables = []
    if table_exists(conn, db_name, "wave_master"):
        wave_tables.append("wave_master")
    if table_exists(conn, db_name, "dashboard_log_wave_process"):
        wave_tables.append("dashboard_log_wave_process")

    if not wave_tables:
        warnings.append("No wave tables found; wave resolution skipped.")
        return None, [], warnings

    m = WAVE_NUM_RE.search(question)
    if not m:
        return None, [], warnings
    n = int(m.group(1))

    all_cands: List[dict] = []
    for t in wave_tables:
        q = f"""
        SELECT DISTINCT WAVE_ID
        FROM {t}
        WHERE (
            NULLIF(REGEXP_REPLACE(WAVE_ID, '[^0-9]', ''), '') IS NOT NULL
            AND CAST(REGEXP_REPLACE(WAVE_ID, '[^0-9]', '') AS UNSIGNED) = %s
        )
        LIMIT 10
        """
        cands = fetch_candidates(conn, q, (n,))
        for c in cands:
            all_cands.append({"WAVE_ID": c.get("WAVE_ID"), "source_table": t})

    unique = sorted({c["WAVE_ID"] for c in all_cands if c.get("WAVE_ID")})
    if len(unique) == 1:
        return unique[0], [], warnings
    if len(unique) > 1:
        warnings.append(f"Wave {n} is ambiguous; multiple WAVE_IDs found.")
        return None, all_cands, warnings

    warnings.append(f"Wave {n} not found.")
    return None, [], warnings


BIN_NUM_RE = re.compile(r"\b(?:bin|bn)\s*[-_ ]?\s*(\d{1,10})\b", re.IGNORECASE)
BARCODE_RE = re.compile(r"\b(?:barcode)\s*[:#-]?\s*([A-Za-z0-9\-_/.]+)\b", re.IGNORECASE)

def resolve_bin(conn, db_name: str, question: str) -> Tuple[Optional[str], Optional[str], List[dict], List[str]]:
    """Resolve bin ID and barcode from question"""
    warnings = []
    if not table_exists(conn, db_name, "bin_info_master"):
        warnings.append("bin_info_master table not found; bin resolution skipped.")
        return None, None, [], warnings

    # Check for barcode first
    m = BARCODE_RE.search(question)
    if m:
        token = m.group(1)
        q = """
        SELECT BIN_ID, BIN_BARCODE
        FROM bin_info_master
        WHERE BIN_BARCODE = %s OR BIN_ID = %s
        LIMIT 10
        """
        cands = fetch_candidates(conn, q, (token, token))
        uniq = sorted({(c.get("BIN_ID"), c.get("BIN_BARCODE")) for c in cands})
        if len(uniq) == 1:
            b = cands[0]
            return b.get("BIN_ID"), b.get("BIN_BARCODE"), [], warnings
        if len(uniq) > 1:
            warnings.append("Barcode token matched multiple bins; ambiguous.")
            return None, None, cands, warnings
        warnings.append("Barcode token not found.")
        return None, None, [], warnings

    # Try numeric bin
    m = BIN_NUM_RE.search(question)
    if not m:
        return None, None, [], warnings
    n = int(m.group(1))

    q = """
    SELECT BIN_ID, BIN_BARCODE
    FROM bin_info_master
    WHERE (
        NULLIF(REGEXP_REPLACE(CAST(BIN_ID AS CHAR), '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(CAST(BIN_ID AS CHAR), '[^0-9]', '') AS UNSIGNED) = %s
    )
    OR (
        NULLIF(REGEXP_REPLACE(CAST(BIN_BARCODE AS CHAR), '[^0-9]', ''), '') IS NOT NULL
        AND CAST(REGEXP_REPLACE(CAST(BIN_BARCODE AS CHAR), '[^0-9]', '') AS UNSIGNED) = %s
    )
    LIMIT 10
    """
    cands = fetch_candidates(conn, q, (n, n))
    uniq = sorted({(c.get("BIN_ID"), c.get("BIN_BARCODE")) for c in cands if c.get("BIN_ID") or c.get("BIN_BARCODE")})
    if len(uniq) == 1:
        b = cands[0]
        return b.get("BIN_ID"), b.get("BIN_BARCODE"), [], warnings
    if len(uniq) > 1:
        warnings.append(f"Bin {n} is ambiguous; multiple matches found.")
        return None, None, cands, warnings

    warnings.append(f"Bin {n} not found.")
    return None, None, [], warnings


def resolve_entities_from_db(question: str, db_config: Dict[str, Any]) -> Dict[str, Any]:
    """Main entity resolution orchestrator"""
    resolved: Dict[str, Any] = {"entities": {}, "candidates": {}, "warnings": []}
    
    try:
        conn = connect_neo(db_config, attempts=2)
    except Exception as e:
        resolved["warnings"].append(f"DB connection failed: {e}")
        return resolved

    try:
        db_name = db_config.get("database", "neo")

        # Resolve BOT_ID
        bot_id, w = resolve_bot(conn, question)
        if bot_id:
            resolved["entities"]["BOT_ID"] = bot_id
        resolved["warnings"].extend(w)

        # Resolve STATION_ID
        station_id, station_cands, w = resolve_station(conn, db_name, question)
        if station_id:
            resolved["entities"]["STATION_ID"] = station_id
        elif station_cands:
            resolved["candidates"]["STATION_ID"] = station_cands
        resolved["warnings"].extend(w)

        # Resolve WAVE_ID
        wave_id, wave_cands, w = resolve_wave(conn, db_name, question)
        if wave_id:
            resolved["entities"]["WAVE_ID"] = wave_id
        elif wave_cands:
            resolved["candidates"]["WAVE_ID"] = wave_cands
        resolved["warnings"].extend(w)

        # Resolve BIN_ID/BIN_BARCODE
        bin_id, bin_barcode, bin_cands, w = resolve_bin(conn, db_name, question)
        if bin_id:
            resolved["entities"]["BIN_ID"] = bin_id
        if bin_barcode:
            resolved["entities"]["BIN_BARCODE"] = bin_barcode
        elif bin_cands:
            resolved["candidates"]["BIN"] = bin_cands
        resolved["warnings"].extend(w)

    except Exception as e:
        resolved["warnings"].append(f"Entity resolution error: {e}")
    finally:
        try:
            conn.close()
        except Exception:
            pass

    return resolved


def inject_resolved_into_question(question: str, resolved: Dict[str, Any]) -> str:
    """Inject resolved entities into question for LLM"""
    parts = [question]

    entities = resolved.get("entities", {})
    cands = resolved.get("candidates", {})
    warnings = resolved.get("warnings", [])

    if entities:
        parts.append("\n**RESOLVED_ENTITIES** (use EXACT values in SQL, do NOT transform or reformat):")
        for k, v in entities.items():
            parts.append(f"- {k} = '{v}'")

    if cands:
        parts.append("\n**RESOLVED_CANDIDATES** (ambiguous; ask follow-up if needed):")
        for k, v in cands.items():
            parts.append(f"- {k}: {json.dumps(v[:3], ensure_ascii=False)}")

    if warnings:
        parts.append("\n**RESOLUTION_WARNINGS:**")
        for w in warnings[:5]:
            parts.append(f"- {w}")

    return "\n".join(parts)


# ----------------------------
# NL → SQL Generator (Enhanced)
# ----------------------------
class NLToSQLGenerator:
    """
    CSV-driven NL → SQL generator with entity resolution
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

        self.schema_csv_path = (
            schema_csv_path
            or os.getenv("NEO_SCHEMA_CSV_PATH")
        )

        if not self.schema_csv_path:
            raise ValueError("Schema CSV path not provided")

        self.schema_df = load_table_summary(self.schema_csv_path)
        self.vec, self.X = build_retriever(self.schema_df)
        
        # Load validation rules and custom priorities
        self.validation_rules = self._load_validation_rules()
        self.custom_priorities = self._load_custom_priorities()
        
        # Load business rules from config
        self.business_rules = self._load_business_rules()
    
    def _load_validation_rules(self) -> Dict[str, Dict[str, List[str]]]:
        """Load query-specific validation rules from JSONL"""
        rules = {}
        validations_path = "data/database/table_priority_validations.jsonl"
        
        if not os.path.exists(validations_path):
            return rules
        
        try:
            with open(validations_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    v = json.loads(line)
                    query = v['query'].lower().strip()
                    table = v['table_name']
                    is_correct = v['is_correct']
                    
                    if query not in rules:
                        rules[query] = {'correct_tables': [], 'incorrect_tables': []}
                    
                    if is_correct and table not in rules[query]['correct_tables']:
                        rules[query]['correct_tables'].append(table)
                    elif not is_correct and table not in rules[query]['incorrect_tables']:
                        rules[query]['incorrect_tables'].append(table)
        except Exception as e:
            print(f"Error loading validation rules: {e}")
        
        return rules
    
    def _load_custom_priorities(self) -> Optional[Dict[str, float]]:
        """Load custom category priority settings"""
        priorities_path = "data/database/table_priority_settings.json"
        
        if not os.path.exists(priorities_path):
            return None
        
        try:
            with open(priorities_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading custom priorities: {e}")
            return None
    
    def _load_business_rules(self) -> Dict[str, Any]:
        """Load business rules from config/sql_assistant_config.json"""
        # Use same path resolution as sql_assistant_service.py
        config_dir = settings.DATA_DIR.parent / "config"
        rules_path = config_dir / "sql_assistant_config.json"
        
        if not rules_path.exists():
            print(f"ℹ️ Business rules not found at {rules_path}")
            return {}
        
        try:
            with open(rules_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                business_rules = config.get("business_rules", {})
                print(f"✅ Loaded {len(business_rules)} business rules from config")
                return business_rules
        except Exception as e:
            print(f"⚠️ Error loading business rules: {e}")
            return {}
    
    def _check_business_rules(self, question: str) -> Optional[Dict[str, Any]]:
        """Check if question matches any business rules
        
        Returns:
            Matched rule config or None
        """
        if not self.business_rules:
            return None
        
        question_lower = question.lower()
        
        for rule_name, rule_config in self.business_rules.items():
            triggers = rule_config.get("triggers", [])
            if any(trigger.lower() in question_lower for trigger in triggers):
                print(f"🔴 BUSINESS RULE MATCHED: {rule_name}")
                return rule_config
        
        return None
    
    def _build_business_rules_prompt(self, rule_config: Dict[str, Any]) -> str:
        """Build prompt section for business rules"""
        prompt = "\n\n" + "="*80 + "\n"
        prompt += "🔴🔴🔴 CRITICAL MANDATORY BUSINESS RULE - MUST FOLLOW 🔴🔴🔴\n"
        prompt += "="*80 + "\n"
        prompt += f"Description: {rule_config.get('description', 'N/A')}\n\n"
        
        if 'required_table' in rule_config:
            prompt += f"✅ REQUIRED TABLE (MUST USE): {rule_config['required_table']}\n"
            prompt += f"❌ DO NOT use any other table for this query type!\n\n"
        
        if 'required_filters' in rule_config:
            prompt += "✅ REQUIRED WHERE CONDITIONS (MUST INCLUDE ALL):\n"
            for filter_rule in rule_config['required_filters']:
                prompt += f"   - {filter_rule}\n"
            prompt += "\n"
        
        if 'forbidden_columns' in rule_config:
            prompt += "❌ FORBIDDEN COLUMNS (DO NOT USE):\n"
            for col in rule_config['forbidden_columns']:
                prompt += f"   - {col}\n"
            prompt += "\n"
        
        if 'additional_columns' in rule_config:
            prompt += "✅ AVAILABLE COLUMNS (use these):\n"
            for col in rule_config.get('additional_columns', [])[:10]:  # Limit to first 10
                prompt += f"   - {col}\n"
            prompt += "\n"
        
        if 'additional_joins' in rule_config:
            prompt += "📋 SUGGESTED JOINS:\n"
            for join_info in rule_config['additional_joins']:
                if isinstance(join_info, dict):
                    prompt += f"   - JOIN {join_info.get('table', '')} ON {join_info.get('condition', '')}\n"
                else:
                    prompt += f"   - {join_info}\n"
            prompt += "\n"
        
        prompt += "="*80 + "\n"
        prompt += "⚠️ VIOLATION OF THIS RULE WILL RESULT IN INCORRECT RESULTS!\n"
        prompt += "⚠️ DO NOT use alternative approaches or skip required conditions!\n"
        prompt += "="*80 + "\n"
        return prompt

    def generate(self, question: str, enable_entity_resolution: bool = True) -> Dict[str, Any]:
        """Generate SQL from natural language question
        
        Args:
            question: User's natural language question
            enable_entity_resolution: If True, resolve entities like BOT_ID, STATION_ID from DB
            
        Returns:
            Dict with sql, confidence, metadata, etc.
        """
        # Step 1: Entity resolution (if enabled and DB config provided)
        resolved = {"entities": {}, "candidates": {}, "warnings": []}
        if enable_entity_resolution and self.db_config:
            try:
                resolved = resolve_entities_from_db(question, self.db_config)
            except Exception as e:
                resolved["warnings"].append(f"Entity resolution failed: {e}")

        # Step 2: Check business rules
        matched_business_rule = self._check_business_rules(question)
        
        # Step 3: Enrich question with resolved entities
        question_for_llm = question
        if resolved.get("entities") or resolved.get("candidates"):
            question_for_llm = inject_resolved_into_question(question, resolved)

        # Step 4: Pick relevant tables using TF-IDF with validation rules
        picked = pick_relevant_tables(
            question_for_llm, 
            self.schema_df, 
            self.vec, 
            self.X, 
            top_k=8,
            validation_rules=self.validation_rules,
            custom_priorities=self.custom_priorities
        )
        schema_context = build_schema_context(picked)

        # Step 5: Generate SQL with OpenAI
        instructions = (
            "You are a senior MySQL 8.x Text-to-SQL generator for the NEO warehouse database.\n\n"
            "CRITICAL RULES:\n"
            "1) Use ONLY the tables/columns provided in SCHEMA CONTEXT below.\n"
            "2) Output MUST strictly match the JSON schema (sql, tables_used, confidence, etc.).\n"
            "3) Generate READ-ONLY SQL only (SELECT/WITH). Never use INSERT/UPDATE/DELETE/DROP.\n"
            "4) If question is ambiguous or missing required filters, set needs_followup=true.\n"
            "5) If returning many rows without explicit user request for all, add LIMIT 200.\n"
            "6) Prefer explicit JOINs using primary/foreign key relationships.\n\n"
            "ENTITY RESOLUTION RULES (CRITICAL):\n"
            "7) If you see **RESOLVED_ENTITIES** section, you MUST use those EXACT values in your SQL.\n"
            "   - DO NOT transform, reformat, or modify these values.\n"
            "   - Example: If BOT_ID = 'BOT-0008', use WHERE BOT_ID = 'BOT-0008' (NOT WHERE BOT_ID = '8').\n"
            "8) If you see **RESOLVED_CANDIDATES** showing multiple matches, set needs_followup=true and ask user to clarify.\n\n"
            "TABLE PRIORITY RULES (CRITICAL):\n"
            "9) For CURRENT/LIVE state queries (status, position, battery), use MASTER tables (bot_master, station_master).\n"
            "10) AVOID telemetry/log tables for business queries unless explicitly asking for historical/sensor data.\n"
            "11) Master tables contain PRIMARY/CURRENT state. Log/telemetry tables are for HISTORY/DEBUGGING.\n"
            "12) Examples:\n"
            "    - 'current position of bot 7' → Use bot_master (GRIDX, GRIDY), NOT teleoperation tables\n"
            "    - 'bot 7 position history' → Use bot_master_log or telemetry\n"
            "    - 'bot 7 sensor readings' → Use teleoperation/telemetry tables\n\n"
            "SIMPLICITY RULES:\n"
            "13) Use the SIMPLEST query that answers the question. Avoid unnecessary complexity.\n"
            "14) Do NOT use UNION unless explicitly needed for combining different data sources.\n"
            "15) Use ORDER BY + LIMIT only when specifically asking for 'latest', 'recent', 'top N', etc.\n"
        )
        
        # Add business rules to instructions if matched
        if matched_business_rule:
            instructions += self._build_business_rules_prompt(matched_business_rule)

        resp = self.client.responses.create(
            model=self.model,
            instructions=instructions,
            input=(
                f"USER QUESTION:\n{question_for_llm}\n\n"
                f"SCHEMA CONTEXT (only these tables/columns are allowed):\n{schema_context}"
            ),
            text={
                "format": {
                    "type": "json_schema",
                    "name": "sql_response",
                    "strict": True,
                    "schema": STRICT_RESPONSE_SCHEMA,
                }
            },
        )

        result = json.loads(resp.output_text)

        # Safety check
        if not is_read_only_sql(result.get("sql", "")):
            raise ValueError("Generated SQL is not read-only")

        # Add entity resolution metadata
        if resolved.get("entities"):
            result["resolved_entities"] = resolved["entities"]
        if resolved.get("warnings"):
            result.setdefault("warnings", []).extend(resolved["warnings"])

        return result
    
    def get_ranked_tables_for_query(self, question: str, top_k: int = 8) -> List[Dict[str, Any]]:
        """
        Get ranked tables for a query (for UI testing/validation)
        
        Args:
            question: User's natural language question
            top_k: Number of tables to return
            
        Returns:
            List of dicts with table_name, description, columns, category, score
        """
        picked = pick_relevant_tables(
            question,
            self.schema_df,
            self.vec,
            self.X,
            top_k=top_k,
            validation_rules=self.validation_rules,
            custom_priorities=self.custom_priorities
        )
        
        # Convert to list of dicts for API response
        results = []
        for _, row in picked.iterrows():
            results.append({
                'table_name': row['Table_name'],
                'description': row.get('Table_description', 'No description'),
                'columns': row.get('Table_columns(Data type)', 'N/A'),
                'primary_key': row.get('Primary_key', 'N/A'),
                'category': row.get('Table_category', 'general_table'),
                'score': float(row.get('score', 0.0))
            })
        
        return results
