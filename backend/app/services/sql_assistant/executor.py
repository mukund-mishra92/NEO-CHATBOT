import mysql.connector
import logging
import re
import time
import threading
from .models import SQLExecutionResult
from .archive_handler import ArchiveHandler

logger = logging.getLogger(__name__)

QUERY_TIMEOUT_SECONDS = 60


class SQLExecutor:

    def __init__(self, db_config):
        self.db_config = db_config
        self.archive_handler = ArchiveHandler(db_config)

    def _redirect_archive_to_main_table(self, sql: str) -> str:
        """If the AI model generated SQL against an _archive table, redirect to the main table."""
        self.archive_handler._ensure_mappings_loaded()
        if self.archive_handler._archive_table_mapping:
            # Build reverse mapping: archive_table -> main_table
            reverse_map = {
                archive: main
                for main, archive in self.archive_handler._archive_table_mapping.items()
            }
            for archive_table, main_table in reverse_map.items():
                pattern = rf'\b{re.escape(archive_table)}\b'
                if re.search(pattern, sql, re.IGNORECASE):
                    sql = re.sub(pattern, main_table, sql, flags=re.IGNORECASE)
                    logger.info(
                        f"🔄 Redirected AI-generated archive reference: "
                        f"{archive_table} → {main_table}"
                    )
        return sql

    def execute(self, sql: str, enable_archive_detection: bool = True, question: str = None, tables_used: list = None) -> SQLExecutionResult:

        start = time.time()

        try:
            # ------------------------------------------------------------------
            # STEP 1: Archive Table Detection (if enabled and conditions met)
            # ------------------------------------------------------------------
            archive_info = None
            if enable_archive_detection and question and tables_used:
                try:
                    # If the AI model directly used an _archive table, redirect
                    # the query to the main table first — the archive handler
                    # will decide whether to UNION with the archive table.
                    sql = self._redirect_archive_to_main_table(sql)

                    # Extract only the tables actually referenced in the SQL query
                    # (not the full candidate list from table selection)
                    table_pattern = r'\bFROM\s+`?(\w+)`?\b|\bJOIN\s+`?(\w+)`?\b'
                    matches = re.findall(table_pattern, sql, re.IGNORECASE)
                    sql_tables = list({m[0] or m[1] for m in matches if m[0] or m[1]})

                    archive_info = self.archive_handler.should_use_archive_for_classified_query(
                        sql_tables, question
                    )

                    if archive_info.get('archive_needed'):
                        logger.info(f"📦 Archive table(s) detected: {archive_info.get('table_archive_map')}")
                        
                        # For each main table that needs archive, modify the query
                        for main_table, archive_table in archive_info.get('table_archive_map', {}).items():
                            sql = self.archive_handler.modify_query_for_archive(
                                sql,
                                main_table,
                                archive_table
                            )
                            logger.info(f"🔄 Query modified to include UNION with {archive_table}")
                    else:
                        logger.debug(f"✅ No archive tables needed for this query")

                except Exception as e:
                    logger.warning(f"⚠️ Archive detection error (continuing with original query): {e}")
                    # Continue with original query if archive detection fails

            # ------------------------------------------------------------------
            # STEP 2: Execute Query
            # ------------------------------------------------------------------
            conn = mysql.connector.connect(**self.db_config)
            cursor = conn.cursor(dictionary=True)
            conn_id = conn.connection_id

            # Enforce read-only at session level to prevent any write operations
            cursor.execute("SET SESSION TRANSACTION READ ONLY")

            # Schedule a watchdog that kills the query after timeout
            timed_out = threading.Event()

            def _kill_query():
                timed_out.set()
                try:
                    kill_conn = mysql.connector.connect(**self.db_config)
                    kill_cursor = kill_conn.cursor()
                    kill_cursor.execute(f"KILL QUERY {conn_id}")
                    kill_cursor.close()
                    kill_conn.close()
                    logger.warning(f"⏱️ Query killed after {QUERY_TIMEOUT_SECONDS}s timeout (connection {conn_id})")
                except Exception as ke:
                    logger.error(f"Failed to kill timed-out query: {ke}")

            timer = threading.Timer(QUERY_TIMEOUT_SECONDS, _kill_query)
            timer.start()

            try:
                cursor.execute(sql)
                rows = cursor.fetchall()
            finally:
                timer.cancel()

            cursor.close()
            conn.close()

            if timed_out.is_set():
                raise Exception(
                    f"Query timed out: execution exceeded {QUERY_TIMEOUT_SECONDS}s. "
                    f"The query was too heavy and has been cancelled to protect the database."
                )

            execution_time = int((time.time() - start) * 1000)

            return SQLExecutionResult(
                rows=rows,
                row_count=len(rows),
                execution_time_ms=execution_time,
                executed_sql=sql
            )
        except mysql.connector.Error as e:
            if 'Query execution was interrupted' in str(e):
                raise Exception(
                    f"Query timed out: execution exceeded {QUERY_TIMEOUT_SECONDS}s. "
                    f"The query was too heavy and has been cancelled to protect the database."
                )
            logger.error(f"❌ Database error: {e}")
            raise Exception(f"Database error: {e.msg if hasattr(e, 'msg') else str(e)}")
        except Exception as e:
            logger.error(f"❌ Execution error: {e}")
            raise
