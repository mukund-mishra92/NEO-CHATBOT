# NEO Chatbot 🤖

Intelligent chatbot assistant for NEO Warehouse Management System with advanced capabilities including knowledge base Q&A, SQL query assistance, and automated diagnostic support.

## 🎯 Features

### 1. **📚 Knowledge Base Chatbot**
- Answer questions about NEO documentation, guides, and manuals
- RAG (Retrieval-Augmented Generation) powered search
- Support for multiple document formats (PDF, DOCX, TXT, MD)
- Citation of source documents

### 2. **💾 SQL Assistant**
- Natural language to SQL query conversion
- Database schema understanding
- Query execution and result formatting
- Data insights and analysis

### 3. **🔧 Diagnostic Support**
- Automated issue detection
- Step-by-step troubleshooting guidance
- Solution recommendations
- Support ticket logging

### 4. **🛠️ Semi-Automated Diagnostics**
- Interactive step-by-step troubleshooting
- User verification at each step
- Category and severity selection
- Progress tracking and ticket creation

### 5. **📊 Diagnostic Support Dashboard**
- Real-time statistics and metrics
- Issue history and trends
- Solution database search
- Log file viewer and analysis

### 6. **🤖 Agentic AI (Multi-Agent System)**
- Multiple AI agents verify responses
- Improved accuracy through consensus
- Automatic fallback to local LLM

### 7. **🔐 Secure OTP Authentication**
- Email-based OTP (One-Time Password) verification for users
- Domain restriction: Only `@falconautotech.com` emails allowed
- Secure OTP generation with hashing and salting
- Rate limiting and attempt limiting for security
- Admin login with username/password (no OTP required)

## 🎨 User Interfaces

### Available Web Pages

| URL | Page | Description |
|-----|------|-------------|
| `/` | Home | Landing page with feature showcase |
| `/login` | Login | Secure OTP-based authentication |
| `/chatbot` | Main Chatbot | 3-in-1 AI assistant (Knowledge Base, SQL, Diagnostic) |
| `/diagnostic` | Semi-Auto Diagnostics | Interactive troubleshooting wizard |
| `/diagnostic-support` | Support Dashboard | Comprehensive support management |
| `/dashboard` | Navigation Hub | Central access to all features |
| `/docs` | API Docs | Interactive API documentation |

## 📁 Project Structure

```
Neo-Chatbot/
├── backend/
│   ├── app/
│   │   ├── api/                    # API endpoints
│   │   │   ├── chatbot_endpoints.py
│   │   │   ├── classification_routes.py
│   │   │   ├── sql_execution_routes.py
│   │   │   └── diagnostic_support_routes.py
│   │   ├── core/                   # Core configuration
│   │   │   └── config.py
│   │   ├── models/                 # Data models
│   │   │   └── schemas.py
│   │   ├── services/               # Business logic
│   │   │   ├── sql_assistant/      # 🧠 NL→SQL pipeline (18 modules)
│   │   │   │   ├── sql_assistant.py      # Main orchestrator
│   │   │   │   ├── query_preprocessor.py # Synonym + entity + intent
│   │   │   │   ├── tenant_resolver.py    # Embedding-based tenant extraction
│   │   │   │   ├── table_selector.py     # Schema-aware table selection
│   │   │   │   ├── validator.py          # SQL safety rules
│   │   │   │   ├── schema_validator.py   # Table/column existence check
│   │   │   │   ├── semantic_validator.py  # Result sanity check
│   │   │   │   ├── retry_engine.py       # Max-3-attempt retry with feedback
│   │   │   │   ├── reuse_engine.py       # Classification-based query reuse
│   │   │   │   ├── entity_resolver.py    # BOT/STATION/WAVE/ORDER/BIN IDs
│   │   │   │   ├── synonym_resolver.py   # sku→article, robot→bot
│   │   │   │   ├── formatter.py          # Markdown table formatting
│   │   │   │   ├── confidence.py         # 0.7×LLM + 0.3×exec scoring
│   │   │   │   ├── cache_manager.py      # In-memory query cache
│   │   │   │   ├── schema_feedback.py    # Smart error messages
│   │   │   │   ├── column_resolver.py    # Fuzzy column matching
│   │   │   │   └── table_priority_loader.py # JSONL validation history
│   │   │   ├── knowledge_base_service.py
│   │   │   ├── query_classification_service.py
│   │   │   ├── session_manager.py
│   │   │   ├── agentic_service.py
│   │   │   └── ...
│   │   ├── utils/                  # Utilities
│   │   ├── prompts/               # LLM prompt templates
│   │   ├── ingetion/              # Document ingestion
│   │   └── main.py                # Application entry point
│   └── requirements.txt
├── test/                           # 🧪 Automated Test Suite (354 tests)
│   ├── conftest.py                 # Shared fixtures & factories
│   ├── pytest.ini                  # Pytest configuration
│   ├── requirements.txt            # Test dependencies
│   ├── fixtures/                   # Test data
│   │   ├── query_cases.json        # 20-query test bank
│   │   ├── expected_outputs.json   # SQL output patterns
│   │   └── mock_llm_responses.json # Canned LLM responses
│   ├── unit/                       # Layer 1: Unit tests (279)
│   │   ├── services/               # 16 test files for sql_assistant/*
│   │   ├── utils/                  # Session manager tests
│   │   ├── models/                 # Pydantic schema tests
│   │   └── api/                    # Session query detection
│   ├── integration/                # Layer 2: Integration tests (28)
│   │   ├── test_pipeline_flow.py   # Preprocessing→validation chain
│   │   ├── test_classification_storage.py  # JSONL round-trip
│   │   └── test_reuse_engine_integration.py # Reuse path + validators
│   ├── api/                        # Layer 3: API tests (25)
│   │   ├── test_chatbot_endpoint.py
│   │   ├── test_sql_routes.py
│   │   └── test_classification_routes.py
│   └── e2e/                        # Layer 4: End-to-end tests (22)
│       ├── test_nl_to_sql_flow.py  # Full NL→SQL→format pipeline
│       └── test_api_e2e.py         # HTTP round-trip + security
├── data/
│   ├── documents/                  # 📚 Documentation files
│   ├── database/                   # 💾 Database schemas & table info
│   ├── classification/             # 🏷️ Classified query JSONL
│   ├── support/                    # 🔧 Support knowledge base
│   └── models/                     # Local LLM models
├── frontend/
│   ├── index.html                  # 🏡 Home/Landing page
│   ├── chatbot.html               # 💬 Main chatbot (3-in-1)
│   ├── classification.html        # 🏷️ Query classification UI
│   ├── schema_management.html     # 📋 Schema management
│   ├── semi_auto_diagnostic.html  # 🛠️ Semi-automated diagnostics
│   ├── diagnostic_support.html    # 📊 Support dashboard
│   └── navigation_dashboard.html  # 🗂️ Navigation hub
├── scripts/
│   ├── ingest_documents.py        # Document ingestion
│   ├── ingest_code.py             # Code ingestion
│   └── test_*.py                  # Manual testing scripts
├── config/                         # AI model & SQL assistant config
├── docs/                           # Architecture documentation
└── README.md
```

## 🚀 Quick Start

### Prerequisites

- Python 3.9 or higher
- MySQL database (for SQL Assistant feature)
- API keys for LLM providers (Groq/OpenAI/Anthropic)

### 1. Clone and Setup

```bash
cd Neo-Chatbot/backend
```

### 2. Create Virtual Environment

```bash
python -m venv venv
# Windows
venv\Scripts\activate
# Linux/Mac
source venv/bin/activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Configure Environment

Copy `.env.example` to `.env` and fill in your values:

```bash
copy .env.example .env  # Windows
cp .env.example .env    # Linux/Mac
```

Edit `.env` and add your API keys:
```env
GROQ_API_KEY=your_groq_api_key_here
OPENAI_API_KEY=your_openai_api_key_here
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=your_password
DB_NAME=neo
```

### 5. Prepare Your Data

#### Documents
Place your documentation files in `data/documents/`:
```
data/documents/
├── manuals/
├── proposals/
├── sops/
└── training_docs/
```

Supported formats: PDF, DOCX, TXT, MD

#### Database Schema
Add your database schema to `data/database/schema.json` or `schema.sql`

#### Support Issues
Create support knowledge base in `data/support/issues.json`

### 6. Ingest Documents

```bash
# Ingest all documents into vector store
python scripts/ingest_documents.py

# Verify ingestion
python scripts/test_knowledge_base.py
```

### 7. Run the Server

```bash
cd backend
python -m app.main
```

Or using uvicorn directly:
```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Server will start at: `http://localhost:8000`

### 8. Access the Application

- **Home Page**: http://localhost:8000
- **API Documentation**: http://localhost:8000/docs
- **Main Chatbot** (3-in-1): http://localhost:8000/chatbot
  - Knowledge Base Q&A
  - SQL Assistant
  - Diagnostic Support
- **Semi-Auto Diagnostics**: http://localhost:8000/diagnostic
- **Support Dashboard**: http://localhost:8000/diagnostic-support
- **Navigation Hub**: http://localhost:8000/dashboard
- **Health Check**: http://localhost:8000/health

## 📖 API Endpoints

### Chatbot Endpoints

```http
POST /api/chatbot/chat
POST /api/chatbot/sql-query
GET  /api/chatbot/health
POST /api/chatbot/upload-document
GET  /api/chatbot/documents
```

### Diagnostic Support Endpoints

```http
POST /api/diagnostic-support/diagnose
GET  /api/diagnostic-support/solutions/{issue_id}
POST /api/diagnostic-support/verify-solution
POST /api/diagnostic-support/log-issue
```

## 🧪 Testing

The project has a **4-layer automated test suite** with **354 tests** covering the full NL→SQL pipeline, API layer, and end-to-end flows.

### Test Architecture

| Layer | Tests | What it covers |
|-------|-------|----------------|
| **Unit** | 279 | Individual modules: validator, entity resolver, synonym resolver, formatter, confidence scoring, cache, schema feedback, retry engine, reuse engine, tenant resolver, query preprocessor, classification service, session manager, Pydantic schemas |
| **Integration** | 28 | Multi-module chains: preprocessing→validation pipeline, classification JSONL storage round-trip, reuse engine with real validators |
| **API** | 25 | HTTP endpoints: chatbot routing, SQL execution security (7 dangerous patterns blocked), classification CRUD, response schema contracts |
| **E2E** | 22 | Full user journeys: NL question→SQL→validation→execution→formatted response, tenant-aware queries, entity resolution flow, cache round-trip, join queries, security gate verification |

### Running Tests

```bash
# Activate virtual environment
venv\Scripts\activate          # Windows
source venv/bin/activate        # Linux/Mac

# Run ALL tests (default: skips @slow)
python -m pytest test/ --tb=short -q

# Run specific layers
python -m pytest test/unit/               # Unit only
python -m pytest test/integration/         # Integration only
python -m pytest test/api/                 # API only
python -m pytest test/e2e/                 # End-to-end only

# Run by marker
python -m pytest -m "integration"          # Integration-marked tests
python -m pytest -m "e2e"                  # E2E-marked tests
python -m pytest -m "not slow"             # Everything except slow

# Run a single module
python -m pytest test/unit/services/test_sql_validator.py -v

# Run with coverage report
python -m pytest test/ --cov=backend/app --cov-report=html

# Run in CI mode (no color, JUnit XML output)
python -m pytest test/ --tb=short -q --junitxml=test-results.xml
```

### Test Dependencies

```bash
pip install -r test/requirements.txt
# Installs: pytest, pytest-mock, pytest-cov, httpx, fastapi[all]
```

### Key Test Fixtures (test/conftest.py)

| Fixture | Purpose |
|---------|----------|
| `sample_schema` | 8-table warehouse schema with hyphenated columns |
| `mock_generation_result` | Factory for SQLGenerationResult objects |
| `mock_execution_result` | Factory for SQLExecutionResult objects |
| `mock_llm_response` | Canned LLM responses (simple, aggregation, join) |
| `tenant_value_mappings` | Predefined tenant mappings (bhiwandi→shakti, etc.) |
| `query_test_bank` | 20 queries loaded from fixtures/query_cases.json |
| `mock_executor` / `mock_validator` | Pre-wired mock services |
| `test_settings` | Patched settings pointing at temp directories |
| `test_client` | FastAPI TestClient with heavy services mocked |

### Manual Test Scripts

```bash
# Legacy manual scripts (still available)
python scripts/test_knowledge_base.py
python scripts/test_intelligent_responses.py
python scripts/check_vector_store.py
```

## 🔧 Configuration

### LLM Providers Priority

1. **Groq** (fastest, recommended)
2. **OpenAI** (high quality)
3. **Anthropic** (Claude models)
4. **Local LLM** (offline fallback)

### Enable/Disable Features

In `.env`:
```env
AGENTIC_MODE_ENABLED=true          # Multi-agent verification
LOCAL_LLM_ENABLED=true             # Local LLM fallback
```

### Customize Settings

Edit `backend/app/core/config.py` for advanced configuration.

## 📚 Documentation

- [Agentic Architecture](docs/AGENTIC_ARCHITECTURE.md) - Multi-agent system design
- [Quick Start Guide](docs/AGENTIC_QUICKSTART.md) - Getting started
- [Configuration Guide](docs/CONFIGURATION_GUIDE.md) - Detailed configuration
- [Integration Guide](docs/INTEGRATION_GUIDE.md) - Integration with other systems

## 🐛 Troubleshooting

### Common Issues

1. **Import errors after migration**
   - Check Python path includes backend directory
   - Verify all `__init__.py` files exist

2. **Database connection failed**
   - Verify MySQL is running
   - Check credentials in `.env`
   - Test connection: `python scripts/test_db_connection.py`

3. **API key errors**
   - Ensure API keys in `.env` are correct
   - Check API provider rate limits
   - Local LLM will activate as fallback

4. **Document ingestion fails**
   - Check document formats are supported
   - Verify file permissions
   - Check available disk space

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## 📝 License

Proprietary - NEO Development Team

## 👥 Authors

Falcon AI Team



Need help? Contact the NEO Development Team.
