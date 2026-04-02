"""
Integration Tests — SQL Pipeline Flow
Target: Full pipeline from preprocessing → validation → schema check

Tests the integration between:
  - SynonymResolver → EntityResolver → QueryPreprocessor
  - SQLValidator → SchemaValidator chain
  - Retry engine with validation chain
  
Uses REAL implementations with mocked LLM + DB.
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))

from app.services.sql_assistant.validator import SQLValidator, SQLValidationError
from app.services.sql_assistant.schema_validator import SchemaValidator, SchemaValidationError
from app.services.sql_assistant.entity_resolver import EntityResolver
from app.services.sql_assistant.synonym_resolver import SynonymResolver
from app.services.sql_assistant.formatter import SQLFormatter
from app.services.sql_assistant.confidence import ConfidenceEvaluator
from app.services.sql_assistant.semantic_validator import SemanticValidator, SemanticValidationError
from app.services.sql_assistant.retry_engine import SQLRetryEngine
from app.services.sql_assistant.models import SQLGenerationResult, SQLExecutionResult


@pytest.mark.integration
class TestPreprocessingPipeline:
    """Test SynonymResolver + EntityResolver integration."""

    def test_synonym_then_entity(self):
        syn = SynonymResolver()
        ent = EntityResolver()

        question = "show robot 5 at workstation 3"
        normalized = syn.normalize(question)
        entities = ent.resolve(normalized)

        assert "bot" in normalized.lower()
        assert "station" in normalized.lower()
        # EntityResolver should still pick up the entity numbers
        # even after synonym normalization
        assert entities.get("BOT_ID") == "BOT-0005" or entities.get("STATION_ID") == "STATION-0003"

    def test_synonym_product_then_entity(self):
        syn = SynonymResolver()
        ent = EntityResolver()

        question = "picks for sku at bin 10"
        normalized = syn.normalize(question)
        entities = ent.resolve(normalized)

        assert "article" in normalized
        assert entities.get("BIN_ID") == "BIN-0010"


@pytest.mark.integration
class TestValidationChain:
    """Test SQLValidator → SchemaValidator chain (same as retry engine uses)."""

    def test_valid_query_passes_both(self, sample_schema):
        sql_validator = SQLValidator()
        schema_validator = SchemaValidator(sample_schema)

        sql = (
            "SELECT article, COUNT(*) AS cnt "
            "FROM bal_pick_dtl "
            "GROUP BY article "
            "ORDER BY cnt DESC LIMIT 10"
        )

        sql_validator.validate(sql)
        schema_validator.validate(sql)

    def test_valid_join_passes_both(self, sample_schema):
        sql_validator = SQLValidator()
        schema_validator = SchemaValidator(sample_schema)

        sql = (
            "SELECT p.article, m.description "
            "FROM bal_pick_dtl p "
            "JOIN bal_master_article m ON p.article = m.article "
            "LIMIT 10"
        )

        sql_validator.validate(sql)
        schema_validator.validate(sql)

    def test_invalid_table_caught_by_schema(self, sample_schema):
        sql_validator = SQLValidator()
        schema_validator = SchemaValidator(sample_schema)

        sql = "SELECT * FROM fake_table LIMIT 10"
        sql_validator.validate(sql)  # Passes syntax check

        with pytest.raises(SchemaValidationError, match="Invalid table"):
            schema_validator.validate(sql)

    def test_dangerous_sql_caught_by_validator(self, sample_schema):
        sql_validator = SQLValidator()

        with pytest.raises(SQLValidationError, match="Write operations"):
            sql_validator.validate("SELECT * FROM (DROP TABLE x) LIMIT 10")


@pytest.mark.integration
class TestRetryEngineIntegration:
    """Test retry engine with real validators and mock generator + executor."""

    def test_first_attempt_success(self, sample_schema):
        engine = SQLRetryEngine(max_attempts=3)
        sql_validator = SQLValidator()
        schema_validator = SchemaValidator(sample_schema)

        gen_result = SQLGenerationResult(
            sql="SELECT COUNT(*) FROM bal_pick_dtl",
            confidence=0.9, explanation="test", assumptions=[],
            metadata={"tables_used": ["bal_pick_dtl"]}
        )
        exec_result = SQLExecutionResult(
            rows=[{"count": 42}], row_count=1, execution_time_ms=50
        )

        gen_fn = MagicMock(return_value=gen_result)
        executor = MagicMock()
        executor.execute.return_value = exec_result

        result_gen, result_exec = engine.run(
            gen_fn, sql_validator, executor,
            schema_validator=schema_validator
        )

        assert result_gen.sql == "SELECT COUNT(*) FROM bal_pick_dtl"
        assert result_exec.row_count == 1

    def test_retry_on_bad_table(self, sample_schema):
        """First generates bad table, retry generates correct table."""
        engine = SQLRetryEngine(max_attempts=3)
        sql_validator = SQLValidator()
        schema_validator = SchemaValidator(sample_schema)

        bad_gen = SQLGenerationResult(
            sql="SELECT * FROM bad_table LIMIT 10",
            confidence=0.5, explanation="", assumptions=[],
            metadata={"tables_used": ["bad_table"]}
        )
        good_gen = SQLGenerationResult(
            sql="SELECT * FROM bal_pick_dtl LIMIT 10",
            confidence=0.9, explanation="", assumptions=[],
            metadata={"tables_used": ["bal_pick_dtl"]}
        )
        exec_result = SQLExecutionResult(
            rows=[{"id": 1}], row_count=1, execution_time_ms=50
        )

        gen_fn = MagicMock(side_effect=[bad_gen, good_gen])
        executor = MagicMock()
        executor.execute.return_value = exec_result

        result_gen, _ = engine.run(
            gen_fn, sql_validator, executor,
            schema_validator=schema_validator
        )

        assert "bal_pick_dtl" in result_gen.sql
        assert gen_fn.call_count == 2


@pytest.mark.integration
class TestFormattingPipeline:
    """Test confidence evaluation → formatting chain."""

    def test_confidence_then_format(self):
        evaluator = ConfidenceEvaluator()
        formatter = SQLFormatter()

        gen_result = SQLGenerationResult(
            sql="SELECT COUNT(*) FROM bal_pick_dtl",
            confidence=0.9, explanation="test", assumptions=[],
            metadata={}
        )
        exec_result = SQLExecutionResult(
            rows=[{"total": 42}], row_count=1, execution_time_ms=50
        )

        confidence = evaluator.compute(gen_result, exec_result)
        formatted = formatter.format(
            "total picks", gen_result.sql, exec_result, confidence
        )

        assert confidence > 0.5
        assert "```sql" in formatted
        assert "Rows Returned: 1" in formatted
        assert "42" in formatted


@pytest.mark.integration
class TestSemanticValidationPipeline:
    """Test semantic validation as final safety gate."""

    def test_normal_result_passes(self):
        validator = SemanticValidator()
        exec_result = SQLExecutionResult(
            rows=[{"id": 1}], row_count=1, execution_time_ms=50
        )
        validator.validate(exec_result)

    def test_huge_result_blocked(self):
        validator = SemanticValidator()
        exec_result = SQLExecutionResult(
            rows=[], row_count=600_000, execution_time_ms=50
        )
        with pytest.raises(SemanticValidationError, match="too large"):
            validator.validate(exec_result)
