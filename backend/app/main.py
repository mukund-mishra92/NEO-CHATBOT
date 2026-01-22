"""
NEO Chatbot - Main Application
FastAPI-based chatbot with knowledge base, SQL assistant, and diagnostic support
"""

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
import logging

from .api.chatbot_endpoints import router as chatbot_router
from .api.diagnostic_support_routes import router as diagnostic_router
from .core.config import settings
from .core.logging import setup_logging

# Setup logging
setup_logging()
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="NEO Chatbot API",
    version="1.0.0",
    description="Intelligent chatbot for NEO Warehouse Management System"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify actual origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(chatbot_router)  # Chatbot API routes (has /api/chatbot prefix)
app.include_router(diagnostic_router)  # Diagnostic support routes (/api/diagnostic-support)

def serve_html_file(filename: str, fallback_message: str = "Page not found"):
    """Helper function to serve HTML files"""
    frontend_path = Path(__file__).parent.parent.parent / "frontend" / filename
    if frontend_path.exists():
        with open(frontend_path, "r", encoding="utf-8") as f:
            return HTMLResponse(content=f.read())
    return HTMLResponse(content=f"<h1>{fallback_message}</h1>", status_code=404)

@app.get("/", response_class=HTMLResponse)
async def root():
    """Root endpoint - Serve home/index page"""
    return serve_html_file("index.html", "Home page not found")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "NEO Chatbot", "version": "1.0.0"}

@app.get("/chatbot", response_class=HTMLResponse)
async def chatbot_page():
    """Serve the main chatbot UI with all features (Knowledge Base, SQL Assistant, Diagnostic)"""
    return serve_html_file("chatbot.html", "Chatbot UI not found")

# DISABLED: Semi-Auto Diagnostic feature
# @app.get("/diagnostic", response_class=HTMLResponse)
# async def diagnostic_page():
#     """Serve the semi-automated diagnostic support UI"""
#     return serve_html_file("semi_auto_diagnostic.html", "Diagnostic UI not found")

@app.get("/diagnostic-support", response_class=HTMLResponse)
async def diagnostic_support_page():
    """Serve the diagnostic support UI"""
    return serve_html_file("diagnostic_support.html", "Diagnostic support UI not found")

if __name__ == "__main__":
    import uvicorn
    logger.info("🚀 Starting NEO Chatbot server...")
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=3960,
        reload=True,
        log_level="info"
    )
