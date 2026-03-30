import mysql.connector
import logging
import time
import threading
from .models import SQLExecutionResult

logger = logging.getLogger(__name__)

QUERY_TIMEOUT_SECONDS = 60


class SQLExecutor:
    """
    Three separate execution pipelines — **no cross-contamination**.

    ┌─────────────────────┬─────────────┬──────────────────────────────┐
    │ Method              │ READ ONLY   │ Use-case                     │
    ├─────────────────────┼─────────────┼──────────────────────────────┤
    │ execute()           │ YES         │ LLM-generated SQL (untrusted)│
    │ execute_trusted()   │ NO          │ SP body SQL / KPI SQL        │
    │ execute_call()      │ NO          │ CALL proc(…) statements      │
    └─────────────────────┴─────────────┴──────────────────────────────┘

    SP body SQL and KPI queries are pre-defined trusted code.  They may
    contain CTEs whose materialisation creates internal temp tables —
    READ ONLY mode blocks that and causes misleading column errors.
    """

    def __init__(self, db_config):
        self.db_config = db_config

    # ==========================================================
    # Shared watchdog helper
    # ==========================================================
    def _watchdog(self, conn_id: int, label: str):
        """Return (timer, timed_out_event) for query-kill watchdog."""
        timed_out = threading.Event()

        def _kill():
            timed_out.set()
            try:
                kc = mysql.connector.connect(**self.db_config)
                kc.cursor().execute(f"KILL QUERY {conn_id}")
                kc.close()
                logger.warning(
                    f"⏱️ {label} killed after {QUERY_TIMEOUT_SECONDS}s "
                    f"timeout (conn {conn_id})"
                )
            except Exception as ke:
                logger.error(f"Failed to kill timed-out {label}: {ke}")

        timer = threading.Timer(QUERY_TIMEOUT_SECONDS, _kill)
        return timer, timed_out

    # ==========================================================
    # 1. LLM-generated SQL  (READ ONLY — untrusted)
    # ==========================================================
    def execute(self, sql: str) -> SQLExecutionResult:
        start = time.time()
        try:
            conn = mysql.connector.connect(**self.db_config)
            cursor = conn.cursor(dictionary=True)

            # Enforce read-only — LLM SQL is untrusted
            cursor.execute("SET SESSION TRANSACTION READ ONLY")

            timer, timed_out = self._watchdog(conn.connection_id, "LLM query")
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
                    f"Query timed out: exceeded {QUERY_TIMEOUT_SECONDS}s. "
                    f"The query was cancelled to protect the database."
                )

            return SQLExecutionResult(
                rows=rows,
                row_count=len(rows),
                execution_time_ms=int((time.time() - start) * 1000),
            )

        except mysql.connector.Error as e:
            if "Query execution was interrupted" in str(e):
                raise Exception(
                    f"Query timed out: exceeded {QUERY_TIMEOUT_SECONDS}s."
                )
            logger.error(f"❌ Database error: {e}")
            raise Exception(
                f"Database error: {e.msg if hasattr(e, 'msg') else str(e)}"
            )
        except Exception as e:
            logger.error(f"❌ Execution error: {e}")
            raise

    # ==========================================================
    # 2. SP body SQL / KPI SQL  (NO READ ONLY — trusted code)
    # ==========================================================
    def execute_trusted(self, sql: str, label: str = "trusted") -> SQLExecutionResult:
        """
        Execute pre-defined SQL (SP body or KPI query).

        NO SET SESSION TRANSACTION READ ONLY because:
        - These are our own verified SQL templates, not LLM-generated.
        - Complex CTEs (WITH … AS) materialise as internal temp tables;
          READ ONLY blocks that, producing misleading "Unknown column" errors.
        - We never write to the DB from this tool.
        """
        start = time.time()
        try:
            conn = mysql.connector.connect(**self.db_config)
            cursor = conn.cursor(dictionary=True)

            timer, timed_out = self._watchdog(conn.connection_id, label)
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
                    f"{label} timed out: exceeded {QUERY_TIMEOUT_SECONDS}s."
                )

            ms = int((time.time() - start) * 1000)
            logger.info(f"✅ {label} executed: {len(rows)} rows in {ms}ms")

            return SQLExecutionResult(
                rows=rows, row_count=len(rows), execution_time_ms=ms
            )

        except mysql.connector.Error as e:
            if "Query execution was interrupted" in str(e):
                raise Exception(
                    f"{label} timed out: exceeded {QUERY_TIMEOUT_SECONDS}s."
                )
            logger.error(f"❌ {label} DB error: {e}")
            raise Exception(
                f"{label} error: {e.msg if hasattr(e, 'msg') else str(e)}"
            )
        except Exception as e:
            logger.error(f"❌ {label} execution error: {e}")
            raise

    # ==========================================================
    # 3. CALL proc(…)  (NO READ ONLY, handles multiple result sets)
    # ==========================================================
    def execute_call(self, call_sql: str) -> SQLExecutionResult:
        """
        Execute a CALL statement for a stored procedure.
        Handles multi-result-set responses via cursor.nextset().
        CALL runs with SQL SECURITY DEFINER (root@%).
        """
        start = time.time()
        try:
            conn = mysql.connector.connect(**self.db_config)
            cursor = conn.cursor(dictionary=True)

            timer, timed_out = self._watchdog(conn.connection_id, "SP CALL")
            timer.start()
            try:
                cursor.execute(call_sql)
                rows = cursor.fetchall()
                # Consume any additional result sets from CALL
                while cursor.nextset():
                    pass
            finally:
                timer.cancel()

            cursor.close()
            conn.close()

            if timed_out.is_set():
                raise Exception(
                    f"SP CALL timed out: exceeded {QUERY_TIMEOUT_SECONDS}s."
                )

            ms = int((time.time() - start) * 1000)
            logger.info(f"⚙️ SP CALL executed: {len(rows)} rows in {ms}ms")

            return SQLExecutionResult(
                rows=rows, row_count=len(rows), execution_time_ms=ms
            )

        except mysql.connector.Error as e:
            if "Query execution was interrupted" in str(e):
                raise Exception(
                    f"SP CALL timed out: exceeded {QUERY_TIMEOUT_SECONDS}s."
                )
            logger.error(f"❌ SP CALL error: {e}")
            raise Exception(
                f"SP CALL error: {e.msg if hasattr(e, 'msg') else str(e)}"
            )
        except Exception as e:
            logger.error(f"❌ SP CALL execution error: {e}")
            raise
