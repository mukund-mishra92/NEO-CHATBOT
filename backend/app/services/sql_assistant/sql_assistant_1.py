# from app.models.schemas import ChatResponse, ChatbotType
# from app.services.sql_engine import SQLEngine
# from app.services.chat_history_service import ChatHistoryService
# from app.services.query_classification_service import QueryClassificationService
# from app.core.config import settings
# from app.services.ai_config_service import get_ai_config_service

# from .models import SQLGenerationResult
# from .cache_manager import QueryCacheManager
# from .reuse_engine import QueryReuseEngine
# from .validator import SQLValidator
# from .executor import SQLExecutor
# from .confidence import ConfidenceEvaluator
# from .formatter import SQLFormatter
# from .retry_engine import SQLRetryEngine
# from .learning import QueryLearningManager
# from .query_preprocessor import QueryPreprocessor
# from .schema_validator import SchemaValidator
# from .semantic_validator import SemanticValidator
# from .schema_feedback import SchemaFeedbackGenerator
# from .table_priority_loader import TablePriorityLoader
# from .table_selector import TableSelector

# import logging
# import csv

# logger = logging.getLogger(__name__)


# class SQLAssistantService:

#     def __init__(self):
#         ai_cfg = get_ai_config_service().get_config()
#         sql_provider = ai_cfg.get("active_provider", "openai")
#         sql_model = ai_cfg.get("sql_model", "gpt-5.2")
#         sql_api_key = settings.GROQ_API_KEY if sql_provider == "groq" else settings.OPENAI_API_KEY

#         self.db_config = {
#             "host": settings.DB_HOST,
#             "port": settings.DB_PORT,
#             "user": settings.DB_USER,
#             "password": settings.DB_PASSWORD,
#             "database": settings.DB_NAME
#         }

#         csv_path = settings.DATA_DIR / "database" / "Table_information.csv"

#         self.sql_engine = SQLEngine(
#             api_key=sql_api_key,
#             model=sql_model,
#             provider=sql_provider,
#             schema_csv_path=str(csv_path),
#             db_config=self.db_config
#         )

#         self.chat_history_service = ChatHistoryService(self.db_config)

#         self.classification_service = QueryClassificationService(
#             settings.DATA_DIR / "classification"
#         )

#         self.cache = QueryCacheManager()
#         self.executor = SQLExecutor(self.db_config)
#         self.validator = SQLValidator()
#         self.confidence = ConfidenceEvaluator()
#         self.formatter = SQLFormatter()
#         self.retry_engine = SQLRetryEngine()

#         self.reuse_engine = QueryReuseEngine(
#             self.classification_service,
#             self.executor
#         )

#         self.learning = QueryLearningManager(
#             self.chat_history_service,
#             self.classification_service
#         )

#         self.preprocessor = QueryPreprocessor()

#         self.schema = self._load_schema(csv_path)
#         self.schema_validator = SchemaValidator(self.schema)
#         self.semantic_validator = SemanticValidator()
#         self.feedback_generator = SchemaFeedbackGenerator(self.schema)

#         validations_file = settings.DATA_DIR / "database" / "table_priority_validations.jsonl"
#         self.table_priority_loader = TablePriorityLoader(validations_file)

#         self.table_selector = TableSelector(self.schema)

#         logger.info(f"✅ SQLAssistantService initialized with {len(self.schema)} tables")

#     # ----------------------------------------------------------
#     # SCHEMA LOADER
#     # ----------------------------------------------------------
#     def _load_schema(self, csv_path):
#         schema = {}

#         with open(csv_path, newline="", encoding="utf-8-sig") as f:
#             reader = csv.DictReader(f)
#             headers = {h.lower().strip(): h for h in reader.fieldnames}

#             table_key = headers["table_name"]
#             columns_key = headers["table_columns(data type)"]

#             for row in reader:
#                 table = row[table_key].strip()
#                 columns_raw = row[columns_key]

#                 if not table:
#                     continue

#                 schema[table] = []

#                 if columns_raw:
#                     columns = columns_raw.split(",")
#                     for col in columns:
#                         col_name = col.split("(")[0].strip()
#                         if col_name:
#                             schema[table].append(col_name)

#         logger.info(f"DEBUG: Loaded {len(schema)} tables from schema")
#         return schema

#     # ----------------------------------------------------------
#     # LEARNED TABLE EXTRACTION
#     # ----------------------------------------------------------
#     def _get_learned_tables(self, question: str):
#         match = self.classification_service.find_similar_classified_query(
#             user_query=question,
#             similarity_threshold=0.85
#         )

#         if match and match.get("tables_used"):
#             return match["tables_used"]

#         return []

#     # ----------------------------------------------------------
#     # MAIN QUERY PROCESSOR
#     # ----------------------------------------------------------
#     def process_query(self, request):

#         session_id = request.session_id
#         question = request.message

#         clean_question, entities = self.preprocessor.process(question)

#         cached = self.cache.get(session_id, clean_question)
#         if cached:
#             return cached

#         reused = self.reuse_engine.try_reuse(clean_question)
#         if reused:
#             sql, execution_result = reused
#             generation_result = SQLGenerationResult(
#                 sql=sql,
#                 confidence=0.95,
#                 explanation="Reused from classified queries",
#                 assumptions=["Query was previously validated"],
#                 metadata={"source": "reuse_engine", "tables_used": []}
#             )
#         else:

#             # --------------------------------------------------
#             # 🔥 DETERMINISTIC SCHEMA SCOPING
#             # --------------------------------------------------

#             validated_tables = self.table_priority_loader.get_validated_tables_for_query(clean_question)
#             learned_tables = self._get_learned_tables(clean_question)

#             if validated_tables["correct"]:
#                 selected_tables = validated_tables["correct"]
#                 logger.info(f"🎯 Using validated tables: {selected_tables}")

#             elif learned_tables:
#                 selected_tables = learned_tables
#                 logger.info(f"🧠 Using learned pattern tables: {selected_tables}")

#             else:
#                 selected_tables = self.table_selector.select(clean_question, max_tables=5)
#                 logger.info(f"🔍 Using heuristic selected tables: {selected_tables}")

#             selected_tables = [
#                 t for t in selected_tables
#                 if t not in validated_tables.get("incorrect", [])
#             ]

#             if not selected_tables:
#                 selected_tables = list(self.schema.keys())[:5]

#             logger.info(f"📦 Final schema scope: {selected_tables}")

#             filtered_schema = {
#                 table: self.schema[table]
#                 for table in selected_tables
#                 if table in self.schema
#             }

#             logger.info(
#                 f"📉 Schema reduced from {len(self.schema)} to {len(filtered_schema)} tables"
#             )

#             # --------------------------------------------------
#             # GENERATION FUNCTION
#             # --------------------------------------------------
#             def generate_fn(feedback, previous_sql):

#                 result = self.sql_engine.generate(
#                     question=clean_question,
#                     feedback=feedback,
#                     previous_sql=previous_sql,
#                     enable_entity_resolution=True,
#                     schema_override=filtered_schema   # 🔥 CRITICAL CHANGE
#                 )

#                 metadata = {
#                     "tables_used": result.get("tables_used", []),
#                     "columns_used": result.get("columns_used", []),
#                     "primary_keys_used": result.get("primary_keys_used", []),
#                     "warnings": result.get("warnings", []),
#                     "needs_followup": result.get("needs_followup", False),
#                     "followup_questions": result.get("followup_questions", []),
#                     "resolved_entities": result.get("resolved_entities", {}),
#                     "domains_matched": result.get("domains_matched", []),
#                 }

#                 return SQLGenerationResult(
#                     sql=result["sql"],
#                     confidence=result.get("confidence", 0.75),
#                     explanation=f"Generated SQL using tables: {', '.join(metadata['tables_used'])}",
#                     assumptions=result.get("assumptions", []),
#                     metadata=metadata
#                 )

#             generation_result, execution_result = self.retry_engine.run(
#                 generate_fn,
#                 self.validator,
#                 self.executor,
#                 feedback_generator=self.feedback_generator,
#                 schema_validator=self.schema_validator,
#             )

#             #self.semantic_validator.validate(execution_result)
#             try:
#                 self.semantic_validator.validate(execution_result)
#             except Exception as e:
#                 logger.warning(f"Semantic validation warning: {e}")

#             sql = generation_result.sql

#         final_confidence = self.confidence.compute(
#             generation_result,
#             execution_result
#         )

#         response_text = self.formatter.format(
#             clean_question,
#             sql,
#             execution_result,
#             final_confidence
#         )

#         self.learning.record_success(
#             session_id,
#             clean_question,
#             response_text,
#             sql,
#             execution_result,
#             generation_result,
#             user_id=getattr(request, 'user_id', None)
#         )

#         response = ChatResponse(
#             response=response_text,
#             chatbot_type=ChatbotType.SQL_ASSISTANT,
#             session_id=session_id,
#             sources=[],
#             confidence_score=final_confidence,
#             metadata={
#                 "sql_query": sql,
#                 "row_count": execution_result.row_count,
#                 "resolved_entities": entities
#             }
#         )

#         self.cache.set(session_id, clean_question, response)

#         return response


