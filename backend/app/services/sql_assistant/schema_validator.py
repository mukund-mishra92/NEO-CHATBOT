import re
from typing import Dict, List


class SchemaValidationError(Exception):
    pass


class SchemaValidator:
    """
    Ensures SQL uses only real tables and columns.
    """

    def __init__(self, schema: Dict[str, List[str]]):
        """
        schema:
            {
                "table_name": ["col1", "col2", ...]
            }
        """
        self.schema = schema

    def _extract_tables(self, sql: str) -> List[str]:
        tables = re.findall(r"(?:from|join)\s+`?(\w+)`?", sql, re.IGNORECASE)
        return list(set(tables))

    def validate(self, sql: str):
        tables = self._extract_tables(sql)

        for table in tables:
            if table not in self.schema:
                raise SchemaValidationError(f"Invalid table: {table}")

        # Column validation (simple approach)
        for table in tables:
            columns = self.schema.get(table, [])
            if not columns:
                continue

            for col in re.findall(rf"{table}\.(\w+)", sql):
                if col not in columns:
                    raise SchemaValidationError(
                        f"Invalid column '{col}' in table '{table}'"
                    )
