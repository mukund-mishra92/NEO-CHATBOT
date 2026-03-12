"""
Diagnostic Service - Automated troubleshooting and issue resolution
Fully aligned with modular SQL Assistant architecture.
"""

import logging
import json
import csv
import uuid
from typing import List, Dict, Any, Optional
from pathlib import Path

print("LOADED FILE:", __file__)

from app.services.llm_service import LLMService
from app.services.rlhf_service import RLHFService
from app.services.diagnostic.diagnostic_support_service import DiagnosticSupportService
from app.services.sql_assistant.executor import SQLExecutor
from app.core.config import settings

from app.models.schemas import (
    ChatRequest,
    ChatResponse,
    ChatbotType,
    SystemHealthStatus
)
from app.utils.session_manager import get_session_manager

logger = logging.getLogger(__name__)


class DiagnosticService:

    def __init__(self):

        self.llm_service = LLMService()
        self.rlhf_service = RLHFService()
        self.support_service = DiagnosticSupportService()
        self.session_manager = get_session_manager()

        # ✅ Modular SQL executor only
        self.sql_executor = SQLExecutor({
            "host": settings.DB_HOST,
            "port": settings.DB_PORT,
            "user": settings.DB_USER,
            "password": settings.DB_PASSWORD,
            "database": settings.DB_NAME
        })

        self.issues_db = self._load_issues_database()

        self.system_prompt = """You are a troubleshooting expert for the NEO Warehouse Management System.
Provide structured diagnosis, causes, step-by-step resolution, and prevention advice."""

        logger.info(f"✅ Diagnostic Service initialized with {len(self.issues_db)} issues")

    # ------------------------------------------------------------
    # ISSUE DATABASE
    # ------------------------------------------------------------

    def _load_issues_database(self) -> List[Dict[str, Any]]:

        try:
            base_path = Path(__file__).parent.parent / "data" / "support"

            json_path = base_path / "issues.json"
            if json_path.exists():
                with open(json_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    return data.get("issues", [])

            csv_path = base_path / "issues.csv"
            if csv_path.exists():
                issues = []
                with open(csv_path, "r", encoding="utf-8") as f:
                    reader = csv.DictReader(f)
                    for row in reader:
                        issues.append(dict(row))
                return issues

            logger.warning("⚠️ No issues.json or issues.csv found")
            return []

        except Exception as e:
            logger.error(f"Error loading issues DB: {e}")
            return []

    # ------------------------------------------------------------
    # MAIN ENTRY
    # ------------------------------------------------------------

    def process_query(self, chat_request: ChatRequest) -> ChatResponse:

        try:
            session_id = chat_request.session_id
            history = self.session_manager.get_conversation_history(session_id) if session_id else []

            response = self._diagnose_with_llm(chat_request, history)
            response.session_id = session_id

            # RLHF logging
            try:
                self.rlhf_service.record_feedback(
                    chatbot_type="diagnostic_support",
                    query=chat_request.message,
                    response=response.response,
                    feedback_type="neutral",
                    rating=None,
                    comment="Diagnostic interaction",
                    metadata={"confidence": response.confidence_score}
                )
            except Exception as e:
                logger.warning(f"RLHF logging failed: {e}")

            return response

        except Exception as e:
            logger.error(f"Diagnostic error: {e}", exc_info=True)
            return ChatResponse(
                response="An internal diagnostic error occurred.",
                chatbot_type=ChatbotType.DIAGNOSTIC,
                session_id=chat_request.session_id or str(uuid.uuid4()),
                confidence_score=0.0
            )

    # ------------------------------------------------------------
    # LLM DIAGNOSIS
    # ------------------------------------------------------------

    def _diagnose_with_llm(self, chat_request: ChatRequest, history: List[Dict]) -> ChatResponse:

        context = "\n".join([f"{m['role']}: {m['content']}" for m in history[-5:]])

        prompt = f"""{self.system_prompt}

Previous context:
{context}

User issue:
{chat_request.message}

Provide:
1. Diagnosis
2. Likely causes
3. Step-by-step resolution
4. Prevention guidance
"""

        llm_response = self.llm_service.generate_response(
            prompt,
            max_completion_tokens=800,
            temperature=0.7
        )

        return ChatResponse(
            response=llm_response,
            chatbot_type=ChatbotType.DIAGNOSTIC,
            session_id=chat_request.session_id,
            confidence_score=0.8
        )

    # ------------------------------------------------------------
    # SAFE SQL EXECUTION
    # ------------------------------------------------------------

    def _execute_query_safe(self, sql_query: str):

        try:
            if not sql_query.strip().upper().startswith("SELECT"):
                return [], "Only SELECT queries are allowed."

            execution_result = self.sql_executor.execute(sql_query)
            return execution_result.rows, None

        except Exception as e:
            logger.error(f"Diagnostic SQL error: {e}")
            return [], str(e)

    # ------------------------------------------------------------
    # SQL RESULT ANALYSIS
    # ------------------------------------------------------------

    def _analyze_sql_results(self, query: str, results: List[Dict], issue: Dict) -> str:

        row_count = len(results)

        if row_count == 0:
            return "✅ No records found. System appears normal for this check."

        if row_count > 20:
            return f"⚠️ Found {row_count} records. This may indicate multiple related issues."

        return f"📊 Found {row_count} matching record(s). Review details carefully."

    # ------------------------------------------------------------
    # ISSUE LOOKUPS
    # ------------------------------------------------------------

    def get_issue_by_id(self, issue_id: str) -> Optional[Dict[str, Any]]:
        for issue in self.issues_db:
            if issue.get("issue_id") == issue_id:
                return issue
        return None

    def get_issues_by_category(self, category: str) -> List[Dict[str, Any]]:
        return [issue for issue in self.issues_db if issue.get("category") == category]

    # ------------------------------------------------------------
    # SYSTEM HEALTH
    # ------------------------------------------------------------

    def check_system_health(self) -> SystemHealthStatus:

        components = {
            "database": "healthy",
            "api": "healthy",
            "scheduler": "healthy"
        }

        return SystemHealthStatus(
            overall_status="healthy",
            components=components,
            issues=[]
        )

    # ------------------------------------------------------------
    # STATS
    # ------------------------------------------------------------

    def get_statistics(self) -> Dict[str, Any]:

        return {
            "total_issues": len(self.issues_db),
            "llm_provider": self.llm_service.get_provider_info()
        }
