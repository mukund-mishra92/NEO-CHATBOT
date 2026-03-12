import mysql.connector
import logging
import time
import threading
from .models import SQLExecutionResult

logger = logging.getLogger(__name__)

QUERY_TIMEOUT_SECONDS = 60


class SQLExecutor:

    def __init__(self, db_config):
        self.db_config = db_config

    def execute(self, sql: str) -> SQLExecutionResult:

        start = time.time()

        try:
            conn = mysql.connector.connect(**self.db_config)
            cursor = conn.cursor(dictionary=True)
            conn_id = conn.connection_id

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
                execution_time_ms=execution_time
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
