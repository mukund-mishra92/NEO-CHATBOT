# 🚀 Quick Reference - Refactored Services

## Import Cheat Sheet

### DiagnosticSupportService
```python
# Recommended (New)
from app.services.diagnostic import DiagnosticSupportService

# Alternative (Services package)
from app.services import DiagnosticSupportService

# Old (Still works)
from app.services.diagnostic_support_service import DiagnosticSupportService
```

### SQLAssistantService
```python
# Recommended (New)
from app.services.sql_assistant import SQLAssistantService

# Alternative (Services package)
from app.services import SQLAssistantService

# Old (Still works)
from app.services.sql_assistant_service import SQLAssistantService
```

---

## Module Structure

### Diagnostic Service (7 modules)
```
diagnostic/
├── core.py               - Main coordinator
├── text_utils.py         - Text cleaning & parsing
├── csv_loader.py         - CSV data loading
├── issue_search.py       - Search engine
├── session_manager.py    - Session workflow
└── report_formatter.py   - Report formatting
```

**Usage:**
```python
service = DiagnosticSupportService()
results = service.search_issue("bot stopped")
session = service.start_diagnostic_session(issue_id=1)
```

### SQL Assistant Service (6 packages, 20 modules)
```
sql_assistant/
├── core.py               - Main coordinator
├── schema/               - Database schema (parser, validator, discovery)
├── query/                - SQL lifecycle (extractor, generator, executor, validator)
├── intent/               - Query understanding (classifier, temporal)
├── context/              - State management (session_cache, conversation)
├── judge/                - Quality assessment (llm_judge)
└── prompts/              - Prompt construction (prompt_builder)
```

**Usage:**
```python
service = SQLAssistantService()
response = service.process_query(chat_request)
tables = service.get_available_tables()
```

---

## Individual Module Imports

### SQL Assistant - Schema Package
```python
from app.services.sql_assistant.schema import (
    SchemaParser,      # Schema introspection
    SchemaValidator,   # SQL validation
    SchemaDiscovery    # Schema discovery & JOINs
)
```

### SQL Assistant - Query Package
```python
from app.services.sql_assistant.query import (
    QueryExtractor,    # Extract SQL from text
    QueryGenerator,    # Generate SQL from NL
    QueryExecutor,     # Execute queries safely
    QueryValidator     # Validate query results
)
```

### SQL Assistant - Intent Package
```python
from app.services.sql_assistant.intent import (
    IntentClassifier,    # Classify query intent
    TemporalClassifier   # Detect temporal scope
)
```

### SQL Assistant - Context Package
```python
from app.services.sql_assistant.context import (
    SessionCache,         # Session-based caching
    ConversationContext   # Extract conversation context
)
```

### SQL Assistant - Judge & Prompts
```python
from app.services.sql_assistant.judge import LLMJudge
from app.services.sql_assistant.prompts import PromptBuilder
```

### Diagnostic - Individual Modules
```python
from app.services.diagnostic.text_utils import clean_text, parse_solution_steps
from app.services.diagnostic.csv_loader import CSVLoader
from app.services.diagnostic.issue_search import IssueSearchEngine
from app.services.diagnostic.session_manager import SessionManager
from app.services.diagnostic.report_formatter import ReportFormatter
```

---

## Common Tasks

### 1. Search for Diagnostic Issues
```python
from app.services import DiagnosticSupportService

service = DiagnosticSupportService()
results = service.search_issue("bot not charging", limit=5)
```

### 2. Process SQL Query
```python
from app.services import SQLAssistantService
from app.models.schemas import ChatRequest, ChatbotType

service = SQLAssistantService()
request = ChatRequest(
    message="How many active bots?",
    chatbot_type=ChatbotType.SQL_ASSISTANT,
    session_id="user-123"
)
response = service.process_query(request)
```

### 3. Get Available Tables
```python
from app.services import SQLAssistantService

service = SQLAssistantService()
tables = service.get_available_tables()  # Returns set of 162 tables
```

### 4. Classify Query Intent
```python
from app.services.sql_assistant.intent import IntentClassifier

classifier = IntentClassifier()
intent = classifier.classify_query_intent("How many orders today?")
# Returns: {'intent': 'count', 'entities': ['order'], 'temporal': 'current'}
```

### 5. Validate SQL Query
```python
from app.services.sql_assistant.schema import SchemaValidator
from app.services.sql_assistant.schema import SchemaParser

parser = SchemaParser()
validator = SchemaValidator(parser)

sql = "SELECT * FROM bot_master WHERE status = 'active'"
tables_valid, invalid_tables = validator.validate_sql_tables(sql)
columns_valid, invalid_columns = validator.validate_sql_columns(sql)
```

---

## Testing

### Run Integration Tests
```bash
python test_service_integration.py
```

### Run Server Startup Test
```bash
python test_server_startup.py
```

### Start Development Server
```bash
uvicorn backend.app.main:app --reload
```

---

## File Locations

### Services
- **Diagnostic:** `backend/app/services/diagnostic/`
- **SQL Assistant:** `backend/app/services/sql_assistant/`

### Tests
- **Integration Test:** `test_service_integration.py`
- **Server Test:** `test_server_startup.py`

### Documentation
- **Diagnostic Guide:** `DIAGNOSTIC_SERVICE_REFACTOR_COMPLETE.md`
- **SQL Progress:** `SQL_ASSISTANT_REFACTOR_PROGRESS.md`
- **Integration:** `SERVICE_INTEGRATION_COMPLETE.md`
- **Summary:** `REFACTORING_PROJECT_SUMMARY.md`

---

## Key Methods

### DiagnosticSupportService
- `search_issue(query, limit)` - Search diagnostic issues
- `start_diagnostic_session(issue_id)` - Start diagnostic workflow
- `get_status(session_id)` - Get session status
- `submit_feedback(session_id, feedback)` - Submit user feedback
- `get_statistics()` - Get issue statistics

### SQLAssistantService
- `process_query(chat_request)` - Process natural language query (main entry point)
- `get_available_tables()` - Get all table names
- `get_table_columns(table_name)` - Get columns for table
- `classify_query_intent(query)` - Classify query intent
- `classify_temporal_scope(query)` - Detect temporal scope
- `execute_query_safe(sql)` - Execute SQL safely
- `extract_sql_query(text)` - Extract SQL from text

---

## Tips

### Best Practices
1. **Use new import paths** - Cleaner and more maintainable
2. **Import from services package** - Unified imports
3. **Import specific modules** - When you need fine-grained control
4. **Test locally first** - Run integration tests before deployment
5. **Check logs** - Monitor initialization messages

### Common Patterns
```python
# Pattern 1: Use coordinator for high-level operations
service = SQLAssistantService()
response = service.process_query(request)

# Pattern 2: Use components for specific tasks
from app.services.sql_assistant.intent import IntentClassifier
classifier = IntentClassifier()
intent = classifier.classify_query_intent("Count active bots")

# Pattern 3: Chain components together
from app.services.sql_assistant.schema import SchemaParser, SchemaValidator
parser = SchemaParser()
validator = SchemaValidator(parser)
is_valid, errors = validator.validate_sql_tables("SELECT * FROM bot_master")
```

---

## Troubleshooting

### Import Errors
```python
# Error: ModuleNotFoundError: No module named 'app.services.diagnostic'
# Solution: Check Python path and working directory

import sys
sys.path.insert(0, '/path/to/backend')
```

### Schema Parser Not Found
```python
# Error: No module named 'backend.app.services.utils'
# Fixed: Changed to 'backend.app.utils' in schema/parser.py
```

### Server Won't Start
```bash
# Check for errors
python test_server_startup.py

# Verify imports
python -c "from app.services import DiagnosticSupportService, SQLAssistantService"
```

---

## Quick Stats

- **Total Modules:** 27 files
- **Diagnostic Service:** 7 files, 989 lines
- **SQL Assistant:** 20 files, ~3,000 lines
- **Tables Cached:** 162 database tables
- **Test Coverage:** All 77 methods tested

---

**Last Updated:** December 2024  
**Version:** 2.0.0 (Modular Architecture)
