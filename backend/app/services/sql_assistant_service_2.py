# app/services/sql_assistant_service.py

import uuid
import logging
from datetime import datetime
from typing import Dict

from app.core.config import settings
from app.models.schemas import ChatRequest, ChatResponse
from app.services.nl_to_sql_generator import NLToSQLGenerator

logger = logging.getLogger(__name__)


class SQLAssistantService:

    def __init__(self, schema_csv_path: str | None = None):
        self.nl_to_sql = NLToSQLGenerator(
            api_key=settings.OPENAI_API_KEY,
            model=settings.NL2SQL_MODEL or "gpt-5.2",
            schema_csv_path=schema_csv_path,  # 🔑 HERE
        )

        self.high_confidence_threshold = 0.92
        self.max_refinement_iterations = 3
        self.judge_confidence_threshold = 0.90

        self.session_query_cache: Dict[str, list] = {}

        # Existing infra
        self.schema_parser = self._load_schema_parser()
        self.available_tables = self._get_available_tables()

    # ----------------------------------------------------
    # MAIN ENTRY
    # ----------------------------------------------------
    def process_query(self, chat_request: ChatRequest) -> ChatResponse:
        query = chat_request.message
        session_id = chat_request.session_id or str(uuid.uuid4())

        # 1️⃣ Tier-0 CSV-based NL→SQL
        candidate = self.nl_to_sql.generate(query)
        sql = candidate["sql"]
        confidence = candidate.get("confidence", 0.0)

        use_shortcut = confidence > self.high_confidence_threshold

        logger.info(
            f"NL→SQL | confidence={confidence:.2f} | shortcut={use_shortcut}"
        )

        # 2️⃣ Cache
        self.session_query_cache.setdefault(session_id, []).append({
            "query": query,
            "sql": sql,
            "confidence": confidence,
            "timestamp": datetime.utcnow().isoformat()
        })

        # 3️⃣ Always validate
        tables_ok, _ = self._validate_sql_tables(sql)
        cols_ok, _ = self._validate_sql_columns(sql)
        values_ok, _ = self._validate_query_values(sql)

        if not (tables_ok and cols_ok and values_ok):
            use_shortcut = False

        # 4️⃣ Shortcut path
        if use_shortcut:
            results, error = self._execute_query_safe(sql)
            if not error:
                return ChatResponse(
                    success=True,
                    sql=sql,
                    data=results,
                    confidence=confidence,
                    used_shortcut=True,
                    session_id=session_id
                )

        # 5️⃣ Refinement fallback
        refined_sql = sql
        judge_confidence = 0.0

        for _ in range(self.max_refinement_iterations):
            refined_sql, judge_confidence = self._refine_sql_with_judge(
                refined_sql, query
            )
            if judge_confidence >= self.judge_confidence_threshold:
                break

        results, error = self._execute_query_safe(refined_sql)
        if error:
            return ChatResponse(
                success=False,
                message="SQL execution failed",
                session_id=session_id
            )

        return ChatResponse(
            success=True,
            sql=refined_sql,
            data=results,
            confidence=max(confidence, judge_confidence),
            used_shortcut=False,
            session_id=session_id
        )

    # ----------------------------------------------------
    # EXISTING METHODS (UNCHANGED)
    # ----------------------------------------------------
    def _load_schema_parser(self): ...
    def _get_available_tables(self): ...
    def _validate_sql_tables(self, sql: str): ...
    def _validate_sql_columns(self, sql: str): ...
    def _validate_query_values(self, sql: str): ...
    def _refine_sql_with_judge(self, sql: str, query: str): ...
    def _execute_query_safe(self, sql: str): ...
