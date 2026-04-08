import logging
import re
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

# Similarity threshold above which we TRUST a verified query even if its
# tables are not in the local schema CSV (Case-5 fix).
# At 99 %+ the query is virtually identical to a human-confirmed correct query.
_HIGH_CONFIDENCE_THRESHOLD = 0.99

# Minimum similarity to accept classified query reuse (raised for precision).
_REUSE_SIMILARITY_THRESHOLD = 0.88


class QueryReuseEngine:

    def __init__(self, classification_service, executor, validator=None, schema_validator=None):
        self.classification_service = classification_service
        self.executor = executor
        self.validator = validator
        self.schema_validator = schema_validator

    def _apply_time_substitution(self, sql: str, time_from: Optional[str],
                                  time_to: Optional[str]) -> str:
        """Replace hardcoded date literals in reused SQL with actual time range.
        Only touches common timestamp/date patterns, not arbitrary strings."""
        if not time_from or not time_to:
            return sql

        # Replace BETWEEN 'date' AND 'date' patterns
        sql = re.sub(
            r"BETWEEN\s+'(\d{4}-\d{2}-\d{2}[^']*)'\s+AND\s+'(\d{4}-\d{2}-\d{2}[^']*)'",
            f"BETWEEN '{time_from}' AND '{time_to}'",
            sql, flags=re.IGNORECASE
        )
        return sql

    def _apply_tenant_substitution(self, sql: str,
                                    tenant_column: str,
                                    tenant_values: list) -> str:
        """Replace tenant/location filter values in reused SQL."""
        if not tenant_values:
            return sql

        if len(tenant_values) == 1:
            val = tenant_values[0]
            # Replace `host-location` IN ('old_val')  → IN ('new_val')
            sql = re.sub(
                rf"`?{re.escape(tenant_column)}`?\s*IN\s*\([^)]+\)",
                f"`{tenant_column}` IN ('{val}')",
                sql, flags=re.IGNORECASE
            )
            # Replace `host-location` = 'old_val'  → = 'new_val'
            sql = re.sub(
                rf"`?{re.escape(tenant_column)}`?\s*=\s*'[^']*'",
                f"`{tenant_column}` = '{val}'",
                sql, flags=re.IGNORECASE
            )
        else:
            in_list = ", ".join(f"'{v}'" for v in tenant_values)
            sql = re.sub(
                rf"`?{re.escape(tenant_column)}`?\s*(?:IN\s*\([^)]+\)|=\s*'[^']*')",
                f"`{tenant_column}` IN ({in_list})",
                sql, flags=re.IGNORECASE
            )
        return sql

    def try_reuse(self, question: str,
                  entities: Optional[Dict[str, Any]] = None,
                  time_from: Optional[str] = None,
                  time_to: Optional[str] = None,
                  tenant_column: Optional[str] = None):
        """
        Attempt to reuse a previously classified 'correct' SQL query.

        Production safety:
        - Only reuses queries classified as 'correct'
        - Validates SQL through SQLValidator + SchemaValidator before execution
        - Falls back to None (fresh generation) on any error

        Case-5 fix — High-confidence trust:
        - When similarity >= 0.99 AND the only failure is SchemaValidationError
          (table missing from schema CSV), we attempt direct DB execution because:
            * The query was verified by a human as correct.
            * The table may genuinely exist in the DB but be absent from the CSV.
            * Falling to fresh generation risks hallucinating wrong tables instead.
          If DB execution also fails, we fall back to fresh generation and log
          the discrepancy so the admin can update the schema CSV.
        """
        try:
            match = self.classification_service.find_similar_classified_query(
                user_query=question,
                similarity_threshold=_REUSE_SIMILARITY_THRESHOLD
            )

            if not match or match.get("classification") != "correct":
                return None

            sql = match.get("corrected_sql") or match.get("generated_sql")
            if not sql:
                return None

            similarity_score = match.get("similarity_score", 0.0)
            is_high_confidence = similarity_score >= _HIGH_CONFIDENCE_THRESHOLD

            # ── Template-based parameter substitution ──
            # Update time and tenant parameters in reused SQL so it reflects
            # the current user's context, not the original query's context.
            if time_from and time_to:
                sql = self._apply_time_substitution(sql, time_from, time_to)
                logger.debug(f"📝 Reuse: applied time substitution [{time_from} → {time_to}]")

            if tenant_column and entities and entities.get(tenant_column):
                tenant_vals = entities[tenant_column]
                if isinstance(tenant_vals, str):
                    tenant_vals = [tenant_vals]
                sql = self._apply_tenant_substitution(sql, tenant_column, tenant_vals)
                logger.debug(f"📝 Reuse: applied tenant substitution → {tenant_vals}")

            # ── Case-5 logic: try schema validation; handle gracefully for
            #    high-confidence matches where the table may just be missing
            #    from the CSV but present in the actual database. ──────────
            schema_validation_failed = False
            schema_error_detail = ""

            if self.validator:
                self.validator.validate(sql)   # syntax / basic SQL validity

            if self.schema_validator:
                try:
                    self.schema_validator.validate(sql)
                except Exception as sv_err:
                    schema_validation_failed = True
                    schema_error_detail = str(sv_err)

                    if is_high_confidence:
                        # Log the discrepancy but don't bail out yet.
                        logger.warning(
                            f"⚠️ Case-5 / High-confidence reuse "
                            f"(similarity={similarity_score:.3f}): SchemaValidator "
                            f"rejected SQL because '{schema_error_detail}'. "
                            f"Table may be missing from schema CSV but present in DB. "
                            f"Attempting direct DB execution to verify."
                        )
                    else:
                        # Low-to-medium confidence → trust the schema validator.
                        raise

            result = self.executor.execute(sql)

            if schema_validation_failed:
                # Execution succeeded even though the CSV said the table was missing.
                logger.info(
                    f"✅ Case-5 / High-confidence reuse recovered: SQL executed "
                    f"successfully despite schema CSV discrepancy "
                    f"('{schema_error_detail}'). "
                    f"Please add the missing table to Table_information.csv."
                )
            else:
                logger.info(
                    f"✅ Reused classified query (similarity={similarity_score:.3f}): "
                    f"original='{match.get('user_query', '')[:60]}' → {result.row_count} rows"
                )

            return sql, result

        except Exception as e:
            logger.warning(f"⚠️ Reuse failed, falling back to fresh generation: {e}")
            return None
