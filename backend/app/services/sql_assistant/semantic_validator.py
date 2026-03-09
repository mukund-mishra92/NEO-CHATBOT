class SemanticValidationError(Exception):
    pass


class SemanticValidator:
    """
    Validates execution results.

    Rules:
    - Zero rows is NOT an error.
    - Extremely large results are blocked for safety.
    """

    # Hard safety threshold (protect DB + memory)
    MAX_ALLOWED_ROWS = 500_000

    def validate(self, execution_result):
        row_count = execution_result.row_count

        # Case 1: Zero rows → allowed
        if row_count == 0:
            return

        # Case 3: Too many rows → block
        if row_count > self.MAX_ALLOWED_ROWS:
            raise SemanticValidationError(
                f"Query returned {row_count} rows. "
                f"Result too large to display. Please refine filters."
            )

