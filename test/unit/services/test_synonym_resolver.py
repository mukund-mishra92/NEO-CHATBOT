"""
Unit Tests — SynonymResolver
Target: backend/app/services/sql_assistant/synonym_resolver.py

Tests:
  - Default synonym replacement (sku→article, robot→bot, etc.)
  - Word boundary matching (no partial replacements)
  - Case insensitivity
  - Custom synonym maps
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.synonym_resolver import SynonymResolver


@pytest.fixture
def resolver():
    return SynonymResolver()


# ===================================================================
# DEFAULT SYNONYMS
# ===================================================================
class TestDefaultSynonyms:

    def test_sku_to_article(self, resolver):
        assert resolver.normalize("how many skus") == "how many articles"

    def test_product_to_article(self, resolver):
        assert resolver.normalize("show product details") == "show article details"

    def test_item_to_article(self, resolver):
        assert resolver.normalize("count of items") == "count of articles"

    def test_robot_to_bot(self, resolver):
        result = resolver.normalize("which robot is active")
        assert "bot" in result

    def test_workstation_to_station(self, resolver):
        result = resolver.normalize("scans at workstation 5")
        assert "station" in result

    def test_container_to_bin(self, resolver):
        result = resolver.normalize("items in container 10")
        assert "bin" in result


# ===================================================================
# PLURAL HANDLING
# ===================================================================
class TestPlurals:

    def test_skus_to_articles(self, resolver):
        assert "articles" in resolver.normalize("count all skus")

    def test_products_to_articles(self, resolver):
        assert "articles" in resolver.normalize("list all products")

    def test_items_to_articles(self, resolver):
        assert "articles" in resolver.normalize("how many items")


# ===================================================================
# WORD BOUNDARIES
# ===================================================================
class TestWordBoundaries:

    def test_no_partial_match_sku(self, resolver):
        """'reskue' should NOT be touched."""
        assert resolver.normalize("reskue mission") == "reskue mission"

    def test_no_partial_match_product(self, resolver):
        """'byproduct' should NOT be touched."""
        assert resolver.normalize("byproduct details") == "byproduct details"


# ===================================================================
# CASE INSENSITIVITY
# ===================================================================
class TestCaseInsensitivity:

    def test_uppercase_sku(self, resolver):
        result = resolver.normalize("how many SKU")
        assert "article" in result.lower()

    def test_mixed_case(self, resolver):
        result = resolver.normalize("Show Products")
        assert "article" in result.lower()


# ===================================================================
# CUSTOM SYNONYMS
# ===================================================================
class TestCustomSynonyms:

    def test_custom_map(self):
        custom = SynonymResolver({"warehouse": "fulfillment center"})
        result = custom.normalize("items in warehouse")
        assert "fulfillment center" in result

    def test_empty_map(self):
        """Empty dict is falsy → `synonyms or DEFAULT` falls back to defaults.
        So passing {} still applies defaults (by design)."""
        empty = SynonymResolver({})
        result = empty.normalize("show sku details")
        # sku → article because {} is falsy, defaults kick in
        assert result == "show article details"


# ===================================================================
# NO CHANGE NEEDED
# ===================================================================
class TestNoChange:

    def test_already_canonical(self, resolver):
        original = "show article details from bot 4"
        assert resolver.normalize(original) == original

    def test_empty_string(self, resolver):
        assert resolver.normalize("") == ""
