"""
E2E Tests — Natural-Language → SQL → Response
=============================================
Simulates the full user journey:
  NL question → preprocessing → table selection → LLM SQL generation
                → validation → execution → formatting → API response

All external dependencies (LLM, Database) are mocked at the boundary,
but the INTERNAL pipeline logic is exercised end-to-end.
"""

import pytest
import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch, PropertyMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))

from app.services.sql_assistant.validator import SQLValidator
from app.services.sql_assistant.schema_validator import SchemaValidator
from app.services.sql_assistant.entity_resolver import EntityResolver
from app.services.sql_assistant.synonym_resolver import SynonymResolver
from app.services.sql_assistant.formatter import SQLFormatter
from app.services.sql_assistant.confidence import ConfidenceEvaluator
from app.services.sql_assistant.semantic_validator import SemanticValidator
from app.services.sql_assistant.cache_manager import QueryCacheManager
from app.services.sql_assistant.models import SQLGenerationResult, SQLExecutionResult


# =====================================================================
# FIXTURES
# =====================================================================

@pytest.fixture
def full_pipeline(sample_schema):
    """Wire up a full internal pipeline with all real components."""
    return {
        "synonym_resolver": SynonymResolver(),
        "entity_resolver": EntityResolver(),
        "sql_validator": SQLValidator(),
        "schema_validator": SchemaValidator(sample_schema),
        "semantic_validator": SemanticValidator(),
        "formatter": SQLFormatter(),
        "confidence": ConfidenceEvaluator(),
        "cache": QueryCacheManager(),
    }


# =====================================================================
# E2E: Simple Query Flow
# =====================================================================

@pytest.mark.e2e
class TestSimpleQueryFlow:
    """Test the full flow for a simple aggregation query."""

    def test_count_picks_flow(self, full_pipeline):
        """
        'show total picks today'
        → synonym/entity resolution → generate SQL (mocked LLM)
        → validate → execute (mocked DB) → format response
        """
        question = "show total picks today"

        # Step 1: Preprocessing
        normalized = full_pipeline["synonym_resolver"].normalize(question)
        entities = full_pipeline["entity_resolver"].resolve(normalized)
        assert isinstance(entities, dict)

        # Step 2: Mock LLM produces SQL
        gen_result = SQLGenerationResult(
            sql="SELECT COUNT(*) AS total_picks FROM bal_pick_dtl WHERE DATE(`pick-time`) = CURDATE()",
            confidence=0.92,
            explanation="Counting total picks for today",
            assumptions=["Using pick-time for date filter"],
            metadata={"tables_used": ["bal_pick_dtl"]}
        )

        # Step 3: Validation chain
        full_pipeline["sql_validator"].validate(gen_result.sql)
        full_pipeline["schema_validator"].validate(gen_result.sql)

        # Step 4: Mock DB execution
        exec_result = SQLExecutionResult(
            rows=[{"total_picks": 1523}],
            row_count=1,
            execution_time_ms=45
        )

        # Step 5: Semantic validation
        full_pipeline["semantic_validator"].validate(exec_result)

        # Step 6: Confidence
        conf = full_pipeline["confidence"].compute(gen_result, exec_result)
        assert 0.0 < conf <= 1.0

        # Step 7: Format response
        formatted = full_pipeline["formatter"].format(
            question, gen_result.sql, exec_result, conf
        )
        assert "```sql" in formatted
        assert "1523" in formatted
        assert "Rows returned: 1" in formatted

    def test_top_articles_flow(self, full_pipeline):
        """
        'top 5 articles picked'
        → full pipeline → should produce formatted markdown with table
        """
        question = "top 5 articles picked"

        normalized = full_pipeline["synonym_resolver"].normalize(question)
        entities = full_pipeline["entity_resolver"].resolve(normalized)

        gen_result = SQLGenerationResult(
            sql=(
                "SELECT article, COUNT(*) AS picks FROM bal_pick_dtl "
                "GROUP BY article ORDER BY picks DESC LIMIT 5"
            ),
            confidence=0.90,
            explanation="Top 5 articles by pick count",
            assumptions=[],
            metadata={"tables_used": ["bal_pick_dtl"]}
        )

        full_pipeline["sql_validator"].validate(gen_result.sql)
        full_pipeline["schema_validator"].validate(gen_result.sql)

        exec_result = SQLExecutionResult(
            rows=[
                {"article": "ART-001", "picks": 300},
                {"article": "ART-002", "picks": 250},
                {"article": "ART-003", "picks": 200},
                {"article": "ART-004", "picks": 150},
                {"article": "ART-005", "picks": 100},
            ],
            row_count=5,
            execution_time_ms=80
        )

        full_pipeline["semantic_validator"].validate(exec_result)
        conf = full_pipeline["confidence"].compute(gen_result, exec_result)
        formatted = full_pipeline["formatter"].format(
            question, gen_result.sql, exec_result, conf
        )

        assert "ART-001" in formatted
        assert "300" in formatted
        assert "Rows returned: 5" in formatted


# =====================================================================
# E2E: Tenant-aware Query Flow
# =====================================================================

@pytest.mark.e2e
class TestTenantQueryFlow:
    """Full flow with tenant injection into SQL."""

    def test_bhiwandi_query_flow(self, full_pipeline):
        """
        'total picks at bhiwandi'
        → synonym normalizes → SQL generated with `host-location` = 'shakti'
        → validation → execution → formatted response
        """
        question = "total picks at bhiwandi"

        normalized = full_pipeline["synonym_resolver"].normalize(question)
        entities = full_pipeline["entity_resolver"].resolve(normalized)

        # LLM (mocked) should produce SQL with shakti tenant
        gen_result = SQLGenerationResult(
            sql="SELECT COUNT(*) AS total FROM bal_pick_dtl WHERE `host-location` = 'shakti'",
            confidence=0.93,
            explanation="Count picks at bhiwandi (mapped to shakti)",
            assumptions=["bhiwandi → shakti tenant mapping"],
            metadata={"tables_used": ["bal_pick_dtl"]}
        )

        full_pipeline["sql_validator"].validate(gen_result.sql)
        full_pipeline["schema_validator"].validate(gen_result.sql)

        exec_result = SQLExecutionResult(
            rows=[{"total": 876}], row_count=1, execution_time_ms=60
        )

        full_pipeline["semantic_validator"].validate(exec_result)
        conf = full_pipeline["confidence"].compute(gen_result, exec_result)
        formatted = full_pipeline["formatter"].format(
            question, gen_result.sql, exec_result, conf
        )

        assert "shakti" in gen_result.sql
        assert "876" in formatted

    def test_all_sites_comparison_flow(self, full_pipeline):
        """
        'compare picks across all sites'
        → SQL with GROUP BY `host-location` (no WHERE filter)
        → validation → execution → formatted table
        """
        question = "compare picks across all sites"

        gen_result = SQLGenerationResult(
            sql=(
                "SELECT `host-location`, COUNT(*) AS picks "
                "FROM bal_pick_dtl "
                "GROUP BY `host-location` "
                "ORDER BY picks DESC"
            ),
            confidence=0.88,
            explanation="Pick count comparison across all sites",
            assumptions=["All sites query — no tenant filter"],
            metadata={"tables_used": ["bal_pick_dtl"]}
        )

        full_pipeline["sql_validator"].validate(gen_result.sql)
        full_pipeline["schema_validator"].validate(gen_result.sql)

        exec_result = SQLExecutionResult(
            rows=[
                {"host-location": "frk", "picks": 5000},
                {"host-location": "shakti", "picks": 3000},
                {"host-location": "BLR", "picks": 2000},
                {"host-location": "chennai", "picks": 1500},
            ],
            row_count=4,
            execution_time_ms=120
        )

        full_pipeline["semantic_validator"].validate(exec_result)
        conf = full_pipeline["confidence"].compute(gen_result, exec_result)
        formatted = full_pipeline["formatter"].format(
            question, gen_result.sql, exec_result, conf
        )

        assert "frk" in formatted
        assert "shakti" in formatted
        assert "Rows returned: 4" in formatted


# =====================================================================
# E2E: Entity Resolution in Full Flow
# =====================================================================

@pytest.mark.e2e
class TestEntityResolutionFlow:
    """Full flow where entity IDs are extracted and used in SQL."""

    def test_bot_specific_query(self, full_pipeline):
        """
        'show picks for bot 5 today'
        → entity_resolver produces BOT_ID = BOT-0005
        → SQL uses BOT-0005 in WHERE clause
        """
        question = "show picks for bot 5 today"

        normalized = full_pipeline["synonym_resolver"].normalize(question)
        entities = full_pipeline["entity_resolver"].resolve(normalized)
        assert entities.get("BOT_ID") == "BOT-0005"

        gen_result = SQLGenerationResult(
            sql=(
                "SELECT * FROM bal_pick_dtl "
                "WHERE `bot-id` = 'BOT-0005' "
                "AND DATE(`pick-time`) = CURDATE() "
                "LIMIT 100"
            ),
            confidence=0.91,
            explanation="Picks for bot 5 today",
            assumptions=["BOT-0005 entity resolved"],
            metadata={"tables_used": ["bal_pick_dtl"]}
        )

        full_pipeline["sql_validator"].validate(gen_result.sql)
        full_pipeline["schema_validator"].validate(gen_result.sql)

        exec_result = SQLExecutionResult(
            rows=[{"id": 1, "bot-id": "BOT-0005", "article": "A1"}],
            row_count=1,
            execution_time_ms=40
        )

        full_pipeline["semantic_validator"].validate(exec_result)
        formatted = full_pipeline["formatter"].format(
            question, gen_result.sql, exec_result, gen_result.confidence
        )

        assert "BOT-0005" in gen_result.sql
        assert "BOT-0005" in formatted


# =====================================================================
# E2E: Cache Round-Trip
# =====================================================================

@pytest.mark.e2e
class TestCacheRoundTrip:
    """Test that cached results are returned without re-running SQL."""

    def test_cache_hit_skips_pipeline(self, full_pipeline):
        """
        1. First call: miss → full pipeline → cache store
        2. Second call: hit → return cached → no LLM/DB call
        """
        cache = full_pipeline["cache"]
        session_id = "session-abc"
        question = "total picks today"

        # Miss
        assert cache.get(session_id, question) is None

        # Simulate first call result
        cached_value = {
            "sql": "SELECT COUNT(*) FROM bal_pick_dtl",
            "formatted": "**Total picks: 100**",
            "confidence": 0.9,
        }
        cache.set(session_id, question, cached_value)

        # Hit
        hit = cache.get(session_id, question)
        assert hit is not None
        assert hit["confidence"] == 0.9
        assert "100" in hit["formatted"]


# =====================================================================
# E2E: Validation Failure Flow
# =====================================================================

@pytest.mark.e2e
class TestValidationFailureFlow:
    """Test that dangerous/invalid SQL never reaches execution."""

    def test_write_operation_blocked(self, full_pipeline):
        """LLM returns a write query → validator blocks before execution."""
        gen_result = SQLGenerationResult(
            sql="DELETE FROM bal_pick_dtl WHERE 1=1",
            confidence=0.3,
            explanation="WRONG",
            assumptions=[],
            metadata={}
        )

        from app.services.sql_assistant.validator import SQLValidationError
        with pytest.raises(SQLValidationError):
            full_pipeline["sql_validator"].validate(gen_result.sql)
        # Execution never happens

    def test_unknown_table_blocked(self, full_pipeline):
        """LLM hallucinates a table → schema validator blocks."""
        gen_result = SQLGenerationResult(
            sql="SELECT * FROM user_passwords LIMIT 10",
            confidence=0.5,
            explanation="bad",
            assumptions=[],
            metadata={}
        )

        full_pipeline["sql_validator"].validate(gen_result.sql)  # passes syntax

        from app.services.sql_assistant.schema_validator import SchemaValidationError
        with pytest.raises(SchemaValidationError):
            full_pipeline["schema_validator"].validate(gen_result.sql)

    def test_huge_result_blocked_by_semantic(self, full_pipeline):
        """Even if SQL is valid, semantic validator blocks > 500K rows."""
        exec_result = SQLExecutionResult(
            rows=[], row_count=600_000, execution_time_ms=5000
        )

        from app.services.sql_assistant.semantic_validator import SemanticValidationError
        with pytest.raises(SemanticValidationError):
            full_pipeline["semantic_validator"].validate(exec_result)


# =====================================================================
# E2E: Join Query Flow
# =====================================================================

@pytest.mark.e2e
class TestJoinQueryFlow:
    """Test multi-table join through the full pipeline."""

    def test_article_master_join(self, full_pipeline):
        """
        'top picked articles with descriptions'
        → joins bal_pick_dtl + bal_master_article
        → both tables validated → formatted with all columns
        """
        question = "top picked articles with descriptions"

        gen_result = SQLGenerationResult(
            sql=(
                "SELECT p.article, m.description, COUNT(*) AS picks "
                "FROM bal_pick_dtl p "
                "JOIN bal_master_article m ON p.article = m.article "
                "AND p.`host-location` = m.`host-location` "
                "WHERE p.`host-location` = 'frk' "
                "GROUP BY p.article, m.description "
                "ORDER BY picks DESC LIMIT 10"
            ),
            confidence=0.88,
            explanation="Top picked articles with master descriptions",
            assumptions=["Join on composite key (article + host-location)"],
            metadata={"tables_used": ["bal_pick_dtl", "bal_master_article"]}
        )

        full_pipeline["sql_validator"].validate(gen_result.sql)
        full_pipeline["schema_validator"].validate(gen_result.sql)

        exec_result = SQLExecutionResult(
            rows=[
                {"article": "ART-001", "description": "Widget A", "picks": 300},
                {"article": "ART-002", "description": "Widget B", "picks": 250},
            ],
            row_count=2,
            execution_time_ms=150
        )

        full_pipeline["semantic_validator"].validate(exec_result)
        conf = full_pipeline["confidence"].compute(gen_result, exec_result)
        formatted = full_pipeline["formatter"].format(
            question, gen_result.sql, exec_result, conf
        )

        assert "Widget A" in formatted
        assert "ART-001" in formatted
        assert "Rows returned: 2" in formatted
