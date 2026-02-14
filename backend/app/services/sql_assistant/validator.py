import re
import logging

logger = logging.getLogger(__name__)


class SQLValidationError(Exception):
    pass


class SQLValidator:

    def validate(self, sql: str):
        sql_lower = sql.lower().strip()

        # Rule 1: Only SELECT queries
        if not sql_lower.startswith("select"):
            raise SQLValidationError("Only SELECT queries are allowed.")

        # Rule 2: No multiple statements
        if ";" in sql.strip()[:-1]:
            raise SQLValidationError("Multiple statements not allowed.")

        # Rule 3: LIMIT clause required (unless it's an aggregation query)
        has_limit = " limit " in sql_lower or "\nlimit " in sql_lower
        
        # Check if it's an aggregation query (COUNT, SUM, AVG, MAX, MIN)
        is_aggregation = bool(re.search(r'\b(count|sum|avg|max|min)\s*\(', sql_lower))
        
        if not has_limit and not is_aggregation:
            raise SQLValidationError(
                "LIMIT clause required for safety. Add 'LIMIT 100' to the end of your query."
            )
        
        # Log if aggregation without LIMIT (allowed but noted)
        if is_aggregation and not has_limit:
            logger.info("✅ Aggregation query without LIMIT - allowed")
