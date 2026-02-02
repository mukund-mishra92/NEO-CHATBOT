# INTEGRATED SQL ASSISTANT SERVICE - COMPLETE FLOW DIAGRAM
## File: backend/app/services/sql_assistant_integrated.py

```
USER ASKS: "how many bots are active"
    ↓
┌───────────────────────────────────────────────────────────────────────────────┐
│ ENTRY POINT: process_query() - Line 731                                      │
│ File: backend/app/services/sql_assistant_integrated.py                       │
│ • Creates/retrieves session                                                  │
│ • Validates database connection                                              │
│ • Extracts conversation context                                              │
└───────────────────────────────────────────────────────────────────────────────┘
    ↓
┌───────────────────────────────────────────────────────────────────────────────┐
│ STEP 1: CHECK SESSION CACHE (In-Memory)                                      │
│ Method: _check_session_cache() - Line 161                                    │
│ File: backend/app/services/sql_assistant_integrated.py                       │
│                                                                               │
│ What it does:                                                                 │
│ • Checks last 10 queries from THIS session                                   │
│ • Uses SequenceMatcher for similarity (85% threshold)                        │
│ • Boosts confidence by +10% for cached queries                               │
│                                                                               │
│ Storage Location:                                                             │
│ • self.session_query_cache: Dict[str, List[Dict]]  (in-memory)              │
│ • Keeps only last 10 queries per session                                     │
│                                                                               │
│ Returns: (sql, confidence, metadata) if similarity >= 85%                    │
└───────────────────────────────────────────────────────────────────────────────┘
    ↓ NOT FOUND (similarity < 85%)
┌───────────────────────────────────────────────────────────────────────────────┐
│ STEP 2: CHECK CLASSIFIED QUERIES (JSONL File)                                │
│ Method: _check_classified_queries() - Line 195                               │
│ File: backend/app/services/sql_assistant_integrated.py                       │
│                                                                               │
│ What it does:                                                                 │
│ • Loads human-verified correct queries from JSONL file                       │
│ • Uses SequenceMatcher for similarity (85% threshold)                        │
│ • High confidence for human-verified + similarity boost                      │
│ • Formula: min(0.98, 0.85 + (similarity * 0.1))                             │
│                                                                               │
│ Storage Location:                                                             │
│ • data/classification/classified_queries.jsonl                                │
│ • Each line: {"query": "...", "sql": "...", "category": "..."}              │
│                                                                               │
│ Service Used:                                                                 │
│ • backend/app/services/query_classification_service.py                       │
│ • Method: get_classified_queries()                                           │
│                                                                               │
│ Returns: (sql, confidence, metadata) if similarity >= 85%                    │
└───────────────────────────────────────────────────────────────────────────────┘
    ↓ NOT FOUND (similarity < 85%)
┌───────────────────────────────────────────────────────────────────────────────┐
│ STEP 3: CHECK CHAT HISTORY (MySQL Database)                                  │
│ Method: _check_chat_history_patterns() - Line 229                            │
│ File: backend/app/services/sql_assistant_integrated.py                       │
│                                                                               │
│ What it does:                                                                 │
│ • Queries MySQL for successful past patterns                                 │
│ • Gets queries with min 75% confidence, checks top 50                        │
│ • Uses similarity matching (80% threshold)                                   │
│ • Scores based on: similarity + frequency + historical confidence            │
│ • Formula: min(0.90, 0.65 + (similarity*0.15) + (frequency*0.05))          │
│                                                                               │
│ Database Tables:                                                              │
│ • chat_interactions: Main conversation log                                   │
│ • sql_queries: SQL generation details                                        │
│ • query_patterns: Pattern learning (intent, entity_table mappings)          │
│                                                                               │
│ Service Used:                                                                 │
│ • backend/app/services/chat_history_service.py                               │
│ • Method: get_successful_query_patterns()                                    │
│                                                                               │
│ Returns: (sql, confidence, metadata) if similarity >= 80%                    │
└───────────────────────────────────────────────────────────────────────────────┘
    ↓ NOT FOUND (no pattern match)
┌───────────────────────────────────────────────────────────────────────────────┐
│ STEP 4: GENERATE NEW SQL                                                     │
│ Location: process_query() - Lines 814-908                                    │
│ File: backend/app/services/sql_assistant_integrated.py                       │
│                                                                               │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ STEP 4a: TRY nl_to_sql_generator.py (PRIORITY - CSV-based)             │ │
│ │ Method: _generate_sql_with_nl_generator() - Line 265                   │ │
│ │ File: backend/app/services/sql_assistant_integrated.py                 │ │
│ │                                                                         │ │
│ │ Generator Implementation:                                               │ │
│ │ • backend/app/services/nl_to_sql_generator.py (209 lines)             │ │
│ │ • Uses TF-IDF for table retrieval from CSV schema                      │ │
│ │ • OpenAI structured output for SQL generation                          │ │
│ │ • Returns: {sql, confidence, tables_used, columns_used, etc.}         │ │
│ │                                                                         │ │
│ │ Schema Source:                                                          │ │
│ │ • data/database/Table_information.csv                                   │ │
│ │ • Format: Table_name, Table_description, Columns, Primary_key         │ │
│ │                                                                         │ │
│ │ Confidence Calculation:                                                 │ │
│ │ • Generator confidence (from nl_to_sql_generator): 0-1.0              │ │
│ │ • Validation confidence (from execution): 0-1.0                        │ │
│ │ • Combined: (generator * 0.6) + (validation * 0.4)                    │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│     ↓                                                                         │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ STEP 4b: RETRY WITH FEEDBACK (Up to 3 attempts)                        │ │
│ │ Loop: Lines 827-893                                                     │ │
│ │                                                                         │ │
│ │ Retry Logic:                                                            │ │
│ │ • Attempt 1: Generate with nl_to_sql_generator                         │ │
│ │ • Execute query → If error: feedback = error message                   │ │
│ │ • Validate results → Calculate combined confidence                     │ │
│ │                                                                         │ │
│ │ Decision Points:                                                        │ │
│ │ • confidence >= 94% → 🚀 HIGH CONFIDENCE - Use immediately!           │ │
│ │ • confidence >= 75% → ✅ ACCEPTABLE - Use result                       │ │
│ │ • confidence < 75%  → ⚠️ LOW - Retry with feedback                    │ │
│ │ • Last attempt      → Use result anyway (even if low)                 │ │
│ │                                                                         │ │
│ │ Feedback Format:                                                        │ │
│ │ • "Low confidence (0.65): No results returned - query too restrictive" │ │
│ │ • "Database error: Unknown column 'bot_status' in 'where clause'"     │ │
│ │ • Passed to nl_to_sql_generator for next attempt                       │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│     ↓                                                                         │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ STEP 4c: FALLBACK TO LLM (If all nl_to_sql attempts fail)             │ │
│ │ Method: _generate_sql_with_llm() - Line 327                            │ │
│ │ File: backend/app/services/sql_assistant_integrated.py                 │ │
│ │                                                                         │ │
│ │ Trigger Conditions:                                                     │ │
│ │ • No SQL generated after 3 nl_to_sql attempts                          │ │
│ │ • OR confidence < 30% after all attempts                               │ │
│ │                                                                         │ │
│ │ LLM Strategies (try in order):                                          │ │
│ │ • 'direct': Simple "Convert to SQL: {question}"                        │ │
│ │ • 'with_context': Full prompt with context                             │ │
│ │ • 'simplified': "Generate simple SQL..."                               │ │
│ │                                                                         │ │
│ │ Service Used:                                                           │ │
│ │ • backend/app/services/llm_service.py                                  │ │
│ │ • Method: generate_response()                                          │ │
│ │ • Uses OpenAI API with dynamic schema prompt                           │ │
│ │                                                                         │ │
│ │ Schema Selection:                                                       │ │
│ │ • Method: _get_relevant_schema() - Line 373                            │ │
│ │ • Scores tables by keyword matches (max 8 tables)                      │ │
│ │ • Source: backend/utils/schema_parser.py                               │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
    ↓
┌───────────────────────────────────────────────────────────────────────────────┐
│ STEP 5: EXECUTE & VALIDATE                                                   │
│ File: backend/app/services/sql_assistant_integrated.py                       │
│                                                                               │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ 5a. Execute Query Safely                                                │ │
│ │ Method: _execute_query_safe() - Line 487                               │ │
│ │                                                                         │ │
│ │ Security Checks:                                                        │ │
│ │ • Block: DROP, DELETE, TRUNCATE, ALTER, CREATE, INSERT, UPDATE        │ │
│ │ • Uses regex patterns with word boundaries                             │ │
│ │                                                                         │ │
│ │ Execution:                                                              │ │
│ │ • Uses pymysql connection                                              │ │
│ │ • Timeout: 5 seconds                                                   │ │
│ │ • Returns: (results_list, error_message)                               │ │
│ │                                                                         │ │
│ │ Database Config:                                                        │ │
│ │ • From app.core.config.settings                                        │ │
│ │ • Host: settings.DB_HOST                                               │ │
│ │ • Database: settings.DB_NAME (neo)                                     │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│     ↓                                                                         │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ 5b. Validate Results                                                    │ │
│ │ Method: _validate_results() - Line 532                                 │ │
│ │                                                                         │ │
│ │ Validation Checks:                                                      │ │
│ │ • Results exist? (0.1 points)                                          │ │
│ │ • Reasonable count (1-1000)? (0.15 points)                             │ │
│ │ • Has meaningful data (70% non-null)? (0.15 points)                    │ │
│ │ • Column names present? (0.10 points)                                  │ │
│ │ • Base confidence: 0.5                                                 │ │
│ │                                                                         │ │
│ │ Returns:                                                                │ │
│ │ • Confidence score: 0.0-0.95                                           │ │
│ │ • Validation message: "✅ 5 results | ✅ reasonable count | ..."       │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
    ↓
┌───────────────────────────────────────────────────────────────────────────────┐
│ STEP 6: STORE FOR FUTURE REUSE                                               │
│ File: backend/app/services/sql_assistant_integrated.py                       │
│ Location: process_query() - Lines 931-982                                    │
│                                                                               │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ 6a. Store in Session Cache (In-Memory)                                 │ │
│ │ Method: _store_successful_query() - Line 577                           │ │
│ │                                                                         │ │
│ │ Stored Data:                                                            │ │
│ │ • question: Original user question                                     │ │
│ │ • sql: Generated SQL query                                             │ │
│ │ • results_count: Number of rows returned                               │ │
│ │ • confidence: Final confidence score                                   │ │
│ │ • sample_data: First 3 rows of results                                 │ │
│ │ • timestamp: ISO format datetime                                       │ │
│ │                                                                         │ │
│ │ Storage:                                                                │ │
│ │ • self.session_query_cache[session_id] (in-memory dict)               │ │
│ │ • Keeps only last 10 queries per session                               │ │
│ │ • Used by STEP 1 for future lookups                                    │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│     ↓                                                                         │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ 6b. Store in Classified Queries (JSONL File)                           │ │
│ │ Condition: confidence >= 85%                                            │ │
│ │                                                                         │ │
│ │ Service:                                                                │ │
│ │ • backend/app/services/query_classification_service.py                 │ │
│ │ • Method: store_query()                                                │ │
│ │                                                                         │ │
│ │ File Location:                                                          │ │
│ │ • data/classification/classified_queries.jsonl                          │ │
│ │                                                                         │ │
│ │ Format (each line):                                                     │ │
│ │ {                                                                       │ │
│ │   "id": 35,                                                             │ │
│ │   "query": "how many bots are active",                                 │ │
│ │   "sql": "SELECT COUNT(*) FROM bot_master WHERE status='active'",     │ │
│ │   "category": "auto_classified",                                       │ │
│ │   "confidence": 0.89,                                                  │ │
│ │   "timestamp": "2026-02-02T10:30:00"                                   │ │
│ │ }                                                                       │ │
│ │                                                                         │ │
│ │ Used by: STEP 2 for future lookups                                     │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│     ↓                                                                         │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ 6c. Store in Chat History (MySQL Database)                             │ │
│ │                                                                         │ │
│ │ Service:                                                                │ │
│ │ • backend/app/services/chat_history_service.py                         │ │
│ │                                                                         │ │
│ │ Tables Updated:                                                         │ │
│ │ ┌─────────────────────────────────────────────────────────┐           │ │
│ │ │ 1. chat_interactions                                    │           │ │
│ │ │    Method: log_chat_interaction()                      │           │ │
│ │ │    Columns:                                             │           │ │
│ │ │    • session_id, chatbot_type, user_query             │           │ │
│ │ │    • assistant_response, confidence_score              │           │ │
│ │ │    • response_time_ms, created_at                      │           │ │
│ │ │    Returns: chat_id (for linking other tables)        │           │ │
│ │ └─────────────────────────────────────────────────────────┘           │ │
│ │         ↓                                                               │ │
│ │ ┌─────────────────────────────────────────────────────────┐           │ │
│ │ │ 2. sql_queries                                          │           │ │
│ │ │    Method: log_sql_query()                             │           │ │
│ │ │    Columns:                                             │           │ │
│ │ │    • chat_id (FK), session_id, user_query              │           │ │
│ │ │    • generated_sql, execution_status                   │           │ │
│ │ │    • rows_returned, execution_time_ms                  │           │ │
│ │ │    • tables_used, columns_used                         │           │ │
│ │ │    • intent, entities, created_at                      │           │ │
│ │ └─────────────────────────────────────────────────────────┘           │ │
│ │         ↓                                                               │ │
│ │ ┌─────────────────────────────────────────────────────────┐           │ │
│ │ │ 3. query_patterns                                       │           │ │
│ │ │    Method: update_query_pattern()                      │           │ │
│ │ │    Columns:                                             │           │ │
│ │ │    • pattern_type (intent, entity_table)               │           │ │
│ │ │    • pattern_key (e.g., "bot_status", "active")        │           │ │
│ │ │    • pattern_value (e.g., "bot_master,task_log")       │           │ │
│ │ │    • success_count, total_count                        │           │ │
│ │ │    • avg_confidence, last_used_at                      │           │ │
│ │ │                                                         │           │ │
│ │ │    Used for: Pattern learning and frequency scoring    │           │ │
│ │ └─────────────────────────────────────────────────────────┘           │ │
│ │                                                                         │ │
│ │ Purpose: Used by STEP 3 for pattern matching                           │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
    ↓
┌───────────────────────────────────────────────────────────────────────────────┐
│ RETURN FORMATTED RESPONSE                                                     │
│ Method: _format_results() - Line 1002                                        │
│ File: backend/app/services/sql_assistant_integrated.py                       │
│                                                                               │
│ Response Format:                                                              │
│ • Source indicator (💾 cache / 📚 classified / 🤖 nl_to_sql / 🔄 llm)        │
│ • Results (all if ≤10, first 5 if >10)                                       │
│ • SQL query in code block                                                    │
│ • Confidence percentage                                                      │
│                                                                               │
│ Returns: ChatResponse with metadata                                          │
└───────────────────────────────────────────────────────────────────────────────┘
```

## VALIDATION CHECKLIST

### Step 1: Session Cache
**File to check:** `backend/app/services/sql_assistant_integrated.py`
- Line 161: `_check_session_cache()` method
- Line 577: `_store_successful_query()` method  
- Storage: `self.session_query_cache` dictionary (in-memory)

### Step 2: Classified Queries
**Files to check:**
1. `backend/app/services/sql_assistant_integrated.py` - Line 195
2. `backend/app/services/query_classification_service.py`
3. `data/classification/classified_queries.jsonl` - Storage file

### Step 3: Chat History
**Files to check:**
1. `backend/app/services/sql_assistant_integrated.py` - Line 229
2. `backend/app/services/chat_history_service.py`
3. MySQL database tables:
   - `chat_interactions`
   - `sql_queries`
   - `query_patterns`

### Step 4a: nl_to_sql_generator (PRIORITY)
**Files to check:**
1. `backend/app/services/sql_assistant_integrated.py` - Line 265
2. `backend/app/services/nl_to_sql_generator.py` - The generator
3. `data/database/Table_information.csv` - Schema source

### Step 4b: Retry with Feedback
**File to check:** `backend/app/services/sql_assistant_integrated.py`
- Lines 827-893: Retry loop in `process_query()`
- Line 153: `high_confidence_threshold = 0.94`
- Line 154: `acceptable_confidence_threshold = 0.75`
- Line 148: `max_retry_attempts = 3`

### Step 4c: LLM Fallback
**Files to check:**
1. `backend/app/services/sql_assistant_integrated.py` - Line 327
2. `backend/app/services/llm_service.py`
3. `backend/utils/schema_parser.py`

### Step 5: Execute & Validate
**File to check:** `backend/app/services/sql_assistant_integrated.py`
- Line 487: `_execute_query_safe()` method
- Line 532: `_validate_results()` method

### Step 6: Storage
**Files to check:**
1. Session cache: Line 577 in `sql_assistant_integrated.py`
2. Classified queries: `query_classification_service.py` (store_query method)
3. Chat history: `chat_history_service.py` (log methods)

## KEY CONFIGURATION VALUES

```python
# backend/app/services/sql_assistant_integrated.py - Line 148-156

max_retry_attempts = 3                          # Maximum retry attempts
high_confidence_threshold = 0.94                # Skip validation above this
acceptable_confidence_threshold = 0.75          # Minimum to return results
session_cache_similarity_threshold = 0.85       # Session cache matching
classified_query_similarity_threshold = 0.85    # Classified query matching
```

## TESTING COMMANDS

```powershell
# Test the integrated service
.\venv\Scripts\python.exe -c "from backend.app.services.sql_assistant_integrated import SQLAssistantService; service = SQLAssistantService(); print('✅ Service initialized successfully')"

# Check if nl_to_sql_generator is available
.\venv\Scripts\python.exe -c "from backend.app.services.sql_assistant_integrated import SQLAssistantService; service = SQLAssistantService(); print(f'nl_to_sql_generator available: {service.nl_sql_generator is not None}')"

# Verify all dependencies
.\venv\Scripts\python.exe -c "from backend.app.services.sql_assistant_integrated import SQLAssistantService; service = SQLAssistantService(); print(f'Vector store: {service.vector_store is not None}'); print(f'Chat history: {service.chat_history_service is not None}'); print(f'Classification: {service.classification_service is not None}')"
```
