"""
Diagnostic Support API Endpoints
Provides troubleshooting and diagnostic support for NEO system issues
Includes Interactive Diagnostic Chat for step-by-step guided resolution
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from app.services.diagnostic_support_service import DiagnosticSupportService
from app.services.interactive_diagnostic_service import get_interactive_diagnostic_service
import logging

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/diagnostic-support", tags=["Diagnostic Support"])

# Initialize diagnostic services
diagnostic_service = DiagnosticSupportService()
interactive_service = get_interactive_diagnostic_service()


class DiagnosticQuery(BaseModel):
    """Request model for diagnostic queries"""
    query: str = Field(..., description="Problem description or keywords")
    issue_type: Optional[str] = Field(None, description="Filter by type: BOT_LEVEL or STATION_LEVEL")


class InteractiveChatRequest(BaseModel):
    """Request model for interactive diagnostic chat"""
    message: str = Field(..., description="User's message")
    session_id: Optional[str] = Field(None, description="Existing session ID for continuation")


class SymptomAnalysisRequest(BaseModel):
    """Request model for multi-symptom analysis"""
    symptoms: List[str] = Field(..., description="List of observed symptoms")


class DiagnosticResponse(BaseModel):
    """Response model for diagnostic results"""
    success: bool
    message: str
    data: Dict[str, Any]


# ========================================
# INTERACTIVE DIAGNOSTIC CHAT ENDPOINTS
# ========================================

@router.post("/chat", response_model=DiagnosticResponse)
async def interactive_diagnostic_chat(request: InteractiveChatRequest):
    """
    🤖 Interactive Diagnostic Chat - ChatGPT-like troubleshooting
    
    This endpoint provides a conversational interface for diagnosing issues.
    Features:
    - Asks clarification questions when problem is ambiguous
    - Walks through solutions step-by-step
    - Asks for feedback after each step
    - Remembers conversation context
    - Tries alternative solutions if needed
    
    **Parameters:**
    - **message**: User's message (problem description, answer to question, or feedback)
    - **session_id**: Optional - provide to continue an existing conversation
    
    **Returns:**
    - Conversational response with state information
    - Session ID for continuing the conversation
    """
    try:
        result = interactive_service.chat(
            message=request.message,
            session_id=request.session_id
        )
        
        return DiagnosticResponse(
            success=True,
            message=result.get('response', 'Processing...'),
            data=result
        )
    
    except Exception as e:
        logger.error(f"Error in interactive chat: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/chat/session/{session_id}", response_model=DiagnosticResponse)
async def get_chat_session(session_id: str):
    """
    Get details of an interactive diagnostic session
    
    **Parameters:**
    - **session_id**: Session ID to retrieve
    
    **Returns:**
    - Session summary including state, progress, and conversation history
    """
    try:
        summary = interactive_service.get_session_summary(session_id)
        
        if 'error' in summary:
            raise HTTPException(status_code=404, detail=summary['error'])
        
        return DiagnosticResponse(
            success=True,
            message="Session retrieved",
            data=summary
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting session: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/chat/session/{session_id}/history", response_model=DiagnosticResponse)
async def get_chat_history(session_id: str):
    """
    Get full conversation history for a session
    
    **Parameters:**
    - **session_id**: Session ID to retrieve history for
    
    **Returns:**
    - Complete conversation history with timestamps
    """
    try:
        session = interactive_service.get_session(session_id)
        
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        return DiagnosticResponse(
            success=True,
            message="History retrieved",
            data={
                'session_id': session_id,
                'conversation_history': session.conversation_history,
                'message_count': len(session.conversation_history)
            }
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting history: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ========================================
# ORIGINAL DIAGNOSTIC ENDPOINTS
# ========================================


@router.post("/search", response_model=DiagnosticResponse)
async def search_issues(query_request: DiagnosticQuery):
    """
    Search for issues matching the query
    
    **Parameters:**
    - **query**: Problem description or keywords to search
    - **issue_type**: Optional filter (BOT_LEVEL, STATION_LEVEL, or None for all)
    
    **Returns:**
    - List of matching issues with relevance scores
    """
    try:
        results = diagnostic_service.search_issue(
            query=query_request.query,
            issue_type=query_request.issue_type
        )
        
        return DiagnosticResponse(
            success=True,
            message=f"Found {len(results)} matching issues",
            data={
                "query": query_request.query,
                "results_count": len(results),
                "results": results
            }
        )
    
    except Exception as e:
        logger.error(f"Error searching issues: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/diagnose", response_model=DiagnosticResponse)
async def diagnose_symptoms(request: SymptomAnalysisRequest):
    """
    Get diagnostic recommendations based on multiple symptoms
    
    **Parameters:**
    - **symptoms**: List of observed symptoms/issues
    
    **Returns:**
    - Comprehensive diagnostic report with top recommendations
    """
    try:
        recommendations = diagnostic_service.get_diagnostic_recommendations(
            symptoms=request.symptoms
        )
        
        return DiagnosticResponse(
            success=True,
            message="Diagnostic analysis complete",
            data=recommendations
        )
    
    except Exception as e:
        logger.error(f"Error diagnosing symptoms: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/issue/{issue_type}/{issue_id}", response_model=DiagnosticResponse)
async def get_issue_details(
    issue_type: str,
    issue_id: int
):
    """
    Get detailed information about a specific issue
    
    **Parameters:**
    - **issue_type**: Type of issue (BOT_LEVEL or STATION_LEVEL)
    - **issue_id**: Issue ID number
    
    **Returns:**
    - Detailed issue information with solution steps
    """
    try:
        if issue_type not in ['BOT_LEVEL', 'STATION_LEVEL']:
            raise HTTPException(
                status_code=400,
                detail="Invalid issue_type. Must be BOT_LEVEL or STATION_LEVEL"
            )
        
        issue = diagnostic_service.get_issue_by_id(issue_id, issue_type)
        
        if not issue:
            raise HTTPException(
                status_code=404,
                detail=f"Issue {issue_id} not found in {issue_type}"
            )
        
        # Format as readable report
        formatted_report = diagnostic_service.format_diagnostic_report(issue)
        
        return DiagnosticResponse(
            success=True,
            message="Issue details retrieved",
            data={
                "issue": issue,
                "formatted_report": formatted_report
            }
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting issue details: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/issues/all", response_model=DiagnosticResponse)
async def get_all_issues(
    severity: Optional[str] = Query(None, description="Filter by severity: High, Medium, or Low")
):
    """
    Get all known issues, optionally filtered by severity
    
    **Parameters:**
    - **severity**: Optional severity filter (High, Medium, Low)
    
    **Returns:**
    - Complete list of bot-level and station-level issues
    """
    try:
        if severity and severity not in ['High', 'Medium', 'Low']:
            raise HTTPException(
                status_code=400,
                detail="Invalid severity. Must be High, Medium, or Low"
            )
        
        issues = diagnostic_service.get_all_issues(severity=severity)
        
        return DiagnosticResponse(
            success=True,
            message=f"Retrieved {issues['total_count']} issues",
            data=issues
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting all issues: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sql-solutions", response_model=DiagnosticResponse)
async def get_sql_solutions(
    problem: str = Query(..., description="Problem keywords to search")
):
    """
    Get issues that have SQL query solutions
    
    **Parameters:**
    - **problem**: Problem keywords to search
    
    **Returns:**
    - List of issues with SQL query solutions
    """
    try:
        solutions = diagnostic_service.get_sql_solutions(problem)
        
        return DiagnosticResponse(
            success=True,
            message=f"Found {len(solutions)} SQL solutions",
            data={
                "problem_query": problem,
                "solutions_count": len(solutions),
                "solutions": solutions
            }
        )
    
    except Exception as e:
        logger.error(f"Error getting SQL solutions: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/statistics", response_model=DiagnosticResponse)
async def get_statistics():
    """
    Get diagnostic support system statistics
    
    **Returns:**
    - Statistics about loaded issues, severity breakdown, etc.
    """
    try:
        stats = diagnostic_service.get_statistics()
        
        return DiagnosticResponse(
            success=True,
            message="Statistics retrieved",
            data=stats
        )
    
    except Exception as e:
        logger.error(f"Error getting statistics: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/health", response_model=DiagnosticResponse)
async def health_check():
    """
    Health check endpoint for diagnostic support service
    
    **Returns:**
    - Service health status
    """
    try:
        stats = diagnostic_service.get_statistics()
        
        return DiagnosticResponse(
            success=True,
            message="Diagnostic Support Service is healthy",
            data={
                "status": "healthy",
                "issues_loaded": stats['total_issues'],
                "service_version": "1.0.0"
            }
        )
    
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
