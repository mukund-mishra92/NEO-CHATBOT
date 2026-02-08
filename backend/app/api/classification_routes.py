"""
API endpoints for query classification and management
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
from pathlib import Path
import logging
import json

from app.core.config import settings

logger = logging.getLogger(__name__)

# Create router
router = APIRouter(prefix="/api/classification", tags=["classification"])

# Initialize classification service (will be done in main.py)
classification_service = None


def init_classification_service(service):
    """Initialize the classification service"""
    global classification_service
    classification_service = service


# ========================================
# REQUEST/RESPONSE MODELS
# ========================================

class ClassifyQueryRequest(BaseModel):
    query_id: str = Field(..., description="ID of query to classify")
    classification: str = Field(..., description="Classification: correct, incorrect, or needs_review")
    notes: Optional[str] = Field(None, description="Optional notes about classification")
    corrected_sql: Optional[str] = Field(None, description="Corrected SQL if incorrect")


class UpdateQueryRequest(BaseModel):
    query_id: str = Field(..., description="ID of query to update")
    user_query: Optional[str] = Field(None, description="Updated user query text")
    generated_sql: Optional[str] = Field(None, description="Updated SQL query")
    notes: Optional[str] = Field(None, description="Update notes")


class QueryResponse(BaseModel):
    query_id: str
    timestamp: str
    user_query: str
    generated_sql: str
    classification: str
    rows_returned: Optional[int] = None
    confidence: float
    tables_used: List[str]
    execution_status: Optional[str] = None
    session_id: Optional[str] = None
    metadata: Optional[dict] = None


class StatsResponse(BaseModel):
    total_queries: int
    correct: int
    incorrect: int
    needs_review: int
    unclassified: int
    accuracy: float


# ========================================
# ENDPOINTS
# ========================================

@router.get("/unclassified", response_model=List[QueryResponse])
async def get_unclassified_queries(
    limit: int = Query(50, description="Maximum number of queries to return", ge=1, le=200)
):
    """
    Get queries awaiting manual classification
    
    Returns list of queries that need review
    """
    try:
        if not classification_service:
            raise HTTPException(status_code=500, detail="Classification service not initialized")
        
        queries = classification_service.get_unclassified_queries(limit=limit)
        
        return [
            QueryResponse(
                query_id=q['query_id'],
                timestamp=q['timestamp'],
                user_query=q['user_query'],
                generated_sql=q['generated_sql'],
                classification=q['classification'],
                rows_returned=q['rows_returned'],
                confidence=q['confidence'],
                tables_used=q['tables_used']
            )
            for q in queries
        ]
        
    except Exception as e:
        logger.error(f"❌ Error getting unclassified queries: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/high-confidence", response_model=List[QueryResponse])
async def get_high_confidence_queries(
    min_confidence: float = Query(0.5, description="Minimum confidence score (0.0-1.0)", ge=0.0, le=1.0),
    limit: int = Query(50, description="Maximum number of queries to return", ge=1, le=200)
):
    """
    Get queries with confidence score >= min_confidence threshold
    
    Shows all high-confidence queries regardless of manual classification status.
    Useful for reviewing system-generated SQL and building training datasets.
    
    Query Parameters:
    - min_confidence: Minimum confidence score (default 0.5 = 50%)
    - limit: Maximum number of queries to return
    """
    try:
        if not classification_service:
            raise HTTPException(status_code=500, detail="Classification service not initialized")
        
        queries = classification_service.get_high_confidence_queries(
            min_confidence=min_confidence,
            limit=limit
        )
        
        return [
            QueryResponse(
                query_id=q['query_id'],
                timestamp=q['timestamp'],
                user_query=q['user_query'],
                generated_sql=q['generated_sql'],
                classification=q['classification'],
                rows_returned=q['rows_returned'],
                confidence=q['confidence'],
                tables_used=q['tables_used']
            )
            for q in queries
        ]
        
    except Exception as e:
        logger.error(f"❌ Error getting high confidence queries: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/classify")
async def classify_query(request: ClassifyQueryRequest):
    """
    Manually classify a query as correct/incorrect/needs_review
    
    This is used to build a training dataset
    """
    try:
        if not classification_service:
            raise HTTPException(status_code=500, detail="Classification service not initialized")
        
        success = classification_service.classify_query(
            query_id=request.query_id,
            classification=request.classification,
            notes=request.notes,
            corrected_sql=request.corrected_sql
        )
        
        if not success:
            raise HTTPException(status_code=404, detail="Query not found or classification failed")
        
        return {
            "success": True,
            "message": f"Query {request.query_id} classified as {request.classification}"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error classifying query: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/update")
async def update_query(request: UpdateQueryRequest):
    """
    Update a query's text or SQL before classification
    
    Allows editing queries for corrections/improvements
    """
    try:
        if not classification_service:
            raise HTTPException(status_code=500, detail="Classification service not initialized")
        
        success = classification_service.update_query(
            query_id=request.query_id,
            user_query=request.user_query,
            generated_sql=request.generated_sql,
            notes=request.notes
        )
        
        if not success:
            raise HTTPException(status_code=404, detail="Query not found or update failed")
        
        return {
            "success": True,
            "message": f"Query {request.query_id} updated successfully"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error updating query: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stats", response_model=StatsResponse)
async def get_classification_stats():
    """
    Get statistics about classified queries
    
    Returns counts and accuracy metrics
    """
    try:
        if not classification_service:
            raise HTTPException(status_code=500, detail="Classification service not initialized")
        
        stats = classification_service.get_classification_stats()
        
        return StatsResponse(**stats)
        
    except Exception as e:
        logger.error(f"❌ Error getting stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/export")
async def export_training_dataset():
    """
    Export classified queries as training dataset
    
    Creates a JSON file with all correct queries and corrections
    """
    try:
        if not classification_service:
            raise HTTPException(status_code=500, detail="Classification service not initialized")
        
        output_path = settings.DATA_DIR / "training_dataset.json"
        success = classification_service.export_training_dataset(output_path)
        
        if not success:
            raise HTTPException(status_code=500, detail="Export failed")
        
        return {
            "success": True,
            "message": f"Training dataset exported to {output_path}",
            "path": str(output_path)
        }
        
    except Exception as e:
        logger.error(f"❌ Error exporting dataset: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/search")
async def search_queries(
    query: str = Query(..., description="Search term"),
    classification: Optional[str] = Query(None, description="Filter by classification"),
    limit: int = Query(20, ge=1, le=100)
):
    """
    Search through classified queries
    
    Useful for finding similar past queries
    """
    try:
        if not classification_service:
            raise HTTPException(status_code=500, detail="Classification service not initialized")
        
        # Get all queries from cache
        all_queries = classification_service.classified_queries_cache
        
        # Filter by classification if specified
        if classification:
            all_queries = [q for q in all_queries if q['classification'] == classification]
        
        # Simple text search
        query_lower = query.lower()
        matching = [
            q for q in all_queries
            if query_lower in q['user_query'].lower() or query_lower in q['generated_sql'].lower()
        ]
        
        # Sort by timestamp (newest first)
        matching.sort(key=lambda x: x['timestamp'], reverse=True)
        
        return {
            "total_found": len(matching),
            "results": [
                {
                    "query_id": q['query_id'],
                    "timestamp": q['timestamp'],
                    "user_query": q['user_query'],
                    "generated_sql": q['generated_sql'],
                    "classification": q['classification'],
                    "rows_returned": q['rows_returned'],
                    "confidence": q['confidence']
                }
                for q in matching[:limit]
            ]
        }
        
    except Exception as e:
        logger.error(f"❌ Error searching queries: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ========================================
# BUSINESS RULES MANAGEMENT
# ========================================

class BusinessRuleRequest(BaseModel):
    rule_name: str = Field(..., description="Name of the business rule")
    rule_config: Dict[str, Any] = Field(..., description="Rule configuration")


@router.get("/business-rules")
async def get_business_rules():
    """
    Get current business rules from config/sql_assistant_config.json
    """
    try:
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        if not config_path.exists():
            return {"business_rules": {}, "path": str(config_path)}
        
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        return {
            "business_rules": config.get("business_rules", {}),
            "total_rules": len(config.get("business_rules", {})),
            "path": str(config_path)
        }
        
    except Exception as e:
        logger.error(f"❌ Error loading business rules: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/business-rules")
async def update_business_rule(request: BusinessRuleRequest):
    """
    Add or update a business rule in config/sql_assistant_config.json
    """
    try:
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        # Load existing config
        if config_path.exists():
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        else:
            config = {"business_rules": {}, "example_queries": {}}
        
        # Ensure business_rules exists
        if "business_rules" not in config:
            config["business_rules"] = {}
        
        # Update the rule
        config["business_rules"][request.rule_name] = request.rule_config
        
        # Save back to file
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        logger.info(f"✅ Updated business rule: {request.rule_name}")
        
        return {
            "success": True,
            "message": f"Business rule '{request.rule_name}' updated successfully",
            "total_rules": len(config["business_rules"])
        }
        
    except Exception as e:
        logger.error(f"❌ Error updating business rule: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/business-rules/{rule_name}")
async def delete_business_rule(rule_name: str):
    """
    Delete a business rule from config/sql_assistant_config.json
    """
    try:
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        if not config_path.exists():
            raise HTTPException(status_code=404, detail="Config file not found")
        
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        if "business_rules" not in config or rule_name not in config["business_rules"]:
            raise HTTPException(status_code=404, detail=f"Rule '{rule_name}' not found")
        
        # Delete the rule
        del config["business_rules"][rule_name]
        
        # Save back to file
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        logger.info(f"✅ Deleted business rule: {rule_name}")
        
        return {
            "success": True,
            "message": f"Business rule '{rule_name}' deleted successfully",
            "total_rules": len(config["business_rules"])
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error deleting business rule: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/business-rules/bulk")
async def update_all_business_rules(business_rules: Dict[str, Any]):
    """
    Replace all business rules in config/sql_assistant_config.json
    """
    try:
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        # Load existing config
        if config_path.exists():
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        else:
            config = {"business_rules": {}, "example_queries": {}}
        
        # Replace all business rules
        config["business_rules"] = business_rules
        
        # Save back to file
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        logger.info(f"✅ Updated all business rules ({len(business_rules)} total)")
        
        return {
            "success": True,
            "message": f"All business rules updated successfully",
            "total_rules": len(business_rules)
        }
        
    except Exception as e:
        logger.error(f"❌ Error updating all business rules: {e}")
        raise HTTPException(status_code=500, detail=str(e))
