from difflib import get_close_matches
from typing import Dict, List, Optional


class ColumnResolver:
    """
    Suggests closest column name when mismatch occurs.
    """

    def __init__(self, schema: Dict[str, List[str]]):
        self.schema = schema

    def resolve(self, table: str, column: str) -> Optional[str]:
        columns = self.schema.get(table, [])
        matches = get_close_matches(column, columns, n=1, cutoff=0.6)
        return matches[0] if matches else None
