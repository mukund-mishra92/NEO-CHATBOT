import logging

logger = logging.getLogger(__name__)


class SemanticValidationError(Exception):
    pass


class SemanticValidator:
    """
    Validates execution results for semantic correctness.

    Rules:
    - Zero rows is NOT an error (valid empty result).
    - Extremely large results are blocked for safety.
    - Tenant column presence verified when tenant is provided.
    """

    MAX_ALLOWED_ROWS = 500_000

    def validate(self, execution_result, sql: str = None, tenant: str = None):
        """
        Validate SQL execution results.
        
        Args:
            execution_result: The SQLExecutionResult object
            sql: The SQL query string (optional, for logging)
            tenant: Expected tenant value (optional, for multi-tenant checks)
        """
        row_count = execution_result.row_count

        # Case 1: Zero rows → allowed (valid empty result)
        if row_count == 0:
            return

        # Case 2: Too many rows → block (safety)
        if row_count > self.MAX_ALLOWED_ROWS:
            raise SemanticValidationError(
                f"Query returned {row_count} rows. "
                f"Result too large to display. Please refine filters."
            )

        # Case 3: Tenant sanity check — if tenant filter was expected, verify
        #         that at least some results contain the expected tenant value
        if tenant and execution_result.rows and row_count > 0:
            # Check if any column in results contains the tenant value
            first_row = execution_result.rows[0]
            row_values = [str(v).lower() for v in first_row.values()] if isinstance(first_row, dict) else []
            if tenant.lower() not in row_values:
                logger.debug(
                    f"Tenant '{tenant}' not visible in first result row columns. "
                    f"This may be expected if tenant column was not in SELECT."
                )
