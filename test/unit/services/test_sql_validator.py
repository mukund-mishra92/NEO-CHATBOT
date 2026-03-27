"""
Unit Tests — SQLValidator (simple syntax/safety validator)
Target: backend/app/services/sql_assistant/validator.py

Tests the 5 security rules:
  1. Only SELECT / WITH allowed
  2. No multi-statement (semicolons)
  3. No write keywords (INSERT, DROP, etc.)
  4. No dangerous functions (SLEEP, BENCHMARK)
  5. LIMIT required unless aggregation
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.validator import SQLValidator, SQLValidationError


@pytest.fixture
def validator():
    return SQLValidator()


# ===================================================================
# RULE 1: Only SELECT / WITH
# ===================================================================
class TestOnlySelectAllowed:

    def test_select_passes(self, validator):
        validator.validate("SELECT * FROM users LIMIT 10")

    def test_with_cte_passes(self, validator):
        validator.validate(
            "WITH cte AS (SELECT id FROM users) SELECT * FROM cte LIMIT 10"
        )

    def test_insert_blocked(self, validator):
        with pytest.raises(SQLValidationError, match="Only SELECT"):
            validator.validate("INSERT INTO users (name) VALUES ('a')")

    def test_update_blocked(self, validator):
        with pytest.raises(SQLValidationError, match="Only SELECT"):
            validator.validate("UPDATE users SET name='a' WHERE id=1")

    def test_delete_blocked(self, validator):
        with pytest.raises(SQLValidationError, match="Only SELECT"):
            validator.validate("DELETE FROM users WHERE id=1")

    def test_drop_blocked(self, validator):
        with pytest.raises(SQLValidationError, match="Only SELECT"):
            validator.validate("DROP TABLE users")

    def test_empty_string(self, validator):
        with pytest.raises(SQLValidationError, match="Only SELECT"):
            validator.validate("")

    def test_whitespace_only(self, validator):
        with pytest.raises(SQLValidationError, match="Only SELECT"):
            validator.validate("   ")


# ===================================================================
# RULE 2: No multiple statements
# ===================================================================
class TestNoMultipleStatements:

    def test_single_statement_passes(self, validator):
        validator.validate("SELECT * FROM users LIMIT 10")

    def test_trailing_semicolon_passes(self, validator):
        validator.validate("SELECT * FROM users LIMIT 10;")

    def test_mid_semicolon_blocked(self, validator):
        with pytest.raises(SQLValidationError, match="Multiple statements"):
            validator.validate("SELECT 1; SELECT 2")

    def test_injection_attempt_blocked(self, validator):
        with pytest.raises(SQLValidationError, match="Multiple statements"):
            validator.validate("SELECT 1; DROP TABLE users")


# ===================================================================
# RULE 3: No write keywords
# ===================================================================
class TestNoWriteKeywords:

    @pytest.mark.parametrize("keyword", [
        "INSERT", "UPDATE", "DELETE", "DROP", "ALTER",
        "CREATE", "TRUNCATE", "GRANT", "REVOKE", "REPLACE"
    ])
    def test_write_keywords_blocked(self, validator, keyword):
        sql = f"SELECT * FROM ({keyword} INTO t) LIMIT 10"
        with pytest.raises(SQLValidationError, match="Write operations"):
            validator.validate(sql)

    def test_select_with_create_in_string_blocked(self, validator):
        """Even inside strings — regex catches it. Doc: known limitation."""
        sql = "SELECT * FROM t WHERE name = 'CREATE something' LIMIT 10"
        with pytest.raises(SQLValidationError, match="Write operations"):
            validator.validate(sql)


# ===================================================================
# RULE 4: No dangerous functions
# ===================================================================
class TestNoDangerousFunctions:

    @pytest.mark.parametrize("func", [
        "SLEEP(5)", "BENCHMARK(1000, SHA1('x'))", "LOAD_FILE('/etc/passwd')",
        "INTO OUTFILE '/tmp/data'", "INTO DUMPFILE '/tmp/data'"
    ])
    def test_dangerous_functions_blocked(self, validator, func):
        sql = f"SELECT {func} FROM t LIMIT 10"
        with pytest.raises(SQLValidationError):
            validator.validate(sql)


# ===================================================================
# RULE 5: LIMIT required unless aggregation
# ===================================================================
class TestLimitRequired:

    def test_no_limit_blocked(self, validator):
        with pytest.raises(SQLValidationError, match="LIMIT clause required"):
            validator.validate("SELECT * FROM users")

    def test_with_limit_passes(self, validator):
        validator.validate("SELECT * FROM users LIMIT 100")

    def test_aggregation_without_limit_passes(self, validator):
        validator.validate("SELECT COUNT(*) FROM users")

    def test_sum_without_limit_passes(self, validator):
        validator.validate("SELECT SUM(amount) FROM orders")

    def test_avg_without_limit_passes(self, validator):
        validator.validate("SELECT AVG(price) FROM products")

    def test_max_min_without_limit_passes(self, validator):
        validator.validate("SELECT MAX(id), MIN(id) FROM users")

    def test_non_aggregation_without_limit_blocked(self, validator):
        with pytest.raises(SQLValidationError, match="LIMIT"):
            validator.validate("SELECT id, name FROM users WHERE id > 5")

    def test_limit_on_newline_passes(self, validator):
        sql = "SELECT * FROM users\nLIMIT 50"
        validator.validate(sql)


# ===================================================================
# COMBINED EDGE CASES
# ===================================================================
class TestEdgeCases:

    def test_valid_complex_query(self, validator):
        sql = (
            "SELECT p.article, COUNT(*) AS cnt "
            "FROM bal_pick_dtl p "
            "JOIN bal_master_article m ON p.article = m.article "
            "WHERE p.`host-location` = 'frk' "
            "GROUP BY p.article "
            "ORDER BY cnt DESC LIMIT 10"
        )
        validator.validate(sql)

    def test_cte_with_aggregation(self, validator):
        sql = (
            "WITH daily AS ("
            "  SELECT DATE(pick_time) AS d, COUNT(*) AS c "
            "  FROM bal_pick_dtl GROUP BY d"
            ") SELECT AVG(c) FROM daily"
        )
        validator.validate(sql)

    def test_subquery_passes(self, validator):
        sql = (
            "SELECT * FROM ("
            "  SELECT article, COUNT(*) AS c FROM bal_pick_dtl GROUP BY article"
            ") sub ORDER BY c DESC LIMIT 5"
        )
        validator.validate(sql)
