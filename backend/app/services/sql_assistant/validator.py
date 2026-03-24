import re
import logging

logger = logging.getLogger(__name__)

# Dangerous MySQL functions that must never appear in generated SQL
_DANGEROUS_FUNCTIONS = re.compile(
    r'\b(SLEEP|BENCHMARK|LOAD_FILE|INTO\s+OUTFILE|INTO\s+DUMPFILE|'
    r'SYSTEM|EXEC|EXECUTE|sp_executesql)\b',
    re.IGNORECASE
)


class SQLValidationError(Exception):
    pass


class SQLValidator:

    def validate(self, sql: str):
        sql_lower = sql.lower().strip()
        sql_stripped = sql.strip()

        # Rule 1: Only SELECT / WITH (CTE) queries
        if not (sql_lower.startswith("select") or sql_lower.startswith("with")):
            raise SQLValidationError("Only SELECT queries are allowed.")

        # Rule 2: No multiple statements (semicolons in the middle)
        if ";" in sql_stripped[:-1]:
            raise SQLValidationError("Multiple statements not allowed.")

        # Rule 3: No dangerous write keywords anywhere in the query
        write_keywords = re.compile(
            r'\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|REPLACE)\b',
            re.IGNORECASE
        )
        if write_keywords.search(sql):
            raise SQLValidationError("Write operations are not allowed in SQL queries.")

        # Rule 4: No dangerous functions (SLEEP, BENCHMARK, LOAD_FILE, etc.)
        if _DANGEROUS_FUNCTIONS.search(sql):
            raise SQLValidationError("Dangerous SQL functions are not allowed.")

        # Rule 5: LIMIT clause required (unless it's an aggregation query)
        has_limit = " limit " in sql_lower or "\nlimit " in sql_lower
        is_aggregation = bool(re.search(r'\b(count|sum|avg|max|min)\s*\(', sql_lower))
        
        if not has_limit and not is_aggregation:
            raise SQLValidationError(
                "LIMIT clause required for safety. Add 'LIMIT 100' to the end of your query."
            )
        
        if is_aggregation and not has_limit:
            logger.info("✅ Aggregation query without LIMIT - allowed")
