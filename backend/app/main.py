"""
NEO Chatbot - Main Application
FastAPI-based chatbot with knowledge base, SQL assistant, and diagnostic support
"""

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
import logging

from app.api.chatbot_endpoints import router as chatbot_router
from app.api.diagnostic_support_routes import router as diagnostic_router
from app.api.classification_routes import router as classification_router
from app.api.schema_management_routes import router as schema_router
from app.api.table_priority_routes import router as table_priority_router
from app.api.sql_execution_routes import router as sql_execution_router
from app.core.config import settings
from app.core.logging import setup_logging

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
app.include_router(classification_router)  # Query classification routes (/api/classification)
app.include_router(schema_router)  # Schema management routes (/api/schema)
app.include_router(table_priority_router)  # Table priority validation routes (/api/table-priority)
app.include_router(sql_execution_router)  # SQL execution routes (/api/sql)

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

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard_page():
    """Serve the navigation dashboard"""
    return serve_html_file("navigation_dashboard.html", "Dashboard not found")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "NEO Chatbot", "version": "1.0.0"}

@app.get("/chatbot", response_class=HTMLResponse)
async def chatbot_page():
    """Serve the main chatbot UI with all features (Knowledge Base, SQL Assistant, Diagnostic)"""
    return serve_html_file("chatbot.html", "Chatbot UI not found")

@app.get("/diagnostic", response_class=HTMLResponse)
async def diagnostic_page():
    """Serve the semi-automated diagnostic support UI"""
    return serve_html_file("semi_auto_diagnostic.html", "Diagnostic UI not found")

@app.get("/diagnostic-support", response_class=HTMLResponse)
async def diagnostic_support_page():
    """Serve the diagnostic support UI"""
    return serve_html_file("diagnostic_support.html", "Diagnostic support UI not found")

@app.get("/classification", response_class=HTMLResponse)
async def classification_page():
    """Serve the query classification UI"""
    return serve_html_file("classification.html", "Classification UI not found")

@app.get("/schema", response_class=HTMLResponse)
async def schema_management_page():
    """Serve the schema management UI"""
    return serve_html_file("schema_management.html", "Schema Management UI not found")

@app.get("/table_priority_analyzer", response_class=HTMLResponse)
async def table_priority_analyzer_page():
    """Serve the table priority validator UI"""
    return serve_html_file("table_priority_validator.html", "Table Priority Analyzer UI not found")

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    try:
        from app.services.query_classification_service import QueryClassificationService
        from app.api import classification_routes
        
        # Initialize classification service
        classification_service = QueryClassificationService(settings.DATA_DIR / "classification")
        classification_routes.init_classification_service(classification_service)
        
        logger.info("✅ Classification service initialized")
    except Exception as e:
        logger.error(f"❌ Failed to initialize services: {e}")

if __name__ == "__main__":
    import uvicorn
    logger.info("🚀 Starting NEO Chatbot server...")
    
    # Configure logging to suppress watchfiles
    log_config = uvicorn.config.LOGGING_CONFIG
    log_config["loggers"]["watchfiles.main"] = {
        "level": "WARNING",
        "handlers": ["default"],
        "propagate": False
    }
    
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        reload_excludes=[
            "logs/**",
            "**/*.log",
            "**/*.jsonl",
            "data/**",
            "**/__pycache__/**",
            "**/classification/**",
            "**/rlhf/**"
        ],  # Exclude logs, data files, and cache from reload
        log_level="info",
        log_config=log_config
    )

