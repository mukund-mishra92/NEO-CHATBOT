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

        # Load business rules for missing-table detection
        self.business_rules = self._load_business_rules()

        logger.info(f"✅ SQLAssistantService initialized with {len(self.schema)} tables")

    # ----------------------------------------------------------
    # LOAD BUSINESS RULES
    # ----------------------------------------------------------
    def _load_business_rules(self) -> dict:
        """Load business rules from config/sql_assistant_config.json for missing-table detection."""
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        if not config_path.exists():
            logger.info("ℹ️ No sql_assistant_config.json found — business rules disabled")
            return {}
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                config = json.load(f)
            rules = config.get("business_rules", {})
            logger.info(f"📋 Loaded {len(rules)} business rules for table validation")
            return rules
        except Exception as e:
            logger.warning(f"⚠️ Failed to load business rules: {e}")
            return {}

    # ----------------------------------------------------------
    # MISSING TABLE DETECTION
    # ----------------------------------------------------------
    # Keyword→table mappings for concepts that may not be in a business rule
    # but are strongly tied to a specific table.  If the table is absent from
    # the schema CSV the user should get a clear error instead of a hallucination.
    _CONCEPT_TABLE_MAP = [
        # (keywords_any_of, required_tables, description)
        (
            ["wcs to wms", "wcs_to_wms", "payload from wcs", "json response from wms",
             "json response received from wms", "wms payload", "wcs payload",
             "api payload", "closing the lpn"],
            ["wcs_to_wms_payload"],
            "WCS→WMS integration payload data",
        ),
        (
            ["wms to wcs payload", "wms_to_wcs_payload"],
            ["wms_to_wcs_payload"],
            "WMS→WCS integration payload data",
        ),
        (
            ["task master", "task_master", "active task", "current task",
             "live task", "running task"],
            ["task_master"],
            "Live task execution data (task_master)",
        ),
        (
            ["bot charging log", "charging bit log", "bot_charging_bit_log",
             "charging history", "charging telemetry"],
            ["bot_charging_bit_log"],
            "Bot charging telemetry log",
        ),
    ]

    def _check_required_tables(self, clean_question: str) -> dict | None:
        """
        Check if the question matches a business rule whose required_table(s)
        are NOT available in the current schema (Table_information.csv).

        Also checks keyword→table concept mappings for broader coverage.

        Returns dict with {rule_name, required_tables, missing_tables} if
        a critical table is missing, else None.
        """
        question_lower = clean_question.lower()
        best_match = None
        best_hits = 0

        # --- Pass 1: business rules (trigger-based) ---
        if self.business_rules:
            for rule_name, rule_config in self.business_rules.items():
                triggers = rule_config.get("triggers", [])
                hit_count = sum(1 for t in triggers if t.lower() in question_lower)
                if hit_count <= 0:
                    continue

                # Gather required tables for this rule
                required = []
                if "required_tables" in rule_config:
                    required = list(rule_config["required_tables"])
                elif "required_table" in rule_config:
                    required = [rule_config["required_table"]]

                if not required:
                    continue

                missing = [t for t in required if t not in self.schema]
                if missing and hit_count > best_hits:
                    best_hits = hit_count
                    best_match = {
                        "rule_name": rule_name,
                        "description": rule_config.get("description", ""),
                        "required_tables": required,
                        "missing_tables": missing,
                        "trigger_hits": hit_count,
                    }

        # --- Pass 2: keyword→table concept mappings ---
        for keywords, required_tables, description in self._CONCEPT_TABLE_MAP:
            hit_count = sum(1 for kw in keywords if kw in question_lower)
            if hit_count <= 0:
                continue
            missing = [t for t in required_tables if t not in self.schema]
            if missing and hit_count > best_hits:
                best_hits = hit_count
                best_match = {
                    "rule_name": f"concept:{required_tables[0]}",
                    "description": description,
                    "required_tables": required_tables,
                    "missing_tables": missing,
                    "trigger_hits": hit_count,
                }

        return best_match

    def _build_missing_table_response(
        self, missing_info: dict, session_id: str, entities: dict
    ) -> ChatResponse:
        """Build a clear user-facing response when a required table is missing from schema."""
        missing_str = ", ".join(f"`{t}`" for t in missing_info["missing_tables"])
        rule_desc = missing_info.get("description", "")

        # Check if the missing table exists in business_context (table_descriptions.json)
        # — this means the table is known but not yet in the DB/schema CSV
        known_tables = [
            t for t in missing_info["missing_tables"]
            if t in self.business_context
        ]
        unknown_tables = [
            t for t in missing_info["missing_tables"]
            if t not in self.business_context
        ]

        msg_parts = [
            f"Your question requires data from the table(s) {missing_str}, "
            f"which {'is' if len(missing_info['missing_tables']) == 1 else 'are'} "
            f"**not currently available** in the database schema."
        ]

        if rule_desc:
            msg_parts.append(f"\n\n**Context:** {rule_desc}")

        if known_tables:
            known_str = ", ".join(f"`{t}`" for t in known_tables)
            msg_parts.append(
                f"\n\nThe table(s) {known_str} are recognized in the system configuration "
                f"but have not been added to this environment's database yet. "
                f"Please ask your administrator to enable CDC replication for "
                f"{'this table' if len(known_tables) == 1 else 'these tables'}."
            )

        if unknown_tables:
            unknown_str = ", ".join(f"`{t}`" for t in unknown_tables)
            msg_parts.append(
                f"\n\nThe table(s) {unknown_str} are not recognized in the system. "
                f"Please verify the table name with your database team."
            )

        response_text = "".join(msg_parts)

        return ChatResponse(
            response=response_text,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=session_id,
            sources=[],
            confidence_score=0.0,
            metadata={
                "error": "required_table_not_available",
                "missing_tables": missing_info["missing_tables"],
                "rule_name": missing_info["rule_name"],
                "resolved_entities": entities,
            },
        )

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
            # MISSING TABLE CHECK (before any generation)
            # --------------------------------------------------
            missing_table_info = self._check_required_tables(clean_question)
            if missing_table_info:
                logger.warning(
                    f"⚠️ Required table(s) missing from schema: "
                    f"{missing_table_info['missing_tables']} "
                    f"(rule={missing_table_info['rule_name']})"
                )
                return self._build_missing_table_response(
                    missing_table_info, session_id, entities
                )

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
    # 📊 LLM KPI VALIDATOR — mid-confidence matches (55-90%)
    # ----------------------------------------------------------
    def _llm_validate_kpi(
        self, user_query: str, candidates: list, current_kpi_id: str
    ) -> str | None:
        """
        Use LLM to pick the best KPI from top candidates for a user query.

        Called when the KPI match score is between 55% and 90% (mid-confidence).
        The LLM sees the user query + top-3 KPI candidates (name, logic,
        tables) and returns the best KPI id, or "NONE" if no KPI is a
        good match (should fall through to SQL generation).

        Returns:
            Selected kpi_id (str) or None (reject all → SQL path)
        """
        if not candidates:
            return None

        # Build candidate descriptions for the LLM
        candidate_lines = []
        for i, c in enumerate(candidates, 1):
            candidate_lines.append(
                f"  {i}. id={c['kpi_id']}, name=\"{c['kpi_name']}\", "
                f"score={c['score']:.2f}\n"
                f"     logic: {c['logic'][:200]}\n"
                f"     tables: {', '.join(c.get('tables_used', []))}\n"
                f"     chart_type: {c.get('chart_type', 'unknown')}"
            )
        candidates_text = "\n".join(candidate_lines)

        prompt = f"""You are a warehouse analytics KPI selector.

USER QUERY: "{user_query}"

The system found these potential KPI matches (pre-built dashboard queries).
Pick the ONE KPI that BEST answers the user's question, or say NONE if
none of them are a good fit (the query needs custom SQL instead).

CANDIDATES:
{candidates_text}

RULES:
- If the user asks for raw data, per-row details, or specific entity lookups → NONE
- If the user asks for a metric/aggregation that a KPI provides → pick that KPI
- "active hours" / "time" / "minutes" for bots = hours breakdown KPI (not count)  
- "how many" / "count" without time units = count KPI
- If the user's intent clearly doesn't match ANY candidate's logic → NONE

Respond with ONLY the kpi_id (e.g. "kpi_001") or "NONE". Nothing else."""

        try:
            client = self.sql_engine.openai_client
            if client is None:
                logger.warning("📊 LLM KPI validator: no OpenAI client available")
                return current_kpi_id  # fall back to original match

            resp = client.responses.create(
                model=self.sql_engine.model,
                input=prompt,
                temperature=0,
                timeout=15,
            )
            answer = resp.output_text.strip().lower().replace('"', '').replace("'", '')

            logger.info(
                f"📊 LLM KPI validator: query='{user_query[:80]}' → "
                f"answer='{answer}' (original={current_kpi_id})"
            )

            if answer == "none":
                return None

            # Validate the returned id is in our candidates
            valid_ids = {c["kpi_id"] for c in candidates}
            if answer in valid_ids:
                return answer
            # Try partial match (e.g., "kpi_001" in "the best match is kpi_001")
            for vid in valid_ids:
                if vid in answer:
                    return vid

            logger.warning(
                f"📊 LLM KPI validator: unexpected answer '{answer}', "
                f"keeping original={current_kpi_id}"
            )
            return current_kpi_id

        except Exception as e:
            logger.warning(f"📊 LLM KPI validator error: {e}, keeping original={current_kpi_id}")
            return current_kpi_id

    # ----------------------------------------------------------
    # 📊 LLM KPI QUERY REFINEMENT (SQL-aware, replaces simple validator)
    # ----------------------------------------------------------

    # JSON schema for the structured LLM response
    _KPI_REFINE_SCHEMA = {
        "type": "object",
        "properties": {
            "selected_kpi_id": {
                "type": "string",
                "description": "The kpi_id that best matches, or NONE",
            },
            "sql": {
                "type": "string",
                "description": "The SQL query to execute — original or modified",
            },
            "chart_type": {
                "type": "string",
                "description": "Chart type for display",
            },
            "explanation": {
                "type": "string",
                "description": "Brief explanation of why this KPI was selected and any modifications made",
            },
        },
        "required": ["selected_kpi_id", "sql", "chart_type", "explanation"],
        "additionalProperties": False,
    }

    def _llm_refine_kpi_query(
        self,
        user_query: str,
        kpi_match,                      # KPIMatch from resolver
        tenant_values: list,
        time_from: str,
        time_to: str,
        all_sites: bool,
        bot_id: str = None,
        station_id: str = None,
        bin_id: str = None,
        wave_id: str = None,
        order_id: str = None,
        category_value: str = None,
        location_breakdown: bool = False,
    ) -> dict | None:
        """
        LLM-enhanced KPI query refinement.

        When KPI match is in the mid-confidence band (0.50–0.90), the LLM
        sees the user query + top-3 KPI SQL queries (parameter-substituted)
        + table/column guidance, and either:
          • picks the best KPI query as-is,
          • modifies it (e.g. column projection), or
          • rejects all (→ SQL generation path).

        Returns dict with {kpi_id, sql, kpi_name, chart_type, explanation,
        tables_used, logic, score} or None (reject → SQL gen).
        """
        if not kpi_match.top_candidates:
            return None

        client = getattr(self.sql_engine, "openai_client", None)
        if client is None:
            logger.warning("📊 LLM KPI refiner: no OpenAI client available")
            return None

        # ── Prepare substituted SQL for each top candidate ────────────
        candidate_sqls = []
        for c in kpi_match.top_candidates[:5]:
            kpi_entry = None
            for entry in self.kpi_resolver.kpis:
                if entry.id == c["kpi_id"]:
                    kpi_entry = entry
                    break
            if not kpi_entry:
                continue

            sql, params = self.kpi_resolver._substitute_params(
                kpi_entry.query, tenant_values, time_from, time_to,
                all_sites, question=user_query, bot_id=bot_id,
                category_value=category_value, station_id=station_id,
                location_breakdown=location_breakdown, kpi_id=kpi_entry.id,
            )
            sql, params = self.kpi_resolver._inject_entity_filters(
                sql, params, bot_id=bot_id, station_id=station_id,
                bin_id=bin_id, wave_id=wave_id, order_id=order_id,
            )

            candidate_sqls.append({
                "kpi_id": c["kpi_id"],
                "kpi_name": c["kpi_name"],
                "score": c["score"],
                "logic": c["logic"],
                "chart_type": c.get("chart_type", "table chart"),
                "tables_used": c.get("tables_used", []),
                "user_queries": c.get("user_queries", []),
                "sql": sql,
            })

        if not candidate_sqls:
            return None

        # ── Table/column guidance ─────────────────────────────────────
        all_tables = set()
        for c in candidate_sqls:
            all_tables.update(c.get("tables_used", []))

        table_schema_lines = []
        for tbl in sorted(all_tables):
            cols = self.schema.get(tbl)
            if cols:
                # cols is a list of column-name strings
                col_names = cols if isinstance(cols[0], str) else [c["name"] for c in cols]
                table_schema_lines.append(
                    f"  TABLE: {tbl}\n  COLUMNS: {', '.join(col_names)}"
                )
        table_context = "\n".join(table_schema_lines) if table_schema_lines else "(no schema)"

        # ── Build candidate blocks ────────────────────────────────────
        candidate_blocks = []
        for i, c in enumerate(candidate_sqls, 1):
            # Include example user queries from the KPI registry
            uq = c.get("user_queries", [])
            uq_text = ""
            if uq:
                uq_lines = "\n".join(f"  - {q}" for q in uq[:5])
                uq_text = f"\nExample user questions this KPI answers:\n{uq_lines}\n"
            candidate_blocks.append(
                f"--- KPI {i}: {c['kpi_id']} ---\n"
                f"Name: {c['kpi_name']}\n"
                f"Logic: {c['logic'][:350]}\n"
                f"Chart type: {c['chart_type']}\n"
                f"Tables: {', '.join(c['tables_used'])}"
                f"{uq_text}\n"
                f"SQL:\n{c['sql']}"
            )
        candidates_text = "\n\n".join(candidate_blocks)

        # ── Prompt ────────────────────────────────────────────────────
        prompt = (
            "You are a warehouse analytics SQL expert. The user asked a question "
            "and the system matched it to these top KPI dashboard queries.\n\n"
            f'USER QUERY: "{user_query}"\n\n'
            f"TOP KPI CANDIDATES (with their parameter-substituted SQL):\n\n"
            f"{candidates_text}\n\n"
            f"TABLE / COLUMN REFERENCE (only these tables exist):\n{table_context}\n\n"
            "CRITICAL CONSTRAINT:\n"
            "You MUST pick one of the above KPI candidates. These KPIs contain "
            "proven, tested SQL that is already parameterised for the user's "
            "location and time range. Do NOT return NONE unless the user's "
            "question is completely unrelated to warehouse operations (e.g. "
            "weather, sports, jokes). If the user asks for a metric that is "
            "computable from the columns in ANY candidate's SQL, pick that "
            "candidate and adjust its SQL.\n\n"
            "YOUR TASK:\n"
            "1. Pick the KPI whose SQL can best answer the user's question.\n"
            "2. If it matches perfectly → return its SQL as-is.\n"
            "3. If it's close but needs modification, you may:\n"
            "   a. COLUMN PROJECTION: wrap in subquery to select fewer columns:\n"
            "      SELECT _cp.COL1 FROM ( <original_sql_without_semicolon> ) AS _cp;\n"
            "   b. AGGREGATION: wrap to SUM/AVG/COUNT over original columns:\n"
            "      SELECT SUM(_cp.INACTIVE_HOURS) AS TOTAL_INACTIVE_HOURS "
            "FROM ( <original_sql_without_semicolon> ) AS _cp "
            "WHERE _cp.BOT_ID = 'BOT-0009';\n"
            "   c. FILTER: add WHERE to the wrapper to filter specific rows.\n"
            "4. NEVER invent new tables or columns. Use ONLY what exists in the "
            "   candidate SQL and the TABLE/COLUMN REFERENCE above.\n"
            "5. Preserve the inner SQL structure exactly (CTEs, JOINs, WHERE, "
            "   ORDER BY). Only wrap the outer SELECT.\n\n"
            "DOMAIN RULES:\n"
            "• \"active time/hours\" for a specific bot → Active vs Inactive hours "
            "KPI, project BOT_ID + ACTIVE_HOURS.\n"
            "• \"inactive time/hours\" for a specific bot → Active vs Inactive hours "
            "KPI, project BOT_ID + INACTIVE_HOURS.\n"
            "• \"total inactive time\" for a bot → Active vs Inactive hours KPI, "
            "project BOT_ID + INACTIVE_HOURS (this gives per-bot hours, which IS "
            "the total inactive time for that bot).\n"
            "• \"active vs inactive\" or comparison → keep ALL columns.\n"
            "• \"how many bots\" / \"count of bots\" (no time words) → count KPI.\n"
            "• \"number of inactive bots\" / \"count inactive bots\" → Inactive Bots count KPI.\n"
            "• The SQL must be valid MySQL 8.x.\n\n"
            "Respond with valid JSON matching the required schema."
        )

        try:
            resp = client.responses.create(
                model=self.sql_engine.model,
                input=prompt,
                temperature=0,
                timeout=30,
                text={
                    "format": {
                        "type": "json_schema",
                        "name": "kpi_refinement",
                        "strict": True,
                        "schema": self._KPI_REFINE_SCHEMA,
                    }
                },
            )
            result = json.loads(resp.output_text)

            selected_id = result.get("selected_kpi_id", "NONE").strip()
            logger.info(
                f"📊 LLM KPI refiner: selected_kpi_id='{selected_id}' "
                f"for '{user_query[:80]}'. "
                f"explanation='{result.get('explanation', '')[:200]}'"
            )

            if selected_id.upper() == "NONE":
                logger.info(
                    f"📊 LLM KPI refiner: rejected all candidates "
                    f"for '{user_query[:80]}' — falling through to SQL gen"
                )
                return None

            # Validate the selected id is in our candidates
            valid_ids = {c["kpi_id"] for c in candidate_sqls}
            if selected_id not in valid_ids:
                logger.warning(
                    f"📊 LLM KPI refiner: invalid id '{selected_id}', "
                    f"valid={valid_ids}. Falling back."
                )
                return None

            selected = next(c for c in candidate_sqls if c["kpi_id"] == selected_id)

            return {
                "kpi_id": selected_id,
                "kpi_name": selected["kpi_name"],
                "sql": result["sql"],
                "chart_type": result.get("chart_type", selected["chart_type"]),
                "explanation": result.get("explanation", ""),
                "tables_used": selected["tables_used"],
                "logic": selected["logic"],
                "score": selected["score"],
            }

        except Exception as e:
            logger.warning(f"📊 LLM KPI refiner error: {e}")
            return None

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
        #  TIERED KPI STRATEGY:
        #    ≥ 0.90  → auto-accept (high confidence, execute directly)
        #    0.55–0.90 → LLM refines from top-3 KPI SQL queries
        #    < 0.55  → already rejected by resolver (never reaches here)
        # ═══════════════════════════════════════════════════════

        # Log top candidates for diagnostics
        if kpi_match.top_candidates:
            for c in kpi_match.top_candidates:
                logger.info(
                    f"📊 KPI candidate: id={c['kpi_id']}, "
                    f"'{c['kpi_name']}' (score={c['score']:.3f})"
                )

        # ── Always route through LLM refiner ──
        # Even high-scoring keyword matches can pick the wrong KPI
        # within a family (e.g. station-wise vs trend vs stat for IPP).
        # The LLM sees top-5 candidates with their SQL + example user
        # queries and makes the final pick.
        logger.info(
            f"📊 KPI match ({kpi_match.match_score:.3f}): "
            f"invoking LLM KPI refiner for '{kpi_match.kpi_name}'"
        )
        llm_result = self._llm_refine_kpi_query(
            user_query=clean_question,
            kpi_match=kpi_match,
            tenant_values=tenant_values,
            time_from=_kpi_time_from,
            time_to=_kpi_time_to,
            all_sites=all_sites,
            bot_id=_bot_id,
            station_id=_station_id,
            bin_id=_bin_id,
            wave_id=_wave_id,
            order_id=_order_id,
            category_value=_category_value,
            location_breakdown=location_breakdown,
        )

        if llm_result is None:
            # LLM refiner unavailable or rejected all → use top-1 as fallback
            logger.info(
                f"📊 LLM refiner returned None for: '{clean_question}' — "
                f"using top KPI match '{kpi_match.kpi_name}' as fallback"
            )
            return kpi_match

        # ── Build KPIMatch from LLM-refined result ──
        selected_id = llm_result["kpi_id"]
        picked_entry = None
        for kpi_entry in self.kpi_resolver.kpis:
            if kpi_entry.id == selected_id:
                picked_entry = kpi_entry
                break

        if picked_entry:
            from .kpi_resolver import KPIMatch
            refined_params = kpi_match.parameters_applied.copy()
            refined_params["llm_refined"] = "true"
            if selected_id != kpi_match.kpi_id:
                refined_params["llm_switched_from"] = kpi_match.kpi_id
            if llm_result.get("explanation"):
                refined_params["llm_explanation"] = llm_result["explanation"][:200]

            kpi_match = KPIMatch(
                kpi_id=selected_id,
                kpi_name=picked_entry.kpi_name,
                category=picked_entry.category,
                chart_type=llm_result.get("chart_type", picked_entry.chart_type),
                logic=picked_entry.logic,
                sql=llm_result["sql"],
                raw_query=picked_entry.query,
                match_score=llm_result.get("score", kpi_match.match_score),
                tables_used=picked_entry.tables_used,
                requires_location=picked_entry.requires_location,
                requires_time_range=picked_entry.requires_time_range,
                parameters_applied=refined_params,
                top_candidates=kpi_match.top_candidates,
            )
            logger.info(
                f"📊 LLM refined KPI: {selected_id} '{picked_entry.kpi_name}' "
                f"(switched={selected_id != kpi_match.kpi_id}). "
                f"Explanation: {llm_result.get('explanation', '')[:150]}"
            )
        else:
            logger.warning(
                f"📊 LLM refiner returned unknown kpi_id={selected_id}, "
                f"keeping original match"
            )

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