# NEO Chatbot - Data Storage

## MySQL Database Tables

### 1. `chatbot_chat_history`
**Purpose:** Main conversation log  
**Columns:** chat_id (PK), session_id, chatbot_type, user_query, assistant_response, timestamp, confidence_score, response_time_ms  
**Indexes:** session_id, chatbot_type, timestamp

### 2. `chatbot_sql_queries`
**Purpose:** SQL query generation tracking  
**Columns:** id (PK), chat_id (FK), session_id, user_query, generated_sql, execution_status, error_message, rows_returned, execution_time_ms, tables_used, columns_used, intent, entities, timestamp  
**Indexes:** chat_id, session_id, execution_status, timestamp

### 3. `chatbot_column_corrections`
**Purpose:** Automatic column name corrections (learning)  
**Columns:** id (PK), chat_id, session_id, table_name, wrong_column, correct_column, correction_type, similarity_score, timestamp  
**Indexes:** chat_id, table_name, wrong_column, timestamp

### 4. `chatbot_feedback`
**Purpose:** User feedback on responses  
**Columns:** id (PK), chat_id (FK), session_id, feedback_type, rating, comment, feedback_category, timestamp  
**Indexes:** chat_id, feedback_type, timestamp

### 5. `chatbot_query_patterns`
**Purpose:** Learned query patterns (RLHF)  
**Columns:** id (PK), pattern_type, pattern_key, pattern_value, frequency, success_rate, avg_confidence, last_used, created_at, updated_at  
**Indexes:** pattern_type, frequency, success_rate

---

## File-Based Storage (JSON/JSONL)

### Vector Store
**File:** `data/vector_store.json`  
**Purpose:** Document embeddings for RAG (Retrieval-Augmented Generation)  
**Format:** JSON array with id, content, embedding, metadata  
**Size:** ~434 MB

### RLHF Data
**Files:**
- `data/rlhf/feedback_history.jsonl` - User feedback history
- `data/rlhf/reward_model.json` - Reward model weights
- `data/rlhf/learned_patterns.json` - Learned patterns from feedback

### Feedback
**File:** `data/database/query_feedback.jsonl`  
**Purpose:** SQL query feedback logs

### Diagnostic Support
**File:** `data/support/issues.json` (optional)  
**Purpose:** Known issues and solutions database

---

## Configuration Notes

- MySQL tables are **optional** - chatbot works without database (in-memory sessions only)
- File-based storage is **required** for core functionality (vector store)
- If MySQL is unavailable, chat history and feedback features are disabled gracefully
