from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class QueryLearningManager:

    def __init__(self, chat_history_service, classification_service):
        self.chat_history_service = chat_history_service
        self.classification_service = classification_service

    def record_success(
        self,
        session_id,
        question,
        response_text,
        sql,
        execution_result,
        generation_result,
        user_id=None
    ):
        response_time_ms = execution_result.execution_time_ms

        # 1. Log to chat history (parent record for FK)
        try:
            chat_id = self.chat_history_service.log_chat_interaction(
                session_id=session_id,
                chatbot_type="sql_assistant",
                user_query=question,
                assistant_response=response_text,
                confidence_score=generation_result.confidence,
                response_time_ms=response_time_ms,
                user_id=user_id
            )

            self.chat_history_service.log_sql_query(
                chat_id=chat_id,
                session_id=session_id,
                user_query=question,
                generated_sql=sql,
                execution_status="success",
                rows_returned=execution_result.row_count,
                execution_time_ms=response_time_ms,
                user_id=user_id
            )
        except Exception as e:
            logger.warning(f"⚠️ Chat history logging failed (non-fatal): {e}")

        # 2. Store in classification service for future reuse
        #    SKIP if this was a reused query (source == 'reuse_engine') to avoid
        #    storing duplicates with empty tables_used
        is_reused = generation_result.metadata.get("source") == "reuse_engine"
        has_sufficient_confidence = generation_result.confidence >= 0.5
        has_tables = bool(generation_result.metadata.get("tables_used"))

        if has_sufficient_confidence and not is_reused and has_tables:
            try:
                self.classification_service.store_query(
                    session_id=session_id,
                    user_query=question,
                    generated_sql=sql,
                    execution_status="success",
                    rows_returned=execution_result.row_count,
                    confidence=generation_result.confidence,
                    tables_used=generation_result.metadata.get("tables_used", []),
                    metadata=generation_result.metadata
                )
            except Exception as e:
                logger.warning(f"⚠️ Classification storage failed (non-fatal): {e}")
        elif is_reused:
            logger.debug("Skipping classification storage for reused query")
        elif not has_tables:
            logger.debug("Skipping classification storage: no tables_used in metadata")
