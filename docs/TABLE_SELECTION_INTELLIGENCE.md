# Table Selection Intelligence Guide

## Problem: How does the system know which table to use based on descriptions?

### Answer: 3-Layer Intelligent Matching System

---

## Layer 1: Validation-Based Learning (Highest Priority - 10× boost)

**How it works:** You manually validate correct/incorrect tables for queries

**Example:**
```
Query: "give me bot locations"

Test → See ranked tables:
#1 dashboard_bot_master (wrong - has LOCK_BY, admin metadata)
#2 bot_master (right - has GRIDX, GRIDY, GRIDZ position)

Action:
- Mark dashboard_bot_master as ✗ Incorrect  
- Mark bot_master as ✓ Correct

Result:
- Saved to table_priority_validations.jsonl
- Next time "bot locations" query → bot_master gets 10× boost
- dashboard_bot_master gets 0.01× penalty
```

**Storage:** `data/database/table_priority_validations.jsonl`
```json
{"query": "give me bot locations", "table_name": "bot_master", "is_correct": true, "timestamp": "..."}
{"query": "give me bot locations", "table_name": "dashboard_bot_master", "is_correct": false, "timestamp": "..."}
```

---

## Layer 2: Description + Column-Aware Matching (TF-IDF + Column Analysis)

**How it works:** System analyzes descriptions AND column names to understand table purpose

### Example 1: Location Queries

**Query:** "show bot locations" or "bot positions" or "where is bot 7"

**Column Patterns Detected:**
- Position columns: `GRIDX`, `GRIDY`, `GRIDZ`, `LOCATION_ID`, `X_COORDINATE`, `Y_COORDINATE`
- Admin columns: `LOCK_BY`, `UNLOCK_BY`, `LOCK_TIMESTAMP`

**Table Analysis:**
```
bot_master:
  Description: "live state (position, battery, status)"  ← "position" keyword
  Columns: GRIDX(int), GRIDY(int), GRIDZ(int)  ← Position columns
  Score: HIGH for location queries

dashboard_bot_master:
  Description: "configuration table (locking, admin)"  ← "configuration" not "position"
  Columns: LOCK_BY(varchar), LOCK_TIMESTAMP(datetime)  ← Admin columns
  Score: LOW for location queries (no position columns)
```

**Matching Logic:**
```python
if "location" in query or "position" in query or "where" in query:
    # Boost tables with position columns
    if "GRIDX" in columns or "LOCATION_ID" in columns:
        score *= 2.0  # Boost position tables
    
    # Penalize tables without position data
    if "LOCK_BY" in columns and "GRIDX" not in columns:
        score *= 0.5  # Penalize admin-only tables
```

### Example 2: Status Queries

**Query:** "show bot status" or "which bots are idle"

**Column Patterns:**
- Status columns: `STATUS`, `STATE`, `ACTIVITY`, `COUNTER`
- Log columns: `LOG_TIMESTAMP`, `ARCHIVED_AT`

**Table Analysis:**
```
bot_master:
  Description: "live state (position, battery, status)"  ← "status" + "live"
  Columns: STATUS(enum), COUNTER(int), AUTO_MANUAL(tinyint)
  Score: HIGH for status queries

bot_master_log:
  Description: "historical log of bot states"  ← "historical" not "live"
  Columns: STATUS(enum), LOG_TIMESTAMP(datetime)
  Score: LOW for current status (historical data)
```

---

## Layer 3: Category Priority Multipliers (Fallback)

**How it works:** Default boost/penalty based on table category

**Categories:**
```
bot_master: 3.0×       → Live bot state (position, status, battery)
station_master: 3.0×   → Live station state
config_master: 1.5×    → Configuration/admin tables (dashboard_bot_master)
log_table: 0.5×        → Historical logs
telemetry_table: 0.2×  → Sensor/teleoperation data
```

**Query Intent Detection:**
```python
# Current state queries
if "current" in query or "now" in query or "latest" in query:
    bot_master: 3.0× → 3.0×  (keep high)
    log_table: 0.5× → 0.2×   (lower further)

# Historical queries  
if "history" in query or "past" in query or "log" in query:
    log_table: 0.5× → 2.0×   (boost logs)
    bot_master: 3.0× → 0.8×  (lower master)
```

---

## Complete Example: "give me bot locations"

### Step 1: Check Validations (Layer 1)
```
Query: "give me bot locations"
Validations found:
  bot_master → Correct (10× boost)
  dashboard_bot_master → Incorrect (0.01× penalty)

Result: bot_master score = baseline × 10 = guaranteed #1
```

### Step 2: No Validations? Use Column Analysis (Layer 2)
```
Query: "give me bot locations"
Keywords detected: ["location"]

Tables analyzed:
1. bot_master
   - Description contains: "position" ✓
   - Has columns: GRIDX, GRIDY, GRIDZ ✓
   - TF-IDF score: 0.45
   - Column boost: ×2.0 (has position columns)
   - Final score: 0.90

2. dashboard_bot_master
   - Description contains: "configuration", "locking"
   - Has columns: LOCK_BY, LOCK_TIMESTAMP
   - TF-IDF score: 0.35
   - Column penalty: ×0.5 (no position columns)
   - Final score: 0.175

3. bot_master_log
   - Description contains: "historical log"
   - Has columns: LOG_TIMESTAMP
   - TF-IDF score: 0.30
   - Query intent penalty: ×0.2 (log for current query)
   - Final score: 0.06

Ranking: #1 bot_master, #2 dashboard_bot_master, #3 bot_master_log
```

### Step 3: Apply Category Multipliers (Layer 3)
```
bot_master (bot_master category): 0.90 × 3.0 = 2.70
dashboard_bot_master (config_master category): 0.175 × 1.5 = 0.26

Final ranking: #1 bot_master (2.70), #2 dashboard_bot_master (0.26)
```

---

## Why Descriptions Matter

Good descriptions help TF-IDF match query keywords:

**Bad Description:**
```
bot_master: "Schema-based summary for bot_master. Key fields: BOT_MASTER_ID..."
```
- Generic, no semantic meaning
- Missing keywords: "position", "live", "current"
- Can't distinguish from dashboard_bot_master

**Good Description:**
```
bot_master: "Robot master and LIVE state (position, battery, alarms, auto/manual). 
Used by allocation, monitoring, and safety logic."
```
- Clear purpose: "LIVE state"
- Mentions "position" → matches location queries
- Keywords: "monitoring", "allocation" → matches operational queries

**Great Description (NEO_Table_Summary 1.csv):**
```
dashboard_bot_master: "Master/configuration table (relatively static reference data). 
Key fields: ID, BOT_ID, LOCK_BY, LOCK_TIMESTAMP, UNLOCK_BY, UNLOCK_TIMESTAMP."
```
- Clear purpose: "configuration" (not operational)
- Mentions: "LOCK_BY" → admin/UI functionality
- Distinguishes from bot_master (live operational data)

---

## Action Items for You

### 1. Use Sync Script (Already Done ✅)
```bash
python scripts/sync_table_descriptions.py
```
Result: 65 verified descriptions copied from NEO_Table_Summary 1.csv

### 2. Validate Critical Queries
Go to: `http://localhost:8000/table_priority_analyzer`

Test and validate:
- "give me bot locations" → ✓ bot_master, ✗ dashboard_bot_master
- "show station locations" → ✓ hw_station_master, ✗ hardware_registered  
- "current bot status" → ✓ bot_master, ✗ bot_master_log
- "bot position history" → ✓ bot_master_log, ✗ bot_master

### 3. Review Descriptions
Go to: `http://localhost:8000/schema`

Check tables without verified descriptions (101 tables need review):
- Tables with "Schema-based summary..." → Need better descriptions
- Add keywords that match common queries

### 4. Monitor and Iterate
- Check validation history
- See which queries are failing
- Add more validations
- Update descriptions for frequently queried tables

---

## Summary

The system combines:
1. **Your manual validations** (10× boost - highest priority)
2. **Smart column analysis** (2× boost for matching column patterns)
3. **Category multipliers** (3× boost for master tables)
4. **Description keywords** (TF-IDF matching with query)

**Result:** Intelligent table selection that learns from your feedback and understands table purpose based on descriptions + columns!
