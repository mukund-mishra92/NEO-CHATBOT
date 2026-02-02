# 🎯 INTEGRATED SQL ASSISTANT - VISUAL FLOW

## Complete End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         USER ASKS: "how many bots are active"               │
└─────────────────────────────────────────────────────────────────────────────┘
                                        ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 1: SESSION CACHE (In-Memory)                                          │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  📍 Location: backend/app/services/sql_assistant_integrated.py:161          │
│  📁 Storage: self.session_query_cache[session_id] (in-memory dict)          │
│                                                                              │
│  ✓ Checks last 10 queries from THIS session                                 │
│  ✓ Similarity matching: 85% threshold (SequenceMatcher)                     │
│  ✓ Column safety check                                                      │
│  ✓ Confidence boost: +10% for cached queries                                │
│                                                                              │
│  IF FOUND → Return cached SQL (confidence ~88-98%) 🎯                       │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ NOT FOUND
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 2: CLASSIFIED QUERIES (JSONL File)                                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  📍 Location: backend/app/services/sql_assistant_integrated.py:195          │
│  📁 Storage: data/classification/classified_queries.jsonl                    │
│  🔧 Service: backend/app/services/query_classification_service.py           │
│                                                                              │
│  ✓ Human-verified correct queries                                           │
│  ✓ Similarity matching: 85% threshold                                       │
│  ✓ High confidence for verified queries                                     │
│  ✓ Formula: min(0.98, 0.85 + (similarity * 0.1))                           │
│                                                                              │
│  IF FOUND → Return classified SQL (confidence ~85-98%) 📚                   │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ NOT FOUND
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 3: CHAT HISTORY (MySQL Database)                                      │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  📍 Location: backend/app/services/sql_assistant_integrated.py:229          │
│  📁 Storage: MySQL tables (chat_interactions, sql_queries, query_patterns)  │
│  🔧 Service: backend/app/services/chat_history_service.py                   │
│                                                                              │
│  ✓ Pattern learning from past successes                                     │
│  ✓ Similarity matching: 80% threshold                                       │
│  ✓ Frequency + confidence scoring                                           │
│  ✓ Formula: 0.65 + (similarity*0.15) + (frequency*0.05)                    │
│                                                                              │
│  IF FOUND → Return historical pattern (confidence ~70-90%) 📊               │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ NOT FOUND
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 4: GENERATE NEW SQL                                                   │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  📍 Location: backend/app/services/sql_assistant_integrated.py:814-908      │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ STEP 4a: nl_to_sql_generator.py (PRIORITY ⭐)                        │  │
│  │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │  │
│  │ 📍 Method: _generate_sql_with_nl_generator():265                     │  │
│  │ 🤖 Generator: backend/app/services/nl_to_sql_generator.py            │  │
│  │ 📁 Schema: data/database/Table_information.csv                        │  │
│  │                                                                        │  │
│  │ ✓ CSV-based schema retrieval                                          │  │
│  │ ✓ TF-IDF table matching (top 8 relevant tables)                       │  │
│  │ ✓ OpenAI structured output generation                                 │  │
│  │ ✓ Returns: {sql, confidence, tables_used, columns_used, ...}         │  │
│  │                                                                        │  │
│  │ Combined Confidence = (generator * 0.6) + (validation * 0.4)          │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              ↓                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ STEP 4b: RETRY WITH FEEDBACK (Max 3 Attempts)                        │  │
│  │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │  │
│  │ 📍 Loop: Lines 827-893                                                │  │
│  │                                                                        │  │
│  │ FOR attempt in range(1, 4):                                           │  │
│  │   1. Generate SQL with nl_to_sql_generator                            │  │
│  │   2. Execute query → Check for errors                                 │  │
│  │   3. Validate results → Calculate confidence                          │  │
│  │                                                                        │  │
│  │   DECISION:                                                            │  │
│  │   • confidence >= 94% → 🚀 HIGH - Use immediately!                   │  │
│  │   • confidence >= 75% → ✅ ACCEPTABLE - Use result                   │  │
│  │   • confidence < 75%  → ⚠️ LOW - Retry with feedback                │  │
│  │   • Last attempt      → Use anyway (even if low)                     │  │
│  │                                                                        │  │
│  │ Feedback passed to next attempt:                                      │  │
│  │   "Low confidence (0.65): No results returned - query too restrictive"│  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              ↓ ALL FAILED                                    │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ STEP 4c: LLM FALLBACK (Only if nl_to_sql fails)                      │  │
│  │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │  │
│  │ 📍 Method: _generate_sql_with_llm():327                               │  │
│  │ 🔧 Service: backend/app/services/llm_service.py                       │  │
│  │ 📁 Schema: backend/utils/schema_parser.py                             │  │
│  │                                                                        │  │
│  │ Triggers when:                                                         │  │
│  │ • No SQL generated after 3 nl_to_sql attempts                         │  │
│  │ • OR confidence < 30% after all attempts                              │  │
│  │                                                                        │  │
│  │ Strategies (try in order):                                             │  │
│  │ 1. 'direct': Simple conversion                                        │  │
│  │ 2. 'with_context': Full context prompt                                │  │
│  │ 3. 'simplified': Basic query                                          │  │
│  │                                                                        │  │
│  │ Uses OpenAI API with dynamic schema (max 8 tables)                    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ SQL GENERATED
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 5: EXECUTE & VALIDATE                                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  📍 Location: backend/app/services/sql_assistant_integrated.py              │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 5a. EXECUTE SAFELY (_execute_query_safe:487)                         │  │
│  │                                                                        │  │
│  │ Security Checks:                                                       │  │
│  │ ❌ DROP, DELETE, TRUNCATE, ALTER, CREATE, INSERT, UPDATE             │  │
│  │                                                                        │  │
│  │ Execution:                                                             │  │
│  │ • pymysql connection with 5-second timeout                            │  │
│  │ • pandas read_sql for results                                         │  │
│  │ • Returns: (results_list, error_message)                              │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              ↓                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 5b. VALIDATE RESULTS (_validate_results:532)                         │  │
│  │                                                                        │  │
│  │ Checks:                                                                │  │
│  │ • Results exist? (+0.1 confidence)                                    │  │
│  │ • Reasonable count 1-1000? (+0.15 confidence)                         │  │
│  │ • 70% non-null data? (+0.15 confidence)                               │  │
│  │ • Column names present? (+0.10 confidence)                            │  │
│  │                                                                        │  │
│  │ Base: 0.5 → Max: 0.95                                                 │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ VALIDATED
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 6: STORE FOR FUTURE REUSE                                             │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  📍 Location: backend/app/services/sql_assistant_integrated.py:931-982      │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 6a. SESSION CACHE (In-Memory) - _store_successful_query:577          │  │
│  │                                                                        │  │
│  │ Stores:                                                                │  │
│  │ • question, sql, results_count, confidence                            │  │
│  │ • sample_data (first 3 rows)                                          │  │
│  │ • timestamp                                                            │  │
│  │                                                                        │  │
│  │ 💾 self.session_query_cache[session_id] (keeps last 10)              │  │
│  │ → Used by STEP 1 for future queries                                  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              ↓                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 6b. CLASSIFIED QUERIES (JSONL) - Only if confidence >= 85%           │  │
│  │                                                                        │  │
│  │ Service: query_classification_service.store_query()                   │  │
│  │                                                                        │  │
│  │ 📁 data/classification/classified_queries.jsonl                        │  │
│  │ Format: {"query": "...", "sql": "...", "confidence": 0.89}           │  │
│  │                                                                        │  │
│  │ → Used by STEP 2 for future queries                                  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              ↓                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 6c. CHAT HISTORY (MySQL Database)                                    │  │
│  │                                                                        │  │
│  │ Service: chat_history_service                                         │  │
│  │                                                                        │  │
│  │ Tables Updated:                                                        │  │
│  │ 1. chat_interactions → log_chat_interaction()                        │  │
│  │    • session_id, user_query, response, confidence, time              │  │
│  │                                                                        │  │
│  │ 2. sql_queries → log_sql_query()                                     │  │
│  │    • chat_id, sql, status, rows, tables, columns                     │  │
│  │                                                                        │  │
│  │ 3. query_patterns → update_query_pattern()                           │  │
│  │    • intent, entity_table mappings, frequency, confidence            │  │
│  │                                                                        │  │
│  │ → Used by STEP 3 for pattern matching                                │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                              ↓ STORED
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RETURN FORMATTED RESPONSE                            │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  📍 Method: _format_results:1002                                             │
│                                                                              │
│  Response includes:                                                          │
│  • Source indicator (💾 cache / 📚 classified / 🤖 nl_to_sql / 🔄 llm)      │
│  • Results (all if ≤10, first 5 if >10)                                     │
│  • SQL query in markdown code block                                         │
│  • Confidence percentage                                                    │
│                                                                              │
│  Returns: ChatResponse with metadata                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 🎯 Key Decision Points

### High Confidence Fast Path (94%)
```
If confidence >= 94%:
  🚀 Skip validation
  🚀 Return immediately
  🚀 Store in all 3 locations
```

### Acceptable Confidence (75%)
```
If 75% <= confidence < 94%:
  ✅ Use result
  ✅ Execute validation
  ✅ Store in all 3 locations
```

### Low Confidence (<75%)
```
If confidence < 75%:
  ⚠️ Retry with feedback (max 3 attempts)
  ⚠️ On last attempt: use anyway
  ⚠️ If all fail: fallback to LLM
```

## 📊 Confidence Calculation

### nl_to_sql_generator Confidence
```
Generator confidence: 0-1.0 (from nl_to_sql_generator.py)
Validation confidence: 0-1.0 (from _validate_results)

Combined = (generator * 0.6) + (validation * 0.4)
```

### Cache Confidence Boost
```
Session cache: base + 10% → min(0.98, base + 0.10)
Classified queries: 0.85 + (similarity * 0.1)
Chat history: 0.65 + (similarity * 0.15) + (frequency * 0.05)
```

## 🔍 Similarity Thresholds

```
Step 1 - Session Cache:       85% (SequenceMatcher)
Step 2 - Classified Queries:  85% (SequenceMatcher)
Step 3 - Chat History:        80% (SequenceMatcher)
```

## 📁 Storage Summary

| Step | Location | Format | Purpose |
|------|----------|--------|---------|
| 1 | In-Memory | Dict | Fast session-level cache |
| 2 | JSONL File | Text | Human-verified queries |
| 3 | MySQL | Database | Pattern learning & history |

## 🚀 Performance Optimizations

1. **Session Cache First** - Fastest (in-memory lookup)
2. **High Confidence Fast Path** - Skip validation if >94%
3. **Early Return** - Stop checking if match found
4. **Max 3 Retries** - Prevent infinite loops
5. **LLM Fallback Only** - Use only if CSV generator fails

## 📝 File Reference Quick Access

```python
# Main Service
backend/app/services/sql_assistant_integrated.py    # 1089 lines

# Supporting Services
backend/app/services/nl_to_sql_generator.py         # CSV-based generator
backend/app/services/llm_service.py                 # LLM fallback
backend/app/services/chat_history_service.py        # MySQL logging
backend/app/services/query_classification_service.py # JSONL management

# Storage Files
data/classification/classified_queries.jsonl        # Human-verified queries
data/database/Table_information.csv                 # Schema for nl_to_sql

# Documentation
docs/INTEGRATED_SQL_ASSISTANT_FLOW.md              # Detailed flow
docs/INTEGRATED_SQL_ASSISTANT_SUMMARY.md           # Quick summary
```
