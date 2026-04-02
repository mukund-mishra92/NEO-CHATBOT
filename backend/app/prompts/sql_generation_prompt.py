"""
Enhanced SQL Generation Prompt with Few-Shot Examples, Guardrails, and Table Relationships.

⚠️  DEPRECATED — March 23, 2026
    This file is NOT used in the active pipeline.
    - Imported ONLY by `nl_to_sql_generator.py` (which is itself dead/unused code).
    - The ACTIVE prompt is `universal_sql_prompt.py` → used by `sql_engine.py`.
    - Valuable content (TABLE_RELATIONSHIPS, COMMON_MISTAKES, GUARDRAILS, FEW-SHOT EXAMPLES)
      has been merged into `universal_sql_prompt.py` as of March 23, 2026.
    - Kept for reference only. Do NOT add new logic here.

Every column, table, and JOIN in this file has been verified against Table_information.csv.
Last verified: 2026-02-08
"""

# ─────────────────────────────────────────────────────────────────────────────
# TABLE RELATIONSHIPS  –  The LLM MUST know how tables connect
# ─────────────────────────────────────────────────────────────────────────────
TABLE_RELATIONSHIPS = """
================================================================================
TABLE RELATIONSHIPS (verified 2026-02-09 from Table_information.csv)
================================================================================

✓ CRITICAL JOINS IN NEO WAREHOUSE:

1) BIN → Physical Location (Aisle/Tower) — MOST COMMON!
   store_bin_master.LOCATION_ID  →  location_master.LOCATION_ID
   Gives: location_master.AISLE_NUMBER (enum: A01-A24, RA01-RA03, URA01-URA04)
         location_master.TOWER_NUMBER (enum: T01-T10)
   ❌ CRITICAL: store_bin_master has NO AISLE_ID/TOWER_ID columns - MUST join location_master!

2) BIN → Bin Details (Barcode):
   store_bin_master.BIN_ID  →  bin_info_master.BIN_ID
   Gives: bin_info_master.BIN_BARCODE, BIN_TYPE, BIN_SEGMENTS
   (bin_info_master has only 4 columns total!)

3) Inventory → Bin Tracking:
   live_inventory_master.BIN_ID  →  bin_info_master.BIN_ID  (for barcode)
   live_inventory_master.BIN_ID  →  store_bin_master.BIN_ID  (for velocity/location)

4) Inventory → SKU Info (Product Names) — VERIFIED TABLE!
   live_inventory_master.ARTICLE_ID  →  article_registered.SKU_ID
   Aliases: article_registered = sku_master  (both valid names in schema)
   Gives: SKU_NAME, CATEGORY, VELOCITY, HSN_CODE, PRIMARY_BARCODE
   ❌ NO 'article_master' table exists! Use article_registered/sku_master!

5) Inventory → Batch/Expiry Info — COMPOUND KEY REQUIRED!
   live_inventory_master.ARTICLE_ID = sku_batch_master.SKU_ID
   AND live_inventory_master.BATCH_ID = sku_batch_master.BATCH_ID
   Gives: sku_batch_master.EXPIRY_DATE, BATCH_NUMBER, MRP, MFG_DATE, VENDOR_ID
   ❌ live_inventory_master has NO EXPIRY_DATE column - MUST use sku_batch_master!

6) Task → Station (Presentations):
   task_master_log.DESTINATION_LOCATION_ID  →  hw_station_master.LOCATION_ID  (TO station)
   OR task_master_log.SOURCE_LOCATION_ID → hw_station_master.LOCATION_ID  (FROM station)
   Gives: hw_station_master.STATION_ID, STATION_ALIAS_NAME, IS_ACTIVE
   Filter: task_master_log.TASK_TYPE IN ('STATION_TO_STATION', 'BIN_STORE_TO_ZONE')
          AND task_master_log.STATUS = 'COMPLETED'

7) Task → Bot Assignment:
   task_master_log.BOT_ID  →  bot_master.BOT_ID
   Gives: bot_master.STATUS, BATTERY, BATTERY_HEALTH, LOAD_CONDITION, GRIDX, GRIDY
   ❌ bot_master has NO BOT_NAME column - only BOT_ID (varchar(50))!

8) Bot → Bot History/Logs:
   bot_master.BOT_MASTER_ID  →  bot_master_log.BOT_MASTER_ID  (state changes)
   bot_master.BOT_ID  →  bot_alarm_log.BOT_ID  (alarms/errors)

9) Station → Location (Station Physical Position):
   hw_station_master.LOCATION_ID  →  location_master.LOCATION_ID
   Gives: station's aisle, tower, XYZ coordinates

❌ CRITICAL SCHEMA CORRECTIONS (FROM VERIFIED CSV):
Table: bot_master
  - PK: BOT_MASTER_ID (int)
  - BOT_ID: varchar(50) - ONLY bot identifier column
  - ❌ NO BOT_NAME column exists!
  - STATUS enum: 'ENABLED', 'DISABLED' (NOT 'ACTIVE'/'INACTIVE')
  - LOAD_CONDITION enum: 'UL', 'LD' (Unloaded/Loaded)
  - BATTERY_HEALTH enum: 'GOOD', 'AVERAGE', 'CRITICAL'

Table: task_master_log
  - PK: LOG_ID (int) — ❌ NOT 'TASK_MASTER_LOG_ID'!
  - TASK_ID: varchar(100) - references actual task
  - TASK_TYPE common: 'STATION_TO_STATION', 'BIN_STORE_TO_ZONE', 'INVENTORY_COUNT'
  - STATUS common: 'COMPLETED', 'IN_PROGRESS', 'ASSIGNED', 'FAILED'

Table: location_master
  - PK: LOCATION_ID (int)
  - AISLE_NUMBER enum: A01-A24, RA01-RA03, URA01-URA04
  - TOWER_NUMBER enum: T01-T10
  - TYPE enum: 'BIN_LOC', 'STATION_LOC', 'BUFFER_LOC', 'WAITING_POINT'

Table: store_bin_master
  - PK: LOCATION_ID (int) — YES, location is the PK!
  - BIN_ID, PREV_BIN_ID, VELOCITY, COST, AGE_OF_BIN
  - ❌ NO AISLE_ID, TOWER_ID, or EXPIRY_DATE columns!

Table: sku_batch_master (Expiry Date Source!)
  - Composite PK: SKU_ID + BATCH_ID
  - EXPIRY_DATE: date — This is THE source for expiry dates!
  - BATCH_NUMBER, MRP, MFG_DATE, VENDOR_ID

TABLE ALIAS CONVENTIONS:
bm = bot_master, tml = task_master_log, hm = hw_station_master
lm = location_master, lim = live_inventory_master
ar = article_registered (or sm = sku_master), sbm = store_bin_master
bim = bin_info_master, skbm = sku_batch_master, bal = bot_alarm_log
================================================================================
"""


# ─────────────────────────────────────────────────────────────────────────────
# FEW-SHOT EXAMPLES  –  All SQL verified against real schema
# ─────────────────────────────────────────────────────────────────────────────
FEW_SHOT_EXAMPLES = """
========================================
FEW-SHOT EXAMPLES (Learn from these!)
========================================

Example 1: Simple Count
-------------------------------
USER: "How many active bots do we have?"

SQL:
SELECT COUNT(*) AS active_bot_count
FROM bot_master
WHERE STATUS = 'ENABLED';

WHY: bot_master for current state. STATUS enum is ('ENABLED','DISABLED'). No BOT_NAME column.


Example 2: Bin Presentations per Station (Aggregation)
-------------------------------
USER: "Show bin presentations per station for yesterday"

SQL:
SELECT
  hm.STATION_ID,
  hm.STATION_ALIAS_NAME,
  COUNT(*) AS bin_presentations
FROM task_master_log tl
JOIN hw_station_master hm
  ON tl.DESTINATION_LOCATION_ID = hm.LOCATION_ID
WHERE tl.TASK_TYPE IN ('STATION_TO_STATION', 'BIN_STORE_TO_ZONE')
  AND tl.STATUS = 'COMPLETED'
  AND DATE(tl.logged_timestamp) = CURDATE() - INTERVAL 1 DAY
GROUP BY hm.STATION_ID, hm.STATION_ALIAS_NAME
ORDER BY bin_presentations DESC
LIMIT 200;

WHY: task_master_log for history. Join hw_station_master via DESTINATION_LOCATION_ID = LOCATION_ID.


Example 3: Inventory Lookup by Product Name
-------------------------------
USER: "Which bins contain Paracetamol?"

SQL:
SELECT
  sm.SKU_NAME,
  sm.SKU_ID,
  lim.BIN_ID,
  bim.BIN_BARCODE,
  lim.QUANTITY,
  lim.SEGMENT_NO
FROM live_inventory_master lim
JOIN sku_master sm
  ON lim.ARTICLE_ID = sm.SKU_ID
LEFT JOIN bin_info_master bim
  ON lim.BIN_ID = bim.BIN_ID
WHERE sm.SKU_NAME LIKE '%Paracetamol%'
  AND lim.IS_ACTIVE = 1
  AND lim.QUANTITY > 0
ORDER BY lim.BIN_ID
LIMIT 200;

WHY: NO article_master table! Use sku_master.SKU_NAME. ARTICLE_ID is a UUID — never LIKE on it.


Example 4: Hourly Time Range
-------------------------------
USER: "Bin presentations from 7pm to 9pm yesterday"

SQL:
SELECT
  hm.STATION_ID,
  hm.STATION_ALIAS_NAME,
  COUNT(*) AS bin_presentations
FROM task_master_log tl
JOIN hw_station_master hm
  ON tl.DESTINATION_LOCATION_ID = hm.LOCATION_ID
WHERE tl.TASK_TYPE IN ('STATION_TO_STATION', 'BIN_STORE_TO_ZONE')
  AND tl.STATUS = 'COMPLETED'
  AND tl.logged_timestamp >= (CURDATE() - INTERVAL 1 DAY) + INTERVAL 19 HOUR
  AND tl.logged_timestamp < (CURDATE() - INTERVAL 1 DAY) + INTERVAL 21 HOUR
GROUP BY hm.STATION_ID, hm.STATION_ALIAS_NAME
ORDER BY bin_presentations DESC
LIMIT 200;

WHY: 7pm = INTERVAL 19 HOUR, 9pm = INTERVAL 21 HOUR. Exclusive upper bound.


Example 5: Bin Location (Aisle/Tower)
-------------------------------
USER: "Show which aisle and tower bin 431 is in"

SQL:
SELECT
  sbm.BIN_ID,
  bim.BIN_BARCODE,
  lm.AISLE_NUMBER,
  lm.TOWER_NUMBER,
  sbm.VELOCITY
FROM store_bin_master sbm
JOIN location_master lm
  ON sbm.LOCATION_ID = lm.LOCATION_ID
LEFT JOIN bin_info_master bim
  ON sbm.BIN_ID = bim.BIN_ID
WHERE sbm.BIN_ID = 431
LIMIT 200;

WHY:
- store_bin_master has NO AISLE_ID/TOWER_ID columns!
- MUST join location_master via LOCATION_ID
- location_master.AISLE_NUMBER (enum A01-A24), TOWER_NUMBER (enum T01-T10)


Example 6: Expiring SKUs with Location and Velocity
-------------------------------
USER: "SKUs expiring in next 7 days with velocity 1, show aisle and tower"

SQL:
SELECT
  sbm.SKU_ID,
  sm.SKU_NAME,
  sbm.EXPIRY_DATE,
  sm.VELOCITY,
  lim.BIN_ID,
  bim.BIN_BARCODE,
  lm.AISLE_NUMBER,
  lm.TOWER_NUMBER,
  lim.SEGMENT_NO,
  lim.QUANTITY
FROM sku_batch_master sbm
JOIN live_inventory_master lim
  ON sbm.SKU_ID = lim.ARTICLE_ID
  AND sbm.BATCH_ID = lim.BATCH_ID
JOIN store_bin_master stbm
  ON lim.BIN_ID = stbm.BIN_ID
JOIN location_master lm
  ON stbm.LOCATION_ID = lm.LOCATION_ID
LEFT JOIN bin_info_master bim
  ON lim.BIN_ID = bim.BIN_ID
JOIN sku_master sm
  ON sbm.SKU_ID = sm.SKU_ID
WHERE sbm.EXPIRY_DATE IS NOT NULL
  AND sbm.EXPIRY_DATE >= CURDATE()
  AND sbm.EXPIRY_DATE < CURDATE() + INTERVAL 7 DAY
  AND sm.VELOCITY = 1
  AND lim.IS_ACTIVE = 1
  AND lim.QUANTITY > 0
ORDER BY sbm.EXPIRY_DATE ASC
LIMIT 200;

WHY:
- sku_batch_master.EXPIRY_DATE (most reliable source, PK: SKU_ID + BATCH_ID)
- sku_master.VELOCITY for SKU-level velocity, sku_master.SKU_NAME for name
- store_bin_master → location_master for AISLE_NUMBER/TOWER_NUMBER
- live_inventory_master links SKU+BATCH → physical BIN
- Chain: sku_batch_master → live_inventory_master → store_bin_master → location_master


Example 7: Bot Status
-------------------------------
USER: "Show all enabled bots with their battery level"

SQL:
SELECT
  BOT_ID,
  STATUS,
  BATTERY,
  BATTERY_HEALTH,
  GRIDX,
  GRIDY,
  LOAD_CONDITION,
  UPDATED_TIMESTAMP
FROM bot_master
WHERE STATUS = 'ENABLED'
ORDER BY BOT_ID
LIMIT 200;

WHY: bot_master for current state. No BOT_NAME column. STATUS enum is ('ENABLED','DISABLED').
"""


# ─────────────────────────────────────────────────────────────────────────────
# COMMON MISTAKES
# ─────────────────────────────────────────────────────────────────────────────
COMMON_MISTAKES = """
========================================
COMMON MISTAKES TO AVOID (Verified Errors)
========================================

❌ MISTAKE 1: Using article_master table (DOES NOT EXIST!)
BAD:  SELECT am.SKU_NAME FROM article_master am
BAD:  JOIN article_master am ON lim.ARTICLE_ID = am.SKU_ID
GOOD: SELECT ar.SKU_NAME FROM article_registered ar
GOOD: JOIN article_registered ar ON lim.ARTICLE_ID = ar.SKU_ID
GOOD: JOIN sku_master sm ON lim.ARTICLE_ID = sm.SKU_ID  (alias)
WHY:  No article_master table exists. Use article_registered or sku_master.

❌ MISTAKE 2: Accessing AISLE_ID/TOWER_ID from store_bin_master (COLUMNS DON'T EXIST!)
BAD:  SELECT sbm.AISLE_ID, sbm.TOWER_ID FROM store_bin_master sbm WHERE sbm.BIN_ID = 431
GOOD: SELECT lm.AISLE_NUMBER, lm.TOWER_NUMBER
      FROM store_bin_master sbm
      JOIN location_master lm ON sbm.LOCATION_ID = lm.LOCATION_ID
      WHERE sbm.BIN_ID = 431
WHY:  store_bin_master has NO aisle/tower columns. MUST join location_master via LOCATION_ID.

❌ MISTAKE 3: Using BOT_NAME column (DOES NOT EXIST!)
BAD:  SELECT bm.BOT_NAME FROM bot_master bm
BAD:  WHERE bm.BOT_NAME = 'BOT-001'
GOOD: SELECT bm.BOT_ID FROM bot_master bm
GOOD: WHERE bm.BOT_ID = 'BOT-001'
WHY:  bot_master has NO BOT_NAME column. Only BOT_ID (varchar(50)) exists.

❌ MISTAKE 4: Using TASK_MASTER_LOG_ID as primary key (WRONG NAME!)
BAD:  SELECT TASK_MASTER_LOG_ID FROM task_master_log
GOOD: SELECT LOG_ID FROM task_master_log
WHY:  Primary key is LOG_ID, not TASK_MASTER_LOG_ID. TASK_ID is the actual task reference.

❌ MISTAKE 5: Filtering product by ID when user gives a name
BAD:  WHERE lim.ARTICLE_ID LIKE '%Paracetamol%'
GOOD: JOIN article_registered ar ON lim.ARTICLE_ID = ar.SKU_ID
      WHERE ar.SKU_NAME LIKE '%Paracetamol%'
WHY:  ARTICLE_ID is a UUID/varchar, not a name. SKU_NAME is in article_registered/sku_master.

❌ MISTAKE 6: Getting expiry date from wrong table
BAD:  SELECT sbm.EXPIRY_DATE FROM store_bin_master sbm
BAD:  SELECT lim.EXPIRY_DATE FROM live_inventory_master lim
GOOD: SELECT skbm.EXPIRY_DATE FROM sku_batch_master skbm
      WHERE skbm.SKU_ID = ? AND skbm.BATCH_ID = ?
WHY:  EXPIRY_DATE only exists in sku_batch_master (compound PK: SKU_ID + BATCH_ID).

❌ MISTAKE 7: Wrong table for bin presentations
BAD:  SELECT COUNT(*) FROM order_bin_mapping WHERE ...
BAD:  SELECT COUNT(*) FROM station_pick_task_master WHERE ...
GOOD: SELECT COUNT(*) FROM task_master_log
      WHERE TASK_TYPE IN ('STATION_TO_STATION', 'BIN_STORE_TO_ZONE')
        AND STATUS = 'COMPLETED'
WHY:  task_master_log is the correct source for bin presentation counts to stations.

❌ MISTAKE 8: Wrong enum values for bot_master.STATUS
BAD:  WHERE bm.STATUS = 'ACTIVE'
BAD:  WHERE bm.STATUS = 'INACTIVE'
GOOD: WHERE bm.STATUS = 'ENABLED'
GOOD: WHERE bm.STATUS = 'DISABLED'
WHY:  bot_master.STATUS enum is ('ENABLED', 'DISABLED'), not 'ACTIVE'/'INACTIVE'.

❌ MISTAKE 9: Forgetting compound key for sku_batch_master
BAD:  JOIN sku_batch_master skbm ON lim.ARTICLE_ID = skbm.SKU_ID
GOOD: JOIN sku_batch_master skbm 
        ON lim.ARTICLE_ID = skbm.SKU_ID 
       AND lim.BATCH_ID = skbm.BATCH_ID
WHY:  sku_batch_master PK is (SKU_ID, BATCH_ID). MUST use both columns in JOIN.

❌ MISTAKE 10: Using wrong timestamp column for task filtering
BAD:  WHERE DATE(tml.CREATED_TIMESTAMP) = CURDATE()
GOOD: WHERE DATE(tml.logged_timestamp) = CURDATE()
WHY:  task_master_log uses logged_timestamp (lowercase) for task completion time.

❌ MISTAKE 11: Filtering inventory without IS_ACTIVE check
BAD:  SELECT * FROM live_inventory_master WHERE BIN_ID = 431
GOOD: SELECT * FROM live_inventory_master 
      WHERE BIN_ID = 431 AND IS_ACTIVE = 1 AND QUANTITY > 0
WHY:  live_inventory_master includes inactive/deleted records. Always filter IS_ACTIVE = 1.

❌ MISTAKE 12: Using article_registered.VELOCITY instead of sku_master.VELOCITY
ACTUALLY OKAY: Both tables have VELOCITY column - they're aliases!
NOTE: article_registered = sku_master in this schema. Use whichever you already joined.

❌ MISTAKE 13: Not limiting results (performance issue)
BAD:  SELECT * FROM task_master_log WHERE STATUS = 'COMPLETED'
GOOD: SELECT * FROM task_master_log WHERE STATUS = 'COMPLETED' ORDER BY logged_timestamp DESC LIMIT 100
WHY:  Log tables can have millions of rows. Always LIMIT results unless user explicitly says "all".
"""


# ─────────────────────────────────────────────────────────────────────────────
# GUARDRAILS
# ─────────────────────────────────────────────────────────────────────────────
GUARDRAILS = """
========================================
GUARDRAILS (Mandatory Rules - Never Break These!)
========================================

🛡️ GUARDRAIL 1: Column Existence Verification
- ONLY use columns that exist in SCHEMA CONTEXT for each table
- NEVER invent columns based on assumptions
- Before writing any column in SQL, verify it appears in that table's column list
- If unsure, ask for clarification rather than guessing

🛡️ GUARDRAIL 2: Table Selection Logic
Priority Order:
  1. Business rules (if provided) override everything
  2. Master tables (bot_master, store_bin_master) = current state
  3. Log tables (task_master_log, bot_master_log) = historical data
  4. Use task_master_log for bin presentations, task counts, bot activity history
  5. Use bot_master for current bot status, location, battery level

🛡️ GUARDRAIL 3: Location Queries (AISLE/TOWER) — NEVER FORGET!
- AISLE_NUMBER and TOWER_NUMBER exist ONLY in location_master
- store_bin_master has LOCATION_ID (FK) to join location_master
- ALWAYS use this pattern:
  ```sql
  FROM store_bin_master sbm
  JOIN location_master lm ON sbm.LOCATION_ID = lm.LOCATION_ID
  SELECT lm.AISLE_NUMBER, lm.TOWER_NUMBER
  ```
- NEVER try: sbm.AISLE_ID, sbm.TOWER_ID (columns don't exist!)

🛡️ GUARDRAIL 4: SKU Name Queries — VERIFIED TABLE!
- Use article_registered (or alias sku_master) for SKU_NAME
- NO article_master table exists in this database
- Pattern:
  ```sql
  FROM live_inventory_master lim
  JOIN article_registered ar ON lim.ARTICLE_ID = ar.SKU_ID
  WHERE ar.SKU_NAME LIKE '%ProductName%'
  ```
- NEVER filter ARTICLE_ID with LIKE when user provides a product name

🛡️ GUARDRAIL 5: Expiry Date Queries — COMPOUND KEY REQUIRED!
- EXPIRY_DATE exists ONLY in sku_batch_master
- Composite PK: (SKU_ID, BATCH_ID) — MUST use both in JOIN
- Pattern:
  ```sql
  FROM live_inventory_master lim
  JOIN sku_batch_master skbm 
    ON lim.ARTICLE_ID = skbm.SKU_ID 
   AND lim.BATCH_ID = skbm.BATCH_ID
  WHERE skbm.EXPIRY_DATE >= CURDATE()
  ```
- Alternative: stock_audit_bin_segments.expiry_date (less common)
- NEVER try: live_inventory_master.EXPIRY_DATE, store_bin_master.EXPIRY_DATE

🛡️ GUARDRAIL 6: Velocity Filtering
- SKU-level velocity: article_registered.VELOCITY or sku_master.VELOCITY
- Bin-level velocity: store_bin_master.VELOCITY
- Choose based on query context:
  - "Fast-moving products" → sku_master.VELOCITY
  - "Fast-moving bins" → store_bin_master.VELOCITY

🛡️ GUARDRAIL 7: Bot Queries — NO BOT_NAME!
- bot_master has ONLY BOT_ID (varchar(50)) as identifier
- NO BOT_NAME column exists
- Pattern:
  ```sql
  SELECT bm.BOT_ID, bm.STATUS, bm.BATTERY, bm.BATTERY_HEALTH
  FROM bot_master bm
  WHERE bm.BOT_ID = 'BOT-001' AND bm.STATUS = 'ENABLED'
  ```
- STATUS enum: 'ENABLED', 'DISABLED' (not 'ACTIVE'/'INACTIVE')
- LOAD_CONDITION enum: 'UL', 'LD'
- BATTERY_HEALTH enum: 'GOOD', 'AVERAGE', 'CRITICAL'

🛡️ GUARDRAIL 8: Task Queries — CORRECT PRIMARY KEY!
- task_master_log PK is LOG_ID (int), NOT 'TASK_MASTER_LOG_ID'
- TASK_ID (varchar) is the actual task reference/identifier
- Common filters:
  - TASK_TYPE IN ('STATION_TO_STATION', 'BIN_STORE_TO_ZONE') for bin presentations
  - STATUS = 'COMPLETED' for finished tasks
  - logged_timestamp for date filtering
- Always ORDER BY logged_timestamp DESC for recent tasks

🛡️ GUARDRAIL 9: Active Records Only
- live_inventory_master: Always filter IS_ACTIVE = 1 AND QUANTITY > 0
- hw_station_master: Filter IS_ACTIVE = 1 for active stations
- Pattern:
  ```sql
  WHERE lim.IS_ACTIVE = 1 AND lim.QUANTITY > 0
  ```

🛡️ GUARDRAIL 10: Safety & Performance
- ALWAYS include LIMIT clause (default LIMIT 100)
- Only omit LIMIT if user explicitly says "all" or "everything"
- READ-ONLY queries only: SELECT, WITH statements
- NO: INSERT, UPDATE, DELETE, DROP, ALTER, CREATE, TRUNCATE, GRANT, REVOKE
- Avoid SELECT * — list specific columns for performance
- Use indexes when available (primary keys, foreign keys)

🛡️ GUARDRAIL 11: Date Filtering Best Practices
- Use DATE(timestamp_col) for date comparisons
- Use CURDATE() for today
- Use DATE_SUB(CURDATE(), INTERVAL n DAY) for "last N days"
- For yesterday: DATE(col) = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
- For time ranges: Use INTERVAL HOUR for hourly queries
- Example: tml.logged_timestamp >= (CURDATE() - INTERVAL 1 DAY) + INTERVAL 19 HOUR

🛡️ GUARDRAIL 12: Enum Value Validation
- Always use EXACT enum values from SCHEMA CONTEXT
- Common enums to remember:
  - bot_master.STATUS: 'ENABLED', 'DISABLED'
  - location_master.AISLE_NUMBER: 'A01'-'A24', 'RA01'-'RA03', 'URA01'-'URA04'
  - location_master.TOWER_NUMBER: 'T01'-'T10'
  - location_master.TYPE: 'BIN_LOC', 'STATION_LOC', 'BUFFER_LOC', 'WAITING_POINT'
- If enum value is unknown, check schema or ask for clarification

🛡️ GUARDRAIL 13: JSON Response Format
- Always return valid JSON with required fields:
  - sql: string (the query)
  - tables_used: array of strings
  - columns_used: array of strings (format: "table.column")
  - primary_keys_used: array of strings
  - assumptions: array of strings (what you assumed)
  - warnings: array of strings (potential issues)
  - needs_followup: boolean
  - followup_questions: array of strings
  - is_read_only: boolean (must be true)
  - confidence: float (0.0-1.0)
"""


# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM INSTRUCTION
# ─────────────────────────────────────────────────────────────────────────────
SYSTEM_INSTRUCTION = (
    "You are a senior MySQL 8.x Text-to-SQL generator for the NEO warehouse database.\n"
    "Generate READ-ONLY SQL only. Output strict JSON matching the response schema.\n"
    "Use ONLY tables and columns from the SCHEMA CONTEXT provided.\n"
    "CRITICAL: Verify every column exists in its table before using it in SQL.\n"
    "If a column does not appear in the SCHEMA CONTEXT for that table, do NOT use it.\n"
)


def build_enhanced_prompt(
    schema_context: str,
    business_rule_prompt: str = "",
) -> str:
    """
    Assemble the full system instruction with all components.

    Args:
        schema_context: Table/column definitions from CSV
        business_rule_prompt: Dynamic business-rule block (may be empty)

    Returns:
        Complete system instruction string
    """
    parts = [
        SYSTEM_INSTRUCTION,
        TABLE_RELATIONSHIPS,
        FEW_SHOT_EXAMPLES,
        COMMON_MISTAKES,
        GUARDRAILS,
    ]

    if business_rule_prompt:
        parts.append(business_rule_prompt)

    return "\n".join(parts)
