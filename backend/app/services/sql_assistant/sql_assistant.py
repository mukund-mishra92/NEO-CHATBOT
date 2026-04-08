from app.models.schemas import ChatResponse, ChatbotType
from app.services.sql_engine import SQLEngine
from app.services.chat_history_service import ChatHistoryService
from app.services.query_classification_service1 import QueryClassificationService
from app.core.config import settings
from app.services.ai_config_service import get_ai_config_service
from .models import SQLGenerationResult
from .cache_manager import QueryCacheManager
from .reuse_engine import QueryReuseEngine
from .validator import SQLValidator
from .executor import SQLExecutor
from .confidence import ConfidenceEvaluator
from .formatter import SQLFormatter
from .retry_engine import SQLRetryEngine
from .learning import QueryLearningManager
from .query_preprocessor import QueryPreprocessor
from .schema_validator import SchemaValidator
from .semantic_validator import SemanticValidator
from .schema_feedback import SchemaFeedbackGenerator
from .table_priority_loader import TablePriorityLoader
from .table_selector import TableSelector
from .kpi_resolver import DashboardKPIResolver
from .sp_resolver import SPResolver
from .archive_handler import ArchiveHandler


import logging
import csv
import json
import re

logger = logging.getLogger(__name__)


class SQLAssistantService:

    # ----------------------------------------------------------
    # INIT
    # ----------------------------------------------------------
    def __init__(self):
        ai_cfg = get_ai_config_service().get_config()
        sql_provider = ai_cfg.get("active_provider", "openai")
        sql_model = ai_cfg.get("sql_model", "gpt-5.2")

        if sql_provider == "groq":
            sql_api_key = settings.GROQ_API_KEY
        else:
            sql_api_key = settings.OPENAI_API_KEY

        self._active_sql_provider = sql_provider
        self._active_sql_model = sql_model

        self.db_config = {
            "host": settings.DB_HOST,
            "port": settings.DB_PORT,
            "user": settings.DB_USER,
            "password": settings.DB_PASSWORD,
            "database": settings.DB_NAME
        }
        self.multi_tenant_enabled = settings.MULTI_TENANT_ENABLED
        self.tenant_column = settings.TENANT_COLUMN
        self.default_tenant = settings.DEFAULT_TENANT

        csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
        business_path = settings.DATA_DIR / "database" / "table_descriptions.json"

        # Load business context
        try:
            with open(business_path, "r", encoding="utf-8") as f:
                raw = json.load(f)

            self.business_context = {
                item["table_name"]: item
                for item in raw
            }

            logger.info(f"📘 Loaded business context for {len(self.business_context)} tables")

        except Exception as e:
            logger.warning(f"⚠️ Failed to load business context JSON: {e}")
            self.business_context = {}

        self.sql_engine = SQLEngine(
            api_key=sql_api_key,
            model=sql_model,
            provider=sql_provider,
            schema_csv_path=str(csv_path),
            db_config=self.db_config
        )

        self.chat_history_service = ChatHistoryService(self.db_config)

        self.classification_service = QueryClassificationService(
            settings.DATA_DIR / "classification"
        )

        self.cache = QueryCacheManager()
        self.executor = SQLExecutor(self.db_config)
        self.validator = SQLValidator()
        self.confidence = ConfidenceEvaluator()
        self.formatter = SQLFormatter()
        self.retry_engine = SQLRetryEngine()

        self.learning = QueryLearningManager(
            self.chat_history_service,
            self.classification_service
        )

        self.preprocessor = QueryPreprocessor()

        self.schema = self._load_schema(csv_path)
        self.schema_validator = SchemaValidator(self.schema)
        self.semantic_validator = SemanticValidator()
        self.feedback_generator = SchemaFeedbackGenerator(self.schema)

        # Reuse engine needs validator + schema_validator — must init after schema is loaded
        self.reuse_engine = QueryReuseEngine(
            self.classification_service,
            self.executor,
            validator=self.validator,
            schema_validator=self.schema_validator
        )

        validations_file = settings.DATA_DIR / "database" / "table_priority_validations.jsonl"
        self.table_priority_loader = TablePriorityLoader(validations_file)


        self.table_selector = TableSelector(
            schema=self.schema,
            table_metadata=self.business_context
        )

        # 🔥 Multi-tenant DISTINCT rule (applies to ALL tables when tenant is enabled)
        # In a multi-tenant system, any ID column is unique only WITHIN a tenant.
        # COUNT(DISTINCT id_col) across tenants will under-count or give wrong results.
        self.multi_tenant_distinct_warning = (
            f"CRITICAL MULTI-TENANT RULE: In this system, record IDs (e.g. BIN_ID, ORDER_ID, "
            f"TASK_ID, STATION_ID,BOT_ID etc.) are unique only within a `{self.tenant_column}` site. "
            f"They are NOT globally unique across all sites. "
            f"Therefore: NEVER use COUNT(DISTINCT <id_column>) — it will give wrong results. "
            f"Instead use COUNT(*) to count records. "
            f"If you truly need globally unique counts, use COUNT(DISTINCT <id_col>, `{self.tenant_column}`)."
        )

        # 📊 Dashboard KPI Resolver — matches questions to pre-built Grafana KPIs
        try:
            kpi_registry_path = str(settings.DATA_DIR / "dashboard-data" / "kpi_registry.json")
            self.kpi_resolver = DashboardKPIResolver(registry_path=kpi_registry_path)
            logger.info(f"📊 Dashboard KPI resolver loaded with {len(self.kpi_resolver.kpis)} KPIs")
        except Exception as e:
            logger.warning(f"⚠️ Dashboard KPI resolver failed to load: {e}")
            self.kpi_resolver = None

        try:
            sp_registry_path = str(settings.DATA_DIR / "BROI_SP" / "SP_registry.json")
            self.sp_resolver = SPResolver(
                registry_path=sp_registry_path,
                tenant_column=self.tenant_column,
                schema=self.schema,
            )
            logger.info(f"⚙️ SP resolver loaded with {len(self.sp_resolver.sps)} SPs")
        except Exception as e:
            logger.warning(f"⚠️ SP resolver failed to load: {e}")
            self.sp_resolver = None

        # Archive handler (dynamic _archive table routing for historical date ranges)
        self.archive_handler = ArchiveHandler(self.db_config)

        logger.info(f"✅ SQLAssistantService initialized with {len(self.schema)} tables")

    # ----------------------------------------------------------
    # LOAD SCHEMA
    # ----------------------------------------------------------
    def _load_schema(self, csv_path):
        schema = {}

        with open(csv_path, newline="", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            headers = {h.lower().strip(): h for h in reader.fieldnames}

            table_key = headers["table_name"]
            columns_key = headers["table_columns(data type)"]

            for row in reader:
                table = row[table_key].strip()
                columns_raw = row[columns_key]

                if not table:
                    continue

                schema[table] = []

                if columns_raw:
                    columns = columns_raw.split(",")
                    for col in columns:
                        col_name = col.split("(")[0].strip()
                        if col_name:
                            schema[table].append(col_name)

        return schema

    # ----------------------------------------------------------
    # LEARNED TABLE EXTRACTION
    # ----------------------------------------------------------
    def _get_learned_tables(self, question: str):
        match = self.classification_service.find_similar_classified_query(
            user_query=question,
            similarity_threshold=0.85
        )

        if match and match.get("tables_used"):
            return match["tables_used"]

        return []

    # ----------------------------------------------------------
    # ENTITY ENFORCEMENT
    # ----------------------------------------------------------
    # def _enforce_entities_in_sql(self, sql: str, entities: dict) -> str:
    #     for key, value in entities.items():

    #         in_pattern = rf"\b{key}\b\s+IN\s*\([^)]+\)"
    #         sql = re.sub(in_pattern, f"{key} = '{value}'", sql, flags=re.IGNORECASE)

    #         eq_pattern = rf"\b{key}\b\s*=\s*'[^']+'"
    #         sql = re.sub(eq_pattern, f"{key} = '{value}'", sql, flags=re.IGNORECASE)

    #     return sql

    def _enforce_entities_in_sql(self, sql: str, entities: dict) -> str:
        """
        Enforce entity values in SQL by replacing any existing values.
        Now includes tenant column to fix any typos or unmapped values.
        """
        import re
        
        for key, value in entities.items():
            
            # 🔥 SKIP internal metadata keys (e.g., _multi_tenant, _all_sites, _tenant_confidence)
            if key.startswith('_'):
                continue
            
            # 🔥 Handle tenant column with backticks (e.g., `host-location`)
            # Need to escape special characters in column name for regex
            if key == self.tenant_column:
                # Escape special characters for regex (e.g., host-location → host\-location)
                escaped_key = re.escape(key)
                
                # Handle list values (multi-tenant)
                if isinstance(value, list):
                    if len(value) == 1:
                        # Convert IN to = for single value
                        in_pattern = rf"`{escaped_key}`\s+IN\s*\([^)]+\)"
                        sql = re.sub(in_pattern, f"`{key}` = '{value[0]}'", sql, flags=re.IGNORECASE)
                        
                        # Replace any = pattern
                        eq_pattern = rf"`{escaped_key}`\s*=\s*'[^']+'"
                        sql = re.sub(eq_pattern, f"`{key}` = '{value[0]}'", sql, flags=re.IGNORECASE)
                    else:
                        # Multiple values - use IN
                        in_pattern = rf"`{escaped_key}`\s+IN\s*\([^)]+\)"
                        values_str = "', '".join(value)
                        sql = re.sub(in_pattern, f"`{key}` IN ('{values_str}')", sql, flags=re.IGNORECASE)
                continue
            
            # 🔥 SKIP other list values (handled above for tenant)
            if isinstance(value, list):
                continue

            # Standard entity enforcement (no special characters)
            in_pattern = rf"\b{key}\b\s+IN\s*\([^)]+\)"
            sql = re.sub(in_pattern, f"{key} = '{value}'", sql, flags=re.IGNORECASE)

            eq_pattern = rf"\b{key}\b\s*=\s*'[^']+'"
            sql = re.sub(eq_pattern, f"{key} = '{value}'", sql, flags=re.IGNORECASE)

        return sql

    def _map_tenant_to_actual_values(self, entities: dict) -> dict:
        """
        Map extracted tenant names to actual database values using embedding similarity.
        
        Example:
            User query: "alarms at location bangalore"
            Extracted: entities["host-location"] = ["BANGALORE"]
            Database has: "BLR" (abbreviation)
            Mapped: entities["host-location"] = ["BLR"]
        
        Args:
            entities: Dictionary containing extracted tenant values
        
        Returns:
            Updated entities with mapped tenant values
        """
        logger.info(f"🔍 DEBUG - _map_tenant_to_actual_values called with entities: {entities}")
        
        if not hasattr(self.preprocessor, 'tenant_resolver') or not self.preprocessor.tenant_resolver:
            logger.warning("⚠️ DEBUG - No tenant_resolver found")
            return entities
        
        tenant_values = entities.get(self.tenant_column)
        logger.info(f"🔍 DEBUG - tenant_column: {self.tenant_column}, tenant_values: {tenant_values}")
        
        if not tenant_values:
            logger.warning("⚠️ DEBUG - No tenant values found in entities")
            return entities
        
        # Ensure list format
        if not isinstance(tenant_values, list):
            tenant_values = [tenant_values]
        
        try:
            # Fetch actual distinct values from DB (cached after first call)
            # This is the authoritative source — avoids using configured placeholder names
            if not hasattr(self, '_cached_tenant_values') or not self._cached_tenant_values:
                self._cached_tenant_values = self.preprocessor.tenant_resolver.fetch_actual_tenant_values(
                    db_config=self.db_config,
                    tenant_column=self.tenant_column
                )
                logger.info(f"📦 Cached {len(self._cached_tenant_values)} tenant values from database")

            # ── _all_sites: replace configured placeholder list with real DB values ──
            # Bug fix: get_all_tenants() returns configured names like ['SHAKTI', 'BANGALORE',
            # 'MUMBAI', 'DELHI', ...] which may not exist in the DB. Replace with actual DB
            # values so KPI queries / SQL filters work correctly.
            if entities.get("_all_sites"):
                if self._cached_tenant_values:
                    entities[self.tenant_column] = list(self._cached_tenant_values)
                    logger.info(
                        f"✅ All-sites: replaced configured tenants with actual DB values: "
                        f"{self._cached_tenant_values}"
                    )
                else:
                    logger.warning("⚠️ All-sites mode but no DB values found — keeping configured values")
                return entities

            if not self._cached_tenant_values:
                logger.warning("⚠️ No tenant values found in database, skipping mapping")
                return entities

            # ── Map each extracted tenant to actual DB value ──────────────────────
            mapped_values = []
            for extracted_tenant in tenant_values:
                mapped_value = self.preprocessor.tenant_resolver.map_to_actual_value(
                    extracted_tenant=extracted_tenant,
                    actual_values=self._cached_tenant_values,
                    threshold=0.5  # Lower threshold for abbreviation matching
                )
                if mapped_value:
                    mapped_values.append(mapped_value)
                else:
                    logger.warning(f"⚠️ No mapping found for '{extracted_tenant}', keeping original")
                    mapped_values.append(extracted_tenant)

            entities[self.tenant_column] = mapped_values
            logger.info(f"✅ Mapped tenants: {tenant_values} → {mapped_values}")

        except Exception as e:
            logger.error(f"❌ Error mapping tenant values: {e}")
            # Keep original values on error

        return entities

    def _inject_tenant_filter(self, sql: str, entities: dict) -> str:
        """
        Inject host_location filter into SQL query.
        Handles single tenant, multi-tenant, and all-sites cases.
        
        Args:
            sql: Generated SQL query
            entities: Extracted entities including tenant information
            
        Returns:
            SQL with tenant filter injected
        """
        if not self.multi_tenant_enabled:
            logger.debug("Multi-tenant mode disabled, skipping tenant filter")
            return sql
        
        # Check if this is an ALL SITES query (aggregate across all locations)
        if entities.get("_all_sites") is True:
            logger.info("✅ ALL SITES query detected - NO tenant filter will be applied (includes all data)")
            return sql
        
        # Check if this is a LOCATION BREAKDOWN query (grouped by location, no WHERE filter)
        if entities.get("_location_breakdown") is True:
            logger.info("✅ LOCATION BREAKDOWN query detected - NO tenant WHERE filter (data grouped by location)")
            return sql
        
        tenant_values = entities.get(self.tenant_column)
        
        if not tenant_values:
            logger.error("❌ No tenant values found in entities")
            raise ValueError(f"Tenant ({self.tenant_column}) must be specified for multi-tenant queries.")
        
        # Ensure tenant_values is a list
        if not isinstance(tenant_values, list):
            tenant_values = [tenant_values]
        
        # Check if tenant filter already in SQL (case insensitive)
        if self.tenant_column.lower() in sql.lower():
            logger.info(f"✅ Tenant filter already present in SQL")
            return sql
        
        # Build WHERE clause based on number of tenants
        # Use backticks to escape column names with special characters (e.g., host-location)
        # 🔥 NEW: Detect table alias/name to avoid ambiguous column errors in JOINs
        table_prefix = self._detect_main_table_prefix(sql)
        
        if table_prefix:
            # Table-qualified column: bal.`host-location` or bot_alarm_log.`host-location`
            escaped_column = f"{table_prefix}.`{self.tenant_column}`"
        else:
            # No JOIN detected, use simple column name
            escaped_column = f"`{self.tenant_column}`"
        
        if len(tenant_values) == 1:
            # Single tenant: WHERE `host-location` = 'FRK'
            tenant_filter = f"{escaped_column} = '{tenant_values[0]}'"
            filter_type = "single"
        else:
            # Multiple tenants: WHERE `host-location` IN ('FRK', 'SHAKTI')
            tenant_list = "', '".join(tenant_values)
            tenant_filter = f"{escaped_column} IN ('{tenant_list}')"
            filter_type = "multi"
        
        logger.info(f"🔧 Injecting {filter_type}-tenant filter: {tenant_filter}")
        
        # Inject tenant filter
        sql = self._insert_where_clause(sql, tenant_filter)
        
        return sql

    def _replace_tenant_filter(self, sql: str, entities: dict) -> str:
        """
        Replace any existing tenant filter in SQL with the CURRENT session's tenant.
        
        Used by the reuse path: a classified query stored for 'shakti' must be
        re-targeted to 'frk' if the current user is asking about FRK.
        
        Strategy:
        1. Strip existing `host-location` = 'xxx' or IN ('x','y') conditions
        2. Call _inject_tenant_filter() to add the correct one
        """
        import re
        
        tenant_col = self.tenant_column  # "host-location"
        
        # Check if tenant filter already present in SQL
        # Pattern matches:  `host-location` = 'xxx'  or  `host-location` IN ('x','y')
        # With optional table prefix like bal.`host-location`
        escaped_col = re.escape(tenant_col)
        
        # Remove existing tenant filter (handles both = and IN, with optional backticks/prefix)
        pattern = (
            r"(?:\w+\.)?"                   # optional table_alias.
            r"(?:`" + escaped_col + r"`|" + escaped_col + r")"  # `host-location` or host-location
            r"\s*"                           # optional whitespace  
            r"(?:"                           # either:
            r"=\s*'[^']*'"                   #   = 'value'
            r"|IN\s*\([^)]*\)"              #   IN ('v1', 'v2')
            r")"
        )
        
        # Try to remove the tenant condition from WHERE clause
        sql_cleaned = sql
        
        # Remove "AND <tenant_filter>" or "<tenant_filter> AND"
        and_pattern = r"\s*AND\s+" + pattern
        sql_cleaned = re.sub(and_pattern, "", sql_cleaned, flags=re.IGNORECASE)
        
        pattern_and = pattern + r"\s+AND\s+"
        sql_cleaned = re.sub(pattern_and, "", sql_cleaned, flags=re.IGNORECASE)
        
        # If the tenant was the ONLY WHERE condition: "WHERE <tenant_filter>"
        where_only = r"WHERE\s+" + pattern + r"\s*(?=GROUP|ORDER|LIMIT|HAVING|;|$)"
        sql_cleaned = re.sub(where_only, "", sql_cleaned, flags=re.IGNORECASE)
        
        if sql_cleaned != sql:
            logger.info(f"🔄 Stripped old tenant filter from reused SQL for re-injection")
        
        # Now inject the correct tenant filter for the current session
        return self._inject_tenant_filter(sql_cleaned, entities)

    def _detect_main_table_prefix(self, sql: str) -> str:
        """
        Detect table alias or name from FROM clause to avoid ambiguous column errors.
        
        Examples:
            FROM bot_alarm_log bal JOIN ... → "bal"
            FROM bot_alarm_log JOIN ... → "bot_alarm_log"
            FROM alarms → ""
        
        Returns:
            Table alias or name if JOINs present, empty string otherwise
        """
        import re
        
        sql_upper = sql.upper()
        
        # Check if query has JOINs (if no JOINs, no ambiguity issue)
        if "JOIN" not in sql_upper:
            return ""
        
        # SQL keywords that are NOT aliases
        sql_keywords = {'JOIN', 'INNER', 'LEFT', 'RIGHT', 'OUTER', 'CROSS', 'WHERE', 
                        'GROUP', 'ORDER', 'HAVING', 'LIMIT', 'UNION', 'ON'}
        
        # Extract FROM clause: FROM table_name [alias]
        from_match = re.search(r'\bFROM\s+(\w+)(?:\s+(\w+))?', sql, re.IGNORECASE)
        
        if from_match:
            table_name = from_match.group(1)  # Main table name
            potential_alias = from_match.group(2)  # Could be alias or keyword
            
            # Check if the second word is actually an alias (not a SQL keyword)
            if potential_alias and potential_alias.upper() not in sql_keywords:
                # It's an alias
                logger.debug(f"🔍 Detected main table: {table_name}, alias: {potential_alias}")
                return potential_alias
            else:
                # No alias, use table name
                logger.debug(f"🔍 Detected main table: {table_name}, no alias")
                return table_name
        
        logger.warning(f"⚠️ Could not detect table prefix from SQL with JOIN")
        return ""

    def _insert_where_clause(self, sql: str, filter_clause: str) -> str:
        """
        Intelligently insert WHERE clause into SQL query.
        Handles:
        - Queries with existing WHERE
        - Queries with JOIN (insert after all JOINs)
        - Queries without WHERE

        IMPORTANT: Uses regex word-boundary matching for WHERE so that
        newline-formatted SQL (`\\nWHERE `) is handled correctly.
        Simple `' WHERE ' in sql.upper()` misses newline-prefixed WHERE
        and causes a duplicate WHERE injection → MySQL syntax error 1064.
        """
        import re
        sql_upper = sql.upper()

        # Case 1: Existing WHERE clause — use regex to handle any whitespace before WHERE
        where_match = re.search(r'\bWHERE\b', sql_upper)
        if where_match:
            where_pos = where_match.end()  # Position right after "WHERE"
            # Skip any leading whitespace so we land on the first condition
            while where_pos < len(sql) and sql[where_pos] in (' ', '\t', '\n', '\r'):
                where_pos += 1

            # Find end of WHERE clause (before GROUP BY/ORDER BY/LIMIT/HAVING)
            end_keywords = ["GROUP BY", "ORDER BY", "HAVING", "LIMIT"]
            end_pos = len(sql)
            for keyword in end_keywords:
                kw_match = re.search(r'\b' + keyword.replace(' ', r'\s+') + r'\b', sql_upper[where_pos:])
                if kw_match:
                    end_pos = min(end_pos, where_pos + kw_match.start())

            # Rebuild: ...FROM/JOIN... WHERE <new_filter> AND (<original_conditions>) GROUP BY...
            original_conditions = sql[where_pos:end_pos].strip()
            where_keyword_start = where_match.start()
            return (
                sql[:where_keyword_start] +
                f"WHERE {filter_clause} AND ({original_conditions}) " +
                sql[end_pos:]
            )

        # Case 2: No WHERE — find insertion point before GROUP BY / ORDER BY / LIMIT
        else:
            insert_pos = self._find_clause_position(sql)
            return (
                sql[:insert_pos].rstrip() +
                f"\nWHERE {filter_clause}\n" +
                sql[insert_pos:]
            )

    def _find_clause_position(self, sql: str) -> int:
        """
        Find position to insert WHERE clause.
        Looks for GROUP BY, ORDER BY, LIMIT, HAVING.
        """
        sql_upper = sql.upper()
        
        # Find position before these keywords
        keywords = ["GROUP BY", "ORDER BY", "LIMIT", "HAVING"]
        
        for keyword in keywords:
            pos = sql_upper.find(keyword)
            if pos != -1:
                return pos
        
        # If no keywords, insert before end (but after all JOINs)
        last_join = sql_upper.rfind("JOIN")
        if last_join != -1:
            # Find end of that join clause
            join_end = sql.find("\n", last_join)
            if join_end != -1:
                return join_end + 1
        
        return len(sql)  # End of query

    def _extract_tables_from_sql(self, sql: str) -> list:
        """
        Extract table names referenced in FROM/JOIN clauses.
        Returns de-duplicated names preserving query order.
        """
        tables = []
        seen = set()

        # Matches FROM/JOIN <table>, with optional backticks and schema prefix
        matches = re.findall(
            r'\b(?:FROM|JOIN)\s+`?([\w.-]+)`?(?:\s+\w+)?',
            sql,
            flags=re.IGNORECASE,
        )

        for raw_table in matches:
            table_name = raw_table.split('.')[-1].strip('`')
            if table_name and table_name not in seen:
                seen.add(table_name)
                tables.append(table_name)

        return tables

    def _apply_archive_if_needed(self, sql: str, question: str) -> str:
        """
        Decide if archive tables are needed based on date range and main-table data window.
        If needed, rewrites SQL with UNION ALL against discovered _archive tables.
        """
        if not self.archive_handler:
            return sql

        try:
            tables_used = self._extract_tables_from_sql(sql)
            if not tables_used:
                return sql

            archive_plan = self.archive_handler.should_use_archive_for_classified_query(
                tables_used=tables_used,
                question=question,
            )

            if not archive_plan.get('archive_needed'):
                logger.info("✅ Archive check complete: main table range covers requested period")
                return sql

            updated_sql = sql
            for main_table, archive_table in archive_plan.get('table_archive_map', {}).items():
                updated_sql = self.archive_handler.modify_query_for_archive(
                    sql=updated_sql,
                    main_table=main_table,
                    archive_table=archive_table,
                )

            if updated_sql != sql:
                logger.info(f"📦 Archive SQL enabled for tables: {archive_plan.get('table_archive_map')}")

            return updated_sql

        except Exception as e:
            logger.error(f"❌ Archive routing failed, using original SQL: {e}")
            return sql

    def _refresh_sql_engine_if_needed(self):
        """Recreate SQL engine if admin provider/model changed at runtime."""
        ai_cfg = get_ai_config_service().get_config()
        provider = ai_cfg.get("active_provider", "openai")
        model = ai_cfg.get("sql_model", "gpt-5.2")

        if provider == self._active_sql_provider and model == self._active_sql_model:
            return

        csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
        api_key = settings.GROQ_API_KEY if provider == "groq" else settings.OPENAI_API_KEY

        self.sql_engine = SQLEngine(
            api_key=api_key,
            model=model,
            provider=provider,
            schema_csv_path=str(csv_path),
            db_config=self.db_config,
        )
        self._active_sql_provider = provider
        self._active_sql_model = model
        logger.info(f"🔄 SQL engine reloaded with provider={provider}, model={model}")

    # ----------------------------------------------------------
    # MAIN QUERY PROCESSOR
    # ----------------------------------------------------------
    def process_query(self, request):

        self._refresh_sql_engine_if_needed()

        session_id = request.session_id
        question = request.message
        conversation_history = getattr(request, 'conversation_history', None) or []

        clean_question, entities = self.preprocessor.process(question)

        # 🔥 DEBUG: Log entities before mapping
        logger.info(f"🔍 DEBUG - Before mapping:")
        logger.info(f"   - multi_tenant_enabled: {self.multi_tenant_enabled}")
        logger.info(f"   - tenant_column: {self.tenant_column}")
        logger.info(f"   - entities keys: {list(entities.keys())}")
        logger.info(f"   - tenant value: {entities.get(self.tenant_column)}")

        # 🔥 NEW: Map extracted tenant names to actual database values
        if self.multi_tenant_enabled and entities.get(self.tenant_column):
            logger.info(f"🔍 DEBUG - Calling _map_tenant_to_actual_values()")
            entities = self._map_tenant_to_actual_values(entities)
        else:
            logger.warning(f"⚠️ DEBUG - Mapping skipped! multi_tenant: {self.multi_tenant_enabled}, has_tenant: {bool(entities.get(self.tenant_column))}")

        logger.info(f"🧠 Resolved entities: {entities}")
        logger.info(f"📝 Clean question: {clean_question}")

        cached = self.cache.get(session_id, clean_question)
        if cached:
            return cached

        # --------------------------------------------------
        # 📊 DASHBOARD KPI MATCH (pre-built Grafana queries)
        # --------------------------------------------------
        kpi_response = self._try_kpi_match(clean_question, entities, session_id,
                                               original_question=question)
        if kpi_response:
            self.cache.set(session_id, clean_question, kpi_response)
            return kpi_response

        sp_response = self._try_sp_match(clean_question, entities)
        if sp_response:
            self.cache.set(session_id, clean_question, sp_response)
            return sp_response

        # ── Compute time range for reuse substitution ──
        _reuse_time_from = _reuse_time_to = None
        try:
            from datetime import datetime, timedelta
            _delta = self.kpi_resolver._parse_time_range(clean_question)
            _now = datetime.now()
            if _delta == timedelta(0):
                _reuse_time_from = _now.strftime("%Y-%m-%d 00:00:00")
            else:
                _reuse_time_from = (_now - _delta).strftime("%Y-%m-%d %H:%M:%S")
            _reuse_time_to = _now.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            pass

        reused = self.reuse_engine.try_reuse(
            clean_question,
            entities=entities,
            time_from=_reuse_time_from,
            time_to=_reuse_time_to,
            tenant_column=self.tenant_column if self.multi_tenant_enabled else None,
        )

        if reused:
            sql, execution_result = reused

            # Archive table swap (separate concern — not handled by reuse engine)
            new_sql = self._apply_archive_if_needed(sql, clean_question)
            if new_sql != sql:
                sql = new_sql
                execution_result = self.executor.execute(sql)

            generation_result = SQLGenerationResult(
                sql=sql,
                confidence=0.95,
                explanation="Reused from classified queries",
                assumptions=["Previously validated query"],
                metadata={"source": "reuse_engine"}
            )
        else:

            # --------------------------------------------------
            # DETERMINISTIC SCHEMA SCOPING
            # --------------------------------------------------
            validated_tables = self.table_priority_loader.get_validated_tables_for_query(clean_question)
            learned_tables = self._get_learned_tables(clean_question)

            if validated_tables.get("correct"):
                selected_tables = validated_tables["correct"]
                logger.info(f"🎯 Using validated tables: {selected_tables}")

            elif learned_tables:
                selected_tables = learned_tables
                logger.info(f"🧠 Using learned tables: {selected_tables}")

            else:
                selected_tables = self.table_selector.select(clean_question, max_tables=12)
                logger.info(f"🔍 Using heuristic selected tables: {selected_tables}")

            if not selected_tables:
                selected_tables = list(self.schema.keys())[:5]

            # --------------------------------------------------
            # ENRICHED SCHEMA
            # --------------------------------------------------
            filtered_schema = {}

            for table in selected_tables:
                if table not in self.schema:
                    continue

                enriched = {"columns": self.schema[table]}

                if table in self.business_context:
                    business_info = self.business_context[table]
                    enriched.update({
                        "description": business_info.get("description", ""),
                        "key_business_attributes": business_info.get("key_business_attributes", []),
                        "frequently_joined_with": business_info.get("frequently_joined_with", []),
                        "supports_analytics": business_info.get("supports_analytics", []),
                        "self_sufficient_for": business_info.get("self_sufficient_for", []),
                        "not_needed_for": business_info.get("not_needed_for", []),
                    })

                filtered_schema[table] = enriched

            # --------------------------------------------------
            # GENERATION FUNCTION
            # --------------------------------------------------
            def generate_fn(feedback, previous_sql):

                # Build entity context, handling lists and internal metadata
                entity_lines = []
                is_all_sites = entities.get("_all_sites", False)
                is_location_breakdown = entities.get("_location_breakdown", False)
                
                for k, v in entities.items():
                    # Skip internal metadata keys
                    if k.startswith('_'):
                        continue
                    
                    # 🔥 Skip tenant column for ALL SITES / location-breakdown queries
                    if is_all_sites and k == self.tenant_column:
                        continue
                    
                    # Handle list values
                    if isinstance(v, list):
                        entity_lines.append(f"{k} = {v[0]}" if len(v) == 1 else f"{k} IN ({', '.join(v)})")
                    else:
                        entity_lines.append(f"{k} = '{v}'")
                
                entity_context = "\n".join(entity_lines)
                
                # 🔥 Add tenant-specific instructions based on query type
                if self.multi_tenant_enabled:
                    # Global rule: IDs are composite with host-location, DISTINCT on single ID is wrong
                    entity_context += f"\n\nSCHEMA WARNING: {self.multi_tenant_distinct_warning}"

                    if is_location_breakdown:
                        # LOCATION BREAKDOWN: Tell AI to GROUP BY host-location (no value filter)
                        entity_context += (
                            f"\n\nIMPORTANT: User wants data GROUPED/SEGREGATED by location. "
                            f"DO NOT filter by `{self.tenant_column}` value. "
                            f"Instead, include `{self.tenant_column}` in SELECT and GROUP BY clause "
                            f"so results are broken down per location."
                        )
                        logger.info(f"📊 Entity context for LOCATION BREAKDOWN query (GROUP BY {self.tenant_column})")
                    elif is_all_sites:
                        # ALL SITES AGGREGATE: No location filter at all
                        entity_context += (
                            f"\n\nIMPORTANT: This is an AGGREGATE query across ALL locations. "
                            f"DO NOT add any `{self.tenant_column}` filter."
                        )
                        logger.info(f"🌐 Entity context for ALL SITES query (no location filter)")
                    elif self.tenant_column not in str(entity_context):
                        # No tenant in context (edge case) - enforce default filtering
                        entity_context += f"\n\nIMPORTANT: Always filter by `{self.tenant_column}`"
                        logger.warning(f"⚠️ Tenant column not in entity_context, adding filter instruction")
                    else:
                        # Tenant already in entity_context with mapped value
                        tenant_value = entities.get(self.tenant_column)
                        logger.info(f"📍 Entity context includes tenant: {self.tenant_column} = {tenant_value}")

                result = self.sql_engine.generate(
                    question=clean_question,
                    feedback=feedback,
                    previous_sql=previous_sql,
                    enable_entity_resolution=True,
                    schema_override=filtered_schema,
                    entity_context=entity_context,
                    conversation_history=[
                        {"role": m.get("role", ""), "content": m.get("content", "")}
                        for m in conversation_history
                    ] if conversation_history else None
                )

                sql = self._enforce_entities_in_sql(result["sql"], entities)
                
                logger.info(f"🔍 DEBUG - After entity enforcement: {sql[:200]}")
                logger.info(f"🔍 DEBUG - Entities used: {entities}")

                # Ensure non-tenant entities are present in SQL (forces retry if missing)
                # NOTE: Tenant column is intentionally EXCLUDED from this check.
                #       _inject_tenant_filter() handles it programmatically AFTER the retry
                #       loop, so validating it here only causes false "Missing entity" 500 errors.
                for key, value in entities.items():
                    # Skip internal metadata keys
                    if key.startswith('_'):
                        continue
                    
                    # Always skip tenant column — enforced by _inject_tenant_filter() later
                    if key == self.tenant_column:
                        continue
                    
                    # Handle list values
                    if isinstance(value, list):
                        if not any(str(v) in sql for v in value):
                            raise ValueError(f"Missing required entity {key} in SQL.")
                    else:
                        if value not in sql:
                            raise ValueError(f"Missing required entity {key} in SQL.")

                return SQLGenerationResult(
                    sql=sql,
                    confidence=result.get("confidence", 0.75),
                    explanation="Generated with enforced canonical entity resolution",
                    assumptions=result.get("assumptions", []),
                    metadata=result
                )

            # generation_result, execution_result = self.retry_engine.run(
            #     generate_fn,
            #     self.validator,
            #     self.executor,
            #     feedback_generator=self.feedback_generator,
            #     schema_validator=self.schema_validator,
            # )

            generation_result, execution_result = self.retry_engine.run(
                generate_fn,
                self.validator,
                self.executor,
                feedback_generator=self.feedback_generator,
                schema_validator=self.schema_validator,
            )

            sql = generation_result.sql

            # --------------------------------------------------
            # 🔥 TENANT ENFORCEMENT (MULTI-TENANT AWARE)
            # --------------------------------------------------
            sql = self._inject_tenant_filter(sql, entities)
            sql = self._apply_archive_if_needed(sql, clean_question)
            generation_result.sql = sql

            # 🔥 CRITICAL: re-execute corrected SQL
            execution_result = self.executor.execute(sql)

            logger.info(f"✅ Final SQL: {sql}")

            sql = generation_result.sql

        # --------------------------------------------------
        # SEMANTIC VALIDATION (both reuse + fresh paths)
        # --------------------------------------------------
        try:
            tenant_value = entities.get(self.tenant_column)
            tenant_str = tenant_value[0] if isinstance(tenant_value, list) and tenant_value else tenant_value
            self.semantic_validator.validate(
                execution_result,
                sql=generation_result.sql,
                tenant=tenant_str
            )
        except Exception as e:
            logger.warning(f"Semantic validation warning: {e}")

        final_confidence = self.confidence.compute(
            generation_result,
            execution_result
        )

        response_text = self.formatter.format(
            clean_question,
            sql,
            execution_result,
            final_confidence
        )

        self.learning.record_success(
            session_id,
            clean_question,
            response_text,
            sql,
            execution_result,
            generation_result,
            user_id=getattr(request, 'user_id', None)
        )

        response = ChatResponse(
            response=response_text,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id,
            sources=[],
            confidence_score=final_confidence,
            metadata={
                "sql_query": sql,
                "row_count": execution_result.row_count,
                "resolved_entities": entities
            }
        )

        self.cache.set(session_id, clean_question, response)

        return response
    # ----------------------------------------------------------
    # 📊 DASHBOARD KPI MATCH
    # ----------------------------------------------------------
    def _try_kpi_match(self, clean_question: str, entities: dict, session_id: str,
                        original_question: str = None):
        """
        📊  DASHBOARD KPI PIPELINE  (deterministic — NO LLM fallback)

        Flow:
            question → KPI matcher → inject time + tenant + variables
            → execute (trusted, no READ ONLY) → return result
            → if fails → return error ChatResponse to user
            → NEVER fall through to LLM

        KPI = pre-defined business logic.  Inventing SQL is a bug.
        """
        if not self.kpi_resolver:
            return None

        # ── Extract tenant values ──
        tenant_values = entities.get(self.tenant_column)
        all_sites = entities.get("_all_sites", False)
        location_breakdown = entities.get("_location_breakdown", False)

        if isinstance(tenant_values, str):
            tenant_values = [tenant_values]
        elif not tenant_values:
            tenant_values = None

        # ── Case-2 fix: derive explicit time_from / time_to from question ──
        # The resolver will parse these from the question text if not provided,
        # but passing them explicitly gives us a single, logged source-of-truth.
        try:
            _parsed = self.kpi_resolver._parse_time_range(clean_question)
            from datetime import datetime as _dt, timedelta as _td
            _now = _dt.now()
            if isinstance(_parsed, tuple):
                # Absolute date range (e.g. "from 2 to 3 march")
                _kpi_time_from = _parsed[0].strftime("%Y-%m-%d %H:%M:%S")
                _kpi_time_to = _parsed[1].strftime("%Y-%m-%d %H:%M:%S")
            else:
                _delta = _parsed
                if _delta.total_seconds() == 0:
                    _kpi_time_from = _now.strftime("%Y-%m-%d 00:00:00")
                else:
                    _kpi_time_from = (_now - _delta).strftime("%Y-%m-%d %H:%M:%S")
                _kpi_time_to = _now.strftime("%Y-%m-%d %H:%M:%S")
            logger.info(
                f"\u23f0 KPI time window derived from question: "
                f"from='{_kpi_time_from}'  to='{_kpi_time_to}'  (parsed={_parsed})"
            )
        except Exception:
            _kpi_time_from = None
            _kpi_time_to   = None

        # ── Extract additional entities for KPI param substitution ──
        # EntityResolver stores keys in UPPERCASE (BOT_ID, STATION_ID, etc.)
        _bot_id = entities.get("BOT_ID")
        _category_value = entities.get("CATEGORY_VALUE")
        _station_id = entities.get("STATION_ID")
        _bin_id = entities.get("BIN_ID")
        _wave_id = entities.get("WAVE_ID")
        _order_id = entities.get("ORDER_ID")

        try:
            kpi_match = self.kpi_resolver.resolve(
                question=clean_question,
                tenant_values=tenant_values,
                all_sites=all_sites,
                location_breakdown=location_breakdown,
                time_from=_kpi_time_from,
                time_to=_kpi_time_to,
                bot_id=_bot_id,
                category_value=_category_value,
                station_id=_station_id,
                bin_id=_bin_id,
                wave_id=_wave_id,
                order_id=_order_id,
                original_question=original_question,
            )
        except Exception as e:
            logger.warning(f"KPI resolver error: {e}")
            return None

        if not kpi_match:
            return None

        # ═══════════════════════════════════════════════════════
        #  KPI MATCHED — execute the pre-built query.
        #  High-confidence matches (≥0.75) are terminal.
        #  Lower-confidence matches are accepted but logged.
        # ═══════════════════════════════════════════════════════

        logger.info(
            f"📊 Dashboard KPI hit: id={kpi_match.kpi_id}, '{kpi_match.kpi_name}' "
            f"(score={kpi_match.match_score:.2f}, chart={kpi_match.chart_type})"
        )
        logger.info(f"📊 KPI tenant params: {kpi_match.parameters_applied}")

        # Case-3 diagnostic: log the stripped text that was used for scoring
        # (helps compare "in chennai Which SKUs…" vs "Which SKUs… in frk?" etc.)
        from .match_utils import strip_matching_noise as _strip_noise
        logger.info(
            f"📊 KPI stripped match_question: '{_strip_noise(clean_question)}'"
        )
        logger.debug(f"📊 KPI SQL (first 300): {kpi_match.sql[:300]}")

        sql = kpi_match.sql

        # ── Execute with execute_trusted (no READ ONLY) ──
        # KPI queries may contain complex CTEs (WITH task_lifecycle AS …)
        # whose materialisation creates internal temp tables —
        # READ ONLY blocks that.
        try:
            execution_result = self.executor.execute_trusted(
                sql, label=f"KPI:{kpi_match.kpi_name}"
            )
        except Exception as e:
            logger.error(
                f"🚫 KPI id={kpi_match.kpi_id}, '{kpi_match.kpi_name}' matched "
                f"(score={kpi_match.match_score:.2f}) but execution "
                f"failed: {e}. Returning error — no LLM fallback."
            )

            error_response = (
                f"Your question matches a predefined dashboard KPI "
                f"(**{kpi_match.kpi_name}**), but execution failed:\n\n"
                f"```\n{e}\n```\n\n"
                f"This is a database permission or schema issue — "
                f"no alternative SQL was generated to avoid incorrect data."
            )

            return ChatResponse(
                response=error_response,
                chatbot_type=ChatbotType.SQL_ASSISTANT,
                session_id=session_id,
                sources=[],
                confidence_score=0.0,
                query_results=[],
                metadata={
                    "sql_query": sql,
                    "error": str(e),
                    "dashboard_kpi": {
                        "kpi_id": kpi_match.kpi_id,
                        "kpi_name": kpi_match.kpi_name,
                        "match_score": kpi_match.match_score,
                        "source": "dashboard_kpi",
                        "status": "execution_failed",
                    },
                },
            )

        # ── Success ──
        row_count = execution_result.row_count
        rows = execution_result.rows or []

        # Case-3 fix: when KPI matched but returned 0 rows, the user often
        # thinks the KPI "didn't fire".  Provide a clear explanation — especially
        # useful when "in chennai Which SKUs near expiry?" finds no data but
        # "in frk?" does (different data coverage, not a matching difference).
        if not rows:
            location_str = (
                ", ".join(tenant_values) if tenant_values else "the selected location"
            )
            no_data_text = (
                f"The system matched your question to the pre-built KPI: "
                f"**{kpi_match.kpi_name}**.\n\n"
                f"The query executed successfully for **{location_str}** "
                f"but returned **no data**. Possible reasons:\n"
                f"- This location may not have any records for this KPI yet.\n"
                f"- The time window ({kpi_match.parameters_applied.get('time_from', 'default')} "
                f"→ {kpi_match.parameters_applied.get('time_to', 'now')}) contains no activity.\n"
                f"- Data for this KPI may not exist at this site.\n\n"
                f"*KPI category: {kpi_match.category} | "
                f"Match score: {kpi_match.match_score:.0%}*"
            )
            logger.info(
                f"📊 KPI id={kpi_match.kpi_id}, '{kpi_match.kpi_name}' matched but returned 0 rows "
                f"for location={tenant_values}"
            )
            return ChatResponse(
                response=no_data_text,
                chatbot_type=ChatbotType.SQL_ASSISTANT,
                session_id=session_id,
                sources=[],
                confidence_score=0.95,
                query_results=[],
                metadata={
                    "sql_query": sql,
                    "row_count": 0,
                    "resolved_entities": entities,
                    "dashboard_kpi": {
                        "kpi_id": kpi_match.kpi_id,
                        "kpi_name": kpi_match.kpi_name,
                        "category": kpi_match.category,
                        "chart_type": kpi_match.chart_type,
                        "match_score": kpi_match.match_score,
                        "parameters_applied": kpi_match.parameters_applied,
                        "source": "dashboard_kpi",
                        "status": "no_data",
                    },
                },
            )

        response_text = self.formatter.format(
            clean_question, sql, execution_result, 0.95
        )
        columns = []
        query_results = []
        if rows:
            columns = list(rows[0].keys()) if isinstance(rows[0], dict) else []
            query_results = [dict(r) if hasattr(r, 'keys') else r for r in rows]

        presentation_mode = "grouped_by_location" if location_breakdown else "single_value"
        effective_chart_type = (
            "bar chart"
            if location_breakdown and rows and len(rows) > 1
            else kpi_match.chart_type
        )

        dashboard_metadata = {
            "kpi_id": kpi_match.kpi_id,
            "kpi_name": kpi_match.kpi_name,
            "category": kpi_match.category,
            "chart_type": effective_chart_type,
            "logic": kpi_match.logic,
            "match_score": kpi_match.match_score,
            "tables_used": kpi_match.tables_used,
            "parameters_applied": kpi_match.parameters_applied,
            "presentation_mode": presentation_mode,
            "group_by_dimension": self.tenant_column if location_breakdown else None,
            "source": "dashboard_kpi",
            "columns": columns,
            "available_chart_types": self._available_charts_for(effective_chart_type, columns),
        }

        return ChatResponse(
            response=response_text,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id,
            sources=[],
            confidence_score=0.95,
            query_results=query_results,
            metadata={
                "sql_query": sql,
                "row_count": row_count,
                "resolved_entities": entities,
                "dashboard_kpi": dashboard_metadata,
            },
        )

    def _try_sp_match(self, clean_question: str, entities: dict):
        """
        ⚙️  STORED PROCEDURE PIPELINE  (deterministic — NO LLM fallback)

        Flow:
            question → SP matcher → resolve uses query_sql (SELECT)
            → execute_trusted (no READ ONLY) → return result
            → if fails → CALL fallback → return result
            → if both fail → return error ChatResponse to user
            → NEVER fall through to LLM

        SP = authoritative business logic.  Inventing SQL is a bug.
        """
        if not self.sp_resolver:
            return None

        # ── Extract tenant values ──
        tenant_values = entities.get(self.tenant_column)
        all_sites = entities.get("_all_sites", False)

        if isinstance(tenant_values, str):
            tenant_values = [tenant_values]
        elif not tenant_values:
            tenant_values = None

        # ── Resolve SP match ──
        try:
            sp_match = self.sp_resolver.resolve(
                question=clean_question,
                tenant_values=tenant_values,
                all_sites=all_sites,
            )
        except Exception as e:
            logger.warning(f"SP resolver error: {e}")
            return None

        if not sp_match:
            return None

        # ═══════════════════════════════════════════════════════
        #  SP MATCHED — from here on, this is the ONLY path.
        #  NO LLM fallback under any circumstances.
        # ═══════════════════════════════════════════════════════

        logger.info(
            f"⚙️ SP hit: '{sp_match.sp_name}' "
            f"(score={sp_match.match_score:.2f})"
        )
        logger.info(f"⚙️ SP params: {sp_match.parameters_applied}")
        logger.debug(f"⚙️ SP SQL (first 500): {sp_match.sql[:500]}")

        sql = sp_match.sql
        execution_error = None
        used_call_fallback = False

        # ── Strategy 1: Execute query SQL / SP body SQL (trusted, no READ ONLY) ──
        try:
            execution_result = self.executor.execute_trusted(
                sql, label=f"SP:{sp_match.sp_name}"
            )
        except Exception as e:
            logger.warning(
                f"⚠️ SP query SQL failed: {e} — trying CALL fallback"
            )
            execution_result = None
            execution_error = str(e)

        # ── Strategy 2: CALL fallback (DEFINER=root@%, needs EXECUTE priv) ──
        if execution_result is None:
            try:
                call_sql = self.sp_resolver.build_call_statement(sp_match)
                logger.info(f"⚙️ CALL fallback: {call_sql}")
                execution_result = self.executor.execute_call(call_sql)
                sql = call_sql
                used_call_fallback = True
                logger.info(
                    f"✅ SP CALL succeeded: {execution_result.row_count} rows"
                )
            except Exception as call_err:
                logger.error(f"❌ SP CALL also failed: {call_err}")
                execution_error = (
                    f"Query: {execution_error}  |  CALL: {call_err}"
                )

        # ── Both strategies failed → return error to user, NO LLM ──
        if execution_result is None:
            logger.error(
                f"🚫 SP '{sp_match.sp_name}' matched "
                f"(score={sp_match.match_score:.2f}) but ALL execution "
                f"strategies failed. Returning error — no LLM fallback."
            )

            error_response = (
                f"Your question matches a predefined report "
                f"(**{sp_match.sp_name}**), but execution failed:\n\n"
                f"```\n{execution_error}\n```\n\n"
                f"This is a database permission or schema issue — "
                f"no alternative SQL was generated to avoid incorrect data.\n\n"
                f"**Action required:** Ask your DBA to grant EXECUTE "
                f"privilege on this stored procedure to the service account."
            )

            return ChatResponse(
                response=error_response,
                chatbot_type=ChatbotType.SQL_ASSISTANT,
                session_id=None,
                sources=[],
                confidence_score=0.0,
                query_results=[],
                metadata={
                    "sql_query": sp_match.sql,
                    "error": execution_error,
                    "stored_procedure": {
                        "sp_name": sp_match.sp_name,
                        "match_score": sp_match.match_score,
                        "source": "stored_procedure",
                        "status": "execution_failed",
                    },
                },
            )

        # ── Success ──
        row_count = execution_result.row_count
        rows = execution_result.rows or []

        response_text = self.formatter.format(
            clean_question, sql, execution_result, 0.95
        )

        columns = []
        query_results = []
        if rows:
            columns = list(rows[0].keys()) if isinstance(rows[0], dict) else []
            query_results = [dict(r) if hasattr(r, 'keys') else r for r in rows]

        sp_metadata = {
            "sp_id": sp_match.sp_id,
            "sp_name": sp_match.sp_name,
            "description": sp_match.description,
            "match_score": sp_match.match_score,
            "parameters_applied": sp_match.parameters_applied,
            "source": "stored_procedure",
            "used_call_fallback": used_call_fallback,
            "columns": columns,
        }

        return ChatResponse(
            response=response_text,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=None,
            sources=[],
            confidence_score=0.95,
            query_results=query_results,
            metadata={
                "sql_query": sql,
                "row_count": row_count,
                "resolved_entities": entities,
                "stored_procedure": sp_metadata,
            },
        )

    # ----------------------------------------------------------
    # CHART TYPE HELPERS
    # ----------------------------------------------------------

    @staticmethod
    def _available_charts_for(default_chart: str, columns: list) -> list:
        """
        Return chart types the user can pick from.
        First item is the recommended default from the KPI definition.
        """
        all_types = ["bar chart", "pie", "table", "stat", "time series", "bar gauge"]
        result = [default_chart] if default_chart else []
        for ct in all_types:
            if ct not in result:
                result.append(ct)
        return result