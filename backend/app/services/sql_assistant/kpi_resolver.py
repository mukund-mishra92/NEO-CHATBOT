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
from typing import Optional, List, Dict, Any, Tuple, Union
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
    "each", "overall", "selected", "range", "period", "during",
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
# NOTE: These must be BIDIRECTIONAL — the SynonymResolver in synonym_resolver.py
# maps user words to schema terms (e.g. sku→article) BEFORE the KPI resolver
# sees the question.  The groups below ensure the *scorer* expands those
# schema terms back so keywords like 'sku' in the registry still match.
SYNONYMS = {
    "active": ["active", "enabled", "running", "online", "working"],
    "inactive": ["inactive", "disabled", "idle", "offline", "not working"],
    "alarm": ["alarm", "alarms", "alert", "alerts", "warning", "error"],
    "downtime": ["downtime", "down time", "offline time", "unavailable"],
    "utilisation": ["utilisation", "utilization", "usage", "used"],
    "bin": ["bin", "bins", "container", "storage bin"],
    "wave": ["wave", "waves", "batch", "batches"],
    "station": ["station", "stations", "workstation", "work station"],
    "lpn": ["lpn", "lpns", "license plate", "license plate number", "carton", "cartons"],
    "ipp": ["ipp", "items per pick", "picks per hour", "pick rate", "pick speed"],
    "trend": ["trend", "over time", "daily", "hourly", "progression", "history"],
    "eaches": ["eaches", "picked quantity", "items picked", "total picked"],
    "picked": ["picked", "eaches", "items picked"],
    # ── Bidirectional groups for SynonymResolver outputs ──
    # SynonymResolver maps sku→article, product→article, item→article.
    # KPI keywords still use 'sku'/'skus', so the scorer must expand
    # 'article' back to the full group.
    "article": ["article", "articles", "sku", "skus", "product", "products", "item", "items"],
    "sku":     ["sku", "skus", "article", "articles", "product", "products", "item", "items"],
    # SynonymResolver maps robot→bot
    "bot":   ["bot", "bots", "robot", "robots"],
    "robot": ["robot", "robots", "bot", "bots"],
    # SynonymResolver maps stock→inventory
    "inventory": ["inventory", "stock", "stocks"],
    "stock":     ["stock", "stocks", "inventory"],
    # SynonymResolver maps failure/fault→error
    "error":   ["error", "errors", "failure", "failures", "fault", "faults"],
    "failure": ["failure", "failures", "error", "errors", "fault", "faults"],
    # SynonymResolver maps putaway/put-away→put
    "put":     ["put", "putaway", "put-away"],
    "putaway": ["putaway", "put-away", "put"],
}

# Warehouse acronym ↔ full-phrase expansions.
# When the user says one form, the scorer should also try the other.
ACRONYM_EXPANSIONS = {
    "olbp": ["order lines per bin", "lines per bin"],
    "qpl": ["quantity per line", "qty per line"],
    "qbp": ["quantity per bin", "qty per bin"],
    "obp": ["orders per bin"],
    "ops": ["orders per sku", "orders persku"],
    "ipp": ["items per pick", "items per pick per hour"],
    "lpn": ["license plate number", "carton"],
    # Reverse: natural phrase → acronym
    "order lines per bin": ["olbp"],
    "quantity per line": ["qpl"],
    "quantity per bin": ["qbp"],
    "orders per bin": ["obp"],
    "orders per sku": ["ops"],
    "items per pick": ["ipp"],
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
# COUNT vs METRIC intent helpers  (Case-1 fix)
# ============================================================

# Phrases that signal the user wants a raw count / number, NOT a rate/percentage.
_COUNT_INTENT_PHRASES = (
    "how many", "number of", "count of", "total number",
    "no. of", "no of", "nos of", "give me count",
    "what is the count", "how much stock", "how many bins",
    "how many bots", "how many orders", "how many skus",
)

# Phrases that signal the user wants a rate/percentage/utilization figure.
_PCT_INTENT_PHRASES = (
    "percent", "utilization", "utilisation", "percentage",
    "occupancy", "how full", "how utilized", "how utilised",
    "usage rate", "fill rate",
)

# Substrings in a KPI name / logic that indicate it returns a % / rate / ratio.
_METRIC_KPI_INDICATORS = (
    "utilization", "utilisation", "percent", "percentage",
    "rate", "ratio", "occupancy",
)


# ============================================================
# Schema / meta-query detection
# ============================================================
# Patterns that indicate the user is asking about database structure,
# not business data.  Table names (e.g. "bot_master") contain domain
# words that can drive false-positive keyword overlap with KPIs.

_SCHEMA_PATTERNS: List[re.Pattern] = [
    re.compile(p, re.IGNORECASE) for p in (
        # Column / table introspection
        r"\bcolumns?\b.*\btable\b",
        r"\btable\b.*\bcolumns?\b",
        r"\bdescribe\b.*\btable\b",
        r"\bschema\b.*\btable\b",
        r"\bstructure\b.*\btable\b",
        r"\bfields?\b.*\btable\b",
        r"\blist\b.*\btables?\b",
        r"\bshow\b.*\btables?\b.*\bdatabase\b",
        # DDL / DML operations
        r"\b(drop|alter|create|truncate|delete\s+from|insert\s+into|update\b.*\bset)\b",
        # Explicit table references with _master / _log / _history suffix
        r"\b\w+_(master|log|history|detail|mapping)\b.*\b(column|field|schema|structure)\b",
    )
]


def _is_schema_query(question: str) -> bool:
    """Return True if the question is about database structure, not business data.

    Examples:
        "show all columns in bot_master table"    → True
        "describe task_master table"              → True
        "how many bots are active?"               → False
        "total bins in inventory"                 → False
    """
    return any(pat.search(question) for pat in _SCHEMA_PATTERNS)


# ============================================================
# Entity-lookup guard
# ============================================================
# Entity IDs (BOT-0001, BIN-0324, STATION-0003, …) contain domain
# words like "bot", "bin", "station" that inflate category and
# name-overlap scores.  When the user asks about a *specific*
# entity's properties (location, IP, state, tower-side) there is
# no KPI to serve the answer — those are row-level SQL lookups.

_ENTITY_ID_RE = re.compile(
    r'\b(?:BOT|BIN|STATION|ST|WAVE|ORD|ORDER)[- _]?\d{2,6}\b',
    re.IGNORECASE,
)

# KPI-intent words — when present alongside an entity ID the query is
# still a legitimate KPI request  (e.g. "alarms for bot 1 today").
_KPI_INTENT_RE = re.compile(
    r'\b(?:'
    r'active|inactive|downtime|uptime|utiliz\w*'
    r'|alarm|alarms|trend|average|percentage|ratio|blocked'
    r'|dashboard|chart|metric|grafana|kpi|sitewise|ipp|eaches'
    r'|how\s+many|total\s+\w+'
    r'|items?\s+per|bins?\s+per\s+hour|orders?\s+per'
    r'|per\s+(?:hour|day|station|bot|pick|put|lpn|order|line|bin)'
    r'|wave\s+(?:duration|time)'
    r'|site[\s-]wise|location[\s-]wise'
    r')\b'
    r'|%',
    re.IGNORECASE,
)

# Lookup-signal phrases — property / state lookups, NOT aggregate metrics.
_LOOKUP_SIGNAL_RE = re.compile(
    r'(?:'
    r'where\s+is|where\s+are|where\s+does|\blocate\b'
    r'|location\s+of|position\s+of|\bcoordinates?\b'
    r'|ip\s+of|ip\s+address|what\s+is\s+the\s+ip|what\s+port'
    r'|\bcounters?\b|\bincreasing\b|\bdecreasing\b'
    r'|tower[\s_]?side|tower[\s_]?number|which\s+side|what\s+side'
    r'|left\s+(?:or|and)\s+right'
    r'|aisle[\s_]?number|which\s+aisle|which\s+tower'
    r'|\bgridx\b|\bgridy\b|\bgridz\b'
    r'|charging\s+point|charging\s+station|not\s+going'
    r'|previous\s+bot|current\s+bot|last\s+bot'
    r'|current\s+task|current\s+state|current\s+location'
    r'|sim[\s_]?port|\bconfig\w*\b'
    r'|details?\s+of|info\s+(?:about|of|for)'
    r'|status\s+of|state\s+of'
    r'|what\s+(?:bins?|is\s+in|does)\s'
    r')',
    re.IGNORECASE,
)


def _is_entity_lookup_query(
    question: str,
    *,
    bot_id: Optional[str] = None,
    station_id: Optional[str] = None,
    bin_id: Optional[str] = None,
    wave_id: Optional[str] = None,
    order_id: Optional[str] = None,
) -> bool:
    """Return True if the query is a property / state lookup for a specific entity.

    Entity-lookup examples (→ True):
        "where is BOT-0001 in frk"
        "what is the IP of BOT-0027 in chennai"
        "are the counters of BOT-0027 increasing"
        "where is BIN-0324 in frk"
        "tower side of BOT-0001"

    KPI-with-entity examples (→ False):
        "bot active vs inactive time for bot 1 in frk today"
        "alarms for bot 27 today"
        "station 3 utilization in frk"
    """
    # 1. Must have at least one resolved entity ID
    has_entity = any([bot_id, station_id, bin_id, wave_id, order_id])
    if not has_entity:
        has_entity = bool(_ENTITY_ID_RE.search(question))
    if not has_entity:
        return False

    q_lower = question.lower()

    # 2. KPI-intent override — metric / aggregate words mean "still a KPI"
    if _KPI_INTENT_RE.search(q_lower):
        return False

    # 3. Lookup-signal detected → entity property lookup
    if _LOOKUP_SIGNAL_RE.search(q_lower):
        return True

    # 4. Residual heuristic: strip noise + entity IDs; if almost nothing
    #    meaningful remains the user typed only an entity ref.
    stripped = _ENTITY_ID_RE.sub('', strip_matching_noise(question)).strip()
    stripped = re.sub(r'\s+', ' ', stripped).strip()
    remaining = [w for w in stripped.split() if len(w) > 1]
    if len(remaining) <= 1:
        return True

    return False


def _has_count_intent(question: str) -> bool:
    """
    Return True when the user is explicitly asking for a COUNT / number,
    and there is NO percentage or utilization intent in the question.

    Example:  "how many bins are used in bangalore" → True
    Example:  "bin utilization in bangalore"         → False
    Example:  "what percent of bins are in use"      → False
    """
    q = question.lower()
    has_count = any(p in q for p in _COUNT_INTENT_PHRASES)
    has_pct   = any(p in q for p in _PCT_INTENT_PHRASES)
    return has_count and not has_pct


def _kpi_returns_metric(kpi: KPIEntry) -> bool:
    """
    Return True if the KPI computes a percentage, rate, or ratio
    rather than a plain count / total.
    """
    text = (kpi.kpi_name + " " + kpi.logic).lower()
    return any(indicator in text for indicator in _METRIC_KPI_INDICATORS)


def _has_any_phrase(question: str, phrases: Tuple[str, ...]) -> bool:
    """Return True when any phrase appears in the question with word boundaries."""
    normalised = question.replace("_", " ").replace("-", " ")
    for phrase in phrases:
        phrase_normalised = phrase.replace("-", " ")
        if (re.search(rf"\b{re.escape(phrase)}\b", question)
                or re.search(rf"\b{re.escape(phrase_normalised)}\b", normalised)):
            return True
    return False


_STATION_SCOPE_PHRASES = (
    "station-wise", "station wise", "per station", "by station",
    "each station", "for each station", "at each station",
)

_IPP_HINT_PHRASES = (
    "ipp", "items per pick",
)

_PICK_HINT_PHRASES = (
    "pick", "picking",
)

_PUT_HINT_PHRASES = (
    "put", "putting",
)

_WAVE_TIME_HINT_PHRASES = (
    "wave time", "wave duration", "wave hours", "waves running",
    "waves run", "how long were waves", "time on waves",
)

_TIME_UNIT_HINT_PHRASES = (
    "time", "duration", "hour", "hours", "long",
)

_ACTIVE_IDLE_HINT_PHRASES = (
    "active", "inactive", "working", "idle",
)

_PRODUCTIVE_IDLE_HINT_PHRASES = (
    "productive", "idle",
)


# ============================================================
# Chart-type intent detection  (ambiguity breaker)
# ============================================================
# Phrases that hint the user wants a trend / time-series / bar chart
_TREND_INTENT_PHRASES = (
    "trend", "over time", "daily", "hourly", "day by day", "day wise",
    "daywise", "per day", "per hour", "each day", "each hour",
    "show trend", "chart", "graph", "time series", "progression",
    "history", "breakdown by day", "breakdown by hour",
)
# Phrases that hint the user wants a single aggregate / stat value
_STAT_INTENT_PHRASES = (
    "what is the", "what's the", "how many", "how much",
    "total", "overall", "current", "right now",
    "give me the number", "count of", "average",
)
# Chart types that are "trend-like" (multi-row, time-axis)
_TREND_CHART_TYPES = frozenset({
    "bar chart", "time series", "line chart", "state timeline",
    "bar gauge", "pie chart", "table",
})
# Chart types that are "stat-like" (single value)
_STAT_CHART_TYPES = frozenset({"stat"})


def _detect_chart_intent(question: str) -> Optional[str]:
    """
    Return 'trend' if the user wants a time-series visual,
    'stat' if they want a single number, or None if ambiguous.
    """
    q = question.lower()
    has_trend = any(p in q for p in _TREND_INTENT_PHRASES)
    has_stat = any(p in q for p in _STAT_INTENT_PHRASES)
    if has_trend and not has_stat:
        return "trend"
    if has_stat and not has_trend:
        return "stat"
    return None


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
    MATCH_THRESHOLD = 0.55

    # If embedding API is unavailable, use keyword-only with a stricter gate
    KEYWORD_ONLY_THRESHOLD = 0.65

    # Weight split for hybrid scoring
    EMBEDDING_WEIGHT = 0.65
    KEYWORD_WEIGHT = 0.35

    # Minimum gap between #1 and #2 candidates to accept a match.
    # If the top two KPIs are within this margin, fall through to
    # SQL generation instead of risking a wrong-KPI hit.
    AMBIGUITY_MARGIN = 0.05          # FIX-5: tightened from 0.08

    # High-confidence threshold — above this, match is terminal (no fallback).
    # Between MATCH_THRESHOLD and HIGH_CONFIDENCE, match is accepted but
    # logged as low-confidence for monitoring.
    HIGH_CONFIDENCE_THRESHOLD = 0.75

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
        self._registry_path = registry_path  # stored for stale-cache check
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
                logger.info("📊 KPI registry changed (IDs differ) — rebuilding embeddings")
                return False

            # Validate: cache must not be older than registry file
            # (catches user_queries / logic edits that don't change IDs)
            import os
            registry_path = getattr(self, '_registry_path', None)
            if registry_path and os.path.exists(registry_path):
                reg_mtime = os.path.getmtime(registry_path)
                cache_mtime = os.path.getmtime(str(self._embeddings_path))
                if reg_mtime > cache_mtime:
                    logger.info(
                        "📊 KPI registry file is newer than embeddings cache — "
                        "rebuilding embeddings"
                    )
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

        # Expand with acronym ↔ phrase mappings
        for word in list(expanded_q):
            if word in ACRONYM_EXPANSIONS:
                for phrase in ACRONYM_EXPANSIONS[word]:
                    expanded_q.update(phrase.split())
        # Also check multi-word phrases in the question
        for phrase, expansions in ACRONYM_EXPANSIONS.items():
            if " " in phrase and phrase in q_normalized:
                for exp in expansions:
                    expanded_q.update(exp.split())

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
        #     matches one of the known natural-language phrasings.
        #     NEW: Near-exact anchor bonus — if ≥90% of a curated user_query's
        #     meaningful words appear in the question, give a large anchor bonus
        #     so curated phrases always dominate over loose similarity.
        #     Increased from 0.30 → 0.55 to ensure anchored keyword scores
        #     outweigh embedding noise in hybrid mode (0.65*emb + 0.35*kw).
        uq_bonus = 0.0
        uq_anchor_bonus = 0.0
        for uq in kpi.user_queries:
            uq_norm = re.sub(r'[^a-z0-9\s]', ' ', uq.lower())
            uq_words = set(uq_norm.split()) - stop_words - _FILLER_SET
            if uq_words and q_words:
                overlap_uq = len(expanded_q & uq_words)
                ratio = overlap_uq / max(len(uq_words), 1)
                if ratio > uq_bonus:
                    uq_bonus = ratio
                # Near-exact anchor: ≥90% token overlap with a curated query
                if ratio >= 0.90 and len(uq_words) >= 3:
                    uq_anchor_bonus = max(uq_anchor_bonus, 0.55)
        uq_bonus = min(uq_bonus * 0.5, 0.45)  # cap contribution

        # 3. Category boost — if question mentions the category
        category_boost = 0.0
        cat_kws = CATEGORY_KEYWORDS.get(kpi.category, [])
        for ckw in cat_kws:
            if ckw in q_normalized:
                category_boost = 0.25          # FIX-8: was 0.15
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

        score = name_bonus + uq_bonus + uq_anchor_bonus + (keyword_score * 0.3) + category_boost + dashboard_boost + col_bonus
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

    # ----------------------------------------------------------
    # NAME-TOKEN TIEBREAKER (resolves ambiguity between siblings)
    # ----------------------------------------------------------
    # Only truly non-discriminating words — keep "avg", "total", "count"
    # etc. out of this because they CAN differentiate sibling KPIs
    # (e.g. "QPL" vs "Avg QPL", "Total Quantity" vs "Total Blocked Quantity").
    _TIEBREAK_STOP = frozenset({
        "per", "vs", "by", "wise", "the", "a", "of", "and", "in", "at",
        "show", "give", "me", "tell", "get", "what", "is", "are", "how",
        # Generic modifiers that don't discriminate between sibling KPIs.
        # E.g. "percentage" shouldn't pick "Bin-wise Volume Utilization (%)"
        # over "Volume Utilization" — both are percentage KPIs.
        "percentage", "percent", "rate", "occupancy",
    })

    # Common abbreviation ↔ full-word map for fuzzy matching in tiebreaker.
    # Includes domain synonyms that the query preprocessor may substitute
    # (e.g. SynonymResolver maps sku→article, product→article) so the
    # tiebreaker can still recognise the user’s original intent.
    _TIEBREAK_ABBREVS = {
        "avg": "average", "qty": "quantity", "no": "number",
        "num": "number", "loc": "location", "locs": "locations",
        # Reverse synonym mappings (preprocessor normalises these)
        "article": "sku", "articles": "skus",
        "bot": "robot", "bots": "robots",
        "put": "putaway", "inventory": "stock",
        "error": "failure", "errors": "failures",
    }

    def _name_token_tiebreak(
        self,
        question: str,
        kpi_a: KPIEntry,
        kpi_b: KPIEntry,
    ) -> Optional[int]:
        """
        Break ambiguity between two close-scoring KPIs by checking which
        KPI's *discriminating* name tokens appear in the user's query.

        Discriminating tokens = words unique to one KPI's name & user_queries
        that are NOT in the other KPI's name & user_queries.

        Returns:
            1  → kpi_a wins (query matches A's discriminators)
            2  → kpi_b wins (query matches B's discriminators)
            None → inconclusive (no clear token evidence)
        """
        def _tokens(kpi: KPIEntry) -> set:
            """Build rich token set from name + user_queries."""
            text = kpi.kpi_name
            for uq in kpi.user_queries:
                text += " " + uq
            normalised = re.sub(r'[^a-z0-9\s]', ' ', text.lower())
            raw_tokens = set(normalised.split())
            # ── Normalise singular / plural so "bin"/"bins" collapse ──
            # This prevents false discriminators when one KPI says "Bin"
            # and the other says "Bins" (grammatical, not semantic).
            stem_tokens = set()
            for t in raw_tokens:
                stem = t.rstrip('s') if (t.endswith('s') and len(t) > 3
                                         and t not in ('this', 'was')) else t
                # Skip token if its stem is a stop word
                # (e.g. "percentages" → "percentage" which is in stop list)
                if stem in self._TIEBREAK_STOP or t in self._TIEBREAK_STOP:
                    continue
                stem_tokens.add(stem)
                stem_tokens.add(t)    # keep original too
            tokens = stem_tokens
            # Expand abbreviations in token set
            expanded = set(tokens)
            for t in tokens:
                if t in self._TIEBREAK_ABBREVS:
                    expanded.add(self._TIEBREAK_ABBREVS[t])
                # Reverse lookup
                for abbr, full in self._TIEBREAK_ABBREVS.items():
                    if t == full:
                        expanded.add(abbr)
            return expanded

        tokens_a = _tokens(kpi_a)
        tokens_b = _tokens(kpi_b)

        # Discriminators — words in one but not the other
        disc_a = tokens_a - tokens_b
        disc_b = tokens_b - tokens_a

        if not disc_a and not disc_b:
            return None   # identical token sets — no way to distinguish

        # Build expanded query tokens (with singular/plural + abbreviation fuzzy match)
        q_norm = re.sub(r'[^a-z0-9\s]', ' ', question.lower())
        q_words = set(q_norm.split())
        q_expanded = set(q_words)
        for w in list(q_words):
            # Plural / singular variants
            if w.endswith('s') and len(w) > 3:
                q_expanded.add(w[:-1])         # "skus" → "sku"
            else:
                q_expanded.add(w + 's')         # "sku" → "skus"
            if w.endswith('ies') and len(w) > 4:
                q_expanded.add(w[:-3] + 'y')   # "quantities" → "quantity"
            if w.endswith('y') and len(w) > 3:
                q_expanded.add(w[:-1] + 'ies') # "quantity" → "quantities"
            # Abbreviation expansion
            if w in self._TIEBREAK_ABBREVS:
                q_expanded.add(self._TIEBREAK_ABBREVS[w])
            for abbr, full in self._TIEBREAK_ABBREVS.items():
                if w == full:
                    q_expanded.add(abbr)

        hits_a = len(q_expanded & disc_a)
        hits_b = len(q_expanded & disc_b)

        logger.debug(
            f"📊 Tiebreak: disc_a={disc_a} hits={hits_a}, "
            f"disc_b={disc_b} hits={hits_b}"
        )

        if hits_a > 0 and hits_b == 0:
            return 1
        if hits_b > 0 and hits_a == 0:
            return 2
        if hits_a > hits_b and hits_a >= 2:
            return 1  # clear advantage
        if hits_b > hits_a and hits_b >= 2:
            return 2
        return None   # inconclusive

    def _apply_family_intent_boosts(
        self,
        question: str,
        scored: List[Tuple[float, KPIEntry]],
        chart_intent: Optional[str] = None,
    ) -> List[Tuple[float, KPIEntry]]:
        """Apply family-aware boosts/penalties for known high-collision KPI clusters."""
        if not scored:
            return scored

        q_lower = question.lower()
        station_scope = _has_any_phrase(q_lower, _STATION_SCOPE_PHRASES) or bool(
            re.search(r'\b(?:station|st)[- _]?\d{1,4}\b', q_lower)
        )
        ipp_intent = _has_any_phrase(q_lower, _IPP_HINT_PHRASES)
        pick_intent = _has_any_phrase(q_lower, _PICK_HINT_PHRASES)
        put_intent = _has_any_phrase(q_lower, _PUT_HINT_PHRASES)
        net_intent = _has_any_phrase(q_lower, ("net",))
        gross_intent = _has_any_phrase(q_lower, ("gross",))
        both_metric_intent = net_intent and gross_intent
        wave_intent = _has_any_phrase(q_lower, ("wave", "waves"))
        wave_time_intent = _has_any_phrase(q_lower, _WAVE_TIME_HINT_PHRASES) or (
            wave_intent and _has_any_phrase(q_lower, _TIME_UNIT_HINT_PHRASES)
        )

        # ── Bot active/inactive family detection ──
        has_active = _has_any_phrase(q_lower, ("active",))
        has_inactive = _has_any_phrase(q_lower, ("inactive",))
        active_vs_inactive_intent = has_active and has_inactive   # both → kpi_001
        active_only_intent = has_active and not has_inactive       # → kpi_002
        inactive_only_intent = has_inactive and not has_active     # → kpi_003

        adjusted: List[Tuple[float, KPIEntry]] = []
        for score, kpi in scored:
            new_score = score
            kid = kpi.id

            if ipp_intent:
                if station_scope:
                    if kid in {"kpi_066", "kpi_080"}:
                        new_score = min(new_score + 0.18, 1.0)
                    elif kid in {"kpi_094", "kpi_095", "kpi_101"}:
                        new_score *= 0.82
                    elif kid in {"kpi_091", "kpi_092"} and chart_intent != "trend":
                        new_score *= 0.88
                elif chart_intent == "trend":
                    if kid in {"kpi_091", "kpi_092"}:
                        new_score = min(new_score + 0.12, 1.0)
                    elif kid in {"kpi_066", "kpi_080", "kpi_094", "kpi_095", "kpi_101"}:
                        new_score *= 0.9

                if pick_intent and not put_intent:
                    if kid in {"kpi_066", "kpi_091", "kpi_094", "kpi_095"}:
                        new_score = min(new_score + 0.12, 1.0)
                    elif kid in {"kpi_080", "kpi_092", "kpi_101"}:
                        new_score *= 0.75

                if put_intent and not pick_intent:
                    if kid in {"kpi_080", "kpi_092", "kpi_101"}:
                        new_score = min(new_score + 0.12, 1.0)
                    elif kid in {"kpi_066", "kpi_091", "kpi_094", "kpi_095"}:
                        new_score *= 0.75

                if both_metric_intent:
                    if kid in {"kpi_066", "kpi_080", "kpi_091", "kpi_092"}:
                        new_score = min(new_score + 0.12, 1.0)
                    elif kid in {"kpi_094", "kpi_095", "kpi_101"}:
                        new_score *= 0.8
                elif net_intent and not gross_intent:
                    if kid in {"kpi_094", "kpi_101"}:
                        new_score = min(new_score + 0.08, 1.0)
                    elif kid == "kpi_095":
                        new_score *= 0.88
                elif gross_intent and not net_intent:
                    if kid == "kpi_095":
                        new_score = min(new_score + 0.08, 1.0)
                    elif kid in {"kpi_094", "kpi_101"}:
                        new_score *= 0.88

            if station_scope:
                if wave_time_intent:
                    if kid == "kpi_065":
                        new_score = min(new_score + 0.18, 1.0)
                    elif kid in {"kpi_062", "kpi_063", "kpi_064", "kpi_039"}:
                        new_score *= 0.82

            # ── Bot active/inactive family disambiguation ────────────────
            # kpi_001 = Active vs Inactive (hours breakdown per bot)
            # kpi_002 = Active Bots (count)
            # kpi_003 = Inactive Bots (count)
            # When user says BOTH "active" and "inactive" → kpi_001.
            # "active" only → kpi_002.  "inactive" only → kpi_003.
            # Only apply for BOT-scope queries (skip station-scope).
            if not station_scope:
                if active_vs_inactive_intent:
                    if kid == "kpi_001":
                        new_score = min(new_score + 0.20, 1.0)
                    elif kid in {"kpi_002", "kpi_003"}:
                        new_score *= 0.70
                elif active_only_intent:
                    if kid == "kpi_002":
                        new_score = min(new_score + 0.10, 1.0)
                    elif kid in {"kpi_001", "kpi_003"}:
                        new_score *= 0.82
                elif inactive_only_intent:
                    if kid == "kpi_003":
                        new_score = min(new_score + 0.10, 1.0)
                    elif kid in {"kpi_001", "kpi_002"}:
                        new_score *= 0.82

            adjusted.append((new_score, kpi))

        adjusted.sort(key=lambda x: x[0], reverse=True)
        return adjusted

    def resolve(
        self,
        question: str,
        tenant_values: Optional[List[str]] = None,
        time_from: Optional[str] = None,
        time_to: Optional[str] = None,
        category_filter: Optional[str] = None,
        all_sites: bool = False,
        location_breakdown: bool = False,
        top_k: int = 1,
        bot_id: Optional[str] = None,
        category_value: Optional[str] = None,
        station_id: Optional[str] = None,
        original_question: Optional[str] = None,
        bin_id: Optional[str] = None,
        wave_id: Optional[str] = None,
        order_id: Optional[str] = None,
    ) -> Optional[KPIMatch]:
        """
        Try to match the question to a dashboard KPI.

        Scoring:
            - Embedding-available:  hybrid = 0.65*cosine + 0.35*keyword
            - Embedding-unavailable: keyword-only (stricter threshold)

        Args:
            question: Natural language user question (may be synonym-normalised)
            tenant_values: List of tenant IDs (e.g., ["frk"], ["frk","shakti"])
            time_from: Start date/datetime string (default: today - 1 day)
            time_to: End date/datetime string (default: now)
            category_filter: Restrict to a category (bot/inventory/orders/station)
            all_sites: If True, remove location filters entirely
            location_breakdown: If True, try to return one row per location
                                instead of a single all-sites aggregate.
            top_k: Return top-k matches (only the best is returned by default)
            original_question: Raw user question before synonym normalisation.
                               Used by the tiebreaker to detect words that the
                               preprocessor may have replaced (e.g. sku→article).

        Returns:
            KPIMatch if a match is found above threshold, else None
        """
        # Backward compat: accept single string
        if isinstance(tenant_values, str):
            tenant_values = [tenant_values]

        # ── Schema / meta-query guard ────────────────────────────────────
        # Queries about database structure (columns, tables, schemas) are
        # NOT dashboard KPIs.  Table names like "bot_master" contain domain
        # words ("bot") that drive false-positive keyword overlap.  Reject
        # early before scoring.
        if _is_schema_query(question):
            logger.info(
                f"📊 KPI reject: schema/meta query detected — '{question}'"
            )
            return None

        # ── Entity-lookup guard ──────────────────────────────────────────
        # Queries about a specific entity's properties (location, IP,
        # tower-side, counters) are NOT dashboard KPIs.  Entity IDs like
        # "BOT-0001" contain domain words ("bot") that inflate scores.
        if _is_entity_lookup_query(
            question,
            bot_id=bot_id,
            station_id=station_id,
            bin_id=bin_id,
            wave_id=wave_id,
            order_id=order_id,
        ):
            logger.info(
                f"📊 KPI reject: entity-lookup query detected — '{question}'"
            )
            return None

        candidates = self.kpis
        if category_filter:
            candidates = [k for k in candidates if k.category == category_filter]

        # ── Strip tenant/time noise for scoring only ──
        # Original `question` is preserved for parameter substitution.
        match_question = strip_matching_noise(question)
        logger.info(f"📊 KPI match_question: '{match_question}' (raw: '{question}')")

        # ── Embed using the ORIGINAL question (before synonym normalisation) ──
        # The SynonymResolver maps user words to schema terms (sku→article,
        # robot→bot, etc.) which is good for SQL generation but HARMFUL for
        # embedding similarity — the KPI text was embedded with original
        # terminology ("SKU", "robot").  Using the original question preserves
        # semantic proximity.  Keyword scoring uses the normalised question
        # and expands via SYNONYMS to bridge the gap.
        if original_question:
            embed_question = strip_matching_noise(original_question)
        else:
            embed_question = match_question
        q_embedding = self._get_question_embedding(embed_question)

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

        # ── Case-1 fix: intent mismatch penalty ──────────────────────────────
        # If the user is clearly asking for a COUNT ("how many ..."), penalise
        # KPIs that return a percentage / rate / utilisation metric so the right
        # COUNT-based KPI bubbles to the top instead.
        # FIX-4: softer penalty (0.6 instead of 0.3) and skip for rate phrases
        _RATE_WORDS = ("per hour", "per bin", "per line", "per day", "per pick",
                   "per lpn", "per order", "utilization", "utilisation",
                   "percentage", "%", "ratio", "rate", "ipp")
        q_lower = question.lower()
        is_rate_question = any(rw in q_lower for rw in _RATE_WORDS)

        if _has_count_intent(question) and not is_rate_question:
            adjusted = []
            for score, kpi in scored:
                if _kpi_returns_metric(kpi):
                    penalised = score * 0.6          # FIX-4: was 0.3
                    logger.debug(
                        f"📊 KPI intent mismatch: user wants COUNT but "
                        f"'{kpi.kpi_name}' returns a metric/% — "
                        f"score {score:.3f} → {penalised:.3f}"
                    )
                    adjusted.append((penalised, kpi))
                else:
                    adjusted.append((score, kpi))
            adjusted.sort(key=lambda x: x[0], reverse=True)
            # Re-apply threshold after penalty
            scored = [(s, k) for s, k in adjusted if s >= threshold]
            if not scored:
                logger.info(
                    "📊 KPI count-intent filter: all % KPIs penalised below "
                    "threshold — falling through to SQL generation"
                )
                return None

        # ── Implicit count-vs-% disambiguation ───────────────────────────────
        # When the query has NO percentage/rate indicator, but a % KPI leads
        # and a non-% KPI is close behind, the user likely wants a raw
        # count (e.g. "bin used" → Bins Used, not Bin Utilisation %).
        # Apply a small penalty to % KPIs so the count KPI bubbles up.
        if not is_rate_question and len(scored) >= 2:
            best_s, best_k = scored[0]
            if _kpi_returns_metric(best_k):
                # Check if a non-% sibling is within AMBIGUITY_MARGIN
                for i, (s, k) in enumerate(scored[1:], 1):
                    if not _kpi_returns_metric(k) and (best_s - s) < self.AMBIGUITY_MARGIN:
                        # Non-% KPI is close — swap to prefer count
                        logger.info(
                            f"📊 Implicit count preference: '{best_k.kpi_name}' "
                            f"(% KPI, {best_s:.3f}) → '{k.kpi_name}' "
                            f"(count KPI, {s:.3f}) — no % indicator in query"
                        )
                        scored[0], scored[i] = scored[i], scored[0]
                        break

        # ── FIX-3: Chart-type intent boost ───────────────────────────────────
        # Detect whether the user wants a trend/chart vs a single stat value.
        # Boost KPIs whose chart_type aligns with detected intent to break
        # ambiguity between sibling KPIs (e.g. OLBP trend vs OLBP stat).
        chart_intent = _detect_chart_intent(question)
        if chart_intent:
            CHART_TYPE_BOOST = 0.15
            boosted = []
            for score, kpi in scored:
                ct = kpi.chart_type.lower().strip()
                if chart_intent == "trend" and ct in _TREND_CHART_TYPES:
                    new_score = min(score + CHART_TYPE_BOOST, 1.0)
                    logger.debug(
                        f"📊 Chart-intent boost (trend): '{kpi.kpi_name}' "
                        f"chart={ct} — score {score:.3f} → {new_score:.3f}"
                    )
                    boosted.append((new_score, kpi))
                elif chart_intent == "stat" and ct in _STAT_CHART_TYPES:
                    new_score = min(score + CHART_TYPE_BOOST, 1.0)
                    logger.debug(
                        f"📊 Chart-intent boost (stat): '{kpi.kpi_name}' "
                        f"chart={ct} — score {score:.3f} → {new_score:.3f}"
                    )
                    boosted.append((new_score, kpi))
                else:
                    boosted.append((score, kpi))
            boosted.sort(key=lambda x: x[0], reverse=True)
            scored = boosted

        # ── Family-aware disambiguation boosts ───────────────────────────────
        # High-collision KPI clusters (IPP, station-hours) need stronger
        # lexical intent handling than raw embeddings can provide.
        scored = self._apply_family_intent_boosts(question, scored, chart_intent)

        best_score, best_kpi = scored[0]

        # ── Ambiguity check: reject if top two candidates are too close ──
        if len(scored) >= 2:
            runner_score, runner_kpi = scored[1]
            margin = best_score - runner_score
            logger.info(
                f"📊 KPI top-2: #1 '{best_kpi.kpi_name}' ({best_score:.3f}) "
                f"vs #2 '{runner_kpi.kpi_name}' ({runner_score:.3f}), "
                f"margin={margin:.3f} (min={self.AMBIGUITY_MARGIN})"
            )
            if margin < self.AMBIGUITY_MARGIN:
                if (
                    not is_rate_question
                    and _has_any_phrase(q_lower, ("used", "in use", "occupied"))
                    and _kpi_returns_metric(best_kpi)
                    and not _kpi_returns_metric(runner_kpi)
                ):
                    best_score, best_kpi = runner_score, runner_kpi
                    logger.info(
                        f"📊 KPI ambiguity override: count-style 'used' query "
                        f"prefers '{best_kpi.kpi_name}' over metric sibling"
                    )
                else:
                # ── Name-token tiebreaker ────────────────────────────
                # Instead of immediately falling through, check if the
                # user's query tokens clearly favour one KPI over the
                # other by looking at *discriminating* name tokens —
                # words unique to each KPI name.
                #
                # Example: "Total blocked SKU" →
                #   #1 'Total Blocked SKUs'     unique: {sku,skus}
                #   #2 'Total Blocked Quantity'  unique: {quantity}
                #   query has "sku" → tiebreak to #1
                # Use the original (pre-synonym) question for tiebreaking
                # so that words like "SKU" (normalised to "article")
                # can still discriminate between sibling KPIs.
                    tiebreak_q = original_question if original_question else match_question
                    tiebreak_winner = self._name_token_tiebreak(
                        tiebreak_q, best_kpi, runner_kpi
                    )
                    if tiebreak_winner is not None:
                        # Tiebreak resolved — pick the winner
                        if tiebreak_winner == 2:
                            best_score, best_kpi = runner_score, runner_kpi
                        logger.info(
                            f"📊 KPI tiebreak resolved → '{best_kpi.kpi_name}' "
                            f"(discriminating tokens matched in query)"
                        )
                    else:
                        # ── Tiebreak inconclusive — accept the higher scorer ──
                        # When two sibling KPIs are very close and the
                        # tiebreaker can't distinguish them, the higher
                        # hybrid score is still the best signal we have.
                        # Rejecting both and falling to SQL generation would
                        # lose a valid KPI match entirely.
                        logger.warning(
                            f"📊 KPI ambiguity: top-2 within margin "
                            f"({margin:.3f} < {self.AMBIGUITY_MARGIN}) — "
                            f"tiebreak inconclusive, accepting higher scorer "
                            f"'{best_kpi.kpi_name}' ({best_score:.3f})"
                        )

        # ── Confidence band logging ──
        if best_score < self.HIGH_CONFIDENCE_THRESHOLD:
            logger.warning(
                f"📊 KPI low-confidence match: '{best_kpi.kpi_name}' "
                f"score={best_score:.3f} (below HIGH_CONFIDENCE={self.HIGH_CONFIDENCE_THRESHOLD}). "
                f"Accepting but flagging for monitoring."
            )

        # Log scoring breakdown for diagnostics
        if q_embedding is not None:
            kw_only = self._score_match(match_question, best_kpi)
            emb_only = float(np.dot(q_embedding, self.kpi_embeddings.get(best_kpi.id, np.zeros(1))))
            logger.info(
                f"📊 KPI scoring: id={best_kpi.id}, keyword={kw_only:.3f}, "
                f"embedding={emb_only:.3f}, hybrid={best_score:.3f} "
                f"(threshold={threshold})"
            )

        # Substitute Grafana variables
        sql, params_applied = self._substitute_params(
            best_kpi.query, tenant_values, time_from, time_to, all_sites,
            question=question,
            bot_id=bot_id,
            category_value=category_value,
            station_id=station_id,
            location_breakdown=location_breakdown,
            kpi_id=best_kpi.id,
        )

        if location_breakdown and params_applied.get("location_breakdown") == "unsupported":
            logger.info(
                f"📊 KPI location-breakdown unsupported for id={best_kpi.id}, "
                f"'{best_kpi.kpi_name}' — falling through to SQL generation"
            )
            return None

        # ── Entity post-filter: inject WHERE clause for specific entities ──
        sql, params_applied = self._inject_entity_filters(
            sql, params_applied,
            bot_id=bot_id,
            station_id=station_id,
            bin_id=bin_id,
            wave_id=wave_id,
            order_id=order_id,
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
            f"📊 KPI matched: id={best_kpi.id}, '{best_kpi.kpi_name}' "
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
        location_breakdown: bool = False,
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

        chart_intent = _detect_chart_intent(question)
        scored = self._apply_family_intent_boosts(question, scored, chart_intent)
        scored.sort(key=lambda x: x[0], reverse=True)

        results = []
        for score, kpi in scored[:top_k]:
            sql, params = self._substitute_params(
                kpi.query, tenant_values, time_from, time_to, all_sites,
                question=question,
                location_breakdown=location_breakdown,
                kpi_id=kpi.id,
            )
            if location_breakdown and params.get("location_breakdown") == "unsupported":
                continue
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

    def _parse_time_range(self, question: str) -> Union[timedelta, Tuple[datetime, datetime]]:
        """
        Extract time range from natural-language expressions in the question.

        Returns:
            timedelta  – for relative ranges ("last 3 days", "yesterday")
            (from_dt, to_dt) tuple – for absolute date ranges
                                     ("from 2 to 3 march", "march 2 to march 5")

        Extended to cover:
          - Absolute date ranges ("from 2 to 3 march", "between march 2 and march 5")
          - Day names         ("on Monday", "last Tuesday")
          - Time-of-day       ("this morning", "this afternoon")
          - Specific dates    ("April 3", "March 23rd", "3rd April")
          - "now" / "current" (last 1 hour)
        """
        q = question.lower()
        now = datetime.now()

        # ── Word-to-number conversion so "last one hour" works ──
        _WORD_NUMS = {
            'one': '1', 'two': '2', 'three': '3', 'four': '4',
            'five': '5', 'six': '6', 'seven': '7', 'eight': '8',
            'nine': '9', 'ten': '10', 'eleven': '11', 'twelve': '12',
            'fifteen': '15', 'twenty': '20', 'thirty': '30',
        }
        for word, digit in _WORD_NUMS.items():
            q = re.sub(rf'\b{word}\b', digit, q)

        # ── Month name lookup (used by absolute & single-date patterns) ──
        _MONTHS = {
            'january': 1, 'february': 2, 'march': 3, 'april': 4,
            'may': 5, 'june': 6, 'july': 7, 'august': 8,
            'september': 9, 'october': 10, 'november': 11, 'december': 12,
            'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
            'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9,
            'oct': 10, 'nov': 11, 'dec': 12,
        }
        _MONTH_PAT = '|'.join(_MONTHS.keys())
        _ORD = r'(?:st|nd|rd|th)?'   # optional ordinal suffix

        # ── Absolute date-range patterns (MUST be checked before single-date) ──
        # Helper to build a datetime, falling back to previous year if future
        def _make_dt(month_name: str, day: int) -> datetime:
            mi = _MONTHS[month_name.lower()]
            try:
                dt = datetime(now.year, mi, day)
            except ValueError:
                return now  # invalid date
            if dt.date() > now.date():
                dt = datetime(now.year - 1, mi, day)
            return dt

        # Pattern 1: "from 2 to 3 march" / "from 2nd to 3rd march"
        #            "between 2 and 3 march" / "2 to 3 march"
        rm = re.search(
            rf'(?:from|between)?\s*(\d{{1,2}}){_ORD}\s*(?:to|-|and)\s*(\d{{1,2}}){_ORD}\s+({_MONTH_PAT})',
            q,
        )
        if rm:
            d1, d2 = int(rm.group(1)), int(rm.group(2))
            mn = rm.group(3)
            from_dt = _make_dt(mn, d1)
            to_dt = _make_dt(mn, d2)
            if from_dt > to_dt:
                from_dt, to_dt = to_dt, from_dt
            from_dt = from_dt.replace(hour=0, minute=0, second=0)
            to_dt = to_dt.replace(hour=23, minute=59, second=59)
            logger.debug(f"⏰ Absolute range (pattern-1): {from_dt} → {to_dt}")
            return (from_dt, to_dt)

        # Pattern 2: "march 2 to march 3" / "march 2nd to march 5th"
        #            "from march 2 to march 3" / "between march 2 and march 5"
        rm = re.search(
            rf'(?:from|between)?\s*({_MONTH_PAT})\s+(\d{{1,2}}){_ORD}\s*(?:to|-|and)\s*({_MONTH_PAT})\s+(\d{{1,2}}){_ORD}',
            q,
        )
        if rm:
            from_dt = _make_dt(rm.group(1), int(rm.group(2)))
            to_dt = _make_dt(rm.group(3), int(rm.group(4)))
            if from_dt > to_dt:
                from_dt, to_dt = to_dt, from_dt
            from_dt = from_dt.replace(hour=0, minute=0, second=0)
            to_dt = to_dt.replace(hour=23, minute=59, second=59)
            logger.debug(f"⏰ Absolute range (pattern-2): {from_dt} → {to_dt}")
            return (from_dt, to_dt)

        # Pattern 3: "march 2 to 5" / "from april 1 to 15" / "between jan 10 and 20"
        rm = re.search(
            rf'(?:from|between)?\s*({_MONTH_PAT})\s+(\d{{1,2}}){_ORD}\s*(?:to|-|and)\s*(\d{{1,2}}){_ORD}',
            q,
        )
        if rm:
            mn = rm.group(1)
            d1, d2 = int(rm.group(2)), int(rm.group(3))
            from_dt = _make_dt(mn, d1)
            to_dt = _make_dt(mn, d2)
            if from_dt > to_dt:
                from_dt, to_dt = to_dt, from_dt
            from_dt = from_dt.replace(hour=0, minute=0, second=0)
            to_dt = to_dt.replace(hour=23, minute=59, second=59)
            logger.debug(f"⏰ Absolute range (pattern-3): {from_dt} → {to_dt}")
            return (from_dt, to_dt)

        # Pattern 4: "2 march to 5 march" / "2nd march to 5th april"
        rm = re.search(
            rf'(\d{{1,2}}){_ORD}\s*({_MONTH_PAT})\s*(?:to|-|and)\s*(\d{{1,2}}){_ORD}\s*({_MONTH_PAT})',
            q,
        )
        if rm:
            from_dt = _make_dt(rm.group(2), int(rm.group(1)))
            to_dt = _make_dt(rm.group(4), int(rm.group(3)))
            if from_dt > to_dt:
                from_dt, to_dt = to_dt, from_dt
            from_dt = from_dt.replace(hour=0, minute=0, second=0)
            to_dt = to_dt.replace(hour=23, minute=59, second=59)
            logger.debug(f"⏰ Absolute range (pattern-4): {from_dt} → {to_dt}")
            return (from_dt, to_dt)

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

        # ── Extended patterns (Case-2 fix) ─────────────────────────────────

        # Named weekday: "on Monday", "last Tuesday", "data for Wednesday"
        _WEEKDAYS = (
            "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday",
        )
        _WEEKDAY_INDEX = {d: i for i, d in enumerate(_WEEKDAYS)}  # mon=0 … sun=6
        day_m = re.search(
            r'\b(' + '|'.join(_WEEKDAYS) + r')\b', q
        )
        if day_m:
            target_idx = _WEEKDAY_INDEX[day_m.group(1)]   # 0=Mon … 6=Sun
            current_idx = now.weekday()                    # 0=Mon … 6=Sun
            days_ago = (current_idx - target_idx) % 7
            if days_ago == 0:
                days_ago = 7   # "Monday" when today is Monday → last Monday
            return timedelta(days=days_ago)

        # "this morning" / "this afternoon" / "this evening" / "this night"
        if re.search(r'\bthis\s+(?:morning|afternoon|evening|night)\b', q):
            return timedelta(hours=12)   # broad same-day window

        # Specific date — "April 3", "March 23rd", "3rd April", "jan 5th"
        # (_MONTHS and _MONTH_PAT already defined above)
        # "April 3" / "April 3rd"
        mdate = re.search(
            rf'\b({_MONTH_PAT})\s+(\d{{1,2}})(?:st|nd|rd|th)?\b', q
        )
        if not mdate:
            # "3rd April" / "3 April"
            mdate = re.search(
                rf'\b(\d{{1,2}})(?:st|nd|rd|th)?\s+({_MONTH_PAT})\b', q
            )
            if mdate:
                # swap groups so we can use uniform logic below
                day_num = int(mdate.group(1))
                month_idx = _MONTHS[mdate.group(2).lower()]
                mdate = None   # handled manually below
                try:
                    target = datetime(now.year, month_idx, day_num)
                    if target > now:
                        target = datetime(now.year - 1, month_idx, day_num)
                    return now - target
                except ValueError:
                    pass
        if mdate:
            try:
                month_idx = _MONTHS[mdate.group(1).lower()]
                day_num = int(mdate.group(2))
                target = datetime(now.year, month_idx, day_num)
                if target > now:
                    target = datetime(now.year - 1, month_idx, day_num)
                return now - target
            except ValueError:
                pass   # invalid date, fall through

        # "now" / "currently" → last 1 hour
        if re.search(r'\b(now|current(?:ly)?)\b', q):
            return timedelta(hours=1)

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
        location_breakdown: bool = False,
        kpi_id: Optional[str] = None,
        question: str = "",
        bot_id: Optional[str] = None,
        category_value: Optional[str] = None,
        station_id: Optional[str] = None,
    ) -> tuple:
        """
        Replace Grafana template variables with actual values.

        Supports:
            - Single tenant: IN ('frk') or = 'frk'
            - Multi tenant:  IN ('frk','shakti')
            - All sites:     removes location filter entirely
            - bot_id:        specific bot or wildcard
            - category_value: specific category or wildcard
            - station_id:    specific station (future use)

        Grafana patterns:
            $location / IN ($location) → actual host-location value(s)
            $__timeFrom() → start datetime
            $__timeTo()   → end datetime
            $Category     → category value or ALL (wildcard)
            ${bot_id:sqlstring} → specific bot or all bots
        """
        params = {}
        sql = query

        # 1. Location substitution
        if location_breakdown and tenant_values:
            if len(tenant_values) == 1:
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
                in_list = ", ".join(f"'{v}'" for v in tenant_values)
                sql = re.sub(
                    r"IN\s*\(\s*\$location\s*\)",
                    f"IN ({in_list})",
                    sql, flags=re.IGNORECASE
                )
                sql = re.sub(
                    r"=\s*'?\$location'?",
                    f"IN ({in_list})",
                    sql, flags=re.IGNORECASE
                )
                params["location"] = tenant_values
        elif all_sites or not tenant_values:
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
            parsed = self._parse_time_range(question) if question else timedelta(days=1)
            if isinstance(parsed, tuple):
                # Absolute date range returned (from_dt, to_dt)
                t_from = parsed[0].strftime("%Y-%m-%d %H:%M:%S")
                t_to = parsed[1].strftime("%Y-%m-%d %H:%M:%S")
                logger.debug(
                    f"⏰ Absolute time range from question: {t_from} → {t_to}"
                )
            else:
                # Relative timedelta
                delta = parsed
                if delta.total_seconds() == 0:
                    t_from = now.strftime("%Y-%m-%d 00:00:00")
                else:
                    t_from = (now - delta).strftime("%Y-%m-%d %H:%M:%S")
                t_to = now.strftime("%Y-%m-%d %H:%M:%S")
        else:
            t_from = time_from
            t_to = time_to if time_to else now.strftime("%Y-%m-%d %H:%M:%S")

        # Replace Grafana time functions
        # $__timeFilter(column) → column BETWEEN 'from' AND 'to'
        sql = re.sub(
            r"\$__timeFilter\(([^)]+)\)",
            rf"\1 BETWEEN '{t_from}' AND '{t_to}'",
            sql, flags=re.IGNORECASE
        )
        # $__timeFrom() - INTERVAL N DAY/HOUR → compute the adjusted timestamp
        # so the buffer period (e.g., midnight-crossing safety) is preserved.
        _interval_pat = re.compile(
            r"\$__timeFrom\(\)\s*-\s*INTERVAL\s+(\d+)\s+(\w+)",
            re.IGNORECASE,
        )
        _iv_match = _interval_pat.search(sql)
        if _iv_match:
            offset_val = int(_iv_match.group(1))
            offset_unit = _iv_match.group(2).upper()
            try:
                t_from_dt = datetime.strptime(t_from, "%Y-%m-%d %H:%M:%S")
            except ValueError:
                t_from_dt = datetime.strptime(t_from, "%Y-%m-%d")
            if offset_unit in ("DAY", "DAYS"):
                adjusted_from = (t_from_dt - timedelta(days=offset_val)).strftime("%Y-%m-%d %H:%M:%S")
            elif offset_unit in ("HOUR", "HOURS"):
                adjusted_from = (t_from_dt - timedelta(hours=offset_val)).strftime("%Y-%m-%d %H:%M:%S")
            else:
                adjusted_from = t_from  # unknown unit, no adjustment
            sql = _interval_pat.sub(f"'{adjusted_from}'", sql)
            logger.debug(
                f"⏰ INTERVAL offset preserved: $__timeFrom() - INTERVAL {offset_val} {offset_unit} "
                f"→ '{adjusted_from}' (original from='{t_from}')"
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

        # 3. $Category substitution — use extracted value or remove filter
        if "$Category" in sql:
            if category_value:
                sql = sql.replace("$Category", category_value)
                params["category"] = category_value
            else:
                sql = re.sub(
                    r"AND\s+\w*\.?`?CATEGORY`?\s*=\s*'\$Category'",
                    "/* all categories */",
                    sql, flags=re.IGNORECASE
                )
                sql = sql.replace("$Category", "%")
                params["category"] = "all"

        # 4. ${bot_id:sqlstring} — use extracted value or remove filter
        if "${bot_id:sqlstring}" in sql:
            if bot_id:
                sql = sql.replace("${bot_id:sqlstring}", f"'{bot_id}'")
                params["bot_id"] = bot_id
            else:
                sql = re.sub(
                    r"AND\s+\w*\.?\w+\s+IN\s*\(\$\{bot_id:sqlstring\}\)",
                    "/* all bots */",
                    sql, flags=re.IGNORECASE
                )
                sql = sql.replace("${bot_id:sqlstring}", "'%'")
                params["bot_id"] = "all"

        # 5. Catch any remaining ${var:sqlstring} patterns — replace with $var
        sql = re.sub(r'\$\{(\w+):sqlstring\}', r"$\1", sql)

        if location_breakdown:
            sql, breakdown_mode = self._rewrite_for_location_breakdown(sql, kpi_id)
            params["location_breakdown"] = breakdown_mode

        return sql, params

    def _rewrite_for_location_breakdown(
        self,
        sql: str,
        kpi_id: Optional[str] = None,
    ) -> Tuple[str, str]:
        """
        Rewrite simple aggregate KPIs into grouped-by-location SQL.

        This is intentionally conservative. Complex KPI SQL is left untouched so
        the caller can fall back to the generic SQL path, which already knows how
        to handle location breakdown prompts.
        """
        sql_body = sql.strip().rstrip(";")
        normalized = f" {re.sub(r'\s+', ' ', sql_body).strip().lower()} "

        unsupported_tokens = (
            " join ", " with ", " union ", " group by ",
            " having ", " order by ",
        )
        if any(token in normalized for token in unsupported_tokens):
            return sql, "unsupported"

        if normalized.count("select ") != 1:
            return sql, "unsupported"

        match = re.match(
            r"(?is)^\s*select\s+(?P<select>.+?)\s+from\s+(?P<from>[^;]+?)\s+where\s+(?P<where>.+)$",
            sql_body,
        )
        if not match:
            return sql, "unsupported"

        select_expr = match.group("select").strip()
        from_clause = match.group("from").strip()
        where_clause = match.group("where").strip()

        if "select " in select_expr.lower() or "(" in from_clause or "," in from_clause:
            return sql, "unsupported"

        from_match = re.match(
            r"^(?P<table>`?[\w-]+`?)(?:\s+(?:AS\s+)?(?P<alias>\w+))?$",
            from_clause,
            flags=re.IGNORECASE,
        )
        if not from_match or "host-location" not in where_clause.lower():
            return sql, "unsupported"

        alias = from_match.group("alias")
        group_expr = f"{alias}.`host-location`" if alias else "`host-location`"

        rewritten_sql = (
            "SELECT\n"
            f"    {group_expr} AS location,\n"
            f"    {select_expr}\n"
            f"FROM {from_clause}\n"
            f"WHERE {where_clause}\n"
            f"GROUP BY {group_expr}\n"
            f"ORDER BY {group_expr};"
        )
        logger.info(
            f"📊 KPI location-breakdown rewrite applied: id={kpi_id or 'unknown'}"
        )
        return rewritten_sql, "grouped_by_location"

    # ----------------------------------------------------------
    # ENTITY POST-FILTER
    # ----------------------------------------------------------

    # Mapping: entity key → list of case-insensitive output column patterns
    _ENTITY_COLUMN_PATTERNS: Dict[str, List[str]] = {
        "BOT_ID":     ["bot_id"],
        "STATION_ID": ["station", "station_id"],
        "BIN_ID":     ["bin_id", "bin id"],
        "WAVE_ID":    ["wave_id"],
        "ORDER_ID":   ["order_id"],
    }

    @staticmethod
    def _extract_outermost_select_columns(sql: str) -> List[str]:
        """
        Extract column aliases from the outermost SELECT clause.

        Handles:  ``expr AS alias``, ``table.col``, bare ``col``,
        backtick-quoted aliases like ```BIN ID` ``.

        Returns a list of alias strings (lowercase, backticks stripped).
        """
        sql_clean = sql.strip().rstrip(";")

        # Skip leading WITH ... to reach the final SELECT
        # Find the last top-level SELECT (not inside parens)
        depth = 0
        last_select_pos = -1
        i = 0
        sql_lower = sql_clean.lower()
        while i < len(sql_clean) - 6:
            ch = sql_clean[i]
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
            elif (depth == 0
                  and sql_lower[i:i+6] == 'select'
                  and sql_clean[i+6] in (' ', '\n', '\r', '\t')):
                last_select_pos = i
            i += 1

        if last_select_pos == -1:
            return []

        # Find the FROM that closes this SELECT
        after_select = sql_clean[last_select_pos + 7:]
        depth = 0
        from_pos = -1
        for j, ch in enumerate(after_select):
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
            elif (depth == 0
                  and j + 4 < len(after_select)
                  and after_select[j:j+4].lower() == 'from'
                  and after_select[j+4] in (' ', '\n', '\r', '\t')):
                from_pos = j
                break

        if from_pos == -1:
            return []

        select_body = after_select[:from_pos]

        # Split by top-level commas (not inside parens/quotes)
        parts: List[str] = []
        depth = 0
        in_quote = False
        current = []
        for ch in select_body:
            if ch == "'" and not in_quote:
                in_quote = True
            elif ch == "'" and in_quote:
                in_quote = False
            elif ch == '(' and not in_quote:
                depth += 1
            elif ch == ')' and not in_quote:
                depth -= 1
            elif ch == ',' and depth == 0 and not in_quote:
                parts.append(''.join(current).strip())
                current = []
                continue
            current.append(ch)
        if current:
            parts.append(''.join(current).strip())

        # Extract alias from each part
        aliases: List[str] = []
        for part in parts:
            part = part.strip()
            if not part:
                continue
            # Pattern: ... AS `alias` or ... AS alias
            as_match = re.search(
                r'\bAS\s+`?([^`,\s]+(?:\s+[^`,\s]+)*)`?\s*$',
                part, flags=re.IGNORECASE,
            )
            if as_match:
                aliases.append(as_match.group(1).strip().lower())
            else:
                # No AS — use the last token (table.col → col, or bare col)
                token = part.rsplit('.', 1)[-1].strip().strip('`').lower()
                aliases.append(token)

        return aliases

    @staticmethod
    def _station_id_variants(station_id: str) -> List[str]:
        """
        Generate value variants for a station entity.

        EntityResolver produces ``STATION-0003``. KPI outputs use
        ``ST-3``, ``STATION-0003``, or even bare ``3``.

        Returns a list of possible string values to match against.
        """
        variants = [station_id]                      # STATION-0003
        numeric = re.search(r'(\d+)$', station_id)
        if numeric:
            n = int(numeric.group(1))
            variants.append(f"ST-{n}")               # ST-3
            variants.append(str(n))                   # 3
            variants.append(f"STATION-{n}")           # STATION-3 (no zero-pad)
        return variants

    def _inject_entity_filters(
        self,
        sql: str,
        params_applied: Dict[str, str],
        *,
        bot_id: Optional[str] = None,
        station_id: Optional[str] = None,
        bin_id: Optional[str] = None,
        wave_id: Optional[str] = None,
        order_id: Optional[str] = None,
    ) -> Tuple[str, Dict[str, str]]:
        """
        Inject WHERE filters for specific entities into KPI SQL.

        Many KPI queries return data for ALL bots / stations / bins.
        When the user asks about a specific entity (e.g. "bot 1"),
        this method wraps the SQL in a subquery and adds a WHERE
        clause to filter to that entity.

        The method is safe / no-op when:
        - No entity value is provided
        - The entity value is already present in the SQL
          (e.g. ``${bot_id:sqlstring}`` was already substituted)
        - The KPI output columns don't include a matching entity column
          (e.g. aggregate KPIs like "Active Bots" → COUNT only)
        """
        entities_to_inject: Dict[str, Tuple[str, List[str]]] = {}
        # Collect entity_key → (canonical_value, match_variants)
        if bot_id:
            entities_to_inject["BOT_ID"] = (bot_id, [bot_id])
        if station_id:
            entities_to_inject["STATION_ID"] = (
                station_id, self._station_id_variants(station_id)
            )
        if bin_id:
            entities_to_inject["BIN_ID"] = (bin_id, [bin_id])
        if wave_id:
            entities_to_inject["WAVE_ID"] = (wave_id, [wave_id])
        if order_id:
            entities_to_inject["ORDER_ID"] = (order_id, [order_id])

        if not entities_to_inject:
            return sql, params_applied

        # Extract column aliases from outermost SELECT
        columns = self._extract_outermost_select_columns(sql)
        if not columns:
            return sql, params_applied

        # Build WHERE clauses for each entity that has a matching output column
        filters: List[str] = []
        params = dict(params_applied)

        for entity_key, (canonical, variants) in entities_to_inject.items():
            # Skip if this entity value is already literally in the SQL
            # (means ${bot_id:sqlstring} was already substituted)
            if canonical in sql:
                logger.debug(
                    f"📊 Entity {entity_key}={canonical} already in SQL — skip injection"
                )
                continue

            # Find matching output column
            patterns = self._ENTITY_COLUMN_PATTERNS.get(entity_key, [])
            matched_col = None
            for col_alias in columns:
                for pattern in patterns:
                    if pattern in col_alias:
                        matched_col = col_alias
                        break
                if matched_col:
                    break

            if not matched_col:
                logger.debug(
                    f"📊 Entity {entity_key}={canonical} — no matching output "
                    f"column in [{', '.join(columns)}] — skip injection"
                )
                continue

            # Build the filter expression
            if len(variants) == 1:
                filters.append(f"_ef.`{matched_col}` = '{variants[0]}'")
            else:
                vals = ", ".join(f"'{v}'" for v in variants)
                filters.append(f"_ef.`{matched_col}` IN ({vals})")

            params[f"entity_filter_{entity_key.lower()}"] = canonical
            logger.info(
                f"📊 Entity filter injected: {entity_key}={canonical} "
                f"→ column `{matched_col}` (variants={variants})"
            )

        if not filters:
            return sql, params

        # Wrap original SQL in a subquery and apply entity filters
        inner_sql = sql.rstrip().rstrip(";")
        where_clause = " AND ".join(filters)
        wrapped_sql = (
            f"SELECT * FROM (\n{inner_sql}\n) AS _ef\n"
            f"WHERE {where_clause};"
        )

        return wrapped_sql, params

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
