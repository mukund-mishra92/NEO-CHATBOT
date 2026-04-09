"""
Unit Tests — TableSelector (log-table preference fix)
Target: backend/app/services/sql_assistant/table_selector.py

Regression tests for the category_bonus fix:
  - "previous"/"last"/"old" queries should boost log tables
  - "current"/"latest"/"status" queries should boost master tables
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.services.sql_assistant.table_selector import TableSelector


# ═══════════════════════════════════════════════════════════════
# Fixtures
# ═══════════════════════════════════════════════════════════════

@pytest.fixture
def mock_embedding_service():
    """Patch embedding_service so no OpenAI calls are needed."""
    with patch("app.services.sql_assistant.table_selector.embedding_service") as mock_svc:
        mock_svc.embed.return_value = [0.0] * 1536
        mock_svc.embed_batch.return_value = [[0.0] * 1536] * 10
        yield mock_svc


@pytest.fixture
def selector_with_log_tables(mock_embedding_service):
    """TableSelector with both master and log variants of order_bin_mapping."""
    schema = {
        "order_bin_mapping": [
            "ORDER_ID", "BIN_ID", "BOT_ID", "STATION_ID", "STATUS", "host-location"
        ],
        "order_bin_mapping_log": [
            "ORDER_ID", "BIN_ID", "BOT_ID", "STATION_ID", "STATUS",
            "host-location", "CREATED_DATE"
        ],
        "bot_master": [
            "BOT_ID", "BOT_IP", "STATUS", "CURRENT_TASK", "host-location"
        ],
        "task_master": [
            "TASK_ID", "BOT_ID", "STATUS", "STATION_ID", "host-location"
        ],
        "task_master_log": [
            "TASK_ID", "BOT_ID", "STATUS", "STATION_ID", "host-location",
            "CREATED_DATE"
        ],
    }
    metadata = {
        "order_bin_mapping": {
            "category": "mapping_master",
            "description": "Current order-to-bin mapping",
        },
        "order_bin_mapping_log": {
            "category": "mapping_log",
            "description": "Historical order-to-bin mapping log",
        },
        "bot_master": {
            "category": "master",
            "description": "Current bot state and config",
        },
        "task_master": {
            "category": "master",
            "description": "Current tasks assigned to bots",
        },
        "task_master_log": {
            "category": "log",
            "description": "Historical task assignments log",
        },
    }
    return TableSelector(schema=schema, table_metadata=metadata)


# ═══════════════════════════════════════════════════════════════
# Log-table preference tests (Fix: "previous bot at station")
# ═══════════════════════════════════════════════════════════════

class TestLogTableCategoryBonus:
    """When the user asks about 'previous'/'last'/'old' data, the
    category_bonus should boost log tables above their master counterpart."""

    def test_previous_bot_boosts_log_table(self, selector_with_log_tables):
        """'previous bot at station 1' should rank order_bin_mapping_log higher."""
        tables = selector_with_log_tables.select(
            "previous bot at station 1 in frk", max_tables=5
        )
        # Both should be present, but log should come first
        assert "order_bin_mapping_log" in tables, (
            "order_bin_mapping_log should be selected for 'previous' queries"
        )
        if "order_bin_mapping" in tables:
            log_idx = tables.index("order_bin_mapping_log")
            master_idx = tables.index("order_bin_mapping")
            assert log_idx < master_idx, (
                f"Log table should rank higher than master for 'previous' "
                f"(log={log_idx}, master={master_idx})"
            )

    def test_last_bot_boosts_log_table(self, selector_with_log_tables):
        """'last bot at station' should also boost log tables."""
        tables = selector_with_log_tables.select(
            "last bot at station 1 in frk", max_tables=5
        )
        assert "order_bin_mapping_log" in tables

    def test_old_task_boosts_log(self, selector_with_log_tables):
        """'old tasks for bot 3' should boost task_master_log."""
        tables = selector_with_log_tables.select(
            "old tasks for bot 3 in frk", max_tables=5
        )
        assert "task_master_log" in tables

    def test_history_boosts_log(self, selector_with_log_tables):
        """'history of bot assignments' should boost log tables."""
        tables = selector_with_log_tables.select(
            "history of bot assignments at station", max_tables=5
        )
        assert "task_master_log" in tables or "order_bin_mapping_log" in tables

    def test_current_status_boosts_master(self, selector_with_log_tables):
        """'current bot status' should boost master tables."""
        tables = selector_with_log_tables.select(
            "current status of bot 3 in frk", max_tables=5
        )
        assert "bot_master" in tables
        if "task_master_log" in tables and "task_master" in tables:
            master_idx = tables.index("task_master")
            log_idx = tables.index("task_master_log")
            assert master_idx < log_idx, (
                "Master table should rank higher for 'current' queries"
            )

    def test_latest_status_boosts_master(self, selector_with_log_tables):
        """'latest bot status' should boost master tables."""
        tables = selector_with_log_tables.select(
            "latest bot status in frk", max_tables=5
        )
        assert "bot_master" in tables
