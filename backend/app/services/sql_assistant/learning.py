from datetime import datetime


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

        # Log to chatbot_chat_history first (creates the parent record for FK)
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

        if generation_result.confidence >= 0.5:
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
