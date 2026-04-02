"""
Response Cache — File-based cache for Knowledge Base responses.

Speeds up repeated / similar queries by 5-10× by returning a cached
response instead of hitting the LLM again.  Uses MD5 hash keys and a
configurable TTL (default 1 hour).
"""

import hashlib
import json
import time
import logging
from typing import Optional, Dict, Any
from pathlib import Path

logger = logging.getLogger(__name__)


class ResponseCache:
    """Simple file-based response cache with TTL expiry."""

    def __init__(
        self,
        cache_dir: Optional[str] = None,
        ttl_seconds: int = 3600,
    ):
        if cache_dir is None:
            cache_dir = str(
                Path(__file__).resolve().parents[4] / "data" / "response_cache"
            )

        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.ttl_seconds = ttl_seconds
        logger.info(
            f"✅ Response cache initialized  dir={self.cache_dir}  TTL={ttl_seconds}s"
        )

    # ------------------------------------------------------------------
    # Key generation
    # ------------------------------------------------------------------
    @staticmethod
    def _make_key(query: str, context_hash: str = "") -> str:
        """Deterministic cache key from normalised query + optional context."""
        content = f"{query.lower().strip()}:{context_hash}"
        return hashlib.md5(content.encode("utf-8")).hexdigest()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def get(self, query: str, context_hash: str = "") -> Optional[Dict[str, Any]]:
        """Return cached response dict, or ``None`` on miss / expiry."""
        try:
            key = self._make_key(query, context_hash)
            path = self.cache_dir / f"{key}.json"

            if not path.exists():
                return None

            data = json.loads(path.read_text(encoding="utf-8"))

            # Expiry check
            if time.time() - data.get("timestamp", 0) > self.ttl_seconds:
                path.unlink(missing_ok=True)
                return None

            logger.info(f"✅ Cache HIT for query: {query[:60]}…")
            return data.get("response")
        except Exception as exc:
            logger.warning(f"⚠️ Cache read error: {exc}")
            return None

    def set(
        self,
        query: str,
        response: Dict[str, Any],
        context_hash: str = "",
    ) -> None:
        """Persist a response to disk."""
        try:
            key = self._make_key(query, context_hash)
            path = self.cache_dir / f"{key}.json"

            payload = {
                "timestamp": time.time(),
                "query": query,
                "response": response,
            }
            path.write_text(json.dumps(payload, default=str), encoding="utf-8")
            logger.info(f"💾 Cached response for query: {query[:60]}…")
        except Exception as exc:
            logger.warning(f"⚠️ Cache write error: {exc}")

    def invalidate(self, query: str, context_hash: str = "") -> None:
        """Remove a single cache entry."""
        key = self._make_key(query, context_hash)
        path = self.cache_dir / f"{key}.json"
        path.unlink(missing_ok=True)

    def clear(self) -> int:
        """Remove **all** cache entries. Returns count deleted."""
        files = list(self.cache_dir.glob("*.json"))
        for f in files:
            f.unlink(missing_ok=True)
        logger.info(f"🗑️ Cache cleared: {len(files)} entries removed")
        return len(files)

    def get_stats(self) -> Dict[str, Any]:
        """Return basic cache statistics."""
        files = list(self.cache_dir.glob("*.json"))
        total_bytes = sum(f.stat().st_size for f in files)
        return {
            "total_entries": len(files),
            "total_size_bytes": total_bytes,
            "total_size_mb": round(total_bytes / (1024 * 1024), 2),
            "cache_directory": str(self.cache_dir),
            "ttl_seconds": self.ttl_seconds,
        }
