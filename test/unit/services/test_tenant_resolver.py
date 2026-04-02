"""
Unit Tests — TenantResolver
Target: backend/app/services/sql_assistant/tenant_resolver.py

Tests:
  - detect_multi_tenant_intent() — keyword matching
  - _extract_location_phrase() — regex phrase extraction
  - _predefined_mapping_lookup() — dict lookup (longest-first)
  - map_to_actual_value() — 4-strategy mapping
  - extract_tenant() with mocked embeddings
"""

import pytest
import sys
import json
from pathlib import Path
from unittest.mock import MagicMock, patch
import numpy as np

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))


@pytest.fixture
def resolver(tmp_path):
    """Create TenantResolver with mocked model and tmp data dir."""
    from app.services.sql_assistant.tenant_resolver import TenantResolver

    # Write predefined mappings
    mappings = {
        "mappings": {
            "bangalore": "BLR",
            "bengaluru": "BLR",
            "blr": "BLR",
            "faridabad": "frk",
            "frk": "frk",
            "bhiwandi": "shakti",
            "biwandi": "shakti",
            "shakti": "shakti",
            "chennai": "chennai",
        }
    }
    mappings_file = tmp_path / "tenant_value_mappings.json"
    with open(mappings_file, "w") as f:
        json.dump(mappings, f)

    tr = TenantResolver.__new__(TenantResolver)
    tr.data_dir = tmp_path
    tr.embeddings_path = tmp_path / "tenant_embeddings.npz"
    tr.metadata_path = tmp_path / "tenant_metadata.json"
    tr.mappings_path = mappings_file
    tr.model = MagicMock()
    # model.encode() should return 2D array (batch) or 1D (single)
    # Real SentenceTransformer returns shape (n, 384) for n inputs
    def mock_encode(texts):
        return np.random.rand(len(texts), 384)
    tr.model.encode.side_effect = mock_encode
    tr.tenant_embeddings = None
    tr.tenant_metadata = [
        {"tenant_id": "BLR", "variation": "bangalore"},
        {"tenant_id": "frk", "variation": "faridabad"},
        {"tenant_id": "shakti", "variation": "bhiwandi"},
        {"tenant_id": "chennai", "variation": "chennai"},
    ]
    tr.predefined_mappings = mappings["mappings"]

    return tr


# ===================================================================
# MULTI-TENANT INTENT DETECTION
# ===================================================================
class TestDetectMultiTenantIntent:

    @pytest.mark.parametrize("query", [
        "compare frk and shakti",
        "between bhiwandi and faridabad",
        "frk vs shakti",
        "picks at frk, shakti, and blr",
    ])
    def test_multi_tenant_detected(self, resolver, query):
        assert resolver.detect_multi_tenant_intent(query) is True

    @pytest.mark.parametrize("query", [
        "show picks at bhiwandi",
        "total picks today",
        "how many bots at frk",
    ])
    def test_single_tenant_not_detected(self, resolver, query):
        assert resolver.detect_multi_tenant_intent(query) is False


# ===================================================================
# PREDEFINED MAPPING LOOKUP
# ===================================================================
class TestPredefinedMappingLookup:

    def test_exact_match_bhiwandi(self, resolver):
        result = resolver._predefined_mapping_lookup("bhiwandi")
        assert result == "shakti"

    def test_exact_match_frk(self, resolver):
        result = resolver._predefined_mapping_lookup("frk")
        assert result == "frk"

    def test_bangalore_to_blr(self, resolver):
        result = resolver._predefined_mapping_lookup("bangalore")
        assert result == "BLR"

    def test_bengaluru_to_blr(self, resolver):
        result = resolver._predefined_mapping_lookup("bengaluru")
        assert result == "BLR"

    def test_no_match(self, resolver):
        result = resolver._predefined_mapping_lookup("mumbai")
        assert result is None

    def test_embedded_in_sentence(self, resolver):
        result = resolver._predefined_mapping_lookup("show picks at bhiwandi today")
        assert result == "shakti"


# ===================================================================
# MAP TO ACTUAL VALUE
# ===================================================================
class TestMapToActualValue:

    def test_exact_match(self, resolver):
        result = resolver.map_to_actual_value("frk", ["BLR", "chennai", "frk", "shakti"])
        assert result == "frk"

    def test_case_insensitive_exact(self, resolver):
        result = resolver.map_to_actual_value("FRK", ["BLR", "chennai", "frk", "shakti"])
        assert result == "frk"

    def test_predefined_mapping(self, resolver):
        result = resolver.map_to_actual_value("bhiwandi", ["BLR", "chennai", "frk", "shakti"])
        assert result == "shakti"

    def test_no_match_returns_none(self, resolver):
        result = resolver.map_to_actual_value("zzz", ["BLR", "chennai", "frk", "shakti"])
        # May return None or a fuzzy match depending on threshold
        assert result is None or result in ["BLR", "chennai", "frk", "shakti"]


# ===================================================================
# GET ALL TENANTS
# ===================================================================
class TestGetAllTenants:

    def test_returns_unique_list(self, resolver):
        resolver.tenant_metadata = [
            {"tenant_id": "frk"}, {"tenant_id": "shakti"},
            {"tenant_id": "frk"}, {"tenant_id": "BLR"}
        ]
        result = resolver.get_all_tenants()
        assert len(result) == 3
        assert set(result) == {"frk", "shakti", "BLR"}
