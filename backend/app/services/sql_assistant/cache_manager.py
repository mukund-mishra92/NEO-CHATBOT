from typing import Dict, Tuple


class QueryCacheManager:

    def __init__(self):
        self._cache: Dict[Tuple[str, str], dict] = {}

    def get(self, session_id: str, question: str):
        return self._cache.get((session_id, question))

    def set(self, session_id: str, question: str, response):
        self._cache[(session_id, question)] = response

    def invalidate(self, session_id: str, question: str):
        self._cache.pop((session_id, question), None)
