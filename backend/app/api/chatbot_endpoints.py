"""
NEO Chatbot API Endpoints
FastAPI routes for chatbot functionality
"""

import logging
import uuid
from typing import Dict, Any
from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from pathlib import Path

from ..models.schemas import (
    ChatRequest, 
    ChatResponse, 
    ChatbotType,
    SQLQueryRequest,
    SQLQueryResponse,
    SystemHealthStatus
)
from ..services.knowledge_base_service import KnowledgeBaseService
from ..services.sql_assistant import SQLAssistantService, SQLAssistantGPT4Service
from ..services.diagnostic_service import DiagnosticService
from ..services.agentic_service import get_agentic_service
from ..services.semi_automated_diagnostic_service import SemiAutomatedDiagnosticService
from ..core.config import settings

logger = logging.getLogger(__name__)

# Create router
router = APIRouter(prefix="/api/chatbot", tags=["NEO Chatbot"])

# Initialize services
kb_service = KnowledgeBaseService()

# Initialize SQL Assistant based on mode
if settings.SQL_ASSISTANT_MODE == "gpt4":
    sql_service = SQLAssistantGPT4Service()
    logger.info("✅ SQL Assistant Mode: GPT-4 Multi-Layer Architecture (NEW)")
else:
    sql_service = SQLAssistantService()
    logger.info("✅ SQL Assistant Mode: Phase 3 Semantic Frame Architecture (LEGACY)")

diagnostic_service = DiagnosticService()
semi_auto_diagnostic = SemiAutomatedDiagnosticService()

# Initialize agentic service if enabled
agentic_service = get_agentic_service() if settings.AGENTIC_MODE_ENABLED else None
if agentic_service:
    logger.info("✅ Agentic AI mode is ENABLED - using multi-agent verification system")
else:
    logger.info("ℹ️ Agentic AI mode is DISABLED - using traditional single-agent system")

# Session storage (in production, use Redis or database)
chat_sessions: Dict[str, list] = {}


@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Main chat endpoint - routes to appropriate service based on chatbot type
    """
    try:
        logger.info(f"📨 Chat request: type={request.chatbot_type}, message={request.message[:50]}...")
        
        # Get or create session
        session_id = request.session_id or str(uuid.uuid4())
        if session_id not in chat_sessions:
            chat_sessions[session_id] = []
        
        # Add user message to history
        chat_sessions[session_id].append({
            "role": "user",
            "content": request.message
        })
        
        # Route to appropriate service
        if request.chatbot_type == ChatbotType.KNOWLEDGE_BASE:
            # Use agentic service if enabled, otherwise fallback to traditional
            if agentic_service and settings.AGENTIC_MODE_ENABLED:
                logger.info("🤖 Using Agentic AI (multi-agent verification system)")
                response = agentic_service.process_query(request)
            else:
                logger.info("📚 Using traditional Knowledge Base service")
                response = kb_service.process_query(request)
        elif request.chatbot_type == ChatbotType.SQL_ASSISTANT:
            response = sql_service.process_query(request)
        elif request.chatbot_type == ChatbotType.DIAGNOSTIC:
            response = diagnostic_service.process_query(request)
        else:
            raise HTTPException(status_code=400, detail=f"Invalid chatbot type: {request.chatbot_type}")
        
        # Add assistant response to history
        chat_sessions[session_id].append({
            "role": "assistant",
            "content": response.response
        })
        
        logger.info(f"✅ Chat response generated: confidence={response.confidence_score:.2f}")
        return response
        
    except Exception as e:
        logger.error(f"❌ Error in chat endpoint: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sql-query", response_model=SQLQueryResponse)
async def execute_sql_query(request: SQLQueryRequest):
    """
    Generate SQL query from natural language
    Note: Does not execute query, only generates it
    """
    try:
        logger.info(f"🔍 SQL query request: {request.query[:50]}...")
        
        chat_request = ChatRequest(
            message=request.query,
            chatbot_type=ChatbotType.SQL_ASSISTANT,
            session_id=request.session_id
        )
        
        response = sql_service.process_query(chat_request)
        
        # Extract SQL from response
        sql_query = sql_service._extract_sql_query(response.response)
        
        return SQLQueryResponse(
            query=request.query,
            generated_sql=sql_query,
            explanation=response.response,
            confidence_score=response.confidence_score,
            session_id=response.session_id
        )
        
    except Exception as e:
        logger.error(f"❌ Error in SQL query endpoint: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/upload-document")
async def upload_document(
    file: UploadFile = File(...),
    category: str = Form("general")
):
    """
    Upload a document to the knowledge base
    Supports: PDF, DOCX, TXT
    """
    try:
        logger.info(f"📤 Uploading document: {file.filename}")
        
        # Validate file type
        allowed_extensions = {".pdf", ".docx", ".txt"}
        file_ext = Path(file.filename).suffix.lower()
        
        if file_ext not in allowed_extensions:
            raise HTTPException(
                status_code=400, 
                detail=f"Unsupported file type. Allowed: {', '.join(allowed_extensions)}"
            )
        
        # Save file temporarily
        upload_dir = Path(__file__).parent.parent / "data" / "documents"
        upload_dir.mkdir(parents=True, exist_ok=True)
        
        file_path = upload_dir / file.filename
        with open(file_path, "wb") as f:
            content = await file.read()
            f.write(content)
        
        # Ingest document
        result = kb_service.ingest_document(str(file_path), category)
        
        logger.info(f"✅ Document uploaded and indexed: {file.filename}")
        return {
            "filename": file.filename,
            "category": category,
            "size_bytes": len(content),
            "status": "success",
            "message": f"Document uploaded and indexed successfully. {result.get('chunks', 0)} chunks created."
        }
        
    except Exception as e:
        logger.error(f"❌ Error uploading document: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/system-health", response_model=SystemHealthStatus)
async def get_system_health():
    """
    Get current system health status
    """
    try:
        logger.info("🏥 Checking system health...")
        health_status = diagnostic_service.check_system_health()
        return health_status
        
    except Exception as e:
        logger.error(f"❌ Error checking system health: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/statistics")
async def get_statistics():
    """
    Get chatbot statistics and metrics
    """
    try:
        kb_stats = kb_service.get_statistics()
        sql_stats = sql_service.get_statistics()
        diag_stats = diagnostic_service.get_statistics()
        
        return {
            "knowledge_base": kb_stats,
            "sql_assistant": sql_stats,
            "diagnostic": diag_stats,
            "total_sessions": len(chat_sessions)
        }
        
    except Exception as e:
        logger.error(f"❌ Error getting statistics: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/session/{session_id}")
async def clear_session(session_id: str):
    """
    Clear a chat session history
    """
    try:
        if session_id in chat_sessions:
            del chat_sessions[session_id]
            logger.info(f"🗑️ Cleared session: {session_id}")
            return {"status": "success", "message": f"Session {session_id} cleared"}
        else:
            raise HTTPException(status_code=404, detail="Session not found")
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error clearing session: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/session/{session_id}/history")
async def get_session_history(session_id: str):
    """
    Get chat history for a session
    """
    try:
        if session_id in chat_sessions:
            return {
                "session_id": session_id,
                "messages": chat_sessions[session_id]
            }
        else:
            return {
                "session_id": session_id,
                "messages": []
            }
            
    except Exception as e:
        logger.error(f"❌ Error getting session history: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/health")
async def health_check():
    """
    Simple health check endpoint
    """
    return {
        "status": "healthy",
        "service": "NEO Chatbot API",
        "version": "1.0.0"
    }


# ===== Chat History & Analytics Endpoints =====

@router.get("/analytics/sql-queries")
async def get_sql_query_analytics(days: int = 7):
    """
    Get analytics for SQL queries over specified time period
    
    Query Parameters:
        days: Number of days to analyze (default: 7)
    
    Returns:
        Analytics including success rates, common tables, intents, and errors
    """
    try:
        if not hasattr(sql_service, 'chat_history_service') or not sql_service.chat_history_service:
            raise HTTPException(
                status_code=503, 
                detail="Chat history service not available"
            )
        
        analytics = sql_service.chat_history_service.get_query_analytics(days=days)
        
        return {
            "status": "success",
            "analytics": analytics
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting SQL analytics: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/analytics/learned-patterns")
async def get_learned_patterns(limit: int = 50):
    """
    Get learned query patterns that have high success rates
    
    Query Parameters:
        limit: Maximum number of patterns to return (default: 50)
    
    Returns:
        List of successful query patterns with frequency and confidence
    """
    try:
        if not hasattr(sql_service, 'chat_history_service') or not sql_service.chat_history_service:
            raise HTTPException(
                status_code=503, 
                detail="Chat history service not available"
            )
        
        patterns = sql_service.chat_history_service.get_common_query_patterns(limit=limit)
        
        return {
            "status": "success",
            "patterns_count": len(patterns),
            "patterns": patterns
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting learned patterns: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/analytics/column-mappings")
async def get_learned_column_mappings(min_frequency: int = 3):
    """
    Get learned column name mappings from corrections
    
    Query Parameters:
        min_frequency: Minimum number of times mapping must occur (default: 3)
    
    Returns:
        Column mappings grouped by table with frequency and confidence
    """
    try:
        if not hasattr(sql_service, 'chat_history_service') or not sql_service.chat_history_service:
            raise HTTPException(
                status_code=503, 
                detail="Chat history service not available"
            )
        
        mappings = sql_service.chat_history_service.get_learned_column_mappings(
            min_frequency=min_frequency
        )
        
        return {
            "status": "success",
            "tables_count": len(mappings),
            "mappings": mappings
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting column mappings: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/analytics/improvement-suggestions")
async def get_improvement_suggestions():
    """
    Get suggestions for improving the SQL assistant based on historical data
    
    Returns:
        Categorized suggestions for system improvements
    """
    try:
        if not hasattr(sql_service, 'chat_history_service') or not sql_service.chat_history_service:
            raise HTTPException(
                status_code=503, 
                detail="Chat history service not available"
            )
        
        suggestions = sql_service.chat_history_service.get_improvement_suggestions()
        
        total_suggestions = sum(len(v) for v in suggestions.values())
        
        return {
            "status": "success",
            "total_suggestions": total_suggestions,
            "suggestions": suggestions
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting improvement suggestions: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/history/{session_id}")
async def get_persistent_session_history(session_id: str, limit: int = 50):
    """
    Get persistent chat history for a session from database
    
    Query Parameters:
        limit: Maximum number of messages to return (default: 50)
    
    Returns:
        Chat history with queries, responses, SQL, and execution status
    """
    try:
        if not hasattr(sql_service, 'chat_history_service') or not sql_service.chat_history_service:
            raise HTTPException(
                status_code=503, 
                detail="Chat history service not available"
            )
        
        history = sql_service.chat_history_service.get_session_history(
            session_id=session_id,
            limit=limit
        )
        
        return {
            "status": "success",
            "session_id": session_id,
            "message_count": len(history),
            "history": history
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting session history: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/feedback")
async def submit_feedback(
    chat_id: str,
    session_id: str,
    feedback_type: str,
    rating: int = None,
    comment: str = None
):
    """
    Submit user feedback for a specific chat interaction
    
    Body Parameters:
        chat_id: Unique ID of the chat interaction
        session_id: Session ID
        feedback_type: Type of feedback ('positive', 'negative', 'neutral')
        rating: Optional numerical rating (1-5)
        comment: Optional text comment
    
    Returns:
        Success confirmation
    """
    try:
        if not hasattr(sql_service, 'chat_history_service') or not sql_service.chat_history_service:
            raise HTTPException(
                status_code=503, 
                detail="Chat history service not available"
            )
        
        # Validate feedback_type
        if feedback_type not in ['positive', 'negative', 'neutral']:
            raise HTTPException(
                status_code=400,
                detail="feedback_type must be 'positive', 'negative', or 'neutral'"
            )
        
        # Validate rating if provided
        if rating is not None and (rating < 1 or rating > 5):
            raise HTTPException(
                status_code=400,
                detail="rating must be between 1 and 5"
            )
        
        sql_service.chat_history_service.log_feedback(
            chat_id=chat_id,
            session_id=session_id,
            feedback_type=feedback_type,
            rating=rating,
            comment=comment
        )
        
        # Also log to RLHF service for cross-session learning
        try:
            sql_service.rlhf_service.record_feedback(
                chatbot_type="sql_assistant",
                query="",  # Would need to fetch from DB
                response="",  # Would need to fetch from DB
                feedback_type=feedback_type,
                rating=rating,
                comment=comment,
                metadata={"chat_id": chat_id}
            )
        except Exception as e:
            logger.warning(f"Failed to record RLHF feedback: {e}")
        
        return {
            "status": "success",
            "message": "Feedback recorded successfully"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error submitting feedback: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# SEMI-AUTOMATED DIAGNOSTIC ENDPOINTS
# ============================================================

@router.post("/diagnostic/start")
async def start_diagnosis(problem_description: str):
    """
    Start semi-automated diagnosis
    
    Args:
        problem_description: User's problem description
    
    Returns:
        Session data with matched cases
    """
    try:
        result = semi_auto_diagnostic.start_diagnosis(problem_description)
        return result
    except Exception as e:
        logger.error(f"❌ Error starting diagnosis: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/diagnostic/audit-sql")
async def audit_with_sql(sql_query: str):
    """
    Execute SQL audit query
    
    Args:
        sql_query: SQL query to execute
    
    Returns:
        Query results and analysis
    """
    try:
        result = semi_auto_diagnostic.execute_sql_audit(sql_query)
        return result
    except Exception as e:
        logger.error(f"❌ Error executing SQL audit: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/diagnostic/analyze-results")
async def analyze_audit_results(case: Dict[str, Any], sql_results: Dict[str, Any]):
    """
    Analyze SQL audit results against expected outcome
    
    Args:
        case: Current diagnostic case
        sql_results: Results from SQL audit
    
    Returns:
        Analysis with recommendations
    """
    try:
        analysis = semi_auto_diagnostic.analyze_sql_results(case, sql_results)
        return analysis
    except Exception as e:
        logger.error(f"❌ Error analyzing results: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/diagnostic/feedback")
async def handle_diagnostic_feedback(
    session_data: Dict[str, Any],
    is_correct: bool,
    user_comment: str = None
):
    """
    Handle user feedback on diagnostic suggestion
    
    Args:
        session_data: Current session data
        is_correct: Whether the solution worked
        user_comment: Optional user feedback
    
    Returns:
        Next suggestion or resolution status
    """
    try:
        result = semi_auto_diagnostic.handle_user_feedback(
            session_data, is_correct, user_comment
        )
        return result
    except Exception as e:
        logger.error(f"❌ Error handling feedback: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/diagnostic/summary")
async def get_diagnostic_summary(session_data: Dict[str, Any]):
    """
    Get session summary in concise format
    
    Args:
        session_data: Current session data
    
    Returns:
        Formatted summary
    """
    try:
        summary = semi_auto_diagnostic.get_session_summary(session_data)
        return {"summary": summary}
    except Exception as e:
        logger.error(f"❌ Error getting summary: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))
