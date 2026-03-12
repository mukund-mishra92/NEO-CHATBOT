class QueryReuseEngine:

    def __init__(self, classification_service, executor):
        self.classification_service = classification_service
        self.executor = executor

    def try_reuse(self, question: str):
        # Use the correct method name from QueryClassificationService
        match = self.classification_service.find_similar_classified_query(
            user_query=question,
            similarity_threshold=0.85
        )

        # The method returns a single match (or None), with 'classification' field
        if match and match.get("classification") == "correct":
            sql = match.get("generated_sql") or match.get("corrected_sql")
            if sql:
                result = self.executor.execute(sql)
                return sql, result

        return None
