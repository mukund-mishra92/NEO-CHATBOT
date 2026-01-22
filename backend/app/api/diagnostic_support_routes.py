"""
Diagnostic Support API Endpoints
Provides troubleshooting and diagnostic support for NEO system issues
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from ..services.diagnostic import DiagnosticSupportService
import logging

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/diagnostic-support", tags=["Diagnostic Support"])

# Initialize diagnostic service
diagnostic_service = DiagnosticSupportService()


class DiagnosticQuery(BaseModel):
    """Request model for diagnostic queries"""
    query: str = Field(..., description="Problem description or keywords")
    issue_type: Optional[str] = Field(None, description="Filter by type: BOT_LEVEL or STATION_LEVEL")


class SymptomAnalysisRequest(BaseModel):
    """Request model for multi-symptom analysis"""
    symptoms: List[str] = Field(..., description="List of observed symptoms")


class DiagnosticResponse(BaseModel):
    """Response model for diagnostic results"""
    success: bool
    message: str
    data: Dict[str, Any]


class StartSessionRequest(BaseModel):
    """Request model for starting a diagnostic session"""
    issue_id: int = Field(..., description="Issue ID to diagnose")
    issue_type: str = Field(default="bot_level", description="Type: bot_level or station_level")


class StepFeedbackRequest(BaseModel):
    """Request model for submitting step feedback"""
    session_id: str = Field(..., description="Diagnostic session ID")
    is_fixed: bool = Field(..., description="Whether the issue is fixed after this step")
    feedback_notes: str = Field(default="", description="Optional feedback notes")


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

# ========== Step-by-Step Diagnostic Workflow Endpoints ==========

@router.post("/session/start", response_model=DiagnosticResponse)
async def start_diagnostic_session(request: StartSessionRequest):
    """
    Start a step-by-step diagnostic session for an issue
    
    **Parameters:**
    - **issue_id**: ID of the issue to diagnose
    - **issue_type**: Type of issue (bot_level or station_level)
    
    **Returns:**
    - Session ID and first diagnostic step with SQL query (if available)
    
    **Workflow:**
    1. Parses solution into individual steps
    2. Parses SQL queries (split by semicolon)
    3. Returns first step for execution
    4. User executes SQL and provides feedback
    5. If not fixed, moves to next step
    """
    try:
        result = diagnostic_service.start_diagnostic_session(
            issue_id=request.issue_id,
            issue_type=request.issue_type
        )
        
        if not result.get('success'):
            raise HTTPException(status_code=404, detail=result.get('error'))
        
        return DiagnosticResponse(
            success=True,
            message=f"Diagnostic session started. Step 1 of {result.get('total_steps')}",
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error starting diagnostic session: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/session/{session_id}/status", response_model=DiagnosticResponse)
async def get_session_status(session_id: str):
    """
    Get current status of a diagnostic session
    
    **Parameters:**
    - **session_id**: Session ID from start_diagnostic_session
    
    **Returns:**
    - Current step information, session history, and status
    """
    try:
        result = diagnostic_service.get_session_status(session_id)
        
        if not result.get('success'):
            raise HTTPException(status_code=404, detail=result.get('error'))
        
        status = result.get('status', 'unknown')
        if status == 'completed':
            message = "Session completed - all steps finished"
        elif status == 'resolved':
            message = "Session completed - issue resolved"
        elif status == 'unresolved':
            message = "Session completed - issue not resolved"
        else:
            current = result.get('current_step', {})
            message = f"Step {current.get('step_number')} of {current.get('total_steps')}"
        
        return DiagnosticResponse(
            success=True,
            message=message,
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting session status: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/session/feedback", response_model=DiagnosticResponse)
async def submit_step_feedback(request: StepFeedbackRequest):
    """
    Submit feedback for current step and get next step (if not fixed)
    
    **Parameters:**
    - **session_id**: Session ID
    - **is_fixed**: True if issue is resolved, False to continue
    - **feedback_notes**: Optional notes about the step execution
    
    **Returns:**
    - Next step (if issue not fixed) or completion status (if fixed or no more steps)
    
    **Example Usage:**
    ```
    1. Execute SQL query from current step
    2. Check if issue is fixed
    3. Submit feedback: {"is_fixed": false, "feedback_notes": "Still seeing error"}
    4. Receive next step and repeat
    ```
    """
    try:
        result = diagnostic_service.submit_step_feedback(
            session_id=request.session_id,
            is_fixed=request.is_fixed,
            feedback_notes=request.feedback_notes
        )
        
        if not result.get('success'):
            raise HTTPException(status_code=404, detail=result.get('error'))
        
        return DiagnosticResponse(
            success=True,
            message=result.get('message', 'Feedback submitted'),
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error submitting feedback: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/session/{session_id}", response_model=DiagnosticResponse)
async def close_diagnostic_session(session_id: str):
    """
    Close a diagnostic session
    
    **Parameters:**
    - **session_id**: Session ID to close
    
    **Returns:**
    - Final session status and history
    """
    try:
        result = diagnostic_service.close_session(session_id)
        
        if not result.get('success'):
            raise HTTPException(status_code=404, detail=result.get('error'))
        
        return DiagnosticResponse(
            success=True,
            message="Session closed",
            data=result
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error closing session: {e}")
        raise HTTPException(status_code=500, detail=str(e))