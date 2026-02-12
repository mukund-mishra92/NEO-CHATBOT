"""
NEO Chatbot API Endpoints
FastAPI routes for chatbot functionality
"""

import logging
import time
import uuid
from typing import Dict, Any, List
from datetime import datetime
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
from ..services.sql_assistant_integrated import SQLAssistantService
from ..services.diagnostic_service import DiagnosticService
from ..services.chat_history_service import ChatHistoryService
from ..services.agentic_service import get_agentic_service
# NOTE: Old SemiAutomatedDiagnosticService has been replaced with SemiAutoSOPService
# New SOP-based endpoints are in diagnostic_support_routes.py under /api/diagnostic-support/sop/*
from app.core.config import settings
from ..utils.session_manager import get_session_manager, SessionType

logger = logging.getLogger(__name__)

# Create router
router = APIRouter(prefix="/api/chatbot", tags=["NEO Chatbot"])

# Initialize services
kb_service = KnowledgeBaseService()
sql_service = SQLAssistantService()
diagnostic_service = DiagnosticService()
# NOTE: semi_auto_diagnostic removed - use /api/diagnostic-support/sop/* endpoints instead
session_manager = get_session_manager()

# Initialize chat history service for non-SQL chat logging (Knowledge Base, etc.)
try:
    _chat_history_db_config = {
        'host': settings.DB_HOST,
        'port': settings.DB_PORT,
        'user': settings.DB_USER,
        'password': settings.DB_PASSWORD,
        'database': settings.DB_NAME
    }
    chat_history_service = ChatHistoryService(_chat_history_db_config)
    logger.info("✅ Chat history logging enabled for non-SQL chat")
except Exception as e:
    logger.warning(f"⚠️ Chat history service unavailable for non-SQL chat: {e}")
    chat_history_service = None

# Initialize agentic service if enabled
agentic_service = get_agentic_service() if settings.AGENTIC_MODE_ENABLED else None
if agentic_service:
    logger.info("✅ Agentic AI mode is ENABLED - using multi-agent verification system")
else:
    logger.info("ℹ️ Agentic AI mode is DISABLED - using traditional single-agent system")

# DEPRECATED: Old session storage - now using session_manager instead
# chat_sessions: Dict[str, list] = {}


@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Main chat endpoint - routes to appropriate service based on chatbot type
    Uses unified session management for conversation memory
    """
    try:
        logger.info(f"📨 Chat request: type={request.chatbot_type}, message={request.message[:50]}...")
        start_time = time.time()
        
        # STEP 1: Get or create unified session
        session_id = request.session_id
        session = None
        
        if session_id:
            session = session_manager.get_session(session_id)
        
        if not session:
            # Create new session
            session_type_map = {
                ChatbotType.KNOWLEDGE_BASE: SessionType.KNOWLEDGE_BASE,
                ChatbotType.SQL_ASSISTANT: SessionType.SQL_ASSISTANT,
                ChatbotType.DIAGNOSTIC: SessionType.DIAGNOSTIC,
                ChatbotType.SEMI_AUTO_DIAGNOSTIC: SessionType.SEMI_AUTO_DIAGNOSTIC,
            }
            
            session_type = session_type_map.get(request.chatbot_type, SessionType.GENERAL)
            session_id = session_manager.create_session(
                session_type=session_type,
                initial_message=request.message
            )
            logger.info(f"🆕 Created new session: {session_id}")
        else:
            # Add user message to existing session
            session_manager.add_message(session_id, 'user', request.message)
        
        # STEP 2: Get conversation history for context
        conversation_history = session_manager.get_conversation_history(session_id)
        # Ensure services receive server-side history even if client sends none
        request.conversation_history = conversation_history
        
        # STEP 2.5: CHECK IF USER IS ASKING ABOUT SESSION/CONVERSATION HISTORY
        # This must be handled BEFORE routing to any service!
        if _is_session_query(request.message):
            logger.info(f"📋 Detected session/conversation query - returning history directly")
            # Get history EXCLUDING the current question about history
            history_for_summary = conversation_history[:-1] if conversation_history else []
            response = _generate_session_summary_response(history_for_summary, session_id)
            
            # Add to session history
            session_manager.add_message(
                session_id,
                'assistant',
                response.response,
                metadata={'type': 'session_summary'}
            )
            return response
        
        # STEP 3: Build context summary for better understanding
        context_summary = _build_context_summary(conversation_history, request.chatbot_type)
        if context_summary:
            logger.info(f"📚 Context summary: {context_summary[:100]}...")
        
        # STEP 4: Route to appropriate service (with conversation history passed)
        response = None
        
        if request.chatbot_type == ChatbotType.KNOWLEDGE_BASE:
            if agentic_service and settings.AGENTIC_MODE_ENABLED:
                logger.info("🤖 Using Agentic AI (multi-agent verification system)")
                response = kb_service.process_query(request)
            else:
                logger.info("📚 Using traditional Knowledge Base service")
                response = kb_service.process_query(request)
                
        elif request.chatbot_type == ChatbotType.SQL_ASSISTANT:
            response = sql_service.process_query(request)
            
        elif request.chatbot_type == ChatbotType.DIAGNOSTIC:
            response = diagnostic_service.process_query(request)
            
        else:
            raise HTTPException(status_code=400, detail=f"Invalid chatbot type: {request.chatbot_type}")
        
        # STEP 5: Update session with response
        if response:
            session_manager.add_message(
                session_id,
                'assistant',
                response.response,
                metadata={
                    'confidence': response.confidence_score,
                    'chatbot_type': request.chatbot_type,
                    'has_sources': len(response.sources) > 0 if response.sources else False
                }
            )
            
            # Ensure response has session ID
            response.session_id = session_id

            # Log Knowledge Base chats to MySQL history
            if request.chatbot_type == ChatbotType.KNOWLEDGE_BASE and chat_history_service:
                try:
                    response_time_ms = int((time.time() - start_time) * 1000)
                    chat_history_service.log_chat_interaction(
                        session_id=session_id,
                        chatbot_type=str(request.chatbot_type),
                        user_query=request.message,
                        assistant_response=response.response,
                        confidence_score=response.confidence_score or 0.0,
                        response_time_ms=response_time_ms
                    )
                except Exception as e:
                    logger.warning(f"⚠️ Failed to log Knowledge Base chat: {e}")
        
        logger.info(f"✅ Chat response generated: confidence={response.confidence_score:.2f}, session={session_id}")
        return response
        
    except Exception as e:
        logger.error(f"❌ Error in chat endpoint: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


def _is_session_query(message: str) -> bool:
    """
    Detect if user is asking about conversation history/session
    Examples:
    - 'What have we discussed?'
    - 'What did I ask earlier?'
    - 'Summarize our conversation'
    - 'What topics have we covered?'
    """
    message_lower = message.lower().strip()
    
    session_patterns = [
        'what have we discussed',
        'what did we discuss',
        'what have we talked',
        'what did we talk',
        'summarize our conversation',
        'summarize the conversation',
        'summarize our chat',
        'what did i ask',
        'what have i asked',
        'recap our conversation',
        'recap the conversation',
        'what topics have we',
        'topics we discussed',
        'what questions have i',
        'our discussion so far',
        'conversation so far',
        'what was discussed',
        'what we covered',
        'what have we covered',
        'tell me what we discussed',
        'what we have discussed',
        'tell me what we have discussed',
        'remind me what we talked',
        'previous questions',
        'earlier in the conversation',
        'before in this chat',
        'history of our chat',
        'chat history',
        'session history',
        'conversation history',
        'what is the context',
        'our context',
        'refresh my memory',
        'what was my question',
    ]
    
    for pattern in session_patterns:
        if pattern in message_lower:
            return True
    
    return False


def _generate_session_summary_response(conversation_history: List[Dict], session_id: str) -> ChatResponse:
    """
    Generate a comprehensive summary of the conversation history
    """
    if not conversation_history or len(conversation_history) < 2:
        summary = """## Conversation Summary

We haven't discussed anything yet in this session! This appears to be the start of our conversation.

**What would you like to talk about?**
- Ask about NEO system documentation
- Get help with SQL queries
- Troubleshoot bot or station issues
"""
        return ChatResponse(
            response=summary,
            chatbot_type=ChatbotType.KNOWLEDGE_BASE,
            session_id=session_id,
            sources=[],
            confidence_score=0.95,
            suggested_actions=["Ask about NEO", "SQL Assistant", "Diagnostics"]
        )
    
    # Build comprehensive summary with deduplication
    user_questions = []
    assistant_responses = []
    seen_user_questions = set()  # Track unique questions to avoid duplicates
    
    for msg in conversation_history:
        role = msg.get('role', '')
        content = msg.get('content', '').strip()
        
        # Skip empty messages or system messages
        if not content or role == 'system':
            continue
            
        if role == 'user':
            # Normalize and check for duplicates
            content_lower = content.lower()
            if content_lower not in seen_user_questions:
                seen_user_questions.add(content_lower)
                # Keep full question text, but limit extremely long ones
                if len(content) > 500:
                    summary_text = content[:500] + '... (truncated for length)'
                else:
                    summary_text = content
                user_questions.append(summary_text)
                
        elif role == 'assistant':
            # Get first meaningful sentence or up to 300 chars
            # Skip if it's a meta response (like session summaries)
            metadata = msg.get('metadata', {})
            if metadata.get('type') == 'session_summary':
                continue
                
            # For assistant responses, provide meaningful excerpts
            if len(content) > 300:
                # Try to find first complete sentence
                first_sentence_end = content.find('. ')
                if first_sentence_end > 0 and first_sentence_end < 250:
                    summary_text = content[:first_sentence_end + 1]
                else:
                    # Just take first 300 chars and add ellipsis at word boundary
                    last_space = content[:300].rfind(' ')
                    if last_space > 200:
                        summary_text = content[:last_space] + '...'
                    else:
                        summary_text = content[:300] + '...'
            else:
                summary_text = content
                
            assistant_responses.append(summary_text)
    
    # Build formatted summary without emojis
    summary_parts = ["## Conversation Summary\n"]
    summary_parts.append(f"**Session ID:** `{session_id}`\n")
    summary_parts.append(f"**Total Exchanges:** {len(user_questions)}\n\n")
    
    if user_questions:
        summary_parts.append("### Your Questions:\n")
        for i, q in enumerate(user_questions, 1):
            summary_parts.append(f"{i}. {q}\n\n")
    
    if assistant_responses:
        summary_parts.append("### Key Information Provided:\n")
        for i, response in enumerate(assistant_responses, 1):
            summary_parts.append(f"**Response {i}:** {response}\n\n")
    
    summary_parts.append("---\n\n**Would you like me to elaborate on any specific point or explore a new topic?**")
    
    return ChatResponse(
        response="".join(summary_parts),
        chatbot_type=ChatbotType.KNOWLEDGE_BASE,
        session_id=session_id,
        sources=[],
        confidence_score=0.95,
        suggested_actions=["Continue previous topic", "Ask new question", "View more details"]
    )


def _build_context_summary(conversation_history: List[Dict], chatbot_type: str) -> str:
    """
    Build a context summary from conversation history
    """
    if not conversation_history or len(conversation_history) < 2:
        return ""
    
    # Get last few messages (excluding the current one)
    recent_messages = conversation_history[:-1][-4:]  # Last 4 messages
    
    summary_parts = []
    for msg in recent_messages:
        role = msg.get('role', 'unknown').upper()
        content = msg.get('content', '')
        
        # Truncate long content
        if len(content) > 100:
            content = content[:100] + "..."
        
        summary_parts.append(f"{role}: {content}")
    
    return "\n".join(summary_parts)



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
        
        # Get active sessions count from session manager
        active_sessions = session_manager.list_active_sessions()
        
        return {
            "knowledge_base": kb_stats,
            "sql_assistant": sql_stats,
            "diagnostic": diag_stats,
            "total_sessions": len(active_sessions),
            "all_sessions": len(session_manager.sessions)
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
        # Use session manager to delete session
        if session_manager.delete_session(session_id):
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
        # Get session from unified session manager
        session = session_manager.get_session(session_id)
        
        if session:
            conversation_history = session_manager.get_conversation_history(session_id)
            return {
                "session_id": session_id,
                "messages": conversation_history,
                "message_count": len(conversation_history),
                "session_type": session.get('type', 'general'),
                "created_at": session.get('created_at'),
                "last_updated": session.get('last_updated')
            }
        else:
            # Session not found - return empty
            logger.warning(f"⚠️ Session not found: {session_id}")
            return {
                "session_id": session_id,
                "messages": [],
                "message_count": 0
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
# SEMI-AUTOMATED DIAGNOSTIC ENDPOINTS (DEPRECATED)
# ============================================================
# NOTE: These endpoints have been replaced with the new SOP-based workflow.
# Use the new endpoints at /api/diagnostic-support/sop/* instead:
#   POST /api/diagnostic-support/sop/start - Start SOP workflow
#   POST /api/diagnostic-support/sop/select - Select problem from candidates
#   POST /api/diagnostic-support/sop/step-input - Submit step observation
#   POST /api/diagnostic-support/sop/resolved - Mark as resolved
#   POST /api/diagnostic-support/sop/not-resolved - Continue to next step
#   GET  /api/diagnostic-support/sop/session/{session_id} - Get session
#   DELETE /api/diagnostic-support/sop/session/{session_id} - Reset session
#   GET  /api/diagnostic-support/sop/problems - Get all SOP problems


@router.post("/diagnostic/start")
async def start_diagnosis_deprecated(problem_description: str, issue_type: str = None):
    """
    DEPRECATED - Use /api/diagnostic-support/sop/start instead.
    
    This endpoint is deprecated and will be removed in a future version.
    Please migrate to the new SOP-based workflow endpoints.
    """
    raise HTTPException(
        status_code=410,
        detail="This endpoint is deprecated. Use POST /api/diagnostic-support/sop/start instead."
    )


@router.post("/diagnostic/classify")
async def classify_diagnostic_issue_deprecated(problem_description: str):
    """
    DEPRECATED - Classification is now handled automatically in the new SOP workflow.
    """
    raise HTTPException(
        status_code=410,
        detail="This endpoint is deprecated. The new SOP workflow handles classification automatically."
    )


@router.post("/diagnostic/audit-sql")
async def audit_with_sql_deprecated(sql_query: str):
    """
    DEPRECATED - SQL execution is now automatic in the new SOP workflow.
    """
    raise HTTPException(
        status_code=410,
        detail="This endpoint is deprecated. SQL queries are executed automatically in the new SOP workflow."
    )


@router.post("/diagnostic/analyze-results")
async def analyze_audit_results_deprecated(case: Dict[str, Any], sql_results: Dict[str, Any], session_id: str = None):
    """
    DEPRECATED - Result analysis is now integrated in the SOP workflow.
    """
    raise HTTPException(
        status_code=410,
        detail="This endpoint is deprecated. Use the new SOP workflow at /api/diagnostic-support/sop/*"
    )


@router.post("/diagnostic/feedback")
async def handle_diagnostic_feedback_deprecated(
    session_id: str,
    is_correct: bool,
    user_comment: str = None
):
    """
    DEPRECATED - Use /api/diagnostic-support/sop/resolved or /api/diagnostic-support/sop/not-resolved instead.
    """
    raise HTTPException(
        status_code=410,
        detail="This endpoint is deprecated. Use POST /api/diagnostic-support/sop/resolved or /api/diagnostic-support/sop/not-resolved instead."
    )


@router.post("/diagnostic/followup")
async def handle_followup_question_deprecated(session_id: str, question: str):
    """
    DEPRECATED - Follow-up is now handled through the step-input endpoint.
    """
    raise HTTPException(
        status_code=410,
        detail="This endpoint is deprecated. Use POST /api/diagnostic-support/sop/step-input instead."
    )


@router.get("/diagnostic/session/{session_id}")
async def get_session_info_deprecated(session_id: str):
    """
    DEPRECATED - Use GET /api/diagnostic-support/sop/session/{session_id} instead.
    """
    raise HTTPException(
        status_code=410,
        detail="This endpoint is deprecated. Use GET /api/diagnostic-support/sop/session/{session_id} instead."
    )


@router.post("/diagnostic/summary")
async def get_diagnostic_summary_deprecated(session_id: str):
    """
    DEPRECATED - Session details available via GET /api/diagnostic-support/sop/session/{session_id}
    """
    raise HTTPException(
        status_code=410,
        detail="This endpoint is deprecated. Use GET /api/diagnostic-support/sop/session/{session_id} instead."
    )


# ========================================
# UNIFIED SESSION MANAGEMENT ENDPOINTS
# ========================================

@router.post("/session/new")
async def create_new_session(session_type: str = "general"):
    """
    Create a new conversation session
    
    Args:
        session_type: Type of session (knowledge_base, sql_assistant, diagnostic, etc.)
    
    Returns:
        Session ID and details
    """
    try:
        # Map session type string to SessionType enum
        type_mapping = {
            "knowledge_base": SessionType.KNOWLEDGE_BASE,
            "sql_assistant": SessionType.SQL_ASSISTANT,
            "diagnostic": SessionType.DIAGNOSTIC,
            "semi_auto_diagnostic": SessionType.SEMI_AUTO_DIAGNOSTIC,
            "intelligent_diagnostic": SessionType.INTELLIGENT_DIAGNOSTIC,
            "agentic": SessionType.AGENTIC,
            "general": SessionType.GENERAL
        }
        
        session_type_enum = type_mapping.get(session_type.lower(), SessionType.GENERAL)
        session_id = session_manager.create_session(session_type=session_type_enum)
        
        logger.info(f"🆕 Created new session: {session_id} (type: {session_type})")
        
        return {
            "session_id": session_id,
            "session_type": session_type,
            "created_at": datetime.now().isoformat(),
            "status": "active"
        }
    except Exception as e:
        logger.error(f"❌ Error creating session: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/session/{session_id}")
async def get_session(session_id: str):
    """
    Get session details and conversation history
    
    Args:
        session_id: Session identifier
    
    Returns:
        Complete session data
    """
    try:
        session = session_manager.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        return session
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting session: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/session/{session_id}/history")
async def get_unified_session_history(session_id: str, last_n: int = None):
    """
    Get conversation history for a session
    
    Args:
        session_id: Session identifier
        last_n: Optional limit to last N messages
    
    Returns:
        List of conversation messages
    """
    try:
        history = session_manager.get_conversation_history(session_id, last_n=last_n)
        
        return {
            "session_id": session_id,
            "message_count": len(history),
            "messages": history
        }
    except Exception as e:
        logger.error(f"❌ Error getting history: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/session/{session_id}")
async def delete_unified_session(session_id: str):
    """
    Delete a session permanently
    
    Args:
        session_id: Session identifier
    
    Returns:
        Deletion confirmation
    """
    try:
        deleted = session_manager.delete_session(session_id)
        
        if not deleted:
            raise HTTPException(status_code=404, detail="Session not found")
        
        logger.info(f"🗑️ Deleted session: {session_id}")
        return {
            "status": "success",
            "message": f"Session {session_id} deleted successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error deleting session: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/session/{session_id}/end")
async def end_session(session_id: str):
    """
    Mark session as ended (inactive but not deleted)
    
    Args:
        session_id: Session identifier
    
    Returns:
        Status confirmation
    """
    try:
        ended = session_manager.end_session(session_id)
        
        if not ended:
            raise HTTPException(status_code=404, detail="Session not found")
        
        logger.info(f"🔚 Ended session: {session_id}")
        return {
            "status": "success",
            "message": f"Session {session_id} ended",
            "session_id": session_id
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error ending session: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sessions")
async def list_active_sessions(session_type: str = None):
    """
    List all active sessions, optionally filtered by type
    
    Args:
        session_type: Optional filter by type
    
    Returns:
        List of active sessions
    """
    try:
        # Map session type if provided
        type_enum = None
        if session_type:
            type_mapping = {
                "knowledge_base": SessionType.KNOWLEDGE_BASE,
                "sql_assistant": SessionType.SQL_ASSISTANT,
                "diagnostic": SessionType.DIAGNOSTIC,
                "semi_auto_diagnostic": SessionType.SEMI_AUTO_DIAGNOSTIC,
                "intelligent_diagnostic": SessionType.INTELLIGENT_DIAGNOSTIC,
                "agentic": SessionType.AGENTIC,
                "general": SessionType.GENERAL
            }
            type_enum = type_mapping.get(session_type.lower())
        
        sessions = session_manager.list_active_sessions(session_type=type_enum)
        
        return {
            "count": len(sessions),
            "sessions": sessions
        }
    except Exception as e:
        logger.error(f"❌ Error listing sessions: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sessions/stats")
async def get_session_stats():
    """
    Get session statistics
    
    Returns:
        Session statistics
    """
    try:
        stats = session_manager.get_total_sessions()
        
        return {
            "statistics": stats,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"❌ Error getting session stats: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))
