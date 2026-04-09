"""
Schema Registry for NEO Warehouse Database — UNIVERSAL EDITION
================================================================
Auto-discovers all table relationships, join paths, column types,
and enum values from Table_information.csv.

This is the SINGLE SOURCE OF TRUTH for SQL generation.
No hardcoded per-query rules. The LLM receives enough schema knowledge
to construct ANY query autonomously — from simple lookups to
multi-join analytics and predictive queries.

Architecture:
    1. TABLE_DOMAINS         – logical groupings with keywords
    2. CORE_RELATIONSHIPS    – verified FK join paths
    3. COLUMN_FACTS          – critical column truths
    4. ENUM_REGISTRY         – all enum values per table.column
    5. SchemaRegistry class  – auto-loads CSV, builds join graph,
                               answers "which tables & joins for this question?"

Author: NEO Chatbot Team
Last verified against Table_information.csv: 2026-02-08  (166 tables)
"""

from __future__ import annotations

import csv
import logging
import re
from collections import defaultdict, deque
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

logger = logging.getLogger(__name__)


# ══════════════════════════════════════════════════════════════════════════════
# 1. TABLE DOMAINS — Logical groupings the LLM uses to find relevant tables
# ══════════════════════════════════════════════════════════════════════════════

TABLE_DOMAINS: Dict[str, Dict[str, Any]] = {
    "inventory": {
        "description": "Live inventory positions, SKU-to-bin mapping, quantities",
        "primary_tables": ["live_inventory_master"],
        "related_tables": [
            "live_inventory_master_log", "bin_info_master", "store_bin_master",
        ],
        "keywords": [
            "inventory", "stock", "quantity", "sku in bin", "available",
            "how many", "what is in", "present in", "stored in", "remaining",
            "total quantity", "count of sku", "items in",
        ],
    },
    "sku_product": {
        "description": "SKU/product master data — names, velocity, category, dimensions, EAN",
        "primary_tables": ["sku_master", "sku_batch_master"],
        "related_tables": [
            "article_registered", "sku_ean_mapping", "sku_velocity_state",
            "sku_velocity_scores", "sku_velocity_history", "sku_velocity_log",
            "category_master",
        ],
        "keywords": [
            "sku", "product", "article", "item", "name", "velocity", "category",
            "batch", "expiry", "mrp", "weight", "dimension", "ean", "barcode",
            "fast moving", "slow moving", "sku name", "product name", "article name",
        ],
    },
    "bin_location": {
        "description": "Bin master data, physical locations (aisle/tower), bin config, velocity",
        "primary_tables": ["bin_info_master", "store_bin_master", "location_master"],
        "related_tables": [
            "bin_configuration", "bin_velocity_scores", "location_block_master",
            "order_bin_task_master",
        ],
        "keywords": [
            "bin", "location", "aisle", "tower", "position", "where",
            "which bin", "bin barcode", "blocked", "bin velocity", "coordinate",
            "grid", "rack", "shelf",
        ],
    },
    "bot_fleet": {
        "description": "Bot master data, status, battery, position, alarms, charging",
        "primary_tables": ["bot_master"],
        "related_tables": [
            "bot_master_log", "bot_alarm_log", "bot_manual_alarm_log",
            "bot_charging_bit_log", "robot_charge_log", "dashboard_bot_master",
            "maintenance_task_master", "maintenance_alarm_logs",
            "auto_calibration_logs", "pseudo_bot_alarm_log",
        ],
        "keywords": [
            "bot", "robot", "agv", "battery", "charging", "alarm", "maintenance",
            "enabled", "disabled", "idle", "position", "grid", "load",
            "recovery", "obstacle", "calibration",
        ],
    },
    "station": {
        "description": "Station master data, utilisation, wave assignment, login",
        "primary_tables": ["hw_station_master"],
        "related_tables": [
            "station_home_master", "station_pick_task_master",
            "hw_charging_station_master", "hw_maintenance_master",
        ],
        "keywords": [
            "station", "pick station", "put station", "gtp", "gtc", "operator",
            "logged in", "station status", "utilisation", "buffer",
        ],
    },
    "task_operations": {
        "description": "Task execution — bin moves, bot assignments, task status, timings",
        "primary_tables": ["task_master", "task_master_log"],
        "related_tables": [
            "task_detail", "task_detail_log", "steps", "steps_archive",
            "dashboard_manual_task_master", "dashboard_log_manual_task_master",
        ],
        "keywords": [
            "task", "bin presentation", "bin move", "completed", "pending",
            "assigned", "processing", "throughput", "how long", "duration",
            "cycle time", "station to station", "bin store to zone",
            "presented", "presentations", "bins presented", "bins moved",
        ],
    },
    "wave_order": {
        "description": "Wave lifecycle — creation, orders, picks, puts, stock audit waves",
        "primary_tables": ["wave_master", "pick_wave_order_master", "put_wave_order_master"],
        "related_tables": [
            "wave_master_archive", "pick_wave_order_master_archive",
            "put_wave_order_master_archive", "pick_wave_wms_data",
            "put_wave_wms_data", "wave_station_rule_mapping",
            "bin_loading_wave_order_master", "short_pick_wave_reason",
            "short_put_wave_reason", "dashboard_log_wave_process",
        ],
        "keywords": [
            "wave", "order", "pick", "put", "putaway", "shipment", "short pick",
            "short put", "wave status", "wave live", "wave complete",
            "order line", "fulfillment",
        ],
    },
    "stock_audit": {
        "description": "Stock audit / cycle count — bin segments, expected vs actual, expiry",
        "primary_tables": ["stock_audit_bin_segments", "stock_audit_wave_order_master"],
        "related_tables": [
            "stock_audit_wave_wms_data", "stock_audit_wave_reason",
            "stock_audit_list", "stock_audit_bin_data_push",
            "stock_audit_wave_order_master_archive",
        ],
        "keywords": [
            "audit", "cycle count", "discrepancy", "expected quantity",
            "actual quantity", "bin audit", "stock check", "variance",
        ],
    },
    "order_bin": {
        "description": "Order-to-bin mapping, bin task assignments at stations",
        "primary_tables": ["order_bin_mapping"],
        "related_tables": [
            "order_bin_mapping_log", "order_bin_task_master",
            "recovery_pick_task_master", "lpn_master",
            "lpn_pick_wave_order_mapping",
        ],
        "keywords": [
            "order bin", "bin mapping", "order status", "lpn", "license plate",
            "bin assignment", "allocated", "task allocated",
        ],
    },
    "integration": {
        "description": "WMS↔WCS payload exchange, API logs, errors",
        "primary_tables": ["wms_to_wcs_payload", "wcs_to_wms_payload"],
        "related_tables": [
            "wms_to_wcs_order_request_data", "wms_to_wcs_order_line_request_data",
            "wms_to_wcs_storage_request_data", "integration_error_logs",
            "dashboard_log_error_api", "api_master",
        ],
        "keywords": [
            "integration", "wms", "wcs", "payload", "api", "error", "http",
            "request", "response", "sync", "upload",
        ],
    },
    "hardware": {
        "description": "Physical hardware — conveyors, scanners, PTLs, curtain lights, displays",
        "primary_tables": ["hw_conveyor_master", "hw_scanner_master", "hw_ptl_master"],
        "related_tables": [
            "hw_conveyor_mux_master", "hw_curtain_light_master",
            "hw_display_master", "hw_safety_door_master", "ptl_current_state",
            "hardware_registered",
        ],
        "keywords": [
            "conveyor", "scanner", "ptl", "display", "safety door",
            "curtain light", "hardware",
        ],
    },
    "velocity_analytics": {
        "description": "SKU and bin velocity scoring, history, optimisation",
        "primary_tables": ["sku_velocity_state", "sku_velocity_scores", "bin_velocity_scores"],
        "related_tables": [
            "sku_velocity_history", "sku_velocity_log",
            "velocity_calculation_jobs", "velocity_calculation_config",
        ],
        "keywords": [
            "velocity", "fast mover", "slow mover", "optimization",
            "recommendation", "dwell", "movement frequency", "velocity score",
        ],
    },
    "telemetry": {
        "description": "Low-level bot sensor data — wheel velocity, axis positions, jog commands",
        "primary_tables": ["teleoperation_numeric_data", "teleoperation_bits"],
        "related_tables": [
            "teleoperation_bool_data", "teleoperation_numeric_data_feedback",
            "teleoperation_bool_data_feedback",
        ],
        "keywords": [
            "teleoperation", "sensor", "wheel", "axis", "jog", "slider",
            "lift", "feedback", "telemetry",
        ],
    },
    "reservation": {
        "description": "Grid location reservations for bot path planning",
        "primary_tables": ["controller_reservations_master"],
        "related_tables": [
            "subcontroller_reservations_master",
            "subcontroller_reservations_master_log",
        ],
        "keywords": ["reservation", "path", "grid", "deadlock", "controller"],
    },
    "config_system": {
        "description": "System configuration, alarms, dashboard settings, user management",
        "primary_tables": ["config_master", "master_config", "alarm_master"],
        "related_tables": [
            "manual_alarm_master", "dashboard_config",
            "dashboard_user_master", "dashboard_role_master",
            "pick_rule_master",
        ],
        "keywords": [
            "config", "setting", "alarm", "user", "role", "dashboard",
            "permission", "rule",
        ],
    },
    "chatbot": {
        "description": "Chatbot's own data — chat history, query logs, feedback",
        "primary_tables": ["chatbot_chat_history", "chatbot_sql_queries"],
        "related_tables": [
            "chatbot_feedback", "chatbot_column_corrections",
            "chatbot_query_patterns",
        ],
        "keywords": ["chat", "chatbot", "feedback", "query log", "session"],
    },
}


# ══════════════════════════════════════════════════════════════════════════════
# 2. CORE RELATIONSHIPS — Verified FK join paths
# ══════════════════════════════════════════════════════════════════════════════

CORE_RELATIONSHIPS: List[Dict[str, str]] = [
    # ── INVENTORY chain ──────────────────────────────────────────────────
    {
        "from": "live_inventory_master",
        "to": "sku_master",
        "join": "live_inventory_master.ARTICLE_ID = sku_master.SKU_ID",
        "note": "SKU name, velocity, category.  ARTICLE_ID = SKU_ID (same UUID).",
    },
    {
        "from": "live_inventory_master",
        "to": "sku_batch_master",
        "join": "live_inventory_master.ARTICLE_ID = sku_batch_master.SKU_ID AND live_inventory_master.BATCH_ID = sku_batch_master.BATCH_ID",
        "note": "Batch details, EXPIRY_DATE, MRP.  Compound key (SKU+BATCH).",
    },
    {
        "from": "live_inventory_master",
        "to": "bin_info_master",
        "join": "live_inventory_master.BIN_ID = bin_info_master.BIN_ID",
        "note": "Bin barcode, type, segments.",
    },
    {
        "from": "live_inventory_master",
        "to": "store_bin_master",
        "join": "live_inventory_master.BIN_ID = store_bin_master.BIN_ID",
        "note": "Bin velocity/cost, and LOCATION_ID for physical location.",
    },

    # ── BIN → PHYSICAL LOCATION ─────────────────────────────────────────
    {
        "from": "store_bin_master",
        "to": "location_master",
        "join": "store_bin_master.LOCATION_ID = location_master.LOCATION_ID",
        "note": "Physical aisle/tower. store_bin_master does NOT have AISLE/TOWER columns!",
    },
    {
        "from": "store_bin_master",
        "to": "bin_info_master",
        "join": "store_bin_master.BIN_ID = bin_info_master.BIN_ID",
        "note": "Bin barcode from bin_info_master.",
    },

    # ── TASK chain ───────────────────────────────────────────────────────
    {
        "from": "task_master_log",
        "to": "hw_station_master",
        "join": "task_master_log.DESTINATION_LOCATION_ID = hw_station_master.LOCATION_ID",
        "note": "Station name for task destination. For bin presentations per station.",
    },
    {
        "from": "task_master_log",
        "to": "bot_master",
        "join": "task_master_log.BOT_ID = bot_master.BOT_ID",
        "note": "Bot details for the task executor.",
    },
    {
        "from": "task_master",
        "to": "task_master_log",
        "join": "task_master.TASK_ID = task_master_log.TASK_ID",
        "note": "task_master = active tasks, task_master_log = all-time log.",
    },
    {
        "from": "task_detail",
        "to": "task_master",
        "join": "task_detail.TASK_MASTER_ID = task_master.TASK_ID",
        "note": "Sub-steps of a task (start/end location, pick/put side).",
    },
    {
        "from": "task_detail_log",
        "to": "task_master_log",
        "join": "task_detail_log.TASK_MASTER_ID = task_master_log.TASK_ID",
        "note": "Historical task detail log.",
    },
    {
        "from": "task_master_log",
        "to": "location_master",
        "join": "task_master_log.FROM_LOCATION_ID = location_master.LOCATION_ID",
        "note": "Source location of task (DESTINATION_LOCATION_ID can also join).",
    },

    # ── WAVE chain ───────────────────────────────────────────────────────
    {
        "from": "pick_wave_order_master",
        "to": "wave_master",
        "join": "pick_wave_order_master.WAVE_ID = wave_master.WAVE_ID",
        "note": "Pick orders belonging to a wave.",
    },
    {
        "from": "put_wave_order_master",
        "to": "wave_master",
        "join": "put_wave_order_master.WAVE_ID = wave_master.WAVE_ID",
        "note": "Put orders belonging to a wave.",
    },
    {
        "from": "pick_wave_order_master",
        "to": "order_bin_mapping",
        "join": "pick_wave_order_master.ORDER_BIN_ID = order_bin_mapping.ORDER_BIN_ID",
        "note": "Order-to-bin allocation.",
    },
    {
        "from": "hw_station_master",
        "to": "wave_master",
        "join": "hw_station_master.WAVE_ID = wave_master.WAVE_ID",
        "note": "Which wave is running at which station.",
    },
    {
        "from": "pick_wave_order_master",
        "to": "sku_master",
        "join": "pick_wave_order_master.SKU_ID = sku_master.SKU_ID",
        "note": "SKU details for pick wave order.",
    },
    {
        "from": "put_wave_order_master",
        "to": "sku_master",
        "join": "put_wave_order_master.SKU_ID = sku_master.SKU_ID",
        "note": "SKU details for put wave order.",
    },

    # ── LOCATION chain ──────────────────────────────────────────────────
    {
        "from": "location_block_master",
        "to": "location_master",
        "join": "location_block_master.LOCATION_ID = location_master.LOCATION_ID",
        "note": "Blocked locations (has AISLE_ID, TOWER_ID as int IDs).",
    },
    {
        "from": "hw_station_master",
        "to": "location_master",
        "join": "hw_station_master.LOCATION_ID = location_master.LOCATION_ID",
        "note": "Station physical position on the grid.",
    },
    {
        "from": "hw_charging_station_master",
        "to": "location_master",
        "join": "hw_charging_station_master.LOCATION_ID = location_master.LOCATION_ID",
        "note": "Charging station physical position.",
    },

    # ── BOT chain ────────────────────────────────────────────────────────
    {
        "from": "bot_master",
        "to": "bot_master_log",
        "join": "bot_master.BOT_ID = bot_master_log.BOT_ID",
        "note": "Bot state history.",
    },
    {
        "from": "bot_alarm_log",
        "to": "alarm_master",
        "join": "bot_alarm_log.ALARM_ID = alarm_master.ALARM_ID",
        "note": "Alarm description and resolution steps.",
    },
    {
        "from": "bot_alarm_log",
        "to": "bot_master",
        "join": "bot_alarm_log.BOT_ID = bot_master.BOT_ID",
        "note": "Which bot raised the alarm.",
    },

    # ── STOCK AUDIT chain ───────────────────────────────────────────────
    {
        "from": "stock_audit_bin_segments",
        "to": "live_inventory_master",
        "join": "stock_audit_bin_segments.sku_id = live_inventory_master.ARTICLE_ID",
        "note": "Audit segment SKU → current inventory.",
    },
    {
        "from": "stock_audit_wave_order_master",
        "to": "wave_master",
        "join": "stock_audit_wave_order_master.WAVE_ID = wave_master.WAVE_ID",
        "note": "Audit orders belonging to a wave.",
    },

    # ── VELOCITY chain ──────────────────────────────────────────────────
    {
        "from": "sku_velocity_state",
        "to": "sku_master",
        "join": "sku_velocity_state.SKU_ID = sku_master.SKU_ID",
        "note": "Current velocity state and dwell timer.",
    },
    {
        "from": "sku_velocity_history",
        "to": "sku_master",
        "join": "sku_velocity_history.SKU_ID = sku_master.SKU_ID",
        "note": "Velocity change history (old → new).",
    },
    {
        "from": "bin_velocity_scores",
        "to": "store_bin_master",
        "join": "bin_velocity_scores.BIN_ID = store_bin_master.BIN_ID",
        "note": "Bin-level velocity scores.",
    },

    # ── ORDER chain ─────────────────────────────────────────────────────
    {
        "from": "order_bin_mapping",
        "to": "bin_info_master",
        "join": "order_bin_mapping.BIN_ID = bin_info_master.BIN_ID",
        "note": "Bin details for order allocation.",
    },
    {
        "from": "order_bin_task_master",
        "to": "hw_station_master",
        "join": "order_bin_task_master.STATION_ID = hw_station_master.STATION_ID",
        "note": "Station context for order bin task.",
    },
    {
        "from": "order_bin_mapping",
        "to": "sku_master",
        "join": "order_bin_mapping.SKU_ID = sku_master.SKU_ID",
        "note": "SKU info for order-bin.",
    },

    # ── MAINTENANCE chain ───────────────────────────────────────────────
    {
        "from": "maintenance_task_master",
        "to": "bot_master",
        "join": "maintenance_task_master.BOT_ID = bot_master.BOT_ID",
        "note": "Maintenance tasks per bot.",
    },
    {
        "from": "maintenance_alarm_logs",
        "to": "alarm_master",
        "join": "maintenance_alarm_logs.ALARM_ID = alarm_master.ALARM_ID",
        "note": "Alarm details for maintenance logs.",
    },
]


# ══════════════════════════════════════════════════════════════════════════════
# 3. COLUMN FACTS — Critical column truths the LLM MUST know
# ══════════════════════════════════════════════════════════════════════════════

COLUMN_FACTS = """
CRITICAL COLUMN FACTS (verified against real database):

1. TABLES THAT DO NOT EXIST:
   - article_master → USE sku_master instead
   - bot_name_master → bot names don't exist, only BOT_ID

2. COLUMNS THAT DO NOT EXIST:
   - bot_master.BOT_NAME → does not exist. Use BOT_ID.
   - store_bin_master.AISLE_ID → does not exist. JOIN location_master.
   - store_bin_master.TOWER_ID → does not exist. JOIN location_master.
   - store_bin_master.TOWER_LEVEL → does not exist.
   - task_master_log.TASK_MASTER_LOG_ID → PK is LOG_ID, task ref is TASK_ID.
   - live_inventory_master.EXPIRY_DATE → does not exist. Use sku_batch_master.
   - live_inventory_master.SKU_NAME → does not exist. JOIN sku_master via ARTICLE_ID = SKU_ID.

3. COLUMN NAME MAPPING (what users say → actual column):
   - "aisle" → location_master.AISLE_NUMBER (enum: A01-A24, RA01-RA03, URA01-URA04)
   - "tower" → location_master.TOWER_NUMBER (enum: T01-T10)
   - "product name" / "sku name" → sku_master.SKU_NAME
   - "velocity" (SKU) → sku_master.VELOCITY or store_bin_master.VELOCITY (bin-level)
   - "expiry" / "expiry date" → sku_batch_master.EXPIRY_DATE
   - "status" (bot) → bot_master.STATUS enum('ENABLED','DISABLED')
   - "mode" / "manual mode" / "auto mode" / "auto/manual" → bot_master.AUTO_MANUAL enum('AUTO','MANUAL')
   - "battery" (bot) → bot_master.BATTERY or bot_master.AH_REMAINING_PERCENTAGE
   - "position" / "grid" (bot) → bot_master.GRIDX, bot_master.GRIDY, bot_master.GRIDZ
   - "load" / "load condition" (bot) → bot_master.LOAD_CONDITION
   - "status" (task) → task_master_log.STATUS enum('PENDING','ASSIGNED','PROCESSING','COMPLETED')
   - "status" (wave) → wave_master.WAVE_STATUS
   - "status" (order) → order_bin_mapping.STATUS

4. ID CROSS-REFERENCES:
   - live_inventory_master.ARTICLE_ID = sku_master.SKU_ID = sku_batch_master.SKU_ID (same UUID)
   - store_bin_master.LOCATION_ID = location_master.LOCATION_ID
   - task_master_log.DESTINATION_LOCATION_ID = hw_station_master.LOCATION_ID
   - task_master_log.FROM_LOCATION_ID / DESTINATION_LOCATION_ID = location_master.LOCATION_ID

5. BIN PRESENTATION QUERY PATTERN:
   - Source table: task_master_log
   - Filter: TASK_TYPE IN ('STATION_TO_STATION', 'BIN_STORE_TO_ZONE') AND STATUS = 'COMPLETED'
   - Time column: logged_timestamp
   - Station: JOIN DESTINATION_LOCATION_ID = hw_station_master.LOCATION_ID
   - Count: COUNT(*) as bin_presentations

6. store_bin_master ACTUAL COLUMNS:
   LOCATION_ID(PK), BIN_ID, PREV_BIN_ID, VELOCITY, COST,
   INSERTED_TIMESTAMP, UPDATED_TIMESTAMP, AUDIT, AUDIT_MARKED_TIMESTAMP

7. bin_info_master ACTUAL COLUMNS:
   BIN_ID(PK), BIN_BARCODE, BIN_TYPE, BIN_SEGMENTS  (only 4 columns!)

8. bot_master ACTUAL COLUMNS (key subset):
   BOT_MASTER_ID(PK), BOT_ID, STATUS, COUNTER, AUTO_MANUAL,
   ACTIVITY_REQUEST, BATTERY, BATTERY_HEALTH, IP, PORT, SIM_PORT,
   GRIDX, GRIDY, GRIDZ, ACTIVE_AXIS, LOAD_CONDITION,
   UPDATED_TIMESTAMP, ALARM, ALARM_TYPE, RECOVERY_BIN_LOAD_STATUS,
   STATION_SAFETY_VALUE, BATTERY_VOLTS, AH_REMAINING_PERCENTAGE,
   AH_REMAINING_NORMAL, RECOVERY_BIT, NON_RECOVERY_BIT,
   LOAD_NON_RECOVERY_BIT, BOT_TO_MAINTENANCE_BIT, CHARGING_BIT,
   BARCODE_TAG_NUMBER, SLIDER_POSITION, LIDAR_ZONE_NUMBER,
   ALARM_TIMESTAMP, ALARM_POSITION_X_Y_Z
   NO: BOT_NAME, BOT_LABEL, BOT_ALIAS, BOT_STATE, WORK_STATE, IS_ONLINE, BOT_MODE

9. TIMESTAMP COLUMNS by table:
   - task_master_log: logged_timestamp, INSERTED_TIMESTAMP, UPDATED_TIMESTAMP
   - wave_master: INSERTED_TIMESTAMP, UPDATED_TIMESTAMP
   - bot_alarm_log: ALARM_DATE
   - live_inventory_master: INSERTED_TIMESTAMP, UPDATED_TIMESTAMP
   - order_bin_mapping: INSERTED_TIMESTAMP, UPDATED_TIMESTAMP
"""


# ══════════════════════════════════════════════════════════════════════════════
# 4. ENUM REGISTRY — DEPRECATED: kept as fallback reference only.
#    Actual enum values are now auto-extracted from Table_information.csv
#    during SchemaRegistry._load_csv() → self.enum_registry.
#    When connecting to a new site, regenerate the CSV and the enum
#    values will be picked up automatically — no manual edits needed.
# ══════════════════════════════════════════════════════════════════════════════

ENUM_REGISTRY: Dict[str, Dict[str, List[str]]] = {
    "bot_master": {
        "STATUS": ["ENABLED", "DISABLED"],
        "AUTO_MANUAL": ["auto", "manual"],  # lowercase in DB!
        "LOAD_CONDITION": ["UL", "LD"],  # UL=Unloaded, LD=Loaded
        "BATTERY_HEALTH": ["GOOD", "AVERAGE", "CRITICAL"],
        "ALARM_TYPE": ["NORMAL", "MAINTENANCE", "PSEUDO"],
    },
    "bot_master_log": {
        "STATUS": ["ENABLED", "DISABLED"],
    },
    "task_master": {
        "STATUS": ["PENDING", "ASSIGNED", "PROCESSING"],
        "TASK_TYPE": [
            "STATION_TO_STATION", "BIN_STORE_TO_ZONE", "ZONE_TO_BIN_STORE",
            "CHARGING", "HOME", "MAINTENANCE", "RECOVERY",
        ],
    },
    "task_master_log": {
        "STATUS": ["PENDING", "ASSIGNED", "PROCESSING", "COMPLETED"],
        "TASK_TYPE": [
            "STATION_TO_STATION", "BIN_STORE_TO_ZONE", "ZONE_TO_BIN_STORE",
            "CHARGING", "HOME", "MAINTENANCE", "RECOVERY",
        ],
    },
    "wave_master": {
        "WAVE_TYPE": [
            "PUT", "PICK", "STOCK_AUDIT", "BIN_LOADING",
            "PUT_STORAGE_REQUEST", "PICK_ORDER_REQUEST",
            "LOCATION_AUDIT", "THROUGHPUT_WAVE",
        ],
        "WAVE_STATUS": [
            "PENDING", "UPLOADED", "STATION_SELECTED",
            "PROCESSING", "COMPLETED", "LEFT_OVER",
        ],
    },
    "hw_station_master": {
        "STATION_TYPE": ["GTP_STATION", "GTC_STATION"],  # NOT 'GTP'/'GTC'!
        "STATUS": ["ENABLED", "DISABLED"],
        "WAVE_STATUS": ["NO_WAVE", "WAITING_OPERATOR", "WAVE_LIVE", "STATION_PAUSE"],
    },
    "hw_ptl_master": {
        "STATUS": ["LPN_OPEN", "LPN_CLOSED", "ENABLED", "DISABLED", "LPN_SCAN"],
    },
    "location_master": {
        "AISLE_NUMBER": [
            "A01", "A02", "A03", "A04", "A05", "A06", "A07", "A08",
            "A09", "A10", "A11", "A12", "A13", "A14", "A15", "A16",
            "A17", "A18", "A19", "A20", "A21", "A22", "A23", "A24",
            "RA01", "RA02", "RA03", "RA04", "RA05", "RA06", "RA07", "RA08",
            "RA09", "RA10", "RA11", "RA12", "RA13", "RA14", "RA15", "RA16",
            "RA17", "RA18", "RA19", "RA20",
            "URA01", "URA02", "URA03", "URA04",
        ],
        "TOWER_NUMBER": [
            "T01", "T02", "T03", "T04", "T05", "T06", "T07", "T08", "T09", "T10",
            "T11", "T12", "T13", "T14", "T15", "T16", "T17", "T18", "T19", "T20",
            "T21", "T22", "T23",
        ],
        "TOWER_SIDE": ["LEFT", "RIGHT"],
    },
    "order_bin_mapping": {
        "TYPE": ["STATION_PICK", "RACK_PICK", "RECOVERY_PICK", "LOCATION_PICK"],  # NOT just 'PICK'!
        "STATUS": [
            "PENDING", "TASK_ALLOCATED", "BIN_PICKED", "ON_STATION",
            "TASK_COMPLETED", "OPERATION_COMPLETED",
            "PRE_ON_STATION", "POST_ON_STATION", "RACK_PENDING",
        ],
    },
    "pick_wave_order_master": {
        "STATUS": [
            "PENDING", "PICK_STARTED", "PICK_COMPLETED",
            "ORDER_COMPLETED", "MID_WAVE_AUDIT_STARTED", "MID_WAVE_AUDIT_COMPLETED",
        ],
    },
    "put_wave_order_master": {
        "STATUS": [
            "PUT_STARTED", "PUT_COMPLETED", "PENDING",
            "INVENTORY_UPDATED", "PUT_SUSPENDED",
        ],
    },
    "bin_info_master": {
        "BIN_TYPE": ["SEGMENT", "VIRTUAL_BIN"],
    },
    "sku_master": {
        "VELOCITY": ["A", "B", "C", "D", "NA"],
    },
    "store_bin_master": {
        "VELOCITY": ["A", "B", "C", "D", "NA"],
    },
    "sku_velocity_state": {
        "VELOCITY": ["A", "B", "C", "D", "NA"],
        "PREV_VELOCITY": ["A", "B", "C", "D", "NA"],
    },
    "stock_audit_wave_order_master": {
        "STATUS": [
            "PENDING", "AUDIT_STARTED", "AUDIT_COMPLETED",
            "AUDIT_SKIPPED", "INVENTORY_UPDATED",
        ],
    },
    "station_no_read_logs": {
        "TYPE": ["FAILREAD", "NOREAD", "BADREAD"],
    },
    "lpn_master": {
        "LPN_STATUS": ["LPN_OPEN", "LPN_CLOSED"],
    },
    "maintenance_task_master": {
        "STATUS": ["PENDING", "IN_PROGRESS", "COMPLETED", "CANCELLED"],
        "PRIORITY": ["LOW", "MEDIUM", "HIGH", "CRITICAL"],
    },
}


# ══════════════════════════════════════════════════════════════════════════════
# 5. SchemaRegistry CLASS
# ══════════════════════════════════════════════════════════════════════════════

class SchemaRegistry:
    """
    Auto-loads Table_information.csv, builds a join graph from
    CORE_RELATIONSHIPS, and provides intelligent schema context
    for any natural-language question.
    """

    def __init__(self, csv_path: str | Path | None = None):
        if csv_path is None:
            csv_path = Path(__file__).resolve().parents[3] / "data" / "database" / "Table_information.csv"
        self.csv_path = Path(csv_path)

        self.tables: Dict[str, Dict[str, Any]] = {}
        self.column_index: Dict[str, Set[str]] = defaultdict(set)
        self.join_graph: Dict[str, Dict[str, Dict]] = defaultdict(dict)
        # Dynamic enum registry — populated from Table_information.csv
        self.enum_registry: Dict[str, Dict[str, List[str]]] = {}

        self._load_csv()
        self._build_join_graph()
        logger.info(
            f"SchemaRegistry: {len(self.tables)} tables, "
            f"{sum(len(v) for v in self.join_graph.values())} edges, "
            f"{sum(len(v) for v in self.enum_registry.values())} enum columns"
        )

    # ── CSV Loading ──────────────────────────────────────────────────────

    def _load_csv(self) -> None:
        if not self.csv_path.exists():
            logger.warning(f"Schema CSV not found: {self.csv_path}")
            return
        with open(self.csv_path, "r", encoding="utf-8-sig") as fh:
            reader = csv.DictReader(fh)
            for row in reader:
                tname = (row.get("Table_name") or "").strip()
                if not tname:
                    continue
                cols_raw = row.get("Table_columns(Data type)", "")
                parsed = self._parse_columns(cols_raw)
                self.tables[tname] = {
                    "description": (row.get("Table_description") or "").strip(),
                    "columns_raw": cols_raw.strip(),
                    "columns_parsed": parsed,
                    "pk": (row.get("Primary_key") or "").strip(),
                    "category": (row.get("Table_category") or "general_table").strip(),
                }
                for col in parsed:
                    self.column_index[col["name"].upper()].add(tname)
                # Extract enum columns and their values from raw column text
                enums = self._extract_enums(cols_raw)
                if enums:
                    self.enum_registry[tname] = enums

    @staticmethod
    def _extract_enums(raw: str) -> Dict[str, List[str]]:
        """Parse enum columns and their values from raw column definition text.

        Example input:
            STATUS(enum('ENABLED','DISABLED')), STATION_TYPE(enum('GTP_STATION','GTC_STATION'))
        Returns:
            {'STATUS': ['ENABLED', 'DISABLED'], 'STATION_TYPE': ['GTP_STATION', 'GTC_STATION']}
        """
        enums: Dict[str, List[str]] = {}
        # Match patterns like: COLUMN_NAME(enum('VAL1','VAL2',...))  
        for m in re.finditer(r"(\w+)\(enum\(([^)]+)\)\)", raw):
            col_name = m.group(1)
            val_str = m.group(2)
            values = [v.strip().strip("'").strip('"') for v in val_str.split(",")]
            values = [v for v in values if v]  # filter empty
            if values:
                enums[col_name] = values
        return enums

    @staticmethod
    def _parse_columns(raw: str) -> List[Dict[str, str]]:
        cols: List[Dict[str, str]] = []
        if not raw:
            return cols
        for token in raw.split(","):
            token = token.strip()
            if not token:
                continue
            m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]+)\)", token)
            if m:
                cols.append({"name": m.group(1), "dtype": m.group(2).strip()})
            else:
                clean = token.strip().split("(")[0].strip()
                if clean and re.match(r"[A-Za-z_]", clean):
                    cols.append({"name": clean, "dtype": "unknown"})
        return cols

    # ── Join Graph ───────────────────────────────────────────────────────

    def _build_join_graph(self) -> None:
        for rel in CORE_RELATIONSHIPS:
            a, b = rel["from"], rel["to"]
            entry = {"join": rel["join"], "note": rel.get("note", "")}
            self.join_graph[a][b] = entry
            self.join_graph[b][a] = {"join": rel["join"], "note": rel.get("note", "")}

    # ── Domain Matching ─────────────────────────────────────────────────

    def find_relevant_domains(self, question: str) -> List[Tuple[str, int]]:
        q = question.lower()
        scored: List[Tuple[str, int]] = []
        for dname, dinfo in TABLE_DOMAINS.items():
            hits = sum(1 for kw in dinfo["keywords"] if kw in q)
            if hits > 0:
                scored.append((dname, hits))
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored

    def get_domain_tables(self, domain_names: List[str]) -> Set[str]:
        tables: Set[str] = set()
        for name in domain_names:
            d = TABLE_DOMAINS.get(name, {})
            tables.update(d.get("primary_tables", []))
            tables.update(d.get("related_tables", []))
        return tables

    # ── Companion Table Logic ────────────────────────────────────────────

    def get_companion_tables(self, selected: Set[str], question: str) -> Set[str]:
        q = question.lower()
        companions: Set[str] = set()

        if any(w in q for w in ["aisle", "tower", "which location", "where is", "rack"]):
            if "store_bin_master" in selected or "live_inventory_master" in selected:
                companions.update(["store_bin_master", "location_master"])

        if any(w in q for w in ["name", "product", "sku name", "which sku", "article name"]):
            if "live_inventory_master" in selected:
                companions.add("sku_master")

        if any(w in q for w in ["expiry", "expiring", "expire", "expiration", "shelf life"]):
            companions.add("sku_batch_master")
            companions.add("live_inventory_master")

        if "velocity" in q:
            companions.add("sku_master")

        if any(w in q for w in ["barcode", "bin barcode", "bin details"]):
            companions.add("bin_info_master")

        if "station" in q and "task_master_log" in selected:
            companions.add("hw_station_master")

        if "bot" in q and "task_master_log" in selected:
            companions.add("bot_master")

        return companions - selected

    # ── Join Path Finder ────────────────────────────────────────────────

    def get_direct_join(self, table_a: str, table_b: str) -> Optional[Dict[str, str]]:
        return self.join_graph.get(table_a, {}).get(table_b)

    def get_joins_for_tables(self, tables: List[str]) -> List[Dict[str, str]]:
        tset = set(tables)
        seen: Set[Tuple[str, str]] = set()
        joins: List[Dict[str, str]] = []
        for a in tables:
            for b, info in self.join_graph.get(a, {}).items():
                if b in tset:
                    key = tuple(sorted([a, b]))
                    if key not in seen:
                        seen.add(key)
                        joins.append({"from": a, "to": b, "join": info["join"], "note": info.get("note", "")})
        return joins

    def find_join_path(self, source: str, target: str, max_depth: int = 4) -> Optional[List[Dict]]:
        if source == target:
            return []
        if source not in self.join_graph:
            return None
        if target in self.join_graph.get(source, {}):
            info = self.join_graph[source][target]
            return [{"from": source, "to": target, **info}]
        visited = {source}
        queue: deque = deque()
        queue.append((source, []))
        while queue:
            current, path = queue.popleft()
            if len(path) >= max_depth:
                continue
            for neighbor, info in self.join_graph.get(current, {}).items():
                if neighbor in visited:
                    continue
                new_path = path + [{"from": current, "to": neighbor, **info}]
                if neighbor == target:
                    return new_path
                visited.add(neighbor)
                queue.append((neighbor, new_path))
        return None

    # ── Enum & Column Lookup ────────────────────────────────────────────

    def get_enum_values(self, table: str, column: str) -> Optional[List[str]]:
        return self.enum_registry.get(table, {}).get(column)

    def get_relevant_enums(self, tables: List[str]) -> Dict[str, Dict[str, List[str]]]:
        result: Dict[str, Dict[str, List[str]]] = {}
        for t in tables:
            if t in self.enum_registry:
                result[t] = self.enum_registry[t]
        return result

    def get_table_columns(self, table: str) -> List[Dict[str, str]]:
        return self.tables.get(table, {}).get("columns_parsed", [])

    def get_table_description(self, table: str) -> str:
        return self.tables.get(table, {}).get("description", "")

    def get_tables_with_column(self, column_name: str) -> Set[str]:
        return self.column_index.get(column_name.upper(), set())

    def table_exists(self, table_name: str) -> bool:
        return table_name in self.tables

    # ══════════════════════════════════════════════════════════════════════
    # MAIN API — get_schema_context()
    # ══════════════════════════════════════════════════════════════════════

    def get_schema_context(self, question: str, max_tables: int = 12) -> Dict[str, Any]:
        """
        Given a natural-language question, return everything the LLM needs:
            selected_tables, schema_text, relationship_text, enum_text,
            path_text, column_facts, domains_matched
        """
        # 1. Find domains
        domains = self.find_relevant_domains(question)
        domain_names = [d[0] for d in domains[:4]]

        # 2. Collect tables from domains
        tables: Set[str] = set()
        for i, dname in enumerate(domain_names):
            d = TABLE_DOMAINS.get(dname, {})
            tables.update(d.get("primary_tables", []))
            if i < 2:  # related only for top 2
                tables.update(d.get("related_tables", []))

        # 3. Add companion tables
        companions = self.get_companion_tables(tables, question)
        tables.update(companions)

        # 4. Fallback if no domain matched
        if not tables:
            tables = self._fallback_table_selection(question)

        # 5. Order: primaries first, then rest
        primary: Set[str] = set()
        for dname in domain_names:
            primary.update(TABLE_DOMAINS.get(dname, {}).get("primary_tables", []))
        primary.update(companions)

        ordered: List[str] = []
        for t in primary:
            if t in tables and t not in ordered:
                ordered.append(t)
        for t in tables:
            if t not in ordered:
                ordered.append(t)
        selected = ordered[:max_tables]

        # 6. Schema text
        schema_lines: List[str] = []
        for t in selected:
            info = self.tables.get(t, {})
            if info:
                schema_lines.append(
                    f"TABLE: {t}\n"
                    f"DESCRIPTION: {info.get('description', '')}\n"
                    f"COLUMNS: {info.get('columns_raw', '')}\n"
                    f"PRIMARY KEY: {info.get('pk', '')}"
                )
        schema_text = "\n---\n".join(schema_lines)

        # 7. Relationship text
        joins = self.get_joins_for_tables(selected)
        rel_lines: List[str] = []
        if joins:
            rel_lines.append("TABLE RELATIONSHIPS (use for JOINs):")
            for j in joins:
                rel_lines.append(f"  {j['from']} → {j['to']}")
                rel_lines.append(f"    JOIN ON: {j['join']}")
                if j.get("note"):
                    rel_lines.append(f"    NOTE: {j['note']}")
        relationship_text = "\n".join(rel_lines)

        # 8. Enum text
        enums = self.get_relevant_enums(selected)
        enum_lines: List[str] = []
        if enums:
            enum_lines.append("ENUM/VALID VALUES (use these exact strings in WHERE):")
            for tbl, cols in enums.items():
                for col, vals in cols.items():
                    enum_lines.append(f"  {tbl}.{col}: {', '.join(vals)}")
        enum_text = "\n".join(enum_lines)

        # 9. Multi-hop join paths
        path_lines: List[str] = []
        for i, t1 in enumerate(selected):
            for t2 in selected[i + 1:]:
                if not self.get_direct_join(t1, t2):
                    path = self.find_join_path(t1, t2)
                    if path and len(path) > 1:
                        hops = " → ".join(s["from"] for s in path) + f" → {path[-1]['to']}"
                        path_lines.append(f"  {t1} ↔ {t2}: {hops}")
        path_text = ""
        if path_lines:
            path_text = "MULTI-HOP JOIN PATHS:\n" + "\n".join(path_lines)

        return {
            "selected_tables": selected,
            "schema_text": schema_text,
            "relationship_text": relationship_text,
            "enum_text": enum_text,
            "path_text": path_text,
            "column_facts": COLUMN_FACTS,
            "domains_matched": domain_names,
        }

    def _fallback_table_selection(self, question: str) -> Set[str]:
        q = question.upper()
        candidates: Set[str] = set()
        for col_name, tbl_set in self.column_index.items():
            if len(col_name) >= 4 and col_name in q:
                candidates.update(tbl_set)
        return set(list(candidates)[:8])

    def build_prompt_section(self, question: str) -> str:
        """Single string block for LLM prompt injection."""
        ctx = self.get_schema_context(question)
        parts: List[str] = []
        parts.append("=" * 80)
        parts.append("SCHEMA CONTEXT")
        parts.append("=" * 80)
        parts.append(ctx["schema_text"])
        if ctx["relationship_text"]:
            parts.append("")
            parts.append(ctx["relationship_text"])
        if ctx["enum_text"]:
            parts.append("")
            parts.append(ctx["enum_text"])
        if ctx["path_text"]:
            parts.append("")
            parts.append(ctx["path_text"])
        parts.append("")
        parts.append(ctx["column_facts"])
        return "\n".join(parts)


# ══════════════════════════════════════════════════════════════════════════════
# MODULE-LEVEL CONVENIENCE FUNCTIONS (backward-compatible)
# ══════════════════════════════════════════════════════════════════════════════

_registry: Optional[SchemaRegistry] = None


def _get_registry() -> SchemaRegistry:
    global _registry
    if _registry is None:
        _registry = SchemaRegistry()
    return _registry


def find_relevant_domains(question: str) -> List[str]:
    return [d[0] for d in _get_registry().find_relevant_domains(question)]


def get_tables_for_domains(domain_names: List[str]) -> Set[str]:
    return _get_registry().get_domain_tables(domain_names)


def get_join_path(table_a: str, table_b: str) -> Optional[Dict]:
    return _get_registry().get_direct_join(table_a, table_b)


def get_all_joins_for_tables(table_names: List[str]) -> List[Dict]:
    return _get_registry().get_joins_for_tables(table_names)


def build_relationship_context(table_names: List[str]) -> str:
    joins = _get_registry().get_joins_for_tables(table_names)
    if not joins:
        return ""
    lines = ["\nTABLE RELATIONSHIPS (use for JOINs):"]
    for j in joins:
        lines.append(f"  {j['from']} → {j['to']}")
        lines.append(f"    JOIN ON: {j['join']}")
        if j.get("note"):
            lines.append(f"    NOTE: {j['note']}")
    return "\n".join(lines)


def get_required_companion_tables(selected_tables: Set[str], question: str) -> Set[str]:
    return _get_registry().get_companion_tables(selected_tables, question)
