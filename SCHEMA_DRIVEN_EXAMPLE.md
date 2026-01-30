# Example: What the LLM Sees Now (Schema-Driven)

## User Query: "show me bot 32 status"

---

## System Prompt (Before - Old Way)

```
You are a SQL expert for the NEO Warehouse Management System.

⚠️⚠️⚠️ CRITICAL: COLUMN NAMES & VALUES ⚠️⚠️⚠️
IMPORTANT KEY TABLE SCHEMAS:

bot_master:
  - ⚠️ CRITICAL: NO BOT_NUMBER COLUMN EXISTS!
  - Primary identifier: BOT_ID (varchar, e.g., 'BOT_001', 'BOT_032')
  - Actual columns: BOT_MASTER_ID, BOT_ID, STATUS, COUNTER, AUTO_MANUAL, BATTERY, BATTERY_HEALTH, 
    IP, PORT, GRIDX, GRIDY, GRIDZ, LOAD_CONDITION, UPDATED_TIMESTAMP, ALARM, etc.
  - ⚠️ Use 'STATUS' NOT 'bot_status'
  - ⚠️ STATUS values: 'ENABLED', 'DISABLED' (NOT 'active'/'inactive')
  - ⚠️ For bot lookups by number: Use BOT_ID with pattern matching (e.g., WHERE BOT_ID LIKE '%32%')

[... 500+ more lines of generic schema info ...]
```

**Problems:**
- ❌ Descriptive, not binding ("use STATUS not bot_status")
- ❌ Mixed with 100+ other tables
- ❌ LLM can ignore warnings
- ❌ Enum values mentioned but not enforced
- ❌ No explicit "these are your ONLY choices"

---

## System Prompt (After - New Way)

```
You are a SQL expert for the NEO Warehouse Management System.

================================================================================
🔒 BINDING SCHEMA CONSTRAINTS (YOU MUST FOLLOW THESE)
================================================================================

⚠️ CRITICAL: You MUST ONLY use tables, columns, and values listed below.
Guessing column names or enum values will cause query failure.

📊 ALLOWED TABLES FOR THIS QUERY: 8
  ✓ bot_master                    ← START HERE
  ✓ bot_master_log
  ✓ bot_alarm_log
  ✓ dashboard_bot_master
  ✓ bot_charging_bit_log
  ✓ robot_charge_log
  ✓ bot_manual_alarm_log
  ✓ dashboard_log_bot_charging

--------------------------------------------------------------------------------

🗂️  TABLE: bot_master
   Primary Key: BOT_MASTER_ID
   Allowed Columns (33):
     • BOT_MASTER_ID (int)
     • BOT_ID (varchar(50))                                    ← Use this for "bot 32"
     • STATUS (enum('ENABLED','DISABLED')) → ONLY: ['ENABLED', 'DISABLED']  ← These are your ONLY choices
     • COUNTER (int)
     • AUTO_MANUAL (enum('auto','manual')) → ONLY: ['auto', 'manual']
     • ACTIVITY_REQUEST (tinyint)
     • BATTERY (double)
     • BATTERY_HEALTH (enum('GOOD','AVERAGE','CRITICAL')) → ONLY: ['GOOD', 'AVERAGE', 'CRITICAL']
     • IP (varchar(200))
     • PORT (int)
     • SIM_PORT (int)
     • GRIDX (int)
     • GRIDY (int)
     • GRIDZ (double)
     • ACTIVE_AXIS (int)
     • LOAD_CONDITION (enum('UL','LD')) → ONLY: ['UL', 'LD']
     • UPDATED_TIMESTAMP (timestamp)
     • ALARM (int)
     • ALARM_TYPE (enum('NORMAL','MAINTENANCE','PSEUDO')) → ONLY: ['NORMAL', 'MAINTENANCE', 'PSEUDO']
     • RECOVERY_BIN_LOAD_STATUS (tinyint)
     ... and 13 more columns

🗂️  TABLE: bot_master_log
   Allowed Columns (26):
     • BOT_MASTER_LOG_ID (bigint)
     • BOT_MASTER_ID (int)
     • BOT_ID (varchar(50))
     • STATUS (enum('ENABLED','DISABLED')) → ONLY: ['ENABLED', 'DISABLED']
     • COUNTER (int)
     • AUTO_MANUAL (enum('auto','manual')) → ONLY: ['auto', 'manual']
     ... (20 more columns)

[... 3 more tables with exact columns ...]

================================================================================
⚠️ DO NOT use any columns or values NOT listed above!
⚠️ If you need a column not listed, ASK USER for clarification first.
================================================================================

[Rest of system prompt continues...]
```

**Improvements:**
- ✅ Binding, not descriptive ("ONLY: ['ENABLED', 'DISABLED']")
- ✅ Context-specific (only 8 bot-related tables, not all 200)
- ✅ Explicit constraints (can't ignore, structured format)
- ✅ Enum values are a closed list
- ✅ Clear hierarchy: tables → columns → allowed values

---

## LLM Decision Process

### Old Way (Reactive)
```
Query: "show me bot 32 status"
LLM thinks:
  - "bot 32" probably means WHERE BOT_NUMBER = 32  ← GUESSING
  - "status" probably means SELECT bot_status       ← GUESSING
  - Sees warning about BOT_NUMBER but generates query anyway
Generates: SELECT bot_status FROM bot_master WHERE BOT_NUMBER = 32
Validation: ❌ FAIL - no BOT_NUMBER column, no bot_status column
Retry with corrections...
```

### New Way (Proactive)
```
Query: "show me bot 32 status"
LLM sees:
  - ALLOWED TABLES: bot_master ← start here
  - bot_master columns: 
      BOT_ID (varchar) ← use this for "bot 32"
      STATUS (enum) → ONLY: ['ENABLED', 'DISABLED'] ← use this for "status"
  - No BOT_NUMBER in the list!
  - No bot_status in the list!
LLM thinks:
  - Must use BOT_ID for bot identifier (it's the only ID column listed)
  - Must use STATUS for status (exact column name in list)
  - Pattern matching needed: BOT_ID LIKE '%32%'
Generates: SELECT BOT_ID, STATUS FROM bot_master WHERE BOT_ID LIKE '%32%'
Validation: ✅ SUCCESS - first attempt
```

---

## Real-World Example

### Query: "show enabled bots"

**Old Prompt (500+ lines, all tables):**
```
bot_master STATUS values: 'ENABLED', 'DISABLED' (NOT 'active'/'inactive')
```
→ LLM might still try `WHERE status = 'active'` (ignores warning)

**New Prompt (8 tables, explicit):**
```
bot_master:
  • STATUS (enum('ENABLED','DISABLED')) → ONLY: ['ENABLED', 'DISABLED']
```
→ LLM MUST choose from ['ENABLED', 'DISABLED'] - no other options shown

---

## Token Efficiency

### Before
- System prompt: ~5000 tokens (all tables)
- Failed query attempt: 500 tokens
- Retry with corrections: 500 tokens
- **Total: ~6000 tokens**

### After
- System prompt: ~6000 tokens (includes binding constraints)
- Successful query (first attempt): 500 tokens
- No retry needed
- **Total: ~6500 tokens**

**Trade-off:** Slightly more upfront tokens for constraints, but:
- ✅ No retry tokens wasted
- ✅ Higher success rate = better user experience
- ✅ Fewer database queries executed
- ✅ Overall more efficient at scale

---

## Architecture Shift

```
BEFORE (Reactive):
┌─────────┐     ┌─────────┐     ┌──────────┐     ┌─────────┐
│  User   │────▶│   LLM   │────▶│  Guess   │────▶│ Validate│
│  Query  │     │ Prompt  │     │   SQL    │     │  Schema │
└─────────┘     └─────────┘     └──────────┘     └────┬────┘
                                                        │
                                                     ❌ Fail
                                                        │
                                      ┌─────────────────┘
                                      ▼
                                 ┌─────────┐
                                 │  Retry  │
                                 │  with   │
                                 │ Hints   │
                                 └─────────┘

AFTER (Proactive):
┌─────────┐     ┌─────────┐     ┌──────────┐     ┌─────────┐
│  User   │────▶│ Detect  │────▶│  Build   │────▶│   LLM   │
│  Query  │     │ Tables  │     │ Binding  │     │  with   │
└─────────┘     └─────────┘     │  Schema  │     │  Schema │
                                 │Constraint│     │  Rules  │
                                 └──────────┘     └────┬────┘
                                                        │
                                                    ✅ Correct SQL
                                                    (first time)
                                                        │
                                                        ▼
                                                   ┌─────────┐
                                                   │ Execute │
                                                   │ Success │
                                                   └─────────┘
```

---

## Key Insight

**The system no longer HOPES the LLM will follow schema guidelines.**

**It FORCES the LLM to choose from a closed set of options.**

This is the difference between:
- "Please use STATUS not bot_status" (hope)
- "Allowed columns: [STATUS] → ONLY: ['ENABLED', 'DISABLED']" (enforcement)

The LLM has no choice but to generate schema-compliant SQL because **it doesn't see any other options.**
