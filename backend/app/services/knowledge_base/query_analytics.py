"""
Query Analytics — Lightweight JSONL-based performance tracking for the
Knowledge Base service.

Writes one JSON line per query to ``data/analytics/query_metrics.jsonl``
and provides on-the-fly aggregation for dashboards / health endpoints.
"""

import json
import time
import logging
from pathlib import Path
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


class QueryAnalytics:
    """Append-only JSONL analytics for RAG queries."""

    def __init__(self, analytics_dir: Optional[str] = None):
        if analytics_dir is None:
            analytics_dir = str(
                Path(__file__).resolve().parents[4] / "data" / "analytics"
            )
        self.analytics_dir = Path(analytics_dir)
        self.analytics_dir.mkdir(parents=True, exist_ok=True)
        self.metrics_file = self.analytics_dir / "query_metrics.jsonl"
        logger.info(f"✅ Query analytics initialized  dir={self.analytics_dir}")

    # ------------------------------------------------------------------
    # Write
    # ------------------------------------------------------------------
    def log_query(
        self,
        query: str,
        response_time_ms: float,
        confidence_score: float,
        num_sources: int,
        cached: bool = False,
        error: Optional[str] = None,
        query_type: Optional[str] = None,
        token_estimate: Optional[int] = None,
    ) -> None:
        """Append a single metric row."""
        try:
            metric = {
                "timestamp": datetime.now().isoformat(),
                "query_length": len(query),
                "query_preview": query[:100],
                "response_time_ms": round(response_time_ms, 2),
                "confidence_score": round(confidence_score, 3),
                "num_sources": num_sources,
                "cached": cached,
                "error": error,
                "query_type": query_type,
                "token_estimate": token_estimate,
            }
            with open(self.metrics_file, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(metric) + "\n")
        except Exception as exc:
            logger.error(f"❌ Analytics write error: {exc}")

    # ------------------------------------------------------------------
    # Read / report
    # ------------------------------------------------------------------
    def get_performance_report(self, days: int = 7) -> Dict[str, Any]:
        """Aggregate metrics for the last *days* days."""
        if not self.metrics_file.exists():
            return {"error": "No metrics available", "total_queries": 0}

        cutoff = datetime.now() - timedelta(days=days)
        metrics: List[Dict[str, Any]] = []

        with open(self.metrics_file, "r", encoding="utf-8") as fh:
            for line in fh:
                try:
                    row = json.loads(line)
                    ts = datetime.fromisoformat(row["timestamp"])
                    if ts >= cutoff:
                        metrics.append(row)
                except Exception:
                    continue

        if not metrics:
            return {"error": "No metrics in period", "total_queries": 0}

        total = len(metrics)
        avg_time = sum(m["response_time_ms"] for m in metrics) / total
        avg_conf = sum(m["confidence_score"] for m in metrics) / total
        cached_count = sum(1 for m in metrics if m.get("cached"))
        error_count = sum(1 for m in metrics if m.get("error"))

        fast = sum(1 for m in metrics if m["response_time_ms"] < 1000)
        high_conf = sum(1 for m in metrics if m["confidence_score"] >= 0.7)

        return {
            "period_days": days,
            "total_queries": total,
            "avg_response_time_ms": round(avg_time, 2),
            "avg_confidence_score": round(avg_conf, 3),
            "cache_hit_rate": round(cached_count / total, 3) if total else 0,
            "error_rate": round(error_count / total, 3) if total else 0,
            "performance": {
                "fast_queries_pct": round(fast / total * 100, 1) if total else 0,
                "avg_response_time_ms": round(avg_time, 2),
                "avg_confidence_score": round(avg_conf, 3),
            },
            "confidence_distribution": {
                "high_pct": round(high_conf / total * 100, 1) if total else 0,
                "low_pct": round((total - high_conf) / total * 100, 1) if total else 0,
            },
        }

    def get_recent_queries(self, limit: int = 20) -> List[Dict[str, Any]]:
        """Return the most recent *limit* metric rows."""
        if not self.metrics_file.exists():
            return []
        rows: List[Dict[str, Any]] = []
        with open(self.metrics_file, "r", encoding="utf-8") as fh:
            for line in fh:
                try:
                    rows.append(json.loads(line))
                except Exception:
                    continue
        return rows[-limit:]
