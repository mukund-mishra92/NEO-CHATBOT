import re
import sys
from typing import List
from pathlib import Path

# Ensure project root (where `data/` lives) is on sys.path
PROJECT_ROOT = Path(__file__).resolve().parents[5]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from data.database.schema_graph_loader import SchemaGraph


class SQLJoinInjector:
    def inject(
        self,
        base_sql: str,
        join_path: List[str],
        schema_graph: SchemaGraph
    ) -> str:
        """
        Inject JOIN clauses into base SQL using schema graph
        """

        from_match = re.search(r"\bFROM\s+(\w+)", base_sql, re.IGNORECASE)
        if not from_match:
            return base_sql

        base_table = from_match.group(1)
        sql = base_sql

        for i in range(len(join_path) - 1):
            left = join_path[i]
            right = join_path[i + 1]

            fk = schema_graph.get_fk(left, right)
            if not fk:
                continue

            join_clause = (
                f" JOIN {right} "
                f"ON {left}.{fk['child']} = {right}.{fk['parent']} "
            )

            sql = sql.replace(
                f"FROM {left}",
                f"FROM {left}{join_clause}",
                1
            )

        return sql
