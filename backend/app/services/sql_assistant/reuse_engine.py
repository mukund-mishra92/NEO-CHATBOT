import logging

logger = logging.getLogger(__name__)


class QueryReuseEngine:

    def __init__(self, classification_service, executor, validator=None, schema_validator=None):
        self.classification_service = classification_service
        self.executor = executor
        self.validator = validator
        self.schema_validator = schema_validator

    def try_reuse(self, question: str):
        """
        Attempt to reuse a previously classified 'correct' SQL query.
        
        Production safety:
        - Only reuses queries classified as 'correct'
        - Validates SQL through SQLValidator + SchemaValidator before execution
        - Falls back to None (fresh generation) on any error
        """
        try:
            match = self.classification_service.find_similar_classified_query(
                user_query=question,
                similarity_threshold=0.85
            )

            if not match or match.get("classification") != "correct":
                return None

            sql = match.get("corrected_sql") or match.get("generated_sql")
            if not sql:
                return None

            # 🔥 VALIDATE before executing — stale SQL may reference dropped tables/columns
            if self.validator:
                self.validator.validate(sql)
            if self.schema_validator:
                self.schema_validator.validate(sql)

            result = self.executor.execute(sql)

            logger.info(
                f"✅ Reused classified query (similarity >= 0.85): "
                f"original='{match.get('user_query', '')[:60]}' → {result.row_count} rows"
            )
            return sql, result

        except Exception as e:
            logger.warning(f"⚠️ Reuse failed, falling back to fresh generation: {e}")
            return None
