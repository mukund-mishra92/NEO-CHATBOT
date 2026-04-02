import json
import logging
from pathlib import Path
from typing import Optional, List, Dict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from difflib import SequenceMatcher
import re
import numpy as np

from .match_utils import strip_matching_noise

logger = logging.getLogger(__name__)


# ============================================================
# Data classes
# ============================================================

@dataclass
class SPEntry:
    id: str
    sp_name: str
    description: str
    requires_time_range: bool
    requires_location: bool
    keywords: List[str] = field(default_factory=list)
    tables_used: List[str] = field(default_factory=list)
    output_columns: List[str] = field(default_factory=list)
    sql_body: str = ""   # SP body parsed from email_reports_sp.sql
    query_sql: str = ""  # SELECT query from queries_sp_mapping/


@dataclass
class SPMatch:
    sp_id: str
    sp_name: str
    description: str
    sql: str
    match_score: float
    parameters_applied: Dict[str, str]
    tables_used: List[str] = field(default_factory=list)
    output_columns: List[str] = field(default_factory=list)


# ============================================================
# Resolver
# ============================================================

class SPResolver:

    MATCH_THRESHOLD = 0.48
    EMBEDDING_WEIGHT = 0.60
    KEYWORD_WEIGHT = 0.25
    DESCRIPTION_WEIGHT = 0.15
    _TEXT_VERSION = 2  # bump when _build_text changes → forces re-embedding

    def __init__(self, registry_path: str, sql_file_path: str = None,
                 tenant_column: str = "host-location",
                 schema: Dict[str, list] = None):
        self.sps: List[SPEntry] = []
        self.sp_embeddings: Dict[str, np.ndarray] = {}
        self._embeddings_available = False
        self.tenant_column = tenant_column

        self._load_registry(registry_path)

        # ── Load SELECT query files from queries_sp_mapping/ ──
        queries_dir = Path(registry_path).parent / "queries_sp_mapping"
        if queries_dir.exists():
            self._load_query_files(str(queries_dir))
        else:
            logger.warning(f"⚠️ queries_sp_mapping dir not found: {queries_dir}")

        # Load actual SP SQL bodies from .sql file (fallback)
        if sql_file_path:
            self._load_sql_bodies(sql_file_path)
        else:
            # Auto-detect: look for email_reports_sp.sql next to registry
            auto_path = Path(registry_path).parent / "email_reports_sp.sql"
            if auto_path.exists():
                self._load_sql_bodies(str(auto_path))
                logger.info(f"⚙️ Auto-loaded SP SQL bodies from {auto_path}")

        # Build set of SP tables that actually have the tenant column
        # (schema-aware: only include tables confirmed in CSV schema)
        self._sp_tables = set()
        all_sp_tables = set()
        for sp in self.sps:
            all_sp_tables.update(t.lower() for t in sp.tables_used)

        if schema:
            for t in all_sp_tables:
                cols = [c.lower().replace('`', '') for c in schema.get(t, [])]
                if tenant_column.lower() in cols:
                    self._sp_tables.add(t)
            skipped = all_sp_tables - self._sp_tables
            if skipped:
                logger.warning(
                    f"⚠️ SP tables without '{tenant_column}': {skipped}"
                )
        else:
            # No schema provided — assume all SP tables have tenant column
            self._sp_tables = all_sp_tables
            logger.warning(
                "⚠️ No schema passed to SPResolver; assuming all SP tables "
                f"have '{tenant_column}'"
            )

        # ── Centralised embeddings folder ──
        from app.core.config import settings
        self._embeddings_dir = settings.EMBEDDINGS_DIR
        self._embeddings_dir.mkdir(parents=True, exist_ok=True)
        self._embeddings_path = self._embeddings_dir / "sp_embeddings.npz"

        self._init_embeddings()

        loaded_bodies = sum(1 for sp in self.sps if sp.sql_body)
        loaded_queries = sum(1 for sp in self.sps if sp.query_sql)
        logger.info(
            f"⚙️ SPResolver loaded {len(self.sps)} SPs "
            f"(query_files={loaded_queries}, bodies={loaded_bodies}, "
            f"embeddings={'✅' if self._embeddings_available else '❌'})"
        )

    # ----------------------------------------------------------
    # LOAD REGISTRY (JSON)
    # ----------------------------------------------------------

    def _load_registry(self, path: str):
        with open(path, "r") as f:
            raw = json.load(f)

        for item in raw:
            sp = SPEntry(
                id=item["id"],
                sp_name=item["sp_name"],
                description=item.get("description", ""),
                requires_time_range=item.get("requires_time_range", False),
                requires_location=item.get("requires_location", False),
                keywords=item.get("keywords", []),
                tables_used=item.get("tables_used", []),
                output_columns=item.get("output_columns", []),
            )
            self.sps.append(sp)

    # ----------------------------------------------------------
    # LOAD SQL BODIES (parse .sql file)
    # ----------------------------------------------------------

    def _load_sql_bodies(self, sql_path: str):
        """Parse email_reports_sp.sql and extract the SQL body for each SP."""
        try:
            with open(sql_path, "r", encoding="utf-8") as f:
                content = f.read()

            # Build lookup: sp_name → SPEntry
            sp_lookup: Dict[str, SPEntry] = {sp.sp_name: sp for sp in self.sps}

            # Split by procedure blocks using the comment header pattern
            # Pattern: CREATE ... PROCEDURE `neo`.`SP_NAME`(...) ... BEGIN ... END
            sp_pattern = re.compile(
                r"CREATE\s+DEFINER.*?PROCEDURE\s+`neo`\.`(\w+)`"
                r".*?BEGIN\s*\n(.*?)\nEND",
                re.DOTALL | re.IGNORECASE,
            )

            matched = 0
            for m in sp_pattern.finditer(content):
                sp_name = m.group(1)
                sql_body = m.group(2).strip()

                if sp_name in sp_lookup:
                    sp_lookup[sp_name].sql_body = sql_body
                    matched += 1

            logger.info(f"⚙️ Parsed {matched}/{len(self.sps)} SP bodies from {sql_path}")

        except Exception as e:
            logger.warning(f"⚠️ Failed to load SP SQL bodies from {sql_path}: {e}")

    # ----------------------------------------------------------
    # LOAD QUERY FILES (queries_sp_mapping/)
    # ----------------------------------------------------------

    def _load_query_files(self, queries_dir: str):
        """Load pre-built SELECT queries from queries_sp_mapping/ directory.

        Files are named sp{N}.sql where N matches the numeric part of sp.id
        (e.g. sp_001 → sp1.sql, sp_010 → sp10.sql).  These queries are the
        **primary** execution path — they run as plain SELECT and don't need
        EXECUTE privilege on stored procedures.
        """
        queries_path = Path(queries_dir)
        loaded = 0

        for sp in self.sps:
            # sp.id = "sp_001" → num = 1
            try:
                sp_num = int(sp.id.split('_')[1])
            except (IndexError, ValueError):
                continue

            query_file = queries_path / f"sp{sp_num}.sql"
            if query_file.exists():
                sp.query_sql = query_file.read_text(encoding='utf-8').strip()
                loaded += 1

        logger.info(
            f"⚙️ Loaded {loaded}/{len(self.sps)} SP query files "
            f"from {queries_dir}"
        )

    # ----------------------------------------------------------
    # EMBEDDINGS
    # ----------------------------------------------------------

    def _build_text(self, sp: SPEntry) -> str:
        """Build text for embedding — emphasises natural language description
        and keywords so the vector matches user questions rather than SQL syntax."""
        # Description repeated for emphasis (most semantically meaningful)
        name_natural = sp.sp_name.replace('ES_', '').replace('_', ' ').lower()
        parts = [sp.description, sp.description, name_natural]

        if sp.keywords:
            parts.append(" ".join(sp.keywords))

        if sp.output_columns:
            parts.append("columns: " + " ".join(sp.output_columns))

        # Intentionally exclude sql_body — SQL syntax dilutes
        # the semantic signal for natural-language matching.

        return " ".join(parts)

    def _init_embeddings(self):
        """Load cached SP embeddings from disk, or compute fresh ones and persist."""
        # 1. Try loading from disk
        if self._load_embeddings_from_disk():
            return

        # 2. Compute fresh embeddings via OpenAI
        try:
            from app.services.embedding_service import embedding_service

            texts = [self._build_text(sp) for sp in self.sps]
            embeddings = embedding_service.embed_batch(texts)

            for sp, emb in zip(self.sps, embeddings):
                self.sp_embeddings[sp.id] = emb

            self._embeddings_available = True

            # Persist to disk
            self._save_embeddings_to_disk()

        except Exception as e:
            logger.warning(f"⚠️ SP embedding init failed: {e}")
            self._embeddings_available = False

    def _load_embeddings_from_disk(self) -> bool:
        """Load saved SP embeddings from data/embeddings/sp_embeddings.npz."""
        if not self._embeddings_path.exists():
            return False

        try:
            data = np.load(str(self._embeddings_path), allow_pickle=True)
            ids = data["ids"].tolist()
            matrix = data["matrix"]

            # Validate version — _build_text changed → must re-embed
            saved_version = int(data["version"][0]) if "version" in data else 1
            if saved_version != self._TEXT_VERSION:
                logger.info(
                    f"⚙️ SP embedding text version changed "
                    f"({saved_version}→{self._TEXT_VERSION}) — rebuilding"
                )
                return False

            # Validate: must match current registry IDs
            sp_id_set = {sp.id for sp in self.sps}
            if set(ids) != sp_id_set:
                logger.info("⚙️ SP registry changed — rebuilding embeddings")
                return False

            for sp_id, emb in zip(ids, matrix):
                self.sp_embeddings[sp_id] = emb

            self._embeddings_available = True
            logger.info(f"💾 Restored {len(ids)} SP embeddings from disk cache (v{saved_version})")
            return True

        except Exception as e:
            logger.warning(f"⚠️ Could not load SP embeddings from disk: {e}")
            return False

    def _save_embeddings_to_disk(self):
        """Persist SP embeddings to data/embeddings/sp_embeddings.npz."""
        if not self.sp_embeddings:
            return

        try:
            ids = list(self.sp_embeddings.keys())
            matrix = np.array([self.sp_embeddings[k] for k in ids])

            np.savez_compressed(
                str(self._embeddings_path),
                ids=np.array(ids, dtype=object),
                matrix=matrix,
                version=np.array([self._TEXT_VERSION]),
            )
            logger.info(
                f"💾 Saved {len(ids)} SP embeddings to "
                f"{self._embeddings_path} (v{self._TEXT_VERSION})"
            )

        except Exception as e:
            logger.warning(f"⚠️ Could not save SP embeddings: {e}")

    def _get_embedding(self, text: str):
        if not self._embeddings_available:
            return None
        try:
            from app.services.embedding_service import embedding_service
            return embedding_service.embed(text)
        except:
            return None

    # ----------------------------------------------------------
    # SCORING
    # ----------------------------------------------------------

    @staticmethod
    def _fuzzy_word_match(word1: str, word2: str, threshold: float = 0.73) -> bool:
        """True when two words are close enough (handles typos like hous→hour)."""
        if word1 == word2:
            return True
        return SequenceMatcher(None, word1, word2).ratio() >= threshold

    def _fuzzy_phrase_in(self, phrase: str, q_normalized: str, q_words: set) -> bool:
        """Check if a multi-word phrase is present in the question, with
        per-word fuzzy tolerance for typos."""
        words = phrase.lower().split()
        if len(words) == 1:
            # Single word → check fuzzy against every question word
            return any(self._fuzzy_word_match(words[0], qw) for qw in q_words)

        # Multi-word → exact substring first (fast path)
        if phrase.lower() in q_normalized:
            return True

        # Fuzzy: all phrase words must have a fuzzy-match in Q
        return all(
            any(self._fuzzy_word_match(pw, qw) for qw in q_words)
            for pw in words
        )

    def _keyword_score(self, question: str, sp: SPEntry) -> float:
        q_lower = question.lower()

        # ── CRITICAL: normalise underscores → spaces ──
        # User may type "BIN_PER_HOUR_PER_STATION" which should match
        # keywords like "bin", "per hour", "station"
        q_normalized = q_lower.replace('_', ' ')
        q_words = set(q_normalized.split())

        # ── 1. SP name direct match (strongest signal) ──
        sp_name_clean = sp.sp_name.lower().replace('es_', '').replace('_', ' ')
        name_words = sp_name_clean.split()
        name_bonus = 0.0
        if sp_name_clean in q_normalized:
            # User typed the full SP concept (e.g. "bin per hour per station")
            name_bonus = 0.5
        elif all(w in q_words for w in name_words):
            # All name-words present somewhere in the question
            name_bonus = 0.35
        elif all(any(self._fuzzy_word_match(nw, qw) for qw in q_words) for nw in name_words):
            # All name-words present with fuzzy tolerance (typos)
            name_bonus = 0.30

        # ── 2. Output column match ──
        col_bonus = 0.0
        if sp.output_columns:
            for col in sp.output_columns:
                col_clean = col.lower().replace('_', ' ')
                if col_clean in q_normalized:
                    col_bonus += 0.05
            col_bonus = min(0.15, col_bonus)

        # ── 3. Keyword matching with fuzzy tolerance ──
        hits = 0
        total_kw = len(sp.keywords) if sp.keywords else 1
        for kw in (sp.keywords or []):
            if self._fuzzy_phrase_in(kw, q_normalized, q_words):
                hits += 1

        # ── 4. Table name bonus ──
        table_bonus = 0
        if sp.tables_used:
            for table in sp.tables_used:
                if table.lower() in q_lower:
                    table_bonus += 0.05

        base = hits / total_kw
        return min(1.0, base + table_bonus + name_bonus + col_bonus)

    # ----------------------------------------------------------
    # DESCRIPTION OVERLAP
    # ----------------------------------------------------------

    _STOPWORDS = frozenset({
        'the', 'a', 'an', 'for', 'in', 'of', 'to', 'and', 'or', 'is',
        'by', 'at', 'on', 'with', 'from', 'that', 'this', 'each', 'given',
        'time', 'window', 'based', 'show', 'shows', 'return', 'returns',
        'all', 'get', 'give', 'me', 'please', 'can', 'you', 'i', 'want',
        'need', 'data', 'report', 'last', 'days', 'day', 'hours',
    })

    def _description_overlap_score(self, question: str, sp: SPEntry) -> float:
        """Word-overlap between user question and SP description/keywords."""
        q_words = set(question.lower().replace('_', ' ').split()) - self._STOPWORDS
        d_text = f"{sp.description} {' '.join(sp.keywords or [])}"
        d_words = set(d_text.lower().replace('_', ' ').split()) - self._STOPWORDS

        if not q_words or not d_words:
            return 0.0

        # Count fuzzy overlaps (handles typos)
        overlap = 0
        for qw in q_words:
            if any(self._fuzzy_word_match(qw, dw) for dw in d_words):
                overlap += 1

        return overlap / max(len(q_words), 1)

    # ----------------------------------------------------------
    # HYBRID SCORE
    # ----------------------------------------------------------

    def _hybrid_score(self, question: str, sp: SPEntry, q_emb) -> float:
        keyword = self._keyword_score(question, sp)
        desc = self._description_overlap_score(question, sp)

        if not self._embeddings_available or q_emb is None:
            return 0.70 * keyword + 0.30 * desc

        sp_emb = self.sp_embeddings.get(sp.id)
        if sp_emb is None:
            return 0.70 * keyword + 0.30 * desc

        emb_score = float(np.dot(q_emb, sp_emb))
        return (
            self.EMBEDDING_WEIGHT * emb_score
            + self.KEYWORD_WEIGHT * keyword
            + self.DESCRIPTION_WEIGHT * desc
        )

    # ----------------------------------------------------------
    # TIME-RANGE PARSING
    # ----------------------------------------------------------

    def _parse_time_range(self, question: str) -> timedelta:
        """Extract time delta from natural-language expressions in the question."""
        q = question.lower()

        # "last N days"
        m = re.search(r'last\s+(\d+)\s+days?', q)
        if m:
            return timedelta(days=int(m.group(1)))

        # "last N hours"
        m = re.search(r'last\s+(\d+)\s+hours?', q)
        if m:
            return timedelta(hours=int(m.group(1)))

        # "yesterday"
        if 'yesterday' in q:
            return timedelta(days=1)

        # "today"
        if re.search(r'\btoday\b', q):
            return timedelta(days=0)

        # "last (one|1)? week(s)"
        m = re.search(r'last\s+(?:one|1)?\s*weeks?', q)
        if m:
            return timedelta(weeks=1)

        # "last N weeks"
        m = re.search(r'last\s+(\d+)\s+weeks?', q)
        if m:
            return timedelta(weeks=int(m.group(1)))

        # "last (one|1)? month(s)"
        m = re.search(r'last\s+(?:one|1)?\s*months?', q)
        if m:
            return timedelta(days=30)

        # "last N months"
        m = re.search(r'last\s+(\d+)\s+months?', q)
        if m:
            return timedelta(days=30 * int(m.group(1)))

        # Default: 7 days
        return timedelta(days=7)

    # ----------------------------------------------------------
    # PARAM BUILDING
    # ----------------------------------------------------------

    def _build_params(self, sp: SPEntry, question: str = "") -> Dict[str, str]:
        now = datetime.now()
        delta = self._parse_time_range(question) if question else timedelta(days=7)

        if delta.total_seconds() == 0:
            # "today" — start at midnight
            start = now.strftime("%Y-%m-%d 00:00:00")
        else:
            start = (now - delta).strftime("%Y-%m-%d 00:00:00")

        end = now.strftime("%Y-%m-%d %H:%M:%S")

        return {
            "start_time": start,
            "end_time": end,
        }

    # ----------------------------------------------------------
    # SQL BUILDING  (query_sql preferred → sql_body → CALL)
    # ----------------------------------------------------------

    def _substitute_dates_in_query(self, sql: str, params: Dict) -> str:
        """Replace hardcoded BETWEEN date-ranges in query_sql files.

        All query files use the pattern:
            BETWEEN 'YYYY-MM-DD HH:MM:SS' AND 'YYYY-MM-DD HH:MM:SS'
        Replace start/end timestamps with the computed time range.
        """
        start = params['start_time']
        end   = params['end_time']

        sql = re.sub(
            r"BETWEEN\s+'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})'"
            r"\s+AND\s+'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})'",
            f"BETWEEN '{start}' AND '{end}'",
            sql,
            flags=re.IGNORECASE,
        )
        return sql

    def _build_sql(self, sp: SPEntry, params: Dict,
                   tenant_values: List[str] = None) -> str:
        """
        Build executable SQL.  Priority:
        1. query_sql  (SELECT from queries_sp_mapping/ — no EXECUTE needed)
        2. sql_body   (SP body from email_reports_sp.sql — uses p_start/end)
        3. CALL       (requires EXECUTE privilege)
        """

        # ── Priority 1: query_sql (standalone SELECT, no perms needed) ──
        if sp.query_sql:
            sql = sp.query_sql

            # Substitute hardcoded dates with computed time range
            sql = self._substitute_dates_in_query(sql, params)

            # Inject tenant filter
            if tenant_values:
                sql = self._inject_tenant_in_sql_body(sql, sp, tenant_values)

            sql = sql.strip().rstrip(';').strip()

            logger.info(
                f"⚙️ Built SQL from query file: {sp.sp_name} "
                f"(tenant={'→'.join(tenant_values) if tenant_values else 'all'})"
            )
            return sql

        # ── Priority 2: sql_body (parsed SP body) ──
        if sp.sql_body:
            sql = sp.sql_body

            # Substitute time parameters used in the SP
            sql = sql.replace('p_start_date_time', f"'{params['start_time']}'")
            sql = sql.replace('p_end_date_time', f"'{params['end_time']}'")

            # Inject tenant filter into CTE sub-queries
            if tenant_values:
                sql = self._inject_tenant_in_sql_body(sql, sp, tenant_values)

            sql = sql.strip().rstrip(';').strip()

            logger.info(
                f"⚙️ Built SQL from SP body: {sp.sp_name} "
                f"(tenant={'→'.join(tenant_values) if tenant_values else 'all'})"
            )
            return sql

        # ── Priority 3: CALL statement ──
        return f"CALL {sp.sp_name}('{params['start_time']}', '{params['end_time']}')"

    # ----------------------------------------------------------
    # BUILD CALL STATEMENT  (fallback when body SQL fails)
    # ----------------------------------------------------------

    def build_call_statement(self, sp_match) -> str:
        """
        Build a CALL statement from the matched SP.
        Used as fallback when body-based SQL execution fails.
        The SP runs with SQL SECURITY DEFINER (root@%) — no
        permission issues, but no per-tenant filtering either.
        """
        params = sp_match.parameters_applied
        return (
            f"CALL {sp_match.sp_name}"
            f"('{params['start_time']}', '{params['end_time']}')"
        )

    # ----------------------------------------------------------
    # TENANT INJECTION  (CTE-safe)
    # ----------------------------------------------------------

    def _inject_tenant_in_sql_body(self, sql: str, sp: SPEntry,
                                   tenant_values: List[str]) -> str:
        """
        Inject tenant filter into SP SQL body for CTE-based queries.

        Strategy: For each real table referenced in the SQL that has the
        tenant column (host-location), find its WHERE clause and prepend
        the tenant condition.  CTE aliases (BaseResults, WithDiff, …) are
        ignored because they aren't in _sp_tables.
        """
        if not tenant_values:
            return sql

        # Build filter clause
        if len(tenant_values) == 1:
            filt = f"`{self.tenant_column}` = '{tenant_values[0]}'"
        else:
            vals = "', '".join(tenant_values)
            filt = f"`{self.tenant_column}` IN ('{vals}')"

        # Process tables longest-name-first to avoid prefix matching
        # (pick_wave_order_master_archive before pick_wave_order_master)
        tables = sorted(
            (t for t in sp.tables_used if t.lower() in self._sp_tables),
            key=len, reverse=True,
        )

        for table in tables:
            # Pattern: FROM <table> [optional stuff on same line]
            #          WHERE <conditions>
            # →        WHERE <tenant_filter> AND <conditions>
            pattern = (
                rf'(FROM\s+{re.escape(table)}\b)'   # group 1: FROM table
                rf'(.*?)'                             # group 2: gap (alias, newline)
                rf'(WHERE\s+)'                        # group 3: WHERE keyword
            )

            def _replacer(m, _filt=filt):
                return f"{m.group(1)}{m.group(2)}{m.group(3)}{_filt}\n          AND "

            sql = re.sub(pattern, _replacer, sql,
                         flags=re.IGNORECASE | re.DOTALL)

        logger.info(f"⚙️ Injected tenant filter ({filt}) into SP SQL body")
        return sql

    # ----------------------------------------------------------
    # MAIN RESOLVE
    # ----------------------------------------------------------

    def resolve(
        self,
        question: str,
        tenant_values=None,
        all_sites=False,
    ) -> Optional[SPMatch]:

        # ── Strip tenant/time noise for scoring only ──
        # The original `question` is kept for _build_params (time parsing)
        # and _build_sql (tenant injection).
        match_question = strip_matching_noise(question)
        logger.debug(f"⚙️ SP match_question: '{match_question}' (raw: '{question}')")

        q_emb = self._get_embedding(match_question)

        best = None
        best_score = 0.0

        for sp in self.sps:
            score = self._hybrid_score(match_question, sp, q_emb)

            if score > best_score and score >= self.MATCH_THRESHOLD:
                best = sp
                best_score = score

        if not best:
            return None

        # Build params with time-range parsing from user question
        params = self._build_params(best, question)

        # Build SQL from SP body with tenant injection
        # (skip tenant filter for all-sites queries)
        effective_tenants = tenant_values if (tenant_values and not all_sites) else None
        sql = self._build_sql(best, params, effective_tenants)

        # Determine SQL source for logging
        sql_source = (
            "query_file" if best.query_sql
            else "sp_body" if best.sql_body
            else "CALL"
        )
        logger.info(
            f"⚙️ SP matched: {best.sp_name} (score={best_score:.2f}, "
            f"source={sql_source}) tables={best.tables_used}"
        )

        return SPMatch(
            sp_id=best.id,
            sp_name=best.sp_name,
            description=best.description,
            sql=sql,
            match_score=best_score,
            parameters_applied=params,
            tables_used=best.tables_used,
            output_columns=best.output_columns,
        )