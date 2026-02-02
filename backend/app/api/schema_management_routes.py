"""
Schema Management API Routes - Generate and manage Table_information.csv
"""

import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from pathlib import Path

from app.core.config import settings
from app.services.schema_generator_service import SchemaGeneratorService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/schema", tags=["Schema Management"])

# Initialize service (lazy loading)
_schema_service = None


def get_schema_service():
    """Get or create schema generator service"""
    global _schema_service
    if _schema_service is None:
        db_config = {
            'host': settings.DB_HOST,
            'port': settings.DB_PORT,
            'user': settings.DB_USER,
            'password': settings.DB_PASSWORD,
            'database': settings.DB_NAME
        }
        _schema_service = SchemaGeneratorService(
            db_config=db_config,
            openai_api_key=settings.OPENAI_API_KEY
        )
    return _schema_service


# Request/Response Models
class GenerateSchemaRequest(BaseModel):
    use_ai_descriptions: bool = True
    use_extended_thinking: bool = False
    overwrite_existing: bool = False


class GenerateSchemaResponse(BaseModel):
    success: bool
    message: str
    table_count: int
    csv_path: str


class ValidateSchemaResponse(BaseModel):
    valid: bool
    message: str
    issues: List[str]


class UpdateDescriptionRequest(BaseModel):
    table_name: str
    new_description: str


class TableSchema(BaseModel):
    Table_name: str
    Table_description: str
    Table_columns: str
    Primary_key: str


# Routes
@router.post("/generate", response_model=GenerateSchemaResponse)
async def generate_schema(request: GenerateSchemaRequest):
    """
    Generate Table_information.csv from live database
    
    Options:
    - use_ai_descriptions: Use OpenAI to generate intelligent descriptions
    - use_extended_thinking: Use o1 model for deeper analysis (slower but better)
    - overwrite_existing: Overwrite existing CSV file (default: False)
    """
    try:
        csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
        
        # Check if file exists and overwrite is False
        if csv_path.exists() and not request.overwrite_existing:
            raise HTTPException(
                status_code=400,
                detail="CSV file already exists. Set overwrite_existing=true to replace it."
            )
        
        service = get_schema_service()
        
        success, message, table_count = service.generate_csv(
            output_path=csv_path,
            use_ai_descriptions=request.use_ai_descriptions,
            use_extended_thinking=request.use_extended_thinking
        )
        
        if not success:
            raise HTTPException(status_code=500, detail=message)
        
        return GenerateSchemaResponse(
            success=success,
            message=message,
            table_count=table_count,
            csv_path=str(csv_path)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Generate schema failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/validate", response_model=ValidateSchemaResponse)
async def validate_schema():
    """
    Validate existing CSV against live database
    Checks for missing tables, new tables, and schema changes
    """
    try:
        csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
        
        if not csv_path.exists():
            raise HTTPException(
                status_code=404,
                detail="Table_information.csv not found. Generate it first using /generate endpoint."
            )
        
        service = get_schema_service()
        valid, message, issues = service.validate_csv(csv_path)
        
        return ValidateSchemaResponse(
            valid=valid,
            message=message,
            issues=issues
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Validate schema failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/tables", response_model=List[TableSchema])
async def get_all_tables():
    """
    Get all tables from CSV file for UI display
    """
    try:
        csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
        
        if not csv_path.exists():
            raise HTTPException(
                status_code=404,
                detail="Table_information.csv not found"
            )
        
        import pandas as pd
        df = pd.read_csv(csv_path)
        
        tables = []
        for _, row in df.iterrows():
            tables.append(TableSchema(
                Table_name=row['Table_name'],
                Table_description=row['Table_description'],
                Table_columns=row['Table_columns(Data type)'],
                Primary_key=row['Primary_key']
            ))
        
        return tables
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Get tables failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/description", response_model=dict)
async def update_description(request: UpdateDescriptionRequest):
    """
    Update table description in CSV file
    """
    try:
        csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
        
        if not csv_path.exists():
            raise HTTPException(
                status_code=404,
                detail="Table_information.csv not found"
            )
        
        service = get_schema_service()
        success, message = service.update_table_description(
            csv_path=csv_path,
            table_name=request.table_name,
            new_description=request.new_description
        )
        
        if not success:
            raise HTTPException(status_code=400, detail=message)
        
        return {"success": success, "message": message}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Update description failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stats")
async def get_schema_stats():
    """Get statistics about current schema"""
    try:
        csv_path = settings.DATA_DIR / "database" / "Table_information.csv"
        
        if not csv_path.exists():
            return {
                "csv_exists": False,
                "table_count": 0,
                "last_modified": None
            }
        
        import pandas as pd
        import os
        from datetime import datetime
        
        df = pd.read_csv(csv_path)
        stats = os.stat(csv_path)
        
        return {
            "csv_exists": True,
            "table_count": len(df),
            "last_modified": datetime.fromtimestamp(stats.st_mtime).isoformat(),
            "file_size_kb": round(stats.st_size / 1024, 2)
        }
        
    except Exception as e:
        logger.error(f"❌ Get stats failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
