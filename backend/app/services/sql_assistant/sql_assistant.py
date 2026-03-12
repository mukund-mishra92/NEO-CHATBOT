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

        self.reuse_engine = QueryReuseEngine(
            self.classification_service,
            self.executor
        )

        self.learning = QueryLearningManager(
            self.chat_history_service,
            self.classification_service
        )

        self.preprocessor = QueryPreprocessor()

        self.schema = self._load_schema(csv_path)
        self.schema_validator = SchemaValidator(self.schema)
        self.semantic_validator = SemanticValidator()
        self.feedback_generator = SchemaFeedbackGenerator(self.schema)

        validations_file = settings.DATA_DIR / "database" / "table_priority_validations.jsonl"
        self.table_priority_loader = TablePriorityLoader(validations_file)


        self.table_selector = TableSelector(
            schema=self.schema,
            table_metadata=self.business_context
        )

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
    def _enforce_entities_in_sql(self, sql: str, entities: dict) -> str:
        for key, value in entities.items():

            in_pattern = rf"\b{key}\b\s+IN\s*\([^)]+\)"
            sql = re.sub(in_pattern, f"{key} = '{value}'", sql, flags=re.IGNORECASE)

            eq_pattern = rf"\b{key}\b\s*=\s*'[^']+'"
            sql = re.sub(eq_pattern, f"{key} = '{value}'", sql, flags=re.IGNORECASE)

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

        logger.info(f"🧠 Resolved entities: {entities}")
        logger.info(f"📝 Clean question: {clean_question}")

        cached = self.cache.get(session_id, clean_question)
        if cached:
            return cached

        reused = self.reuse_engine.try_reuse(clean_question)

        if reused:
            sql, execution_result = reused
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
                selected_tables = self.table_selector.select(clean_question, max_tables=20)
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
                    })

                filtered_schema[table] = enriched

            # --------------------------------------------------
            # GENERATION FUNCTION
            # --------------------------------------------------
            def generate_fn(feedback, previous_sql):

                entity_context = "\n".join(
                    [f"{k} = '{v}'" for k, v in entities.items()]
                )

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

                # Ensure entity present (forces retry if missing)
                for key, value in entities.items():
                    if value not in sql:
                        raise ValueError(f"Missing required entity {key} in SQL.")

                return SQLGenerationResult(
                    sql=sql,
                    confidence=result.get("confidence", 0.75),
                    explanation="Generated with enforced canonical entity resolution",
                    assumptions=result.get("assumptions", []),
                    metadata=result
                )

            generation_result, execution_result = self.retry_engine.run(
                generate_fn,
                self.validator,
                self.executor,
                feedback_generator=self.feedback_generator,
                schema_validator=self.schema_validator,
            )

            # Restore semantic validation
            try:
                self.semantic_validator.validate(execution_result)
            except Exception as e:
                logger.warning(f"Semantic validation warning: {e}")

            sql = generation_result.sql

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
