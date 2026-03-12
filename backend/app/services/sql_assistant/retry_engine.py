import logging
from typing import Callable, Tuple, Optional

from .models import SQLGenerationResult, SQLExecutionResult

logger = logging.getLogger(__name__)


class SQLRetryEngine:
    """
    Production-grade retry engine for SQL generation with schema-aware feedback.

    Retries on:
    - SQL syntax errors
    - Validation errors (missing LIMIT, etc.)
    - Database errors (unknown table/column)
    
    Provides intelligent feedback with closest schema matches.
    """

    def __init__(self, max_attempts: int = 3):
        self.max_attempts = max_attempts

    def run(
        self,
        generate_fn: Callable[[str, str], SQLGenerationResult],
        validator,
        executor,
        feedback_generator=None,
        schema_validator=None,
        required_tables=None,
        forbidden_tables=None,
    ) -> Tuple[SQLGenerationResult, SQLExecutionResult]:
        """
        Run SQL generation with retry logic and smart feedback
        
        Args:
            generate_fn: Function that generates SQL (takes feedback and previous_sql)
            validator: Basic SQL validator (syntax, LIMIT check, etc.)
            executor: SQL executor (runs query against DB)
            feedback_generator: Schema-aware feedback generator (optional)
            schema_validator: Schema validator (checks tables/columns exist) (optional)
        
        Returns:
            (generation_result, execution_result) tuple
        """
        feedback = None
        previous_sql = None
        last_error = None

        for attempt in range(self.max_attempts):
            logger.info(f"🔄 SQL generation attempt {attempt + 1}/{self.max_attempts}")

            try:
                # Step 1: Generate SQL
                generation_result = generate_fn(feedback, previous_sql)
                sql = generation_result.sql
                logger.info(f"✅ Generated SQL: {sql[:150]}...")

                # Step 2: Validate SQL syntax and safety
                validator.validate(sql)
                logger.info(f"✅ SQL validation passed")
                
                # Step 2.5: HARD CHECK - Enforce table validation rules BEFORE schema validation
                if (forbidden_tables or required_tables):
                    tables_used = generation_result.metadata.get('tables_used', [])
                    logger.info(f"🔍 Checking table validation: tables_used={tables_used}, required={required_tables}, forbidden={forbidden_tables}")
                    
                    # Check for forbidden table usage
                    violated = [t for t in tables_used if t in (forbidden_tables or [])]
                    if violated:
                        logger.error(f"❌ TABLE VALIDATION VIOLATION! SQL uses forbidden tables: {violated}")
                        logger.error(f"   Tables used: {tables_used}")
                        logger.error(f"   Forbidden: {forbidden_tables}")
                        error_msg = f"CRITICAL ERROR: You used FORBIDDEN tables: {', '.join(violated)}. These tables are absolutely NOT ALLOWED! "
                        if required_tables:
                            error_msg += f"You MUST use ONLY these tables: {', '.join(required_tables)}"
                        raise Exception(error_msg)
                    
                    # Check if required tables are used (if specified)
                    if required_tables:
                        has_required = any(t in tables_used for t in required_tables)
                        if not has_required:
                            logger.error(f"❌ TABLE VALIDATION VIOLATION! SQL doesn't use required tables: {required_tables}")
                            logger.error(f"   Tables used: {tables_used}")
                            logger.error(f"   Required: {required_tables}")
                            error_msg = f"CRITICAL ERROR: You MUST use one of these tables: {', '.join(required_tables)}. You used: {', '.join(tables_used)}. This is WRONG!"
                            raise Exception(error_msg)

                # Step 3: Validate schema (tables and columns exist)
                if schema_validator:
                    schema_validator.validate(sql)
                    logger.info(f"✅ Schema validation passed")

                # Step 4: Execute SQL
                execution_result = executor.execute(sql)
                logger.info(f"✅ SQL execution succeeded: {execution_result.row_count} rows")

                return generation_result, execution_result

            except Exception as e:
                last_error = e
                error_str = str(e)
                
                # Generate schema-aware feedback if available
                if feedback_generator:
                    feedback = feedback_generator.generate_feedback(error_str, sql if 'sql' in locals() else previous_sql or "")
                else:
                    feedback = error_str
                
                previous_sql = sql if 'sql' in locals() else previous_sql
                
                logger.warning(f"❌ Attempt {attempt + 1} failed: {error_str[:200]}")
                if attempt < self.max_attempts - 1:
                    logger.info(f"🔄 Retrying with enhanced feedback...")
                    logger.debug(f"Feedback: {feedback[:300]}")

        logger.error(f"❌ SQL generation failed after {self.max_attempts} attempts. Last error: {last_error}")
        raise Exception(f"SQL generation failed after retries: {last_error}")
