

import logging
import re
from typing import Dict, List, Tuple, Optional, Any
from datetime import datetime, timedelta
import mysql.connector

logger = logging.getLogger(__name__)


class ArchiveHandler:
    """
    Detects and handles archive table requirements for SQL queries.
    Auto-discovers archive tables and their timestamp columns from the database.
    """

    def __init__(self, db_config: Dict[str, Any]):
        """
        Initialize the archive handler with database configuration.
        Auto-discovers archive table mappings and timestamp columns from DB.

        Args:
            db_config: Database connection configuration dict
        """
        self.db_config = db_config

        # Auto-discovered mappings (populated on first use, then cached)
        self._archive_table_mapping: Optional[Dict[str, str]] = None
        self._table_timestamp_columns: Optional[Dict[str, str]] = None

    # ----------------------------------------------------------
    # AUTO-DISCOVERY
    # ----------------------------------------------------------
    def _ensure_mappings_loaded(self, db_connection=None):
        """Load archive table mappings and timestamp columns from DB if not yet cached."""
        if self._archive_table_mapping is not None and self._table_timestamp_columns is not None:
            return

        try:
            close_conn = False
            conn = db_connection
            if not conn:
                conn = mysql.connector.connect(**self.db_config)
                close_conn = True

            try:
                self._archive_table_mapping = self._discover_archive_tables(conn)
                self._table_timestamp_columns = self._discover_timestamp_columns(conn)

                logger.info(
                    f"📦 Auto-discovered {len(self._archive_table_mapping)} archive table mappings: "
                    f"{self._archive_table_mapping}"
                )
                logger.info(
                    f"🕐 Auto-discovered timestamp columns for {len(self._table_timestamp_columns)} tables"
                )
            finally:
                if close_conn and conn:
                    conn.close()

        except Exception as e:
            logger.error(f"❌ Failed to auto-discover archive mappings: {e}")
            # Fallback to empty mappings so the system doesn't crash
            self._archive_table_mapping = self._archive_table_mapping or {}
            self._table_timestamp_columns = self._table_timestamp_columns or {}

    def _discover_archive_tables(self, conn) -> Dict[str, str]:
        """
        Query the database to find all tables ending with '_archive'
        and map them to their main table counterparts.

        Returns:
            Dict mapping main_table -> archive_table
        """
        mapping = {}
        cursor = conn.cursor()
        cursor.execute("SHOW TABLES")
        all_tables = {row[0] for row in cursor.fetchall()}
        cursor.close()

        for table_name in all_tables:
            if table_name.endswith("_archive"):
                main_table = table_name[: -len("_archive")]
                if main_table in all_tables:
                    mapping[main_table] = table_name
                    logger.debug(f"  📦 Mapped: {main_table} -> {table_name}")

        return mapping

    def _discover_timestamp_columns(self, conn) -> Dict[str, str]:
        """
        For every table that appears in the archive mapping (both main and archive),
        discover the best timestamp/datetime column by querying INFORMATION_SCHEMA.

        Heuristic priority:
          1. Column name contains 'timestamp' (case-insensitive)
          2. Column name contains 'date' or 'time' (case-insensitive)
          3. First DATETIME/TIMESTAMP column found

        Returns:
            Dict mapping table_name -> timestamp_column_name
        """
        if not self._archive_table_mapping:
            return {}

        # Collect all tables we need timestamp info for
        tables_to_check = set()
        for main_table, archive_table in self._archive_table_mapping.items():
            tables_to_check.add(main_table)
            tables_to_check.add(archive_table)

        db_name = self.db_config.get("database", "")
        ts_columns: Dict[str, str] = {}

        cursor = conn.cursor(dictionary=True)

        for table_name in tables_to_check:
            cursor.execute(
                "SELECT COLUMN_NAME, DATA_TYPE "
                "FROM INFORMATION_SCHEMA.COLUMNS "
                "WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s "
                "AND DATA_TYPE IN ('datetime', 'timestamp') "
                "ORDER BY ORDINAL_POSITION",
                (db_name, table_name),
            )
            rows = cursor.fetchall()

            if not rows:
                logger.warning(f"⚠️ No datetime/timestamp column found for {table_name}")
                continue

            # Pick best column using heuristic priority
            best = None
            for row in rows:
                col = row["COLUMN_NAME"]
                col_lower = col.lower()
                if "timestamp" in col_lower:
                    best = col
                    break
            if not best:
                for row in rows:
                    col = row["COLUMN_NAME"]
                    col_lower = col.lower()
                    if "date" in col_lower or "time" in col_lower:
                        best = col
                        break
            if not best:
                best = rows[0]["COLUMN_NAME"]

            ts_columns[table_name] = best
            logger.debug(f"  🕐 {table_name} -> {best}")

        cursor.close()
        return ts_columns

    def refresh_mappings(self):
        """Force re-discovery of archive tables and timestamp columns."""
        self._archive_table_mapping = None
        self._table_timestamp_columns = None
        logger.info("🔄 Archive mappings cleared — will re-discover on next use")

    def should_use_archive(
        self,
        table_name: str,
        requested_start_date: Optional[datetime] = None,
        requested_end_date: Optional[datetime] = None,
        db_connection=None
    ) -> Tuple[bool, Optional[str], Optional[Dict[str, datetime]]]:
        """
        Determine if archive table is needed for the query.

        Args:
            table_name: Main table name to check
            requested_start_date: Requested start date (from user query)
            requested_end_date: Requested end date (from user query)
            db_connection: Optional existing DB connection (reuse if provided)

        Returns:
            Tuple of (needs_archive: bool, archive_table: Optional[str], date_info: Optional[Dict])
            - needs_archive: True if archive table is needed
            - archive_table: Name of archive table if needed, else None
            - date_info: Dict with keys:
                - 'main_table_min_date': Earliest date in main table
                - 'main_table_max_date': Latest date in main table
                - 'requested_start_date': User requested start date
                - 'requested_end_date': User requested end date
        """

        # Ensure dynamic mappings are loaded
        self._ensure_mappings_loaded(db_connection)

        # Check if archive table exists for this main table
        if table_name not in self._archive_table_mapping:
            logger.debug(f"⚠️ No archive table mapping for {table_name}")
            return False, None, None

        archive_table = self._archive_table_mapping[table_name]

        # If no date range specified, no need to check archive
        if not requested_start_date and not requested_end_date:
            logger.debug(f"ℹ️ No date range in query - archive not needed for {table_name}")
            return False, None, None

        try:
            # Get actual date range from main table
            date_info = self._get_table_date_range(
                table_name,
                db_connection
            )

            if not date_info:
                logger.warning(f"⚠️ Could not determine date range for {table_name}")
                return False, None, None

            date_info['requested_start_date'] = requested_start_date
            date_info['requested_end_date'] = requested_end_date

            main_min = date_info['main_table_min_date']
            main_max = date_info['main_table_max_date']

            # Determine if archive is needed
            # Archive tables contain OLD historical data that has been moved out
            # of the main table. We only need the archive when the user requests
            # data OLDER than what the main table still holds (start < main_min).
            needs_archive = False

            if requested_start_date:
                # If user is asking for data BEFORE the main table's minimum date
                if requested_start_date < main_min:
                    logger.info(
                        f"📦 Archive needed: Requested start {requested_start_date} "
                        f"is BEFORE main table min {main_min}"
                    )
                    needs_archive = True

            if not needs_archive:
                logger.info(
                    f"✅ Archive not needed: "
                    f"Main table ({main_min} to {main_max}) covers "
                    f"requested period ({requested_start_date} to {requested_end_date})"
                )

            return needs_archive, archive_table if needs_archive else None, date_info

        except Exception as e:
            logger.error(f"❌ Error checking archive requirement: {e}")
            return False, None, None

    def _get_table_date_range(
        self,
        table_name: str,
        existing_connection=None
    ) -> Optional[Dict[str, datetime]]:
        """
        Query the database to get MIN and MAX dates from the main table.

        Args:
            table_name: Table to query
            existing_connection: Optional existing connection to reuse

        Returns:
            Dict with 'main_table_min_date' and 'main_table_max_date', or None on error
        """

        self._ensure_mappings_loaded(existing_connection)

        if table_name not in self._table_timestamp_columns:
            logger.warning(f"⚠️ No timestamp column mapping for {table_name}")
            return None

        timestamp_col = self._table_timestamp_columns[table_name]

        query = f"""
            SELECT 
                MIN({timestamp_col}) as min_date,
                MAX({timestamp_col}) as max_date
            FROM {table_name}
            LIMIT 1
        """

        try:
            close_conn = False
            conn = existing_connection

            if not conn:
                conn = mysql.connector.connect(**self.db_config)
                close_conn = True

            try:
                cursor = conn.cursor(dictionary=True)
                cursor.execute(query)
                result = cursor.fetchone()
                cursor.close()

                if result and result['min_date'] and result['max_date']:
                    logger.info(
                        f"📊 Date range from {table_name}: "
                        f"{result['min_date']} to {result['max_date']}"
                    )
                    return {
                        'main_table_min_date': result['min_date'],
                        'main_table_max_date': result['max_date']
                    }
                else:
                    logger.warning(f"⚠️ No data found in {table_name}")
                    return None

            finally:
                if close_conn and conn:
                    conn.close()

        except Exception as e:
            logger.error(f"❌ Error getting date range from {table_name}: {e}")
            return None

    def extract_date_range_from_question(self, question: str) -> Tuple[Optional[datetime], Optional[datetime]]:
        """
        Extract date range from user question using regex patterns.

        Supports patterns like:
        - "last 7 days", "past 30 days", "last N days"
        - "from YYYY-MM-DD to YYYY-MM-DD"
        - "since YYYY-MM-DD"
        - "before YYYY-MM-DD", "after YYYY-MM-DD"

        Args:
            question: User question text

        Returns:
            Tuple of (start_date, end_date) or (None, None) if no date range found
        """

        question_lower = question.lower()
        today = datetime.now().date()
        end_date = today

        # Pattern: "last N days" / "past N days"
        last_days_match = re.search(r'(?:last|past)\s+(\d+)\s+days?', question_lower)
        if last_days_match:
            num_days = int(last_days_match.group(1))
            start_date = today - timedelta(days=num_days)
            logger.info(f"📅 Extracted '{num_days} days': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "last N weeks" / "past N weeks"
        weeks_match = re.search(r'(?:last|past)\s+(\d+)\s+weeks?', question_lower)
        if weeks_match:
            num_weeks = int(weeks_match.group(1))
            start_date = today - timedelta(weeks=num_weeks)
            logger.info(f"📅 Extracted '{num_weeks} weeks': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "last N months" / "past N months" / "N months back/ago"
        months_match = re.search(r'(?:last|past)\s+(\d+)\s+months?', question_lower)
        if not months_match:
            months_match = re.search(r'(\d+)\s+months?\s+(?:back|ago)', question_lower)
        if months_match:
            num_months = int(months_match.group(1))
            # Approximate months as 30 days each
            start_date = today - timedelta(days=num_months * 30)
            logger.info(f"📅 Extracted '{num_months} months': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "last N years" / "past N years" / "N years back/ago"
        years_match = re.search(r'(?:last|past)\s+(\d+)\s+years?', question_lower)
        if not years_match:
            years_match = re.search(r'(\d+)\s+years?\s+(?:back|ago)', question_lower)
        if years_match:
            num_years = int(years_match.group(1))
            start_date = today - timedelta(days=num_years * 365)
            logger.info(f"📅 Extracted '{num_years} years': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "last week" (no number)
        if re.search(r'last\s+week\b', question_lower):
            start_date = today - timedelta(weeks=1)
            logger.info(f"📅 Extracted 'last week': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "last month" (no number)
        if re.search(r'last\s+month\b', question_lower):
            start_date = today - timedelta(days=30)
            logger.info(f"📅 Extracted 'last month': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "last year" (no number)
        if re.search(r'last\s+year\b', question_lower):
            start_date = today - timedelta(days=365)
            logger.info(f"📅 Extracted 'last year': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "from YYYY-MM-DD to YYYY-MM-DD"
        date_range_match = re.search(
            r'from\s+(\d{4}-\d{2}-\d{2})\s+to\s+(\d{4}-\d{2}-\d{2})',
            question_lower
        )
        if date_range_match:
            try:
                start_date = datetime.strptime(date_range_match.group(1), '%Y-%m-%d').date()
                end_date = datetime.strptime(date_range_match.group(2), '%Y-%m-%d').date()
                logger.info(f"📅 Extracted date range: {start_date} to {end_date}")
                return (
                    datetime.combine(start_date, datetime.min.time()),
                    datetime.combine(end_date, datetime.max.time())
                )
            except ValueError as e:
                logger.warning(f"⚠️ Failed to parse date range: {e}")

        # Pattern: "since YYYY-MM-DD"
        since_match = re.search(r'since\s+(\d{4}-\d{2}-\d{2})', question_lower)
        if since_match:
            try:
                start_date = datetime.strptime(since_match.group(1), '%Y-%m-%d').date()
                logger.info(f"📅 Extracted 'since' date: {start_date} to {end_date}")
                return (
                    datetime.combine(start_date, datetime.min.time()),
                    datetime.combine(end_date, datetime.max.time())
                )
            except ValueError as e:
                logger.warning(f"⚠️ Failed to parse since date: {e}")

        # Pattern: "before/after YYYY-MM-DD"
        before_match = re.search(r'before\s+(\d{4}-\d{2}-\d{2})', question_lower)
        if before_match:
            try:
                end_date_extracted = datetime.strptime(before_match.group(1), '%Y-%m-%d').date()
                logger.info(f"📅 Extracted 'before' date: None to {end_date_extracted}")
                return (None, datetime.combine(end_date_extracted, datetime.max.time()))
            except ValueError as e:
                logger.warning(f"⚠️ Failed to parse before date: {e}")

        after_match = re.search(r'after\s+(\d{4}-\d{2}-\d{2})', question_lower)
        if after_match:
            try:
                start_date_extracted = datetime.strptime(after_match.group(1), '%Y-%m-%d').date()
                logger.info(f"📅 Extracted 'after' date: {start_date_extracted} to None")
                return (datetime.combine(start_date_extracted, datetime.min.time()), None)
            except ValueError as e:
                logger.warning(f"⚠️ Failed to parse after date: {e}")

        # Pattern: "this year" / "current year"
        if re.search(r'(?:this|current)\s+year\b', question_lower):
            start_date = today.replace(month=1, day=1)
            logger.info(f"📅 Extracted 'this year': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "this month" / "current month"
        if re.search(r'(?:this|current)\s+month\b', question_lower):
            start_date = today.replace(day=1)
            logger.info(f"📅 Extracted 'this month': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "this week" / "current week"
        if re.search(r'(?:this|current)\s+week\b', question_lower):
            start_date = today - timedelta(days=today.weekday())
            logger.info(f"📅 Extracted 'this week': {start_date} to {end_date}")
            return (
                datetime.combine(start_date, datetime.min.time()),
                datetime.combine(end_date, datetime.max.time())
            )

        # Pattern: "today"
        if re.search(r'\btoday\b', question_lower):
            logger.info(f"📅 Extracted 'today': {today} to {today}")
            return (
                datetime.combine(today, datetime.min.time()),
                datetime.combine(today, datetime.max.time())
            )

        # Pattern: "yesterday"
        if re.search(r'\byesterday\b', question_lower):
            yesterday = today - timedelta(days=1)
            logger.info(f"📅 Extracted 'yesterday': {yesterday} to {yesterday}")
            return (
                datetime.combine(yesterday, datetime.min.time()),
                datetime.combine(yesterday, datetime.max.time())
            )

        # Pattern: "in YYYY" / "in year YYYY" (e.g., "in 2025")
        in_year_match = re.search(r'\bin\s+(?:year\s+)?(\d{4})\b', question_lower)
        if in_year_match:
            year = int(in_year_match.group(1))
            if 2000 <= year <= 2100:
                start_date = datetime(year, 1, 1).date()
                year_end = datetime(year, 12, 31).date()
                actual_end = min(year_end, today)
                logger.info(f"📅 Extracted 'in {year}': {start_date} to {actual_end}")
                return (
                    datetime.combine(start_date, datetime.min.time()),
                    datetime.combine(actual_end, datetime.max.time())
                )

        logger.debug(f"ℹ️ No date range pattern found in question")
        return None, None

    def modify_query_for_archive(
        self,
        sql: str,
        main_table: str,
        archive_table: str,
        host_location: Optional[str] = None
    ) -> str:
        """
        Modify the generated SQL query to include archive table via UNION or JOIN.

        Strategy:
        - If query selects from main table only, create a UNION with archive table query
        - Preserves WHERE conditions and formatting

        Args:
            sql: Original SQL query (SELECT statement)
            main_table: Main table name
            archive_table: Archive table name
            host_location: Optional host-location for multi-tenant filtering

        Returns:
            Modified SQL query that includes archive table
        """

        # Remove leading/trailing whitespace and semicolon
        sql = sql.strip()
        if sql.endswith(';'):
            sql = sql[:-1]

        # Get timestamp column for this table (from auto-discovered mapping)
        self._ensure_mappings_loaded()
        timestamp_col = self._table_timestamp_columns.get(main_table, 'logged_timestamp')

        # If the archive table is already referenced in the SQL (AI model added it), skip
        if re.search(r'\b' + re.escape(archive_table) + r'\b', sql, re.IGNORECASE):
            logger.info(
                f"ℹ️ Archive table {archive_table} already present in SQL — skipping UNION modification"
            )
            return sql

        # Check if single table query (SELECT ... FROM main_table WHERE ...)
        table_pattern = rf'\bFROM\s+{re.escape(main_table)}\b'

        if not re.search(table_pattern, sql, re.IGNORECASE):
            logger.warning(
                f"⚠️ Archive table modification failed: "
                f"Query does not select from {main_table}"
            )
            return sql

        # Build UNION query pattern
        try:
            # Create archive query by replacing main table with archive table
            archive_sql = re.sub(
                table_pattern,
                f" FROM {archive_table} ",
                sql,
                flags=re.IGNORECASE
            )

            # Wrap both queries in parentheses and UNION
            combined_sql = f"""
(
{sql}
)
UNION ALL
(
{archive_sql}
)
"""

            # If there's a LIMIT clause, add it after UNION
            limit_match = re.search(r'LIMIT\s+(\d+)\s*$', sql, re.IGNORECASE)
            if limit_match:
                limit_value = limit_match.group(1)
                # Remove LIMIT from both individual queries
                sql_clean = re.sub(r'\s+LIMIT\s+\d+\s*$', '', sql, flags=re.IGNORECASE)
                archive_sql_clean = re.sub(r'\s+LIMIT\s+\d+\s*$', '', archive_sql, flags=re.IGNORECASE)

                combined_sql = f"""
(
{sql_clean}
)
UNION ALL
(
{archive_sql_clean}
)
LIMIT {limit_value}
"""

            logger.info(
                f"✅ Query modified for archive table: "
                f"Added UNION with {archive_table}"
            )
            return combined_sql.strip()

        except Exception as e:
            logger.error(f"❌ Error modifying query for archive: {e}")
            return sql

    def should_use_archive_for_classified_query(
        self,
        tables_used: List[str],
        question: str,
        db_connection=None
    ) -> Dict[str, Any]:


        self._ensure_mappings_loaded(db_connection)

        archives_to_add = {}
        start_date, end_date = self.extract_date_range_from_question(question)

        for main_table in tables_used:
            if main_table in self._archive_table_mapping:
                needs_archive, archive_table, date_info = self.should_use_archive(
                    main_table,
                    start_date,
                    end_date,
                    db_connection
                )

                if needs_archive and archive_table:
                    archives_to_add[main_table] = archive_table

        return {
            'archive_needed': len(archives_to_add) > 0,
            'table_archive_map': archives_to_add,
            'date_range': (start_date, end_date),
            'tables_to_union': list(archives_to_add.values())
        }
