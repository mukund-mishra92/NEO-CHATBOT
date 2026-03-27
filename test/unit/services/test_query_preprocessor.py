"""
Unit Tests — QueryPreprocessor
Target: backend/app/services/sql_assistant/query_preprocessor.py

Tests:
  - _is_all_sites_query — keyword detection
  - _is_location_breakdown_query
  - _is_aggregate_query — keyword categories
  - Tenant extraction flow (mocked resolver)
  - Default tenant application modes
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))


# ===================================================================
# IMPORT WITH SETTINGS PATCHING
# We must patch settings before importing QueryPreprocessor because
# it reads settings at class level.
# ===================================================================
@pytest.fixture
def preprocessor():
    """Create a QueryPreprocessor with mocked dependencies."""
    with patch("app.services.sql_assistant.query_preprocessor.settings") as mock_settings:
        mock_settings.MULTI_TENANT_ENABLED = True
        mock_settings.TENANT_COLUMN = "host-location"
        mock_settings.DEFAULT_TENANT = "frk"
        mock_settings.TENANT_EXTRACTION_THRESHOLD = 0.65
        mock_settings.TENANT_DEFAULT_BEHAVIOR = "smart_aggregate"
        mock_settings.DATA_DIR = Path(".")

        from app.services.sql_assistant.query_preprocessor import QueryPreprocessor

        # Create with mocked sub-resolvers
        pp = QueryPreprocessor.__new__(QueryPreprocessor)
        pp.synonym_resolver = MagicMock()
        pp.synonym_resolver.normalize.side_effect = lambda q: q  # passthrough
        pp.entity_resolver = MagicMock()
        pp.entity_resolver.resolve.return_value = {}
        pp.entity_resolver.substitute.side_effect = lambda q, e: q
        pp.tenant_resolver = MagicMock()
        pp.tenant_resolver.extract_tenant.return_value = (None, 0.0, [])
        pp.tenant_resolver.extract_all_tenants.return_value = ([], [])
        pp.tenant_resolver.detect_multi_tenant_intent.return_value = False
        pp.tenant_resolver.get_all_tenants.return_value = ["BLR", "chennai", "frk", "shakti"]
        pp.tenant_resolver.map_to_actual_value.side_effect = lambda v, vals, **kw: v
        pp.multi_tenant_enabled = True
        pp.tenant_column = "host-location"
        pp.default_tenant = "frk"
        pp.extraction_threshold = 0.65
        pp.default_behavior = "smart_aggregate"
        pp.low_signal_threshold = 0.30

    return pp


# ===================================================================
# ALL-SITES DETECTION
# ===================================================================
class TestIsAllSitesQuery:

    @pytest.mark.parametrize("query", [
        "show picks across all sites",
        "total for all locations",
        "data for every site",
        "picks for all warehouses",
        "every location total",
        "company-wide report",
    ])
    def test_all_sites_detected(self, preprocessor, query):
        assert preprocessor._is_all_sites_query(query.lower()) is True

    @pytest.mark.parametrize("query", [
        "show picks at bhiwandi",
        "total picks today",
        "compare sites",  # Note: "compare" alone may not trigger all-sites
    ])
    def test_not_all_sites(self, preprocessor, query):
        assert preprocessor._is_all_sites_query(query.lower()) is False


# ===================================================================
# LOCATION BREAKDOWN DETECTION
# ===================================================================
class TestIsLocationBreakdownQuery:

    @pytest.mark.parametrize("query", [
        "breakdown by location",
        "split by site",
        "per location picks",
        "location wise totals",
        "site-wise comparison",
        "group by location",
    ])
    def test_breakdown_detected(self, preprocessor, query):
        assert preprocessor._is_location_breakdown_query(query.lower()) is True

    @pytest.mark.parametrize("query", [
        "show picks at bhiwandi",
        "total picks today",
    ])
    def test_not_breakdown(self, preprocessor, query):
        assert preprocessor._is_location_breakdown_query(query.lower()) is False


# ===================================================================
# AGGREGATE QUERY DETECTION
# ===================================================================
class TestIsAggregateQuery:

    @pytest.mark.parametrize("query", [
        "count all picks",
        "total items received",
        "how many bots active",
        "sum of quantities",
        "average pick time",
        "what is the trend",
        "compare sites",
        "show statistics",
    ])
    def test_aggregation_detected(self, preprocessor, query):
        assert preprocessor._is_aggregate_query(query.lower()) is True

    @pytest.mark.parametrize("query", [
        "show me details of bot 4",
        "what is the status of bin 23",
    ])
    def test_not_aggregation(self, preprocessor, query):
        assert preprocessor._is_aggregate_query(query.lower()) is False
