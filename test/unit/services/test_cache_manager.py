"""
Unit Tests — QueryCacheManager
Target: backend/app/services/sql_assistant/cache_manager.py

Fully in-memory — no mocking needed.
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.cache_manager import QueryCacheManager


@pytest.fixture
def cache():
    return QueryCacheManager()


class TestCacheManager:

    def test_get_empty_cache(self, cache):
        assert cache.get("sess-1", "query") is None

    def test_set_and_get(self, cache):
        cache.set("sess-1", "show picks", {"response": "42 picks"})
        result = cache.get("sess-1", "show picks")
        assert result == {"response": "42 picks"}

    def test_different_sessions_isolated(self, cache):
        cache.set("sess-1", "show picks", {"data": "session1"})
        cache.set("sess-2", "show picks", {"data": "session2"})
        assert cache.get("sess-1", "show picks")["data"] == "session1"
        assert cache.get("sess-2", "show picks")["data"] == "session2"

    def test_different_questions_isolated(self, cache):
        cache.set("sess-1", "query A", {"data": "A"})
        cache.set("sess-1", "query B", {"data": "B"})
        assert cache.get("sess-1", "query A")["data"] == "A"
        assert cache.get("sess-1", "query B")["data"] == "B"

    def test_overwrite_existing(self, cache):
        cache.set("s1", "q1", {"v": 1})
        cache.set("s1", "q1", {"v": 2})
        assert cache.get("s1", "q1")["v"] == 2

    def test_miss_returns_none(self, cache):
        cache.set("s1", "q1", {"v": 1})
        assert cache.get("s1", "q2") is None
        assert cache.get("s2", "q1") is None
