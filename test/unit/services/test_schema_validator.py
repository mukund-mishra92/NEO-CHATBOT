"""
Unit Tests — SchemaValidator
Target: backend/app/services/sql_assistant/schema_validator.py

Tests:
  - Valid table detection
  - Invalid table raises SchemaValidationError
  - Column validation via table.column reference
  - Backtick-wrapped table names
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.schema_validator import SchemaValidator, SchemaValidationError


@pytest.fixture
def schema_validator(sample_schema):
    return SchemaValidator(sample_schema)


# ===================================================================
# TABLE EXTRACTION
# ===================================================================
class TestTableExtraction:

    def test_extract_single_table(self, schema_validator):
        tables = schema_validator._extract_tables("SELECT * FROM bal_pick_dtl LIMIT 10")
        assert "bal_pick_dtl" in tables

    def test_extract_join_tables(self, schema_validator):
        sql = (
            "SELECT * FROM bal_pick_dtl p "
            "JOIN bal_master_article m ON p.article = m.article LIMIT 10"
        )
        tables = schema_validator._extract_tables(sql)
        assert "bal_pick_dtl" in tables
        assert "bal_master_article" in tables

    def test_extract_backtick_table(self, schema_validator):
        tables = schema_validator._extract_tables("SELECT * FROM `bal_pick_dtl` LIMIT 10")
        assert "bal_pick_dtl" in tables

    def test_deduplicate_tables(self, schema_validator):
        sql = (
            "SELECT * FROM bal_pick_dtl p "
            "JOIN bal_pick_dtl p2 ON p.id = p2.id LIMIT 10"
        )
        tables = schema_validator._extract_tables(sql)
        assert tables.count("bal_pick_dtl") == 1


# ===================================================================
# TABLE VALIDATION
# ===================================================================
class TestTableValidation:

    def test_valid_table_passes(self, schema_validator):
        schema_validator.validate("SELECT * FROM bal_pick_dtl LIMIT 10")

    def test_invalid_table_raises(self, schema_validator):
        with pytest.raises(SchemaValidationError, match="Invalid table"):
            schema_validator.validate("SELECT * FROM non_existent_table LIMIT 10")

    def test_multiple_valid_tables_pass(self, schema_validator):
        sql = (
            "SELECT * FROM bal_pick_dtl p "
            "JOIN bal_master_article m ON p.article = m.article LIMIT 10"
        )
        schema_validator.validate(sql)

    def test_one_invalid_among_valid_raises(self, schema_validator):
        sql = (
            "SELECT * FROM bal_pick_dtl p "
            "JOIN fake_table f ON p.id = f.id LIMIT 10"
        )
        with pytest.raises(SchemaValidationError, match="Invalid table.*fake_table"):
            schema_validator.validate(sql)


# ===================================================================
# COLUMN VALIDATION (table.column references)
# ===================================================================
class TestColumnValidation:

    def test_valid_column_passes(self, schema_validator):
        sql = "SELECT bal_pick_dtl.article FROM bal_pick_dtl LIMIT 10"
        schema_validator.validate(sql)

    def test_invalid_column_raises(self, schema_validator):
        sql = "SELECT bal_pick_dtl.nonexistent FROM bal_pick_dtl LIMIT 10"
        with pytest.raises(SchemaValidationError, match="Invalid column.*nonexistent"):
            schema_validator.validate(sql)

    def test_column_without_table_prefix_not_validated(self, schema_validator):
        """Bare column references are NOT validated — by design."""
        sql = "SELECT nonexistent FROM bal_pick_dtl LIMIT 10"
        schema_validator.validate(sql)  # Should pass (no table.column pattern)


# ===================================================================
# EDGE CASES
# ===================================================================
class TestSchemaEdgeCases:

    def test_empty_schema(self):
        sv = SchemaValidator({})
        with pytest.raises(SchemaValidationError, match="Invalid table"):
            sv.validate("SELECT * FROM any_table LIMIT 10")

    def test_subquery_tables_extracted(self, schema_validator):
        sql = (
            "SELECT * FROM bal_pick_dtl "
            "WHERE article IN (SELECT article FROM bal_master_article) LIMIT 10"
        )
        schema_validator.validate(sql)
