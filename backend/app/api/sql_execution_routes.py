"""
API endpoints for SQL query execution
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
import logging
from datetime import datetime
import pymysql
import pandas as pd
import re

from app.core.config import settings

logger = logging.getLogger(__name__)

# Create router
router = APIRouter(prefix="/api/sql", tags=["sql-execution"])

# Database configuration
db_config = {
    'host': settings.DB_HOST,
    'user': settings.DB_USER,
    'password': settings.DB_PASSWORD,
    'database': settings.DB_NAME,
    'port': settings.DB_PORT,
    'charset': 'utf8mb4',
    'cursorclass': pymysql.cursors.DictCursor
}


# ========================================
# REQUEST/RESPONSE MODELS
# ========================================

class SQLExecuteRequest(BaseModel):
    sql_query: str = Field(..., description="SQL query to execute")


class SQLExecuteResponse(BaseModel):
    success: bool
    results: Optional[List[Dict[str, Any]]] = None
    row_count: int
    execution_time_ms: float
    error: Optional[str] = None


# ========================================
# ENDPOINTS
# ========================================

@router.post("/execute", response_model=SQLExecuteResponse)
async def execute_sql_query(request: SQLExecuteRequest):
    """
    Execute a SQL query and return results
    
    This endpoint is used by the classification page to execute queries
    for preview/validation purposes.
    """
    start_time = datetime.now()
    
    try:
        sql_query = request.sql_query.strip()
        
        # Security check - only allow SELECT queries
        dangerous_patterns = [
            r'\bDROP\s+',
            r'\bDELETE\s+FROM\b',
            r'\bTRUNCATE\s+',
            r'\bALTER\s+TABLE\b',
            r'\bCREATE\s+TABLE\b',
            r'\bINSERT\s+INTO\b',
            r'\bUPDATE\s+\w+\s+SET\b'
        ]
        
        query_upper = sql_query.upper()
        for pattern in dangerous_patterns:
            if re.search(pattern, query_upper):
                return SQLExecuteResponse(
                    success=False,
                    results=None,
                    row_count=0,
                    execution_time_ms=0,
                    error=f"Query contains dangerous operation: {pattern}"
                )
        
        # Execute the query
        logger.info(f"🔍 Executing SQL: {sql_query[:100]}...")
        
        conn = pymysql.connect(**db_config, connect_timeout=10)
        
        try:
            # Use pymysql cursor directly instead of pandas (fixes compatibility issues)
            with conn.cursor() as cursor:
                cursor.execute(sql_query)
                results = cursor.fetchall()
                
                # Convert to list of dicts (cursor already returns dicts due to DictCursor)
                results = [dict(row) for row in results] if results else []
            
            end_time = datetime.now()
            execution_time = (end_time - start_time).total_seconds() * 1000
            
            logger.info(f"✅ Query executed successfully: {len(results)} rows returned")
            
            return SQLExecuteResponse(
                success=True,
                results=results,
                row_count=len(results),
                execution_time_ms=execution_time,
                error=None
            )
            
        finally:
            conn.close()
        
    except pymysql.Error as e:
        end_time = datetime.now()
        execution_time = (end_time - start_time).total_seconds() * 1000
        error_msg = str(e)
        logger.error(f"❌ Database error: {error_msg}")
        
        return SQLExecuteResponse(
            success=False,
            results=None,
            row_count=0,
            execution_time_ms=execution_time,
            error=f"Database error: {error_msg}"
        )
        
    except Exception as e:
        end_time = datetime.now()
        execution_time = (end_time - start_time).total_seconds() * 1000
        error_msg = str(e)
        logger.error(f"❌ Execution error: {error_msg}")
        
        return SQLExecuteResponse(
            success=False,
            results=None,
            row_count=0,
            execution_time_ms=execution_time,
            error=f"Execution error: {error_msg}"
        )
