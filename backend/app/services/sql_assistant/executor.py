import mysql.connector
import logging
import time
from .models import SQLExecutionResult

logger = logging.getLogger(__name__)


class SQLExecutor:

    def __init__(self, db_config):
        self.db_config = db_config

    def execute(self, sql: str) -> SQLExecutionResult:

        start = time.time()

        try:
            conn = mysql.connector.connect(**self.db_config)
            cursor = conn.cursor(dictionary=True)

            cursor.execute(sql)
            rows = cursor.fetchall()

            cursor.close()
            conn.close()

            execution_time = int((time.time() - start) * 1000)

            return SQLExecutionResult(
                rows=rows,
                row_count=len(rows),
                execution_time_ms=execution_time
            )
        except mysql.connector.Error as e:
            logger.error(f"❌ Database error: {e}")
            raise Exception(f"Database error: {e.msg if hasattr(e, 'msg') else str(e)}")
        except Exception as e:
            logger.error(f"❌ Execution error: {e}")
            raise
