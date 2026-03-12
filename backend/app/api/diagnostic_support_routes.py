"""
Diagnostic Support API Endpoints
Provides troubleshooting and diagnostic support for NEO system issues
Includes Interactive Diagnostic Chat for step-by-step guided resolution
Includes Semi-Auto SOP Diagnostic Workflow (based on semi-auto-diag.py)
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from app.services.diagnostic.diagnostic_support_service import DiagnosticSupportService
from app.services.semi_diagnostic.interactive_diagnostic_service import get_interactive_diagnostic_service
from app.services.semi_diagnostic.semi_auto_sop_service import get_sop_service
import logging

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/diagnostic-support", tags=["Diagnostic Support"])

# Initialize diagnostic services
diagnostic_service = DiagnosticSupportService()
interactive_service = get_interactive_diagnostic_service()
sop_service = get_sop_service()


class DiagnosticQuery(BaseModel):
    """Request model for diagnostic queries"""
    query: str = Field(..., description="Problem description or keywords")
    issue_type: Optional[str] = Field(None, description="Filter by type: BOT_LEVEL or STATION_LEVEL")


class InteractiveChatRequest(BaseModel):
    """Request model for interactive diagnostic chat"""
    message: str = Field(..., description="User's message")
    session_id: Optional[str] = Field(None, description="Existing session ID for continuation")


class SOPStartRequest(BaseModel):
    """Request model for starting SOP workflow"""
    problem_description: str = Field(..., description="User's problem description")
    session_id: Optional[str] = Field(None, description="Optional existing session ID to continue conversation")


class SOPSelectRequest(BaseModel):
    """Request model for selecting SOP problem"""
    session_id: str = Field(..., description="Session ID")
    s_no: float = Field(..., description="S.No. of selected problem")


class SOPStepInputRequest(BaseModel):
    """Request model for submitting step observation"""
    session_id: str = Field(..., description="Session ID")
    user_input: str = Field(..., description="User observation/output")


class SOPResolutionRequest(BaseModel):
    """Request model for resolution status"""
    session_id: str = Field(..., description="Session ID")


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
# SEMI-AUTO SOP DIAGNOSTIC WORKFLOW ENDPOINTS
# Based on semi-auto-diag.py functionality
# ========================================

@router.post("/sop/start", response_model=DiagnosticResponse)
async def start_sop_workflow(request: SOPStartRequest):
    """
    🔧 Start Semi-Auto SOP Diagnostic Workflow
    
    This endpoint initiates a step-by-step SOP diagnostic workflow.
    Features:
    - TF-IDF based problem matching from SOP Excel
    - Priority-ordered step execution
    - Automatic SQL query execution
    - Interactive resolution confirmation
    
    **Parameters:**
    - **problem_description**: User's problem description
    
    **Returns:**
    - Session with matched SOP or candidates for selection
    """
    try:
        result = sop_service.start_workflow(
            user_query=request.problem_description,
            session_id=request.session_id  # Pass existing session if provided
        )
        
        if not result.get("success", False):
            raise HTTPException(status_code=400, detail=result.get("error", "Failed to start workflow"))
        
        return DiagnosticResponse(
            success=True,
            message=result.get("message", "SOP workflow started"),
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error starting SOP workflow: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sop/select", response_model=DiagnosticResponse)
async def select_sop_problem(request: SOPSelectRequest):
    """
    Select a specific SOP problem from candidates
    
    When match confidence is low, user selects the correct problem.
    
    **Parameters:**
    - **session_id**: Session ID from start endpoint
    - **s_no**: S.No. of selected problem
    
    **Returns:**
    - Updated session with first step execution
    """
    try:
        result = sop_service.select_problem(request.session_id, request.s_no)
        
        if not result.get("success", False):
            raise HTTPException(status_code=400, detail=result.get("error", "Failed to select problem"))
        
        return DiagnosticResponse(
            success=True,
            message="Problem selected, workflow started",
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error selecting SOP problem: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sop/step-input", response_model=DiagnosticResponse)
async def submit_sop_step_input(request: SOPStepInputRequest):
    """
    Submit observation/output for a manual SOP step
    
    For non-SQL steps, user provides their observation after performing the action.
    
    **Parameters:**
    - **session_id**: Session ID
    - **user_input**: User's observation or command output
    
    **Returns:**
    - Updated session awaiting resolution confirmation
    """
    try:
        result = sop_service.submit_step_input(request.session_id, request.user_input)
        
        if not result.get("success", False):
            raise HTTPException(status_code=400, detail=result.get("error", "Failed to submit input"))
        
        return DiagnosticResponse(
            success=True,
            message="Observation recorded",
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error submitting step input: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sop/resolved", response_model=DiagnosticResponse)
async def mark_sop_resolved(request: SOPResolutionRequest):
    """
    Mark the SOP workflow as resolved
    
    User confirms that the issue has been resolved.
    
    **Parameters:**
    - **session_id**: Session ID
    
    **Returns:**
    - Final session state marked as resolved
    """
    try:
        result = sop_service.mark_resolved(request.session_id)
        
        if not result.get("success", False):
            raise HTTPException(status_code=400, detail=result.get("error", "Failed to mark resolved"))
        
        return DiagnosticResponse(
            success=True,
            message="Issue marked as resolved",
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error marking resolved: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sop/not-resolved", response_model=DiagnosticResponse)
async def mark_sop_not_resolved(request: SOPResolutionRequest):
    """
    Mark step as not resolved and continue to next step
    
    User indicates the current step did not resolve the issue.
    
    **Parameters:**
    - **session_id**: Session ID
    
    **Returns:**
    - Updated session with next step execution
    """
    try:
        result = sop_service.mark_not_resolved(request.session_id)
        
        if not result.get("success", False):
            raise HTTPException(status_code=400, detail=result.get("error", "Failed to continue"))
        
        return DiagnosticResponse(
            success=True,
            message="Continuing to next step",
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error marking not resolved: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sop/session/{session_id}", response_model=DiagnosticResponse)
async def get_sop_session(session_id: str):
    """
    Get SOP workflow session details
    
    **Parameters:**
    - **session_id**: Session ID
    
    **Returns:**
    - Full session state including messages and progress
    """
    try:
        session = sop_service.get_session(session_id)
        
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        return DiagnosticResponse(
            success=True,
            message="Session retrieved",
            data=session
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting SOP session: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/sop/session/{session_id}", response_model=DiagnosticResponse)
async def reset_sop_session(session_id: str):
    """
    Reset/delete an SOP workflow session
    
    **Parameters:**
    - **session_id**: Session ID
    
    **Returns:**
    - Confirmation of reset
    """
    try:
        result = sop_service.reset_session(session_id)
        
        return DiagnosticResponse(
            success=True,
            message="Session reset",
            data=result
        )
    
    except Exception as e:
        logger.error(f"Error resetting SOP session: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sop/problems", response_model=DiagnosticResponse)
async def get_all_sop_problems():
    """
    Get all SOP problem statements
    
    Useful for manual problem selection or browsing.
    
    **Returns:**
    - List of all problem statements with S.No. and Impact
    """
    try:
        problems = sop_service.get_all_problems()
        
        return DiagnosticResponse(
            success=True,
            message=f"Retrieved {len(problems)} problems",
            data={"problems": problems, "count": len(problems)}
        )
    
    except Exception as e:
        logger.error(f"Error getting SOP problems: {e}", exc_info=True)
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
