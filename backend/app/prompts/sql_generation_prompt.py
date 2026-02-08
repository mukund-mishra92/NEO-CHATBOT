"""
Enhanced SQL Generation Prompt with Few-Shot Examples, Guardrails, and Table Relationships.

Every column, table, and JOIN in this file has been verified against Table_information.csv.
Last verified: 2026-02-08
"""

# ─────────────────────────────────────────────────────────────────────────────
# TABLE RELATIONSHIPS  –  The LLM MUST know how tables connect
# ─────────────────────────────────────────────────────────────────────────────
TABLE_RELATIONSHIPS = """
================================================================================
TABLE RELATIONSHIPS (use these for JOINs)
================================================================================

1) BIN → Physical Location (Aisle/Tower):
   store_bin_master.LOCATION_ID  →  location_master.LOCATION_ID
   Gives: location_master.AISLE_NUMBER (enum A01-A24), location_master.TOWER_NUMBER (enum T01-T10)
   NOTE: store_bin_master does NOT have AISLE_ID or TOWER_ID columns!

2) BIN → Bin Details:
   store_bin_master.BIN_ID  →  bin_info_master.BIN_ID
   Gives: bin_info_master.BIN_BARCODE, BIN_TYPE, BIN_SEGMENTS

3) Inventory → Bin:
   live_inventory_master.BIN_ID  →  bin_info_master.BIN_ID
   live_inventory_master.BIN_ID  →  store_bin_master.BIN_ID

4) Inventory → SKU info:
   live_inventory_master.ARTICLE_ID  →  sku_master.SKU_ID
   Gives: sku_master.SKU_NAME, sku_master.VELOCITY, sku_master.CATEGORY

5) Inventory → Batch/Expiry info:
   live_inventory_master.ARTICLE_ID = sku_batch_master.SKU_ID
   AND live_inventory_master.BATCH_ID = sku_batch_master.BATCH_ID
   Gives: sku_batch_master.EXPIRY_DATE, BATCH_NUMBER, MRP

6) Task → Station:
   task_master_log.DESTINATION_LOCATION_ID  →  hw_station_master.LOCATION_ID
   Gives: hw_station_master.STATION_ID, STATION_ALIAS_NAME

7) Task → Bot:
   task_master_log.BOT_ID  →  bot_master.BOT_ID
   NOTE: bot_master has NO BOT_NAME column. Use BOT_ID directly.

8) Location blocks:
   location_block_master has AISLE_ID(int), TOWER_ID(int) directly

9) Order bin tasks:
   order_bin_task_master has AISLE_ID, TOWER_ID, TOWER_LEVEL, BIN_ID directly
   (use ONLY for order-related bin task queries, NOT for general bin locations)

CRITICAL TABLE FACTS:
- There is NO 'article_master' table! SKU names are in sku_master.SKU_NAME
- store_bin_master columns: LOCATION_ID(PK), BIN_ID, PREV_BIN_ID, VELOCITY, COST, timestamps, AUDIT
- bot_master has NO BOT_NAME column
- location_master columns: LOCATION_ID(PK), X, Y, Z, TYPE, AISLE_NUMBER(enum), TOWER_NUMBER(enum)
- bin_info_master has only 4 columns: BIN_ID(PK), BIN_BARCODE, BIN_TYPE, BIN_SEGMENTS
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
COMMON MISTAKES TO AVOID
========================================

❌ MISTAKE 1: store_bin_master has AISLE_ID/TOWER_ID  (IT DOES NOT!)
BAD:  SELECT sbm.AISLE_ID, sbm.TOWER_ID FROM store_bin_master sbm
GOOD: JOIN location_master lm ON sbm.LOCATION_ID = lm.LOCATION_ID
      SELECT lm.AISLE_NUMBER, lm.TOWER_NUMBER

❌ MISTAKE 2: Using article_master  (TABLE DOES NOT EXIST!)
BAD:  JOIN article_master am ON ...
GOOD: JOIN sku_master sm ON lim.ARTICLE_ID = sm.SKU_ID

❌ MISTAKE 3: Filtering product by ID when given a name
BAD:  WHERE ARTICLE_ID LIKE '%Paracetamol%'
GOOD: JOIN sku_master sm ... WHERE sm.SKU_NAME LIKE '%Paracetamol%'

❌ MISTAKE 4: Wrong table for bin presentations
BAD:  FROM order_bin_mapping / station_pick_task_master
GOOD: FROM task_master_log WHERE TASK_TYPE IN ('STATION_TO_STATION','BIN_STORE_TO_ZONE')

❌ MISTAKE 5: Using BOT_NAME  (COLUMN DOES NOT EXIST!)
BAD:  SELECT bm.BOT_NAME FROM bot_master
GOOD: SELECT bm.BOT_ID FROM bot_master

❌ MISTAKE 6: Wrong expiry source
BAD:  store_bin_master.EXPIRY_DATE  (doesn't exist)
GOOD: sku_batch_master.EXPIRY_DATE  (PK: SKU_ID, BATCH_ID)

❌ MISTAKE 7: Using TASK_MASTER_LOG_ID  (doesn't exist)
BAD:  SELECT TASK_MASTER_LOG_ID FROM task_master_log
GOOD: SELECT LOG_ID FROM task_master_log  (PK), or TASK_ID for the task reference
"""


# ─────────────────────────────────────────────────────────────────────────────
# GUARDRAILS
# ─────────────────────────────────────────────────────────────────────────────
GUARDRAILS = """
========================================
GUARDRAILS (Must Follow!)
========================================

🛡️ 1: Column Verification
- Use ONLY columns from SCHEMA CONTEXT. NEVER invent columns.
- Before using any column, verify it exists in that table's column list.

🛡️ 2: Table Selection
- Business rules override everything when matched.
- Master tables = current state. Log tables = history.

🛡️ 3: Location (Aisle/Tower) — CRITICAL!
- AISLE_NUMBER and TOWER_NUMBER are ONLY in location_master
- store_bin_master connects via LOCATION_ID
- ALWAYS: store_bin_master JOIN location_master ON LOCATION_ID
- NEVER: store_bin_master.AISLE_ID (doesn't exist!)

🛡️ 4: SKU Names
- Use sku_master.SKU_NAME (no article_master table!)
- live_inventory_master.ARTICLE_ID = sku_master.SKU_ID

🛡️ 5: Expiry Date
- Primary: sku_batch_master.EXPIRY_DATE (PK: SKU_ID, BATCH_ID)
- Alternative: stock_audit_bin_segments.expiry_date
- NOT in live_inventory_master, NOT in store_bin_master

🛡️ 6: Velocity
- SKU-level: sku_master.VELOCITY
- Bin-level: store_bin_master.VELOCITY

🛡️ 7: Safety
- Always LIMIT 200 unless user says "all"
- READ-ONLY only (SELECT/WITH)
- Avoid SELECT * — list specific columns
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
