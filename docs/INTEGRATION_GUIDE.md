# NEO Chatbot Integration Guide

## ✅ What's Been Implemented

All core chatbot modules are now complete:

### 1. **Core Services** (app/modules/neo_chatbot/services/)
- ✅ `llm_service.py` - OpenAI/Anthropic/Mock LLM integration
- ✅ `vector_store_service.py` - Document embeddings & semantic search
- ✅ `knowledge_base_service.py` - RAG-based Q&A with documentation
- ✅ `sql_assistant_service.py` - Natural language to SQL
- ✅ `diagnostic_service.py` - Issue troubleshooting & support

### 2. **API Layer** (app/modules/neo_chatbot/api/)
- ✅ `chatbot_endpoints.py` - FastAPI routes for all chatbot features
- ✅ Endpoints: `/chat`, `/sql-query`, `/upload-document`, `/system-health`, `/statistics`

### 3. **Data Models** (app/modules/neo_chatbot/models/)
- ✅ `schemas.py` - Pydantic models for type safety

### 4. **Documentation**
- ✅ `README.md` - Complete module documentation
- ✅ Data templates in `data/` folders

---

## 🚀 Next Steps to Activate Chatbot

### Step 1: Install Dependencies

Add to your `requirements.txt`:
```txt
# LLM providers (choose one or both)
openai>=1.0.0
anthropic>=0.25.0

# Vector operations
numpy>=1.24.0

# Document processing (when you're ready to add docs)
PyPDF2>=3.0.0
python-docx>=0.8.11
```

Install:
```bash
pip install openai anthropic numpy
```

### Step 2: Set Up API Keys

Create `.env` file (or add to existing):
```env
# Choose your LLM provider
OPENAI_API_KEY=your_openai_key_here
# OR
ANTHROPIC_API_KEY=your_anthropic_key_here

# Note: If neither is set, chatbot will use mock mode (good for development)
```

### Step 3: Register API Routes

In your `app/main.py`, add:

```python
from app.modules.neo_chatbot.api import router as chatbot_router

# Add to your FastAPI app
app.include_router(chatbot_router)
```

### Step 4: Add UI Page (When Ready)

Create `app/web/templates/chatbot.html`:
- Chat interface with message history
- Toggle between 3 chatbot types (Knowledge Base, SQL Assistant, Diagnostic)
- File upload for documents
- Display source citations

### Step 5: Add Navigation Link

Update your navigation to link to the chatbot page (remove "Coming Soon").

---

## 📂 Adding Your Data Sources

### 1. Documentation Files
Place your solution proposal documents in:
```
app/modules/neo_chatbot/data/documents/
```

Supported formats: PDF, DOCX, TXT

Then run ingestion script (you'll need to create this):
```python
from app.modules.neo_chatbot.services import KnowledgeBaseService

kb = KnowledgeBaseService()
kb.ingest_document("path/to/document.pdf", category="sales_proposals")
```

### 2. Database Schema
Create:
```
app/modules/neo_chatbot/data/database/schema.sql
```

Example:
```sql
CREATE TABLE order_history (
    order_id INT PRIMARY KEY,
    customer_id INT,
    order_date DATE,
    total_amount DECIMAL(10,2),
    status VARCHAR(50)
);

-- Add all your tables...
```

### 3. Support Issues
Create:
```
app/modules/neo_chatbot/data/support/issues.json
```

Example:
```json
{
  "issues": [
    {
      "issue_id": "SCH001",
      "issue_name": "Scheduler not running",
      "category": "scheduler",
      "severity": "high",
      "symptoms": ["No scheduled jobs executing", "Logs show no activity"],
      "diagnostic_steps": ["Check scheduler service status", "Verify database connection"],
      "solution_1_title": "Restart Scheduler Service",
      "solution_1_steps": "Navigate to Services > Restart Mining Scheduler",
      "solution_1_type": "quick_fix",
      "prevention": ["Enable auto-restart", "Set up health monitoring"]
    }
  ]
}
```

See templates in respective data/ folders for more examples.

---

## 🧪 Testing the Chatbot

### Test with Mock Mode (No API Keys)
```python
from app.modules.neo_chatbot.services import LLMService

llm = LLMService()  # Auto-detects no API keys, uses mock
response = llm.generate_response([{"role": "user", "content": "Hello"}])
print(response)  # Returns mock response
```

### Test API Endpoints
```bash
# Start your FastAPI server
uvicorn app.main:app --reload

# Test chat endpoint
curl -X POST http://localhost:8000/api/chatbot/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is NEO?",
    "chatbot_type": "knowledge_base"
  }'

# Test SQL generation
curl -X POST http://localhost:8000/api/chatbot/sql-query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Show me top 10 customers by order value"
  }'

# Get statistics
curl http://localhost:8000/api/chatbot/statistics
```

---

## 🎯 Features Overview

### Knowledge Base Chatbot
- **Purpose**: Answer questions about NEO from documentation
- **How it works**: RAG (Retrieval-Augmented Generation)
- **Use case**: "What are the main features of NEO?" → Searches docs, generates answer with sources

### SQL Assistant
- **Purpose**: Convert natural language to SQL queries
- **How it works**: Schema-aware SQL generation
- **Use case**: "Show me top 5 products" → Generates SQL query with explanation

### Diagnostic Support
- **Purpose**: Troubleshoot system issues
- **How it works**: Symptom matching + conversational guidance
- **Use case**: "Scheduler not working" → Identifies issue, provides step-by-step solution

---

## 📊 Current Status

| Component | Status | Notes |
|-----------|--------|-------|
| Core Services | ✅ Complete | All 5 services implemented |
| API Endpoints | ✅ Complete | 8 endpoints ready |
| Data Models | ✅ Complete | Full Pydantic validation |
| LLM Integration | ✅ Complete | OpenAI/Anthropic/Mock |
| Vector Search | ✅ Complete | Cosine similarity with filtering |
| Documentation | ✅ Complete | READMEs and templates |
| Web UI | ⏳ Pending | Need HTML/JS/CSS |
| Data Ingestion | ⏳ Pending | Need your documents |
| Testing | ⏳ Pending | Unit tests needed |

---

## 🔧 Troubleshooting

### "Module not found" errors
```bash
# Make sure you're in the right directory
cd c:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system

# Reinstall in development mode
pip install -e .
```

### Mock mode vs Real LLM
- **No API keys set**: Automatically uses mock responses
- **To use real LLM**: Set `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` in environment

### Empty knowledge base
- Until you add documents, chatbot will tell users to add documents
- This is expected behavior - won't crash

---

## 💡 Recommended Next Actions

1. **Test in mock mode** - Verify endpoints work without API keys
2. **Add one test document** - Try PDF ingestion with a sample file
3. **Create SQL schema file** - Add your database structure
4. **Add 1-2 sample issues** - Test diagnostic matching
5. **Build web UI** - Create chat interface page
6. **Get API key** - Choose OpenAI or Anthropic for production

---

## 📝 Notes

- All services handle missing data gracefully (no crashes)
- Mock mode lets you develop without API costs
- Vector store is file-based (can upgrade to Pinecone/Weaviate later)
- Session storage is in-memory (use Redis for production)
- Everything is on `chatbot-development` branch (safe from production)

**You can now add your documents whenever ready - the system is waiting for them!** 🚀
