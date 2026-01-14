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

## 🎨 User Interfaces

### Available Web Pages

| URL | Page | Description |
|-----|------|-------------|
| `/` | Home | Landing page with feature showcase |
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
│   │   │   └── diagnostic_support_routes.py
│   │   ├── core/                   # Core configuration
│   │   │   ├── config.py
│   │   │   ├── logging.py
│   │   │   ├── security.py
│   │   │   └── setting.py
│   │   ├── models/                 # Data models
│   │   │   └── schemas.py
│   │   ├── services/               # Business logic
│   │   │   ├── llm_service.py
│   │   │   ├── vector_store_service.py
│   │   │   ├── knowledge_base_service.py
│   │   │   ├── sql_assistant_service.py
│   │   │   ├── diagnostic_service.py
│   │   │   ├── agentic_service.py
│   │   │   └── ...
│   │   ├── utils/                  # Utilities
│   │   ├── ingetion/              # Document ingestion
│   │   │   ├── ingest_pipeline.py
│   │   │   ├── chunking/
│   │   │   └── loaders/
│   │   └── main.py                 # Application entry point
│   ├── requirements.txt
│   └── .env.example
├── data/
│   ├── documents/                  # 📚 Your documentation files
│   ├── database/                   # 💾 Database schemas
│   ├── support/                    # 🔧 Support knowledge base
│   ├── models/                     # Local LLM models
│   └── vector_store.json          # Vector embeddings
├── frontend/
│   ├── index.html                  # 🏡 Home/Landing page
│   ├── chatbot.html               # 💬 Main chatbot (3-in-1)
│   ├── semi_auto_diagnostic.html  # 🛠️ Semi-automated diagnostics
│   ├── diagnostic_support.html    # 📊 Support dashboard
│   └── navigation_dashboard.html  # 🗂️ Navigation hub
├── scripts/
│   ├── ingest_documents.py        # Document ingestion
│   ├── ingest_code.py             # Code ingestion
│   └── test_*.py                  # Testing scripts
├── docs/
│   ├── AGENTIC_ARCHITECTURE.md
│   ├── AGENTIC_QUICKSTART.md
│   ├── CONFIGURATION_GUIDE.md
│   └── INTEGRATION_GUIDE.md
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

## Python 3.11 is required.
## so you can create virtual environemnt like 
py --3.11 venv venv
## or 
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

```bash
# Test knowledge base
python scripts/test_knowledge_base.py

# Test intelligent responses
python scripts/test_intelligent_responses.py

# Check vector store
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

NEO Development Team

---

## 🎯 Next Steps

1. **Customize the chatbot** for your specific use case
2. **Add more documents** to improve knowledge base
3. **Configure database** for SQL Assistant
4. **Set up monitoring** and logging
5. **Deploy to production** environment

Need help? Contact the NEO Development Team.
