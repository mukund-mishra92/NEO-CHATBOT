"""
AI Configuration routes.
Admin-facing endpoints for selecting global provider/model settings.
"""

from typing import Any, Dict

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.services.ai_config_service import get_ai_config_service

router = APIRouter(prefix="/api/ai-config", tags=["AI Config"])


class AIConfigUpdateRequest(BaseModel):
    active_provider: str = Field(..., description="openai or groq")
    chat_model: str
    sql_model: str
    agent_model: str
    vision_model: str
    embedding_model: str


@router.get("")
async def get_ai_config() -> Dict[str, Any]:
    service = get_ai_config_service()
    return {
        "success": True,
        "config": service.get_config(),
        "catalog": service.get_catalog(),
    }


@router.put("")
async def update_ai_config(request: AIConfigUpdateRequest) -> Dict[str, Any]:
    service = get_ai_config_service()
    try:
        updated = service.update_config(request.model_dump())
        return {
            "success": True,
            "message": "AI configuration updated successfully.",
            "config": updated,
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))
