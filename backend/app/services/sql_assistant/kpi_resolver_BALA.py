"""
Dashboard KPI Resolver
=======================
Matches user questions to pre-built dashboard KPI queries.

When a user asks a question that maps to a known Grafana-style KPI,
this service returns the ready-made SQL (with parameter substitution)
instead of letting the LLM generate from scratch.

Flow:
  1. Load kpi_registry.json (85 KPIs across bot/inventory/orders/station)
  2. Build keyword index for fast matching
  3. On each query → keyword score + optional semantic similarity
  4. If match found → substitute $location / $__timeFrom / $__timeTo
  5. Return KPIMatch with chart_type, query, metadata for the frontend
"""

import json
import re
import logging
from pathlib import Path
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field
from datetime import datetime, timedelta

import numpy as np

from .match_utils import strip_matching_noise

logger = logging.getLogger(__name__)


# ============================================================
# Data classes
# ============================================================

@dataclass
class KPIEntry:
    """A single KPI from the registry."""
    id: str
    kpi_name: str
    category: str                   # bot | inventory | orders | station
    chart_type: str                 # stat | bar chart | pie | table | time series | state timeline | bar gauge
    logic: str                      # Human-readable explanation
    query: str                      # Raw SQL with Grafana variables
    requires_location: bool
    requires_time_range: bool
    tables_used: List[str]
    keywords: List[str] = field(default_factory=list)
    user_queries: List[str] = field(default_factory=list)  # Natural-language questions from the registry


@dataclass
class KPIMatch:
    """Result when a user question is matched to a KPI."""
    kpi_id: str
    kpi_name: str
    category: str
    chart_type: str
    logic: str
    sql: str                        # Ready-to-execute SQL (parameters substituted)
    raw_query: str                  # Original query with Grafana variables
    match_score: float              # 0.0 – 1.0
    tables_used: List[str]
    requires_location: bool
    requires_time_range: bool
    parameters_applied: Dict[str, str] = field(default_factory=dict)


# ============================================================
# Keyword extraction helpers
# ============================================================

# Common filler words to ignore when comparing user_queries
_FILLER_SET = frozenset({
    "what", "is", "the", "a", "an", "are", "how", "many", "much", "show",
    "me", "give", "display", "get", "for", "of", "in", "at", "to", "and",
    "or", "on", "by", "was", "were", "did", "do", "does", "with", "across",
    "each", "overall", "selected", "time", "range", "period", "during",
})

# Category keywords that help boost matching
CATEGORY_KEYWORDS = {
    "bot": ["bot", "bots", "robot", "robots", "active bot", "inactive bot",
            "alarm", "alarms", "downtime", "home time", "battery",
            "obstacle", "gearbox", "calibration"],
    "inventory": ["inventory", "bin", "bins", "sku", "skus", "segment",
                  "utilisation", "utilization", "storage", "location",
                  "quantity", "weight", "volume", "capacity", "blocked",
                  "reserved", "expiry", "category", "audit"],
    "orders": ["order", "orders", "wave", "waves", "pick", "put",
               "olbp", "qpl", "qbp", "obp", "ops", "ipp",
               "lpn", "lpns", "eaches", "stock adjustment",
               "parent order", "child order", "completion time"],
    "station": ["station", "stations", "station-wise", "stationwise",
                "productive", "idle", "utilization", "no-read",
                "presentation", "bin presentation"],
}

# Synonyms to expand matching
SYNONYMS = {
    "active": ["active", "enabled", "running", "online", "working"],
    "inactive": ["inactive", "disabled", "idle", "offline", "not working"],
    "alarm": ["alarm", "alarms", "alert", "alerts", "warning", "error"],
    "downtime": ["downtime", "down time", "offline time", "unavailable"],
    "utilisation": ["utilisation", "utilization", "usage", "used"],
    "bin": ["bin", "bins", "container", "storage bin"],
    "wave": ["wave", "waves", "batch", "batches"],
    "station": ["station", "stations", "workstation", "work station"],
    "lpn": ["lpn", "lpns", "license plate", "license plate number"],
    "ipp": ["ipp", "items per pick", "picks per hour", "pick rate"],
    "trend": ["trend", "over time", "daily", "hourly", "progression", "history"],
}


def _extract_keywords(kpi_name: str, logic: str, category: str,
                      user_queries: Optional[List[str]] = None) -> List[str]:
    """Extract searchable keywords from KPI name + logic + user_queries."""
    uq_text = " ".join(user_queries or [])
    text = f"{kpi_name} {logic} {uq_text}".lower()
    # Remove special characters
    text = re.sub(r'[^a-z0-9\s\-]', ' ', text)
    words = text.split()
    # Remove very short/common words
    stopwords = {"the", "a", "an", "is", "in", "at", "of", "for", "to",
                 "and", "or", "by", "it", "this", "that", "are", "was",
                 "were", "been", "be", "has", "had", "do", "did", "will",
                 "can", "may", "not", "with", "from", "each", "how", "many",
                 "which", "what", "show", "get", "all"}
    keywords = [w for w in words if len(w) > 1 and w not in stopwords]
    keywords.append(category)
    return list(set(keywords))


# ============================================================
# Main resolver class
# ============================================================

class DashboardKPIResolver:
    """
    Resolves user questions to pre-built dashboard KPI queries.

    Usage:
        resolver = DashboardKPIResolver()
        match = resolver.resolve(
            question="how many bots are active in faruknagar?",
            tenant_value="frk",
            time_from="2026-03-01",
            time_to="2026-03-24"
        )
        if match:
            # match.sql is ready to execute
            # match.chart_type tells the frontend how to render
    """

    # ── Thresholds ──
    # Hybrid score = 0.65 * embedding_similarity + 0.35 * keyword_score
    # Only scores above this are considered valid matches.
    MATCH_THRESHOLD = 0.40

    # If embedding API is unavailable, use keyword-only with a stricter gate
    KEYWORD_ONLY_THRESHOLD = 0.55

    # Weight split for hybrid scoring
    EMBEDDING_WEIGHT = 0.65
    KEYWORD_WEIGHT = 0.35

    def __init__(self, registry_path: Optional[str] = None):
        if registry_path is None:
            # Try multiple fallback paths
            candidates = [
                Path(__file__).parent.parent.parent.parent.parent
                / "data" / "dashboard-data" / "kpi_registry.json",
                Path(__file__).parent.parent.parent.parent
                / "data" / "dashboard-data" / "kpi_registry.json",
            ]
            for p in candidates:
                if p.exists():
                    registry_path = str(p)
                    break
            if registry_path is None:
                registry_path = str(candidates[0])

        self.kpis: List[KPIEntry] = []
        self._load_registry(registry_path)

        # ── Centralised embeddings folder ──
        from app.core.config import settings
        self._embeddings_dir = settings.EMBEDDINGS_DIR
        self._embeddings_dir.mkdir(parents=True, exist_ok=True)
        self._embeddings_path = self._embeddings_dir / "kpi_embeddings.npz"

        # ── Pre-compute KPI embeddings for semantic matching ──
        self.kpi_embeddings: Dict[str, np.ndarray] = {}
        self._embeddings_available = False
        self._init_embeddings()

        logger.info(
            f"📊 DashboardKPIResolver loaded {len(self.kpis)} KPIs "
            f"(embeddings={'✅' if self._embeddings_available else '❌ keyword-only'})"
        )

    def _load_registry(self, path: str):
        """Load KPI registry from JSON."""
        try:
            with open(path, "r", encoding="utf-8") as f:
                raw = json.load(f)

            for item in raw:
                kpi = KPIEntry(
                    id=item["id"],
                    kpi_name=item["kpi_name"],
                    category=item["category"],
                    chart_type=item["chart_type"],
                    logic=item.get("logic", ""),
                    query=item["query"],
                    requires_location=item.get("requires_location", False),
                    requires_time_range=item.get("requires_time_range", False),
                    tables_used=item.get("tables_used", []),
                    user_queries=item.get("user_queries", []),
                )
                kpi.keywords = _extract_keywords(
                    kpi.kpi_name, kpi.logic, kpi.category, kpi.user_queries
                )
                self.kpis.append(kpi)

        except Exception as e:
            logger.error(f"Failed to load KPI registry from {path}: {e}")

    # ----------------------------------------------------------
    # EMBEDDING INITIALIZATION
    # ----------------------------------------------------------

    def _build_kpi_text(self, kpi: KPIEntry) -> str:
        """Build a rich text representation of a KPI for embedding."""
        uq_text = "\n".join(kpi.user_queries[:5]) if kpi.user_queries else ""
        return (
            f"KPI: {kpi.kpi_name}\n"
            f"Category: {kpi.category}\n"
            f"Description: {kpi.logic}\n"
            f"Tables: {', '.join(kpi.tables_used)}\n"
            f"Chart: {kpi.chart_type}\n"
            f"Example questions: {uq_text}"
        )

    def _init_embeddings(self):
        """
        Load cached KPI embeddings from disk, or compute fresh ones via
        OpenAI and persist them to data/embeddings/kpi_embeddings.npz.
        Falls back to keyword-only matching if unavailable.
        """
        # 1. Try loading from disk
        if self._load_embeddings_from_disk():
            return

        # 2. Compute fresh embeddings via OpenAI
        try:
            from app.services.embedding_service import embedding_service

            texts = [self._build_kpi_text(kpi) for kpi in self.kpis]
            embeddings = embedding_service.embed_batch(texts)

            for kpi, emb in zip(self.kpis, embeddings):
                self.kpi_embeddings[kpi.id] = emb

            self._embeddings_available = True
            logger.info(f"✅ KPI embeddings computed for {len(self.kpis)} KPIs")

            # Persist to disk
            self._save_embeddings_to_disk()

        except Exception as e:
            logger.warning(
                f"⚠️ KPI embedding init failed ({e}). "
                f"Falling back to keyword-only matching (threshold={self.KEYWORD_ONLY_THRESHOLD})"
            )
            self._embeddings_available = False

    def _load_embeddings_from_disk(self) -> bool:
        """Load saved KPI embeddings from data/embeddings/kpi_embeddings.npz."""
        if not self._embeddings_path.exists():
            return False

        try:
            data = np.load(str(self._embeddings_path), allow_pickle=True)
            ids = data["ids"].tolist()
            matrix = data["matrix"]

            # Validate: must match current registry IDs
            kpi_id_set = {kpi.id for kpi in self.kpis}
            if set(ids) != kpi_id_set:
                logger.info("📊 KPI registry changed — rebuilding embeddings")
                return False

            for kpi_id, emb in zip(ids, matrix):
                self.kpi_embeddings[kpi_id] = emb

            self._embeddings_available = True
            logger.info(f"💾 Restored {len(ids)} KPI embeddings from disk cache")
            return True

        except Exception as e:
            logger.warning(f"⚠️ Could not load KPI embeddings from disk: {e}")
            return False

    def _save_embeddings_to_disk(self):
        """Persist KPI embeddings to data/embeddings/kpi_embeddings.npz."""
        if not self.kpi_embeddings:
            return

        try:
            ids = list(self.kpi_embeddings.keys())
            matrix = np.array([self.kpi_embeddings[k] for k in ids])

            np.savez_compressed(
                str(self._embeddings_path),
                ids=np.array(ids, dtype=object),
                matrix=matrix,
            )
            logger.info(f"💾 Saved {len(ids)} KPI embeddings to {self._embeddings_path}")

        except Exception as e:
            logger.warning(f"⚠️ Could not save KPI embeddings: {e}")

    def _embedding_similarity(self, question: str, kpi: KPIEntry) -> float:
        """
        Compute cosine similarity between the user question and a KPI.
        Returns 0.0 if embeddings are unavailable.
        """
        if not self._embeddings_available:
            return 0.0

        kpi_emb = self.kpi_embeddings.get(kpi.id)
        if kpi_emb is None:
            return 0.0

        try:
            from app.services.embedding_service import embedding_service
            q_emb = embedding_service.embed(question)
            # Both vectors are already L2-normalized by EmbeddingService
            return float(np.dot(q_emb, kpi_emb))
        except Exception:
            return 0.0

    # ----------------------------------------------------------
    # MATCHING
    # ----------------------------------------------------------

    def _score_match(self, question: str, kpi: KPIEntry) -> float:
        """
        Keyword-based score for a user question vs a KPI.
        Returns 0.0 – 1.0.  Used alone when embeddings are unavailable,
        otherwise blended with the embedding score.
        """
        q_lower = question.lower()

        # ── CRITICAL: normalise underscores → spaces ──
        # User may type ACTIVE_BOTS or BIN_PRESENTATION which should
        # match keywords like "active", "bots", "bin presentation"
        q_normalized = q_lower.replace('_', ' ')
        q_words = set(re.sub(r'[^a-z0-9\s]', ' ', q_normalized).split())

        # Expand question words with synonyms
        expanded_q = set(q_words)
        for word in list(q_words):
            for syn_key, syn_list in SYNONYMS.items():
                if word in syn_list:
                    expanded_q.update(syn_list)

        kpi_keywords = set(kpi.keywords)

        if not kpi_keywords:
            return 0.0

        # 1. Keyword overlap (Jaccard-like)
        intersection = expanded_q & kpi_keywords
        keyword_score = len(intersection) / max(len(kpi_keywords), 1)

        # 2. KPI name full-phrase match (strongest signal)
        #    e.g., question "show active bots" matches KPI "Active Bots"
        name_lower = kpi.kpi_name.lower().strip()
        name_normalized = re.sub(r'[^a-z0-9\s]', ' ', name_lower)
        name_words = set(name_normalized.split())
        stop_words = {"per", "vs", "by", "wise"}

        name_bonus = 0.0
        # Full phrase match: "active bots" in normalized question
        if name_normalized.strip() in q_normalized:
            name_bonus = 0.5
        else:
            # Word-level overlap
            meaningful = name_words - stop_words
            if meaningful:
                overlap = len(expanded_q & meaningful)
                name_bonus = 0.5 * (overlap / len(meaningful))

        # 2b. user_queries phrase match — reward when user question closely
        #     matches one of the known natural-language phrasings
        uq_bonus = 0.0
        for uq in kpi.user_queries:
            uq_norm = re.sub(r'[^a-z0-9\s]', ' ', uq.lower())
            uq_words = set(uq_norm.split()) - stop_words - _FILLER_SET
            if uq_words and q_words:
                overlap_uq = len(expanded_q & uq_words)
                ratio = overlap_uq / max(len(uq_words), 1)
                if ratio > uq_bonus:
                    uq_bonus = ratio
        uq_bonus = min(uq_bonus * 0.5, 0.45)  # cap contribution

        # 3. Category boost — if question mentions the category
        category_boost = 0.0
        cat_kws = CATEGORY_KEYWORDS.get(kpi.category, [])
        for ckw in cat_kws:
            if ckw in q_normalized:
                category_boost = 0.15
                break

        # 4. Chart-type / dashboard keyword boost
        dashboard_boost = 0.0
        dashboard_keywords = ["kpi", "dashboard", "chart", "grafana", "metric",
                              "analytics", "visualization", "trend", "report"]
        if any(dkw in q_normalized for dkw in dashboard_keywords):
            dashboard_boost = 0.1

        # 5. Output column match — user may reference column names
        col_bonus = 0.0
        if kpi.tables_used:
            for t in kpi.tables_used:
                if t.lower() in q_normalized:
                    col_bonus += 0.03
            col_bonus = min(0.1, col_bonus)

        score = name_bonus + uq_bonus + (keyword_score * 0.3) + category_boost + dashboard_boost + col_bonus
        return min(score, 1.0)

    def _hybrid_score(self, question: str, kpi: KPIEntry,
                      question_embedding: Optional[np.ndarray] = None) -> float:
        """
        Combine embedding similarity + keyword score for more precise matching.

        Hybrid  = EMBEDDING_WEIGHT * cosine_sim  +  KEYWORD_WEIGHT * keyword_score
        When embeddings are unavailable, returns keyword-only score.
        """
        keyword_score = self._score_match(question, kpi)

        if not self._embeddings_available or question_embedding is None:
            return keyword_score

        kpi_emb = self.kpi_embeddings.get(kpi.id)
        if kpi_emb is None:
            return keyword_score

        embedding_score = float(np.dot(question_embedding, kpi_emb))
        hybrid = (self.EMBEDDING_WEIGHT * embedding_score
                  + self.KEYWORD_WEIGHT * keyword_score)
        return hybrid

    def _get_question_embedding(self, question: str) -> Optional[np.ndarray]:
        """Embed the user question.  Returns None on failure."""
        if not self._embeddings_available:
            return None
        try:
            from app.services.embedding_service import embedding_service
            return embedding_service.embed(question)
        except Exception as e:
            logger.warning(f"⚠️ Question embedding failed: {e}")
            return None

    def resolve(
        self,
        question: str,
        tenant_values: Optional[List[str]] = None,
        time_from: Optional[str] = None,
        time_to: Optional[str] = None,
        category_filter: Optional[str] = None,
        all_sites: bool = False,
        top_k: int = 1,
    ) -> Optional[KPIMatch]:
        """
        Try to match the question to a dashboard KPI.

        Scoring:
            - Embedding-available:  hybrid = 0.65*cosine + 0.35*keyword
            - Embedding-unavailable: keyword-only (stricter threshold)

        Args:
            question: Natural language user question
            tenant_values: List of tenant IDs (e.g., ["frk"], ["frk","shakti"])
            time_from: Start date/datetime string (default: today - 1 day)
            time_to: End date/datetime string (default: now)
            category_filter: Restrict to a category (bot/inventory/orders/station)
            all_sites: If True, remove location filters entirely
            top_k: Return top-k matches (only the best is returned by default)

        Returns:
            KPIMatch if a match is found above threshold, else None
        """
        # Backward compat: accept single string
        if isinstance(tenant_values, str):
            tenant_values = [tenant_values]

        candidates = self.kpis
        if category_filter:
            candidates = [k for k in candidates if k.category == category_filter]

        # ── Strip tenant/time noise for scoring only ──
        # Original `question` is preserved for parameter substitution.
        match_question = strip_matching_noise(question)
        logger.debug(f"📊 KPI match_question: '{match_question}' (raw: '{question}')")

        # Embed the *cleaned* question once (reused for all candidates)
        q_embedding = self._get_question_embedding(match_question)

        # Choose threshold based on available scoring method
        threshold = (self.MATCH_THRESHOLD if self._embeddings_available
                     else self.KEYWORD_ONLY_THRESHOLD)

        scored = []
        for kpi in candidates:
            score = self._hybrid_score(match_question, kpi, q_embedding)
            if score >= threshold:
                scored.append((score, kpi))

        if not scored:
            return None

        scored.sort(key=lambda x: x[0], reverse=True)
        best_score, best_kpi = scored[0]

        # Log scoring breakdown for diagnostics
        if q_embedding is not None:
            kw_only = self._score_match(match_question, best_kpi)
            emb_only = float(np.dot(q_embedding, self.kpi_embeddings.get(best_kpi.id, np.zeros(1))))
            logger.info(
                f"📊 KPI scoring: keyword={kw_only:.3f}, embedding={emb_only:.3f}, "
                f"hybrid={best_score:.3f} (threshold={threshold})"
            )

        # Substitute Grafana variables
        sql, params_applied = self._substitute_params(
            best_kpi.query, tenant_values, time_from, time_to, all_sites,
            question=question,
        )

        match = KPIMatch(
            kpi_id=best_kpi.id,
            kpi_name=best_kpi.kpi_name,
            category=best_kpi.category,
            chart_type=best_kpi.chart_type,
            logic=best_kpi.logic,
            sql=sql,
            raw_query=best_kpi.query,
            match_score=best_score,
            tables_used=best_kpi.tables_used,
            requires_location=best_kpi.requires_location,
            requires_time_range=best_kpi.requires_time_range,
            parameters_applied=params_applied,
        )

        logger.info(
            f"📊 KPI matched: '{best_kpi.kpi_name}' "
            f"(score={best_score:.2f}, chart={best_kpi.chart_type}, "
            f"category={best_kpi.category})"
        )

        return match

    def resolve_top_k(
        self,
        question: str,
        tenant_values: Optional[List[str]] = None,
        time_from: Optional[str] = None,
        time_to: Optional[str] = None,
        all_sites: bool = False,
        top_k: int = 3,
    ) -> List[KPIMatch]:
        """Return top-k KPI matches (for suggestion UI)."""
        if isinstance(tenant_values, str):
            tenant_values = [tenant_values]

        # ── Strip noise for scoring ──
        match_question = strip_matching_noise(question)
        q_embedding = self._get_question_embedding(match_question)
        threshold = (self.MATCH_THRESHOLD if self._embeddings_available
                     else self.KEYWORD_ONLY_THRESHOLD)

        scored = []
        for kpi in self.kpis:
            score = self._hybrid_score(match_question, kpi, q_embedding)
            if score >= threshold:
                scored.append((score, kpi))

        scored.sort(key=lambda x: x[0], reverse=True)

        results = []
        for score, kpi in scored[:top_k]:
            sql, params = self._substitute_params(
                kpi.query, tenant_values, time_from, time_to, all_sites,
                question=question,
            )
            results.append(KPIMatch(
                kpi_id=kpi.id,
                kpi_name=kpi.kpi_name,
                category=kpi.category,
                chart_type=kpi.chart_type,
                logic=kpi.logic,
                sql=sql,
                raw_query=kpi.query,
                match_score=score,
                tables_used=kpi.tables_used,
                requires_location=kpi.requires_location,
                requires_time_range=kpi.requires_time_range,
                parameters_applied=params,
            ))

        return results

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

        # Default: 1 day (Grafana default)
        return timedelta(days=1)

    # ----------------------------------------------------------
    # PARAMETER SUBSTITUTION
    # ----------------------------------------------------------

    def _substitute_params(
        self, query: str,
        tenant_values: Optional[List[str]],
        time_from: Optional[str],
        time_to: Optional[str],
        all_sites: bool = False,
        question: str = "",
    ) -> tuple:
        """
        Replace Grafana template variables with actual values.

        Supports:
            - Single tenant: IN ('frk') or = 'frk'
            - Multi tenant:  IN ('frk','shakti')
            - All sites:     removes location filter entirely

        Grafana patterns:
            $location / IN ($location) → actual host-location value(s)
            $__timeFrom() → start datetime
            $__timeTo()   → end datetime
            $Category     → category value or ALL (wildcard)
        """
        params = {}
        sql = query

        # 1. Location substitution
        if all_sites or not tenant_values:
            # All sites or no tenant — remove location filter entirely
            # Handle "AND <alias.>`host-location` IN/= $location"
            sql = re.sub(
                r"AND\s+\w*\.?[`]?host-location[`]?\s*(IN\s*\(\s*\$location\s*\)|=\s*'?\$location'?)",
                "/* all sites — no location filter */",
                sql, flags=re.IGNORECASE
            )
            # Handle "WHERE <alias.>`host-location` IN/= $location AND ..."
            sql = re.sub(
                r"WHERE\s+\w*\.?[`]?host-location[`]?\s*(IN\s*\(\s*\$location\s*\)|=\s*'?\$location'?)\s*AND",
                "WHERE",
                sql, flags=re.IGNORECASE
            )
            # Handle "WHERE <alias.>`host-location` IN/= $location" at end of clause
            sql = re.sub(
                r"WHERE\s+\w*\.?[`]?host-location[`]?\s*(IN\s*\(\s*\$location\s*\)|=\s*'?\$location'?)\s*$",
                "",
                sql, flags=re.IGNORECASE | re.MULTILINE
            )
            params["location"] = "all_sites" if all_sites else "none"
        elif len(tenant_values) == 1:
            # Single tenant
            val = tenant_values[0]
            sql = re.sub(
                r"IN\s*\(\s*\$location\s*\)",
                f"IN ('{val}')",
                sql, flags=re.IGNORECASE
            )
            sql = sql.replace("'$location'", f"'{val}'")
            sql = sql.replace("$location", f"'{val}'")
            params["location"] = val
        else:
            # Multiple tenants
            in_list = ", ".join(f"'{v}'" for v in tenant_values)
            sql = re.sub(
                r"IN\s*\(\s*\$location\s*\)",
                f"IN ({in_list})",
                sql, flags=re.IGNORECASE
            )
            # Convert = '$location' to IN (...) for multi-tenant
            sql = re.sub(
                r"=\s*'?\$location'?",
                f"IN ({in_list})",
                sql, flags=re.IGNORECASE
            )
            params["location"] = tenant_values

        # 2. Time range substitution — parse from question if no explicit range
        now = datetime.now()
        if not time_from:
            delta = self._parse_time_range(question) if question else timedelta(days=1)
            if delta.total_seconds() == 0:
                t_from = now.strftime("%Y-%m-%d 00:00:00")
            else:
                t_from = (now - delta).strftime("%Y-%m-%d %H:%M:%S")
        else:
            t_from = time_from
        if not time_to:
            t_to = now.strftime("%Y-%m-%d %H:%M:%S")
        else:
            t_to = time_to

        # Replace Grafana time functions
        # $__timeFilter(column) → column BETWEEN 'from' AND 'to'
        sql = re.sub(
            r"\$__timeFilter\(([^)]+)\)",
            rf"\1 BETWEEN '{t_from}' AND '{t_to}'",
            sql, flags=re.IGNORECASE
        )
        # $__timeFrom() - INTERVAL 1 DAY → we just use the from time directly
        sql = re.sub(
            r"\$__timeFrom\(\)\s*-\s*INTERVAL\s+\d+\s+\w+",
            f"'{t_from}'",
            sql, flags=re.IGNORECASE
        )
        sql = sql.replace("$__timeFrom()", f"'{t_from}'")
        sql = sql.replace("$__timeTo()", f"'{t_to}'")

        # ── Params CTE pattern (7 KPIs: kpi_062–064, 076–077, 081–082) ──
        # TIMESTAMP('2026-01-03 00:00:00') AS from_ts  →  actual computed from
        # TIMESTAMP('2026-01-03 23:59:59') AS to_ts    →  actual computed to
        sql = re.sub(
            r"TIMESTAMP\s*\(\s*'[^']+'\s*\)\s*(AS\s+from_ts)",
            f"TIMESTAMP('{t_from}') \\1",
            sql, flags=re.IGNORECASE,
        )
        # to_ts should be end-of-day 23:59:59 for the Params CTE pattern
        t_to_eod = t_to.split(" ")[0] + " 23:59:59"
        sql = re.sub(
            r"TIMESTAMP\s*\(\s*'[^']+'\s*\)\s*(AS\s+to_ts)",
            f"TIMESTAMP('{t_to_eod}') \\1",
            sql, flags=re.IGNORECASE,
        )

        # ── CAST date equality pattern (31 KPIs: kpi_048–085) ──
        # CAST(col AS DATE) = '2026-01-03'  →  CAST(col AS DATE) BETWEEN 'from' AND 'to'
        # These KPIs use single-day snapshots; for multi-day ranges we convert
        # = 'hardcoded_date' to BETWEEN '{from_date}' AND '{to_date}'
        t_from_date = t_from.split(" ")[0]   # '2026-03-24'
        t_to_date = t_to.split(" ")[0]       # '2026-03-27'
        sql = re.sub(
            r"(CAST\s*\([^)]+AS\s+DATE\s*\))\s*=?\s*'(\d{4}-\d{2}-\d{2})'",
            rf"\1 BETWEEN '{t_from_date}' AND '{t_to_date}'",
            sql, flags=re.IGNORECASE,
        )

        params["time_from"] = t_from
        params["time_to"] = t_to

        # 3. $Category substitution — remove filter or replace with '%'
        if "$Category" in sql:
            sql = re.sub(
                r"AND\s+\w*\.?`?CATEGORY`?\s*=\s*'\$Category'",
                "/* all categories */",
                sql, flags=re.IGNORECASE
            )
            sql = sql.replace("$Category", "%")
            params["category"] = "all"

        # 4. ${bot_id:sqlstring} — no bot_id extraction yet, remove filter
        if "${bot_id:sqlstring}" in sql:
            sql = re.sub(
                r"AND\s+\w*\.?\w+\s+IN\s*\(\$\{bot_id:sqlstring\}\)",
                "/* all bots */",
                sql, flags=re.IGNORECASE
            )
            sql = sql.replace("${bot_id:sqlstring}", "'%'")
            params["bot_id"] = "all"

        # 5. Catch any remaining ${var:sqlstring} patterns — replace with $var
        sql = re.sub(r'\$\{(\w+):sqlstring\}', r"$\1", sql)

        return sql, params

    # ----------------------------------------------------------
    # UTILITY
    # ----------------------------------------------------------

    def list_kpis(self, category: Optional[str] = None) -> List[Dict[str, Any]]:
        """List available KPIs (for API/UI)."""
        kpis = self.kpis
        if category:
            kpis = [k for k in kpis if k.category == category]

        return [
            {
                "id": k.id,
                "kpi_name": k.kpi_name,
                "category": k.category,
                "chart_type": k.chart_type,
                "logic": k.logic[:200],
                "requires_location": k.requires_location,
                "requires_time_range": k.requires_time_range,
            }
            for k in kpis
        ]

    def get_categories(self) -> List[str]:
        """Return distinct KPI categories."""
        return sorted(set(k.category for k in self.kpis))
