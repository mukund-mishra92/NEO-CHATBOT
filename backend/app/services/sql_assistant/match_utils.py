"""
Match Utilities — shared by KPI and SP resolvers
=================================================
Strips tenant names, time-range phrases and filler words from user
questions so the remaining text is a clean *domain* query for scoring.

The original question is PRESERVED for:
  - Time-range parsing  (_parse_time_range / _substitute_params)
  - Tenant injection    (_build_sql / _inject_tenant)
  - Entity extraction   (preprocessor)

Only the *scoring* functions (keyword overlap, embedding cosine)
receive the stripped version.
"""

import re
from typing import FrozenSet

# ------------------------------------------------------------------
# Tenant / location words to strip before matching
# ------------------------------------------------------------------
# These are location names that the user adds to specify WHERE they
# want data — but they must NOT affect WHAT KPI / SP is matched.
# Tenant identity is already extracted by the preprocessor.

_TENANT_NAMES: FrozenSet[str] = frozenset({
    # Actual site IDs
    "frk", "shakti", "blr", "chennai", "chn",
    # City / area names tied to warehouses
    "faruknagar", "farruknagar", "farukhnagar", "faruk",
    "bhiwandi", "biwandi", "bhivandi", "bhiwanid",
    "bangalore", "bengaluru", "banglore", "bangaluru", "bangalor",
    "madras", "chenai", "chenni", "channai", "chnnai",
    "mumbai", "bombay", "delhi", "pune",
    # Generic site placeholders
    "ncr",
})

# Prepositions that often precede tenant names — stripped WITH the name
_LOC_PREP = r"(?:in|at|from|for|of|near)\s+"

# ------------------------------------------------------------------
# Time-range patterns to strip (order matters — longer first)
# ------------------------------------------------------------------
_TIME_PATTERNS = [
    # "in the last N days/hours/weeks/months"
    r"\bin\s+the\s+last\s+\d+\s+(?:days?|hours?|weeks?|months?)\b",
    # "for the last N days"
    r"\bfor\s+the\s+last\s+\d+\s+(?:days?|hours?|weeks?|months?)\b",
    # "last N days/hours/weeks/months"
    r"\blast\s+\d+\s+(?:days?|hours?|weeks?|months?)\b",
    # "last one/two/... days/hours/weeks/months" (word numbers)
    r"\blast\s+(?:one|two|three|four|five|six|seven|eight|nine|ten)\s+(?:days?|hours?|weeks?|months?)\b",
    # "last (one)? week/month/year"
    r"\blast\s+(?:one\s+)?(?:week|month|year)\b",
    # "past N days/hours"
    r"\bpast\s+\d+\s+(?:days?|hours?|weeks?|months?)\b",
    # "today", "yesterday", "this week/month/year"
    r"\b(?:today|yesterday|this\s+(?:week|month|year))\b",
    # "since yesterday/morning/monday/…"
    r"\bsince\s+\w+\b",
    # "from <date> to <date>"  (YYYY-MM-DD or DD/MM/YYYY)
    r"\bfrom\s+\d{1,4}[-/]\d{1,2}[-/]\d{1,4}\s+to\s+\d{1,4}[-/]\d{1,2}[-/]\d{1,4}\b",
]
_TIME_RES = [re.compile(p, re.IGNORECASE) for p in _TIME_PATTERNS]

# ------------------------------------------------------------------
# Filler words (intent markers, not domain-relevant)
# ------------------------------------------------------------------
_FILLER: FrozenSet[str] = frozenset({
    "give", "me", "show", "please", "can", "you", "i", "want",
    "need", "get", "tell", "fetch", "display", "list", "find",
    "could", "would", "know", "see", "what", "is", "the", "a",
    "an", "are", "how", "many", "much",
})


# ------------------------------------------------------------------
# Domain synonyms — expand to canonical keyword form
# ------------------------------------------------------------------
# These handle cases where users say "putaway" but SP keywords have
# "put", or "stock" but KPI keywords have "inventory".
# Both the original AND the canonical form are kept so keyword
# matching and fuzzy overlap work maximally.
_DOMAIN_SYNONYMS: dict = {
    "putaway": "put",
    "put-away": "put",
    "stock": "inventory",
    "stocks": "inventory",
    "failure": "error",
    "failures": "errors",
    "faults": "errors",
    "fault": "error",
}


def strip_time_noise_for_embedding(question: str) -> str:
    """Strip *only* time-range phrases from the question.

    Unlike :func:`strip_matching_noise`, filler words, location names,
    and sentence structure are preserved — this is intended for use with
    embedding models that benefit from natural-language phrasing and
    domain-contextual words (e.g. warehouse locations).

    Only time constraints are removed because they dilute cosine
    similarity without contributing domain-specific signal to KPI
    or SP matching.

    Examples
    --------
    >>> strip_time_noise_for_embedding("What is volume at bangalore today?")
    'what is volume at bangalore?'
    >>> strip_time_noise_for_embedding("give me bin per hour for last 5 days")
    'give me bin per hour'
    """
    q = question.lower().strip()

    # Remove time-range phrases only
    for pat in _TIME_RES:
        q = pat.sub(" ", q)

    # Collapse whitespace
    result = " ".join(q.split()).strip()

    return result if result else question.lower().strip()


def strip_matching_noise(question: str) -> str:
    """Return a *scoring-friendly* version of the question.

    Removes:
      1. Time-range phrases  ("last 5 days", "today", "since morning")
      2. Tenant / location names with prepositions  ("in bhiwandi", "at frk")
      3. Common filler words  ("give me", "show", "please")

    The result is a concise domain query suitable for keyword overlap
    and embedding cosine similarity.

    Examples
    --------
    >>> strip_matching_noise("give me bin per hour per station for last 5 days in bhiwandi")
    'bin per hour per station'
    >>> strip_matching_noise("show live inventory in frk today")
    'live inventory'
    >>> strip_matching_noise("bot tasks per hour yesterday at shakti")
    'bot tasks per hour'
    """
    q = question.lower().strip()

    # 1. Remove time-range phrases (longest patterns first)
    for pat in _TIME_RES:
        q = pat.sub(" ", q)

    # 2. Remove tenant names (with optional leading preposition)
    #    Sort by length desc so "faruknagar" is tried before "faruk"
    for name in sorted(_TENANT_NAMES, key=len, reverse=True):
        # With preposition: "in bhiwandi" → ""
        q = re.sub(rf"\b{_LOC_PREP}{re.escape(name)}\b", " ", q)
        # Bare name: "bhiwandi warehouse" → " warehouse"
        q = re.sub(rf"\b{re.escape(name)}\b", " ", q)

    # 3. Remove filler words
    words = q.split()
    words = [w for w in words if w not in _FILLER]

    # 4. Expand domain synonyms (add canonical form alongside original)
    expanded = []
    for w in words:
        expanded.append(w)
        canon = _DOMAIN_SYNONYMS.get(w)
        if canon and canon not in expanded:
            expanded.append(canon)
    words = expanded

    # 5. Collapse whitespace
    result = " ".join(words).strip()

    # Never return empty — fall back to original (lowered)
    return result if result else question.lower().strip()
