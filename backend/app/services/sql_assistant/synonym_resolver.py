import re
from typing import Dict


class SynonymResolver:
    """
    Normalize user language to schema-aligned terminology.
    Example:
        'sku' -> 'article'
        'product' -> 'article'
        'bot' -> 'robot'
    """

    DEFAULT_SYNONYMS: Dict[str, str] = {
        "sku": "article",
        "skus": "articles",
        "product": "article",
        "products": "articles",
        "item": "article",
        "items": "articles",
        "bot": "robot",
        "bots": "robots",
        "station": "workstation",
        "stations": "workstations",
        "bin": "container",
        "bins": "containers",
    }

    def __init__(self, synonyms: Dict[str, str] = None):
        self.synonyms = synonyms or self.DEFAULT_SYNONYMS

    def normalize(self, question: str) -> str:
        normalized = question

        for src, target in self.synonyms.items():
            pattern = rf"\b{re.escape(src)}\b"
            normalized = re.sub(pattern, target, normalized, flags=re.IGNORECASE)

        return normalized
